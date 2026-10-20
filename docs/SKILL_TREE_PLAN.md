# Skill tree plan: perks as a Diablo 2 tree

*Written 2026-10-19 by Claude Fable 5.1 at Emmitt's request ("can we turn this into a skill tree like in Diablo 2?"), looking at the P12 perk pick. A plan for one milestone (P13); building starts once PR #108 is merged.*

## What Diablo 2 does that this game doesn't yet

- **Three trees of real depth.** Each tree is rows of skills; the lower rows open as your character grows. Ours has three trees of 3, 3 and 6 perks, all open from the first point.
- **Arrows.** Skills lead to skills: you can't take the big one without the small one under it. Ours has none.
- **Synergies.** Points in one skill feed another, so a build has a shape. Ours has exactly one (Dampened Gears gets stronger with Ghost points).
- **A picture per skill.** You read the tree by its icons. Ours is text rows with a "+1" button, which is a wall for Kaleb.

## The design

### The trees

Three trees, as now: **Engineer** (the base and its machines), **Ghost** (quiet and finding things), **Fighter** (melee, guns, staying alive). Three rows each. A row opens when you have **3 points in that tree** (row 2) and **6 points** (row 3), the way Diablo 2 opens rows by level, but counted per tree so a kid can see why: "put three in this column and the next row lights up". Arrows between perks are hard requirements: at least one point in the perk above.

Every perk keeps **5 ranks** (as today). Points come as today: one for every three skill levels, about four a game day.

Draft layout (26 perks; the 12 that exist stay where they are; the 14 new ones reuse bonuses the game already applies, so most need no new rules, only data):

| | Engineer | Ghost | Fighter |
|---|---|---|---|
| **Row 1** (open) | Fast Lines (belts faster) · Tuned Machines (craft faster) · Dampened Gears (machines quieter) | Soft Step (quieter steps) · Quick Fingers (search faster) · Lucky Find (extra loot) | Heavy Swing (melee damage) · Second Wind (stamina) · Thick Skin (take less) |
| **Row 2** (3 pts in tree) | Cheap Repairs (repair_discount) ← Tuned · Green Thumb (planter_extra) ← Fast Lines · Pack Mule (carry_kg) | Parkour (vault_speed) ← Soft Step · Light Gear (gear_quiet) ← Soft Step · Deep Pockets (carry_kg) ← Quick Fingers | Steady Hands (recoil_cut) · Shove (knockback) ← Heavy Swing · Field Medic (bandage_heal, heal_rate) ← Thick Skin |
| **Row 3** (6 pts) | Careful Hands (wear_cut) ← Cheap Repairs · Silent Running (machine_quiet + quiet_all) ← Dampened Gears | Night Walker (quiet_all) ← Light Gear · Treasure Sense (lucky_find + search_speed) ← Lucky Find | Quick Hands (reload_speed) ← Steady Hands · Deadeye (gun_damage, spread_cut) ← Steady Hands · Gunsmith (suppressed quieter) ← Quick Hands · Iron Hide (damage_cut, bleed_cut) ← Thick Skin |

Synergies (shown on the card, as Diablo 2 does): Dampened Gears ← Ghost points (exists); Deadeye ← points in Steady Hands; Treasure Sense ← points in Quick Fingers; Silent Running ← points in Tuned Machines. Numbers are a first draft to tune after a playtest; the point is the shape.

### The screen

- The K screen's right side becomes the tree: three columns, three rows, each perk a **big square with a picture**, lines and arrowheads between them. Rows not yet open are dark with "3 points in Engineer opens this". Perks you can afford glow gold; a click puts a point in (the +1 button goes). Rank shows as five pips under the picture.
- Pictures without new art: every perk maps to an item or piece picture the game already has (`assets/icons`): Fast Lines → belt, Tuned Machines → smelter, Dampened Gears → the muffler's generator, Soft Step → sneakers, Quick Fingers → work gloves, Lucky Find → a storage crate, Pack Mule → hiking pack, Heavy Swing → axe, Thick Skin → hard hat, Field Medic → bandage, Steady Hands → pistol, Deadeye → scope, Gunsmith → suppressor, Quick Hands → rifle rounds, Iron Hide → jacket, Night Walker → headlamp, Green Thumb → seeds, Cheap Repairs → repair kit, Parkour → work boots, and so on. Drawn icons from Codex can replace them later in one batch; the layout won't change.
- Pointing at a perk shows its words, its arrow (what it needs), its synergy, and what the next rank gives; the first time, the P12 explanation line.
- The left column (the 13 skills with their bars) stays. On big windows the screen scales up like the build menu and the perk pick.
- **The quiet-moment pick opens the tree**, not three random cards: it lands on the tree you have the most points in, with the affordable perks glowing. "Later" keeps working as P12 made it. The three-card screen goes.
- **Reset:** a "Take my points back" button per tree, free once a game day (a kid will misclick; Diablo 2's three-per-character is too stingy for a six-year-old). The log counts resets.

### The rules (sim)

- `Skills.can_spend(perk)` gains the row and arrow checks; `tree_points` exists already. `Skills.offer` goes (the pick opens the tree).
- New data in `skills.json`: each perk's `row`, `needs` (the perk above, if any), `icon`, and `synergy` where listed; each tree's `rows` thresholds `[0, 3, 6]`.
- 14 new perks, almost all on effect keys the game already reads (`carry_kg`, `vault_speed`, `gear_quiet`, `quiet_all`, `repair_discount`, `planter_extra`, `wear_cut`, `bandage_heal`, `heal_rate`, `knockback`, `gun_damage`, `spread_cut`, `bleed_cut`). None needs a new rule in the sim beyond reading its key.
- A reset: `Skills.reset_tree(tree)` returns the tree's points, once per game day (`reset_day`), saved.
- Tests: the data checks out (every perk in exactly one tree and row, every `needs` in the same tree one row up, every effect key one the game reads); rows open at 3 and 6; an arrow blocks and then allows; a reset gives points back once a day; the screen shows 26 pictures, the right ones glow, a click spends, the pick opens on the biggest tree; save and load keep ranks.

### Why it also matters for co-op

Each player gets their own tree. The co-op plan (`docs/COOP_PLAN.md`) makes skills per player in its first phase; a tree that is already data-driven and per `Skills` instance drops straight in.

## Size

One session (P13). Data and rules first (cloud-safe), then the screen and screenshots on the PC. No new art required to ship; Codex icons are an optional follow-up batch.

## Not decided here

- The exact numbers on the 14 new perks. Draft values go in; the next playtest's log (perks taken, resets) tunes them.
- Whether the 13 levelling skills should also show as a picture grid. Later, if Kaleb reaches for them.
