# CLAUDE.md — Noise Floor

First-person survival-automation game: Project Zomboid survival × Satisfactory factory building, where **machines make noise and noise draws zombies**. Solo player. Godot **4.7**, GDScript 2.0.
Owner: Emmitt. He is not very technical, so explain things in plain words, give one recommendation, and act on it.

**Start every session by reading `docs/DIRECTION.md` (what to build next and why), the newest entry in `docs/PLAYTESTS.md`, `docs/GAME_DESIGN.md` (design + milestone checklist) and the latest entry in `docs/DEVLOG.md`.** If the newest playtest entry is newer than the last milestone, fix what it says first. Otherwise build the next step in the order `docs/DIRECTION.md` gives, which overrides the checklist order in `GAME_DESIGN.md`.

## Where this runs
- Mostly in **Claude Code cloud sessions** (Linux, no GPU) from the private repo `efenn-dev/noise-floor`. At session start, `.claude/settings.json` runs `tools/cloud-setup.sh`, which installs the pinned Godot 4.7 (sha512-checked) to `~/.local/godot` plus Xvfb/Mesa for screenshots, then prints a status line. If it says FAILED, fix that before writing game code.
- Also on Emmitt's Windows PC at `C:/projects/noise-floor` (Godot in `C:/projects/Godot_v4.7-stable_win64.exe/`). He plays by double-clicking `play.bat` (or `play.bat --demo-factory` etc. in a terminal). It first fast-forwards a clean `main` checkout from GitHub (so merging a PR is all he has to do; it skips any other branch or local changes), then runs `--import` so new `class_name` scripts are known. When telling him how to try something, give `play.bat` commands, not raw Godot command lines. Everything must work in both places: use `tools/*.sh`, and never hard-code one OS's paths in game code. On his PC, run one heavy job at a time (the machine hard-powers-off under sustained load); a screenshot run is fine.

## Commands
```bash
tools/test.sh                      # headless (--fixed-fps 60, so physics tests run faster than real time): run every test/test_*.gd; non-zero on any failed check or SCRIPT ERROR
tools/shot.sh <name> [game flags]  # one frame -> .shots/<name>.png, then Read the PNG.  e.g. tools/shot.sh night --time=22
tools/godot.sh <args>              # the pinned Godot binary
tools/stress.sh                    # headless sim stress test (town, 50 machines, 200 / 20 zombies; ~1 min): prints ms per tick and per-call costs; not part of test.sh. Report: docs/perf/
```
Session logs (since P0): each play session writes a plain-words summary (deaths and causes, builds, heat, loudest sounds, first five minutes) to `user://sessions/<YYYY-MM-DD_HHMM>.txt` on every death and at quit (on Windows `%APPDATA%/Godot/app_userdata/Noise Floor/sessions/`); the console prints `Session log: <path>`. Never in headless runs or screenshots.
Build line (since P1): `play.bat` rewrites `version.txt` (`git log -1 --format="%h %s"`, shown on the title screen, in the session log header and the console) and `play-update.log` (what its update step did) next to itself on every run; both are git-ignored. Tests point `GameSession.version_path` at their own file.
Game flags (after `--` when calling Godot directly): `--screenshot[=PATH]`, `--time=HOURS`, `--cam=X,Y,Z[,YAW[,PITCH]]` (player feet position + look in degrees; 0,0 = north, +yaw turns left, +pitch looks up), `--flashlight`, `--build=foundation|wall` (start in build mode), `--demo-base` (pre-build a small base north of spawn), `--demo-factory` (smelter → belts → press loaded with scrap, generator + pole), `--demo-farm` (rain collector → purifier, planter → canner, solar panel), `--demo-defense` (walled square: door, barricades, loaded nail turret, spikes), `--advance=SECONDS` (run the sim first, so shots show items moving), `--zombies=N` (street zombies at start, default 8; 0 = none, and no house zombies either), `--zombie=X,Z[,X,Z...]` (extra zombies facing the player, for framing; `--zombie-type=runner|screamer` picks their kind), `--hurt=N` (start damaged; 100 shows the death screen), `--noise-overlay` (noise rings + zombie states, N in game), `--heat=N` (start the Director's heat), `--title` / `--pause` / `--settings` (open that menu, for screenshots), `--inventory[=ITEM]` (open the inventory screen, optionally with ITEM in your pockets selected), `--skills` (open the skills and perks screen, K in game), `--drive[=car_N]` (start in that car, car_0 by default), `--no-hints` (no first-game hints; they only show in a new game without `--demo-*`/`--cam`, and tests that load `main.tscn` set `GameSession.skip_hints = true`), `--hints` (show them anyway, for screenshots), `--inside[=N]` (start inside house N, 0-11, looking at its fridge; e.g. `tools/shot.sh inside --inside=1 --time=12`). With no flags at all the game opens on the title screen; any flag skips it. Tests that load `scenes/main.tscn` set `GameSession.skip_menu = true` (and point `GameSession.save_path` at a test file before saving). e.g. `tools/shot.sh factory --time=15 --cam=-3,0,-100,30,10`, `tools/shot.sh base --demo-base --build=wall --cam=0,0,6,0,-20`, `tools/shot.sh factory --demo-factory --advance=7.5 --cam=0,0,6,0,-25`. Add new flags in `src/world/main.gd` `_parse_user_args()` and list them here. Since M6 the debug kit starts in a storage crate at cell (1, 3), not in the player's pockets; build with `sim.stock_at(pos)`, not `sim.inventory`. Since M7 powered machines (smelter, press, purifier, canner) need power; tests about other things set `sim.power.free = true`.

## Architecture rules
- **`src/sim/`** holds the game rules as plain `RefCounted` classes: no Nodes, no scene tree, no rendering. Inventory, recipes, machines, belts, power, noise, zombie brains, the director and survival stats all live here, stepped by a **fixed sim tick**, separate from the frame rate, so results are deterministic. Everything here gets headless tests. **Cloud sessions can't watch the game, so an untested rule should be assumed broken.**
- **`src/world/`** handles presentation and input: nodes that read sim state and draw it, the player controller, the build ghost, zombie bodies, the HUD. Keep game rules out of it.
- **`data/`** holds content (items, recipes, machines, loot tables) as JSON, loaded and validated by a test.
- Build scene content in code where practical, and keep hand-written `.tscn` files tiny. That's easier to diff and harder to corrupt.
- Commit `.uid` and `.import` files. `.godot/` and `.shots/` are ignored.

## Art and sound (since M10)
- **Models:** `tools/art/<id>.py` are deterministic Blender 5.1 scripts on the shared `tools/art/kit.py` (read its docstring: front = -Y, separate `Lamp`/`Head` parts, fit-in-collider checks). They export `assets/models/<id>.glb`, and `BuildView.MODELS` lists them. `test/test_art_models.gd` checks fit, floor contact, merging, lamps and heads, and facing. The zombie is `tools/art/zombie.py` (rigged, animated) and is driven by `ZombieBody`.
- **Textures:** Codex-generated photos, made seamless with a normal map by `tools/art/make_tileable.py`. They're drawn via `Surfaces.material(name, tile_m, tint)`: world-space triplanar, shared, no UVs needed. Imports need mipmaps on (see existing `.import` files).
- **Icons:** `tools/art/make_icon.py` cuts generated item pictures out to `assets/icons/<item_id>.png`.
- **Sounds:** `tools/audio/synth.py` builds the machine, ambience and impact sounds; loop points are written into the WAVs, so they loop on import. Zombie voices are CC0 recordings in `assets/sounds/zombie/`. `SoundView` plays machine hums at the sim's loudness, so what you hear matches what zombies hear.
- **Vehicles (since M10c):** `CarBody` (VehicleBody3D) drives toward +Z, so the -Z-facing model is turned round inside it and `sim_yaw()` converts. Car models need separate `Wheel_*` parts plus "Car Paint" and "Car Glass" materials (`test_vehicle_models.gd`). The rules (fuel, keys, hotwiring, damage, noise) are in `Vehicles` + `SimWorld`, with data in `vehicles.json` and `skills.json`.
- **Third-party files** are listed in `assets/CREDITS.md` (CC0 only, and ask Emmitt first).
- Codex and Blender exist only on Emmitt's PC. Cloud sessions can re-run `synth.py` and use the committed assets, but can't make new models, textures or icons. Leave a placeholder and note it in the devlog.

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
