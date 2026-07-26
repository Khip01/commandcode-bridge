@echo off
cd /d "%~dp0"
if not exist "bin\commandcode_bridge.exe" (
    echo Binary not found. Building first...
    call build.bat
)
if /i "%1" == "server" (
    bin\commandcode_bridge.exe run --server
) else (
    bin\commandcode_bridge.exe run %*
)
