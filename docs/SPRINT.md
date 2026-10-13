# Sprint 2 — "Into the houses"

*Started 2026-10-12, right after Sprint 1 closed: #16, #17 and #18 merged, and Emmitt's first play (on the old build, before play.bat caught up) said two things: no way into the buildings, and cars that would not drive. Lead: Claude Fable 5.1. Builders: Claude Opus 5.5. QA: Emmitt and Kaleb. Budget rule unchanged: the lead checks the 5-hour window before launching a builder, stops launching at 75%, one build agent on the PC at a time; cloud sessions on the credit don't count against it.*

## Sprint goal

Emmitt opens a front door, loots a kitchen in the dark, closes the door and hears the street go quiet. Then writes Playtest #1.

## Board

| # | Task | Owner | Status | Done when |
|---|---|---|---|---|
| S2-1 | P1 playtest fixes: car prompts explain keys and wrecks; play.bat writes an update log and a version line the title screen shows | Opus 5.5 agent | Merged (#20) | PR merged; Emmitt sees the version on the title screen |
| S2-2 | W1a — into the houses (plan: `docs/plans/W1.md`) | Opus 5.5 agent on the PC, worktree `noise-floor-w1a` (Emmitt chose local, 2026-10-13) | In progress | PR merged; walk in, loot inside, closed door muffles; tests and screenshots per the plan |
| S2-3 | Playtest #1 on the merged build (30 min, with the session log) | Emmitt + Kaleb | Ready now | Entry in `docs/PLAYTESTS.md` |
| S2-4 | W1b — life inside: zombies in some houses, factory floor, hordes on roads, props | Decided after Playtest #1 | Backlog | |
| S2-5 | Sprint review: read Playtest #1 and the session logs; plan Sprint 3 (M12 skills unless the playtest says otherwise) | Fable | Waiting on S2-3 | Sprint 3 board here |

## Overnight run, night of 2026-10-12 to 13

Emmitt went to bed and left the PC on. The lead runs one Opus 5.5 builder at a time, reviews each pull request, and checks the 5-hour window before every launch (no launch above 75%; wait for the reset instead). Each builder branches from the previous one, so the morning merge order is the queue order; merging the first retargets the next on GitHub. Queue:

1. **W1a — into the houses** (running). PR against `main`.
2. **Stress test**: one headless test with 200 zombies, 50 machines and a game-day, printing the time per tick, the noise query and the navmesh bake. Branch from W1a so it measures the town pieces too. Numbers only, no fixes.
3. **W1b — life inside**: a zombie in about one house in three, the factory as a grid interior with a roof, hordes that follow the road. Branch from W1a. Furniture props stay out (PC art).
4. **M12 — skills and perks**, from `GAME_DESIGN.md`: skills that level by doing, the Strength carry limit and bags, perk points, the three trees with a few perks each, a skills screen. Branch from W1b. Only if the window allows.

Not tonight: anything needing Codex or Blender, W1 tuning (waits for Playtest #1), M11 tuning, M13+.

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
