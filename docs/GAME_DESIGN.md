# Noise Floor — Game Design

*Working title. First-person survival automation: Project Zomboid's survival meets Satisfactory's factory building.*

## Pitch

The world ended a few weeks ago. You're alone on the edge of a dead factory town. First you scavenge to stay alive (food, water, sleep, wounds), like Project Zomboid. Then you build machines and conveyor belts, like Satisfactory, so the things you need get made automatically: canned food, clean water, power, ammo, wall panels.

**The catch: machines make noise, and noise draws the dead.** A bigger factory is a louder factory. Every upgrade trades more production against staying hidden.

**There's no ending.** The town runs dry, the dead get worse the louder you get, and the goal is to last, gearing up with Diablo 2-style loot and Tarkov-style guns, and leaving automated defenses to hold the base while you're out.

## Pillars

1. **Noise is the price of progress.** Every machine has a loudness. Sound spreads, fades with distance, and gets muffled by walls. Zombies walk toward what they hear. You manage it by running loud machines by day, muffling them (costs materials), building decoy noisemakers far from base, and shutting down at night.
2. **Automation exists to solve survival.** Every production chain answers a real need: hunger, thirst, defense, power. There are no abstract points.
3. **Day is for work, night is for fear.** Long days (16 h) and short, dangerous nights (8 h). Nights are dark, zombies are more numerous, and sound carries further.
4. **Readable, grid-snapped building in first person.** Foundations, walls, machines and belts snap to a grid, and belts connect machine ports.
5. **No ending.** You can't beat the world. It gets harder the more you build, and your skills and gear grow to match. The goal is to last.
6. **Small and finished beats big and broken.** Every milestone leaves a game you can launch and play.

## Core loop

- **Minute to minute:** explore → loot → fight or sneak → carry it home.
- **Hour to hour:** craft by hand → build a first machine (fed by hand) → connect machines with belts → add power → production runs by itself → it's loud → zombies come → build walls, traps and turrets → expand.

## Systems (v1 scope)

### Player and survival
Health, hunger, thirst, fatigue, and stamina (sprinting, swinging). Simple injuries: bleeding, fixed with bandages. Death respawns you at your bed with your skills kept. Everything you carried stays where you died until you go back and loot it, and nothing despawns if you die again first. M4 does this with a bag; later it becomes your body. A permadeath hardcore mode comes later as an option.

### Scavenging
Searchable containers in houses, cars and shops (cabinets, fridges, car trunks), each with a loot table. Searching takes time and makes a little noise.

**Storage (added in M6):** storage crates hold what you can't carry. Building and hand-feeding machines draw from your pockets first, then from any crate within 30 m, and build refunds go back into the crate. The starting kit begins in a crate next to the spawn point.

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

**As built (M7):** poles link anything within 12 m; other powered pieces link to neighbours within 3 m. Generators (100 W, loudness 80) burn gas cans siphoned from cars, only in proportion to the load, and are silent when idle. Solar panels (60 W x daylight) are silent and used first. Smelter 40 W, press 30 W, purifier 20 W, canner 30 W; the rain collector and planter need no power.

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

## Long game (after first playable)

*Agreed with Emmitt 2026-10-12. Satisfactory runs out of things to do once you finish it. Noise Floor never ends, like Zomboid: the world gets harder the more you build, and your character and gear keep improving to match.*

### The world gets worse
- **The town runs dry.** Loot doesn't respawn, gas in cars goes stale after about 3 weeks, and food spoils. Scavenging carries you early, but by week 3 you have to automate or starve.
- **Infamy.** Every bit of noise you make adds to a permanent infamy score. As it climbs, new zombies appear:
  - **Runners**
  - **Screamers:** yell when they see you and pull in everything nearby
  - **Brutes:** smash walls
  - **Crawlers:** get in through vents
  - **Listeners:** hear quieter sounds

  A bigger factory brings worse zombies, not just more of them.
- **Seasons.** Winter stops crops, the cold means you need heat, and sound carries farther on cold, still nights.
- **Big projects, no final win.** Restart the water tower, power the substation, fix the radio tower (it calls traders, and the dead). Each one is loud enough to trigger a siege, and finishing it opens a harder area. There is no last one.
- **Areas get harder further out:** start town → suburbs → industrial park → hospital → military base → the city. Harder areas hold better loot: higher base tiers, uniques, sets and blueprints.
- **Stats screen:** days survived, deaths, kills, total noise made.

### Skills and perks (Zomboid × Diablo 2)
- **Skills level by doing** (0–10, Zomboid style): Strength, Fitness, Building, Mechanics, Scavenging, Sneaking, Melee, Firearms, First Aid, Farming.
- **Every 3 skill levels earn 1 perk point** to spend in one of three trees. Each perk has ranks 1–5.
  - **Engineer:** faster building, faster machines, quieter machines, faster belts, cheaper mufflers.
  - **Ghost:** silent footsteps, faster searching, better loot rolls, see noise rings, harder to spot.
  - **Fighter:** melee damage, recoil control, reload speed, **Gunsmith** (needed for advanced gun parts).
- **Synergies** like D2: some perks get stronger from points in another tree. For example, Engineer's *Dampened Gears* also gains from Ghost points.
- **Item bonuses** like "+1 to Ghost perks" add a rank to every Ghost perk you've put at least one point into, and can push a perk past rank 5.
- **Respec** needs a rare crafted item, the *Clean Slate*, which is a late-game factory goal.
- **You keep skills and perks when you die.**

### Carry weight (Zomboid style)
- Every item has a weight in kg, starting in M2.
- **Carry limit = 20 kg + 3 kg per Strength level** (20–50 kg). Bags add capacity: school bag +8, hiking pack +18, military rucksack +25.
- Over the limit you move slower, use more stamina, and your footsteps get louder. Over 150% you can't sprint.
- Strength goes up by carrying heavy loads and swinging melee weapons. It also adds melee damage and knockback.

### Loot (Diablo 2 colors and rolls)

| Color | Rarity | Stats |
|---|---|---|
| White | Common | Base stats only |
| Blue | Magic | 1–2 random stats |
| Yellow | Rare | 3–5 random stats |
| Gold | Unique | Named. A fixed list of stats, each rolling within a range |
| Green | Set | Named pieces. Wearing more pieces of the set unlocks bonuses |
| Orange | Crafted | Made at a top-tier machine from a recipe: some fixed stats, some random |

- **Stats roll in ranges**, for example: +10–25% damage, +1–2 to Fighter perks, +1–3 Strength, −5–15 loudness, +5–15 kg carry, +10–20% reload speed, +10–30% durability, +10–25% search speed.
- **Base tiers**, like D2's normal/exceptional/elite: Civilian → Police → Military. Better bases have higher base stats and room for more rolled stats, and they turn up in harder areas.
- **Example unique, Old Pete's Deer Rifle** (gold): +15–30% damage, +1–2 to Fighter perks, −5–10 loudness, threaded barrel. Old Pete carries it himself; he's a named zombie at the hunting lodge.
- **Example set, Night Shift** (green): hard hat, hi-vis vest, work gloves, headlamp.
  - 2 pieces: +15% search speed.
  - 3 pieces: +10 kg carry.
  - All 4: your noises count as 3 quieter.
- **Condition** (Worn → Mint) is durability. Gear wears out and needs repair kits from the factory, so the factory always has work.

### Guns and gunsmithing (Tarkov style)
- A gun is a base plus parts: barrel, muzzle, stock, grip, sight, magazine and light. You swap parts at a workbench.
- Parts change damage, recoil, accuracy, handling and **loudness**. The suppressor is the most important part in the game.
- **The factory supplies the armory.** Early on you get a crude oil-filter suppressor that wears out fast. Later the factory makes machined suppressors and subsonic ammo.
- **Ammo types:**
  - **Subsonic:** quiet, weaker.
  - **Standard.**
  - **Armor-piercing:** for brutes.
- Rare parts and blueprints only come from harder areas, and advanced parts need the Gunsmith perk. Gun parts can roll rarity and stats too.

### Automated defense (keep the base safe while you're away)
- **The base keeps running when you leave.** Machines, belts, turrets and zombies all live in the sim, so an attack on your base follows the same rules whether you're watching or in another town. Only the visuals are skipped. Ammo drains, walls take damage, turrets break.
- **Turrets** take ammo from a belt or a hopper, and accept gun parts (suppressor, scope):

| Turret | Ammo | Noise | Role |
|---|---|---|---|
| Nail turret | Nails (from the Press) | Quiet (L 35) | Weak, cheap first defense |
| Crossbow turret | Bolts | Near silent (L 20) | Slow, strong single shots |
| Rifle turret | Rifle ammo | Loud (L 85) unless suppressed | Long range |
| Shotgun turret | Shells | Loud (L 90) | Close-range crowds |

- **Traps:**
  - **Spike strips:** slow and hurt zombies, wear out.
  - **Bear traps:** pin one zombie.
  - **Tripwire bells:** sound an alarm.
  - **Electric fence:** needs power, stuns.
- **Sensors and simple rules:** a motion or noise sensor triggers an action you pick from a list. Options: shut down loud machines (quiet mode), turn on floodlights, fire a far-off decoy noisemaker to pull a horde away, lock doors. No programming, just sensor → action.
- **Repair station:** uses wall panels from a belt to fix walls in range.
- **Radio:** carry a handheld radio and you hear alerts like "East wall under attack: 18 zombies." The base log shows everything that happened while you were gone.
- **Outposts:** build a second base in another town, with its own defenses. Same rules.
- **The noise trade-off:** loud turrets save you tonight and bring more zombies tomorrow. Quiet defense costs more.

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
- [x] **M6 — Survive.** Hunger, thirst, fatigue, bleeding; searchable containers with loot tables; eat and drink; water and canned-food chains.
  - Also in M6 (from the long-game plan): every item gets a weight in kg in `data/`, and the player gets a carry limit of 20 kg plus bags (Strength raises it in M12). Over the limit: slower, more stamina use, louder footsteps. Over 150%: no sprinting.
- [x] **M7 — Power.** Generator + fuel, poles and wires, power draw, brownouts; first quiet power source.
- [x] **M8 — Defend.** Doors, barricades, traps, a turret that uses produced ammo; structure HP and repair.
- [x] **M9 — Keep it.** Save/load, main menu, settings (mouse sensitivity, volume, day length), pause.
- [x] **M10 — Look and sound.** CC0 models (ask Emmitt first), machine hums and zombie moans (sound sells the noise theme), fog and flashlight atmosphere, title screen.
- [x] **M10b — Inventory screen.** **Tab** opens your pockets next to any crate in reach, with item icons, counts, weights and your carry limit. Click an item to use it (eat, drink, bandage), drop it, or move it between pockets and the crate (shift-click moves the whole stack). Item icons are made with Codex (`assets/icons/`). This comes before M11, because loot, bags and carry weight all need a place to see your stuff.
- [x] **M10c — Wheels.** Drivable cars, with better-looking ones:
  - **Look:** a few car types (sedan, pickup, van) with worn, rusty, scratched paint, tinted per car. Their textures are mapped to the car itself, not the world, so they don't slide when it moves.
  - **Driving:** **E** gets in and out, WASD drives, Space is the handbrake, **H** is the horn, and headlights come on at night. Physics is Godot's `VehicleBody3D`, and the car models need their wheels as separate parts.
  - **Noise:** a running engine is loud (about a generator) and draws zombies; the horn is very loud.
  - **Fuel:** a car's tank is the gas you can siphon, so siphoning strands it. Refuel from gas cans.
  - **Wrecks:** some cars can't drive (flat tyres, smashed); the rest start if they have fuel.
  - **Keys (Zomboid style, Emmitt's call):** every car has its own key: in the ignition, in the glovebox (search the car), in the nearest house, or lost. Without it you can sit in the car but it won't start, unless you hotwire it (**R** in the car), which needs **Mechanics 2** and gets quicker with skill. Mechanics levels by doing: repairs, mufflers, car repairs and hotwiring. It's the first M12 skill, brought forward.
  - **Damage and storage:** hitting zombies hurts them and the car. The trunk is storage that shows up in the inventory screen.
  - **Saving:** cars are saved where you parked them.
  - **Rules in the sim:** fuel, damage and position are sim state (tested); the world handles the physics, like zombie bodies and brains. Moving cars need navmesh obstacles so zombies path around them.
- [x] **P0 — Playtest kit.** Session log written on death and quit; first-game hints.
- [x] **P1 — Playtest fixes.** Car prompts explain keys and wrecks; play.bat logs its update and the title screen shows the build.
- [x] **P3 — Playtest readiness.** F1 controls screen, a key hint line that fits the moment, a fuller session log, town pieces salvage instead of refunding.
- [x] **W1a — Into the houses.** Houses are grid pieces: doors, windows, rooms with loot, roofs, and walls that muffle.
- [x] **W1b — Life inside.** A zombie in some houses, the factory floor, hordes down the road.
- [x] **W1c — Furniture.** Counters, tables, couches, shelves, bathtubs and toilets as salvageable pieces, placed by the town plan.

**The long game** (see "Long game" above), in this order:

- [x] **M11 — The world gets worse.** Finite loot, stale gas, food spoilage, the infamy score, the first evolved zombies (runner, screamer), the stats screen.
- [x] **M12 — Skills and carry weight.** (Mechanics and the skill table already exist, since M10c.) Skills that level by doing, the Strength-based carry limit and bags, perk points, the three trees with a few perks each, synergies.
- [x] **M13 — Loot.** Rarity colors, stat rolls in ranges, base tiers, durability and repair kits, the first uniques and one set.
- [x] **M14 — Guns.** Firearms, workbench and parts, loudness per part, the crude suppressor, the subsonic ammo chain, the Gunsmith perk.
- [x] **M15 — Automated defense.** The turret lineup fed by belts, traps, sensors and actions, the repair station, attacks that play out while you're away, radio alerts and the base log.
- [ ] **M16 — Seasons.** Winter, heat, crop cycles, sound carrying farther in the cold.
- [ ] **M17 — Further out.** A second, harder area, the first big project (water tower), outposts.

## Open questions (decide when we get there)
- Map: hand-built town vs. procedurally generated blocks? (Hand-built greybox until M6.)
- Hardcore mode (permadeath): an opt-in option, after M17. Normal mode keeps skills on death and leaves your items on your body.
- How hard should nights be? Tune after M5 playtests with Emmitt (and Kaleb).
