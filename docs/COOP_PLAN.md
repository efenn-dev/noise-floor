# Co-op plan: The kid plays with Emmitt

*Written 2026-10-19 by Claude Fable 5.1 at Emmitt's request ("my son really wants to play with me so could you start planning for that"). This is a plan, not a build. It says what two-player means for this game, the one design I recommend, the order of work, and the three decisions Emmitt owns.*

## In plain words

Today the game is built for one person. One set of pockets, one body, one set of skills, and every zombie thinks about one player. Letting the kid play alongside Emmitt means:

1. **Two players in the rules.** Two bodies, two sets of pockets and gear, two skill trees, two hunger meters, two deaths. One shared world: the base, the machines, the belts, the zombies, the clock, the Hub.
2. **Two PCs talking over the house network.** Emmitt's PC runs the game ("the host"). The kid's PC joins it and shows him the same world. No internet needed, no accounts, no port forwarding: it's the same network the family drive already uses.
3. **A face for the other player.** Each of you needs to see the other one walking about, so a survivor body (made from the same kit as the zombies, in normal skin and the gear you wear).
4. **Kid-proofing.** The kid can't read yet and dies more. Co-op is the chance to fix that in person: a "where's Dad" arrow, going down instead of dying when Dad is near (he can pick you up), respawning at Dad's bed, and no friendly fire.

It's the biggest change the game has had. Honest size: **six to eight sessions**, and the first one has nothing to show on screen (it rewires the rules so they can hold two players). Everything single-player keeps working the whole way through; nothing waits on the end of the plan.

## The one design I recommend

**The host runs the game; the other PC is a window onto it.**

- Emmitt's PC runs the sim exactly as today. It is the only place the rules run.
- The kid's PC keeps a copy of the sim's state that the host refreshes many times a second (zombies, belts, machines, doors, the clock, both players). All of the game's drawing code already reads the sim's state and draws it, so on the kid's PC that code keeps working unchanged: it's just reading a copy.
- When the kid does something (opens a door, swings, builds, loots), his PC does it on its own copy at once (so it feels instant) **and** sends the same action to the host. The host does it for real, and the next refresh overwrites the kid's copy with the truth. In a family game the two almost never disagree; when they do (both open the same fridge), the host wins.
- The kid's own walking is his PC's business (his body is a normal physics body there); his position is sent to the host every tick, and the host trusts it. No anti-cheat in a family game.

Why not the alternatives:

- **Both PCs run the rules in lockstep** (each sends only its key presses). The sim is deterministic on purpose, which makes this tempting, but zombies find their way with the world's navigation mesh, which lives outside the sim, and the first tiny difference between two PCs would split the two games apart for good, with no way to tell. Too fragile.
- **Two players on one PC, split screen.** the kid has his own PC and likes to stream from it; two keyboards on one desk doesn't fit the family.
- **A server on the internet (hermes).** Not needed in one house. The design above can be pointed at a relay later if cousins ever want in; nothing in it rules that out.

## What is shared and what is per player

| Shared (one copy, the host's) | Per player (one each) |
|---|---|
| the world, the town, the build grid, every piece | position, facing, the camera |
| machines, belts, power, carts, the Hub and its milestones | pockets (inventory), gear worn, weapon in hand, the hotbar |
| loot containers and what's in them (one search at a time per container) | health, food, water, energy, stamina, warmth, bleeding |
| zombies, the Director's heat and waves, the clock and seasons | skills, perks and the skill tree |
| what the base has learned (Learning), felled trees, stripped cars | deaths, the respawn bed, the session log |
| the base log | the objectives of the first night (ate, drank, found a bed); later chapters are shared |
| the save file (holds every player by name) | messages on the HUD ("Door opened" is yours, not his) |

Zombies target the **nearest** living player, hear both, and a wave walks to the loudest sound as today. The Director's heat is one number for the whole base.

## The order of work

Each phase is one pull request (or two), tests green, single-player untouched, and something to try at the end except the first.

### Phase A — the rules can hold two players (1 session, nothing to see) — DONE 2026-10-19 (see the devlog)

The sim's one `player` becomes `players[]`, with everything that was one-per-game becoming one-per-player: PlayerStats, Inventory, Gear, Gunplay, Hotbar, Skills, position and facing, the active search, the car being driven, the pending vault. `sim.player`, `sim.inventory`, `sim.gear` and friends stay as aliases for player 0 so the ~260 places in the drawing code that use them keep compiling, and get rewritten to "the local player" in Phase C. Zombies, the Director, noise, loot and cars take a player index or a position instead of assuming the one. Saves hold a `players` list (an old save becomes a one-player list). The soak and every test still pass. A headless test plays two players in the same sim: both loot, both build, a zombie switches to the nearer one.

### Phase B — the kid can walk into Dad's world (1–2 sessions) — DONE 2026-10-20 (see the devlog)

- Title screen: **Host a game** / **Join Dad's game**. Hosting opens a port on the house network and announces itself (a UDP broadcast every second), so joining needs no typing: the launcher lists games it hears. A typed address stays as the fallback.
- Godot's built-in ENet networking (`ENetMultiplayerPeer`, `@rpc`), nothing third-party.
- The joiner receives the world as the host has it (seed, every piece, machines, containers' searched flags, zombies) and builds it with the same code a save-load uses today; then a steady stream of small refreshes: players, zombies within view, belt items, machine states, pieces changed, the clock. Order of magnitude on a home network: a few dozen kilobytes a second. Fine.
- The other player is drawn as a capsule with a name tag for now; the local player walks and looks as today. No actions yet.

### Phase C — the kid can play (2 sessions)

- Every action the drawing code asks the sim for (E, swing, fire, build, take down, loot moves, equip, use, hotbar, car, workbench, hub, sensors) goes through one small gate: run locally, send to the host. The host runs it and the refresh carries the result. Messages come back to the player who acted.
- HUD, screens and the build menu read the local player. The objectives panel shows the shared chapters.
- Zombies attack whoever is nearer; turrets and traps don't hurt players; no friendly fire between players.
- Each player's skills and tree (the skill tree work pays off here: it's per player already).

### Phase D — it holds together (1–2 sessions)

- The host's save holds both; the kid rejoins by name with his pockets and perks as he left them; drop in and out mid-game.
- **Downed, not dead:** with the other player within 40 m you go down for 60 s instead of dying; E on you picks you up (half health). Alone, you die as today. Respawn at your own bed, or the other player's.
- **Where's Dad:** an arrow at the screen's edge toward the other player and the distance, on by default for the joiner.
- A survivor body from the zombie kit (normal skin, no wounds; it wears the gear you wear; the UAL walk/run/idle clips). The first-person arms stay as they are for your own view.
- A second session log for the joiner, and the host's log gains a "with the kid: minutes together, who picked whom up" line.
- The soak gets a scripted second player (a bot that follows the first) so this is tested every time.

### Phase E — polish (1 session)

- Bandwidth: zombies beyond 60 m refreshed less often, belt items only within 40 m, pieces as change events only.
- Lag hiding for the other player's body (interpolate between refreshes).
- The portable launcher for the kid's PC: "Join Dad's game" straight from the launcher; the family drive can carry the host's address so even the broadcast isn't needed.
- Kid mode on the joiner (Emmitt's call): more health, slower hunger, zombies prefer the host.

## What could go wrong

- **The single-player assumption is everywhere.** 260 places in the drawing code reach for `sim.player`, `sim.gear`, `sim.guns`, `sim.inventory`. Phase A keeps them compiling with aliases; Phase C has to visit each one. It's mechanical but long, and the place a bug hides.
- **The host's PC is doing double duty.** It runs the whole sim, its own drawing, and now sends refreshes. This PC hard-powers-off under sustained load (see the memory note); keep the refresh rate modest and watch temperatures on the first long session.
- **the kid's PC.** Unknown specs. The joiner is lighter than the host (no sim), but it draws the same world. The graphics preset (`--graphics=low`) exists already.
- **Saves.** The format changes (a `players` list). Phase A bumps the save version and keeps a fixture from today loading, as every milestone does.
- **Testing without two PCs.** Two Godot instances on one PC (host headless, joiner windowed, or both headless) is enough for the tests and the soak. A real two-PC run is the playtest.

## Decisions Emmitt owns

1. **Same house only, or over the internet too, one day?** Recommendation: same house only. If "one day" is likely, say so now: it costs nothing today and shapes Phase B's address handling.
2. **Should the kid's character be easier than yours?** Recommendation: yes, a kid mode on the joiner (more health, slower hunger, zombies prefer the host), switchable, so the game stays fun for both.
3. **Keyboard and mouse, or a controller, for the kid?** There is no controller support today. If he'd play better on a pad, that is its own small milestone before Phase B.

## What this plan does not do

- It does not touch the skill tree, which is a separate plan (`docs/SKILL_TREE_PLAN.md`) and should land before Phase C so each player gets one.
- It does not pick a date. One phase per session, in order, after PR #108 (P12) is merged.
