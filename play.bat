@echo off
rem Double-click to play Noise Floor on Windows.
rem First it downloads the latest merged version (so merging on GitHub is all you need to do), then it
rem refreshes Godot's list of game scripts (needed when an update adds new ones) and starts the game.
rem Extra options pass through to the game, e.g.:  play.bat --demo-factory --noise-overlay
if not defined GODOT set "GODOT=C:\projects\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe"
cd /d "%~dp0"
if not exist "%GODOT%" (
	echo Can't find Godot at %GODOT%
	echo Set the GODOT variable to where Godot_v4.7-stable_win64.exe is, or edit this file.
	pause
	exit /b 1
)
call :update
echo Refreshing scripts...
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . -- %*
exit /b


rem Updates only a clean copy that's on the main branch, so it never touches work in progress.
rem Any problem (no git, no internet, local changes) just skips the update and plays what's here.
:update
where git >nul 2>&1 || exit /b 0
for /f "delims=" %%b in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "NF_BRANCH=%%b"
if not "%NF_BRANCH%"=="main" (
	echo Not on main ^(%NF_BRANCH%^), skipping the update.
	exit /b 0
)
git diff --quiet >nul 2>&1 || (
	echo Local changes here, skipping the update.
	exit /b 0
)
echo Checking for updates...
git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 fetch -q origin main >nul 2>&1 || (
	echo Couldn't reach GitHub, playing the version you have.
	exit /b 0
)
git merge -q --ff-only origin/main >nul 2>&1 && (
	for /f "delims=" %%v in ('git log -1 --format^=%%s') do echo Up to date: %%v
) || echo Couldn't update automatically, playing the version you have.
exit /b 0
