; Inno Setup 6 script for the Windows release.
; Build the EXE first with build_windows.bat, then compile this file.

#ifndef MyAppVersion
  #define MyAppVersion "2.0.0"
#endif
#ifndef MyAppFullVersion
  #define MyAppFullVersion "2.0.0-dev.6"
#endif

#define MyAppName "Crazy Legs Mundell Rampage"
#define MyAppPublisher "Hickston Inc."
#define MyAppExeName "CrazyLegsMundellRampage.exe"

[Setup]
AppId={{7F4C3A62-9E21-4C0B-9A55-6C0C1F8E2D71}
AppName={#MyAppName}
AppVersion={#MyAppFullVersion}
AppVerName={#MyAppName} {#MyAppFullVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Crazy Legs Mundell Rampage
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=CrazyLegsMundellRampage_Setup
SetupIconFile=assets\art\hickston.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
VersionInfoVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "dist\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "CHANGES_2.0.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
