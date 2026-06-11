@echo off
cd /d "%~dp0"
if not exist "%~dp0..\utils\alt11-service-args.txt" exit /b 1
for /f "usebackq delims=" %%A in ("%~dp0..\utils\alt11-service-args.txt") do (
  "%~dp0winws.exe" %%A
)
exit /b %ERRORLEVEL%
