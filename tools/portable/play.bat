@echo off
rem Noise Floor, portable copy: double-click to play. Made by tools/make_portable.sh (no git or GitHub needed).
rem The first time on a PC it brings the saved games that came with it across (only if that PC has none yet).
cd /d "%~dp0"
set "GODOT=%~dp0godot\Godot_v4.7-stable_win64.exe"
set "SAVES=%APPDATA%\Godot\app_userdata\Noise Floor"
if not exist "%GODOT%" (
	echo Can't find the game's Godot at %GODOT%
	echo Keep the godot folder next to this file.
	pause
	exit /b 1
)
if not exist "%SAVES%\save.json" if not exist "%SAVES%\saves\" if exist "saves\" (
	echo Bringing the saved games across...
	mkdir "%SAVES%" 2>nul
	xcopy "saves" "%SAVES%" /e /i /y /q >nul
)
echo Starting Noise Floor...
"%GODOT%" --headless --path game --import >nul 2>&1
start "" "%GODOT%" --path game
