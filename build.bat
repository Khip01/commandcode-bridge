@echo off
cd /d "%~dp0"
echo Getting dependencies...
call dart pub get
echo Compiling...
call dart compile exe bin\commandcode_bridge.dart -o bin\commandcode_bridge.exe
echo Done! Binary at bin\commandcode_bridge.exe
