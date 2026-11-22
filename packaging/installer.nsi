; Dangal Windows installer (built in CI with makensis on Linux)
; makensis -DVERSION=0.3.0 -DSRC=build/windows -DOUT=Dangal-Setup.exe packaging/installer.nsi
Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel admin
!include "MUI2.nsh"

!define APP "Dangal"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Dangal"

Name "${APP} ${VERSION}"
OutFile "${OUT}"
InstallDir "$PROGRAMFILES64\${APP}"
InstallDirRegKey HKLM "${REGKEY}" "InstallLocation"
!define MUI_ICON "dangal.ico"
!define MUI_UNICON "dangal.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Dangal.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play Dangal now"

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
  File "dangal.ico"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateDirectory "$SMPROGRAMS\${APP}"
  CreateShortcut "$SMPROGRAMS\${APP}\${APP}.lnk" "$INSTDIR\Dangal.exe" "" "$INSTDIR\dangal.ico"
  CreateShortcut "$SMPROGRAMS\${APP}\Uninstall ${APP}.lnk" "$INSTDIR\Uninstall.exe"
  CreateShortcut "$DESKTOP\${APP}.lnk" "$INSTDIR\Dangal.exe" "" "$INSTDIR\dangal.ico"
  WriteRegStr HKLM "${REGKEY}" "DisplayName" "${APP}"
  WriteRegStr HKLM "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${REGKEY}" "Publisher" "QuietByte"
  WriteRegStr HKLM "${REGKEY}" "DisplayIcon" "$INSTDIR\dangal.ico"
  WriteRegStr HKLM "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${REGKEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "${REGKEY}" "URLInfoAbout" "https://github.com/quietbytehq/dangal"
  WriteRegDWORD HKLM "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${REGKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$DESKTOP\${APP}.lnk"
  RMDir /r "$SMPROGRAMS\${APP}"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKLM "${REGKEY}"
SectionEnd
