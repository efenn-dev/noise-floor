# Devlog

Newest first. One entry per milestone: what was built, how to try it, known gaps, next.

## 2026-10-12 — Fixes from the first PC playtest: mouse, play.bat

**Mouse didn't work (no turning, no swinging, no building):** the white crosshair dot was a HUD element that caught mouse input. A locked mouse sits in the middle of the screen, right on the dot, so the dot swallowed every look and click. Now nothing on the HUD catches the mouse. New test `test/test_main_input.gd` loads the real game scene and feeds it mouse moves and clicks the way Windows does (turn, look up, swing, build), so this can't slip past the cloud again. It failed before the fix and passes after.

**play.bat launcher:**

Problem: after pulling M5, launching Godot directly on the PC failed with "Could not find type NoiseOverlay". Godot only learns about new named scripts when it imports the project; the cloud test script does that, launching the game directly doesn't.

Fix: `play.bat` in the project folder. Double-click it to play. It refreshes Godot's script list, then starts the game. Options go after it in a terminal: `play.bat --demo-factory --noise-overlay`. If Godot ever moves, edit the path at the top of the file.

## 2026-10-12 — M5 Noise (first playable)

**Built:** the signature system. A working machine is loud (smelter 60, press 55; idle machines are silent). Sound fades with distance and each of your walls in the way takes 10 off: `heard = loudness - 20*log10(distance) - 10*walls`. Zombies listen every half second and hear anything at 20 or more by day, or 14 at night. When they hear something they walk to it; if it's a machine they wreck it, and if it's anything else they look around and wander off. Your footsteps make noise too: walking barely carries, sprinting does (a zombie 8 m away hears you sprint but not walk), and crouching is silent. Pipe hits, zombies bashing on walls and things being wrecked all make noise, so a fight draws a crowd. Look at a machine to see its loudness; **U** fits a **muffler** (4 metal plates, 8 nails): 15 quieter, 10% slower, refunded if you remove the machine. The **Director** keeps a heat score from how loud your machines are 50 m away through the leakiest side of your walls (1.5 times faster at night). Heat cools when things are quiet. Every 30 s it may send zombies in from a road end toward your loudest machine: 2 wanderers by day, and at night a group of 4 or a horde of 8. A message at the top says which way they're coming from, and a line under your materials warns when heat is building. **N** shows the noise overlay: hearing rings around machines (orange = day, blue = night, through your walls' leakiest side), white rings for one-off sounds, and a coloured mark over each zombie (grey idle, yellow investigating with a line to what it heard, red chasing, orange breaking).

**What it means in play:** a bare smelter gets noticed in about 30 s and draws wanderers. At night, groups and then hordes come. Walling a machine in on all four sides or fitting a muffler keeps the heat falling, but a single gap lets the noise out.

**Rules (sim, tested):** `NoiseField` (formula, wall counting along the grid, continuous and one-off sounds, outdoor level), `Director` (heat, waves, spending heat), `ZombieBrain` gains INVESTIGATE, and mufflers on factory machines. Tuning lives in `data/noise.json`; machine loudness in `data/buildables.json`; hearing thresholds in `data/zombies.json`. Machines now roll straight into their next item instead of pausing a tick between items. The tests caught this: the Director could look during that one silent tick.

**Tests:** 332 checks. Formula values from the design doc (80 at 1 km = 20; 60 at 100 m = 20), wall counting (straight, diagonal, through a room), machines noisy only while working, muffler numbers and refund, a zombie hearing a smelter 41 m away then wrecking it, walls stopping the sound by day but not at night, sprint vs walk, every zombie getting to hear one-off sounds, bashing drawing others, heat rising and cooling, walls or a muffler keeping things calm and a gap leaking, and day/night wave sizes.

**Try it on the PC:** merge, `git pull`, launch with `-- --demo-factory --noise-overlay` and watch the rings. Stand still and yellow lines appear as zombies come to look. Press U on the smelter, or build walls round it, and watch the heat line. Try a night with `-- --time=20 --demo-factory`.

**Known gaps:** the town's buildings don't muffle sound (only your walls do); no sound effects yet (M10); hordes don't take roads, they walk straight from a road end; zombies never stop investigating a machine that's still running unless they wreck it; a flashlight shadow glitch shows as stripes on distant faces in the cloud's software renderer (probably fine on the PC's GPU; tell me if you see it).

**Next:** First playable is done (M1–M5), so **play it** and say what feels off. Then M6, survival: hunger, thirst, fatigue, bleeding, searchable containers and loot.

## 2026-10-12 — M4 The dead

**Built:** 8 shamblers roam the sidewalks of the main street. They stroll near where they stand, spot you by sight (25 m by day, 12 m at night, but 25 m at night if your flashlight is on; they also notice you within 3 m whatever way they face), walk after you along a navmesh, and hit you for 10 every 1.2 s. If they lose you, they go to where they last saw you, look around for 4 s and give up (or give up after 20 s if they can't get there). If something you built is in the way, they hit it (10 per hit) until it breaks; wrecked pieces give no refund and lose whatever they held. Your **health** shows bottom left and the screen flashes red when you're hit. **Left-click** swings a pipe (34 damage, double on a head hit, 0.7 s between swings, knocks them back); three body hits or a head hit plus a body hit kill one, and it falls over. If you **die**, everything you carried drops in a glowing bag where you fell, and you respawn at the start 3 s later; walk back and press **E** on the bag.

**Rules (sim, tested):** `ZombieBrain` (idle → wander → chase → attack, break, dead), `Horde` (spawning, corpses cleared after 15 s), `PlayerStats` (health, swing timer, death and respawn), building hit points and wreckage in `BuildGrid`, death bags in `SimWorld`. Zombie and pipe numbers live in `data/zombies.json` and `data/weapons.json`; building hit points in `data/buildables.json`.

**World:** `NavBaker` bakes the zombie navmesh from the town at start and re-bakes in the background about a second after you build or something breaks. `ZombieBody` walks the path (or straight at you if there's no path) and reports what it sees and bumps into. `Melee`, `BagView`, health HUD and death screen. The ground is now a solid slab (the navmesh baker can't read an endless plane).

**Tests:** 263 checks. Brain: sight rules, wandering, chase → attack timing, losing you, breaking a wall, dying. Sim: dying drops a bag and respawns you at the start, swing cooldown, two zombies take a wall down, wreckage without refund. Physics runs: a zombie chases and bites, breaks a wall it can't get round, takes a head hit then a body hit and falls over, and follows the navmesh round a building to reach you. `tools/test.sh` now runs Godot with `--fixed-fps 60`, so those physics runs finish in seconds instead of in real time (the whole suite takes about 6 s).

**Try it on the PC:** merge, `git pull`, launch, walk north up the street. Back off to see them follow; swing with left-click. Build a little walled box (B) and stand inside to watch them hit the walls. `-- --zombie=0,-4` puts one right in front of you.

**Known gaps:** no stamina cost for swinging (stamina comes in M6); zombies are coloured capsules; no sounds; no zombie-on-machine attacks unless the machine is in the way; you respawn at the start, not at a bed (beds come with M6 or M9); corpses just vanish after 15 s.

**Next:** M5, noise. Machines get loud, zombies hear them, and a Director sends groups at night. That's the first playable.

## 2026-10-12 — M3 Machines and belts

**Built:** three new things in build mode: **3 belt**, **4 smelter**, **5 press**. They sit on foundations and face away from you (R turns them). A machine takes items in at its back (blue port) and pushes products out of its front (orange port). Belts carry items forward and can turn corners. The **Smelter** turns 1 scrap metal into 1 metal plate every 2 s; the **Press** turns 1 plate into 4 nails every 2 s. A lamp on each machine glows green while it works and amber when its output is full. Look at a machine (not in build mode) to see what's in it; **E** takes its output and loads it with what it needs from your pockets. E on a belt picks up the items on it. Removing a machine or belt gives back its build cost *and* everything inside it.

**Rules (sim, tested):** `Factory` (`src/sim/factory.gd`) with machines and belts on the fixed tick. Belts run at 1 cell (2 m) per second with items at least a quarter-cell apart. Each tick moves every item first, then does hand-offs, so results don't depend on build order. Recipes live in `data/recipes.json`, machines and belts in `data/buildables.json`, and item colours in `data/items.json`.

**Tests:** 169 checks. The M3 proof: smelter → 3 belts → press, hand-fed 10 scrap, gives 10 plates and then 40 nails within 28 s, with exactly 7 plates at 15 s. Also: belt speed (3 cells in 3 s), corners, no feeding a belt head-on, no feeding a machine from its side, belts backing up without overlap, output-full stop, input caps, refunds of contents including a half-made item, identical results whatever the frame rate, and a world test of looking at a machine, pressing E and seeing items drawn on belts.

**Try it on the PC:** merge, `git pull`, launch. Press B and build a row of foundations (1), a smelter (4) facing along the row, belts (3) after it, and a press (5) at the end. Press B to leave build mode, look at the smelter and press E to load scrap. Or launch with `-- --demo-factory` for a ready-made line.

**Known gaps:** each machine has one fixed recipe (no recipe picker yet); no splitters or mergers; no storage box at the end of a line; machines don't need power yet (M7) and aren't loud yet (M5); you can't place items onto a belt by hand.

**Next:** M4, the dead (zombies).

## 2026-10-12 — M2 Build

**Built:** press **B** for build mode. A see-through ghost snaps to the 2 m grid where you aim: green means you can build, red means you can't, and the HUD says why ("Needs a foundation", "Not enough materials", "Something's in the way"). **1** picks foundation, **2** picks wall, **R** turns the wall to the next edge of the square, **left-click** builds, **right-click** removes what you're looking at with a full refund. Your materials show top right; you start with a debug kit (100 planks, 100 nails, 20 scrap). Foundations are low enough to walk onto; walls are solid.

**Rules (sim, tested):** `Inventory` (all-or-nothing payments), `GameData` (loads and checks `data/items.json`, `data/buildables.json`, `data/debug_kit.json`), `BuildGrid` (grid snapping, walls need a foundation on one side, an edge shared by two squares holds only one wall, you can't pull a foundation out from under a wall, 100% refunds). Physics layers: built pieces are on their own layer so they never count as "in the way" of each other.

**Tests:** 120 checks. New: inventory, data validation (including a deliberately broken file), the build rules, and a scripted physics run: aim, build, wall on top, remove both, crate blocks placement, can't build under yourself, player walks up onto foundations and is stopped by a wall. Also a check that `main.gd` compiles, after a typo in it slipped past the tests once.

**Also:** fixed dark stripes the flashlight's shadow made on flat walls.

**Try it on the PC:** merge, `git pull`, launch, press B, look at the ground and left-click. Press 2 for walls and build them on the edges of your foundations.

**Known gaps:** no build menu yet (number keys only); no doorways, doors, windows or stairs (doors and barricades come in M8); nothing saves (M9); materials only come from the debug kit until scavenging (M6); foundations only sit at ground level (no stacking or second floors).

**Next:** M3, machines and belts.

## 2026-10-12 — M1 Walk the town

**Built:** first-person `Player` (`src/world/player.gd`): WASD, mouse look, Shift sprint, Space jump, Ctrl/C crouch (won't stand up under a low ceiling), F flashlight, Esc frees the mouse and a click grabs it back. Input keys are registered in one place (`src/world/input_setup.gd`). New `SimWorld` (`src/sim/sim_world.gd`) steps all game rules on a fixed 20-per-second tick; the clock now runs there, and later systems (machines, noise, zombies) hook into `SimWorld.step()`. HUD shows day + clock, a centre dot and a key-hint line. New screenshot flags `--cam=X,Y,Z,YAW,PITCH` and `--flashlight`.

**Tests:** 39 checks. New: fixed-tick determinism (same result however frames are sliced), and a scripted physics run proving the player walks forward, sprints faster, crouches slower, jumps and lands, is **blocked by a wall**, and stays crouched under a low slab. The test runner now supports tests that `await` physics frames.

**Cloud bootstrap verified:** first cloud session; the setup hook printed `godot 4.7-stable ok | screenshots ok`, tests and screenshots work in the cloud.

**Try it on the PC:** pull/merge, then `C:/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe --path C:/projects/noise-floor`. Click into the window, walk around, wait for night (about 11 real minutes from the 08:00 start, or launch with `-- --time=20`) and press F.

**Known gaps:** mouse sensitivity is fixed (settings come in M9); no stamina yet (sprint is unlimited until M6); no footstep sounds; nothing to do in town yet. Flashlight and lighting were tuned on the cloud's flat software renderer, so they may look brighter on the PC.

**Next:** M2 — Build.

## 2026-10-12 — M0 Skeleton

**Built:** Godot 4.7 project; greybox town (road, 12 block houses, 4 cars, the factory at the north end) built in code (`src/world/main.gd`); day/night sun + moon driven by `GameClock` (`src/sim/game_clock.gd`: 1 real minute = 1 hour, sun up 05:00–21:00); zero-dependency headless test runner (18 checks); screenshot tool; cloud bootstrap hook that installs pinned Godot + Xvfb/Mesa.

**Verified on Emmitt's PC:** `tools/test.sh` green; runner correctly reports a failing check and a crashing test; screenshots render in both Forward+ and the Compatibility renderer (the one cloud sessions use); nights are properly dark.

**Not yet verified:** the cloud bootstrap itself. The first cloud session should confirm the `cloud-setup:` status line says `ok` for both Godot and screenshots.

**Try it on the PC:** `C:/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe --path C:/projects/noise-floor` (camera is fixed; time passes at 1 hour per minute).

**Next:** M1 — Walk the town.
