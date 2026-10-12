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
## Where saves go (tests point this somewhere else).
static var save_path := SAVE_PATH
