# Read me first (Emmitt)

*Updated 2026-10-13 11:40Z. Emmitt is at work; the lead is running a day queue (below) with the same rules. Builders are running; the merge list grows at the bottom as PRs appear.*

**Merge these on GitHub, top to bottom, each against `main`:** #24 (stress test + W1b), #26 (M12 skills and perks), #27 (M13 loot), #28 (W1c furniture), #29 (M14 guns), #30 (M15 automated defense), #31 (P2 gun feel and screens), then #25 (this board) last. Every one targets `main`, so the order only keeps the diffs readable; merging a later one first is safe. After the last merge, `play.bat` updates itself; the title screen shows the build in the corner.

**Checks on the final branch: 4371, all passing.** Save files from any earlier version still load (each milestone bumped the save version and keeps a fixture of the one before).

**What to play, in this order:** a new game. Open a front door and loot a kitchen; one house in three has a zombie inside. Press K for skills, Tab for your gear (colours are rarity), E on the workbench to fit a scope, Q to swap pipe and gun, right click to zoom, L for the base log. North end of the road: the factory hall, Old Pete, his axe and rifle. `play.bat --demo-defense --time=22` shows a defended base at night with floodlights, sensors and a decoy.

**What nobody has verified:** a human playing any of it. Every number is a builder's guess checked by a test, which is why the next step is still your thirty minutes and a `docs/PLAYTESTS.md` entry. Known soft spots the builders flagged: house zombies barely hear a search by day (they find you by sight); town doors and beds refund their full build cost when removed; zooming adds no accuracy; the skills screen needs about 1220 px of width; the decoy noisemaker adds no Director heat by design.

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
1. **P3 — playtest readiness** (running): a help screen on F1, key hints that fit the moment, a session log that covers gear, skills, guns and the base log, town doors and beds that salvage instead of refunding, crosshair contrast.
2. **Q1 — integration soak and screenshot tour**: a headless scripted "bot day" over three game-days through the whole stack with script-error detection, plus `tools/tour.sh` that takes a dozen screenshots around town for the lead to review; fix what breaks.
3. **A1 — street dressing** with the Blender kit: lamp posts, mailboxes, fences, trash cans, a few trees, placed by the town plan. No Codex.
4. **M16 — seasons**: a calendar, winter stops crops, cold needs heat, sound carries farther on cold nights.
5. **A2 — zombie variety** (if time): more body variants from the rigged zombie script.
6. **M17 — further out** (only if the day allows): a second, harder area and the first big project.
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
