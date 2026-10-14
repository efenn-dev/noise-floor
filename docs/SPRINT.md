# Read me first (Emmitt)

*Updated 2026-10-13 night by Claude Opus 5.5.* Sprint 4 has started: make the first 30 minutes look, sound and feel premium, with no new systems and free assets only (see the top of `docs/DIRECTION.md`). Codex is making the art and Claude is wiring it in. Each task lands as its own pull request against `main`. Merge them as they come, and `play.bat` picks them up. When the board says V8, play 30 minutes from a new game and write the Playtest #2 entry.

---

# Sprint 4 — "The first 30 minutes"

*Started 2026-10-13 night at Emmitt's request. Lead: Claude Opus 5.5 in a local session. Art: Codex on Emmitt's ChatGPT plan, one job at a time, in its own worktree. Feature freeze: polish, tuning and bug fixes only.*

## Sprint goal

A new game's first 30 minutes (day 1, the first night, the next morning) look, sound and feel good enough that Emmitt would post a 60-second clip of them.

## Board

| # | Task | Owner | Status | Done when |
|---|---|---|---|---|
| V1 | Lighting and atmosphere: volumetric fog the flashlight shows up in, ambient occlusion, bounce light, a colour grade for a dead town, a real flashlight beam (Codex light texture), pools of light from street lamps, glow on lamps and machine lights; a graphics quality setting so weaker PCs still run | Claude, branch `v1-lighting` | PR open; tests green; screenshots checked (SDFGI dropped: black houses at noon) | Day and night screenshots beat the old ones; settings has low/medium/high; tests green |
| V2 | Textured zombies and guns, a different shirt and colours per zombie, detailed pistol and rifle models (this is S3-1c) | Codex (textures, gun models, wiring), Claude reviews, branch `s3-1c-codex-art` | Codex running | Zombies and guns read as textured close up; tests green |
| V3 | Game feel: weapon sway and bob, recoil kick, camera shake on hits, impact puffs (dust, sparks, blood), a hit marker, a red edge when hurt, a step bob | Claude, branch `v3-game-feel` (stacked on V1) | PR open; tests green | It feels good in Emmitt's hands (V8) |
| V4 | Sound: walls muffle what the player hears (same wall count the zombies use), echo indoors, layered wind and distant moans, heavier guns and hits | Claude, branch `v4-sound` (stacked on V3) | PR open; tests green | Indoors sounds different from outdoors; a machine behind a wall is quieter |
| V5 | Art direction: `docs/ART_DIRECTION.md`, one page with palette, mood and reference pictures from Codex; every later asset is checked against it | Codex (pictures), Claude (page) | Queued after V2 | Page merged |
| V6 | First-person arms: rigged arms in a Blender script (idle, walk, swing, shoot, reload), shown with the pipe and both guns | Codex (model and animations), Claude (wiring) | Queued after V5 | Hands visible holding every weapon |
| V7 | Zombie hits and deaths: stagger when hit, a ragdoll fall on death, blood decals, a headshot that reads | Claude, branch `v7-hits-deaths` (stacked on the car fix) | PR open; tests green (the rig already had hit-react and death animations) | A fight looks right in a screenshot sequence |
| V9 | Weapons wear out and break (Emmitt): each weapon wears at its own rate (a knife fast, a pipe slowly), a worn weapon warns you, at 0 it snaps and is gone; the HUD shows its condition; a knife joins the loot | Claude, branch `v9-weapon-skills` | PR open; tests green | You need a new weapon every so often |
| V10 | Zomboid weapon skills (Emmitt): Blunt, Blades and Axe replace Melee (+6% damage and 4% quicker swings per level with that kind of weapon), Maintenance (7% less wear per level); old Melee xp carries over (save version 14) | Claude, same branch as V9 | PR open; tests green | Skills screen shows them; a trained weapon hits harder and faster |
| V11 | Attack animations (Emmitt): real models for pipe, bat, axe, machete and knife (Codex), and a swing for each kind (diagonal, side, overhead chop, slash, stab) with wind-up, strike and recovery, the hit landing at the strike | Codex (models), Claude (swings), branch `v11-attacks` | PR open | Each weapon looks and swings differently |
| V8 | Playtest #2 on the polished build (30 min from a new game, session log pasted in), then tuning from it (replaces S3-2 and S3-3) | Emmitt (+ Kaleb), then Claude | Waiting on V1–V7 | Entry in `docs/PLAYTESTS.md`; tuning PR merged |

Order: V2 runs in Codex while Claude builds V1; then V3 and V4 (code) while Codex does V5 and V6 (art); V7 after V2 merges because both touch the zombie; V8 last. Before V8, run `tools/soak.sh --days=3` and `tools/tour.sh` on `main`, as DIRECTION.md asks.

---

*Below: Sprint 3 and the earlier sprints, kept for the record.*

# Read me first (Emmitt), Sprint 3

*Updated 2026-10-13 evening by Claude Fable 5.1 after your Playtest #1 notes. Everything from the day run is merged; `main` is #41.*

**Two pull requests to merge, in order: S3 (branch `s3-playtest-fixes`), then S4 (branch `s4-playtest-1b`, stacked on it; it shows both until S3 merges).** S4 adds pictures on the hotbar and in the build menu, green tips that walk you through your first factory with power and loading, bodies you can search (E on a dead zombie), and jumpscare stings. The first-factory steps are also under F1. It fixes the two things you hit (driving, doors) and adds what you asked for (a hotbar and a build menu). After the merge, `play.bat` picks it up. Try, in order: walk to the red sedan, E at its back to search the trunk for the key, E at its side to get in, W to drive, E to get out. Open a house door with E, walk in, turn round and press E on the open door to close it. Press 1 and click to lay a foundation; B for the build menu; point at a piece in it and press a number to put it on that key; Tab, click a bandage, press 0. Then tell the lead what felt wrong and the next sprint-3 pass is tuning from that.

---

# Sprint 3 — "Tuning from Playtest #1"

*Started 2026-10-13 evening, after Emmitt's first playtest on the merged build (docs/PLAYTESTS.md, 2026-10-13). Lead and builder for S3: Claude Fable 5.1 in one local session (no agents: the fixes needed the real scene and a careful read of input order). Rule from DIRECTION.md: the next task comes from a playtest entry, not the checklist.*

## Sprint goal

Emmitt drives a car, closes a door behind him, and builds from a hotbar and a build menu without reading anything.

## Board

| # | Task | Owner | Status | Done when |
|---|---|---|---|---|
| S3-1 | Playtest #1 fixes: driving (E bounced you out), doors (couldn't close, walked through the open panel), plus the hotbar (1-9, 0) and the build menu (B) he asked for | Fable 5.1, worktree `noise-floor-s3`, branch `s3-playtest-fixes` | PR open; tests green; screenshots checked | PR merged; Emmitt drives, closes a door, builds from the hotbar |
| S3-1b | Second pass from Playtest #1 (his second message): piece pictures, first-factory walkthrough (hints, build menu notes, F1 guide, no-power message), lootable corpses, jumpscare stings | Fable 5.1, worktree `noise-floor-s4`, branch `s4-playtest-1b` | PR open; tests green; screenshots checked | PR merged; Emmitt builds a running smelter from the tips alone |
| S3-1c | Art pass with Codex: zombie skin and clothes textures (object-space triplanar, like car paint), gun metal and wood, then clothes variety per zombie | Codex, worktree `noise-floor-art3`, branch `s3-1c-codex-art` | Implemented in code with coverage tests; Godot crashed on sandbox log access, so the full suite and five Forward+ screenshots still need PC validation before merge | Zombies and guns read as textured in a screenshot |
| S3-2 | Playtest #2 on the merged build (30 min, session log pasted in) | Emmitt (+ Kaleb) | Waiting on S3-1 and S3-1b | Entry in `docs/PLAYTESTS.md` |
| S3-3 | Tuning from Playtest #2 (the builders' flagged soft spots: infamy and heat climb, early water, winter stove, park difficulty) | Fable plans, Opus 5.5 builds | Waiting on S3-2 | PR merged |

---

*Below: the day run's read-me and the earlier sprints, kept for the record.*

*Final update of the day run: 2026-10-13 15:45Z. Nothing is running. The lead has stopped.*

**Merge these on GitHub, top to bottom, each against `main`:** #24, then #26, #27, #28, #29, #30, #31, #32, #33, #34, #35, #36, #37, #38, #39, #40, then #25 (this board) last. Every one targets `main`; the order only keeps the diffs readable. After the last merge `play.bat` updates itself and shows the build in the title screen's corner.

**On the final branch:** 7968 checks pass; the bot plays a week into winter and the park headless and reports `SOAK OK` (13 deaths in the week, 6 of them the bot dying of thirst in house 1, none from cold, none from Old Pete, no beds, stoves or furniture lost). Save files from any earlier version still load.

**What to play, in this order:** a new game with no flags, as a stranger: do the tips and F1 explain enough? Into a house, loot the kitchen, meet the zombie in one of them, close the door. The red sedan's key is in its trunk. Build a smelter line with a generator and watch heat and infamy; note when the first runner appears. Tab, K, L, F1. Fit a scope at the workbench and hold right click. Play into the night: lamps, flashlight, fog indoors. If you have time, north through the hall into the park and the water tower; expect to die. Then the entry at the top of `docs/PLAYTESTS.md` with the session log pasted in.

**What nobody has verified:** a human playing any of it. The builders' flagged soft spots, in one place: infamy and heat climb fast once a generator runs; house zombies barely hear a search by day; early clean water needs a powered purifier, so the bot dies of thirst by day three; the winter stove runs dry around 04:30 each night; zoom adds no accuracy; the park is hard; you can shoot Old Pete from outside his doorway and he won't react.

**Sprint 3 is tuning from your notes, not new systems.** `docs/DIRECTION.md` says so at the top.

---



# Sprint 2 — "Into the houses"

*Started 2026-10-12, right after Sprint 1 closed: #16, #17 and #18 merged, and Emmitt's first play (on the old build, before play.bat caught up) said two things: no way into the buildings, and cars that would not drive. Lead: Claude Fable 5.1. Builders: Claude Opus 5.5. QA: Emmitt and Kaleb. Budget rule unchanged: the lead checks the 5-hour window before launching a builder, stops launching at 75%, one build agent on the PC at a time; cloud sessions on the credit don't count against it.*

## Sprint goal

Emmitt opens a front door, loots a kitchen in the dark, closes the door and hears the street go quiet. Then writes Playtest #1.

## Board

| # | Task | Owner | Status | Done when |
|---|---|---|---|---|
| S2-1 | P1 playtest fixes: car prompts explain keys and wrecks; play.bat writes an update log and a version line the title screen shows | Opus 5.5 agent | Merged (#20) | PR merged; Emmitt sees the version on the title screen |
| S2-2 | W1a — into the houses (plan: `docs/plans/W1.md`) | Opus 5.5 agent on the PC, worktree `noise-floor-w1a` (Emmitt chose local, 2026-10-13) | PR #21 open; 1546 checks green; 455 town pieces, first bake 48 ms | PR merged; walk in, loot inside, closed door muffles; tests and screenshots per the plan |
| S2-3 | Playtest #1 on the merged build (30 min, with the session log) | Emmitt + Kaleb | Ready now | Entry in `docs/PLAYTESTS.md` |
| S2-4 | W1b — life inside: zombies in some houses, factory floor, hordes on roads, props | Opus 5.5 agent on the PC, worktree `noise-floor-w1b`, stacked on #22 | PR #23 open; 2022 checks green | |
| S2-5 | Sprint review: read Playtest #1 and the session logs; plan Sprint 3 (M12 skills unless the playtest says otherwise) | Fable | Waiting on S2-3 | Sprint 3 board here |

## Day run, 2026-10-13 (Emmitt at work, ~12 hours)

Chosen for value before a playtest and low design risk, in this order, one at a time, each PR against `main`, each reviewed by the lead:
1. **P3 — playtest readiness**: done, PR #32 (4706 checks): a help screen on F1, key hints that fit the moment, a session log that covers gear, skills, guns and the base log, town doors and beds that salvage instead of refunding, crosshair contrast.
2. **Q1 — integration soak and screenshot tour**: done, PR #33. Soak OK over three game-days (176 s wall, memory 113 to 124 MB, worst frame 2.2 ms). Unfixed, for Q2: idle zombies break a town door and a kitchen counter on day 1; fog indoors is as thick as outside; the heat warning overlaps the carry line; the car reports one NaN speed after you get out: a headless scripted "bot day" over three game-days through the whole stack with script-error detection, plus `tools/tour.sh` that takes a dozen screenshots around town for the lead to review; fix what breaks.
3. **A1 — street dressing**: done, PR #34 (4843 checks; all five models built first try) with the Blender kit: lamp posts, mailboxes, fences, trash cans, a few trees, placed by the town plan. No Codex.
3b. **Q2 — fixes from the soak**: done, PR #35 (4928 checks). The counter still breaks because an investigating zombie may wreck what blocks it; the lead decided zombies never break furniture, and that rule rides with M16: idle zombies stop bashing furniture and doors unless they are chasing or investigating, thinner fog under a roof, the heat warning gets its own line, the car NaN root cause if cheap.
4. **M16 — seasons**: done, PR #36 (5155 checks; soak OK, the counter now survives): a calendar, winter stops crops, cold needs heat, sound carries farther on cold nights.
5. **A2 — zombie variety**: done, PR #37 (5325 checks): more body variants from the rigged zombie script.
6. **M17a — the industrial park and the water tower**: done, PR #38 (7878 checks; soak OK; a game-day of soak now takes 102 s instead of 59 s, bake 49 to 78 ms), then **Q3 — a seven-day winter soak and the tour again**: done, PR #39 (SOAK OK over 7 days, 90 s per game-day, memory flat; found: Old Pete leaves the hall and kills you on evening one, zombies still wreck beds and stoves, indoors warms you in winter with no fire, the bot dies of thirst from day 14), then **Q4 — rule fixes**: done, PR #40 (7968 checks; Old Pete guards the hall, a breakable-kinds list in one place, indoor cold at a third of the outdoor rate; the week-long soak now passes end to end: 7 days, 87 s per game-day, 0 cold deaths, 0 Old Pete kills). Day run complete. Outposts and the substation wait for a playtest.
6b. **M17 — further out** (original line, for reference): a second, harder area and the first big project.
Not today: tuning (waits for Playtest #1), anything needing Codex image generation.

## Overnight run, night of 2026-10-12 to 13

Emmitt went to bed and left the PC on. The lead runs one Opus 5.5 builder at a time, reviews each pull request, and checks the 5-hour window before every launch (no launch above 75%; wait for the reset instead). Each builder branches from the previous one, so the morning merge order is the queue order; merging the first retargets the next on GitHub. Queue:

1. **W1a — into the houses**: done, PR #21 against `main`.
2. **Stress test**: done, PR #22 (numbers only: 4.6 ms per tick with 200 zombies, 50 machines and the town; the Director's once-a-second wall count spikes to 20 ms; cheap cache fix noted in docs/perf): one headless test with 200 zombies, 50 machines and a game-day, printing the time per tick, the noise query and the navmesh bake. Branch from W1a so it measures the town pieces too. Numbers only, no fixes.
3. **W1b — life inside**: done, PR #23 (stacked on #22; 2022 checks; a zombie in 4 of 12 houses, the factory hall with a 4 m doorway, groups and hordes come down the road): a zombie in about one house in three, the factory as a grid interior with a roof, hordes that follow the road. Branch from W1a. Furniture props stay out (PC art).
4. **M12 — skills and perks**: done, PR #26 against main (2189 checks; ten skills with effects, Strength carry, three perk trees, K screen; interrupted once by an app restart and resumed), from `GAME_DESIGN.md`: skills that level by doing, the Strength carry limit and bags, perk points, the three trees with a few perks each, a skills screen. Branch from W1b. Only if the window allows.

Extended while Emmitt is away until the evening of 2026-10-13, in this order, one at a time, each PR against `main`, each reviewed by the lead:
5. **M13 — loot**: done, PR #27 against main (2367 checks; gear instances with rarity colours and rolled stats, five slots, condition and repair kits from the Press, Old Pete and his axe in the factory hall, the Night Shift set; `--gear` flag): rarity colours, stat rolls in ranges, base tiers, durability and repair kits, the first uniques and one set (`GAME_DESIGN.md` "Loot"). Branch from M12.
6. **W1c — furniture**: done, PR #28 against main (3794 checks; six Blender-kit props in every house and the factory hall, salvageable for planks; `--inside=N,PROP` flag): Blender-kit props (table, counter, couch, shelves, bathtub) placed by TownPlan, existing surfaces, no Codex. Branch from M13.
7. **M14 — guns**: done, PR #29 against main (3995 checks; pistol and rifle in a gun slot with Q to swap, parts and a workbench, crude and machined suppressors, casings from the Press, Firearms levels, Gunsmith plus two more Fighter perks; `--gun`, `--workbench`, `--shoot` flags; known soft spot: a shot rolls twice, the ray and then a hit chance, so misses may feel harsh, and there is no crosshair): firearms, workbench and parts, loudness per part, the crude suppressor, the subsonic ammo chain, the Gunsmith perk. Branch from W1c.
8. **M15 — automated defense**: done, PR #30 against main (4285 checks; belt-fed and hopper-fed turrets, crossbow and rifle turrets with suppressors, motion and noise sensors with quiet mode, floodlights, decoy noisemakers and door locks, base log on L and radio alerts, bear traps, tripwire bells, electric fences, the repair station, and the Director cache: worst tick 20 ms down to 12 ms; no new Blender models, reused bodies and boxes): turrets fed by belts, traps, sensors and actions, the repair station, attacks that play out while you are away, radio alerts and the base log. Includes the cheap Director cache from docs/perf. Branch from M14.
9. **P2 — polish**: done, PR #31 against main (4371 checks; one roll per shot, a crosshair that shows the spread, scope zoom on right click, skills screen in three scrolling columns; noise.refresh 448 to 95 microseconds, the Dampened Gears lookup is now once a tick): a crosshair when a gun is in hand, shooting decided by the spread ray alone (no second roll), scope zoom, skills screen layout with six Fighter perks.
Not in this run: tuning of any kind (waits for Playtest #1), M16, M17, anything needing Codex image generation.

## What Emmitt tests, and when

**Now, on the merged build:** `play.bat`, New game. The green tip line should be there. Play thirty minutes. Cars: the first car up the street (red sedan) has its key in the trunk: look at its back, press E to search, then look at its side and press E to get in. Note when the first runner shows up. Quit from the title screen and check `%APPDATA%/Godot/app_userdata/Noise Floor/sessions/` for the log. Write the `PLAYTESTS.md` entry.

**After S2-1 merges:** the title screen shows a short build line in a corner; `play-update.log` next to play.bat says what the updater did; looking at a car tells you about its key or wreck before you press E.

**After S2-2 merges:** open a front door, go in, find the fridge, close the door, run a smelter indoors with `--noise-overlay` and compare the rings to outdoors.

---

# Sprint 1 — "Someone plays it" (closed 2026-10-12)

*Started 2026-10-12. Ends when the first entry lands in `docs/PLAYTESTS.md`. Lead: Claude Fable 5.1 (plans, review, this board). Builders: Claude Opus 5.5 sessions and agents, one milestone per worktree. QA: Emmitt, with Kaleb when he's willing. Update the Status column as things move; keep the table honest.*

## Sprint goal

Emmitt and Kaleb play Noise Floor for 30 minutes on `main` via `play.bat` and write the first playtest entry, and the game itself writes a session log they can paste in. Nothing else matters this sprint.

## Budget rule

Stay inside the account's 5-hour usage window. The lead checks it before launching any builder and stops launching at 75%. One build agent at a time unless the window is under 50%. No multi-agent workflows. The weekly Fable allowance is not the constraint; the shared 5-hour window is.

## Board

| # | Task | Owner | Status | Done when |
|---|---|---|---|---|
| S1-1 | M11 — the world gets worse, kept small (finite loot, stale gas, spoilage, infamy score, stats screen, runner and screamer as simple variants; no tuning pass) | Opus 5.5 session, worktree `noise-floor-m11` | PR #16 open, mergeable; the session reports 983 checks green | PR merged; devlog names what landed and which model built it |
| S1-2 | Direction, playtest template, this board | Fable | PR #17 open, clean | PR merged |
| S1-3 | P0 playtest kit: session log the game writes on death and quit, first-five-minutes hints for a new game | Opus 5.5 agent, worktree `noise-floor-p0` | PR #18 open; M11 merged in by the lead (a `stats` name clash fixed); 1067 checks green | PR merged; tests green; Emmitt finds the log file on his PC |
| S1-4 | Save upgrades: bump `SaveGame.VERSION` per milestone, load old saves with defaults, fixture-save test | Done inside PR #16 (VERSION 2; version-1 saves load with defaults; test added) | Done | A committed save from the previous version still loads in a test |
| S1-5 | Playtest #1 (30 minutes, then one `PLAYTESTS.md` entry) | Emmitt + Kaleb | Ready now on current `main`; play again after #16 and P0 land | Entry pushed to `main` |
| S1-6 | Sprint review: read the playtest and the session log, plan Sprint 2 (W1 real town) | Fable | Waiting on S1-5 | `docs/plans/W1.md` written, Sprint 2 board here |

## What Emmitt tests, and when

**After S1-1 (M11) merges.** Double-click `play.bat` (it updates itself). Check:
- Loot: search the same fridge twice; it must stay empty. Loot never comes back.
- Gas and food: leave a gas can and a vegetable in a crate for a few game days; they should go stale or spoil, and the HUD or inventory should say so.
- Infamy: build and run a loud machine for a while; the stats screen (wherever M11 puts it, the PR will say) should show infamy rising.
- New zombies: after enough noise, at least one runner or screamer should show up. Note whether it felt fair or cheap.

**After S1-3 (P0) merges.** Start a new game, die once on purpose, then quit. Check:
- A file appeared under `%APPDATA%\Godot\app_userdata\Noise Floor\sessions\` with a readable summary under 40 lines.
- On a new game, hints told you what to do first (find the crate, build a smelter, it's loud, wall it or muffle it) and went away by themselves.

**Then Playtest #1.** Thirty minutes, ideally with Kaleb, then fill in the template at the top of `docs/PLAYTESTS.md` and paste the session log. Short answers are fine. That entry decides Sprint 2.

## Rules of play for builders

- Branch from `main` in a worktree named `C:/projects/noise-floor-<task>`; leave `C:/projects/noise-floor` on `main`.
- Finish means: tests green, a screenshot looked at, a devlog entry with "Try it" `play.bat` commands and the model that built it, a pull request. Then stop and report. Don't start the next task.
- One heavy job at a time on Emmitt's PC. Before running tests or screenshots, check that no other Godot or Blender is running; wait if one is.
- Keep output compact. Emmitt pays per token.

## Backlog (Sprint 2 and later, in `docs/DIRECTION.md` order)

W1 real town · M12 skills · M13 loot · stress test (cloud session) · M14 guns · M15 automated defense · M16 seasons · M17 further out.
