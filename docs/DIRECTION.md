# Direction — where Noise Floor goes next

*Written 2026-10-12 by Claude Fable 5.1 at Emmitt's request, after reading the design doc, the devlog, the sim code and the first fifteen pull requests. This file outranks the milestone list in `GAME_DESIGN.md`: when they disagree, follow this one. Update it when a decision below changes.*

## Update, 2026-10-15: a much bigger world, then Satisfactory-style building (Emmitt's calls)

*Written by Claude Opus 5.5 at Emmitt's request. He said: "I like the game a lot but it needs a much bigger world. Then we can start working on in-depth mechanics and building", picked **town + countryside** (about 15-20x the old map) over "bigger town only" and "several towns", and later: "I'd like the building to be more like Satisfactory but it doesn't feel like it fits into the game right now." Sprint 4's feature freeze is over by his call.*

**Why building doesn't fit today:** nothing in the survival loop needs a factory. Loot gives you everything, and a machine only makes noise that brings zombies, so building is all risk and no reward (the session logs: 0-1 builds per session). The fix is to make the factory the answer to survival, the Satisfactory way, with Noise Floor's own twist: the bigger the factory, the louder it is and the bigger the hordes, so it has to make the ammo, turrets and walls that defend it.

**Order of work:**
1. **W3a: the bigger world's groundwork** (done in this PR): the road network (`WorldMap`), the map 720 x 760 m, waves starting out of sight 110-180 m along the roads, the navmesh in 64 m tiles, woods, fields, the highway with wreck jams, the map's edge.
2. **V35: zombies die facing you** (Emmitt saw every zombie turn its back as it died): a backward fall that keeps facing you, mixed with some falling forward toward you.
3. **F1-F3: building like Satisfactory.**
   - **F1 resource nodes** (done, #80): places in the new world you can only work with machines: scrap piles at a junkyard, the gas station's tank (fuel), a farm well (water), a quarry (stone). Build a salvager/pump/drill on one and belt it home. Loot gets scarcer as the days go on (finite loot is in already), so the factory takes over.
   - **F2 the Hub and milestones** (done): deliver parts to the Hub to unlock new machines and tiers; the last goal is a radio tower that calls in a rescue.
   - **F3 build feel** (done): drag to lay a row of foundations, walls or belts; belts on bare ground (walk-over) that fill crates; splitters and mergers (Logistics milestone); in/out tabs on every router.
4. **W3b downtown** (done: grocery, pharmacy, hardware store, police station with an armory of gun lockers, gas station with pumps and a fuel-tanker node), **W3c more streets of houses** (done: West and East Street, about two dozen houses), **W3d the countryside** (done: two farms with barns and cornfields round their wells, the hunting cabin, searchable wrecks on the highway and in the junkyard), each with its resource nodes from F1.
5. **W3e population and balance** (done: far zombies think every fourth tick, loot grows with distance (data/areas.json), eight roadside wanderers, the map on M): zombies and loot per area, far zombies thinking less often, and a map (an item or a screen) so the bigger world is easy to find your way round.

## Update, night of 2026-10-13: Sprint 4, "The first 30 minutes" (Emmitt's call)

*Written by Claude Opus 5.5 at Emmitt's request. He asked how to make Noise Floor feel like a AAA game, then said: stay free for now, write the sprint into direction, and start it.*

Real AAA is a hundred-million-dollar budget and hundreds of people. The target is a game that feels premium in a narrow slice, the way Road to Vostok (one developer, Godot) does. Noise Floor doesn't lack systems; it lacks finish. So:

- **Feature freeze for Sprint 4.** No new systems, nothing from M17b. Bug fixes, tuning and polish only. Playtest notes still come first, as the rest of this file says.
- **The goal is the first 30 minutes at trailer quality.** A new game starts at 08:00 on day 1 of summer, and sunset is 21:00, so in real time the slice is day 1 (minutes 0 to 13), the first night (13 to 21) and the next morning (21 to 30):
  - **0–5:** wake up, read the first tip, open the crate, search a house, hear the town.
  - **5–13:** first smelter and generator. It's loud, and the first zombies come up the street.
  - **13–21:** dusk, then the first night: fog, the flashlight, a fight at the walls, the stings.
  - **21–30:** dawn, the base log of what happened, the next goal clear.

  Every pass in this sprint is judged by how those 30 minutes look, sound and feel.
- **Free assets only (Emmitt, 2026-10-13).** No paid packs, no freelancers for now. Art comes from Codex (image generation, plus Blender scripts Codex writes and runs) and the Blender kit. Third-party files stay CC0 with Emmitt asked first.
- **Who does what.** Codex makes art on Emmitt's ChatGPT plan, one job at a time (parallel `codex exec` runs deadlock on this PC). Claude writes the code, wires the art in, runs tests and screenshots, and reviews each PR. One heavy job (Godot, Blender) at a time.
- **Exit test.** A 60-second capture of those 30 minutes that Emmitt would post, plus Playtest #2 on the polished build (it replaces Sprint 3's S3-2 and S3-3).

The board is in `docs/SPRINT.md`. In order of impact: lighting and atmosphere, textured zombies and guns, game feel, sound, a written art direction, first-person arms, zombie hit reactions and deaths, then the playtest.

**Added by Emmitt the same night (an exception to the freeze, his call):** attack animations, weapons that wear out and break, and Zomboid weapon skills (Blunt, Blades, Axe, plus Maintenance). Board items V9 to V11.

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

- **Decided 2026-10-13: free assets only for now.** No paid asset packs or freelance artists. Revisit if Codex and Blender can't make convincing zombies and first-person arms.

- **Who is the player?** The recommendation: Emmitt and Kaleb on a forgiving "normal"; hardcore later as an option. Tuning follows from this.
- **Map style for W1.** Recommendation: a kit of rooms assembled by seeded code. The alternative is hand-built scenes in the Godot editor, which look better per hour of human work but can't be built in cloud sessions or tested headlessly.

## What this review did not do

It did not play the game, and it did not run the tests on the PC (another session had Godot busy; one heavy job at a time). It read the code and the docs. The first playtest is worth more than this file.
