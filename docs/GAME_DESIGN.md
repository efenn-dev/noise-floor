# Noise Floor — Game Design

*Working title. First-person survival automation: Project Zomboid's survival meets Satisfactory's factory building.*

## Pitch

The world ended a few weeks ago. You're alone on the edge of a dead factory town. First you scavenge to stay alive (food, water, sleep, wounds), like Project Zomboid. Then you build machines and conveyor belts, like Satisfactory, so the things you need get made automatically: canned food, clean water, power, ammo, wall panels.

**The catch: machines make noise, and noise draws the dead.** A bigger factory is a louder factory. Every upgrade trades more production against staying hidden.

## Pillars

1. **Noise is the price of progress.** Every machine has a loudness. Sound spreads, fades with distance, and gets muffled by walls. Zombies walk toward what they hear. You manage it by running loud machines by day, muffling them (costs materials), building decoy noisemakers far from base, and shutting down at night.
2. **Automation exists to solve survival.** Every production chain answers a real need: hunger, thirst, defense, power. There are no abstract points.
3. **Day is for work, night is for fear.** Long days (16 h) and short, dangerous nights (8 h). Nights are dark, zombies are more numerous, and sound carries further.
4. **Readable, grid-snapped building in first person.** Foundations, walls, machines and belts snap to a grid, and belts connect machine ports.
5. **Small and finished beats big and broken.** Every milestone leaves a game you can launch and play.

## Core loop

- **Minute to minute:** explore → loot → fight or sneak → carry it home.
- **Hour to hour:** craft by hand → build a first machine (fed by hand) → connect machines with belts → add power → production runs by itself → it's loud → zombies come → build walls, traps and turrets → expand.

## Systems (v1 scope)

### Player and survival
Health, hunger, thirst, fatigue, and stamina (sprinting, swinging). Simple injuries: bleeding, fixed with bandages. Death respawns you at your bed and drops your inventory in a bag; a permadeath "hardcore" option comes later.

### Scavenging
Searchable containers in houses, cars and shops (cabinets, fridges, car trunks), each with a loot table. Searching takes time and makes a little noise.

### Building
Build menu with a ghost preview, grid snapping (2 m foundations), and rotation. Costs come out of your inventory and deconstructing refunds 100%. Pieces: foundation, wall, doorway, door, barricaded window, stairs.

### Production (first chains)

| Need | Chain |
|---|---|
| Metal | Scrap → **Smelter** → Metal plate |
| Parts | Metal plate → **Press** → Nails / Wall panel / Ammo casing |
| Wood | Logs or furniture → **Saw** → Planks |
| Water | Rain collector → **Purifier** → Clean water |
| Food | Seeds → **Planter** → Vegetables → **Canner** (+ metal plate) → Canned food |
| Power | Fuel (gas cans, siphoned from cars) → **Generator** → Power |

Machines have input and output buffers, and each recipe takes a set time. Belts carry items between ports at a fixed speed. Splitters and mergers come later.

### Power
A generator burns fuel and feeds a power network through poles. Machines draw watts, and if demand exceeds supply, everything stops. Later: solar, wind, batteries. **Quiet power is a big reward because of noise.**

### Noise (the signature system)
- Every source has a **loudness** L from 0 to 100. Continuous: machines, generators. One-off: gunshots, breaking glass, sprinting footsteps.
- **Heard level** at distance d meters = `L − 20·log10(max(d, 1)) − 10 × (walls in between)`.
- A zombie hears a source if heard level ≥ its threshold (20 by day, 14 at night). Example: an unmuffled generator (L = 80) carries ~1 km in open air; muffled to 60, it carries ~100 m.
- A **Director** builds up "heat" from continuous noise near your base. As heat crosses thresholds it sends wanderers, then groups, then a horde along the roads. Heat cools down when it's quiet.
- **Mufflers** are a machine upgrade: −15 loudness, but they cost materials and slow the machine 10%.

### Zombies
Slow shamblers in the Zomboid style, often in groups. States: idle/wander → investigate a sound → chase (on sight) → attack (you or your walls). They wear down structure HP over time. Later variants: rare runners, crawlers.

### Combat
Melee first (pipe, bat, axe): stamina cost, knockback, bonus for hits to the head. Guns come later, and **they're loud**.

### Time
One real minute = one in-game hour, so a full day is 24 real minutes. The sun is up 05:00–21:00. `src/sim/game_clock.gd` holds the rules.

## Tech shape (see CLAUDE.md for rules)
- `src/sim/` holds the game rules as plain classes on a fixed tick (inventory, recipes, machines, belts, power, noise, director, survival), all with headless tests.
- `src/world/` holds what you see and touch: player controller, build ghost, machine and zombie visuals, HUD.
- `data/` holds content (items, recipes, machines) as JSON, checked by a test.

## Milestones

Each milestone is one cloud session or branch, sized to finish. Check the box when it's merged.
**First playable = M1–M5:** walk a dark town, build a noisy machine line, and defend it from the zombies it attracts.

- [x] **M0 — Skeleton.** Godot 4.7 project, greybox town, day/night sun, headless tests, screenshot tool, cloud bootstrap.
- [x] **M1 — Walk the town.** First-person controller (WASD, mouse look, sprint, jump, crouch), flashlight, collisions with the greybox town, HUD clock, Esc to free the mouse. Game clock runs on a fixed sim tick. A test (or scripted run) proves the player can walk forward and is blocked by a wall. Screenshot flag gains a camera pose so shots can be framed.
- [x] **M2 — Build.** Inventory (sim, tested), build mode with ghost preview, 2 m grid snap, rotate, place and deconstruct foundations and walls; debug kit gives starting materials. Building data in `data/`.
- [x] **M3 — Machines and belts.** Item and recipe data, Smelter + Press, belts between ports, items visibly moving, all simulated headlessly on the fixed tick (tests prove throughput: N scrap in → N plates out in T seconds). Hand-feed and take output with interact.
- [x] **M4 — The dead.** Zombies on a navmesh: wander, see, chase, attack the player and walls. Player health, melee weapon, death and respawn. Zombie brain is sim-side and tested (state transitions).
- [x] **M5 — Noise.** Noise sources, the heard-level formula, walls muffling, zombies investigating sounds, the heat Director sending groups at night, mufflers. Debug overlay shows noise rings. **First playable.**
- [ ] **M6 — Survive.** Hunger, thirst, fatigue, bleeding; searchable containers with loot tables; eat and drink; water and canned-food chains.
- [ ] **M7 — Power.** Generator + fuel, poles and wires, power draw, brownouts; first quiet power source.
- [ ] **M8 — Defend.** Doors, barricades, traps, a turret that uses produced ammo; structure HP and repair.
- [ ] **M9 — Keep it.** Save/load, main menu, settings (mouse sensitivity, volume, day length), pause.
- [ ] **M10 — Look and sound.** CC0 models (ask Emmitt first), machine hums and zombie moans (sound sells the noise theme), fog and flashlight atmosphere, title screen.

## Open questions (decide when we get there)
- Map: hand-built town vs. procedurally generated blocks? (Hand-built greybox until M6.)
- Permadeath default or opt-in?
- How hard should nights be? Tune after M5 playtests with Emmitt (and Kaleb).
