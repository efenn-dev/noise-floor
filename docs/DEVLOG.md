# Devlog

Newest first. One entry per milestone: what was built, how to try it, known gaps, next.

## 2026-10-13 — M12 Skills and perks

From the M12 brief by the project lead, on top of W1b.

**Built:**
- **Ten skills that level by doing** (0-10, Zomboid style), each with one effect you can feel:
  - **Strength:** trained by swinging the pipe and by walking with more than half your carry limit. Carry limit is 20 kg + 3 kg per level (20-50 kg before bags), and melee damage and knockback go up 5% per level.
  - **Fitness:** trained by sprinting. Stamina comes back 5% faster per level.
  - **Building:** trained by placing pieces and repairing them. Repairs cost 5% less per level (rounded, never below half).
  - **Mechanics:** as before (repairs, car repairs, mufflers, hotwiring; hotwiring needs level 2 and gets quicker).
  - **Scavenging:** trained by each finished search. Searching takes 5% less time per level.
  - **Sneaking:** trained by each second you move crouched within 15 m of a zombie that hasn't noticed you. Walking footsteps are 1 quieter per level.
  - **Melee:** trained by each hit, more for a kill. Melee damage +4% per level (on top of Strength).
  - **Firearms:** listed, greyed out ("Comes with guns"); nothing trains it yet.
  - **First Aid:** trained by each bandage. A bandage also heals 5 health per level, and a zombie bite is 2 points less likely to make you bleed per level.
  - **Farming:** trained each time you take a planter's vegetables. Planters grow one extra vegetable per three levels.
- **Perk points:** every 3 skill levels you gain (all skills added up) earns 1 point. The HUD says "Strength 2" when a skill goes up and "Perk point earned: K to spend" when you get a point.
- **Three perk trees, three perks each, ranks 1-5,** spent on the skills screen and never refunded:
  - **Engineer:** Fast Lines (belts +10% speed per rank), Dampened Gears (machines and generators 2 quieter per rank, plus 1 more for every 3 points you've spent in Ghost), Tuned Machines (machines craft 5% faster per rank).
  - **Ghost:** Soft Step (walking and sprinting footsteps 3 quieter per rank), Quick Fingers (searches 10% faster per rank), Lucky Find (20% chance per rank that a search finds one extra item).
  - **Fighter:** Heavy Swing (melee damage +10% per rank), Second Wind (stamina back 10% faster per rank), Thick Skin (zombies hurt you 5% less per rank).
- **The skills screen (K, Esc or K closes):** every skill with its level, a bar to the next level and what it does; your perk points; the three trees with each perk's rank and a +1 button (greyed with no points or at rank 5). The game keeps running while it's open, like the inventory, and you stand still. The HUD's key line says "K skills".
- **You keep skills, perks and unspent points when you die.**

**Rules (sim, tested):** `Skills` holds xp, `perks` (ranks) and `perk_points`; `practice(skill, action, times)` adds xp from `data/skills.json` and earns points (`points_earned` = total levels / 3); `spend(perk)`/`can_spend`; and one query, `bonus(effect)`, sums every skill level and perk rank that gives `effect` (a `{"value", "every"}` spec gives "1 per 3 levels"; a perk's `synergy` adds per `every` points in another tree once you have a rank). The rules call it: `SimWorld.carry_limit` (carry_kg), `melee_damage`/`hit_zombie` (melee_damage, knockback), `PlayerStats.stamina_regen_mult` (stamina_regen), `BuildGrid.repair_cost(key, discount)` via `SimWorld.repair_cost` (repair_discount), `Loot.search_time` (search_speed, floor `search_time_min`) and a Lucky Find roll on the container's own seeded rng after the normal roll (lucky_find), `SimWorld.noise_loudness` for footsteps (walk_quiet, sprint_quiet), `bleed_chance` and `use_bandage` (bleed_cut, bandage_heal), zombie hits (damage_cut), `Factory` (belt_speed, craft_speed, planter_extra per craft), `NoiseField.machine_loudness` and `PowerGrid.noise_sources` (machine_quiet). New sim entry points: `SimWorld.swing()` (the world's swing now goes through it, for Strength xp), `machine_interact()` (E on a machine; Farming xp), `player_sneaking` (written by the world), `BuildGrid.piece_built` (only `place`, not `restore`, so loading a save or laying the town teaches nothing; demo bases are muted too). `GameData` validates the skills, trees and perks. **Saves:** `SaveGame.VERSION` is 5 (perks and perk points). A version-4 save loads with no perks and the points its skill levels are worth; a committed fixture `test/fixtures/save_v4.json` (written by the W1b code before these changes) is tested, and the v2 and v3 fixtures still load.

**Tests:** `test_skills.gd` (the ten skills in data; level thresholds; xp from swings, heavy steps, sprinting, placing and repairing, searching, sneaking near unaware zombies only, bandages, harvests; the level-up and perk-point messages; a point every 3 levels, even across a jump; spending, the rank-5 cap and no points no spend; each effect at level 0 vs 5: carry 20 -> 35 (50 at 10, bags on top), melee damage and knockback, stamina regen, repair cost and what's charged, search time and its floor, footstep loudness as zombies hear it, bandage heal and bleed chance, planter yield 3/4/4/5 at 0/3/5/6; Fast Lines, Tuned Machines, Dampened Gears with the Ghost synergy on machines and generators, Thick Skin, Lucky Find on the seeded rng; death keeps everything; save and load of xp, perks and points), `test_skills_screen.gd` (shows levels, greyed Firearms, ranks; the button spends a point and the rank shown changes; greyed with no points and at rank 5; in the real game K opens it, the player stands still, the game keeps running, Esc closes it without the pause menu, K toggles), `test_save.gd` (the version-4 fixture loads with a perk point for its Mechanics 3). `test_car_keys.gd` now expects "Mechanics 1". **2189 checks** (was 2022).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- Press **K** to see the skills screen. Or open it straight away: `play.bat --skills`.
- Sprint for 30 seconds: "Fitness 1" pops up. Hit a zombie a few times with the pipe: Strength and Melee go up. Search a few kitchen cupboards: Scavenging. Three levels in all and the HUD says "Perk point earned: K to spend"; press K and click +1 next to a perk.
- Strength: watch the "kg" number by your pockets (top right) go up from 20 as Strength levels.
- Farming: `play.bat --demo-farm --time=12`, wait for the planter, then E on it to take the vegetables.

**Known gaps:**
- Not in M12, as planned: items with "+1 to perks", respec (the Clean Slate), anything Firearms does, guns (M14). The design's other perk ideas (cheaper mufflers, see noise rings, harder to spot, recoil, reload, Gunsmith) aren't in yet.
- Every number is a first guess (xp per action in `data/skills.json`, e.g. a search 10, a bandage 15, a second of sprinting 1, level 1 at 30 xp). Tune after Playtest #1.
- Farming xp and the extra vegetables: xp only when you take the vegetables by hand (E), not when a belt carries them off; the extra vegetables are grown either way.
- Sneaking xp counts any zombie within 15 m that is idle, wandering or investigating (not one chasing you), with no line-of-sight check.
- The inventory screen still shows its own Mechanics line; the skills screen is the full list.
- No screenshot of a level-up message (no flag sets xp); the screen was checked by day and night.

**Next:** Playtest #1, then M13 loot.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1b Life inside

From the W1 plan (`docs/plans/W1.md`, "W1b — life inside"), on top of W1a and the stress test.

**Built:**
- **A zombie inside some houses.** In every town, 4 of the 12 houses have one shambler standing inside (never the two houses by the spawn). The world seed picks which houses and where, so the same seed always has them in the same places; in a new game (seed 1) they're in the 2nd house up on each side, the 4th on the left and the 6th on the right. Each one stands in the kitchen, next to the fridge or the kitchen cabinet, facing the front door. It just stands there: a zombie whose home is on a house floor doesn't go for strolls (my call: idle without wandering, rather than wandering inside the house's cells; it can't drift out and it's simpler). It's an ordinary zombie otherwise: it sees you through doorways and windows, hears you, and comes for you. Searching the fridge or cabinet next to it is loud enough to wake it by day.
- **The factory is a hall you can walk into.** The solid grey block at the north end of the road is gone. In its place: a 15 x 12-cell floor (30 x 24 m), walls in the old factory's grey brick, a 4 m wide open doorway (two empty edges, no door) where the road ends, three windows down each long side, and a roof with a dark ceiling about 6 m up (the brick carries on above the wall pieces up to the roof, and over the doorway). The three supply crates are inside now. It's built from the same grid pieces as the houses, so the walls muffle sound, zombies can bash them, and the navmesh runs in through the doorway.
- **Hordes come down the road.** Wanderers still come from any of the four edges, straight at the noise. Groups and hordes now come from the north or south end of the road only. From the north they appear behind the factory, come round its west side onto the road, and walk down it; from the south they walk up from the end of the asphalt. They follow the road to the point nearest the noise, then turn off toward it. The HUD still says "A horde is coming from the north...".

**Rules (sim, tested):** `TownPlan.generate` also returns `"zombies"` (house, cell, pos, facing; its own random stream, so the houses themselves don't change) and `"factory"` (`TownPlan.factory()`: cells, pieces, crates, doorway edges, windows; the same in every town). `SimWorld.place_factory(plan)` lays the hall like `place_town`; `SimWorld.spawn_house_zombies(plan)` spawns them through the horde. `ZombieBrain`: an idle zombie whose home is on a `town_floor` doesn't wander (`_indoors`); `hear_via(via, at, key, time)` gives it a short waypoint list (`route`) walked during INVESTIGATE, each waypoint consumed on arrival (each leg gets the full lure time), then `target_pos` becomes `sound_pos`; hearing the same sound again on the way keeps the route, a different sound drops it. `hear()` is still the entry point. `Director`: group and horde waves pick EDGES 0 or 1 (north or south) and call `hear_via(Director.road_route(edge, lure), ...)`; `road_route` is the corner behind the factory (north only), the road end, then road points at most 40 m apart down to the road point nearest the lure. The wave dict also carries its `route`. **Saves:** `SaveGame.VERSION` is 4 (`FIRST_WITH_FACTORY`, `holds_factory`). House zombies are ordinary saved zombies, and a loaded game doesn't spawn them again. A version-3 save (W1a) loads with the factory hall laid fresh under it; a committed fixture `test/fixtures/save_v3.json` (written by the W1a code) is tested. World: `main.gd` lays the hall, puts the crates on its floor and spawns the house zombies in a new game (not with `--zombies=0`); `TownView` draws the hall's roof, ceiling and upper brick; `BuildView` has a "factory" wall style.

**Tests:** `test_house_zombies.gd` (same seed same houses, 4 of 12, never lot 0, inside and not on a container or the doorway; one spawned per picked house; with no noise they stay idle and inside for five minutes while a street zombie wanders; searching the kitchen next to each one makes it investigate; a save brings them back once), `test_factory_hall.gd` (15 x 12 floor, walls and windows all round less the two-cell doorway, the doorway edges empty and on the road in the south wall, crates inside, no overlap with houses, sound gets out through the doorway but not the side walls; physics: you walk in through the doorway and the wall beside it stops you; a zombie on the road follows you in without breaking anything), `test_road_hordes.gd` (`road_route` from both ends; a north wave zombie with a smelter east of the road reaches the road point first, keeps to the asphalt, then reaches the smelter; same sound keeps the route, a new one replaces it; over six seeds the HUD's edge matches where the horde spawned and both ends get used; wanderers come straight), `test_save.gd` (the version-3 fixture loads with the hall added), `test_town_world.gd` (the whole game lays the hall and a zombie in each picked house, and a save brings the same zombies back, not doubled). **2022 checks** (was 1546).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- House zombie: walk up the street to the second house on the right (east side), open the front door (E) and look left through the doorway into the kitchen. Or start there: `play.bat --cam=9,0.1,-22.6,-63,-3 --time=12`.
- Factory: walk north to the end of the road and go in through the big doorway; the three crates are inside. Or: `play.bat --cam=0,0,-98,0,6 --time=12`.
- Hordes: `play.bat --demo-factory --time=21 --heat=100 --noise-overlay` and wait up to 30 seconds for "A horde is coming from the north (or south)...". Press N to see them: they walk the road toward you before turning off it.

**Known gaps:**
- Not in W1b, as planned: furniture props (table, couch, shelves need Blender art on the PC), a fifth house plan, the shop, any zombie tuning, and no change to infamy or heat numbers.
- With today's numbers a house zombie mostly finds you by sight, not sound: a search (30) is only heard within about 3 m by day, footsteps (22) and a door opening (25) barely at all. That's why they stand next to the kitchen. Tune hearing after the playtest if they feel deaf.
- Any zombie that ends up idle on a house or factory floor stays there (e.g. one that chased you in and lost you), not only the planted ones.
- A wave's road route isn't saved: a zombie that was walking the road when you saved stands where it was after loading (as every investigating zombie already did).
- The north road end is behind the factory, so northern hordes come round its west side; there's no road there. Hordes don't avoid the houses' lawns other than by the waypoints, and nothing makes the road a preferred lane on the navmesh.
- The factory is empty apart from the crates: no machines, shelves or props, and the brick above the wall pieces has a faint seam line at 2.8 m. Its roof has no collider (like the houses').
- Town pieces go from 455 to 687 with the hall; the first navmesh bake is about 49 ms headless (the console line now says "town pieces").

**Next:** Playtest #1, then M12.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — Stress test (numbers only)

How expensive one sim tick is with many zombies and machines, before zombies inside houses, hordes and automated defense. No code changed outside the test; nothing optimised.

- `tools/stress.sh` runs `test/stress/stress_sim.gd` (headless, not part of `tools/test.sh`): the W1a town, `power.free`, 50 smelters and presses kept crafting, 200 shamblers on the main street, `sim.step()` in a loop. A full day would take ~113 s of wall time, so it runs **4 game hours** from 19:00. Full table: `docs/perf/stress-2026-10-13.md`.
- **Town + 200 zombies + 50 machines: 4.6 ms per tick on average, 20 ms worst** (the budget at 20 ticks per second is 50 ms). Empty map: 4.2 ms. Town + 20 zombies: 2.3 ms.
- Where the time goes: zombies listening (`loudest_heard`, ~170 us each, every half second; it grows with zombies x machines) and the Director's `gain_now` (~10 ms once a second, which makes the worst ticks). The town itself adds ~0.4 ms. Memory +1.4 MB.
- Not measured: zombie bodies, navmesh and physics (a sim-only run never moves zombies).

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1a Into the houses

From Playtest #1 ("there are no doors or ways into the buildings") and the plan in `docs/plans/W1.md`.

**Built:**
- **Houses you can walk into.** The twelve box houses are gone. Each lot now has a real house built from the same 2 m grid pieces you build with: a floor, outside walls in brick or painted siding, a front door facing the road, a back door, three or four windows, and inside walls (pale plaster) with open doorways between the rooms. Three floor plans: A (8 x 8 m: living room, kitchen, bedroom, bathroom), B (10 x 6 m: kitchen-living room with a galley kitchen, bedroom, bathroom off the bedroom) and C (an L-shape: living room, kitchen and bathroom behind it, a bedroom wing). The world seed picks each lot's plan and whether it's mirrored, so the same seed always gives the same town. Each house has a flat roof with a ceiling under it, so rooms are dim by day and dark at night (the flashlight matters), and a strip of wall above each door.
- **The loot is inside.** Every house has a fridge and a kitchen cabinet in the kitchen and a cabinet in the bathroom (36 containers, was 12 on the lawns), back to the wall and facing the room, plus a real bed in the bedroom (sleep in it to make it your respawn point, like your own bed). A car key that lives "in the nearest house" is now in one of that house's containers.
- **Doors, windows and walls work like yours.** E opens and closes the doors. Closed doors, walls and whole windows muffle sound like your own walls, so closing the door behind you makes you harder to hear, and a loud machine indoors heats the Director up slower. Zombies bash doors, walls and windows. A window has 40 hp; when it breaks the glass is gone and it's an opening (sound, sight, zombies and you can go through). Build a barricade on that edge to board it up. You can see through glass, and so can zombies. You can't build town pieces yourself, but in build mode right-click knocks one down for a small refund: a plank from a floor or a window frame, a plank and a scrap from a house wall (a broken window gives nothing).
- **One new tip** after the crate tip in a new game: "Houses have food inside. E opens doors; close them behind you". It moves on when you search something in a house, or after 40 s.
- **Numbers for next time:** the town lays **455 pieces** (floors, walls, doors, windows and beds) and the first navmesh bake takes **about 48 ms** on Emmitt's PC. The console prints `Town: N house pieces laid, first navmesh bake N ms` at startup, and `test_town_world.gd` prints the same.

**Rules (sim, tested):** `TownPlan` (new, `src/sim/town_plan.gd`, pure): `generate(seed)` gives the pieces, containers, beds and houses for the twelve lots. `SimWorld.place_town(plan)` lays them into the `BuildGrid` with `restore` (free, full hp, not counted as your builds), and `SimWorld.town_container_pos` says where a container stands. New pieces in `buildables.json`: `town_floor` (kind foundation), `town_wall` (kind wall, 600 hp), `window` (a new kind, 40 hp), all `"player_placeable": false`. `BuildGrid`: windows are edge pieces; `edge_blocks` (whole glass blocks sound but not sight; broken blocks nothing), `is_broken`, `damage` leaves a broken window in place at hp 0 instead of wrecking it, `can_place` refuses town pieces ("Only found in town") and lets a barricade replace a broken window (no refund), `repair` on a broken window says to board it up, `remove` refunds nothing for a broken window. `ZombieBrain` stops bashing a window once it's broken. **Saves:** `SaveGame.VERSION` is 3. Town pieces are saved with the rest, so damage, open doors, broken windows and walls you knocked down stay that way. On load the town plan still runs (for the containers and roofs), but it only lays the houses when the save is older than version 3 (`SaveGame.holds_town`). A committed version-2 save (`test/fixtures/save_v2.json`, written by the pre-W1a code) still loads, with the houses laid fresh under it. World: `TownView` (roofs, ceilings, door lintels), `BuildView` draws town walls, floors and windows with the house's surface (`styles`), zombies see through window glass, and the `--inside[=N]` flag.

Where the plan and the code differed, I followed the code: `town_floor` is 0.1 m thick like `foundation` rather than flush, because walls and objects sit on `foundation_top()`. Containers and beds come with the wall `side` they stand against. The plans have two or three runs of inside wall (with doorways) rather than one or two, so each room reads as a room, and every plan has a wall straight behind the front door. The generator runs on every load, because containers aren't saved; only laying the pieces is skipped.

**Fixed on the way:** zombies treated the low edge of a floor they were stepping onto as a wall and started "breaking" it, standing still at the edge of houses and bases. Now they only count something they walk into face first.

**Tests:** `test_town_plan.gd` (same seed gives the same town; all three plans in use; every house closed all round with a floor under every cell; front door on the road side in the front row, a back door, 3-4 windows; containers and beds inside, against a wall; no shared cells; lots where the old houses stood; town pieces not in the build menu), `test_town_sound.gd` (for every house, a closed front door muffles and opening it lets sound out; a broken window lets it out and a barricade shuts it again; a smelter indoors is 10 dB quieter to the Director and heats it slower), `test_window.gd` (hp, breaking into an opening, sight vs sound, barricade over a broken window with no refund, can't build town pieces, refunds), `test_town_world.gd` (physics: walk in through the open door and stop at the wall behind the front room; a closed door keeps you out; a zombie on the street follows you in through the open door and bites; with the door shut it breaks the door; the whole game lays the houses once and a save brings them back with the open door and the damage), `test_save.gd` (the version-2 fixture loads; town damage, an open door, a broken window and a removed wall survive save and load). `test_hints.gd` now expects the new tip as step 2. **1546 checks** (was 1095).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**. Walk up the street: the houses have doors facing the road and windows. Press E on a front door to open it and go in: kitchen, bathroom, bedroom. Press E on the fridge and cabinets to search them. Close the door behind you (E). To start inside a house: `play.bat --inside=1` (any number 0 to 11). At night with the flashlight: `play.bat --inside=4 --time=22 --flashlight`. To see houses muffle sound: `play.bat --noise-overlay`, then open and close a door while a zombie is near. Old saves still load (the houses appear around your base, and house loot is fresh).

**Known gaps:**
- No new models or textures (as planned): windows are frame boxes with a glass pane, outside walls show brick or siding on the inside too, and there's no furniture beyond the fridge, cabinet and bed models.
- No zombies inside houses yet, the factory is still a solid block, hordes don't follow the road, and roofs don't affect sound (W1b).
- Town doors are ordinary doors and house beds are ordinary beds, so knocking them down refunds their full build cost (6 planks and 8 nails a door, 6 planks and 10 nails a bed). That's a lot of free material across 24 doors and 12 beds; tune it after the playtest.
- A broken window has no collider, so you can't aim at it to remove it with right-click. You can still board it up.
- The strip of wall above a door stays if the door is knocked down. Outside corners have a small notch where two walls meet (the same as your own walls).
- Containers you'd searched in a version-2 save stood on the lawns. Those are gone, so house loot is fresh after the upgrade.
- At 455 pieces the town's navmesh bake takes about 48 ms, and a rebake after each build still covers the whole town. The stress test in DIRECTION.md should measure it with many zombies.

**Next:** Playtest #1, then W1b.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — P1 Playtest fixes

From Playtest #1 (`docs/PLAYTESTS.md`): Emmitt pressed E on cars and couldn't drive them, and nobody could tell which build he was playing.

**Built:**
- **Cars explain themselves.** Looking at a car you have no key for now says `[E] get in   No key: search the trunk (E at the back) or the nearest house`. A wreck says what's wrong first, then what you can still do: `Flat tyres.   [E] search the trunk   [G] siphon gas`. A car you can start still just says `[E] get in`. The first time you sit in a keyless car, the HUD also says "No key. The glovebox is searched from the trunk, or try the nearest house" (once per car). The in-car line with `[R] hotwire` is unchanged.
- **Which build am I playing.** `play.bat` now writes two files next to itself on every run: `play-update.log` (when it ran and everything the update step said, including why it skipped or failed, plus git's own error text) and `version.txt` (the commit about to run, like `0c55be4 Merge pull request #18 ...`; "unknown build" without git). The title screen shows that line small in the bottom-right corner ("dev build" when there's no file), the session log's header starts with `Build: <that line>`, and the console prints `Noise Floor build: <that line>` at startup. The update itself is unchanged: clean `main` only, fast-forward only. Both files are git-ignored.

**Rules (sim, tested):** `Vehicles.start_hint(id, pockets)` (the one-line reason a car won't go: "" if it starts, the wreck text plus "you can still search the trunk and siphon its gas", or `Vehicles.NO_KEY_HINT`); `SimWorld.enter_car` adds `SimWorld.NO_KEY_MESSAGE` once per car. World: the car look-at prompt in `Interactor._car_status`, `GameSession.version_line()` / `version_path` (tests point it at their own file, like `save_path`), the title-screen label in `Menus`, the header line in `SessionLog`, and the console line in `main.gd`.

**Tests:** `test_car_keys.gd` (start_hint for no key, key in pockets, key in the ignition, hotwired and a wreck; the no-key message comes once per car and not for a car you can start), `test_car_prompts_world.gd` (loads the game, stands beside the first car and reads the prompt with no key, with the key, and as a wreck), `test_version.gd` (a temp version file shows on the title screen and in the session log header; no file or an empty one says "dev build"). 1095 checks (was 1067). `play.bat` was tried by hand on a branch (skips, logs why), a clean `main` one commit behind (fast-forwards, logs "Up to date"), and with local changes (skips, logs why).

**Try it on the PC:** merge, then double-click `play.bat`. The title screen's bottom-right corner shows the build; `play-update.log` and `version.txt` appear next to `play.bat` (open them with Notepad). Start a **New game**, walk up the street to the red sedan and look at its side: it says there's no key and where to look. Look at its back and press E to search the trunk (the glovebox key is there), then E at the side to get in and drive. To try a wreck, walk on down the street until a car says "Flat tyres", "The engine won't turn over" or "Smashed up too badly".

**Known gaps:** the no-key hint doesn't say which house, and a car whose key is lost gets the same hint (hotwiring with Mechanics 2 is its only way). The "told you once" memory isn't saved, so a loaded game may say it once more. `version.txt` is only written by `play.bat`, so running Godot directly shows "dev build". The houses are still closed boxes (W1).

**Next:** Playtest #1 on the merged build.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — P0 Playtest kit

**Built:**
- **Session log.** Every time you play, the game keeps a short plain-words diary of the session and saves it as a text file (under 40 lines): how long you played (real and game time), each death and what caused it (the zombie type, starvation, dehydration or bleeding), how hot the Director got and when, what you built (by kind), mufflers fitted, zombies killed, the loudest one-off sound and the loudest machine or engine, and a timeline of your first five real minutes (built X, searched Y, hit a zombie, died, siphoned, got in a car...). It's written when you die and again when you quit (closing the window, Quit on the title screen, or quitting to the title), to `sessions/<date_time>.txt` in the game's save folder; the console prints `Session log: <path>`. Loading a save during a sitting carries on the same log.
- **First-game hints.** A new game shows one tip at a time above the health line: find the crate and press E, build a foundation and a smelter, press N to see how far the noise carries, then wall it in or fit a muffler (U). Each moves on when you've done it, or after 90 seconds so it never nags (the noise tip after 40). They never take input. Not after loading a save, not with `--demo-*` or `--cam`, not in screenshots; `--no-hints` turns them off and `--hints` forces them on.

**Rules (sim, tested):** `RunStats` (new, in `src/sim`) records the session; `SimWorld.stats` is fed where things already happen (zombie hits and kills, deaths, builds, mufflers, searches, siphoning, getting in a car, crate use, Director waves and heat, the noise field each tick). `PlayerStats.last_cause` remembers what hurt you last, so the death cause is worked out in the sim. The game's own setup (start crate, demo bases, loading a save) is muted, so it isn't counted as yours. World: `SessionLog` (writes the file; off in headless runs and screenshots, tests use `path_override`), `Hints` (one label), `GameSession.skip_hints`, and the `--no-hints` / `--hints` flags.

**Tests:** `test_run_stats.gd` (death by a zombie vs starvation, thirst, bleeding; builds by kind, not counting the start crate; the five-minute timeline cut-off and repeats; peak heat and when; loudest sounds), `test_session_log.gd` (a death writes the log with the expected lines to a test path; off unless enabled), `test_hints.gd` (hints follow the crate, the smelter, the noise timeout and a muffler; time out; a new game shows them and a loaded save doesn't). 1013 checks (was 929).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**: the first tip appears above your health. Play a while (die once if you can), then quit from the title screen. The log is in `%APPDATA%\Godot\app_userdata\Noise Floor\sessions\` (paste that into the Explorer address bar); the newest `.txt` is your session. To play without tips: `play.bat --no-hints`.

**Known gaps:** the game has no version string yet, so the log's header gives the date, world seed and game clock instead of a commit. One file per sitting, rewritten each time (deaths are listed inside it, not as separate files). Kills only count your pipe and your car, not turrets or spikes. The hints restart if you start another new game in the same sitting. Session logs are never uploaded anywhere: someone has to open the folder.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — M11 The world gets worse

**Built:**
- **Loot never comes back:** a searched container stays empty for good (it already worked that way; now there's a test).
- **Food spoils:** vegetables keep about 5 days (`spoil_days` in items.json), in your pockets and in crates, and rot into **rotten food**, which you can't eat. Fresh food you find in town from day 7 on is already rotten. Canned food, chips and soda keep forever, which is what the canner is for.
- **Stale gas:** on day 21 the gas left in the town's cars goes stale. Only gas you poured in yourself stays good, so siphoning dries up and generators eventually need another fuel source or solar.
- **Infamy:** a permanent score of all the noise you've made that the dead could hear: machine and generator noise reaching 50 m out, plus loud one-offs like the horn. It never cools off the way heat does; zombies' own bangs don't count. As it climbs, waves bring new kinds of zombie. **Runners** come at 3000 infamy (about a quarter of the wave), roughly a quarter of an hour of an unmuffled generator in the open. **Screamers** come at 8000 (about 1 in 8). Each one arrives with a warning message.
- **Runners:** they sprint at 3.6 m/s (shamblers do 1.3) but have 60 hp. They're smaller, dark-skinned and dark-clothed, and have a new **Run** animation.
- **Screamers:** when one spots you it stops and shrieks (a loudness-88 noise, then 25 s before it can again), and everything within earshot comes to investigate. They're pale with blood-red shirts, and have a new **Scream** animation and a high, warped moan.
- **Stats:** the pause menu shows the day, your deaths, zombies killed (by you, your turrets, traps or your car) and total noise made. Saved with the game.

**Rules (sim, tested):** `Director.infamy`/`unlocked`/`pick_type`, screamers in `ZombieBrain` (`screaming`), spoilage (`SimWorld._spoil`, `Inventory.spoil_debt`), `_rot_old_food`, `Vehicles.go_stale` (cars track the `fresh` gas you poured in), and kill and death `stats`. Data: runner and screamer in `zombies.json`, `infamy` in `noise.json`, `spoil_days` and `rotten_food` in items.json, and `gas_stale_day` and `found_food_rots_day` in survival.json. World: zombie looks and the Run/Scream animations in `ZombieBody`, the scream sound in `SoundView`, stats in the pause menu, and a new `--zombie-type=` flag.

**Tests:** `test_world_worse.gd` (loot stays gone, vegetables rot and canned food keeps, in crates too, late-found food is rotten, stale gas, infamy builds and never cools (the horn counts, wrecks don't), runners then screamers unlock, a screamer pulls in a zombie that couldn't see you, stats add up and are saved) and `test_zombie_types_world.gd` (runners run, screamers scream, the kinds look different). 978 checks.

**Try it on the PC:** merge, then double-click `play.bat`. To meet the new zombies straight away, run `play.bat --zombie=0,-10,2,-12 --zombie-type=runner` or `play.bat --zombie=0,-8 --zombie-type=screamer`. Press **Esc** to see your stats.

**Saves:** the save version is now 2. Saves from M9-M10c still load, and whatever they lack starts at its default (no stats, no infamy, fresh gas); a save from a newer game is refused.

**Known gaps:** rotten food has no use yet (compost for the planter would be a good one); only vegetables spoil; gas cans in pockets and crates never go stale; there's no infamy meter apart from the stats line; brutes, crawlers and listeners come later.

**Next:** M12, skills and carry weight (Mechanics already exists).

Built by Claude Opus 5.5.

## 2026-10-12 — M10c Wheels

**Built:**
- **Drivable cars.** The town has a sedan, a pickup, a van and another sedan (new Codex models, built by `tools/art/sedan.py`, `pickup.py` and `van.py`, with separate wheels that spin and steer). They have worn, rusty paint (a Codex texture mapped to the car, so it doesn't slide as the car moves) tinted per car, and see-through glass with a dashboard and steering wheel inside. Godot's `VehicleBody3D` does the physics (`CarBody`).
- **Driving:** look at the front or side of a car and press **E** to get in. **W/S** are gas and brake (hold S to reverse), **A/D** steer, **Space** is the handbrake, **H** the horn, **F** the headlights, **E** gets out beside the driver's door, and the mouse looks around the cab. The readout shows speed, gas, damage and what's wrong.
- **Noise:** a running engine is a continuous noise source as loud as a generator, so it draws zombies, and its sound revs with speed. The horn is very loud (95).
- **Fuel** is the same gas **G** siphons: siphoning strands a car, **R** pours gas cans back in, and driving burns gas by distance (plus a little idling). The tank's in gas cans; pickups are thirstier.
- **Keys, Zomboid style (Emmitt's call).** Every car has its own key: in the ignition, in the glovebox (search the car), in the nearest house, or lost. car_0's is always in its glovebox. Without it the engine won't start. **Hotwiring** (**R** in the car) needs **Mechanics 2**, takes 12 s (2 s less per level above 2, at least 4), makes a little noise, and stays hotwired. **Mechanics** levels by doing (`data/skills.json`): piece repairs, car repairs, mufflers, hotwiring. It shows in the inventory screen. This is the first M12 skill, brought forward.
- **Wrecks** (flat tyres, a dead engine, smashed) can be searched and siphoned but not driven. **Damage:** zombies hit the car, not you, while you're inside; running zombies over hurts them by speed and dents the car; **T** repairs a quarter for a metal plate and 4 nails.
- **The trunk** is searched from the back of the car (and moves with it). **Saved:** where each car is parked, its gas, damage, key and hotwiring, plus your Mechanics. Saving while driving loads you beside the car. Zombies path around a parked car (the navmesh is rebaked when you get out).
- **Footsteps** are redone: a soft, dull heel thud with a gentle scuff, much quieter (Emmitt: the old ones were "too loud and sharp"). Each sound now has its own random seed, so adding a sound never changes the others.
- **`play.bat` updates itself:** it fast-forwards a clean `main` checkout from GitHub before starting, so merging a PR is all you need to do. It skips other branches or local changes, and plays what you have if it's offline.

**Rules (sim, tested):** `Vehicles` (cars, fuel, keys, hotwiring state, ram damage, repair, engine noise, save), `Skills`, and in `SimWorld`: `enter_car`, `exit_car`, `car_moved`, `honk`, `hotwire`, `refuel_car`, `repair_car`, `car_hits_zombie`. `Loot.add_extra` (a key in a particular container). Data: `data/vehicles.json` and `data/skills.json`; the horn and wreck chance are in `noise.json` and `survival.json`. World: `CarBody`, plus driving in `main.gd`, car prompts in `Interactor`, engine and horn in `SoundView`, and `--drive[=car_N]`.

**Tests:** `test_vehicles.gd` (wrecks, getting in and out, fuel, engine noise and horn, out of gas, idling, siphon and refuel, zombies hitting the car, ramming, repair, save), `test_car_keys.gd` (key spots, glovebox search, ignition, hotwiring needs Mechanics 2 and is quicker with skill, Mechanics levels by doing, save), `test_driving.gd` (real physics: drives the way it faces, brakes then reverses, steers, no gas no go, parked cars stay put), `test_vehicle_models.gd`. 929 checks.

**Try it on the PC:** merge, then double-click `play.bat` (it pulls the update itself). Walk north up the street to the first car (a red sedan), look at its back, press **E** to search the trunk and you'll find its key. Then look at the side, press **E** to get in, and drive. `play.bat --drive` starts you in it (without the key: search for it, or level Mechanics by repairing things).

**Known gaps:** no crash damage from hitting walls or houses (only zombies dent it); no passengers; in a new game the van is a wreck (its engine won't turn over), the pickup's key is in its glovebox and the far sedan's is in its ignition; the zombie navmesh only updates when you get out, so zombies can bump into a car you're driving; you can't use the trunk as storage from the inventory screen yet. The sounds still need your ears: say if the engine or horn are off.

**Next:** M11, the world gets worse.

## 2026-10-12 — M10b Inventory screen

**Built:**
- **Tab** (or **I**) opens your pockets next to the nearest storage crate within arm's reach (3 m; arrows switch between crates if several are close). Every item shows its Codex-made icon and count. **Tab** or **Esc** closes it. You stand still while it's open, but the game keeps running, so a zombie can walk up while you sort.
- **Click** an item to see its weight and what it does (food, water, stops bleeding, or how much a bag adds to your carry limit), with buttons to **Use** it (eat, drink, bandage), **Move 1 / Move all** to the other side, or **Drop 1 / Drop all**. **Shift-click** moves the whole stack straight across; **ctrl-click** moves one.
- **Carry weight** shows at the top, with your best bag's bonus. It turns yellow near the limit and red when you're overloaded (slower and louder).
- **Dropping** puts items in a bag at your feet (into one already lying there if there is one), the same as a death bag: **E** picks it back up, and it's saved.
- The plan gained **M10c — Wheels**: drivable cars with better textures, loud engines, fuel shared with siphoning, wrecks, saved where you park.

**Rules (sim, tested):** `Inventory.move_to`, `SimWorld.use_item` / `can_use` (one particular item, not just the best one), `drop_items` (joins a nearby bag), `crates_near` (within `crate_reach`, nearest first). World: `InventoryScreen`, plus the new `--inventory[=ITEM]` screenshot flag.

**Tests:** `test_inventory_actions.gd` (moving, using, dropping, reach) and `test_inventory_screen.gd` (what the screen shows; shift-click and ctrl-click moves; use and drop; no crate in reach; bag limit). 785 checks.

**Try it on the PC:** merge, `git pull`, `play.bat`, walk up to the starting crate just east of where you spawn, and press **Tab**.

**Known gaps:** only storage crates appear on the right, not car trunks, fridges or ground bags (searching still drops loot straight into your pockets). There's no drag and drop yet, just clicks. The pipe isn't an inventory item yet.

**Next:** M10c — Wheels.

## 2026-10-12 — M10 Look and sound

**Built:**
- **Our own zombie** (`tools/art/zombie.py`): a rigged, animated low-poly townsperson (grey-green skin, torn work shirt, jeans, boots) that Codex built in Blender after Kaleb ruled the CC0 goblin "cursed". It has Idle, Walk, Punch, HitReact and Death animations. `ZombieBody` picks the animation from the brain's state and real speed (the walk speeds up and slows to match the feet), flinches when hit, and plays the death fall instead of tipping the body over. Each zombie gets its own shirt colour and a slightly different size.
- **Every building piece has a model now:** belt, bed, crate, door (hinge and handle on the right sides), barricade, spike strip, and a nail turret whose `Head` turns to aim. The Blender kit gained separate parts (`part()`, `SEPARATE`). Wrecked cars, fridges and cabinets in town are models too (`_dress()` in `main.gd` keeps the old colliders; missing models fall back to boxes).
- **Textures** (Codex photos, seamless via `make_tileable.py`, drawn by the new `Surfaces` helper): asphalt road, brick and painted-siding houses (every third house brick), a brick factory, dry grass and dirt ground, and corrugated scrap for built walls. A missing texture falls back to a plain colour.
- **Sound** (`SoundView`): every working machine and running generator hums with its own sound at its loudness in the noise system, so a muffler really makes it quieter and what you hear is what zombies hear. Footsteps (none while crouching, same as the noise system), pipe hits, wall bashes, doors and turret shots play from the sim's noise events. The wind turns into a colder howl at night. A hard limiter keeps a big factory from clipping. Zombies moan now and then (more often when chasing), grunt when they attack or get hit, and moan once when they die. Plus a pipe-swing whoosh, a build clunk and the flashlight click. All of these except the zombie voices are generated by `tools/audio/synth.py` (deterministic; loop points written into the WAVs). The zombie voices are a CC0 pack (`assets/CREDITS.md`).
- **Atmosphere:** fog thickens and darkens at night. On Forward+ (your GPU), volumetric fog makes the flashlight beam visible, machine lamps glow a little, and SSAO grounds things. The title screen now shows a foggy dusk view down the main street with a flickering title, and the HUD is hidden behind it. Starting a game switches straight back to your own view without touching the sim.
- **Item icons** for the coming inventory screen (M10b): all 16 items plus the pipe, made by Codex and cut out by `tools/art/make_icon.py` into `assets/icons/`.

**Tests:** new `test_sound_view.gd` (a working machine hums at its loudness, a muffler makes it quieter, an idle machine goes quiet, noise events play once), and `test_art_models.gd` now covers turret heads. The zombie-fall test checks the Death animation. Headless runs skip audio playback, because a sound still playing at quit is reported as a leak. 739 checks.

**Try it on the PC:** merge, `git pull`, then double-click `play.bat` for the new title screen. `play.bat --demo-factory` to hear machines (fit a muffler with **U** and listen), `play.bat --demo-defense` for the door, turret and spikes, and `play.bat --time=22` with **F** for the night fog. Use headphones for the moans and the wind.

**Known gaps:** the sounds were made by a script and checked by numbers, not by ear, so tell me which ones sound wrong. Houses are still plain textured boxes (no windows, doors or roofs). There's one zombie body (colour and size vary). The rigid-segment animation is stiff up close. Volumetric fog only shows on Forward+, so cloud screenshots look flatter.

**Next:** M10b, the inventory screen.

## 2026-10-12 — M9 Keep it

**Built:**
- **Title screen** when you double-click `play.bat`: Continue (your last save), New game, Settings, Quit.
- **Esc pauses** the game (time stops, mouse freed) and opens a menu: Resume, Save game, Load last save, Settings, Save and quit to title. Esc again resumes.
- **F5** quick-saves and **F9** loads the last save. The game also **autosaves every 5 minutes** of play, and when you quit to the title. There's one save slot. On the PC it's `%APPDATA%\Godot\app_userdata\Noise Floor\save.json`.
- **What's saved:** the time and day, your pockets and every meter (food, water, bleeding...), where you stand and look, everything you built (with damage, open doors, worn spikes), what's inside machines, on belts, in crates and turrets, generator fuel, the zombies (where they are and how hurt), the Director's heat, which containers you've searched, which cars you've siphoned, death bags, and the world seed. Loading rebuilds the town and puts all of that back.
- **Settings** (kept separately in `settings.cfg`, so they apply to every game): mouse sensitivity (0.2x-3x), volume (ready for when sounds arrive in M10), day length (24, 36, 48 or 72 real minutes per in-game day), fullscreen.

**Rules (sim, tested):** `SaveGame` (`src/sim/save_game.gd`) turns a `SimWorld` into JSON and back, with a version number so old saves are refused cleanly. World: `Menus`, `Settings`, `GameSession` (what survives a scene restart).

**Tests:** 634 checks. A busy base (machines mid-craft, items on belts, open door, damaged wall, turret ammo, crate contents, generator fuel, hurt zombie, heat, siphoned car, death bag, bleeding) survives a save → JSON text → load. **The loaded world then runs 30 s exactly like the original.** Searched containers stay searched; file write/read; other versions refused. Plus the real game scene: build, save, rebuild from the save, and find the wall, your position, facing and thirst; Esc pauses (time stops) and resumes.

**Try it on the PC:** merge, `git pull`, double-click `play.bat`. New game, build something, press F5, quit, start again and choose Continue.

**Known gaps:** one save slot (no named saves); zombies come back where they were but forget what they were doing; a save from an older version of the game won't load once the save format changes (it says so instead of crashing); volume has nothing to control yet.

**Next:** M10, look and sound: CC0 models (Emmitt to approve sources), machine hums and zombie moans, fog and flashlight atmosphere, a proper title screen.

## 2026-10-12 — M8 Defend

**Built:**
- **Door:** takes a wall's place on an edge (2 m gate). **E** opens or closes it, with a little noise. Open, it lets you through, and zombies too; the navmesh re-bakes so they path through it. Shut, it blocks and muffles like a wall, and zombies beat it down like one.
- **Barricade:** a cheap, low board wall (1.3 m). Zombies have to break it, it muffles sound, but turrets shoot over it.
- **Spike strip:** goes on bare ground (no foundation). A zombie on it moves at 40% speed and takes 8 damage a second. The strip wears down by the damage it deals (100 hp, so about 12 seconds of one zombie). You walk over it fine.
- **Nail turret:** on a foundation. **E** loads nails (from pockets or crates in range), or feed it with a belt from any side. Every 0.6 s it shoots the nearest zombie within 15 m that it can see: walls and closed doors block it, barricades don't. 25 damage a nail (4 nails per shambler). Each shot makes a quiet noise (35). A zombie it hits comes for the turret. The head swings to aim and shots leave a brief tracer.
- **Repair:** look at anything you built and press **T**. It costs that piece's build cost times the share of hp missing (at least 1 of each), from pockets and crates in range. Walls, doors, floors and every object now show their hp when damaged.
- Build pieces now go 1 foundation, 2 wall, 3 door, 4 barricade, 5 belt, 6 smelter, 7 press, 8 rain collector, 9 purifier, 0 planter; the mouse wheel reaches the rest (canner, bed, crate, generator, solar, pole, spikes, turret).

**Rules (sim, tested):** `Defense` (`src/sim/defense.gd`) for traps and turrets, turret magazines in `Factory` (belt-fed), doors, edge kinds and repair in `BuildGrid`, open doors and barricades in the noise and sight wall counts, zombie slow and trap damage in `ZombieBrain`.

**Tests:** 590 checks. Doors and barricades follow wall rules, door open/shut changes sound and tells the world, barricades block sound but not turret sight, spikes slow, hurt, kill and wear out, a turret picks the nearest, kills two zombies with 8 nails and makes quiet noise, can't shoot through walls, makes its target come for it, takes nails from a belt, repair costs and refusals, zombies breaking a closed door, plus a physics run: shut door blocks you, E opens it, you walk through, and spikes don't block you.

**Try it on the PC:** merge, `git pull`, `play.bat --demo-defense`. Walk to the far side and watch zombies come up the street onto the spikes and get shot over the barricades. Press T on anything they damaged.

**Known gaps:** only the nail turret (crossbow, rifle and shotgun turrets come with M15), only spike traps, no stairs or windows; turrets don't need power; a door is a full-width gate, not a doorway in a wall.

**Next:** M9, keep it: save and load, main menu, settings (mouse sensitivity, volume, day length), pause.

## 2026-10-12 — Machine art (Codex, not a milestone)

**Built:** real models for every machine and power piece (press, smelter, rain collector, purifier, planter, canner, generator, solar panel, power pole) plus concrete foundations, all made on Emmitt's PC with Codex on his ChatGPT plan (no API key).
- **Models:** each `tools/art/<id>.py` is a deterministic Blender 5.1 script that Codex wrote on the shared `tools/art/kit.py`. The kit gives one palette, merges each model into one mesh (one draw call per material), stands it on the floor of its collision box, checks that it fits, turns it to face the game's -Z front and exports `assets/models/<id>.glb`. Rebuild one with `"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup --python tools/art/<id>.py`.
- **Conventions:** machines and generators carry a `Lamp` that `BuildView` hands to `FactoryView` with its own material, so status colours still work. Item machines show their input in INPUT_BLUE paint at the back and their output in OUTPUT_ORANGE at the front, replacing the old placeholder panels. Colliders didn't change.
- **Concrete:** a Codex photo made seamless by `tools/art/make_tileable.py` (plus a normal map), drawn world-space triplanar with one tile per 2 m cell.
- **Tests:** `test_art_models.gd` checks that every model loads, fits its box, stands on the floor, is merged into one mesh, has a lamp where needed, faces the right way (orange at -Z, blue at +Z; this caught every model facing backwards before the kit fix) and gets an unshared lamp material. 656 passed.

**Try it on the PC:** `play.bat --demo-factory` (smelter, press, generator, pole) and `play.bat --demo-farm` (rain collector, purifier, planter, canner, solar panel).

**Known gaps:** belts, walls, beds, crates and the M8 defences are still boxes. Textures import lossless with mipmaps; switch to VRAM compression after checking the cloud renderer. Codex and Blender exist only on the PC, so cloud sessions use the committed files and can't make new art. New pieces need a `tools/art/<id>.py` made on the PC (see the kit docstring) and an entry in `BuildView.MODELS`.

**Next:** M9 continues in the cloud; art for walls, belts and the defences can follow in M10.

## 2026-10-12 — M7 Power

**Built:**
- **Machines need power now:** the smelter (40 W), press (30 W), purifier (20 W) and canner (30 W). The rain collector and planter don't. A machine with no power shows a red lamp and "no power".
- **Generator** (build key, or wheel to it): 100 W, very loud (80, the design doc's example). Load it with gas cans (E). It only burns fuel in proportion to what's being used, and goes silent when nothing needs power, so turning machines off at night really does quiet the base. It takes a muffler (U) like machines do. Removing one gives back its full cans.
- **Gas:** press **G** on a car to siphon 1-3 gas cans (fixed per car by the world seed; once only; a little noise). Gas cans also turn up in car trunks and factory crates, and the starting crate has 3. They weigh 4 kg each.
- **Solar panel:** 60 W times the daylight, **completely silent**, nothing at night. Solar power is used first and generators cover the rest. This is the first quiet power source.
- **Power poles** stand on bare ground (no foundation) and link anything within 12 m, poles included. Other powered pieces link to anything right next door (3 m). Wires are drawn between linked pieces.
- **Brownouts:** if a network's machines want more than it makes, everything on that network stops and generators stop burning. The HUD shows "network: X W made / Y W wanted" and BROWNOUT when you look at anything powered.

**Rules (sim, tested):** `PowerGrid` (`src/sim/power_grid.gd`): networks (union-find), supply/demand per network, brownouts, solar-first load sharing, fuel burn, generator noise sources, muffler, refunds. Car fuel and siphoning in `SimWorld`. Numbers live in `data/buildables.json` (watts, watts_out, fuel, burn_time, reach) and `data/survival.json` (siphon noise, fuel per car).

**Tests:** 535 checks. Machines idle without power and planters don't care, a neighbour generator powers a smelter at 40% load and burns 0.4 s of fuel per second, an idle generator is silent and burns nothing, a muffled generator reads 65, poles bridge 20 m and removing one cuts power, 110 W on a 100 W generator browns everything out (and burns nothing) until the press goes, solar at noon runs a smelter, gives nothing at night and takes load off a generator at dusk, siphoning (range, once only, noise, same per seed), generator refunds, and poles needing no foundation. Older noise and factory tests run with free power.

**Try it on the PC:** merge, `git pull`, `play.bat --demo-factory` (now with a generator and pole). Look at the generator, then watch the heat with `--noise-overlay`. `play.bat --demo-farm` has a solar panel; wait for night and watch the purifier and canner stop. Siphon cars up the street with G.

**Known gaps:** no batteries or switches (a generator runs whenever something needs power); you can't choose which pole links where (it's automatic by distance); wires don't block or get cut; no wind power yet.

**Next:** M8, defend. Doors, barricades, traps, a nail turret fed by the press, structure HP and repair.

## 2026-10-12 — M6 Survive

**Built:**
- **Needs:** food, water and energy drain over time (water fastest, about a game day from full to empty). At empty food or water you lose health. **Z** eats your most filling food and **X** drinks your best drink; rainwater has to be purified first.
- **Stamina:** sprinting and swinging use it, and it comes back after a second's rest. Out of stamina: no sprint, no swing.
- **Bleeding:** zombie bites sometimes cause it (30%) and it drains health until you press **H** with a bandage.
- **Beds:** build one (**0** in build mode) and press E on it to sleep. Time runs about 8x faster while you sleep, any key or a hit wakes you, and the bed becomes where you respawn.
- **Carry weight:** every item has a weight. You can carry 20 kg, plus the best bag you have (school bag +8, hiking pack +18, military rucksack +25). Over the limit you're slower, tire faster and your footsteps are 10 louder. Over 150% you can't sprint. The HUD shows pockets and kg top right.
- **Scavenging:** a cabinet or fridge outside every house, every car's trunk and three crates by the factory can be searched (E, about 2.5 s, stay close, a little noise). Loot rolls from `data/loot.json` and never respawns.
- **Storage crates:** the starting kit now sits in a crate next to where you start. Building and hand-feeding machines use your pockets, then any crate within 30 m. Removing things refunds into the crate. E on a crate puts away building materials (food, drink, bandages and bags stay with you). A wrecked or removed crate spills its contents in a bag.
- **New machines:** rain collector (rainwater every 20 s from nothing; nearly silent), purifier (rainwater → clean water, 4 s, loud), planter (seeds + rainwater → 3 vegetables in 60 s; quiet), canner (2 vegetables + 1 metal plate → 2 canned food, 5 s; loud). Build keys go 1-9 and 0, and the mouse wheel cycles through all 11 pieces.

**Rules (sim, tested):** `PlayerStats` (all meters, stamina, bleeding, sleep, carry effects), `Loot` (tables, searching), `Stock` (pockets + nearby crates), storage, beds and respawn points in `SimWorld`. Numbers in `data/survival.json`, `data/loot.json`, `data/items.json` (weights, food/water values, bags), `data/recipes.json`.

**Tests:** 463 checks. Drain rates, starving, eating and drinking choices, stamina drain/recovery and swing cost, bites causing bleeding and bandages stopping it, sleeping and waking, respawning at the bed, weights and bag limits, overload slowing/louder steps/no sprint, building from a crate in range but not out of range, deposits, wrecked crates spilling, loot rolls staying in range and repeating with the seed, search timing, walking away cancelling a search, the water chain (3 clean water in ~65 s) and food chain (2 seeds → 6 vegetables → 6 cans), plus a physics run of searching, storing and sleeping with E, and Z/mouse-wheel through the real game.

**Try it on the PC:** merge, `git pull`, double-click `play.bat`. Walk up the street and press E on fridges, cabinets and cars. `play.bat --demo-farm` builds the water and food lines.

**Known gaps:** no inventory screen yet (Z/X/H pick the best item automatically; you can't drop or move single items); crates only take materials in, not out; loot containers stand outside houses because the houses have no insides yet; no sickness from rainwater; sleeping is 8x speed rather than an instant skip.

**Next:** M7, power. Generator, fuel siphoned from cars, poles and wires, brownouts, first quiet power source.

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
