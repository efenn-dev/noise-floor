# Devlog

Newest first. One entry per milestone: what was built, how to try it, known gaps, next.

## 2026-10-13 — P2 Gun feel and screens

From the P2 brief by the project lead, on top of M15 (PR #30). A small polish pass: no new content, no tuning.

**Built:**
- **One roll, not two.** A shot used to need the ray inside the spread cone to meet a zombie *and then* a hit-chance roll by distance, which felt harsh (a scoped rifle could land the ray and still "miss"). Now the cone is the only roll: what the ray meets is hit. Everything that used to change the hit chance now changes the cone instead: **Firearms** (3% tighter a level, as before), the **scope** and "+% accuracy at range" rolls (a gun with +60% range has a cone 1/1.6 as wide), **recoil** (each shot widens it, it settles back in a second or two) and **distance** (the same cone covers more ground further out: a pistol's cone is about 0.4 m across at 10 m and 1.7 m at 40 m, so far shots still mostly miss).
- **A crosshair.** With a gun in hand four small ticks replace the centre dot. Their gap is the cone's real size on screen, so it opens after each shot, closes as you steady, and is tighter with a scope, with Firearms levels, or zoomed in. With the pipe in hand you get the old dot back. It never catches the mouse.
- **Scope zoom.** Hold **right click** with a scoped gun in hand to zoom in (75 to 35 degrees); let go to zoom out. Without a scope right click does nothing (in build mode it still removes pieces). The scope's tighter cone is always on, zoomed or not, so the zoom is for seeing.
- **The skills screen fits small windows.** The three perk trees now sit side by side, each with its perks' text wrapped to its column, and each tree (and the skills list) scrolls if the window is too short. It reads at 1280x720 as well as 1600x900, with six Fighter perks.
- **`noise.refresh` is back to its old cost.** The M15 stress run measured it at about 448 us a tick against 82 before. The cause was M12's Dampened Gears: every working machine and every running generator asked the skills for its "machine quiet" bonus, and that question walks all ten skills, every perk and (since M13) all your gear and gear sets. With 50 machines that was 50 walks a tick. It is now asked once a tick. Stress run on Emmitt's PC after the fix: **95 us** (town + 200 zombies), 94 (empty map), 96 (town + 20); average tick 3.2 ms (was 3.8), worst 11.4 ms. Turrets, furniture and the cache invalidation were not the cause (the empty map, with no town and no turrets, measured the same 446 before).
- Two new game flags for screenshots: `--aim` (fits a scope and holds the zoom) and `--window=1280x720` (a smaller window).

**Rules (sim, tested):** `Gunplay`: `hit_chance()` is gone; `sight_mult()` (base gun range / this gun's range, 0.1-1) now multiplies `spread_deg()` with `spread_mult()` (Firearms) and the recoil bloom; `cone_radius(distance)`; `scoped()` (a working sight part on the gun in hand). `SimWorld.shoot_zombie(id, head)` no longer takes a distance or rolls: a live zombie the ray met is hit. `data/guns.json` loses `hit_chance`. The Firearms skill's text no longer mentions hit chance. `NoiseField.refresh` and `PowerGrid.noise_sources` ask `Skills.bonus("machine_quiet")` once a tick (`machine_loudness(m, quiet)` takes it as an optional argument). World: `Crosshair` (new, `src/world/crosshair.gd`), `Shooter` (the `aim` action on right click, `aiming()`, `hold_aim`, the FOV zoom), `SkillsScreen` (trees in columns, scrolling, `fit()` on open and on a window resize), `InputSetup` (`aim`), `main.gd` (crosshair or dot, `--aim`, `--window`, "RMB scope" in the key hints).

**Tests:** `test_guns.gd`: the hit-chance test and the "mostly misses at 40 m" roll are gone; new: every shot the ray lands at 40 m hits (200 of 200), the cone is 4x as wide at 40 m as at 10 m, a dead or missing zombie can't be hit; Firearms 5 gives a 15% smaller cone than Firearms 0, a scope makes it 1/1.6 as wide, a shot's recoil grows the scoped cone and it settles back, a rifle's cone is far tighter, a holstered gun is never scoped. `test_guns_world.gd`: right click without a scope leaves the FOV at 75, with a scope it zooms to 35 while held and comes back on release, `--aim` holds it, the pipe in hand drops it; in the real game scene the crosshair is hidden and the dot shown with the pipe, the crosshair (and its ticks) ignore the mouse, a gun shows the crosshair and hides the dot, its gap matches the cone on screen, opens after a shot and closes as it settles. `test_skills_screen.gd`: at 1280x720 with six Fighter perks the panel fits the window, the three tree columns and the skills column sit inside it without overlapping, every perk row fits its column's width and doesn't overlap the one above, and a taller window gives the trees more room. **4371 checks** (was 4285).

**Try it on the PC:** merge, then in a terminal in the game folder:
- `play.bat --gun --time=12`: the crosshair. Fire a few quick shots at the street and watch it open, then close as you steady. Press **Q** for the pipe: the dot comes back.
- `play.bat --gun=rifle --aim --time=12`: a rifle with a scope fitted, held zoomed in (`--aim` holds the zoom for you). For the real thing, `play.bat --workbench --time=12`, fit the scope at the bench, close it, then hold **right click**.
- `play.bat --skills --window=1280x720`: the skills screen in a small window; scroll the Fighter tree with the mouse wheel.

**Known gaps:**
- Mouse look is not slowed while zoomed, so aiming at 35 degrees feels twitchy. Worth a look at the playtest.
- The zoom doesn't tighten the cone further: the scope's tighter cone applies whether or not you zoom. Decided so hip-firing a scoped gun didn't get worse; change it if the playtest wants "aim down sights" to matter.
- The crosshair is a fixed white; it doesn't turn red over a zombie or show a hit marker.
- The skills screen's columns are fixed widths (350 and 3 x 250 px), so on a very wide window it doesn't spread out, and below about 1220 px wide it would run off the sides.
- Every other gap from the M14 and M15 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M15 Automated defense

From the M15 brief by the project lead, on top of M14 (PR #29).

**Built:**
- **Turrets fed by belts and hoppers.** A belt ending at a turret pushes its ammo in (as since M8, from any side), and E still loads it by hand. A new **ammo hopper** (4 planks + 6 nails, on a foundation) holds up to 100 rounds of one kind and feeds the turret on the cell in front of it, one round a tick; E loads it from your pockets and crates, and a belt can top it up.
- **Two new turrets.** The **crossbow turret** shoots **crossbow bolts** (the Press's new recipe: 1 plate makes 6): near silent (20), slow (one every 2 s), 60 damage, 20 m. The **rifle turret** shoots M14's **standard rounds**: loud (85), 50 damage every 1.5 s, 35 m, and it needs **20 W** of power. Shots still go through the noise system, so loud defense draws more dead.
- **Suppressors and scopes on turrets.** E on a turret with one in your pockets fits it: an oil-filter suppressor takes the rifle turret from 85 to 65 (the machined one to 55) and wears 0.5% a shot as on a gun; a scope adds 60% range. Pulling the turret down gives them back.
- **Sensors and one action each.** A **motion sensor** sees zombies within 12 m (walls and closed doors block it); a **noise sensor** hears one-off sounds of 30 or more within 20 m (not your machines' hum, not the noisemakers). **E** opens a small screen to pick its action: **quiet mode** (every machine and generator on the sensor's power network stops until it clears, plus 30 s), **floodlights** (every floodlight within 20 m comes on, at night only), **decoy** (every charged noisemaker within 60 m goes off) or **lock doors** (every door within 12 m shuts and E can't open it until 10 s after it clears).
- **Floodlight** (10 W, a pole with a lamp): lit only at night, by a sensor or set to light every night with E. Standing within 10 m of a lit one counts as having your flashlight on: zombies see you from further. **Noisemaker** (15 W, a box with a horn): once set off (by a decoy sensor, or E) it blares at 90 for 20 s, then needs 60 s of power to recharge. Zombies that hear it go there instead of your walls, and wreck it if they reach it.
- **Base log and radio.** The sim keeps the last 50 events with the game time: turret kills, a turret out of ammo, your walls, doors and machines under attack ("West wall under attack: 6 zombies", at most once per 30 s each) or destroyed, sensors going off and what they did, noisemakers, bear traps and tripwires, the repair station's work, waves arriving and Old Pete on the move. **L** (or **Base log** in the pause menu) opens it. A **handheld radio** (in the starting crate) in your pockets turns any event more than 40 m from you into a HUD line ("Radio: Nail turret out of nails").
- **Traps.** **Bear trap** (2 plates + 4 nails, on bare ground): the first zombie into its cell takes 10 and is pinned for 15 s; then it's sprung until you reset it with E. **Tripwire bell** (an edge piece, 2 nails + 1 scrap): a zombie crossing it rings it at 60 and sets off every sensor within 20 m. **Electric fence** (an edge piece on a power network, 15 W): a zombie touching it is stunned for 3 s (no walking, no biting) and takes 10; in a brownout it does nothing.
- **Repair station** (20 W, a machine body): takes **wall panels** by hand or from a belt (the Press's other new recipe: 2 plates make 1 panel) and every 10 s gives 50 hp back to the most damaged wall, door, barricade or fence within 12 m.
- **The Director's cache** (from the stress report): each continuous sound's outdoor wall count is kept until the build grid changes (a piece added, removed, opened or broken), so the once-a-second heat check no longer walks 8 x 50 m per machine. Same heat numbers as before.
- `--demo-defense` now also has a hopper behind the turret, two floodlights (set to light every night), a motion sensor on decoy, a noisemaker 30 m east on a pole line, a generator, a bear trap and two tripwires.
- **Models:** no Blender runs. The crossbow and rifle turrets reuse the nail turret's model with a bow or a long barrel added to the head in code; the floodlight is the power pole with a lamp box; the repair station is the purifier's body with a stack of panels on top. The hopper, sensors (a lamp that goes red when triggered), noisemaker (a lamp that flashes while it blares), bear trap, tripwire and fence are plain coloured boxes with a few parts. Bolts, wall panels and the radio have no icons yet.

**Rules (sim, tested):** `data/defense.json` (new): hopper cap and what it feeds, turret part slots, sensor check interval and noise threshold, the four actions (name, hold, radius, the screen's text), floodlight light radius, noisemaker blare, recharge and pulse, bear trap pin, tripwire trigger radius, fence stun and reach, repair station panels and hp, log size and attack throttle, radio range. `data/buildables.json`: the 11 new pieces (turret numbers stay here). `Factory`: `Turret.id` and `parts`; `Bin` (hoppers and repair stations: one item, a cap, fed by hand or belt); a hopper hands one round a tick to the turret in front. `PowerGrid`: any powered piece is a consumer (`wants`, `is_powered`); sensors join networks; `switched_off` for quiet mode. `Defense`: turret power, parts (`turret_stats`) and suppressor wear, bear traps (`sprung`, `reset_trap`), tripwires (`bells`), fences, repair stations, `most_damaged`, and a per-kind key cache so traps don't scan every piece each tick. **`Automation`** (new): sensors (`sense`, `set_action`), the actions, floodlights (`lit_positions`, `in_light`), noisemakers (`fire_noisemaker`), locked doors. **`BaseLog`** (new): entries with game time, `add_once` throttling, directions from the middle of your base. `ZombieBrain`: `pinned` (can't walk) and `stunned` (does nothing). `NoiseField`: `outdoor_walls`; a stopped machine (brownout, quiet mode) is silent. `Director`: the wall-count cache (`watch(build)`, `recounts`). `BuildGrid`: tripwire and fence are edge pieces that stand on bare ground and block neither sound nor sight; sensors, floodlights, noisemakers and bear traps stand on bare ground. `SimWorld`: wiring, `turret_interact`, `set_sensor_action`, `toggle_floodlight`, `fire_noisemaker`, `reset_trap`, locked doors in `toggle_door`, the radio, wall-hit, destroyed, wave and Old Pete log entries; the start crate gets a radio. **Saves:** `SaveGame.VERSION` is 9: turret parts, hoppers and repair stations (`bins`), sensors with their actions, floodlights' night setting, noisemakers, locked doors (`automation`), sprung traps and the base log. `test/fixtures/save_v8.json` was written by the M14 code before these changes and loads with none of these; the older fixtures still load.

World: `SensorScreen` and `BaseLogScreen` (new), `DefenseView` (new: floodlight spotlights and lamps, sensor and noisemaker lamps), the new pieces in `BuildView` (walk-over layer for bear traps and tripwires) and the build menu (mouse wheel, after the workbench), `Interactor` prompts and E actions for each, `L` in `InputSetup`, a "Base log (L)" pause button, `SoundView` plays the horn for a noisemaker and a click for a tripwire bell.

**Tests:** `test_automated_defense.gd` (a belt feeds a nail turret and it kills with those nails; the hopper loads 100, feeds one a tick, holds one kind, takes a belt; the crossbow's 60 / 2 s / 20 m / 20 and the rifle's 50 / 1.5 s / 35 m / 85, the rifle turret silent without power and drawing 20 W with it; a suppressor on a rifle turret: 65 loud, 0.5% wear a shot, a scope 56 m, parts back when it's pulled down; a motion sensor sees a zombie, quiet mode stops the generator and smelter and silences them, logs it, and they're back 30 s after it clears; walls block a motion sensor; a noise sensor's range and threshold; a decoy sensor sets off a noisemaker that pulls an investigating zombie away from a wall, blares 20 s at 90, then recharges 60 s; lock doors shuts a door, E can't open it, it opens 10 s after; floodlights dark and drawing nothing by day, lit and drawing 10 W at night, you stand in their light; the base log records a wall hit once with the game time and a turret kill, keeps 50; the radio calls out a turret out of nails 200 m away but not 10 m away, not without a radio, and the start crate has one; a bear trap pins for 15 s, catches nothing sprung, resets; a tripwire rings at 60 and sets off a sensor that can't see the zombie; an electric fence stuns and hurts, and does nothing in a brownout; the repair station spends a panel for 50 hp every 10 s, takes panels from a belt; the Press's bolts and panels; the Director's cached gain equals the uncached one, isn't recounted when asked again, and is after a wall goes up; save and load keeps sensor actions, floodlight setting, hopper nails, turret ammo and suppressor, sprung traps and the log; the version-8 fixture loads with none of it and the older fixtures still load), `test_automated_defense_world.gd` (the sensor screen lists four actions and a click picks Decoy; the base log screen lists newest first with times; every new piece gets a body, walk-over ones on the trap layer, the rifle turret's barrel, a lit floodlight's spotlight). `test_gear.gd` (the Press now cycles through bolts and panels), `test_guns.gd` (saves are version 9 now) and `test_art_models.gd` (the floodlight is a pole with a crossbar) updated. **4285 checks** (was 3995).

**Stress (`tools/stress.sh`, this PC, 4 game hours from 19:00):** worst tick 20.0 / 23.0 / 23.2 ms before (the 2026-10-13 report) and 11.7 / 11.2 / 9.7 ms now (town + 200 zombies / empty map + 200 / town + 20); average 4.63 -> 3.78 ms with the town and 200 zombies. `gain_now` costs 26 us from the cache, and 930 us when it has to recount everything (10,410 us before: the 8-direction walk now also stops at the first open side). The script has a new "gain_now us (recount)" column. Not looked into: `noise.refresh` measured 448 us here against 82 us in that report (M12-M14 sit between the two runs).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- The defended base at night: `play.bat --demo-defense --time=22`. Walk round to the barricade side: two floodlights, the turret with a hopper of nails behind it, spikes, a bear trap and two tripwires. Wait for the street zombies; look at the motion sensor (a short pole with a box, just west of the walls): its lamp goes red and the noisemaker 30 m east starts blaring. Press **L** for the base log.
- The sensor screen: `play.bat --demo-defense --time=12 --sensor-screen` (or E on any sensor). Click an action.
- The base log screen: `play.bat --base-log --time=12` (it fills in some example events).
- Build your own (B, mouse wheel past the workbench): crossbow and rifle turrets, hopper, motion and noise sensors, floodlight, noisemaker, bear trap, tripwire, electric fence, repair station. The Press (R on it) now also makes crossbow bolts and wall panels. Walk 40 m away from your base with the radio in your pockets (take it from the starting crate) and wait for the HUD's "Radio:" lines.

**Known gaps:**
- Not in M15, as planned: outposts (M17), the shotgun turret (there's no shotgun yet), turrets aiming at the player, and anything needing Codex (icons for bolts, wall panels and the radio).
- No new models (see Models above); a proper bell sound isn't synthesized yet (the tripwire uses the click).
- Turrets still take ammo from a belt on any side, not only the back (kept from M8, so old belt layouts keep working). The rifle turret takes standard rounds only (no subsonic).
- A part comes off a turret only by pulling the turret down. Parts on a turret don't show on its model.
- The noise sensor ignores continuous hums (machines, generators, engines) and the noisemakers' blare, so a sensor next to your factory doesn't keep switching it off, and a decoy can't set itself off.
- A noisemaker's blare is a string of one-off sounds (zombies hear it and come to wreck it; it adds to infamy), not a continuous source, so it doesn't add Director heat and the Director's waves still head for your loudest machine. Decided so one decoy at night doesn't summon a horde on its own; worth a look at the playtest.
- Floodlights make you "lit" within 10 m (like your flashlight); they don't light zombies up for turrets (turrets see in the dark already).
- Fences and tripwires on bare ground stand at foundation height, so they float 10 cm. Zombies bash a fence like a barricade; it blocks neither sound nor sight.
- Directions in the base log are from the middle of everything you built, so a town-sized base gives coarse directions. Only pieces you built are logged as under attack.
- Every number in `data/defense.json` and the new pieces is a first guess. Tune after the playtest.

**Next:** Playtest #1; then M16 seasons after the playtest.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M14 Guns

From the M14 brief by the project lead, on top of W1c (PR #28).

**Built:**
- **Two guns, both gear:** a **pistol** and a **hunting rifle**, in a new **gun** slot (the weapon slot stays melee). **Q** swaps what's in your hands, pipe or gun; the top-right HUD line says which ("Gun: Pistol 7/8 standard rounds (Q: Pipe)"). Raising a gun takes a moment (pistol 0.35 s, rifle 0.8 s).
- **Guns are loud.** Pistol 85, rifle 95: louder than a generator. A shot is a one-off noise where you stand, so it carries across town (a zombie 400 m away comes to look), raises the Director's heat and your infamy like any other sound.
- **Shooting:** left click fires. The game shoots a ray from the camera inside a cone as wide as the gun's spread; if it meets a zombie, the chance to hit falls with distance (pistol: half the time at 18 m, nearly always close up; rifle: half at 50 m). Headshots double. Each shot kicks the spread wider (recoil), and it settles back in a second or two. A brief muzzle flash, a recoil kick on the camera, and new shot sounds.
- **Magazines and ammo:** pistol 8 rounds, rifle 5. **R** reloads when you're on foot with a gun in hand (in a car R still refuels and hotwires; looking at a Press it still switches the recipe). Rounds are a stackable item per type: **standard**, **subsonic** (15 quieter, 25% weaker) and armour-piercing (in the data, does nothing yet). With no rounds of the loaded type, or a full magazine and another type in your pockets, R switches type and gives back what was in it.
- **Parts (gear, carried in pockets, fitted at a workbench):** muzzle (**oil-filter suppressor**: 20 quieter, wears 0.5% a shot; **machined suppressor**: 30 quieter, barely wears), **extended magazine** (+50% rounds), **scope** (+60% accuracy at range), **padded stock** (35% less recoil). Parts roll rarity and gun stats like other gear (+5-20% gun damage, 2-6 quieter shots, +5-20% accuracy, 5-20% less recoil). A gun's numbers are its base plus its parts, shown in Tab and at the bench.
- **The workbench:** a new piece in build mode (the last one, 6 planks + 10 nails). **E** opens it: your gun and its four part slots (click a slot to take a part off), the parts in your pockets (click to attach), and what it makes by hand from your pockets and crates nearby: **10 standard rounds** (10 casings + 1 scrap), **10 subsonic rounds** (10 casings + 2 scrap, needs Gunsmith), the **oil-filter suppressor** (3 scrap + 6 nails), the **machined suppressor** (4 plates + 2 scrap + 10 nails, needs Gunsmith) and a **padded stock** (2 planks + 6 nails).
- **The factory supplies the armoury:** the Press has a third recipe, **ammo casings** (1 metal plate → 10 casings, 3 s); R on a press cycles nails → repair kits → casings.
- **Firearms levels now:** 1 xp a shot, 3 a hit, 6 a kill; each level makes your spread 3% tighter. **Three new Fighter perks:** **Steady Hands** (8% less recoil a rank), **Quick Hands** (reloads 10% faster a rank) and **Gunsmith** (rank 1 unlocks subsonic rounds and the machined suppressor; each rank makes suppressed shots 2 quieter).
- **Where guns turn up:** car trunks (5% a gun, pistols three times as often as rifles, 2% a part, 25% a handful of standard rounds), factory crates (15% a part, 30% rounds), and a 2% Police-tier gun or part in any search. **Old Pete's Deer Rifle** (gold: +15-30% gun damage, +1-2 to Fighter perks, 5-10 quieter, and a threaded barrel: suppressors on it wear half as fast) is a **second drop from Old Pete**, with 10 rounds, in the same bag as his axe.
- **Models:** `tools/art/pistol.py` and `tools/art/hunting_rifle.py` (kit models, flat colours) held in view at the lower right like the pipe.

**Rules (sim, tested):** `data/guns.json` (new): gun bases (damage, range, spread, recoil, settle, handling, magazine, loudness, cooldown, reload, knockback, wear per shot, sound), part slots and parts, ammo types, hit-chance clamp, finds per loot table, the police find, gun and part weights, Old Pete's extra drop. `data/gear.json`: slot `gun`, gun and part bases, five gun-only stats (with `"slots"`; ordinary gear never rolls them and ordinary finds never roll guns or parts, so M13's seeded rolls are unchanged), the unique. `GameData` loads and validates guns.json, workbench recipes (`station`, `perk`, `gear` out), the `workbench` kind. `Gear`: gun pieces carry `parts`, `loaded`, `ammo`; `gun_stats(piece)` is the one query for base + tier + own rolls + working parts (the rules, the inventory screen and the workbench all read it); `attach`/`detach`, `wear_shot`, `roll_gun_piece`; gun-only stats never count in `bonus()`. **`Gunplay`** (new, `src/sim/gunplay.gd`): hands, raise time, cooldown, recoil bloom and settle, `spread_deg`, `hit_chance(d)` = 1 - 0.5 (d / reach)^2 clamped to 5-97% (reach = range / Firearms spread multiplier), `shot_loudness` (gun + parts + ammo - Gunsmith on suppressed shots), `damage`, reloads and ammo switching, the HUD line. `SimWorld`: `swap_hands`, `fire` (round, bloom, wear, noise through `noise.emit` minus Night Shift's quiet_all, Firearms xp), `shoot_zombie(id, head, distance)` next to `hit_zombie`, `reload` (a 15-loud click), `attach_part`/`detach_part`, `bench_recipes`/`can_bench_craft`/`bench_craft`, `_search_guns` (its own seeded stream), Old Pete's second drop. **Saves:** `SaveGame.VERSION` is 8: guns with their parts, rounds and ammo type ride inside `gear`, plus `hands`. `test/fixtures/save_v7.json` was written by the W1c code before these changes and loads with an empty gun slot; the older fixtures still load.

World: `Shooter` (new) does the raycast in the spread cone, the headshot test, the gun models, muzzle light and kick; `Melee` stands down while the gun is out; `WorkbenchScreen` (new); `Interactor` opens it on E and reloads on R; `InputSetup` adds Q (`swap_hands`); `SoundView` plays `shot_pistol`, `shot_rifle`, both suppressed, and `reload`, made by `tools/audio/synth.py` (new `--only` flag, so the other sounds weren't regenerated).

**Tests:** `test_guns.gd` (guns.json validates and a broken gun base is caught; base + parts: magazine 12 with the extended mag, range x1.6 with a scope, recoil x0.65 with the stock, 65 with the crude and 55 with the machined suppressor, Police x1.25, rolled gun stats count once; loudness 85 / 65 / 50 with subsonic / 46 with Gunsmith 2, and nothing off an unsuppressed shot; hit chance near 1 close up, 0.5 at range, floor 5%, higher with Firearms 5 and a scope; spread grows with each shot, settles back, kicks less with a stock and Steady Hands, 30% tighter at Firearms 10; empty click, reload time and rounds from pockets, top-up, type switch, Quick Hands, rounds back when the extended mag comes off, Q and raise time; wear 0.2% and 0.5% a shot, a worn-out suppressor stops working, a threaded barrel halves it; a pistol shot is heard 400 m away and raises infamy, a suppressed subsonic one 25 m away but not 60 m; damage, headshots, Firearms xp for shots, hits and kills, mostly misses at 40 m; workbench cost, recipes, the Gunsmith gate; the Press makes casings; trunk and crate finds, rifles rarer, Police finds, same seed same find, guns roll only gun stats; Old Pete's rifle and its stats; save and load keeps guns, parts, wear, rounds, ammo and hands; the version-7 fixture loads with no gun), `test_guns_world.gd` (physics: a pistol fired from the camera at a placed zombie kills it in a few shots; the model shows only with the gun out, a shot at the sky misses, the camera kicks and settles, R through the interactor reloads; both models load and are long front to back; every shot kind has its sound; the workbench screen attaches a suppressor by click, shows it in the muzzle slot, makes rounds, and takes it off). `test_gear.gd` and `test_skills.gd` updated for the gun slot, the casings recipe, Old Pete's second drop and the enabled Firearms skill. **3995 checks** (was 3794).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- A pistol straight away: `play.bat --gun --time=12`. Left click shoots, **R** reloads, **Q** swaps to the pipe and back. Shoot near the street zombies and watch the rest of the street come (N shows the noise rings). The rifle: `play.bat --gun=rifle --time=12`; Old Pete's: `play.bat --gun=pete --time=12`.
- The workbench screen: `play.bat --workbench --time=12`. Click **Scope** to fit it, click **Muzzle** to take the suppressor off, make some rounds.
- The whole chain: `play.bat --demo-factory --time=12`. Look at the press and press **R** twice ("Press now makes Ammo casings"), take metal plates from the crate by the spawn and **E** them into it. Build a **workbench** (B, scroll to the last piece), **E** on it and make standard rounds.
- Old Pete's rifle: `play.bat --cam=-1,0,-115,0,4 --time=12`, kill him, E on his bag, then Tab and **Equip** the rifle.
- Gunsmith: K, Fighter tree (needs a perk point).

**Known gaps:**
- Not in M14, as planned: belts feeding ammo and an automatic bench (M15), turrets using guns (M15), armour-piercing effects (needs brutes), gun repair beyond the repair kit (a kit works on a gun from Tab; a part has to come off the gun to be repaired).
- Bench recipes are made instantly by hand (each has a time in recipes.json for when M15 automates them).
- No crosshair, so the spread is felt rather than seen. A shot has two rolls: the ray in the cone must meet the zombie, then the sim's hit chance by distance.
- Parts don't show on the gun model (a suppressed pistol looks the same), and the scope doesn't zoom. Gun, part and ammo icons are placeholders (the rarity tile with a letter; ammo a colour).
- Old Pete's rifle comes only from killing him, so a version-7 save where he's already dead has no way to get it yet. Police-tier guns only come from the 2% police find; there's no police station.
- Shots don't go through a zombie into the next one, and don't damage walls. You can't shoot from a car.
- The Fighter tree now has six perks; the skills screen fits at 1600 x 900 but only just.
- `--shoot` fires before the physics world settles, so its screenshot says "Missed"; it's for the HUD line.
- Every number in `data/guns.json` is a first guess. Tune after the playtest.

**Next:** Playtest #1, then M15 automated defense.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1c Furniture

From the W1c brief by the project lead (the W1b "furniture props" line in `docs/plans/W1.md`), on top of M13 (PR #27).

**Built:**
- **Rooms have furniture now.** Six new Blender-kit models, flat colours, low-poly: a **kitchen counter** with a sink, tap and cupboards (1.76 m), a small **table with two chairs** (1.6 m), a three-seat **couch** (1.76 m), a **bookshelf** with rows of coloured books (1 m wide, 1.8 m tall), a **bathtub** (1.6 m) and a **toilet**. Each stands with its back to a wall and faces into the room.
- **Every house is furnished** (six pieces each, 72 in town): every kitchen has a counter (in the L-shaped house it's under the kitchen window, sink under the glass); living rooms have a couch and a bookshelf; bedrooms keep the bed and get a bookshelf; bathrooms have a bathtub and a toilet in the square house, and one of the two in the smaller bathrooms (the long house a tub, the L-shaped one a toilet). The long house's kitchen-living room has a table; the L-shaped house's table stands in the living room next to the kitchen.
- **The factory hall** has two bookshelves against its north wall and a table against its east wall, well away from the doorway and Old Pete.
- **Furniture is a piece, like a wall.** You bump into it, zombies walk round it (the navmesh reads it) or wreck it if it's in their way, and it's saved with the rest of the town. You can't build it, but in build mode right-click pulls it apart for salvage: 2-3 planks from wooden pieces, a plank and some scrap metal from a bathtub or toilet. Looking at one shows its name and hp ("Kitchen counter · 80/80 hp"); T repairs it like a wall.

**Rules (sim, tested):** furniture is six entries in `data/buildables.json` with `"kind": "prop"`, `"player_placeable": false`, a collision box, modest hp (40-120), a cost that is the removal refund, and a new generic flag `"against_wall": true`. `BuildGrid`: `prop` is an object kind (one per cell, on a floor, facing a side); `center_for` stands an `against_wall` object at the back of its cell (`WALL_HALF` + `WALL_GAP` off the edge) instead of its middle. `GameData` knows the kind and checks a prop fits along one wall (at most 1.8 x 0.9 m) and isn't player-placeable. `TownPlan`: each floor plan lists `"props"` ([id, u, v, wall], placed by hand like the containers), and `generate` returns `"props"` ({id, cell, side (facing), wall, house}); `factory()` returns its three; house zombies never stand in a furniture cell. `SimWorld.place_props(plan)` lays the houses' and the hall's furniture with `restore` (free, muted), skipping a cell that already has an object, has lost its floor or has a zombie in it. Nothing else in `src/sim` knows what furniture is. World: `BuildView.MODELS` draws the six models; `Interactor` treats a prop like a wall (no E action); `--inside=N,PROP` stands you in front of house N's PROP. **Saves:** `SaveGame.VERSION` is 7 (`FIRST_WITH_PROPS`, `holds_props`). A new game lays the furniture with the town. A save from before 7 loads, then gets furnished (after the save is applied, so a crate you built in a kitchen keeps its spot and that counter is skipped). `test/fixtures/save_v6.json` was written by the M13 code before these changes; the v2-v5 fixtures still load and get furnished too.

Where the brief and the houses differed: the brief asked for props never on "a doorway cell", checked by a whole-cell flood fill. The rooms are 2 x 2 cells, and plan A's kitchen holds the back door, the fridge, the cabinet and both doorways in its four cells (its bathroom is only reached through the fridge's cell), so that rule leaves no room for a counter and the whole-cell walk fails on the W1a layout before any furniture. Instead each piece takes the half of its cell along its wall, and the walk test runs on 1 m half-cells: from the front door every free square is reachable and everything has a reachable square beside it, so every doorway keeps a 1 m path. Props are still never on a door's cell, a container's cell or the bed's cell. No container or wall moved.

**Tests:** `test_furniture.gd` (the six are props, not buildable, modest hp, a few planks, drawn from models, and a too-wide prop is caught; same seed same furniture, six per house, a counter and a couch in every house; for seeds 1, 5 and 77 every prop is inside its house, back to a wall (a low one may be under a window), facing the room, not on a door, container, bed or other prop's cell; the half-cell walk test for every house; the hall's two shelves and table against its walls, off the crates and Pete, away from the doorway; `place_props` lays them all once, the box's back is at the wall and on the floor, not counted as your builds; you can't build a couch or build on one; pulling one apart refunds its planks; zombies wreck one at 0 hp; house zombies are never in furniture; a removed and a damaged piece survive save and load), `test_furniture_world.gd` (physics: you walk into a counter and stop in front of it; a zombie up the street comes in through the open front door and bites you at the sink of a furnished kitchen; the real game loads the version-6 fixture furnished, and a second save and load doesn't furnish it twice), `test_art_models.gd` (the six fit their boxes, stand on the floor and are merged; each faces the room: the cupboard doors at the front, the couch's back, the shelf's back panel, the tub's taps and the toilet's cistern at the back), `test_save.gd` (the version-6 fixture loads with its door, gear and pieces, then gets all 75 pieces of furniture, or one fewer with your crate on a counter's spot; the v2-v5 fixtures load and get furnished). `test_gear.gd` now accepts any version from 6. **3794 checks** (was 2367).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**. Walk up the street, open a front door (E) and look round: a counter in the kitchen, a couch and a bookshelf in the living room, a bookshelf by the bed, a tub or a toilet in the bathroom. Walk into the furniture (it's solid). In build mode (B), aim at a couch and right-click to pull it apart for planks. To start in front of a piece: `play.bat --inside=0,counter --time=12` (a counter under a window), `play.bat --inside=6,couch --time=12`, `play.bat --inside=6,bathtub --time=12`, `play.bat --inside=1,table --time=12`. At night: `play.bat --inside=6,shelf --time=22 --flashlight`. The factory's shelves and table: walk to the end of the road and in through the big doorway. An old save loads with its houses furnished.

**Known gaps:**
- Not in W1c, as planned: textures (flat colours only), a shop, a fifth house plan, furniture outside the houses and the hall, and any tuning.
- The rooms are small for one piece per cell: plan A's kitchen has no table (back door, fridge, cabinet and counter fill it), the long house's bathroom has no toilet and the L-shaped one's no bathtub. Bigger rooms or a fifth plan would fix that.
- The counter and couch are 1.76 m, not 2 m, so they fit between the side walls of a corner cell.
- Bathtubs and toilets refund a plank and scrap metal (wooden furniture refunds 2-3 planks), so the town holds a little free scrap. Tune after the playtest.
- Furniture laid into an old save skips any cell you built on and any cell a zombie was standing in when you saved, so a house can be one piece short.
- An open door has no collider, and in some houses an open door lies flat along the side of a couch; nothing clips through, but the swing isn't checked against furniture.
- Furniture doesn't block sight or muffle sound (only walls, doors and windows do).

**Next:** Playtest #1, then M14 guns.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M13 Loot

From the M13 brief by the project lead, on top of M12 (PR #26).

**Built:**
- **Gear is now things you find, each one rolled.** Scrap, nails, food and the like still stack as before. Weapons and things you wear are single pieces, each with its own rarity, rolled stats and condition, in the Diablo 2 colours: **white** (plain), **blue** (1-2 stats), **yellow** (3-5 stats, a random two-word name like "Rust Beacon"), **gold** (a named unique), **green** (a set piece); orange is kept for crafted gear later.
- **Stats roll in ranges:** +10-25% melee damage, +1-2 to Fighter / Ghost / Engineer perks (adds that many ranks to every perk you have at least one rank in, in that tree, and can push a perk past 5), +1-3 Strength (counts as levels for Strength's effects), 5-15 quieter footsteps and swings, +5-15 kg carry, +10-30% durability, +10-25% search speed.
- **Bases and tiers:** weapons pipe, baseball bat, axe and machete (each its own damage and speed); a hard hat or cap (head), hi-vis vest or jacket (body), work gloves (hands) and a headlamp (light), each with a small stat of its own (the hard hat: zombies hurt you 5% less; the cap: footsteps 1 quieter; the vest: +3 kg; the jacket: 8% less damage; gloves: +5% melee; headlamp: +5% search speed). **Police** pieces (15% of finds) have 25% better base stats and one extra rolled stat. Military is reserved for a later area.
- **Five slots you wear:** weapon, head, body, hands, light. **You start holding the pipe** as a white piece in the weapon slot (the M10b gap "the pipe isn't an inventory item yet" is closed). With nothing in the weapon slot you punch.
- **Condition (Mint, Good, Worn, Worn out):** your weapon loses 0.4% per hit, worn gear 3% per game day; durability slows it. Under 25% a piece's rolled stats stop working (its base stats stay) and the HUD says "Your Axe is worn out". A **repair kit** puts it back to mint from the inventory screen.
- **Repair kits come from the Press:** look at a press and press **R** to switch it between nails and repair kits (1 metal plate + 4 nails, 6 seconds). Whatever was waiting in it comes back to your pockets.
- **The first unique, Pete's Fire Axe** (gold): an axe with +15-30% melee damage, +1-2 to Fighter perks and 5-10 quieter. **Old Pete**, a named zombie (bigger, red shirt, 200 hp, hits for 16), stands in the middle of the factory hall facing the doorway, and always drops it. The HUD says "Old Pete drops something gold".
- **The first set, Night Shift** (green): hard hat, hi-vis vest, work gloves, headlamp. 2 pieces: +15% search speed; 3: +10 kg carry; all 4: every noise you make counts as 3 quieter. Set pieces turn up in factory crates, and anywhere as Police-tier finds.
- **Where gear comes from:** a search finds a piece now and then (kitchen and bathroom cabinets 5%, factory crates 25%, car trunks 15%; Lucky Find rolls again), with odds white 70 / blue 20 / yellow 8 / set 2. Zombies drop a piece 10% of the time (runners 20%) in a bag where they fell. The "Found ..." message names it; a gold or green find gets its own message.
- **Inventory screen (Tab):** gear pieces sit in your pockets after the stacks as a rounded tile in the rarity colour with the base's first letter and the condition. Click one to see its name in its colour, what it is, its condition and stats, and **Equip**, **Drop** or **Repair (1 kit)**. A new **Wearing** column on the right lists your five slots in colour; click one to **Unequip** or repair it.
- **HUD:** "Weapon: <name>" under the pocket weight at the top right. The pipe in your hand disappears when you have no weapon.
- **Death:** gear in your pockets goes into your death bag like everything else; what you're wearing stays on you.

**Rules (sim, tested):** `Gear` (`src/sim/gear.gd`, RefCounted) owns pieces `{uid, base, tier, rarity, stats, condition, name, set}`: `pieces` (pockets), `equipped` (slot -> piece), `roll_piece(rng, source)`, `roll_unique`, `roll_stats`, `equip`/`unequip`/`take`/`find`, `weight()` (pocket pieces only), `bonus(effect)` (base stats times the tier, working rolled stats, set bonuses), `weapon_stats()`, `wear_weapon()`/`wear_day()`, `repair(uid, inv)`, `to_dict`/`load_dict`. **Routing:** `SimWorld` gives `Skills` a reference (`skills.gear = gear`) and `Skills.bonus(effect)` adds `gear.bonus(effect)`, uses `effective_level(skill)` (+N Strength) and `effective_rank(perk)` (+N to a tree, only for ranked perks), so every rule still makes its one `skills.bonus(...)` call and none changed. New gear-only effects: `gear_quiet` (footsteps and melee hits in `SimWorld.noise_loudness`, which hits now go through) and `quiet_all` (every noise that goes through `noise_loudness`). `SimWorld`: `carried_kg()` (items + pocket gear; `carry_ratio`, the HUD and the screen use it), `weapon_stats()` from the equipped piece (fists in `weapons.json`), `equip_gear`, `unequip_gear`, `drop_gear`, `repair_gear` (trains Mechanics), `spawn_old_pete()` (at `TownPlan.factory()["pete"]`), `cycle_recipe(cell)`, `_search_gear` (its own seeded stream per container), `_zombie_drop` from `_count_kills` (seeded by zombie id, so car and turret kills drop too), bags carry `"gear"`. `Loot.tick` also returns the table and whether Lucky Find fired. `Factory.Machine.recipe_id` + `Factory.set_recipe`; a buildable's `"recipes"` lists what it can switch to. Data: `data/gear.json` (all the numbers), new weapons, the `old_pete` zombie, the `repair_kit` item and recipe; `GameData` validates gear.json and machine recipe lists. **Saves:** `SaveGame.VERSION` is 6 (gear, gear in bags, a press's recipe). A version-5 save loads with the pipe as a white mint piece in the weapon slot and Old Pete added to the hall (older saves too); `test/fixtures/save_v5.json` was written by the M12 code before these changes, and the v2-v4 fixtures still load.

**Tests:** `test_gear.gd` (gear.json validates and a broken one is caught; the starting pipe; every rolled stat and condition inside its range over 600 rolls, the unique's too; rarity odds over 6000 seeded rolls near 70/20/8/2 and Police near 15%; white 0, blue 1-2, yellow 3-5 stats, Police +1; set pieces rare outside the factory; Police damage x1.25; `Skills.bonus` includes worn gear (carry, melee, search time, the cap's footsteps, +2 Strength as 6 kg) and not pocket gear; +1 to Fighter perks raises Heavy Swing 5 to 6 and Thick Skin 1 to 2 but not an unranked perk or Ghost; Night Shift at 1/2/3/4 pieces; quieter footsteps and hits but not doors; wear per hit and with durability, per day only for worn non-weapons, stats off under 25% with the base kept, repair needs and uses a kit, the worn-out message; the Press switches to repair kits, makes one, gives back its input, and the switch is saved; Old Pete has 200 hp, stands in the hall and drops his gold axe in a bag with the message, which you can pick up and equip; zombie drops land in bags near 10% (runners 20%) and the same seed drops the same; searches find gear, Lucky Find rolls again, fridges hold none; carry weight counts pocket gear only; death drops pocket gear and keeps what you wear; save and load keep pieces, slots, condition, bag gear and uids; the version-5 fixture loads with the pipe and Old Pete, once). `test_inventory_screen.gd` (a yellow piece's tile in its colour with its letter and condition; a click shows its name in yellow and its stats; Equip puts it on and its stats count; the Wearing column shows it in colour; Repair with a kit, Unequip, Drop). `test_town_world.gd` (the real game has Old Pete in the hall, once after a save, and the pipe in your hand). `test_save.gd`/`test_skills.gd`: the v3 fixture now also gets Old Pete; a new save is the current version. **2367 checks** (was 2189).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- Press **Tab**: the Wearing column shows "Weapon: Pipe". To see a rolled piece straight away: `play.bat --gear` (a yellow one), or `play.bat --gear=gold` (Pete's Fire Axe), `play.bat --gear=set` (a Night Shift piece), `play.bat --gear=blue`. Click it, then **Equip**: watch the kg limit and the "Weapon:" line at the top right change.
- Old Pete: walk north up the road into the factory hall; he's in the middle, in a red shirt, bigger than the rest. Or start facing him: `play.bat --cam=-1,0,-115,0,4 --time=12`. He takes about six pipe hits; then press **E** on his bag and Tab to equip the axe.
- Search cupboards, trunks and the factory crates: now and then "Found ..." names a piece of gear.
- Repair kits: `play.bat --demo-factory --time=12`, look at the press, press **R** ("Press now makes Repair kit"), take some nails from the crate by the spawn, then **E** on the press to load them.

**Known gaps:**
- Gear icons are placeholders drawn in code (a rounded square in the rarity colour with the base's first letter); Codex pictures are a PC job. Every weapon still looks like the pipe in your hand, and Old Pete is the ordinary zombie model, scaled up with a red shirt.
- Worn gear doesn't count against your carry limit (only gear in your pockets does), and it doesn't show on your body.
- The skills screen still shows the ranks you bought, not the extra ranks gear adds (the effects do use them).
- The headlamp doesn't light anything yet (its base stat is +5% search speed); the flashlight is still F.
- No crafted (orange) gear, no Military tier, no guns or reload/recoil stats (M14), and only one unique and one set. Every number in `data/gear.json` is a first guess.
- Old Pete is added to a loaded pre-M13 save even if you'd already cleared the factory.
- Set pieces have no stats of their own beyond their base; the set bonus is what they're for.

**Next:** Playtest #1, then W1c furniture and M14 guns.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

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
