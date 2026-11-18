# Builds TDLib for Windows into windows/tdlib/windows-<arch>/tdjson.dll.
#
#   powershell -ExecutionPolicy Bypass -File tool/build_tdlib_windows.ps1 [-Arch x64|arm64]
#
# handy_tdlib ships TDLib for Android only. This builds the same TDLib commit
# from source as one tdjson.dll with OpenSSL linked in. It runs on Windows
# with Visual Studio 2022 (Desktop development with C++), Git, CMake and
# Strawberry Perl; zlib and gperf come from vcpkg, cloned at a fixed tag.
# It takes a while. Run it again after changing TdCommit or OpenSslVersion.
param(
  [ValidateSet('x64', 'arm64')]
  [string] $Arch = 'x64'
)
$ErrorActionPreference = 'Stop'

# The commit handy_tdlib's Dart API was generated from (TDLib 1.8.36). Keep
# the two in step: a different TDLib can send objects the Dart side cannot
# parse, or reject requests it builds.
$TdCommit = '87d881071fe514936bb17029e96761141287d2be'

$OpenSslVersion = '3.5.9'
$OpenSslSha256 = '603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a'

$VcpkgTag = '2026.10.16'

$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root "build\tdlib-windows-$Arch"
$Out = Join-Path $Root "windows\tdlib\windows-$Arch"

foreach ($tool in 'git', 'cmake', 'perl') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is required" }
}

function Invoke-Checked {
  param([string] $Command, [string[]] $Arguments)
  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Command $($Arguments -join ' ') failed with $LASTEXITCODE" }
}

# The compiler and nmake, for the architecture being built.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio 2022 with the C++ tools is required' }
Import-Module (Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments "-arch=$Arch -host_arch=x64" | Out-Null

New-Item -ItemType Directory -Force $Work | Out-Null
Set-Location $Work

# Sources.
if (-not (Test-Path td)) { Invoke-Checked git @('clone', 'https://github.com/tdlib/td.git', 'td') }
& git -C td cat-file -e "$TdCommit^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { Invoke-Checked git @('-C', 'td', 'fetch', 'origin') }
Invoke-Checked git @('-C', 'td', 'checkout', '-q', $TdCommit)

if (-not (Test-Path vcpkg)) {
  Invoke-Checked git @('clone', '--branch', $VcpkgTag, '--depth', '1', 'https://github.com/microsoft/vcpkg.git', 'vcpkg')
}
if (-not (Test-Path vcpkg\vcpkg.exe)) { Invoke-Checked vcpkg\bootstrap-vcpkg.bat @('-disableMetrics') }

# zlib for TDLib, static with the shared C runtime the app uses; gperf runs
# on this machine while TDLib's sources are generated.
$Triplet = "$Arch-windows-static-md"
Invoke-Checked vcpkg\vcpkg.exe @('install', "zlib:$Triplet", 'gperf:x64-windows')
$env:PATH = "$Work\vcpkg\installed\x64-windows\tools\gperf;$env:PATH"

$OpenSslTar = "openssl-$OpenSslVersion.tar.gz"
if (-not (Test-Path $OpenSslTar)) {
  Invoke-WebRequest -Uri "https://github.com/openssl/openssl/releases/download/openssl-$OpenSslVersion/$OpenSslTar" -OutFile "$OpenSslTar.part"
  Move-Item "$OpenSslTar.part" $OpenSslTar
}
if ((Get-FileHash $OpenSslTar -Algorithm SHA256).Hash.ToLower() -ne $OpenSslSha256) {
  throw "$OpenSslTar doesn't match its checksum"
}

# OpenSSL, static, to link into tdjson.dll.
$Ssl = Join-Path $Work "openssl-$Arch"
if (-not (Test-Path "$Ssl\lib\libcrypto.lib")) {
  $Src = Join-Path $Work "openssl-src-$Arch"
  if (Test-Path $Src) { Remove-Item -Recurse -Force $Src }
  New-Item -ItemType Directory $Src | Out-Null
  Invoke-Checked tar @('xzf', $OpenSslTar, '-C', $Src, '--strip-components', '1')
  Push-Location $Src
  $Target = if ($Arch -eq 'x64') { 'VC-WIN64A' } else { 'VC-WIN64-ARM' }
  Invoke-Checked perl @('Configure', $Target, 'no-shared', 'no-tests', 'no-apps', 'no-docs',
    'no-engine', 'no-async', 'no-asm', "--prefix=$Ssl", "--openssldir=$Ssl\ssl")
  Invoke-Checked nmake @('build_libs')
  Invoke-Checked nmake @('install_dev')
  Pop-Location
}

$CmakeArch = if ($Arch -eq 'x64') { 'x64' } else { 'ARM64' }
Invoke-Checked cmake @('-S', 'td', '-B', "td-$Arch", '-A', $CmakeArch,
  "-DCMAKE_TOOLCHAIN_FILE=$Work\vcpkg\scripts\buildsystems\vcpkg.cmake",
  "-DVCPKG_TARGET_TRIPLET=$Triplet",
  '-DCMAKE_POLICY_VERSION_MINIMUM=3.5',
  '-DOPENSSL_FOUND=1',
  "-DOPENSSL_INCLUDE_DIR=$Ssl\include",
  "-DOPENSSL_CRYPTO_LIBRARY=$Ssl\lib\libcrypto.lib",
  "-DOPENSSL_SSL_LIBRARY=$Ssl\lib\libssl.lib",
  "-DOPENSSL_LIBRARIES=$Ssl\lib\libssl.lib;$Ssl\lib\libcrypto.lib;crypt32;ws2_32;user32;advapi32")
Invoke-Checked cmake @('--build', "td-$Arch", '--target', 'tdjson', '--config', 'Release')

New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item "td-$Arch\Release\tdjson.dll" (Join-Path $Out 'tdjson.dll') -Force

# The DLL must need nothing but Windows and the C runtime the app ships with.
$Deps = (& dumpbin /dependents (Join-Path $Out 'tdjson.dll')) -match '\.dll' | ForEach-Object { $_.Trim() }
$Foreign = $Deps | Where-Object { $_ -match 'libssl|libcrypto|zlib' }
if ($Foreign) { throw "tdjson.dll needs $($Foreign -join ', ')" }
$Deps
Write-Host "Built $Out\tdjson.dll"
