; Inno Setup 6 script for the Windows release of the Godot build.
;
; Export the game first (see README, "Building the Godot release"):
;   godot --headless --path godot --export-release "Windows Desktop" ^
;         build/windows/CrazyLegsMundellRampage.exe
; then compile this file from the repository root:
;   ISCC /DMyAppFullVersion=2.1.0 installer.iss
;
; The exported EXE carries its own data, so the installer adds only the
; documents, the shortcuts and the uninstaller around that one file.

#ifndef MyAppFullVersion
  #define MyAppFullVersion "2.0.0-dev.9"
#endif
; VersionInfoVersion must be numeric: 2.0.0-dev.9 -> 2.0.0
#ifndef MyAppVersion
  #define MyAppVersion Copy(MyAppFullVersion, 1, Pos("-", MyAppFullVersion + "-") - 1)
#endif

#define MyAppName "Crazy Legs Mundell Rampage"
#define MyAppPublisher "Hickston Inc."
#define MyAppURL "https://treymun.github.io/crazy-legs-mundell-rampage/"
#define MyAppExeName "CrazyLegsMundellRampage.exe"
#define MyAppSource "godot\build\windows"

[Setup]
AppId={{7F4C3A62-9E21-4C0B-9A55-6C0C1F8E2D71}
AppName={#MyAppName}
AppVersion={#MyAppFullVersion}
AppVerName={#MyAppName} {#MyAppFullVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL=https://github.com/treymun/crazy-legs-mundell-rampage/issues
DefaultDirName={autopf}\Crazy Legs Mundell Rampage
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=CrazyLegsMundellRampage_Setup
SetupIconFile=godot\icons\icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; The payload is one large file of art and sound that is already hard to
; squeeze; "max" spends several minutes for almost nothing over "normal".
Compression=lzma2/normal
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
VersionInfoVersion={#MyAppVersion}
VersionInfoProductName={#MyAppName}
VersionInfoCompany={#MyAppPublisher}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyAppSource}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "CHANGES_2.0.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Read Me"; Filename: "{app}\README.md"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
