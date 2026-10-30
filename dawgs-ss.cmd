@echo off
setlocal
set "SOURCE_URL=https://raw.githubusercontent.com/NotADawg/DawgsSSTool/main/DawgsSSTool.ps1"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -Command "$scriptText = Invoke-RestMethod -Uri '%SOURCE_URL%'; & ([scriptblock]::Create($scriptText)) %*"
exit /b %ERRORLEVEL%
