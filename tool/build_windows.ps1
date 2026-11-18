# Builds Telegrive for Windows into build\windows-release:
#
#   telegrive-<version>-windows-<arch>.zip          the app's folder, to unpack anywhere
#   telegrive-<version>-windows-<arch>-setup.exe    an installer for the person running it
#
#   powershell -ExecutionPolicy Bypass -File tool/build_windows.ps1 [-Arch x64|arm64] [flutter build arguments…]
#
# It runs on Windows, for the machine's own architecture, with Flutter,
# Visual Studio 2022 (Desktop development with C++) and Inno Setup 6, and
# needs TDLib for the architecture (tool/build_tdlib_windows.ps1). mpv's
# libraries come with media_kit as the app builds. Extra arguments go to
# flutter build, for example --dart-define-from-file=telegram_api.json.
param(
  [ValidateSet('x64', 'arm64')]
  [string] $Arch = 'x64',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs = @()
)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Host64 = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
if ($Arch -ne $Host64) { throw "Flutter builds for this machine's architecture, $Host64; build $Arch on such a machine." }
if (-not (Test-Path "windows\tdlib\windows-$Arch\tdjson.dll")) {
  throw "TDLib for $Arch is missing; run tool/build_tdlib_windows.ps1 -Arch $Arch first"
}
$Iscc = @(
  (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source,
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $Iscc) { throw 'Inno Setup 6 is missing: install it from jrsoftware.org' }

$Release = Join-Path $Root "build\windows\$Arch\runner\Release"
if (Test-Path $Release) { Remove-Item -Recurse -Force $Release }
flutter build windows --release @FlutterArgs
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed' }

foreach ($file in 'Telegrive.exe', 'tdjson.dll', 'flutter_windows.dll', 'data\app.so') {
  if (-not (Test-Path (Join-Path $Release $file))) { throw "$Release doesn't carry $file" }
}
if (-not (Get-ChildItem $Release -Filter 'libmpv*.dll')) { throw "$Release doesn't carry mpv" }

$Version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
$Out = Join-Path $Root 'build\windows-release'
New-Item -ItemType Directory -Force $Out | Out-Null

# The folder, as Telegrive\ in the archive.
$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ("telegrive-" + [guid]::NewGuid())
Copy-Item -Recurse $Release (Join-Path $Stage 'Telegrive')
$Zip = Join-Path $Out "telegrive-$Version-windows-$Arch.zip"
if (Test-Path $Zip) { Remove-Item $Zip }
Compress-Archive -Path (Join-Path $Stage 'Telegrive') -DestinationPath $Zip
Remove-Item -Recurse -Force $Stage

& $Iscc /Q "/DAppVersion=$Version" "/DArch=$Arch" "/DBuildDir=$Release" "/O$Out" 'windows\installer\telegrive.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }

$Sums = Get-ChildItem $Out -Filter "*$Version-windows-$Arch*" | ForEach-Object {
  "$((Get-FileHash -Algorithm SHA256 $_.FullName).Hash.ToLower())  $($_.Name)"
}
$Sums | Set-Content -Encoding ascii (Join-Path $Out "SHA256SUMS-windows-$Arch.txt")
Get-ChildItem $Out
