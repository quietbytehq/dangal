; Neon Knuckle Windows installer (built in CI with makensis on Linux)
; makensis -DVERSION=0.3.0 -DSRC=build/windows -DOUT=NeonKnuckle-Setup.exe packaging/installer.nsi
Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel admin
!include "MUI2.nsh"

!define APP "Neon Knuckle"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\NeonKnuckle"

Name "${APP} ${VERSION}"
OutFile "${OUT}"
InstallDir "$PROGRAMFILES64\${APP}"
InstallDirRegKey HKLM "${REGKEY}" "InstallLocation"
!define MUI_ICON "neon-knuckle.ico"
!define MUI_UNICON "neon-knuckle.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\NeonKnuckle.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play Neon Knuckle now"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${SRC}\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SRC}\*.*"
  File "neon-knuckle.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\NeonKnuckle.exe" "" "$INSTDIR\neon-knuckle.ico"
  CreateShortcut "$SMPROGRAMS\${APP}\Uninstall ${APP}.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\NeonKnuckle.exe" "" "$INSTDIR\neon-knuckle.ico"
  WriteRegStr HKLM "${REGKEY}" "DisplayName" "${APP}"
  WriteRegStr HKLM "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${REGKEY}" "Publisher" "QuietByte"
  WriteRegStr HKLM "${REGKEY}" "DisplayIcon" "$INSTDIR\neon-knuckle.ico"
  WriteRegStr HKLM "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${REGKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${REGKEY}" "URLInfoAbout" "https://github.com/quietbytehq/neon-knuckle"
  WriteRegDWORD HKLM "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${REGKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP}.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${REGKEY}"
SectionEnd
