# CLAUDE.md — Noise Floor

First-person survival-automation game: Project Zomboid survival × Satisfactory factory building, where **machines make noise and noise draws zombies**. Solo player. Godot **4.7**, GDScript 2.0.
Owner: Emmitt. He is not very technical, so explain things in plain words, give one recommendation, and act on it.

**Start every session by reading `docs/GAME_DESIGN.md` (design + milestone checklist) and the latest entry in `docs/DEVLOG.md`.** Unless told otherwise, build the first unchecked milestone.

## Where this runs
- Mostly in **Claude Code cloud sessions** (Linux, no GPU) from the private repo `efenn-dev/noise-floor`. At session start, `.claude/settings.json` runs `tools/cloud-setup.sh`, which installs the pinned Godot 4.7 (sha512-checked) to `~/.local/godot` plus Xvfb/Mesa for screenshots, then prints a status line. If it says FAILED, fix that before writing game code.
- Also on Emmitt's Windows PC at `C:/projects/noise-floor` (Godot in `C:/projects/Godot_v4.7-stable_win64.exe/`). Everything must work in both places: use `tools/*.sh`, and never hard-code one OS's paths in game code. On his PC, run one heavy job at a time (the machine hard-powers-off under sustained load); a screenshot run is fine.

## Commands
```bash
tools/test.sh                      # headless: refresh class cache, run every test/test_*.gd; non-zero on any failed check or SCRIPT ERROR
tools/shot.sh <name> [game flags]  # one frame -> .shots/<name>.png, then Read the PNG.  e.g. tools/shot.sh night --time=22
tools/godot.sh <args>              # the pinned Godot binary
```
Game flags (after `--` when calling Godot directly): `--screenshot[=PATH]`, `--time=HOURS`, `--cam=X,Y,Z[,YAW[,PITCH]]` (player feet position + look in degrees; 0,0 = north, +yaw turns left, +pitch looks up), `--flashlight`, `--build=foundation|wall` (start in build mode), `--demo-base` (pre-build a small base north of spawn), `--demo-factory` (smelter → belts → press loaded with scrap), `--advance=SECONDS` (run the sim first, so shots show items moving). e.g. `tools/shot.sh factory --time=15 --cam=-3,0,-100,30,10`, `tools/shot.sh base --demo-base --build=wall --cam=0,0,6,0,-20`, `tools/shot.sh factory --demo-factory --advance=7.5 --cam=0,0,6,0,-25`. Add new flags in `src/world/main.gd` `_parse_user_args()` and list them here.

## Architecture rules
- **`src/sim/`** holds the game rules as plain `RefCounted` classes: no Nodes, no scene tree, no rendering. Inventory, recipes, machines, belts, power, noise, zombie brains, the director and survival stats all live here, stepped by a **fixed sim tick**, separate from the frame rate, so results are deterministic. Everything here gets headless tests. **Cloud sessions can't watch the game, so an untested rule should be assumed broken.**
- **`src/world/`** handles presentation and input: nodes that read sim state and draw it, the player controller, the build ghost, zombie bodies, the HUD. Keep game rules out of it.
- **`data/`** holds content (items, recipes, machines, loot tables) as JSON, loaded and validated by a test.
- Build scene content in code where practical, and keep hand-written `.tscn` files tiny. That's easier to diff and harder to corrupt.
- Commit `.uid` and `.import` files. `.godot/` and `.shots/` are ignored.

## Godot 4.x traps (training data is full of Godot 3)
- GDScript 2.0: `@export`, `@onready`, `super()`, typed `var x: int` / `:=`, `signal_name.connect(callable)` and `signal_name.emit()`, `await` (not `yield`), `instantiate()` (not `instance()`).
- Renames: `Spatial`→`Node3D`, `KinematicBody`→`CharacterBody3D` (`velocity` is a property; `move_and_slide()` takes no args), `rand_range`→`randf_range`, `PoolStringArray`→`PackedStringArray`, `deg2rad`→`deg_to_rad`.
- After adding or renaming a `class_name` script, the class cache needs a refresh. `tools/test.sh` does it (`--import`).
- Test files extend `"res://test/base_test.gd"` **by path** and name methods `test_*`. Use `check`, `eq`, `near`. A test may `await tree.physics_frame` to run real physics (see `test/test_player_walk.gd`); free what it adds to `tree.root`. Don't name non-test files `test_*.gd`.
- Input actions: register them in code at startup (one place), not by hand-editing `project.godot`.

## Visual checks
After any visible change, take a screenshot, and a night one (`--time=22`). Look at the PNG before claiming it works. Cloud screenshots use the Compatibility renderer on software GL, so lighting looks flatter than Forward+ on Emmitt's GPU. Judge layout and legibility, not final looks.

## Working rules
- One milestone per session/branch. Finish with: tests green, screenshots checked, the milestone box ticked in `docs/GAME_DESIGN.md`, and a short `docs/DEVLOG.md` entry covering what was built, how to try it on the PC, known gaps, and what's next.
- One bundled commit per milestone with a structured body (what + why). Push the session branch; Emmitt merges the PR before the next session starts.
- No third-party assets or addons without asking Emmitt. CC0 only (Kenney, Quaternius, ambientCG, Poly Haven).
- Keep command output compact. Emmitt pays per token. Don't dump whole logs; grep them.
