@echo off
cd /d "%~dp0"
if not exist "bin\commandcode_bridge.exe" (
    echo Binary not found. Building first...
    call build.bat
)
bin\commandcode_bridge.exe %*
