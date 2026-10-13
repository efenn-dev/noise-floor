class_name GameSession
extends RefCounted
## Things that must survive restarting the game scene (loading a save reloads the scene).

const SAVE_PATH := "user://save.json"
const AUTOSAVE_SECONDS := 300.0

## Path of a save to load as soon as the scene has rebuilt the town ("" = start fresh).
static var pending_load := ""
## True once the title screen has been passed this run, so reloads go straight into the game.
static var started := false
## Tests and command-line flags skip the title screen.
static var skip_menu := false
## Tests that load the main scene skip the first-game hints (like --no-hints).
static var skip_hints := false
## Where saves go (tests point this somewhere else).
static var save_path := SAVE_PATH

## Where play.bat writes the build being played: one line, "<short commit> <commit title>".
const VERSION_PATH := "res://version.txt"
## Tests point this at a file of their own, so they never read the real one.
static var version_path := VERSION_PATH
## True once the build line has been printed to the console (main.gd, once per run).
static var build_printed := false


## The build being played, for the title screen, the session log and the console. "dev build" when
## play.bat didn't write one (running from the editor, a test, a cloud session).
static func version_line() -> String:
	if not FileAccess.file_exists(version_path):
		return "dev build"
	var f := FileAccess.open(version_path, FileAccess.READ)
	if f == null:
		return "dev build"
	var line := f.get_line().trim_prefix("\ufeff").strip_edges()
	return line if line != "" else "dev build"
