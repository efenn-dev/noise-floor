# Direction — where Noise Floor goes next

*Written 2026-10-12 by Claude Fable 5.1 at Emmitt's request, after reading the design doc, the devlog, the sim code and the first fifteen pull requests. This file outranks the milestone list in `GAME_DESIGN.md`: when they disagree, follow this one. Update it when a decision below changes.*

## Update, evening of 2026-10-13: where things stand

In the thirty hours after this file was written, builders (Claude Opus 5.5, one at a time, each from a plan by the lead) delivered the whole long-game list except outposts: W1a–W1c (houses with rooms, loot, furniture, a zombie in some, the factory hall, hordes down the road), M12–M16 (skills and perks, loot with rarity and gear, guns and the workbench, automated defense with sensors and the base log, seasons with cold and the stove), M17a (the industrial park and the water tower project), two art passes (street dressing, five zombie bodies), three polish passes (gun feel, playtest readiness with a help screen, soak fixes) and three QA passes (a stress test, a bot that plays game-days headless, a twelve-shot tour). Every one is a pull request against `main` with tests; the suite is past seven thousand checks.

**The rule from the top of this file is now the only thing that matters:** nobody has played it. Everything above the line "Order of work from here" still holds, with the order replaced by this:

1. **Playtest #1.** Thirty minutes, the template in `docs/PLAYTESTS.md`, the session log pasted in. Then a second session a day later.
2. **Sprint 3 is tuning from those notes, not new systems.** Likely candidates the builders flagged, to be confirmed by play: infamy and heat climb fast once a generator runs; house zombies barely hear a search by day; the first runner's timing; whether the cold in winter is fair; whether the park is too hard; the bot dies two to four times a game-day, mostly to street zombies.
3. **M17b** (outposts, the substation and radio-tower projects) and the hardcore option come after two playtests, not before.
4. **Before every playtest**, run `tools/soak.sh --days=3` and `tools/tour.sh` on `main` and fix what they find first. They are cheap and they caught real bugs (a NaN that spammed 836,000 warnings an hour after a car ride; zombies wrecking furniture).

**Process rules learned:** every pull request targets `main` (stacked ones merged into each other once); one builder at a time on this PC; a builder costs about five points of a 5-hour usage window; the lead reviews each PR and keeps `docs/SPRINT.md` honest.

## What's right. Keep all of it.

- **The shape of the code.** Rules in `src/sim/` on a fixed 20 Hz tick, seeded, with no scene nodes; what you see in `src/world/`; content in `data/*.json` checked by a test. This is why 15 milestones landed in one day without the game falling over. Don't let a feature bypass it "just this once".
- **The test loop.** 785 headless checks in seconds, `tools/shot.sh` for pictures, one milestone per worktree and pull request, a devlog entry per milestone, and `play.bat` that updates itself. Every session should leave these stronger, never weaker.
- **Godot 4.7.** Emmitt asked today about moving to Unreal or Unity. The answer is no, for this game. The tests, the screenshot loop and the Blender kit are the asset; Unreal would throw them away and is the hardest engine for an AI to work in (binary scenes, Blueprints). M10 showed Godot can look right with textures, fog and models. The long-term Unreal FPS goal is better served by finishing this game, then starting a dedicated Unreal prototype with what was learned.

## The one thing that's wrong: nobody has played it

Fifteen pull requests merged in a day. One recorded playtest, which found a mouse bug and a "cursed" zombie model. Every number in `data/` (loudness, heat thresholds, drain rates, loot odds, zombie damage) was picked by a model and checked by a test, never felt by a person. The design doc's own gate, "tune after M5 playtests with Emmitt (and Kaleb)", was skipped, and the list kept growing: seven more system milestones (M11–M17) are queued for a game no one has played for half an hour.

Systems are cheap now. Finding out whether the game is fun is the expensive, scarce thing, and only Emmitt and Kaleb can produce it. So:

**Rule: after each milestone merges, the next one is chosen from a playtest, not from the list.** A playtest is Emmitt (and Kaleb when he's willing) playing at least 30 minutes on `main` via `play.bat`, then filling in one entry in `docs/PLAYTESTS.md` (template at the top of that file). The next session reads the newest playtest entry before anything else and fixes what it says first.

## Order of work from here

M11 (the world gets worse) was already started by another session when this was written. Let it land, kept small: finite loot, stale gas, spoilage, the infamy score and the stats screen. Hold the tuning of the evolved zombies for the first playtest. Then:

1. **P0 — Playtest kit** (one short session, no new game systems).
   - A session log. On death and on quit the game writes a compact summary to `user://sessions/<date>.txt`: minutes survived, deaths and what killed you, heat peaks, machines built, zombies killed, loudest moment, and what you did in your first five minutes. Sessions read that file instead of asking Emmitt to describe his run or reading a transcript. Keep it under 40 lines.
   - `docs/PLAYTESTS.md` with the template (done with this file), and the line in `CLAUDE.md` that makes every session read it (also done).
   - A first-five-minutes check: does a new player know what to do? If not, a short hint sequence on the HUD (find the crate → build a smelter → it's loud → wall it or muffle it), nothing more.
   - Then **Playtest #1.**
2. **W1 — A real town.** For a first-person game the world is the thing you stare at, and today the houses are textured boxes with the loot standing outside them. This is the biggest unforced risk left and it blocks M17 (a second area) outright. Build a small kit of room layouts from the Blender kit (a few house interiors, a shop, the factory floor), put containers inside, give houses doors, and make the town's buildings muffle sound the way built walls do (the noise system's own listed gap). Keep the seeded code assembly: it fits the repo and the tests; just assemble from rooms instead of boxes. Hordes should follow the roads.
3. **M12 Skills, then M13 Loot, before more pressure.** The game currently has no progression: nothing to get better at, nothing to find. For a kid playtester that is why you quit. Rewards before pressure is the prior; Playtest #1 can overrule it.
4. **M14 Guns, then M15 Automated defense**, with a **stress test** first: one headless test that runs 200 zombies, 50 machines and 10 game-days in seconds, and reports how long a tick takes. The noise query is zombies × sounds with a grid walk per pair every half second, the Director re-counts walls in eight directions once a second, and the navmesh re-bakes the whole town after every build. Fine today; M11 and M15 assume many more zombies and a base that fights while you're away. Find the cliff before building on it.
5. **Save compatibility, done with every milestone from now on.** `SaveGame.VERSION` is 1 and a mismatch refuses to load. Every milestone that adds state either leaves the version alone (and silently half-loads) or breaks every save. Once Emmitt and Kaleb have real saves, a merge that wipes them ends playtesting. Bump the version per milestone, add a small per-version upgrade step (fill in defaults for new keys), and keep a committed fixture save from the previous version that a test must still load.
6. **M16 Seasons, M17 Further out**, in that order, each after a playtest.

## How a session should work on this game now

- Start by reading this file, the newest `docs/PLAYTESTS.md` entry, and the latest `docs/DEVLOG.md` entry. Playtest notes newer than the last milestone come first.
- One milestone (or one playtest's fixes) per worktree and pull request. Say what to try with `play.bat` commands. Leave `C:/projects/noise-floor` on `main`.
- **Which Claude does what.** Fable writes direction, the plan at the top of each milestone, and reviews the pull request; it also takes the hard bugs. Opus 5.5 is fine for building from a Fable-written plan. Either way, say in the devlog which model built the milestone.
- **Where.** Cloud sessions (while the credit lasts, about 2026-11-05) for anything that is only sim, data and tests: M12, M13, the stress test, save upgrades, the session log. PC sessions for art (Codex and Blender live only there), GPU screenshots and anything Emmitt needs to try right away. One heavy job at a time on the PC.
- **Token discipline.** Prefer a compact report file (the session log, a test summary) over reading transcripts or frames. Don't launch multi-agent workflows on this project without asking Emmitt and quoting a cost.

## Decisions Emmitt still owns

- **Who is the player?** The recommendation: Emmitt and Kaleb on a forgiving "normal"; hardcore later as an option. Tuning follows from this.
- **Map style for W1.** Recommendation: a kit of rooms assembled by seeded code. The alternative is hand-built scenes in the Godot editor, which look better per hour of human work but can't be built in cloud sessions or tested headlessly.

## What this review did not do

It did not play the game, and it did not run the tests on the PC (another session had Godot busy; one heavy job at a time). It read the code and the docs. The first playtest is worth more than this file.
