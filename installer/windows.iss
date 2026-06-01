; Inno Setup script for packaging the Flutter Windows release build.
; Build output expected at build/windows/x64/runner/Release

#define MyAppName "Kash Cube"
#define MyAppPublisher "Kash Cube"
#ifndef MyAppVersion
	#define MyAppVersion "1.1.0"
#endif
#define MyAppExeName "kash_cube.exe"

[Setup]
; Important: keep `AppId` constant across releases so Inno Setup
; recognizes this as an upgrade of the same application.
AppId={{B3D91B6F-DB53-4F45-B375-FD6D0A2A2B3D}}
AppName={#MyAppName}
AppVerName={#MyAppName} {#MyAppVersion}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Install application binaries into Program Files; user data is stored
; separately under Local AppData so it survives upgrades and uninstall.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=dist
OutputBaseFilename=KashCube-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UsePreviousAppDir=yes
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Dirs]
; Create a per-user data directory under Local AppData and mark it so
; the uninstaller will not remove it. This preserves user data (database,
; settings) across upgrades and even if the app is uninstalled.
Name: "{localappdata}\{#MyAppName}\data"; Flags: uninsneveruninstall

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
