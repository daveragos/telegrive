; The Windows installer, built by tool/build_windows.ps1 with Inno Setup 6:
;
;   ISCC /DAppVersion=1.0.0 /DArch=x64 /DBuildDir=... /O... windows\installer\telegrive.iss
;
; It installs for the person running it, under their own Programs folder,
; so it asks for no administrator. A running Telegrive is closed first and
; started again after. Uninstalling leaves the drive's index and settings in
; the app's data folder, as a reinstall finds them, and takes away the
; entry that opens Telegrive at login.

#ifndef AppVersion
  #error Pass /DAppVersion=<version>
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef BuildDir
  #error Pass /DBuildDir=<the Release folder flutter build windows made>
#endif

[Setup]
; The same for every version, so each installs over the one before.
AppId={{2893AEEF-8064-49C0-A6EB-1B1D91216832}
AppName=Telegrive
AppVersion={#AppVersion}
AppPublisher=Dawit
AppPublisherURL=https://daveragos.github.io/telegrive/
AppSupportURL=https://github.com/daveragos/telegrive/issues
AppCopyright=Copyright (C) 2026 Dawit. Free software under the GNU GPL, version 3.
DefaultDirName={localappdata}\Programs\Telegrive
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Telegrive.exe
CloseApplications=yes
RestartApplications=yes
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputBaseFilename=telegrive-{#AppVersion}-windows-{#Arch}-setup

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Telegrive"; Filename: "{app}\Telegrive.exe"
Name: "{autodesktop}\Telegrive"; Filename: "{app}\Telegrive.exe"; Tasks: desktopicon

[Registry]
; Written by Open at login in Settings; nothing is written here.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Telegrive"; ValueType: none; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\Telegrive.exe"; Description: "{cm:LaunchProgram,Telegrive}"; Flags: nowait postinstall skipifsilent
