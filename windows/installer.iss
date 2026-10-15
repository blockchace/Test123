[Setup]
AppId={{2BEE348D-2B04-4DF4-82A5-0C209C185214}
AppName=ChaceRecordings
AppVersion=2.0.0
DefaultDirName={localappdata}\Programs\ChaceRecordings
DefaultGroupName=ChaceRecordings
OutputDir=..\dist
OutputBaseFilename=ChaceRecordings-Windows11-Setup-x64
SetupIconFile=ChaceRecordings\app.ico
UninstallDisplayIcon={app}\ChaceRecordings.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Files]
Source: "..\dist\windows\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ChaceRecordings"; Filename: "{app}\ChaceRecordings.exe"
Name: "{autodesktop}\ChaceRecordings"; Filename: "{app}\ChaceRecordings.exe"

[Run]
Filename: "{app}\ChaceRecordings.exe"; Description: "Abrir ChaceRecordings"; Flags: nowait postinstall skipifsilent
