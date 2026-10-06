@echo off
rem The knwlge launcher of the Chocolatey package: runs the release unpacked beside it with the Node.js on PATH.
node "%~dp0package\dist\index.js" %*
if %ERRORLEVEL% neq 9009 exit /b %ERRORLEVEL%
echo knwlge needs Node.js 22 or newer on PATH. Install it, open a new terminal and run knwlge again. 1>&2
exit /b 9009
