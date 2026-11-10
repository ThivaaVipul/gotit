; Gotit's Windows installer (Inno Setup 6).
;
; Build after `flutter build windows --release` in app/:
;   ISCC.exe /DAppVersion=0.1.0 installer\gotit.iss
; It writes dist\gotit-<version>-setup.exe.
;
; Per user, no admin: installs to %LOCALAPPDATA%\Programs\Gotit. The app
; updates itself by running a newer setup with /VERYSILENT; the [Run] entry
; then starts Gotit again (postinstall entries run in silent mode too).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change the AppId: Windows uses it to recognise Gotit across versions.
AppId={{223B26BB-1C7B-452B-B244-210CBDA3F95A}
AppName=Gotit
AppVersion={#AppVersion}
AppVerName=Gotit {#AppVersion}
AppPublisher=Gotit
AppPublisherURL=https://github.com/ThivaaVipul/gotit
AppSupportURL=https://github.com/ThivaaVipul/gotit/issues
AppUpdatesURL=https://github.com/ThivaaVipul/gotit/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Gotit
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=gotit-{#AppVersion}-setup
SetupIconFile=..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\gotit.exe
UninstallDisplayName=Gotit
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Close a running Gotit before replacing its files.
CloseApplications=force
RestartApplications=no

[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; The AppUserModelID lets Gotit's notifications show under its own name.
Name: "{autoprograms}\Gotit"; Filename: "{app}\gotit.exe"; AppUserModelID: "app.gotit"

[Registry]
; Gotit adds itself to the per-user Run key when "Start with Windows" is on.
; This entry creates nothing; it only removes that value on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "Gotit"; Flags: uninsdeletevalue

[Run]
; A self-update passes /RUNARGS=--hidden when Gotit was in the tray, so the new
; version starts there too instead of opening its window.
Filename: "{app}\gotit.exe"; Parameters: "{param:RUNARGS|}"; Description: "Open Gotit"; Flags: nowait postinstall
