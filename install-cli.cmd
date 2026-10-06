@echo off
rem Install the newest knwlge developer CLI release on Windows, from Command Prompt:
rem
rem   curl -fsSL https://raw.githubusercontent.com/Replient/knwlge-releases/main/install-cli.cmd -o install-cli.cmd && install-cli.cmd && del install-cli.cmd
rem
rem Downloads install-cli.ps1 from the same place and runs it with Windows PowerShell; that script does the work
rem (newest cli-v release, SHA-256 check, npm install -g) and documents KNWLGE_CLI_VERSION. In PowerShell itself, use
rem the one-line command at the top of install-cli.ps1 instead.
rem
rem No labels and no goto, and CRLF line endings (.gitattributes): cmd.exe misreads both in a file with bare LF.
setlocal
set "KNWLGE_INSTALL_SCRIPT=%TEMP%\knwlge-install-cli-%RANDOM%%RANDOM%.ps1"
curl.exe -fsSL "https://raw.githubusercontent.com/Replient/knwlge-releases/main/install-cli.ps1" -o "%KNWLGE_INSTALL_SCRIPT%"
if errorlevel 1 (
  echo install-cli: install-cli.ps1 could not be downloaded from Replient/knwlge-releases. 1>&2
  exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%KNWLGE_INSTALL_SCRIPT%"
set "KNWLGE_INSTALL_EXIT=%ERRORLEVEL%"
del "%KNWLGE_INSTALL_SCRIPT%" >nul 2>&1
exit /b %KNWLGE_INSTALL_EXIT%
