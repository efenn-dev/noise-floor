@echo off
rem Double-click to play Noise Floor on Windows.
rem Refreshes Godot's list of game scripts first (needed after a git pull adds new ones), then starts the game.
rem Extra options pass through to the game, e.g.:  play.bat --demo-factory --noise-overlay
if not defined GODOT set "GODOT=C:\projects\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
cd /d "%~dp0"
if not exist "%GODOT%" (
	echo Can't find Godot at %GODOT%
	echo Set the GODOT variable to where Godot_v4.7-stable_win64.exe is, or edit this file.
	pause
	exit /b 1
)
echo Refreshing scripts...
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . -- %*
