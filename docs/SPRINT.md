# Sprint 1 — "Someone plays it"

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
