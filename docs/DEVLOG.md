# Devlog

Newest first. One entry per milestone: what was built, how to try it, known gaps, next.

## 2026-10-17 — P11 Chop trees for planks, strip broken cars for scrap

Same playtest as P10 (Emmitt and Kaleb, 30+ minutes): "The problem was resources ... We need a way to chop down trees for lumber and a way to get metal scrap."

**Built:**
- **Swing at a tree to chop it down** (`Salvage`, `SimWorld.player_hit_tree`).
  - Every tree counts: the town's, the suburbs', and the thousand in the countryside.
  - Each hit does the weapon's melee damage times its class's wood factor (axe 2.2, blade and blunt 0.8, fists 1.0).
  - An axe fells a tree in 5 hits, a pipe in about 18, and bare fists fell a small pine in about 24.
  - A tree gives 6 planks (a small pine 3). They go into your pockets, and whatever doesn't fit lies on the ground where you stand.
  - The tree tips over away from you (`CountryView.tipped`, 1.4 s) and is gone; you can walk through where it stood.
  - Felled trees stay down (saved under "salvage").
- **Swing at a car that won't drive to strip it.**
  - Strippable cars:
    - the town's broken-down cars (flat tyres, dead engine, smashed)
    - downtown's and the park's burned-out wrecks
    - the highway and junkyard wrecks
  - One scrap metal for every 80 damage (blunt 1.4, axe 1.0, blade 0.5, fists 0.3), until it's stripped: a sedan holds 8, a pickup 10, a van 12.
  - A car that still drives says so and gives nothing.
- **Both are loud.** Every chop (42), a falling tree (55) and every strip (52) is a one-off noise zombies hear (noise.json). Each hit wears the weapon like a hit on a door.
  - New synthesized sounds `chop`, `tree_fall`, `metal_strip` (tools/audio/synth.py).
- **The game says how:**
  - Looking at a tree: "[LMB] swing at it to chop it down for planks (an axe is quickest; it's loud)".
  - Looking at a broken car: "[LMB] swing at it to strip scrap metal (N left; loud)".
  - While you chop, "Chopping: 40%" shows under it.
  - Planks' and scrap metal's "where" (shown when you're short, and in the P10 build menu) and the controls screen mention trees and broken cars.
- Flags for screenshots:
  - `--tree` stands you by the nearest town tree with an axe.
  - `--tree=T` fells it and freezes the fall at fraction T.
  - `--wreck` stands you beside the nearest car you can strip.

**Try it on the PC:** start a game, walk to a tree and click at it (the pipe works; an axe from a house or the hardware store is much quicker). A broken car on Main Street gives scrap the same way.

**Known gaps:**
- Trees don't grow back and leave no stump.
- The navmesh keeps a felled trunk as an obstacle until the next bake, so zombies may step round an empty spot.
- Wrecks look the same stripped as whole.
- Drivable cars can't be stripped, on purpose (nobody wrecks the car they drive by accident).

**Next:** the next playtest, with P10 and P11 together.
## 2026-10-16 — P10 A picture build menu, and pieces you learn by building

Playtest (Emmitt and Kaleb, 30+ minutes): Kaleb "can't read very well", so the build menu's wall of text lost him: "thumbnails and a sidebar nav with icons for categories so he can see the machines better and the items required to craft it". Emmitt: "players should be limited on what they can build early so they can get eased into what they can build and how the items work."

**Built:**
- **The build menu (B) is pictures first** (`BuildMenu`):
  - A sidebar of group pictures (Base, Hub, Factory, Extractors, Power, Defense; `GROUP_PICS`).
  - The group's pieces as big picture tiles, five across, each with its cost as item pictures and counts, green when the crates near you and your pockets can pay, red when not.
  - The right side shows the piece you point at: a big picture, its numbers, "Costs" as item pictures with have / need (and where to find whatever's short), "Makes" as item pictures (scrap → plate; the Press shows four of its recipes), the plain line, and its hotbar key.
  - Drawn for 1600 x 900 and scaled up on bigger windows (1.6 x on Emmitt's 2560 x 1440), so the pictures are big enough for a child.
- **Pieces you learn by building** (`Learning`, `data/learning.json`):
  - A new game opens five pieces: foundation, wall, door, bed, storage crate.
  - Each piece in `after` opens once you've built the piece it names: a door teaches the workbench; a workbench teaches the generator, the Hub, the nail turret and the rain collector; a generator the power pole; a pole the smelter; a smelter the belt and the Press, and so on. Taking a piece down doesn't forget what it taught.
  - The Hub milestones still lock the advanced machines, and the Hub itself needs a workbench.
  - "New to build: Workbench. Find it in the build menu (B)" when you learn something. Its tile and its group's sidebar picture say NEW until you point at it.
  - A locked tile is dark, with a padlock and the picture of what to build first (the Hub's for a milestone piece). The right side shows every piece on the way as pictures, in order, from the one you can build now ("Learn it by building these in order: Generator → Power pole → Smelter").
  - Clicking a locked piece says why instead of starting build mode. `BuildGrid.can_place` refuses it with the same words.
  - The objectives panel's defend and feed goals say how to learn their piece when it's locked ("First learn it: build a Workbench, then the Nail turret.").
  - Saved under "learning". A save from before P10 knows every piece, and so do test worlds; a real new game starts over (`main.gd`). The start-of-game crate doesn't count as the player building.
- `--build-menu=ID` opens the menu pointing at that piece, for screenshots.

**Try it on the PC:** start a new game (`play.bat`), press B. Build a foundation and a door, then press B again: the workbench says NEW.

**Known gaps:**
- The group pictures are pieces from each group, not drawn icons.
- The tiles still carry names (small) for grown-ups. Nothing is read aloud.
- The learning order is a first guess. Tune `data/learning.json` after the next playtest.

**Next:** P11, from the same playtest: chopping trees for planks and stripping wrecked cars for scrap metal.

## 2026-10-16 — P9 Kaleb's updates come from the internet too

Emmitt: "can we make it easier to update the game for kaleb so he sees the new changes? we can use our cdn server". Kaleb's copy only updated from R: over the home network, which needs this PC switched on and his PC able to reach the share. His logs never arrived, so it probably wasn't reaching it.

**Built:**
- **A private family folder on the CDN:** https://cdn.agencyedge.io/noisefloor/ on hermes.
  - Password-protected (nginx basic auth, `/etc/nginx/noisefloor.htpasswd`), so the game and its paid arm models stay family-only. Wrong or missing password: 401.
  - Never cached.
  - Written by the restricted `cdnpublish` account, the same one ClipLab publishes with.
  - The nginx config was backed up to `/root/cdn.nginx.bak-20261016` and tested before reload. ClipLab's downloads and cliplabpro.com still answer.
- **`tools/publish_family.sh` publishes to both:** R: and the CDN. Each zip is uploaded and renamed into place, with version.txt last.
  - Both version.txt files carry the zip's SHA-256 on a second line. Old launchers read only the first line, so they're unaffected.
  - `NO_CDN=1` skips the upload.
- **The launcher (`update.ps1`) falls back to the CDN:** it tries the R: folders first (fast at home), then `https://cdn.agencyedge.io/noisefloor`, using the password in `family_cdn.txt`.
  - `make_portable.sh` copies that file in from `~/.noisefloor/family_cdn.txt`. It's never in git.
  - Downloads show progress every 10%.
  - A copy whose fingerprint doesn't match is thrown away (a folder copy too).
  - The P7 folder swap installs it.

**Tested** (scratch install, R: unreachable):
- Downloaded from the CDN and installed in 38 s; a second start said up to date.
- A wrong password keeps the old version.
- A damaged copy keeps the old version.
- The CDN now holds 43be875 with the new launcher.

**For Kaleb's PC:** it gets the new launcher with its next update from R:, so this PC must be on when he starts the game that once. Leave the window open until "Updated". From then on, updates also come over the internet, whether or not this PC is on.

**Known gaps:** play logs still only reach R:, so they only arrive when his PC can see the share.
## 2026-10-16 — V39 Supporting hands that cradle, a two-handed axe, and a real scope

Emmitt, with screenshots: "the left hand should be palm up and the arm is floating. the axe has a finger that looks off, maybe rethink the grip with 2 hands. pistol looks a bit weird but acceptable for now." Then: "I found a scope but it doesn't zoom in much and has no reticle".

**Built:**
- **Long guns rest in the left palm** (`Hands.CRADLES`, `cradle_basis`): the rifle's fore-end, the shotgun's pump and the crossbow's stock now sit in the left palm, with the forearm running back and off to the lower left.
  - Why it looked wrong: a wrap-round grip, rolled like the gun hand, could only set the forearm square to the barrel, so the arm stuck straight out to the left.
  - The hand keeps the cradle while it slides along the barrel (pumping). It blends back to the old grip once it leaves the barrel's line (reloads).
  - Its fingers rest in the HoldMag pose.
- **Two-handed axe:** a right-hander's chopping grip, with the left hand at the foot of the handle and the right hand 30 cm up it. Before, both hands were bunched 9 cm apart at the foot, and the left's fingers poked out past the right.
- **Scopes zoom per gun** (`Shooter.SCOPE_FOV`): about 4.4x on the hunting rifle (20 degrees), 2.9x on the crossbow, 1.9x on a pistol. Before, every scope stopped at 35 degrees (barely 2x).
- **Mouse look scales with zoom:** looking turns slower while zoomed (`Player.LOOK_FOV`), so a 20-degree scope isn't twitchy.
- **A scope view** (`ScopeOverlay`):
  - black round a round lens, with a soft rim;
  - a duplex reticle: thick outer posts, fine centre lines and a red centre dot;
  - three holdover ticks below the centre.
  - It fades in with the aim; the normal crosshair hides while it shows.

**Try it:** `play.bat --gun=rifle`, `play.bat --gun=shotgun`, `play.bat --weapon=axe`, `play.bat --gun=rifle --aim`

**Tests:** 20,617 green.
- New `test_long_guns_rest_in_a_palm_up_cradle`: palm up, forearm back and to the left; the cradle holds while sliding along the barrel and lets go off the barrel's line; the pistol is unchanged.
- The scope zoom test now uses each gun's own zoom, and the crosshair test checks that a fitted scope shows its reticle, not the crosshair.
- Soak 1 day OK, 143 s.

**Known gaps:**
- In the axe's block, the left hand shows its palm.
- The pistol hold is unchanged, as Emmitt asked.
## 2026-10-16 — P8 Shift-click works on coloured gear

Emmitt: "with colored items the shift+click to inventory function breaks". Item stacks used a click handler that checks shift (move the whole stack) and ctrl (move one). Gear pieces, the rarity-coloured items, were wired straight to "select", so shift- or ctrl-click only highlighted them.

**Built:** gear tiles use `InventoryScreen._on_gear_slot`. Shift- or ctrl-click moves the piece to the other side (`move_gear`): pockets to the open container and back, or a worn piece off into your pockets. A plain click still selects it.

**Try it:** `play.bat --loot`, put a coloured piece in your pockets, then shift-click it into the fridge and back.

**Tests:** 20,606 green (new `test_shift_click_moves_gear_pieces`: real shift and ctrl key presses through Godot's input, clicking the live tiles).

## 2026-10-16 — P7 Updates that can't leave a half-new game

Emmitt watched his son's stream: white poles through the arms and the old loose fists. The game on main and the family zip both looked right. His copy was half updated: the new arm models (in `assets\`) with the old arm code (in `src\`). The old code adds a sleeve tube, white here because the new model has no sleeve material for it to borrow. The old updater copied the new files over the old ones folder by folder (`assets` before `src`). Its unzip (Expand-Archive) takes 25 s on this PC and longer on his, with no sign of progress, so a closed window or a second click left a mix. The new updater, the one that sends his logs, is only installed at the very end of an update, which is why no logs came.

**Built (`tools/portable/update.ps1`):**
- **Whole folders, swapped:** the new game folder is unpacked in full and moved in beside the live one (`game.new`), then two renames swap it in. Closing the window at any point leaves the old version or the new one, never a mix. A swap cut off between its renames is put back at the next start, and half-copied folders are cleared. Godot's folder is only replaced when its exe changed.
- **Fast:** .NET's ZipFile unpacks in 3 s; a whole update took under 4 s on this PC (the old one, 25 s just to unpack).
- **Says what it's doing:** "Updating ... Please don't close this window", then steps 1/3 to 3/3 and "Updated".
- **One at a time:** a second launcher waits for the first instead of copying over it.
- The README says to leave the window open until "Updated".

**Tested** on a scratch copy of the family build:
- An old install updated in 3.6 s, with a stray file gone.
- A cut-off swap was restored.
- Two launchers at once: the second waited, then found nothing to do.

**For his PC:** his copy still runs the old updater, which tries the update again at every start until it finishes. Once it does (leave the window open until "Updated"), the new updater takes over and his logs start arriving on the family drive.

## 2026-10-16 — V38 An axe that looks like an axe

Emmitt: "I'd like to fix the axe, it looks more like a sledgehammer". The head was one flat-sided block 5 cm thick with a square back. You held it with the blade pointing straight away, so all you ever saw was the back of the head. It was dark gunmetal, which renders nearly black, and on the ground it balanced on its edge.

**Built:**
- **A felling-axe head** (`tools/art/axe.py`), built through cross-sections from back to blade:
  - a slim rounded back, a fuller eye, and cheeks tapering to a sharp edge;
  - the blade flares to 14 cm tall, and its edge curves (furthest forward in the middle);
  - painted red, with a wide, bright ground bevel ("Axe Paint" / "Axe Bevel" in `Melee.WEAPON_LOOKS`, on the car-paint photo, because the gunmetal one turned the red almost black);
  - a slimmer oval handle with a swell at the foot, its top showing through the eye.
- **Held turned 35 degrees at rest** (the "overhead" style's rest keys), so you see the side of the head. The chop still swings round to hit edge-first.
- **Dropped melee weapons lie on their flat side** (`BagView`): the axe shows its red head; the machete and knife no longer balance on their edges.

**Try it:** `play.bat --weapon=axe`, `play.bat --drop=axe,machete,knife --cam=0,0,0,0,-40`

**Tests:** 20,599 green (new `test_dropped_blades_lie_flat`). Soak 1 day OK, 153 s.

**Known gaps:** at night the held head is a dark silhouette like everything else; the hotbar icon is the old picture.

## 2026-10-16 — V37 Real first-person arms: Davlet's FPS Arms Pack 06

Emmitt: "we really need some hand models, these look cursed". He bought Davlet's Modular FPS Arms Pack 06 on Superhive ($26, royalty-free). The old arms were a MakeHuman hand with tube sleeves added in the engine. Now the game uses the pack's own stitched leather gloves and olive canvas jacket sleeves.

**Built:**
- **`tools/art/fp_arm_fps06.py`** (Blender) turns the pack's variant 02a into `fp_arm_right.glb` / `fp_arm_left.glb` on the game's existing 17-bone arm contract, so every weapon, reload and inspect pose works unchanged:
  - Every vertex moves from the pack's Unreal pose to the game's grip. It reuses `fp_arm_mpfb.py`'s palm alignment.
  - The fingers wrap the 34 mm handle by searched joint bends. Every joint curls forward, so the engine's pose maths works, and no part of the glove goes inside the handle (clearance 17.7 mm).
  - The elbow is straightened, so the sleeve runs 0.69 m back from the wrist, off the screen.
  - About 23k triangles and 1 MB per arm. The seven textures (3.7 MB) are shared files in `assets/textures/fp_arms/` that both models point at, so Godot imports each once.
- **`tools/art/fp_arm_fps06_textures.py`** (Pillow) shrinks the 4K textures for the game: sleeve colour c3 (olive) and glove colour 02 (tan), with their baked shading multiplied in. It also tints the glove's grey brand tag to leather and makes it matte; it was flashing like a chip of metal.
- **`hands.gd`:** the pack's materials keep their own textures and are drawn from both sides. An arm that brings its own sleeve gets no extension tube. The fist is tightened (fingers 100/110/70 degrees, the thumb tucked against the side) so it reads as a fist from the player's eye.
- **`tools/art/hand_poses.gd`** renders the six hand poses from the front, the eye and the index side, for tuning.
- The pack's files stay local-only (`C:/projects/assets-src/fps-arms`). The licence is noted in `assets/CREDITS.md`.

**Try it:** `play.bat --fists`, `play.bat --gun`, `play.bat --gun=rifle --aim=irons`, `play.bat --weapon=bat`.

**Tests:** 20,565 green. `test_the_sleeve_carries_on_to_the_shoulder` now checks the arm's own sleeve: it reaches more than 0.6 m back, keeps its textures, is drawn from both sides, and gets no tube. Soak 1 day OK.

**Known gaps:**
- The thumb rests along the side of the fist, not across the fingers.
- The glove tag's top edge is a little blocky up close.
- Swapping sleeve or glove colours means changing two constants and re-running both scripts.
- A public release would need a packed build and a look at the pack's own licence text.
## 2026-10-16 — P6 Doors you can swap: taking pieces down says so, and a door goes in the doorway you look at

Emmitt's son pulled down a house's front door, built his own, "used it and it disappeared", then couldn't build a new one. He got frustrated. In the game scene, two things went wrong:
- Right-click in build mode takes a piece down without a word, so clicking a door in build mode just made it vanish (its materials went quietly back into a crate).
- A wall, door or window goes on the far edge of the cell you aim at. Looking at an empty doorway, the look ray went through it and hit the floor or wall inside, so the ghost sat on a wall inside the house and said "Already built". Only aiming at the lawn just outside worked.

**Built:**
- **Taking something down says what came down and where its materials went:** "Took down the Door: 6 Plank, 8 Nails back in the crate" (or "in your pockets"; a town door gives 2 planks).
- **A door goes in the doorway you look through:** with a wall, door or window picked, looking through a gap in a wall line (walls on both sides, low enough to walk through) aims at that gap (`BuildController.gap_on_ray`, `is_wall_gap`). The end of a wall line and open ground keep the old aim.
- The build line no longer errors the frame after a removal (the piece's body is still in the physics world until it's freed; `update_aim` now ignores it).
- **His logs come to us:** the portable launcher (`update.ps1`) copies the PC's session logs to `logs\<computer name>\` in the family folder at each start (new or changed logs only; a drive it can't write to is skipped). The first start after this update brings in the new launcher; from the start after that, his logs appear in R:/Reserve/Noise Floor/logs/.

**Try it:** `play.bat`, walk to a house, B, pick Door, look at its front door, right-click (the message says what came back), keep looking at the empty doorway (green ghost in it) and left-click. Esc, then E opens it.

**Tests:** 20,592 green (new `test_door_swap_world.gd`, real game scene: take the town door down, see the message, the ghost sits in the empty doorway, a new door goes in, E opens it and it's still there, take it down for its full cost and build again; the end of a wall line isn't a gap). Soak 1 day OK, 143 s.

**Known gaps:** what "used it and it disappeared" was exactly is a best guess (build mode right-click) until his logs arrive. Right-click still takes a piece down with no undo.

**Next:** the FPS arms (Davlet pack, bought), then PT.
## 2026-10-16 — V36 Hats that fit: the hard hat and cap sized to each body's head

Emmitt: "when we changed the zombie models the clothing got messed up a bit, mostly just the headwear scaled strangely to the new zombies". The hard hat (heavy body) and the cap (short body) were fixed sizes left over from the old blocky zombie: about twice as wide as the new MakeHuman heads and too flat, so they looked like sombreros with the dark scalp poking through the top, and the cap's bill floated at eye level.

**Built:**
- **Hats are fitted to the head they sit on:** `zombie_mpfb.py` `head_fit` measures the head (its vertices above the hat band plus the hair on it), then grows the dome until all of it is inside with a little clearance. The hard hat is a proper dome with an oval brim and a moulded ridge on top; the cap is a snug crown with its bill coming out of the front at the band, dipping slightly. `zombie_heavy.glb` and `zombie_short.glb` rebuilt; the other three bodies wear no hat and are unchanged.
- **`--zombie-body=A,B,...`** (screenshots): the bodies `--zombie`'s zombies wear, in order, e.g. `--zombie-body=heavy,short`.

**Try it:** `play.bat --zombies=0 --zombie=-0.3,-1.6,0.3,-1.6 --zombie-body=heavy,short --cam=0,0,-0.4,0,3 --time=12` puts a hard hat and a cap zombie right in front of you. Brutes always wear the hard hat body.

**Tests:** 20,575 green (new `test_hats_fit_their_heads` in `test_zombie_types_world.gd`: each hat covers the top of the head and its hair, and is at most 1.75 (hard hat) / 1.45 (cap) heads wide; the old ones were about 2.1 and 1.8 with hair through the top). Soak 1 day OK, 148 s (in the usual range; only models changed).

**Known gaps:** hats never come off (a head shot could knock one off later).

**Next:** PT, Emmitt's first loud night.

## 2026-10-16 — P5 Gathering by hand: the first rung before the machines

Emmitt: "how should we make users gather materials for things like the smelter?" The answer, the Satisfactory way: a ladder. You start with the crate and loot; you gather raw materials by hand at the world's resource nodes (slow, and you stand there making noise); then you build the node's machine and bring its output home by belt or cart. The middle rung was missing: a resource node could only be worked by its machine, which needs a milestone and power. Code and checks by Claude Opus 5.5.

**Built:**
- **E on a resource node gathers by hand:** a scrap heap (the junkyard) gives scrap metal every 4 s, a timber stand (the woods) planks every 5 s, a farm well rainwater every 3 s, a fuel tanker a gas can every 30 s; a rich node is twice as quick, a poor one half. It keeps going while you stay close; E again, walking away, full pockets or getting in a car stops it. Each one clanks or chops loud enough for zombies to hear (the well and tanker are quiet), and it trains Scavenging. Looking at a node says both ways: "[E] pull scrap from the heap by hand: a scrap metal every 4 s (loud)" and "Or build a Salvager on the yellow spot", and while you gather it shows how far along you are.
- **The game says what you're short of and where to get it:** instead of "Not enough materials", the build line says "Not enough: 6 Scrap metal (search cars, garages and trash, pull town furniture down (B, then right-click), or pull it from a scrap heap at the junkyard (E))". Every raw material knows where it comes from (planks, scrap, nails, plates, gas, wall panels, rainwater, seeds).
- The controls screen's first step and the build menu's Extractors note mention gathering by hand; the session log counts what you gathered.

**Try it:** `play.bat --at=junkyard`, look at a scrap heap and press E. Then pick a smelter in the build menu with empty pockets: the line says what's missing and where it comes from.

**Tests:** 20,567 green (new `test_gather.gd`: too far says get closer; E starts it, a scrap metal per round with a clank, it repeats, the session log counts it, E stops it; walking away and full pockets stop it; a rich heap is quicker; every node kind can be worked by hand and a timber stand gives planks; the missing-materials words name counts and sources; the node's look-at line says E gathers and shows progress). Soak one game-day: SOAK OK, 121 s.

**Known gaps:** car wrecks can't be stripped for scrap yet (next on the ladder if scrap is still short); hand gathering never runs a node dry.

**Next:** PT, Emmitt's first loud night.

## 2026-10-16 — P4 Belts you can read: IN and OUT on every machine, belts that snap, ticks and crosses

Emmitt's playtest: "the conveyor belts were hard to tell if they snapped into a machine like in satisfactory. I just built a machine with conveyor belts around all sides and still didn't know how it worked." The rule was strict and invisible: a machine takes items in only at its back and puts them out only at its front, and a belt pointing anywhere else silently did nothing. Code and checks by Claude Opus 5.5.

**Built:**
- **IN and OUT on every machine:** a blue arrow on the ground at its back, pointing in and marked IN, and an orange one at its front, pointing out and marked OUT. The build ghost of a machine shows them too, so you can turn it (R) before you place it. The build line says "Takes items IN at the back (blue arrow), puts them OUT at the front (orange arrow)."
- **Belts snap:** a belt placed behind a machine turns itself to feed in; one placed in front turns to carry the output away; one placed after a belt that ends there carries the line on. R still turns it your way (and stops the snapping on that spot).
- **See if it connects:** every belt end that meets something shows a green tick if it connects (a machine's IN, a crate, a turret, the Hub, the right side of a splitter) and a red X if it doesn't (a machine's side or front, a belt running back at it). A machine whose output runs into a belt pointing back at it gets a red X too. While placing a belt the build line says what it will feed: "This belt ✓ feeds the Smelter's IN" or "This belt X points at the Smelter's side: machines only take items in at the back (blue IN)".
- **Belts plug in (Emmitt, after seeing it: "can we make the graphics a bit better where the belt actually connects to the machines so items don't look like they float over the belts?"):** a machine model is narrower than its 2 m cell (a Press is 1.35 m deep), so a belt used to stop short of it and items vanished in mid-air. A connected port now gets a short chute from the belt's end to the machine's face with a dark port frame on it, items ride the chute through the frame into the machine (and come out of a machine's OUT frame onto the belt), a machine feeding straight into the next gets a bridge, and items sit on the belt's rubber deck. Free ports keep their arrow.
- **Look-at lines:** a belt says where its end goes; a machine says what feeds its IN and what takes from its OUT ("IN (back, blue): fed by a belt   OUT (front, orange): BLOCKED: the belt there runs back into it").
- The build menu's Factory note and the controls screen's walkthrough explain IN and OUT.

**Try it:** `play.bat --demo-factory`: the smelter and Press show their arrows and the belts' ticks. Then build a machine and walk belts round it: each one snaps or shows an X.

**Tests:** 20,535 green (new `test_belt_ports.gd`: chutes reach the machines' faces (the Press model is about 1.35 m deep) and replace the arrow at a connected port; a belt into a machine's back feeds it and one at its side or front doesn't, and the words say why; head-to-head belts are stuck, a line carries on, crates and the Hub connect; belts snap behind a machine, in front of it and after a belt, R overrides; a machine's ports in words, a blocked output, a Press fed straight from a smelter; the markers: IN and OUT arrows, one tick and one X; the build line's tick and X). The item-height test now expects items on the belt's deck. Soak one game-day: SOAK OK, 148 s (main today: 125-152 s; nothing new runs per tick).

**Known gaps:** splitters and mergers keep their coloured tabs (no IN/OUT words yet); the markers fade past 45 m.

**Next:** PT, Emmitt's first loud night, now that building reads.

## 2026-10-16 — F6 Compact and deep, part 2: see every machine, days of food and water, shotgun ammo by machine, med kits

Emmitt: "start F6 part 2". The rest of F6: make a compact base easy to read and close the last survival gaps. Code and checks by Claude Opus 5.5.

**Built:**
- **Every machine at a glance:** the base log (L) now has a right-hand column, "Your machines (stuck ones first)": each machine you built, where it is and what it's doing: "Purifier (south-east): needs Rainwater", "Press: output full", "Smelter: no power", "Rain collector: working 50%". In a chain you can see which link stopped.
- **Days of food and water:** a fourth line under "what your machines made": "Yesterday's making comes to about 3 days of food and less than a day of water." A plain answer to "does my base keep me alive?"
- **Shotgun ammo by machine:** the Press now makes gunpowder (8 casings + 1 scrap) and shotgun shells (6 casings + 1 gunpowder), so shotgun ammo can come down a belt like the rest (the workbench recipes stay).
- **Med kits:** R on the canner now also packs med kits (2 bandages + 1 clean water). A med kit gives 40 health back and stops bleeding: use it from your pockets or a hotbar key, and H uses one when you're hurt but not bleeding. It has its own model (a white case with a red cross).

**Try it:** `play.bat --demo-factory --demo-farm`, wait a bit, then L: the machines column shows what each one is doing.

**Tests:** 20,470 green (new `test_deep.gd`: the stuck purifier comes first and says it needs Rainwater, the working rain collector after it, no power is said; three days of cans come to "about 3 days of food", a little to "less than a day"; the Press makes gunpowder and six shells; the canner packs a med kit, it's usable from pockets and hotbar, not when you're well, heals 40 and stops bleeding, and H uses one when hurt but not bleeding). The Press's recipe cycle test now includes the two new recipes. Soak one game-day: SOAK OK, 147 s; the stress test: 4.14 ms a tick (main this morning: 4.16).

**Known gaps:** cotton and med kits have no inventory picture yet (coloured squares); the machine column lists machines only, not generators or turrets.

**Next:** F6 is done. Per DIRECTION.md: PT, Emmitt's first loud night on main (build a loud base on day 1 and survive the wave it draws), the gate before R1 (a private test with friends).

## 2026-10-16 — F6 Compact and deep, part 1: farming that lasts, bandages, tight layouts pay, "what your base made", a third goals chapter

Emmitt: "start F6". The roadmap: recipes chain into what survival needs and loot runs out of, sized for a backyard factory of about twenty machines. The audit: water, warmth, gas, ammo, panels and repair kits already had a machine; food didn't last (a planter ate a seed every harvest, 24 a day, and seeds only came from loot) and bandages were loot only. Code and checks by Claude Opus 5.5.

**Built:**
- **Farming that lasts:** whatever a machine makes that its own recipe uses goes straight back into it, so a planter keeps its seed: one seed now grows for ever. Returned seeds don't count as "made".
- **Cotton and bandages:** R on a planter switches it to cotton (2 a harvest, the seed kept); R on the canner switches it to bandages (2 cotton + 1 clean water make 2). A dropped cotton has its own little model.
- **Tight layouts pay:** a machine fed straight from the machine behind it (its front against the next one's back, no belt) works 15% faster while the parts keep coming; the look-at line says so. A smelter pushing plates straight into a Press is now better than a belt between them.
- **What your base made:** the base log (L) now opens with what your machines made today and yesterday ("Clean water 12, Canned food 4, Bandages 2...") and what you eat and drink in a day (about 1.3 cans of food and 2.5 clean waters on Normal), so you can see whether the base keeps you.
- **"Live off your base"**, a third goals chapter (shown like the others on the left, O hides it): collect water with a machine, clean it in a purifier, grow food in a planter, can it in a canner. It starts when "Defend your base" is done, or from day 5 in any game, so his son gets it even if the defence goals are still open. Goals met early count.
- Flag: `--feed[=N]` (those goals with N done).

**Try it:** `play.bat --demo-farm`, then L after a minute: the machines' output shows at the top. `play.bat --feed=1` shows the new goals.

**Tests:** 20,423 green (new `test_compact.gd`: a planter grows on one seed, the seed never comes out, returned seeds aren't counted as made; R switches the planter to cotton and the canner to bandages, which are real bandages; a press fed straight from a smelter is 15% faster and a belt-fed one isn't; made today and yesterday roll over at a new day, save and load, and the base log's lines say them; what you eat per day matches the data; "Live off your base" starts on day 5, moves through its goals, counts one met early without skipping, saves, finishes; the panel shows it over the defence goals). The item-model test now covers cotton (`tools/art/item_props.py -- cotton`, built with Blender here). Soak one game-day: SOAK OK, 151 and 152 s (main: 140 and 125 s; the branch runs had more fights, 22-28 kills against 15). The stress test settles it: 4.16 ms a tick on both (factory.tick +0.01 ms).

**Known gaps:** cotton has no inventory picture yet (it shows as a coloured square; a Codex icon later); "what your base made" counts what was made, not what was eaten or used up; tiers and machine counts are unchanged (the audit found nothing that only makes sense at Satisfactory scale worth cutting yet).

**Next:** F6 part 2 if the son's logs show he's farming (otherwise PT: Emmitt's first loud night, the gate before anything goes to friends).

## 2026-10-16 — F5 Loudness as a puzzle, part 2: hordes go where it's loudest outside, supply carts, decoys that wear out

Emmitt: "start F5 part 2". The rest of F5: outposts worth using, and decoys with a cost. Code and checks by Claude Opus 5.5.

**Built:**
- **Hordes go for what they hear from outside:** a wave used to walk toward whichever machine had the biggest loudness number, walls or not. Now it goes for the sound that's loudest out in the open (the same measure the heat uses: 50 m out through its leakiest side). So walls, soundproof walls and sound boxes decide where the dead go: box in your home base and a loud salvager out at the junkyard draws the hordes there instead. The warning says where: "A horde is coming from the north, heading for your salvager (Junkyard)...", and the base log too.
- **Supply carts:** a new **cart stop** (Extractors group: 4 planks, 6 nails, 4 scrap). The first one you build is the home stop; put it by a crate at your base (by the Hub, so its parts count for milestones). Every other stop is a pickup with its own little cart: it loads up to 40 items from the crates within 4 m of its stop, drives the roads home, unloads into the crates by the home stop, and drives back. It hums as it drives (zombies hear it pass) and has headlamps at night. E on a stop makes that one home. Looking at a stop says what its cart is doing; the map shows carts as yellow squares; the session log counts what they brought home. So an outpost is: extractor -> crate -> cart stop, and the output turns up at home by itself.
- **Decoys cost something:** a noisemaker shakes itself apart a little with every blare (25 hp of 100): four blares and it falls apart unless you repair it (R). It warns in the base log on its last blare, and looking at it says how many it has left.
- Flag: `--demo-carts` (a home stop and a pickup 30 m up the road with a crate of scrap).

**Try it:** `play.bat --demo-carts --advance=3` shows a cart on its way home. In a game: build an extractor at the junkyard facing a crate, a cart stop beside the crate, and a cart stop by a crate at home (build the home one first).

**Tests:** 20,368 green (new `test_outposts.gd`: walled in at home, the open outpost becomes the target; the warning names "your smelter"; a cart loads up to its cap, drives the roads (over 70 m for 80 m apart), hums while moving, unloads at home, comes back and takes the rest; waits silently when there's nothing, notices new items, counts in the session log; pulling a pickup down gives back its cargo; pulling home down turns carts round; E makes another stop home and the old home becomes a pickup; home, carts, cargo and position save and load; a noisemaker loses 25 hp a blare, warns, and falls apart after four; the cart view draws a cart where the sim says, with a crate only when loaded; the cart stop is in the data and menus). Soak one game-day: SOAK OK, 142 and 158 s in two runs (main under the same conditions: 149 s; nothing new runs in the soak).

**Known gaps:** carts drive through parked cars and zombies (they're ghosts on the road; nothing attacks them); a cart stop only serves crates, not an extractor directly; carts carry anything in the crates, there's no filter.

**Next:** per DIRECTION.md, F6 (compact and deep: recipes that chain into what survival needs), then PT (Emmitt's first loud night).

## 2026-10-16 — F5 Loudness as a puzzle, part 1: see how far it's heard, muffle it, box it in, rest it at night

Emmitt: "start F5". The roadmap: a player should look at a noisy base and see three ways to quiet it. Part 1 makes the noise visible and gives three of the ways. Code and checks by Claude Opus 5.5.

**Built:**
- **See it before you build it:** placing anything that makes noise now shows how far zombies will hear it there. On the build line: "Loudness 60: zombies hear it 200 m off at night, 100 m by day". On the ground: a blue ring (night) and an orange ring (day). On the right: a small top-down **heard map** of both rings to scale, north up, so the walls around show as dents (in the middle of town the sound escapes along the streets and the houses stop the rest). It's the zombies' own rule: the leakiest direction, walls included, a cold winter night carries further, and the difficulty's hearing counts. Looking at a built machine or generator says how far it's heard too.
- **Muffle it, then box it in:** U fits a muffler (-15) as before; U again now fits a **sound box** over it (-12 more, 2 wall panels, 5% slower), on machines and generators. A smelter goes 60 -> 45 -> 33: heard 200 m -> 35 m -> 9 m by night in the open. The look-at line says what U does next.
- **Wall it in properly:** a new **soundproof wall** (Base group: 4 planks, 6 nails, 2 metal plates) stops twice the sound of a plain wall. Boxing a generator in with them is the strongest fix.
- **Rest it at night:** a new **dusk timer** (Power group, cheap, no milestone) stands by a power pole and switches off the machines on that power line from dusk to dawn, when zombies hear furthest; the generator keeps running for lights, fences and turrets and goes quiet if nothing else needs it. It's a sensor ("Machines off" is also a new action any sensor can pick), and the base log says "night, machines off" and "morning, machines back on".
- **Build menu fix:** pieces with a long cost (the Hub, the salvager, the rain collector, both new pieces) had no picture: the button squeezed it out. Every row now keeps a 26 px picture.

**Try it:** `play.bat`, press B, pick the Smelter and look at the ground: the line and the heard map show it. Put walls round a spot and watch the rings dent. For the timer: B > Power > Dusk timer next to your generator's pole.

**Tests:** 20,276 green (new `test_loudness.gd`: open-air radius is the formula turned round, capped at 400 m, 0 when too quiet; a wall dents the ring east, a soundproof wall twice, one for sight; a quiet sound stops at the wall; the preview is louder at night, further on a winter night, cached until the grid changes; loudness of new and built pieces with the muffler, sound box and Dampened Gears; the sound box costs, slows, saves, loads and comes back when the machine is pulled down; a boxed generator is quieter and saves; the dusk timer switches the smelter off at night (not the generator), silences it, logs it, and lets it go at dawn; the ghost shows rings for a smelter and none for a wall; the heard words; the heard map draws north up; the new pieces in the data and menus). One older test now expects U again to ask for a sound box. Soak one game-day: SOAK OK, 147 s (main under the same conditions: 151 s).

**Known gaps (part 2):** outposts worth using (output brought home by belt or cart), decoys with a cost. The ground rings are 100-200 m out for a loud machine, so in first person you mostly see them once a machine is quiet: the heard map is the picture to look at.

**Next:** F5 part 2.

## 2026-10-16 — F4 The loop closes, part 2: belts into the Hub, a rescue night on power, power that follows the threat, a perk pick

Emmitt: "start F4 part 2". The roadmap's last F4 pieces: the Hub and radio tower pulling parts out of the factory on a schedule, and power and panels tuned against loot; plus the perk nudge his son needs (14 points earned, none spent). Code and checks by Claude Opus 5.5.

**Built:**
- **Belts feed the Hub:** run a belt into the Hub and it hands in parts by itself, to the first open milestone (lowest tier first) that still needs them. Anything no milestone wants stays on the belt, so the line backs up instead of losing parts. A milestone finished by belt is announced as one handed in by hand. The session log says how many parts belts handed the Hub.
- **The rescue night runs on power:** the radio mast now needs 60 W while it broadcasts: put a generator with gas beside it (or a power pole from one). It won't start without the power for it. Only powered hours count: it needs 8 hours of signal, and if the generator runs dry the signal drops (silent, a message and the base log say so) and the hours wait. Once the 8 hours are in, the rescuers answer and come at the next 6:00, if the mast still stands. So the rescue night needs the factory's gas, at max heat, while the loudest horde of the game comes. Looking at the mast shows the signal hours.
- **Power that follows the threat:** electric fences draw power all night, and by day only while a zombie is within 6 m (before, a fenced base burned gas all day for nothing). The repair station draws power only while it has panels and something to fix.
- **Tuned against loot:** new `tools/balance.sh` loads the real game and adds up what the whole world's loot holds (30 gas cans in containers + 14 in car tanks, 537 nails, 26 wall panels) against what a defended base burns (about 5 cans a night for 2 floodlights, 6 fences and a repair station; 5 nails per shambler; 4 panels per wall rebuilt). With the new power rules gas, nails and panels each run out from loot around night 2-4 for a base that fights, which is the roadmap's target; the old rules burned the world's gas in two days on fences alone. Report: `docs/perf/balance-2026-10-16-f4.md`.
- **The dawn perk pick:** once a day, in daylight with no zombie within 25 m and perk points to spend, a "A new day. Pick a perk!" screen shows three big cards, one from each tree (the lowest-rank perks first, changing day to day). Click one to take it; with points left it shows three more; "Later" or Esc closes it till tomorrow. A zombie coming within 12 m closes it. K still opens the full skills screen.
- Flag: `--perk-pick` (the pick with three points). `--mast` now puts a fuelled generator beside the mast.

**Try it:** `play.bat`: load his save; if he has perk points, the cards come up the first daylight moment it's safe. For the Hub: run a belt from a crate or machine into the Hub's side.

**Tests:** 20,159 green (new `test_loop_schedule.gd`: a belt hands the Hub a plank for the first open milestone and keeps a part nobody needs; a belt finishes a milestone and unlocks its machines; the broadcast won't start without power, starts with a generator next door, draws its watts and is heard; no power: hours wait, silent, you're told; enough hours: rescue at the next 6:00 even if power goes after; signal hours save and load; a fallen mast loses them; an idle mast draws nothing; a fence wants power by night or with a zombie near, not otherwise; a repair station with panels and nothing to fix wants none and mends a damaged wall; the perk offer is one per tree, lowest rank first, changes by day, skips a maxed tree; the pick waits for points, daylight, once a day and no zombie near; the screen spends points and closes when they're gone). Two older rescue tests now give the mast power and a night of signal. Soak one game-day: SOAK OK, 137 s (main under the same conditions: 142 s).

**Known gaps:** the Hub takes parts from a belt but not from a hopper; the perk pick has no picture per perk (text cards); `tools/balance.sh` works the night's draw out from the data rather than playing a night, so it's a budget, not a measurement of a real siege.

**Next:** his next session log against the F4 measure (builds > 0, waves sent > 0, a belt-fed turret, the base standing at dawn), then F5 loudness as a puzzle.

## 2026-10-15 — F4 The loop closes, part 1: turrets, ammo from the factory, louder bases, bigger hordes

Emmitt: "merge 83 and start F4". The roadmap (#83) asks for a loop where the factory feeds the defense its own noise provokes; his son's session logs show why: three sessions on 10-15 (95 minutes), 77 zombies killed, 37 pieces of gear found, 12 waves survived, and built nothing; 14 perk points earned, none spent. Code and checks by Claude Opus 5.5.

**Built:**
- **A louder base draws bigger hordes:** every wave is multiplied by how loud your base is right now (1x when quiet, 2x at a loud unwalled generator-and-machines setup, at most 2.5x). The message says so when it's a big one.
- **The factory makes every turret's ammo:** the Press already made nails and bolts; now it makes **rifle rounds** too (10 casings + 1 scrap: R on the Press switches to it), so a rifle turret can be fed by belt.
- **The nail turret is there from the start** (it no longer waits for the Hub's Sentry milestone): it's the heart of the loop. Sentry still unlocks the hopper, motion sensor and floodlight.
- **"Defend your base"**, the second chapter of goals (shown on the left like the first night's, O hides it), starts once the first night's goals are done (or from day 2 in an older game, like his son's): build a nail turret, make its ammo with a Press, feed the turret by belt (or a hopper), hold a night (the turret kills a zombie in the dark and a turret still stands at dawn). Each goal says how in plain words, and a message says what's next when one is met.
- **The session log** now says how many times the turrets fired, what they killed, and whether a belt, hopper or machine ever fed one (the roadmap's measure for F4).
- Flag: `--defend[=N]` (those goals with N done; 1+ puts a nail turret ahead).

**Try it:** `play.bat`, keep playing his save: from day 2 the left panel says "DEFEND YOUR BASE". Or `play.bat --defend=1`.

**Tests:** 20,085 green (new `test_loop.gd`: the loudness multiplier and a horde from a loud base bigger than from a quiet one; the Press makes every turret's ammo, rifle rounds from casings; a belt feeding a turret counts and your hands don't; a turret's kill counts in it and in the session log, which says a belt fed one; the nail turret needs no milestone and the hopper still does; "Defend your base" starts after the first night's goals (or from day 2 in an older game), moves on with each goal, survives saving, finishes at dawn after a turret kill in the dark; the objectives panel shows it). Four older tests now expect waves times how loud their machine is, and the Press's recipe cycle includes rifle rounds. One-day soak OK: 154 s per game-day against 155 s for main on the same machine.

**Known gaps (F4 part 2):** lights, fences and the repair station already draw power and the repair station panels, but none of it is tuned against loot yet; the Hub and the radio tower don't pull parts on a schedule yet; perks still need a better nudge (his son never spends them).

**Next:** F4 part 2 (the schedule and tuning), then F5 loudness as a puzzle.

## 2026-10-15 — W3e Population, balance and the map (the bigger world, part 5)

Emmitt: "merge it and start W3e". Code and checks by Claude Opus 5.5.

**Built:**
- **The map** (press **M**): the whole world, north up: every area by name (Town, West and East Street, Downtown, the Industrial park, the Junkyard, the two farms, the woods and the Hunting cabin, the Highway), every road (asphalt, dirt drives, the highway), the resource spots coloured by kind (scrap, water, fuel, timber), your base, the Hub and radio mast if you've built them, and you: a yellow arrow pointing the way you face. M, Tab or Esc closes it. On the controls screen (F1) and the hint line.
- **The further out, the better the loot:** a search rolls more the further the place is from where you start (data/areas.json): town as before, West and East Street 1.1x, downtown 1.2x, the park 1.25x, the farms and the highway 1.3x, the woods 1.4x, the hunting cabin 1.5x.
- **Zombies on the roads between places:** a new game puts eight wanderers beside the roads out in the open (at least 120 m from the start, spread out, one a runner), so a trip across the map isn't empty.
- **Far zombies cost much less:** a zombie more than 60 m from you that's idle, wandering or dead thinks every fourth tick (with the time saved up, so its timers keep pace); it still listens as before, and once a noise draws it, it thinks every tick. And a far zombie strolling about now rests like an idle one (its stroll waits until you come within 35 m or a noise draws it): without that, the eight roadside wanderers made a soak day 16% slower; with it, a soak day is about a third *faster* than before W3e.
- Flag: `--map`.

**Try it:** `play.bat`, then press M.

**Tests:** 19,959 green (new `test_population.gd`: a far idle zombie skips about three thinks in four and still wakes on a noise, then thinks every tick; areas.json checks out, the cabin counts as the cabin (not the woods round it), a crate at the cabin holds more than one in town; the roadside zombies are seeded, eight, away from the start, beside (not on) the roads, out between the places, spread out, one runner; the map opens, finds your base, keeps the world's shape with north up, and M closes it). `test_zombie_world.gd`: a far zombie strolling about rests too; `test_zombie_brain.gd` allows a far corpse its few ticks. One-day soak OK: 134 s per game-day against 207 s for main on the same machine (56 of 58 zombies resting at the end), 535 MB.

**Known gaps:** no fog of war (the map shows everything from the start); older saves don't get the roadside wanderers (they're for new games); zombie numbers per area are unchanged apart from those.

**Next:** the world plan (W3) is done. Next by DIRECTION.md: a playtest of the bigger world (Emmitt and his son), then what it turns up.

## 2026-10-15 — W3d The countryside: farms, the hunting cabin, highway loot (the bigger world, part 4)

Emmitt: "merge both and start W3d". Code and checks by Claude Opus 5.5, using the farm props Codex made for W3a.

**Built:**
- **Two farms**, each round the farm well that was already there (an F1 resource node): a **farmhouse** (one of the town's houses, furnished, fridge and cupboards, a bed), a **red barn** with a pitched roof and a big open doorway (a tractor and three crates to search, round hay bales), a **cornfield** behind a wooden fence with a gate (you and the zombies walk through the corn: good for hiding), hay bales and a water trough in the yard. Each farm has a dirt drive: the west farm off County Road West, the south farm straight on south from where West Street meets Market Street.
- **The hunting cabin** in its clearing in the north-west woods: one dark-wood room with a bed, a hunter's cupboard and a **gun locker**, a good place to find a rifle (about a third of games).
- **Highway loot:** every wrecked car on the highway (and in the junkyard) now has a trunk to search: travellers' things on the highway (food, water, bandages, bags, gas, sometimes a gun), car junk in the junkyard.
- **Zombies:** one in a farmhouse or the cabin (two of the three), one in each barn, two in each cornfield (a runner on the south farm), one by the cabin.
- **Older saves** get all of it built round anything the player already built there (a building that would land on your walls is left out and stays out), like W3c's streets.
- Saves: version 25. Flags: `--at=farm` (the west farm's drive), `--at=cabin`.

**Try it:** `play.bat --at=farm` or `play.bat --at=cabin`.

**Tests:** 19,610 green (new `test_rural.gd`: seeded; every building in its area and off every road, the town, the park, downtown, the new streets, the resource nodes and each other; the fields fenced round with a gate, full of corn, clear of their wells; barns open with a back door, houses and the cabin closed with doors, the cabin's facing the track; laying registers the tractors, barn crates and gun locker, the barns and cabin count as indoors, zombies spawn where they should; the cabin's locker finds guns; every wreck searchable with highway loot on the highway; a version-24 save with a wall where the west farmhouse goes keeps it and the farmhouse is left out, also after save and load; walking into a barn through its doorway and into the cabin through its door). Three older tests count the countryside too (the cabin's locker beats warehouse crates for guns, like the armory's). One-day soak OK: 193 s per game-day against 188 s for main on the same machine (about 3%), 530 MB.

**Known gaps:** the farmhouses are the town's three floor plans; no animals; the barns' crates are the storage-crate model; the corn doesn't change with the seasons.

**Next:** W3e population and balance: zombies and loot per area, far zombies thinking less often, and a map so the bigger world is easy to find your way round.

## 2026-10-15 — W3c More streets of houses (the bigger world, part 3)

Emmitt: "start on W3c" (his son had no complaints after testing downtown). Code and checks by Claude Opus 5.5.

**Built:**
- **West Street and East Street** now have houses down both sides: about two dozen more, roughly double the town. They're the town's own houses (the same three floor plans, brick or siding, furnished, with fridges, kitchen and bathroom cupboards and a bed), so everything that works in town works there: doors, windows, searching, sleeping, indoors for warmth and fog. A lot stands empty now and then, and East Street leaves room for the junkyard lane.
- About **one house in three has a zombie inside**, waiting by the kitchen like the town's.
- A **mailbox** by every front path, a **trash can** behind every house (searchable), and a tree behind about half.
- **Older saves** get the new streets the first time they load, built round anything the player already built there: a house that would land on your walls is simply left out (and stays out).
- Saves: version 24. Flag: `--at=east` (East Street; `--at=west` already showed West Street).

**Try it:** `play.bat --at=west` or `play.bat --at=east`, or walk: West Street is the next road west of Main Street, East Street the next one east.

**Tests:** 19,480 green (new `test_suburbs.gd`: seeded; houses inside their areas and off every road, the town, the park, downtown, the junkyard, the resource nodes and each other for eight seeds; every house closed with its front door 8 m back facing its road; the scenery off roads and houses; laying furnishes every house with a bed, registers the trash cans and spawns a zombie in one house in three, inside; a version-23 save with a foundation and wall on West Street keeps them, the house that would have stood there is left out, and the skip survives saving and loading; the session log names street houses; walking into a West Street house through its front door). Three older tests count the new streets' furniture and trash cans too. One-day soak OK: 189 s per game-day against 175 s for main on the same machine (about 8% for twice the houses and eight more zombies; without the new zombies it's 172 s, so the houses themselves cost nothing), 521 MB. Far idle zombies now rest from 35 m (was 50: still beyond every zombie's 30 m sight), keeping their hit zones in range; the soak's hourly line now says how many are resting (about 70%).

**Known gaps:** no street lamps or fences on the new streets yet (Main Street has them); the houses are the town's three floor plans, so they repeat; the new streets' zombies stand still until they hear you.

**Next:** W3d the countryside (farms and barns, the hunting cabin in the woods, highway loot), then W3e population and balance plus a map.

## 2026-10-15 — W3b Downtown (the bigger world, part 2)

Emmitt: "it needs a much bigger world" (town + countryside). Code and checks by Claude Opus 5.5, using the shop props Codex made for W3a. Stacked on F3 (#82), which is stacked on F2 (#81).

**Built:**
- **Five shops along Market Street**, east of Main Street (walk south from spawn to the crossroads, then east): a **grocery**, a **pharmacy** and a **hardware store** on the north side; the **police station** and a **gas station** on the south side. Each is made of the same pieces as the houses (floors, walls, shop windows along the front, a front door and a back door), so doors open and close, windows break, zombies inside stay muffled, and it counts as indoors (warmth, fog). A coloured sign over each front, flat roofs, concrete sidewalks.
- **Things to search** (E): grocery shelves (canned food, chips, soda, water, seeds), pharmacy shelves and counters (bandages, water), hardware shelves (nails, planks, plates, bolts, repair kits, gas cans, work boots and pants, gun parts sometimes), police desks (ammo, radios), and the police station's **armory**: five **gun lockers** behind an inside wall, the best place in the game to find a gun (about a 1 in 3 chance each) and plenty of ammunition. The gas station has snack shelves, two **pumps** (a gas can or two each) under a canopy, and a dumpster beside every shop.
- **A fuel tanker** parked behind the gas station is an F1 resource node: put a fuel pump on its yellow spot.
- **Zombies:** two in every shop (a brute in the police station) and seven on the street; two or three burned-out cars on Market Street with trunks to search.
- **Saves:** version 23. A save from before downtown gets it built fresh, with its zombies, the first time it loads.
- **Far zombies rest** (W3e pulled forward): a zombie standing idle more than 50 m from you stops animating and skips its physics until a noise draws it or you come close (beyond every zombie's sight, so it notices exactly what it did before). Without this, downtown's 17 zombies made a soak day 60% slower; with it, a soak day costs the same as before downtown (159 s vs 154 s on main).
- **Fix (F2, also pushed to #81):** the radio mast's warning light looked for the mast by walking every piece in the world each frame (another 60% on a soak day); the Hub and mast are now found from an index.
- Flags: `--at=downtown`, `--at=police`, `--at=gas`.

**Try it:** `play.bat --at=downtown` (or walk: south down Main Street to Market Street, then east).

**Tests:** 17,696 green (new `test_downtown.gd`: seeded; inside its area and off every road, house, warehouse and resource node for eight seeds; every shop closed with its doors and windows; props inside their shop, never overlapping, and a walkable way to the front of every shelf, counter and locker; containers and wrecks registered; gun lockers find guns and ammo; zombies in their shops (one brute) and saved; a version-22 save gets downtown fresh; walking into the grocery through its door and finding a solid, searchable shelf); `test_zombie_world.gd`: a far idle zombie rests and a noise wakes it. One-day soak OK, 159 s (main 154 s), 488 MB. The park test now lets gun lockers beat warehouse crates for guns; the street test counts downtown's wrecks and dumpsters.

**Known gaps:** shop interiors are lit only by their windows (dim, like the houses); no shop-specific items yet (medicine is still bandages); downtown's east end past the hardware store is open street (room for W3e or more shops); zombies stand still until they hear you, like the park's.

**Next:** W3c more streets of houses (West and East Street), then W3d the countryside.

## 2026-10-15 — F3 Build feel: drag-placing, field belts, splitters and mergers (building like Satisfactory, part 3)

Emmitt: building should feel like Satisfactory. Code and checks by Claude Opus 5.5. Stacked on F2 (#81).

**Built:**
- **Drag to build a row** ("zooping"): hold left-click, walk or look along, let go. Foundations go in a straight line along whichever way you dragged further; walls run along their edge (a wall on a north edge runs east-west); belts face the way you dragged. Up to 32 at once. Green/red ghosts show each piece while you drag; the HUD says "Built 6 foundations" or "Built 4 of 6 (not enough materials)". A click without dragging still builds one.
- **Belts on bare ground:** belts, splitters and mergers no longer need a foundation, so a line can run from a salvager out at the junkyard back to base. On a foundation they sit on top as before. Belts are now walk-over (like spike strips) so a belt line doesn't fence you in.
- **Belts fill crates:** a belt (or a machine's output) ending at a storage crate puts its items in, up to 500 items per crate. Extractor → belt → crate now works with no one standing there.
- **Splitter and merger** (Factory group; new **Logistics** milestone, tier 2: 15 plates, 15 nails, 10 planks): a splitter takes items at its back and sends them out the front, left and right in turn, skipping a side with nothing to take them; a merger joins belts from its back, left and right into its front. Each holds up to two items while blocked; those save and come back with the refund. Placeholder look: a dark box with orange tabs where items go out and blue where they come in.
- **Fix (F2):** the Hub and radio mast were stored like floor tiles, so a machine could be built floating inside the Hub. They're proper one-per-cell objects now and stand on a foundation if there is one.
- Flags: `--demo-logistics` (a loaded belt line through a splitter into three crates), `--zoop=N` (with `--build`, a held drag preview).

**Try it:** `play.bat`, B → Factory → Belt, hold left-click and walk. `play.bat --demo-logistics` shows a splitter feeding three crates.

**Tests:** 14,446+ green (new `test_build_feel.gd`: ground belts and their height, belt → crate, splitter turns and dead ends, splitter only takes at its back, merger joins and refuses its front, a blocked router holds two through a save and refunds them, Logistics locks both, the Hub as an object, drag run cells and facing; `test_build_world.gd`: a real drag lays four foundations then four west-facing belts, the player walks over a ground belt line).

**Known gaps:** splitter/merger are placeholder boxes (no Codex models yet); no belt lifts or curves (corners still work belt to belt); drag is straight lines only, no diagonal or area fill; crates fed by belts don't count weight.

**Next:** W3b downtown (shops, police station, gas station), then W3c streets and W3d countryside.

## 2026-10-15 — F2 The Hub, milestones and the rescue (building like Satisfactory, part 2)

Emmitt: building should feel like Satisfactory. Models by Codex (one job on his ChatGPT plan), code and checks by Claude Opus 5.5.

**Built:**
- **The Hub** (Build menu, new **Hub** group; one per game, no foundation): your base's command post, a desk with a map, a radio and a milestone board. E opens the **milestones screen**: every milestone tier by tier (done, open, locked); pick one to see its parts (handed in / needed, and how many are in reach: your pockets and any crate within 8 m of the Hub), what it unlocks, and **Hand in what's in reach**. Parts go in part at a time and stay in.
- **Seven milestones in four tiers** (`data/milestones.json`): Tier 1 Scavenger (Salvage rig: salvager + water pump; Lumber yard: sawmill), Tier 2 Settler (Fuel line: fuel pump + solar panel; Kitchen: purifier + canner; Sentry: nail turret, hopper, motion sensor, floodlight), Tier 3 Fortress (Heavy defense: crossbow and rifle turrets, electric fence, repair station, noise sensor, noisemaker), Tier 4 Rescue (Rescue signal: the radio mast). A tier opens when the one before is all done. Locked pieces say which milestone opens them; the basics (foundations, walls, smelter, press, generator, belts...) are never locked.
- **The rescue (the game's goal):** build the 12 m **radio mast**, press E at dusk (after 18:00) to start the broadcast: it's a 100-loud noise all night and the Director's heat jumps to the top, so the hordes come. Keep the mast standing until 06:00 and the helicopter comes: a **RESCUED** screen with your day, kills and milestones (Keep playing carries on). If the mast falls, the broadcast is lost; rebuild and try again. Its warning light blinks red while it broadcasts.
- **Saves:** version 22 keeps milestones, handed-in parts and the broadcast. **A save from before the Hub gets every milestone but the rescue**, so nothing it built is locked away. A new game starts with all of them ahead.
- First-game tips gain two steps: build a Hub, hand something in.
- Flags: `--hub[=N]` (a Hub ahead with N milestones done, its screen open), `--mast` (a radio mast ahead, broadcasting after 18:00).

**Try it:** `play.bat` (new game), build a Hub from the Hub group, press E on it. `play.bat --mast --time=19` shows a broadcasting mast.

**Tests:** 14,360+ green (new `test_hub_milestones.gd`: tiers open in order, part-at-a-time hand-ins, locks and unlocks, one Hub, hand-ins from crates near the Hub, the broadcast refused at noon / started at dusk / heard by everything / rescue at dawn / lost if the mast falls, saves, the old-save grant; `test_hints.gd` for the two new tips). Test worlds (`SimWorld.new`) start with everything but the rescue unlocked, like `power.free`; a real new game clears it.

**Known gaps:** no rescue cinematic (a screen, not a helicopter yet); milestone costs are first guesses for Playtest #2 to tune; a Hub you lose is just rebuilt (its progress is kept).

**Next:** F3 build feel (drag belts, splitters and mergers, snapping), then W3b downtown.

## 2026-10-15 — F1 Resource nodes and extractors (building like Satisfactory, part 1)

Emmitt: "I'd like the building to be more like Satisfactory but it doesn't feel like it fits into the game right now." Models by Codex (one job on his ChatGPT plan), code and checks by Claude Opus 5.5. Stacked on W3a (#78).

**Why:** nothing in the survival loop needed a factory: loot gave you everything and machines only made noise. F1 gives the factory things only it can do.

**Built:**
- **16 resource nodes on the map** (`data/resources.json`): scrap heaps in a new **junkyard** east of town (fenced, wrecked cars, a dirt lane from East Street) and by the highway jams, **farm wells**, two **crashed fuel tankers** by the highway, and **timber stands** in the woods. Each is poor (x0.5), normal or rich (x2). Its own model stands beside a **yellow painted spot**; looking at either says what it is and what to build ("Scrap heap (rich) - Build a Salvager on the yellow spot").
- **Four extractors** (Build menu, new **Extractors** group): **Salvager** (scrap metal, very loud), **Water pump** (dirty water), **Fuel pump** (gas cans for generators and cars), **Sawmill** (planks; a portable bandsaw mill, for Emmitt's HM122). They go only on their kind's spot, need no foundation, need power, make their resource with nothing put in, at the node's purity, and are as loud as machines should be: an outpost draws zombies.
- Rules: `BuildGrid.nodes` + `needs_node` in buildables.json; `Factory.Machine.node_rate`; `SimWorld.resource_nodes` / `node_at()`. Nothing new is saved (nodes are fixed; extractors are pieces like any machine).
- `NodeView` draws the nodes and spots; the countryside keeps clear of them. Flags: `--demo-outpost` (one of each extractor built and running), `--at=junkyard|timber`.

**Try it:** `play.bat --at=junkyard --demo-outpost`, or find the junkyard (east of East Street, down the dirt lane) and build a Salvager on a yellow spot with a generator and a power pole.

**Tests:** 13,883 green (new `test_resource_nodes.gd`: the data, every node on the map and off the roads, spot-only placement with no foundation, each extractor making its resource with no input at its purity, rich = 2x normal, loudness, no trees on nodes).

**Known gaps:** outposts are far from town and belts cost a plate per 2 m, so for now you fetch the output by hand or by car (F3 brings better logistics); nodes never run dry; the salvager's claw doesn't move.

**Next:** F2, the Hub and milestones (deliver parts to unlock machines and tiers, ending in a radio rescue), then F3 build feel.

## 2026-10-15 — V35 Zombies die facing you

Emmitt: "the zombies seem to die facing away from the player each time". By Claude Opus 5.5.

**Found:** the zombies' Death animation (Quaternius UAL "Death01") falls *backwards*, but V7 assumed it fell forwards and turned every dying zombie to face away from the blow first, so each one showed you its back and fell toward you.

**Fixed:** a dying zombie now turns to face whoever hit it (you, when nothing knocked it) and goes down one of two ways:
- **Backwards** (6 in 10, and always after a hard hit like a shotgun blast or a heavy swing): the Death animation, sliding back a little from the blow, landing on its back with its feet toward you.
- **Forwards** (the rest): its hit reaction, then it tips over toward you about its feet and lands face down.

`ZombieBody.death_style_for` picks by id, so the same zombie always dies the same way. Screenshot flags: `--dead-zombies` now shows bodies already fallen, and `--death-style=back|forward` forces one.

**Try it:** `play.bat --zombie=-3,-5,0,-5,3,-5,-1.5,-8,1.5,-8 --dead-zombies --advance=1.6 --cam=0,0,0,0,-14`, or just fight.

**Tests:** 13,525 green (`test_hits_deaths.gd`: facing the blow, hard hits go backwards, the 6-in-10 split, the forward tip).

**Known gaps:** a forward fall uses the hit reaction's bent-knee pose, so the feet stay a little raised once it's down; a proper forward-death animation would need a new motion clip (none in the free packs).
## 2026-10-15 — W3a The bigger world: roads, countryside and a tiled navmesh

Emmitt: "it needs a much bigger world" (town + countryside). Props by Codex (one job on his ChatGPT plan), code and checks by Claude Opus 5.5.

**Built:**
- **The map is 720 x 760 m** (`WorldMap.EXTENT`), about 28x the old street. Main Street, the factory hall and the park keep their places, so saves load as before; nothing new is saved (the same land every game).
- **A road network** (`WorldMap.ROADS`): Main Street runs on south to Market Street (downtown, next), West and East Street (more houses, next), County Road West and a farm lane, a dirt track from West Street into the woods, the north road past the park, and a 4-lane highway down the east side. `RoadView` draws them (asphalt with centre dashes, dirt, the highway with lanes, edge lines and guardrails).
- **Zombie waves use the roads:** a group or horde starts on a road 110-180 m along the roads from the noise (and at least 70 m away in a straight line, so never on the next street over), out of sight, and walks `WorldMap.route()` to it; the message names the compass way ("A horde is coming from the south-east..."). Wanderers start 70-120 m out.
- **The countryside** (`CountryPlan`, `CountryView`): pine woods in the north-west, leafy and pine trees over the fields, rocks and bushes, a forest belt and concrete barriers where the world ends (an invisible wall behind them), and jams of rusted wrecks on the highway. Trees and props are drawn from one MultiMesh per kind; trunks, rocks, guardrails and barriers are solid. Leaves follow the seasons.
- **The navmesh is tiled** (`NavBaker`): 64 m tiles, each its own region (baked with a border so tiles meet exactly, even through a wall on a seam). The fixed scenery is read once; building something re-bakes only the tiles round it, one at a time in the background. Startup bakes where you are (~0.5 s) and the rest of the map in the background.
- **22 new props by Codex** (`tools/art/world_props.py`, contact sheet `tools/art/world_props_contact.jpg`): pines, bushes, rocks, guardrails, barriers and road signs are used now; the shop shelves, checkout, pharmacy counter, police desk, gun locker, gas pump, dumpster, bench, hay bales, corn, farm fence, tractor and water trough are for downtown and the farms.
- Screenshot flag `--at=market|south|highway|woods|farms|west`. `tools/test.sh "a|b"` runs the files matching either.

**Try it:** `play.bat`, then walk or drive south past the end of Main Street, or `play.bat --at=highway`.

**Tests:** 13,697 green (new `test_world_map.gd`; the road-horde, park and street-plan route tests rewritten for the network; navmesh tests now wait for the map to sync in real time). Soak 1 day: SOAK OK.

**Known gaps:** the new areas are open land for now (downtown, the new streets and the farms come next); memory is about 455 MB (was 270) and the worst physics frame about 7 ms (was 3); the tree belt hides the map's edge but the barriers don't say why; wrecks on the highway can't be searched yet.

**Next:** V35 (deaths facing you), then F1-F3 (building like Satisfactory), then W3b-d. See the top of `docs/DIRECTION.md`.
## 2026-10-14 — V34 Items in the world: dropped things look like themselves, and placing (Sprint 4)

Emmitt: "could you add a PR for skins for the items dropped? also allow placing items". Models by Codex (one job on his ChatGPT plan), code and checks by Claude Opus 5.5.

**Built:**
- **37 new item models** (`tools/art/item_props.py` -> `assets/models/item_<id>.glb`): every stack item (food, water, nails, planks, ammo boxes, bags, gas can, radio...) and every wearable (jacket and vest folded, pants, boots and sneakers as pairs, gloves, hard hat, cap, headlamp). Weapons, guns, gun parts, the bottle and the pipe bomb use their own models. Materials are named "Item ..." and textured by `BagView.ITEM_LOOKS`. Contact sheet: `tools/art/item_props_contact.jpg`.
- **Dropping:** Drop in the inventory puts the thing on the floor a step in front of you as itself (a rifle on its side, an axe flat), turned the way you face; the same item dropped on the same spot joins that stack (up to three shown side by side). Looking at it says what it is ("12 Nails", "Work boots"); E picks it up. Death bags now look like a stuffed rucksack.
- **Placing:** Place in the inventory (items and gear) closes it and shows the thing see-through where you aim: any floor, table, counter or shelf within about 3 m. Mouse wheel turns it, left click puts one down (stays ready while you have more), right click or Esc stops. The sim checks reach (`SimWorld.place_item` / `place_gear`).
- Saves: version 21. Each thing on the ground keeps its kind and facing; older saves load their bags as bags (fixture `test/fixtures/save_v20.json`).
- Screenshot flags `--drop=A,B,...` (a row of things ahead of you) and `--place=ITEM` (placing mode on).

**Try it:** `play.bat`, Tab, pick something, Drop or Place. Or `play.bat --drop=canned_food,soda,jacket,hunting_rifle,axe --cam=0,0,0,0,-38` to see a row.

**Tests:** 13,872 green (new `test_items_in_world.gd`: drop in front of you, stacking, naming, picking up, gear, placing reach, save round trip, old saves, a model that rests on the floor for every item and wearable, the placer on a floor vs. nothing in reach; `test_inventory_actions.gd` updated for drops as themselves).

**Known gaps:** zombies ignore things on the ground; you can't place on top of another placed thing yet; labels on cans and boxes are colour bands, not printed text; the three backpacks are boxy.
## 2026-10-14 — V33 Better hitboxes: hit zones on the bones (Sprint 4)

Emmitt: "add better hitboxes". By Claude Opus 5.5. Stacked on V32 (blood toggle): both touch the hit code.

**Built:**
- **Hit zones that move with the animation.** Every zombie has a box on each of its 17 bones (head; neck, chest, spine and hips = torso; arms and hands; legs and feet), fitted to that body's own mesh, once per body variant (`ZombieHitboxes`, on a new physics layer `Layers.HITBOX`). A crawler's head is down by the floor, a runner's swinging arm is where you see it, a brute's zones are brute-sized.
- **Guns are exact:** a round through the gap between arm and body flies on (a miss, or the zombie behind). **Melee is forgiving:** a swing that touches the body but slips between zones still hits, in the zone at that height.
- **Damage by zone** (`data/hit_zones.json`): head = the weapon's or gun's own head multiplier as before, torso 1.0, arms 0.6, legs 0.75, and a **leg hit makes it limp** (55% speed for 1.5 s). Messages say "Headshot!", "Arm hit", "Leg hit".
- **Crossbow bolts** (simulated in the sim) now land in a zone too, by where they meet the body: a bolt to the head is a headshot (with the headshot sound). A crawler's head is the front of its body (`head_ahead` in zombies.json). Shotgun pellets stay flat damage, as in V30.
- Past 45 m from you the zones switch off and the old capsule with its head and leg lines decides (cheaper with a crowd far away). Dead bodies have no live zones; E searches them as before.
- Screenshot flag `--hitboxes` draws the zones (head red, body yellow, arms blue, legs green).

**Try it:** `play.bat --zombie=0,-3 --hitboxes --cam=0,0,-0.5,0,-8` to see the zones; then play normally and try legs, arms and heads with the rifle.

**Tests:** new `test_hitboxes.gd` (zones on every bone and moving with the animation, a ray at each zone counts as that zone, a gap a round passes through but a swing doesn't, the crawler's head by the floor, zones off on a dead body, damage per zone, the limp, bolts by zone).

**Known gaps:** pellets don't use zones (a shotgun is about the spread); hands count as arms; the zones are boxes, so the very edges of a shoulder or hip can be a few centimetres generous.

## 2026-10-14 — V32 Blood on/off (Sprint 4)

Emmitt: "add the blood toggle" (his son plays). By Claude Opus 5.5.

**Built:**
- **Settings → Blood** (on by default, saved in `user://settings.cfg` with the other settings). Off: a hit on a zombie puffs dust instead of spraying blood, and no blood stains are made under hits or bodies. Turning it off clears the stains already on the ground.
- One gate for every caller (guns, shotgun pellets, melee, thrown bottles and bombs, bodies): `ImpactFx.shown_kind` and `ImpactFx.stain`.
- Screenshot flag `--blood=off` (this run only, not saved).

**Try it:** `play.bat`, Esc → Settings → untick Blood, then hit a zombie.

**Tests:** 13,527 green (new `test_blood_setting.gd`).

**Known gaps:** the zombies' own clothes and skin textures keep their grime; only sprays and stains are switched.

## 2026-10-14 — Q6 Second pre-playtest check, after V23-V31 (Sprint 4)

The check DIRECTION.md asks for before a playtest, on `main` at #73 (attachments, guidance, save slots, crawler and brute, difficulty and the first night, new weapons, the arm fix all merged), by Claude Opus 5.5 on the PC. Also read the newest session logs (45 minutes on 10-14: 11 perk points earned and none spent, two gold pieces found but a white pipe worn, nothing built, no deaths; V25 and V29 were aimed at exactly that).

**Found and fixed:**
- **Iron sights sliced your right hand.** Since V16 the camera skipped everything closer than 34 cm while aiming a long gun, so the stock didn't fill the view, but that also cut the right glove and sleeve into a hollow horn shape. Now only the gun's own surfaces fade out up close (a per-pixel distance fade on the gun's materials, `Shooter._fading_gun_materials`), and the right arm runs whole to the bottom-right corner, like an arm. `test_ads_fade.gd`.
- **Respawning into the zombies that killed you** (Q5 flagged it; this soak hit it on the first night: dead at 21:12, again at 21:19, again at 22:01). For 8 seconds after a respawn zombies take no notice of you (`respawn_grace` in `data/survival.json`), so you can get away; swinging, shooting or throwing ends it early. `test_respawn_grace.gd` (fails without the fix). The soak bot still dies three times, because it fights instead of running and its swing ends the head start; a person runs.
- **The dusk warning after dark:** a game started or loaded on day 1 after 21:00 said "It'll be dark at 21:00" with "Night falls" under it (tour shot 08). The warning now only shows between 19:00 and 21:00. Test in `test_difficulty.gd`.
- `docs/SPRINT.md` caught up: V6 to V22 marked merged, V23 to V31 and Q6 added.

**Found, not changed:**
- The bot ran out of water twice (dehydration on day 2 night and day 4); Q5 had one. That's mostly the bot never searching for water; worth watching in Playtest #2.
- Director heat reads 145 in the soak: that's fine, the cap has been 150 since M5.

**Result:** `tools/soak.sh --days=3` reports SOAK OK twice (136 and 150 s per game-day, no errors, no stuck physics). `tools/tour.sh`: all 16 shots fine. `tools/test.sh`: 13,518 passed.

**Try it on the PC:** `play.bat --gun=rifle --time=12`, hold right click (iron sights). To see the head start, die near zombies on purpose and run when you come back.

**Next:** Playtest #2 (V8): 30 minutes from a new game, pick a difficulty, and the session log pasted into `docs/PLAYTESTS.md`.

## 2026-10-14 — V31 The left arm on long guns is one arm again (Sprint 4)

Seen in V30's screenshots: on the hunting rifle the left forearm looked like a separate floating pipe beside the hand. By Claude Opus 5.5.

**Fixed:**
- **Found by measuring the arm model:** its own sleeve runs straight down the forearm bone, but its hand and wrist cuff sit about 8 cm to one side of that line, so the sleeve never met the wrist. V22's extension followed the bone too, so it made the gap longer.
- **One sleeve, centred on the cuff:** `Hands._prepare_rig` now builds a single tapered sleeve from over the glove's cuff, up the forearm to the wrist joint and 45 cm past the elbow, centred on the cuff (`Hands.cuff_centre`, measured from the mesh once per side). The model's own off-line sleeve is hidden.
- Checked on the rifle (day, night, iron sights, reload), the pistol rack, fists blocking, the pistol and the axe. Pistol and axe frame the same as before (their hands sit below the screen at rest).

**Try it:** `play.bat --gun=rifle --time=12`, then R to reload.

**Tests:** 11,896 green (`test_hand_poses.gd`: the sleeve is centred on the cuff, starts near the wrist, and the model's sleeve is hidden).

**Known gaps:** the MakeHuman glove has a long, thin wrist that bends off to the side, so a thin brown strip still shows between the hand and the sleeve. On iron sights the right glove still fills the lower middle of the screen (the camera sits right at the stock), and when a reload brings the left hand near the camera the sleeve shows as a big close-up cylinder. A real fix is a proper FPS arms model (the paid pack we talked about).
## 2026-10-14 — V30 Shotgun, crossbow, pipe bomb and bottle (Sprint 4)

The session logs say fighting is the fun; Emmitt asked for grenades earlier. Built by Codex (one job on his ChatGPT plan, on top of V23 attachments); fixes and the checks by Claude Opus 5.5.

**Built:**
- **Pump shotgun** (Primary): 6 shells, 8 pellets of 18 in a 4.5 degree cone with falloff from 12 to 28 m, loudness 100, a pump between shots (0.85 s), loads one shell at a time (0.58 s each, firing interrupts). Takes a padded stock and a new **choke** (40% tighter spread); no suppressor or scope.
- **Crossbow** (Primary): 100 damage, loudness 25, one bolt, 2.8 s draw; the bolt is a real projectile in the sim (55 m/s with gravity), drawn in flight; 70% of bolts can be picked back up from bodies or where they land. Takes a scope; bolts are craftable.
- **Pipe bomb** (throwable): hold to throw with an arc preview, bounces, 3 s fuse, 5 m blast with damage, knockback and stun that fall off, hurts you too, lightly damages pieces, and is loud enough (150) to draw everything around: a lure as much as a weapon. Crafted at the bench (scrap, gunpowder, nails).
- **Glass bottle** (throwable): shatters where it lands with a noise (65) that zombies go to investigate, for sneaking past.
- Throwables go on the hands bar; left click holds/releases to throw, right click cancels. Models, icons and sounds for all of them; grips and sights measured from the models; loot and recipes.
- Fixes by Claude: a Codex edit had pasted the throw key hints into the `--inspect-at` code (main.gd didn't compile); kitchens found guns 3x as often as before and the unplaced police/hunter/cabin sources beat warehouse crates (rebalanced); bottles made trash bins mostly full (rarer now).

**Try it on the PC:** `play.bat --gun=shotgun`, `play.bat --gun=crossbow`, `play.bat --throw=pipe_bomb`, `play.bat --throw=bottle`.

**Tests:** 13,149 green (new `test_new_weapons.gd`).

**Known gap (from V22, now visible on every long gun):** the left arm's sleeve extension shows its open end and looks detached from the forearm on the rifle, shotgun and crossbow fore-end grip; fixing next.

## 2026-10-14 — V23 Tarkov-style gun attachments (Sprint 4)

Emmitt: "the attachments for guns, none of them work, make it so the guns have attachment slots like in tarkov." Built by Codex (one job on his ChatGPT plan); review, one fix and the checks by Claude Opus 5.5.

**Why they didn't work:** fitting was only possible at the workbench screen (hard to find), the inventory told you to go to a workbench, the parts were invisible on the gun, every gun shared one slot list (a pistol could take a stock), and parts almost never dropped.

**Built:**
- **A modding panel in the inventory:** select a gun (pockets, a container, Primary or Sidearm) and its attachment slots appear: pistol = muzzle, magazine, sight; hunting rifle = muzzle, magazine, sight, stock (per gun in `guns.json`). Drag a part on (or double-click it), drag it off (or double-click the slot). Works anywhere, instantly; crafting parts still needs the bench. Fitting makes a small noise.
- **Stats you can see:** damage, recoil, accuracy cone, raise time, magazine and loudness, with each part's change in green or red, all from the sim.
- **Parts on the gun:** five new models (`tools/art/part_*.py`): oil-filter and machined suppressors, a longer magazine, a scope with rings and turrets, a rubber recoil pad, fixed at anchors measured on each gun.
- **Effects that matter:** suppressors 20 / 30 quieter, the extended magazine +50% rounds (reloads fill it), the scope's zoom and tighter cone, the padded stock 35% less recoil.
- **Parts drop:** car trunks 12%, factory crates 35%, industrial loot 45%, zombie corpses 8%.
- Fix by Claude: looking through the scope showed the back of the scope tube over the target; the gun hides again at full scope aim (the zoom and reticle take over), as before.

**Try it on the PC:** find a gun and a part, press Tab, click the gun; `play.bat --mod-screen=rifle` gives you a rifle and every part.

**Tests:** 12,014 green (new `test_gun_mods.gd`).
## 2026-10-14 — V29 Difficulty, and a first night that matters (Sprint 4)

Nobody had died in nine sessions and nobody built a shelter, because nothing forced it; Emmitt wanted the first night to matter and an easier setting for his son. Built by Codex (one job on his ChatGPT plan, on top of V26 save slots and V25 objectives); a test fix, a screenshot flag and the checks by Claude Opus 5.5.

**Built:**
- **Easy / Normal / Hard**, chosen on the New game screen after the slot name, saved with the game (VERSION 20; older saves load as Normal) and shown in the slot summary and pause menu. One `Difficulty` object (data in `data/difficulty.json`) scales zombie damage (0.5 / 1 / 1.5x), health (0.6 / 1 / 1.4x), counts and night waves (0.6 / 1 / 1.5x), Director heat (0.6 / 1 / 1.5x), hunger/thirst/energy drain (0.6 / 1 / 1.4x), loot (1.5 / 1 / 0.7x) and how much better zombies hear and move at night. Skills are kept on death on every setting.
- **The first night:** at 19:00 a warning ("It'll be dark at 21:00. Find shelter: a bed inside walls with a door"); at 21:00 "Night falls" and a wave (Easy 3 slow ones, Normal 5, Hard 8 with a runner). Caught outside, they hunt you; in a shelter (a bed in a closed player-built room, or a closed town house with intact windows) they mill around outside unless you make noise. At 06:00 "You made it to morning". Later nights keep the heat-driven waves, more dangerous than days.
- `--new-game[=SLOT]` opens the New game screen for screenshots.
- Test fix: the road-horde tests start at 23:00 on day 1, so the first-night wave joined them; they mark the first night as done.

**Try it on the PC:** New game, pick a difficulty, and see if you can get a bed behind walls and a door before 21:00. The 1-day soak bot survives (2 waves, 1 death).

**Tests:** 12,116 green (new `test_difficulty.gd`, fixture `save_v19.json`).
## 2026-10-14 — V28 New zombies: the crawler and the brute (Sprint 4)

The session logs say fighting is what keeps players going; more kinds of zombie to fight. Built by Codex (one job on his ChatGPT plan); three test fixes and the checks by Claude Opus 5.5.

**Built:**
- **Crawler:** ruined legs, drags itself along the floor (the Crawl animation). 70 HP, 0.6 m/s, a low box collider (shots must go low; its head is near the floor and headshots count there), hears and moans quieter, grabs your ankles (1.5 s stumble at 45% speed), never breaks doors, crawls through a broken window in 4 s. About 1 in 12 street zombies and 1 in 4 house zombies from day one.
- **Brute:** the heavy body at 1.28x, darker and battered. 300 HP, 0.8 m/s, hits for 24 and shoves you about a metre, breaks doors, windows and barricades 3x faster, blocks only half work and a parry doesn't stagger it, melee barely moves it; a deeper groan. Unlocks at 5,500 infamy and joins night waves only (one per group, two per horde, two alive at most).
- All numbers in `data/zombies.json`; headshot and sight heights follow each type; the session log and the noise overlay name them.
- Test fixes: a disabled body leaves physics in Godot (the crawler hit-box test needed `DISABLE_MODE_KEEP_ACTIVE`), a kill capped the headshot damage the test compared, and the house-hearing test now skips crawlers (they hear less on purpose).

**Try it on the PC:** `play.bat --zombies=0 --zombie=0,-4 --zombie-type=crawler` or `--zombie-type=brute`.

**Tests:** 11,989 green (new `test_zombie_types.gd`).

## 2026-10-14 — V27 Take all button, wear gear straight from a container (Sprint 4)

Emmitt: "a loot all button might help, I also noticed that we can't immediately equip items, it has to go to inventory before being equipped". By Claude Opus 5.5.

**Built:**
- **Take all (R)** is now a button beside the container's name, not only the R key.
- **Wear it from the container:** a gear piece in an open container has an Equip action, and you can drag it straight onto a character slot. What you wore there goes into your pockets, or stays in the container if you can't carry it (the message says so). Gun parts and wrong slots are refused with a reason. Rules in the sim (`SimWorld.can_equip_from_container` / `equip_from_container`).

**Tests:** 11,876 green (new `test_loot_polish.gd`).
## 2026-10-14 — V24 Fixes from play: sleeping, the roof, zombie arms (Sprint 4)

Emmitt, after playing: "I was not able to sleep or regain energy", "if you jump in a house you can see through the roof and you can see zombie arms sticking through walls". By Claude Opus 5.5.

**Fixed:**
- **You can sleep again.** E on a bed put you to sleep, but the same key press then reached main.gd, where "any key wakes you" woke you in the same instant, so energy never came back. The interactor now marks that E press as used once it puts you to sleep, the way it already did for getting into a car. `test_sleep_key.gd` presses E through the real input path (it fails without the fix).
- **No more seeing through the roof.** House and factory roofs had no colliders on purpose (sound is 2-D), so a jump, or a jump off the furniture, put your head and the camera up through the ceiling. Each roof now has a ceiling slab on its own physics layer (`Layers.CEILING`) that only the walker bumps into; the navmesh, rays and sound still ignore roofs.
- **Zombie arms stay out of walls.** The motion-captured walk and scratch hold the arms past the body's 35 cm capsule, so a zombie pressed against a wall put its hands through. A ball at arm height in front of the chest (reaching 0.54 m ahead) keeps the body back; it goes with the capsule when the zombie dies. Attack range (1.5 m) is unchanged.

**Try it on the PC:** sleep in any bed in a house when you're tired (energy under 90); jump inside a house; let a zombie chase you to a wall.

**Tests:** 11,870 green (new `test_sleep_key.gd`, `test_clipping.gd`).
## 2026-10-14 — V26 Save slots: one per player (Sprint 4)

Emmitt and his son share the PC and there was one save file, so they overwrote each other. Built by Codex (one job on his ChatGPT plan); a safer migration, two fixes and the checks by Claude Opus 5.5.

**Built:**
- **Three save slots**, each its own file (`user://saves/slot_N.json`) with a name you type ("Dad", "Kaleb"), the day and time in game, time played, zombies killed and when it was last played. The title screen's Continue opens a slot picker; New game asks which slot (warning before replacing one) and for a name; each slot has Delete with a confirm. The pause menu, F5 and F9 use the slot you're playing; session logs name it. Settings stay shared.
- **Your old save becomes slot 1 automatically** the first time, named "Slot 1". It is COPIED: the old `save.json` is never deleted (Codex's version moved it, which would have made a screenshot or test run of this branch take the save away from the current build on main).
- Fixes: the slot picker's test helper looked one level too shallow; the migrated save's "Last played" showed UTC instead of local time.

**Try it on the PC:** `play.bat`, Continue: your current game is Slot 1; New game into Slot 2 with your son's name. `play.bat --slots` opens the picker.

**Tests:** 11,909 green (new `test_save_slots.gd`, all on test-only paths; no real save is touched).
## 2026-10-14 — V25 First-hour guidance (Sprint 4)

The session logs (nine sessions, about 80 minutes, Emmitt and his son) showed nobody dying, almost nobody building, 24 perk points earned and 2 spent, and good gear found but never worn. Built by Codex (one job on his ChatGPT plan); checks by Claude Opus 5.5.

**Built:**
- **Perk points get noticed:** a toast when you earn one ("Perk point! Press K") and a small badge while any are unspent; the skills screen highlights them.
- **Better gear gets worn:** picking up or looting a piece better than what's in that slot (rarity, tier, condition and the slot's main stat, compared in the sim) shows an 8-second toast in its rarity colour; **Y** puts it on straight away (checked again before equipping).
- **A first-night goal list** in a new game, top-left: find food and water, find a bed, before dark (21:00) shelter a bed with walls and a door (it ticks the foundation, the bed inside, walls and door as you build; town houses don't count), survive the night. **O** hides it; "Show objectives" in Settings. Saved with the game (VERSION 19; older saves load with it off).
- The session log now records gear you equip and perk points spent, so we can see whether this works.

**Try it on the PC:** start a New game; `play.bat --objectives` shows the list half done.

**Tests:** 11,929 green (new `test_guidance.gd`).

## 2026-10-14 — V22 Hands fixed in the engine (Sprint 4)

Emmitt: "fix the hands in the engine". Every Blender pass bent some finger the wrong way once it reached Godot, so the poses are now built in Godot, where they can be measured. By Claude Opus 5.5.

**Built:**
- **Finger poses made in the engine** (`Hands.build_pose_library`): the arm's rest pose is the grip round a 34 mm handle; each pose says how bent each joint should be (knuckle, middle, tip) per finger, and each joint is turned about its finger's own curl axis, measured from the rest bones, by the difference. The fist is fully closed (88/100/62 degrees) with the thumb across; Flat is straight; Open, Pinch and HoldMag are relaxed versions. The baked Blender poses are replaced when the arm loads; nothing else changed for the code that asks for poses.
- **The arm reaches the shoulder:** a 45 cm sleeve continues the jacket past the end of the model's forearm (a tube on the Forearm bone in the sleeve's own cloth), so the arm always runs off the screen.
- **A free hand's forearm points at the shoulder:** when the left hand lets go of the gun (magazine, slide, cartridges) it turns so its forearm runs back toward that side's shoulder, below and beside the eye, instead of pointing up the sleeve at you; on the grip the hold is exactly as before.
- The bare-wrist band (an open ring that showed as a peach scroll) is the jacket's cuff now.

**Try it on the PC:** `play.bat --gun` then R (reload) and V; `play.bat --fists` and hold right click; `play.bat --gun=rifle` then R.

**Tests:** 11,856 green (new `test_hand_poses.gd`: each pose bends each joint by what it asks for, the fist closes, flat is straight, the sleeve, the free forearm). Test lesson: a Skeleton3D only recomputes global poses inside the tree, and reading one before that freezes the cache.

**Known gaps:** the hand model itself is still MakeHuman's with a glove texture (no stitched seams up close); the ADS pistol grip shows both hands large at the bottom edge.

## 2026-10-14 — V20 Realistic zombies: MakeHuman bodies with motion capture (Sprint 4)

Emmitt: "more realistic ... zombies". Bodies and animation by Codex (three jobs on his ChatGPT plan, one cut off by the weekly limit and resumed); review in the game and the pick by Claude Opus 5.5.

**Built:**
- **Five new zombie bodies** from the MakeHuman human (MPFB 2.0.18, CC0 output) by `tools/art/zombie_mpfb.py`: an average man, a heavy man (hard hat, vest), a slim man, a short man (cap) and a woman; grey-green mottled skin, sunken eyes, hair, wounds, a torn shirt (the game still tints and textures it per zombie), jeans and work boots. Same 17-bone skeleton, animation names and material names as before, so `zombie_body.gd` didn't change. `zombie.py` (the blocky ones) is superseded.
- **Motion capture** from Quaternius' Universal Animation Library 1 and 2 (CC0; the originals live outside the repo at C:/projects/assets-src/quaternius-ual, so only the PC can rebuild): Idle = zombie idle (corrected into a standing sway), Walk = zombie walk, Run = sprint with a hunched layer, Punch = zombie scratch, Death = Death01, HitReact = Hit_Chest, Crawl = crouch walk with a crawl layer; the Scream is hand-made. Walk and Run are retimed to the game's 1.0 and 3.45 m/s so feet don't slide.
- The UAL-pose arms pass from the same branch was rejected in the game (the fingers came out as flat twisted ribbons) and the V16 arms stay; the attempt is in history (534fac9).

**Try it on the PC:** `play.bat` and walk down the street; `play.bat --zombie=0.3,-2.2 --zombies=0` for one close up.

**Tests:** 11,753 green (the art-model, textured-look and zombie tests pass on the new bodies unchanged).

**Known gaps:** faces are simple and the boots a little big; a $100 motion-capture pack (MoCap Online) would add lunges, grabs and directional deaths if Emmitt buys it.

## 2026-10-14 — V19 Two hotbars: your hands and build mode (Sprint 4)

Emmitt: "a build mode where the hotbar items are for building, then regular mode where the user can set items to their hotbar like weapons, meds, grenades... I keep wanting to hit 1 for a weapon but pull out a foundation." Built by Claude Opus 5.5 (Codex hit its weekly limit).

**Built:**
- **Two bars.** On foot the keys are your **hands bar**: 1 melee, 2 rifle (Primary), 3 pistol (Sidearm), 4 bandage, the rest yours to fill. A weapon key draws that weapon with the same raise and aim rules as Q (an empty slot says so); an item key eats, drinks or bandages. In build mode the keys are the **build bar** (foundation, wall, door, crate, smelter, belt, press, generator, bed); "BUILD" shows in front of it and the bar switches back when you stop building.
- **Things go to the right bar by themselves.** A building piece can only be on the build bar and everything else only on the hands bar, so assigning never asks which: the build menu's number keys fill the build bar; the inventory's number keys (or dragging onto a key) fill the hands bar. A weapon picked in the inventory puts its slot on the key, so the key draws whatever is in that slot.
- **The HUD** shows the bar you're using: weapon icons with the one in your hands in gold, item icons with counts.
- **Saves:** VERSION 18. An old single bar splits itself: pieces keep their keys on the build bar, food and bandages move to the hands bar after the three weapon keys (keeping their key when free). `test/fixtures/save_v17.json` was written by the V18 code.

**Try it on the PC:** press 1, 2, 3 on foot; open the build menu (B) and pick a piece, then 1-9 build.

**Tests:** 11,722 green (test_hotbar and test_build_menu rewritten for two bars; the v17 split).

**Known gaps:** no grenades yet (the bar takes new kinds by prefix when they exist); right-click-to-clear on the HUD isn't there (drag a new thing onto the key, or the inventory).

## 2026-10-14 — V18 Loot window: hotkeys and drag and drop (Sprint 4)

Emmitt: "make looting open the containers so you can choose what to loot with hotkeys and click and drag function." Built by Codex (one job on his ChatGPT plan); fixes, the merge with V17 and checks by Claude Opus 5.5.

**Built:**
- **Searching opens the container.** E on a fridge, cabinet, shelf, crate, car trunk or corpse searches it as before; when the search ends the inventory opens with that container on the right ("Fridge", "Corpse", "Trunk"), the mouse freed and the game still running. Already-searched containers open at once. Walking out of reach or getting hurt closes it with a message. Built storage crates now open the same way (they used to take your materials automatically).
- **Hotkeys:** E or double-click moves the picked stack between the container and your pockets; **R takes everything that fits** and says what didn't; Ctrl-click moves one, Shift-click the stack; 1-9/0 put the picked item on the hotbar; Tab/Esc close. Shown on the screen and in Help.
- **Drag and drop:** container <-> pockets, pockets -> a character slot (equips if it fits), slot -> pockets (unequips), pocket item -> a hotbar key; a picture of the item follows the mouse; a bad drop snaps back with "Too heavy" or "Doesn't fit that slot". Ctrl-drag moves one.
- **Saves:** VERSION 17: searched containers keep what's left in them (including gear). This branch also contains V17 window climbing (save 16 = window glass).
- Fix found on the way: putting on gear you carry was refused as "Too heavy" when you were already over the limit, though wearing it makes you lighter.

**Try it on the PC:** search any fridge or cabinet in a house; `play.bat --loot` opens a searched fridge.

**Tests:** 11,671 green (new `test_loot_screen.gd`).

**Known gaps:** no grid/Tetris inventory (items are tiles, not shapes); no item tooltips on hover yet.

## 2026-10-14 — V17 Climbing through windows (Sprint 4)

Emmitt: "we need to add a vault mechanic for windows because you can just run through broken windows." Built by Codex (one job on his ChatGPT plan); test fixes, checks and screenshots by Claude Opus 5.5.

**Built:**
- **Windows always block.** Intact or broken, a window stops you and zombies (collision and the navmesh: zombies path around instead of through).
- **Climb through a broken window (Space).** Looking at one within 2.2 m: "Space: climb through". A scripted 0.9 s move over the sill (3% faster per Fitness level), 14 stamina, a little noise (30). Not while aiming, reloading, swinging, blocking or over-encumbered.
- **Glass.** A broken window keeps its shards until you clear them (E, 1.5 s, faster with a melee weapon in hand, a glass noise). Climbing over shards cuts you: 5 damage and bleeding, like Zomboid.
- **Zombies climb too**, slowly (2.5 s), leaning over the sill and unable to attack until through, so a window is a choke point you can defend.
- **Saves:** VERSION 16; broken windows from older saves load with shards (`test/fixtures/save_v15.json`).

**Try it on the PC:** `play.bat --inside=0 --break-windows`, walk at a window (you can't pass), press E to clear the glass, then Space. Screenshot flag `--vault-at=T`.

**Tests:** 11,584 green (new `test_vault.gd`; its navmesh checks wait a few frames for the map to sync).

**Known gaps:** no vaulting over fences or barricades (they're 1.3-1.5 m, too tall for a vault). The climb is a camera move, no arm animation on the sill yet. Zombies use a code-driven lean while the new zombie models are being made.
## 2026-10-14 — Q5 Pre-playtest check (Sprint 4)

The check DIRECTION.md asks for before every playtest, on `main` at #55, by Claude Opus 5.5 in a cloud session.

**Found and fixed:**
- **Sleeping while bleeding woke you at once, with no reason given** (the bleed damage each tick wakes you). The bed now says "You're bleeding. Bandage first (H)". Test in `test_needs.gd`.
- **Long messages ran under the clock and the pockets** (tour tile 06: "Smelter placed. It needs power: ..."). Messages are now a centred column between the top-left and top-right blocks that wraps. `test_hud_layout.gd` checks the longest real message at 1600x900 and 1280x720.
- **Bleeding stops on its own (Emmitt's call).** A cut bleeds for 40 seconds (`bleed_time` in `data/survival.json`), about 20 health, then "The bleeding stopped". A new cut restarts the 40 seconds; a bandage still stops it at once and heals. Before, it bled until you died (full health to dead in about 3.5 minutes) and you start with one bandage. The time left isn't saved: a save loaded while bleeding gets a fresh 40 s. Test in `test_needs.gd`.
- **Soak bot:** it now bandages when it bleeds (H, as the HUD says), and counts the bleeds it had no bandage for; on day 2 it rebuilds a machine a zombie wrecked before the dusk wave check (that made the soak fail: a chasing zombie broke the smelter on day 1, so no machine was running for the wave to home in on).

**Found, not changed (for Playtest #2 to judge):**
- **A soak game-day now takes about 177 s instead of 87 s**, and memory starts at about 260 MB instead of 115 MB (S5's Jolt Physics and W2's breakable glass and doors are the likely causes). One 94 ms physics spike on day 1. Fine in play so far; worth a look before the world grows.
- **Respawning into the zombies that killed you.** On day 3 the bot died at house 1 three times in about 30 game-minutes: it wakes at its bed with the zombies that killed it still in the room. Worth a short grace period or a safer respawn if Playtest #2 hits it.
- **The hands sit low on the melee weapons:** with the axe or pipe the gripping hand is mostly below the screen and the left hand doesn't show. Judge on the PC (Forward+), not from cloud shots.

**Result:** `tools/soak.sh --days=3` reports SOAK OK (189 s per game-day; 5 deaths: 4 shambler on day 3, the bot's planned death and three at its bed after respawning, and 1 dehydration on day 4; **no bleeding deaths**: it bandaged twice and bled out of bandages twice and lived). Before the bleeding change the same run had a bleeding death on day 1. `tools/test.sh`: 9215 passed. Tour checked.

**Try it on the PC:** `play.bat`, get hit until "BLEEDING (H)" shows, then press E on a bed; then wait about 40 seconds for "The bleeding stopped". `play.bat --demo-factory` for the message column.

**Next:** Playtest #2 (V8).

## 2026-10-14 — V16 MakeHuman arms, reload sounds, rifle sights (Sprint 4)

Emmitt: "merge the branches then work on the human model generator and the rest of the things still not right". #57 and #58 merged. MakeHuman installed with his OK; arms and sounds by Codex (four jobs on his ChatGPT plan), testing, picks and fixes by Claude Opus 5.5.

**Built:**
- **Arms from a real human.** MakeHuman's Blender add-on (MPFB 2.0.18, installed into Blender 5.1 from extensions.blender.org; exported models are CC0, listed in `assets/CREDITS.md`) makes an anatomically correct adult; `tools/art/fp_arm_mpfb.py` cuts out each forearm and hand, keeps MakeHuman's finger weights, adds the leather glove, a skin band and the canvas sleeve, and maps its game-engine skeleton onto our 17 bones and six poses, so no game code changed. Real fingers now wrap the pistol grip and the fist reads as a gloved fist. `fp_arm_rig.py` (the procedural arms) is superseded. A second Codex pass (fist and sleeve fixes) passed its own checks but slid the hands off the grips in the game, so it was reverted (kept in history, commit 5d564d9).
- **Reload and inspect sounds** (`tools/audio/synth.py`): mag_out, mag_in, slide_rack, bolt_open, round_in (x3), bolt_close, timed to the reload animation (`Shooter.reload_sounds`, each once per reload, none after a cancel); gun_handle / blade_handle when you inspect. The generic reload sound is now only for guns without a choreography. No change to the sim's reload noise.
- **Rifle iron sights:** the rifle sits further out and the camera skips the first 0.34 m while it's aimed, so the stock under your cheek no longer fills the bottom of the view (`Shooter.ADS_NEAR`).
- The sleeve is drawn on both sides, so when a pose turns its open end toward you it shows cloth, not a hole.

**Try it on the PC:** `play.bat --gun` then R (listen for the magazine and the slide) and V; `play.bat --gun=rifle` and hold right click; `play.bat --fists`.

**Tests:** 11,532 green (new: `test_reload_sounds.gd`).

**Known gaps:** in the fist the index finger sits a little forward of the others; during the pistol's slide rack the left sleeve's open end shows at the bottom of the view; the rifle's cut-off stock shows its inside if you look for it. Next for realism: zombies from MakeHuman bodies with motion-captured animation (CC0 sources), the bigger "zombies look basic" item.

## 2026-10-13 — V13 Rigged arms, reload and inspect + V15 Right click to aim or block (Sprint 4)

Emmitt: "more realistic hands, reload/inspect mechanics" and "use right click to defend or ADS/scope in". Arm rig and code by Codex (four jobs on his ChatGPT plan); testing, sight measurements and fixes by Claude Opus 5.5.

**Built:**
- **Rigged arms** (`tools/art/fp_arm_rig.py` -> `fp_arm_right.glb` / `fp_arm_left.glb`): a skeleton with a forearm, wrist and three joints per finger and thumb, skinned, with six hand poses (Grip, Open, Flat, HoldMag, Pinch, Fist). Same grip frame as V12's hands, so `Hands.make` prefers them and falls back to the V12 models. A second pass made the fingers continuous tubes instead of stacked capsules.
- **Reload you can see.** Pistol: the gun tilts, the old magazine drops away, the left hand goes to your belt, comes back holding a fresh one, seats it and racks the slide. Rifle: the left hand presses three cartridges into the action, then the bolt is worked. Keyed to the sim's reload time (`Shooter.reload_pose`), so Quick Hands speeds it up too. The left hand can leave its grip (`Hands.set_target`) and always returns exactly.
- **Inspect (V).** The gun or melee weapon comes closer and turns over, with a message: name, condition and rounds ("Pistol 100% · 8/8 rounds"). Attacking, reloading, swapping or aiming cancels it.
- **Aim down sights (right click, every gun).** The gun comes to the centre with its sights on the crosshair (heights measured from the exported models), the view narrows 15%, sway nearly stops, you walk at 70%, sprinting drops it. Aimed shots have half the spread (sim: `guns.json` `ads_spread`). With a scope: the old zoom, the gun gets out of the way and the crosshair is the reticle.
- **Block (right click with melee or fists).** A guard pose; a hit from the front (within 70 degrees) loses 70% (blunt, axe), 50% (blades) or 30% (fists), costs stamina and wears the weapon. Raise it within 0.25 s of the hit for a **parry**: no damage and the zombie staggers back. No stamina, no block. You can't attack while blocking and move at 60%.

**Try it on the PC:** `play.bat --gun` then R (reload), V (inspect), hold right click (aim); `play.bat --gun=rifle`; `play.bat --weapon=axe` and hold right click to block; `play.bat --fists`. Screenshot flags: `--reload-at=T`, `--inspect-at=T`, `--aim=irons`, `--block`.

**Tests:** 11,353 green (new: `test_reload_inspect.gd`, `test_aim_block.gd`).

**Known gaps:** the hands still don't look truly realistic (thin fingers, a puffy back of the glove); a procedural Blender script has hit its limit here, and the next step is a CC0 sculpted base (MakeHuman/MPFB, whose output is CC0) if Emmitt agrees. With the rifle's iron sights the stock fills the bottom of the view. The fingers don't animate within a reload beyond the pose changes. No new sounds for magazine and bolt (the existing reload sound plays).

**Next:** Playtest #2 (V8).
## 2026-10-13 — V14 Character slots and item pictures (Sprint 4)

Emmitt: "character slots available in our game for equipment and weapons. a lot of the items still need thumbnail images." Slots, character screen and pictures by Codex (two jobs on his ChatGPT plan); fixes, layout and checks by Claude Opus 5.5.

**Built:**
- **Ten slots instead of six.** Head, body, hands, **legs**, **feet**, **back**, light, plus **Melee**, **Primary** (rifles) and **Sidearm** (pistols); the single gun slot is split. Q cycles melee -> primary -> sidearm and skips empty slots (fists when there's no melee weapon). `Gear.gun()` is still "the gun in your hands", so the gun code didn't change.
- **New clothing:** work pants, cargo pants (a little extra carry), work boots, sneakers (quieter footsteps), with rarities, rolls and loot drops like the other clothing.
- **Bags go on your back.** Only the worn bag adds carrying capacity now (before, the best bag in your pockets counted). Double-click a bag to wear it.
- **Character screen.** The text list of worn gear is now a figure with a tile per slot: the item's picture, its rarity colour as the border and a condition bar; empty slots are dark tiles with their name. Double-click equips from your pockets and unequips from the figure. The backdrop is darker, so the world doesn't show through.
- **29 new item pictures** (Codex image generation, cut out by `tools/art/make_icon.py`): ammo, bolts, the repair kit, radio, wall panel, every melee weapon, all clothing, the pistol, the rifle and every gun part. Gear tiles in your pockets and crates now show the picture too (they were coloured letters).
- **Saves:** VERSION 15. A version-14 save moves its gun to Primary or Sidearm and wears your best bag; nothing is lost (`test/fixtures/save_v14.json`).

**Try it on the PC:** `play.bat --gear=yellow` (a rare piece in your pockets and the character screen open), or Tab in any game. `play.bat --gun` now puts the pistol in the Sidearm slot.

**Tests:** 9,288 green (`test_equipment_slots.gd` is new: slots, Q cycling, worn-bag capacity, new clothing, the v14 migration, every tile on the figure).

**Known gaps:** no drag and drop yet (double-click instead). The figure is drawn shapes, not a picture of your character. A second gun of the same kind can't be carried as a backup in the other gun slot (a pistol only fits Sidearm).

**Next:** V13 (rigged arms with reload and inspect) and V15 (right click to aim or block) are on the `v13-arms` branch.

## 2026-10-13 — V12 First-person hands (Sprint 4)

Emmitt: "work on the animations". Hand models by Codex (one job on his ChatGPT plan); attachment and fists by Claude Opus 5.5.

**Built:**
- **Hands on every weapon.** Gloved hands with a jacket sleeve (`tools/art/fp_hand_right.py`, `fp_hand_left.py`): the hand grips a handle along its own +Y through the origin and the forearm runs back toward +Z. `Hands.attach` makes them children of each weapon, so they follow every swing, kick and reload the weapon already does: the right hand on every grip, a left hand on the bat and axe handles and under the pistol and the rifle's fore-end (`Hands.MELEE`, `Hands.GUNS`).
- **Forearms leave the bottom of the screen.** Each hand is rolled about its handle (`Hands.best_roll`) so that, with the weapon in its resting pose, the forearm runs toward the bottom corner on its own side instead of up past the camera. The handle crosses the palm at a 25° slant (`WRIST_TILT`), like a real grip.
- **Bare fists.** With no weapon, two gloved fists hold a raised guard and the right one jabs (the "punch" style).
- Materials: gloves get the leather photo, sleeves the canvas cloth; skin is left plain (`Hands.LOOKS`). Placeholder boxes stand in when the models are missing (cloud sessions).
- `--fists` flag (start bare-handed). `test/test_hands.gd`: every weapon has its hands, forearms go down and toward their own side at rest, materials are mapped, fists show only bare-handed and the jab moves forward.

**Try it on the PC:** `play.bat --weapon=axe`, `play.bat --gun=rifle`, `play.bat --fists`.

**Known gaps:** the hands are rigid (no finger or wrist animation); the left hand doesn't let go during a reload; elbows and upper arms are never seen.

## 2026-10-13 — S5 Physics: grounded bodies, the stuck car, Jolt Physics

Built by Claude Opus 5.5 from Emmitt's notes on the #51 build: "when you walk over a slain zombie you push the dead bodies. Can you make them much more grounded... Is there any physics engine we could use? also I got in the car but was not able to drive."

**Found:** his log showed the pickup (car_1) going NaN right after he got in, and the guard from the earlier fix putting it back every tick, so it never moved. Dead bodies are kinematic bodies, which the engine treats as unpushable and infinitely heavy. They collided with you (so walking over one shoved it around) and with cars. A body pressed against a car is a likely source of the NaN: both of his NaN sessions came right after kills.

**Built:**
- **Bodies are grounded.** A body adds collision exceptions with you and with every car (cars are in the "cars" group), so neither pushes the other. Walking over one nudges it at a tenth of your speed while your feet are on it (`ZombieBody.nudge_for`, `NUDGE_RADIUS` 0.75 m, `NUDGE_SHARE` 0.1).
- **A NaN car gets fresh wheels.** `CarBody.recover_from_nan` also rebuilds every VehicleWheel3D with the same settings and tyre model (the old wheels kept the engine's NaN in their own state). If it goes NaN three times within a second, the car freezes for half a second to settle. The first time, the log gets a report of the tick before: position, speed, spin, engine, steering and what each wheel and the body were touching.
- **Jolt Physics.** `project.godot` now uses Godot 4.7's built-in Jolt engine (free; the engine behind Horizon Forbidden West) instead of Godot Physics. The full suite passes on both engines, and the one-day soak passed on Jolt (car driven 24.5 m, 10 kills, 0 NaN recoveries).
- `test/test_corpse_ground.gd` (nudge maths, exceptions with the player and car_0, walking over a body moves it under half a metre, fresh wheels after a NaN).

**Try it on the PC:** `play.bat`, kill a zombie and walk over it; get in the pickup and drive. If a car ever goes NaN again, `godot.log` has one line starting "Car car_N: its physics went NaN" with what it was touching.

**Known gaps:** bodies are still a single slab (no ragdoll). Jolt makes ragdolls practical later (PhysicalBoneSimulator3D on the zombie rig).
## 2026-10-13 — W2 Breakable windows and doors

Built by Claude Opus 5.5 from Emmitt's ask: "lets work on making things destructible like windows". Stacked on V11.

**Built:**
- **You can break things.** `SimWorld.player_hit_piece(key, damage, by)` with `piece_material`:
  - **Windows are glass:** one hit from anything (a punch, any weapon, a round) breaks one.
  - **Town doors and fences are wood:** `BREAK_FACTOR` sets how hard each weapon hits them (axe 2.2x, blunt 1x, blade 0.4x, fists 0.25x, a round 0.3x). Chopping wears your weapon like a hit on a zombie.
  - **Some things don't break:** brick house walls, floors, and everything you built yourself (no wrecking your own base with a missed swing).
  - Melee swings and gunshots both use it.
- **Breaking glass is loud** (`glass_break` 62, louder than a melee hit). The first window you break tells you everything nearby heard it. Zombies breaking a window now make the same glass sound at the window, instead of a generic thud. Wood knocks (`wood_hit` 38) and a door giving way (`wood_break` 50) are noise too.
- **How it looks and sounds:** a burst of glass shards both ways (`ImpactFx` "glass"), and jagged glass left in the frame (`BuildView.shard_ring`: thin triangles along the pane's edges, laid out from the piece key so a window always breaks the same way; loaded saves get the jagged edge without the burst). Wood splinters (`ImpactFx` "wood") when a door, barricade or fence is wrecked. New synth sounds: `glass_break` (crash and tinkling pieces), `wood_break` (crack, splinters, boards falling).
- `--break-windows[=R]` breaks every window within R m (default 12) at the start, for screenshots.
- `test/test_breakable.gd` (25 checks).

**Try it on the PC:** `play.bat --weapon=axe`, walk to a house, break a window, then chop the front door down. Listen for zombies coming.

**Known gaps:** street fences, cars and furniture aren't breakable yet. No sledgehammer for walls. Broken glass on the floor isn't a hazard.

## 2026-10-13 — V11 Attack animations (Sprint 4)

Emmitt: "Lets also work on the attack animations". Models by Codex (one job on his ChatGPT plan); swings and wiring by Claude Opus 5.5.

**Built:**
- **Real weapon models** for the pipe, bat, axe, machete and knife (`tools/art/<id>.py` on `melee_common.py`; grip at the origin, pointing up +Y, striking side toward -Z; 600 to 2,800 triangles each). Their materials (Weapon Metal, Wood, Grip, Edge) are textured with the gun and cloth photos (`Melee.WEAPON_LOOKS`, through `Shooter._gun_material`).
- **A swing per kind of weapon** (`weapons.json` "style", `Melee.STYLES`): the pipe's diagonal, the bat's wide side swing, the axe's overhead chop, the machete's quick slash, the knife's stab. Each is keyframes of wind-up, strike and recovery, smoothed between keys, and quicker with the weapon's skill (`swing_seconds()` follows `swing_cooldown()`).
- **Hits land at the strike.** Whether a swing hits is still decided at the click (rules and tests unchanged). The blood, the hit marker, the shake and the head crunch wait for the strike moment of the animation.
- `--weapon=pipe|bat|axe|machete|knife` and `--swing-at=T` flags, for screenshots of any weapon at any point in its swing.
- `test/test_melee_styles.gd`: every weapon has a style and a model, poses are finite and start and end at rest, weapon materials are mapped, Blades 5 makes the animation 20% quicker, the hit marker waits for the strike.

**Try it on the PC:** `play.bat --weapon=axe`, `play.bat --weapon=bat`, `play.bat --weapon=knife` and swing at a zombie.

**Known gaps:** no hands yet (V6 first-person arms is next for Codex). Fists show nothing when you punch.

## 2026-10-13 — V9 + V10 Weapons wear out, Zomboid weapon skills (Sprint 4)

Built by Claude Opus 5.5 from Emmitt's ask: "adding durability to items so we need to get a new weapon every so often. I want zomboid like skills where you level up your blunt, blades, axe, etc skills and do more damage/faster attacks."

**Built:**
- **Weapons wear at their own rate and break.** `weapons.json` gives each a `wear` per hit: pipe 0.008 (about 125 hits), axe 0.010, bat 0.012, machete 0.014, knife 0.02 (about 50). Dropping below `broken_below` warns you it'll break soon (its bonuses stop, as before). At 0 it snaps: it's gone from your hands, a loud crack (`weapon_break`, 55 loud, new synth sound), and you're back to fists. Repair kits from the Press still restore one. The HUD's weapon line shows the condition once it has some wear ("Weapon: Bat 60%", "... 20% worn out").
- **Blunt, Blades and Axe replace Melee.** Each weapon has a `class` (pipe and bat blunt; machete and the new knife blade; axe axe). A hit with it trains its skill. Each level gives +6% damage and swings 4% quicker with that kind of weapon (`<class>_damage`, `<class>_speed`; never quicker than half). `SimWorld.swing_cooldown()` and `weapon_skill()`. Strength and the Fighter perks still add to every weapon.
- **Maintenance:** 7% less wear per level. Every hit gives a little xp, a repair more.
- **The knife:** a fast, short blade (22 damage, 0.4 s, 2.5x on the head) that wears quickly. It's a gear base, so it turns up in loot like the others.
- **Save version 14:** a save from before gives its Melee xp to all three weapon skills (`test/fixtures/save_v13.json`, written by the pre-V10 code). Swing `style` per weapon is in `weapons.json` for V11.
- `test/test_weapon_skills.gd` (50 checks); `test_skills.gd` and `test_gear.gd` updated to the new skills and wear rates.

**Try it on the PC:** `play.bat`, fight with the pipe until it wears (watch the HUD line), K for the skills screen (Blunt, Blades, Axe, Maintenance), find a machete or a knife and feel the difference.

**Known gaps:** every weapon still looks and swings the same until V11 lands (Codex is making the models). No spears or long blades yet. Repairs still restore a weapon fully; Zomboid lowers the maximum each time, so tune after Playtest #2.

## 2026-10-13 — S3-1c Textured zombies, varied clothes and textured guns

Built by Codex from Emmitt's Playtest #1 request for better zombie and gun textures. No save change: each look is derived from the zombie id already in the save.

**Built:** `ZombieBody` now maps the authored Zombie Skin, Shirt, Jeans and Boots material names to the new albedo and normal pairs with object-space triplanar projection, so textures follow animated bodies. A deterministic id-based pick gives each zombie one of three shirt fabrics, one of six faded shirt colours and a slight ordinary-skin shift; runner, screamer and Old Pete colours, runner-dimmed clothes, wounds, eyes, hair, stains, hi-vis gear, body variants and animation handling remain. Identical looks share cached materials. `Shooter` maps Gun Metal, Gun Wood, Gun Polymer and Gun Rubber the same way at a 0.15 m repeat while keeping the GLB's metal/roughness/colour settings; rubber reuses the polymer grain because no separate rubber texture was supplied. All new texture imports generate mipmaps. `test_textured_looks.gd` audits all five zombie GLBs and both gun GLBs, the explicit untextured lists, deterministic shirt variety, texture files, normals and object-space settings.

**Try it on the PC:** `play.bat --time=12 --zombie=0,-3,1.2,-4,-1.2,-4.5 --cam=0,0,0,0,-5` for three daytime zombies; change to `--time=22 --flashlight` for night. `play.bat --gun --time=12 --zombie=1,-9` shows the pistol, and `play.bat --gun=rifle --time=12 --zombie=1,-9` the rifle.

**Known gaps:** the workbench screen is text-only, so it has no second 3-D gun preview to texture. Gun Rubber uses the polymer photo under its original near-black, rough tint. This sandbox could not run Godot: opening `user://logs/godot2026-10-13T19.43.58.log` failed and Godot 4.7 then crashed with signal 11. Per the task rule no user-directory workaround was attempted, so the full suite and the five requested Forward+ screenshots remain unverified on the PC.

**Next:** run `tools/test.sh`, take and inspect the five S3-1c shots in the brief one at a time, tune tile sizes/tints if needed, then mark S3-1c fully validated.

**Review by Claude Opus 5.5 (Codex couldn't run Godot from its sandbox, so nothing had been tested or seen):** rebased onto V7, then ran the tests and Forward+ screenshots. Two looks were wrong and are fixed:
- Zombie faces and shirts were nearly black: the model's colour was multiplied by a photo that is itself dark. `Surfaces.tint_for_texture` divides each photo's measured average brightness (`TEXTURE_MEAN`) back out, so a textured surface averages the look's own colour. The look's colour is kept on the material as `look_tint` meta, which `test_zombie_types_world.gd` now reads.
- The pistol was solid black: its model colour is near black and its steel fully metallic, which reflected a dim sky. Gun materials now take the photo's colour times a per-material `tint`, and gun steel is satin (metallic 0.5, roughness 0.5).

Full suite 8868 passed. Screenshots checked: three zombies by day (flannel, work shirt, a green shirt, denim, boots) and night, the pistol and the rifle.
## 2026-10-13 — V7 Hits and deaths (Sprint 4)

Built by Claude Opus 5.5, stacked on the car fix. The zombie rig already had hit-react and death animations; this pass makes hits and kills read.

**Built:**
- **Blood stains.** A hit on a zombie leaves a stain on the ground below it (bigger for the head), and a pool spreads under a body over four seconds and stays as long as the body does. `ImpactFx.stain` places Decals of a procedural splat (`tools/art/make_blood_splat.py`, free). They fade after three minutes, and at most 48 exist at once (the oldest go first). Decals need Forward+; cloud screenshots won't show them.
- **Bodies fall away from the blow.** The Death animation tips a zombie forward, so a dying zombie now turns to face the way it was knocked (away from you if nothing knocked it) and slides back a little as it drops, instead of falling onto you.
- **Headshots read.** A bigger blood burst (`blood_head`), a bigger stain, and a new `headshot` sound (a bone crack, a wet splat and a knock, from synth.py) for pipe and gun hits to the head.
- `test/test_hits_deaths.gd` (stain orientation, the cap, a pool spreading, a zombie hit from the east falling and sliding west with a pool under it).

**Try it on the PC:** `play.bat`, then hit zombies with the pipe (aim for the head) and shoot one with `play.bat --gun --zombie=0,-6`. Watch the body fall away and the pool spread.

**Known gaps:** no full ragdoll (bodies use the animation). No blood on walls behind a shot. Stains go through thin floors onto the ground below (rare).

**Next:** Emmitt's new asks: attack animations, weapons that wear out, and Zomboid weapon skills.

## 2026-10-13 — Fix: the game stalled after getting into a car

Built by Claude Opus 5.5, from Emmitt's report on the V3 build (1c6ffcd): "when I got into the car the game bugged out".

**What happened:** his log shows the car's physics state turned NaN inside the engine's vehicle maths right after he got in (a NaN rotation axis, no script on the stack). Every zombie touching the NaN car then failed its physics move each frame, and about 28,000 warnings with script backtraces in a minute stalled the game. Q1 and Q2 had seen the same kind of car NaN and never pinned it down.

**Couldn't reproduce headless, so it's contained instead:** `test_car_corpse.gd` (dead and live zombies under and around the car, then drive) and `test_car_save_drive.gd` (a copy of Emmitt's own save, every car with gas driven hard with steering) both stay finite. The fix makes a NaN unable to spread or stall the game, wherever it comes from:
- **The car checks itself every physics tick** (`CarBody.state_ok`). If anything went NaN, `recover_from_nan()` puts it back where it last was, stopped, in the node and the physics server, with one warning per car.
- **Zombies drop a NaN knock or step** before it reaches the physics engine (`ZombieBody.bad_moves` counts them), and a body lying down zeroes a NaN velocity.
- **The hidden walker no longer collides while you drive.** It used to stay at the car door, an invisible post the car could hit. `Player.MASK` is restored when you get out.
- `test_car_nan_guard.gd` checks all three.

**Try it:** `play.bat`, get into a car and drive through zombies and over bodies. If it ever happens again, the log (`%APPDATA%/Godot/app_userdata/Noise Floor/logs/godot.log`) will show one "Car car_N: its physics went NaN" line instead of a flood. Tell me and send that file.

## 2026-10-13 — V4 Sound (Sprint 4)

Built by Claude Opus 5.5 in a local session, stacked on V3. Nobody could listen to it while it was built (no speakers in the loop), so the numbers are checked by tests and the ear test is Emmitt's (V8).

**Built:**
- **Walls muffle what you hear.** Every world sound (machine hums, footsteps, hits, bashes, doors, gunshots, turret shots, screams) is turned down and dulled by the walls between your ears and it, counted with the same `NoiseField.walls_between` the zombies' hearing uses. So a generator behind a wall really sounds like it's behind a wall, and what you hear still matches what they hear. `SoundView.OCCLUSION`: one wall -7 dB and dull, two -12 dB, three or more -16 dB. Hums re-count four times a second.
- **Echo indoors.** World sounds play on a new World bus with a reverb that follows how far under a roof you are (main.gd's eased indoor value): a small, damped room inside, a faint slap off the houses outside.
- **Wind dulls indoors.** The wind plays on a new Ambience bus whose low-pass and volume follow the same value.
- **Background sound.** Now and then a far-off zombie moan or a metal clang plays 35 to 60 m away (every 12 to 30 s at night, 35 to 75 s by day), or a house creaks near you when you're inside. Atmosphere only: the zombies don't hear these.
- **Heavier hits and guns** (`tools/audio/synth.py`): the pipe hit has a deeper body thump and a crunch; open gunshots have a sub-bass thump and two dull echoes off the houses. New sounds: `creak`, `clang_far`. Re-made only those five with `--only`; the other sounds are unchanged.
- `test/test_sound_space.gd` (occlusion table, a real wall muffling a real smelter hum, indoor echo, buses made once, background scheduling).

**Try it on the PC:** `play.bat --demo-factory`, then walk behind a house wall and listen to the press, and into a house (echo, quieter wind). Stand outside at night for a minute for the background sounds. Fire a gun in the street and then inside a house.

**Known gaps:** sound bends round corners only as far as the wall count allows (an open doorway next to you counts as open). The indoor echo is the same for every room size. No music.

**Next:** V2 (Codex art) lands, then V5 art direction and V6 first-person arms in Codex, and V7 zombie hits and deaths.

## 2026-10-13 — V3 Game feel (Sprint 4)

Built by Claude Opus 5.5 in a local session, stacked on V1. Most of this is motion and timing, which still screenshots can't show, so the maths has checks (test_view_feel.gd) and Emmitt's hands decide the rest (V8).

**Built:**
- **`ViewFeel`** (new, `src/world/view_feel.gd`), one node that owns how the view moves and reacts:
  - **Head bob** with your steps: stronger sprinting, softer crouched, nothing in the air or standing still, easing in and out.
  - **The pipe and the guns** bob with your steps and lag the mouse (sway). Guns are steady while scoped.
  - **Screen shake** ("trauma", squared so small knocks stay small): a pistol shot, a bigger one for the rifle, a pipe hit on a zombie, a swing into a wall, and taking damage. It settles within about a second.
  - **The gun's kick** now goes through ViewFeel, so it adds to the shake instead of fighting it.
  - **A hit marker** at the crosshair: white for a body hit, yellow for the head, red for a kill.
  - **A dark red screen edge** when you take damage, which pulses while health is under 35 (`hurt_vignette.gdshader`). ViewFeel watches health itself, so every kind of damage counts.
- **`ImpactFx`** (new): blood droplets that fall where a pipe or a round hits a zombie, and a slow dust puff where a swing or a shot hits anything else. CPU particles, so they work in every renderer, and each frees itself.
- **Settings → "Head bob and camera shake"** (on by default). Off removes the bob, sway and shake for anyone who gets motion sick; the kick, the marker and the red edge stay.
- Melee and Shooter report hits to ViewFeel. Both still work without it, for the tests that build them alone.

**Try it on the PC:** `play.bat`, New game. Walk, then sprint, and watch the pipe. Hit a wall and a zombie with it. `play.bat --gun --zombie=0,-6` and shoot. Take a hit from a zombie. Settings → untick head bob to compare.

**Known gaps:** no blood on the ground or on walls yet (decals are V7, with hit reactions). The hit marker is easy to miss under the blood at close range. No landing dip after a jump.

**Next:** V4 sound, and V2's Codex art when its run finishes.

## 2026-10-13 — V1 Lighting and atmosphere (Sprint 4)

Built by Claude Opus 5.5 in a local session, the first task of Sprint 4 ("the first 30 minutes", see DIRECTION.md). Judged on Forward+ screenshots on Emmitt's GPU, before and after: 10:00, 20:30, 06:00, 23:00 on the street, 22:00 and 13:00 inside a house, the factory at 21:30, and the night street on each quality preset.

**Built:**
- **Dusk and dawn glow.** The sky, ambient light and fog used to follow `daylight()` (the sine of the sun's arc), so at 20:30 the town was already black. `Atmosphere.sky_light(elevation)` keeps a glow through twilight, the low sun stays strong (`sun_strength`) and turns orange (`sun_color`), the sky's colours follow the sun (blue by day, a golden horizon at sunset, near black at night) and the fog warms at dusk. Night itself is as dark as before.
- **A real flashlight beam.** Energy 8 to 5 (it whited out anything within two metres), a wider cone, and a projected beam pattern from `tools/art/make_flashlight_cookie.py`: hot spot, reflector ring, dim spill, lens smudges. The beam shows in the night fog.
- **Colour and tone.** AgX tone mapping (bright lamps and the flashlight roll off instead of clipping), a slightly drained, slightly contrasty grade for a dead town, ambient occlusion and screen-space bounce light, softer sun shadows, glow only on things brighter than white.
- **Graphics quality** in Settings: Low (plain fog, no ambient occlusion: for weak PCs), Medium (adds ambient occlusion and the volumetric fog), High (default: adds bounce light, soft shadows, a finer fog grid). `--graphics=low|medium|high` sets it for one run, for screenshots. `Atmosphere.PRESETS` is the table.
- `test/test_atmosphere.gd` (65 checks); `test_indoor_fog.gd` now expects the new twilight formula.

**Tried and dropped:** SDFGI (engine-wide bounce light). It shut the sky's light out of houses and left them black at noon, which matters in a game about searching houses.

**Try it on the PC:** merge, then `play.bat`, New game. Wait for 20:30 (12 minutes in) and look west down the street, then turn the flashlight on (F) at night and inside a house. Settings → Graphics quality to compare. On High it held 240 fps (the monitor's cap) at night on the 5070 Ti.

**Known gaps:** Low's flashlight is dim (no fog to show the beam). Interiors by day are lit by the sky's ambient light, not real light through the windows. The title screen keeps its own dusk look. No rain or wet roads yet.

**Next:** V2 (textured zombies and guns, running in Codex), then V3 game feel and V4 sound.

## 2026-10-13 — S4 Playtest #1, second pass: pictures, a first-factory walkthrough, lootable zombies, jumpscares

Built by Claude Fable 5.1 in the same local session as S3, from the rest of Emmitt's Playtest #1 notes: "give the hotbar pictures", "zombies look great but I want them to be lootable like in Zomboid", "jumpscare sounds when a zombie surprises you around a corner or a large mob gets aggroed like in Zomboid", and "I was also not able to figure out the building and machines". Stacked on S3 (branch `s3-playtest-fixes`); no save change (corpses are not saved: VERSION stays 13).

**Built:**
- **Pictures on the hotbar and in the build menu.** `tools/art/piece_icons.gd` renders every piece the way the game draws it (its model, or its box) from a three-quarter angle on a transparent background to `assets/icons/piece_<id>.png`; the hotbar and the build menu show them. Re-run it after a model or BuildView change (it needs a window: the PC, or Xvfb in the cloud).
- **Building and machines explained where you need it.** The first-game hints now walk through a whole first factory, each step waiting until you have done it: the crate, a foundation, a smelter from the build menu, *a generator and a power pole beside it*, *gas cans into the generator*, *scrap into the smelter*, then noise and walls. The build menu has a line under each group saying how its pieces work ("Machines stand on a foundation and most need power. E on a machine loads it and takes what it made"). Placing a machine with no power says so at once on the HUD ("Smelter placed. It needs power: a generator (E loads gas cans) or a solar panel, and a power pole within 12 m"). The controls screen (F1) has "Your first factory" in six steps under the keys.
- **Lootable zombies.** A dead zombie lies where it fell for four game-hours as a searchable body: look at it and press E, like a cabinet. It gives from a small "zombie" table (scrap, nails, a bandage, chips, soda, a few rounds; often nothing) plus whatever that zombie carried, which used to drop as a bag: the odd gear piece, and Old Pete's axe, rifle and rounds. A searched body is cleared after thirty seconds. The first kill tells you bodies can be searched; a zombie carrying something gold says so. Clothes that make each zombie unique are the next step on this (not built).
- **Jumpscare stings.** Two short synthesised stings (`tools/audio/synth.py`): one when a zombie you had not seen is suddenly in front of you within 6 m (behind a door you open, round a corner), and a heavier one when four or more zombies start chasing you within three seconds. A zombie you watched walk up never stings; one that goes out of sight for three seconds can again; 8 s and 45 s cooldowns.

**Rules (sim, tested):** `Scares` (new, `src/sim/scares.gd`): `tick(dt, zombies, player_pos, player_facing, player_dead)`, `fired`, `count(kind)`; in view = within 55° of where you look, line of sight clear (`ZombieBrain.los_clear`, set by the body), within 30 m. `SimWorld.player_facing` (main sets it from the camera), `SimWorld.scares`, `SimWorld.CORPSE` ("corpse_<id>"): `_count_kills` registers each new corpse as a loot container at the body (`_add_corpse`), `_zombie_drop(z, cid)` puts what it carried into the container (`Loot.add_gear`, `Loot.add_extra`) instead of `drop_bag`, a search hands over `found["gear"]`, and a cleared corpse takes its container with it (`Loot.remove`, abandoning a search of it). `ZombieBrain.CORPSE_TIME` 15 → 240 s, `SEARCHED_CORPSE_TIME` 30 s, `searched`; `Horde.tick` clears by whichever applies. `data/loot.json` `zombie`. `SimWorld._on_piece_built`: the no-power message. World: `ZombieBody` (a dead body swaps its capsule for a low slab on the BAG layer with meta `container_id`, so only the look ray sees it), `SoundView._play_new_scares` (`STINGS`, not positional), `Hints.STEPS` (eight, with `_powered_machine`, `_fuelled_generator`, `_machine_fed`), `HelpScreen.GUIDE` + `guide_text()`, `BuildMenu.GROUP_NOTES` + button icons, `HotbarView` piece icons, `tools/art/piece_icons.gd`, `synth.py` `sting_close`, `sting_horde`.

**Tests:** `test_corpses.gd` (new): a dead zombie is a "Dead zombie" container at its spot and no bag; searching gives its loot once and marks it; a searched corpse clears after 30 s with its container; forty corpses give a few different things from the table and some nothing; about a fifth of runners carry a piece; an unsearched corpse outlasts 30 s; a corpse cleared mid-search drops the search; in the real scene the body on the ground is on the bag layer, the look ray finds it, the prompt says "Dead zombie [E] search" and E starts the search. `test_scares.gd` (new): a zombie 4 m ahead behind a door stings the moment the line of sight clears, once; behind you, 20 m away, walking up in view, dead, or while you're dead: never; out of sight for a second and back: no; for the cooldown and back: again; three chasing is no mob, four within three seconds is, a fifth right after isn't, the cooldown; SimWorld feeds it and SoundView plays each sting once; both WAVs exist. `test_hints.gd` follows the eight steps (power, gas, scrap). `test_gear.gd` and `test_guns.gd`: Old Pete's axe, rifle and rounds are on his body and come with a search; drop rates measured on corpses. `test_build_menu.gd`: every piece has a picture and every group a note. `test_help_screen.gd`: the six guide steps are on screen. **8574 checks** (was 8357).

**Try it on the PC:** merge, `play.bat`, New game, and follow the green tips: they now take you through power and loading. Kill a zombie, look down at it, E. Open a house door with a zombie behind it. `play.bat --help --time=12` shows the guide; `play.bat --build-menu --time=12` the pictures.

**Known gaps:** corpses are not saved (a loaded game has none lying about). Zombies still wear the same few flat colours (clothes for unique zombies, and better skin and gun textures, are a Codex art job: next). No setting to turn the stings off yet. A zombie standing right behind a door stings every time you open it after three seconds away, which may be too often; tune from Playtest #2. Four hotbar pieces (hopper, workbench, sensors) are plain boxes because they have no model.

**Next:** Playtest #2 on the merged build; the zombie and gun texture pass with Codex.

## 2026-10-13 — S3 Playtest #1 fixes: driving, doors, a hotbar and a build menu

Built by Claude Fable 5.1 in one local session from Emmitt's Playtest #1 notes (docs/PLAYTESTS.md, 2026-10-13): "the driving feature does not work", "we are not able to close doors after opening and you can clip through the door after open", and "I would like to have a hotbar for items like Satisfactory and a build menu. You should be able to assign anything to the hotbar keys from the build menu and usable items." Save VERSION 13.

**Built:**
- **Driving works.** Pressing E at a car got you in and, with the same key press, straight back out: the Interactor (a child node) entered the car, then main.gd (its parent, which gets the event next) read "E while driving" as get out. Eight presses left eight copies of the driving-keys message down the screen (his screenshot). The Interactor now marks that E as handled when it gets you into a car. Nothing else about driving changed. B and the hotbar keys do nothing from the driver's seat.
- **Doors close again, and you can't walk through an open one.** An open door used to be put on no collision layer at all: the look ray never found it again (so no "[E] close"), and the swung panel was a picture you walked through. An open door is now a solid piece in its swung pose beside the doorway; you close it by looking at the panel from either side. It **swings away from whoever opens it** (a new "swing" on the piece, saved), so it never shoves you, and it **won't shut on anyone standing in the doorway** ("Something's in the way of the door"). Zombies still come through the open doorway (the navmesh rebake routes them round the panel).
- **A hotbar**, Satisfactory-style: ten slots along the bottom of the HUD under 1-9 and 0. A slot holds a piece to build or an item to use (food, drink, bandages). On foot, a piece's key starts building it (the same key again stops), an item's key uses it, an empty key says how to fill it. The HUD shows each slot's name or picture, the count you carry, grey when you can't afford or don't have it, and a gold edge on the piece you're building. A new game starts with foundation, wall, door, crate, smelter, belt, press, generator, bed and bandage on 1-0. Saved with the game; older saves get that default.
- **A build menu on B:** every piece you can build, in four groups (Base, Factory, Power, Defense) with its cost, greyed when your pockets and the crates near you can't pay; point at one for its numbers (loudness, watts, range, hp), a plain line about it, and which key it's on. **Click a piece to start building it** (the ghost, R, LMB and RMB as before); **press 1-9 or 0 with a piece pointed at to put it on that key.** In your pockets (Tab), click a food, drink or bandage and press a number to put it on that key. **Esc stops building** (Esc again pauses); B while building reopens the menu; the mouse wheel still steps through every piece.
- The first-game hint, the help screen (F1) and the bottom key-hint line say all this. `tools/test.sh hotbar` runs just the test files whose name contains "hotbar".

**Rules (sim, tested):** `Hotbar` (new, `src/sim/hotbar.gd`): `SLOTS`, `DEFAULT`, `assign(i, "build:<piece>" | "item:<item>")` (pieces must be player-placeable, items usable: food, water or bandage; a thing is on one key only), `clear`, `entry/kind/id/label/find`, `key_name`, `to_array/load_array` (an empty list = the defaults). `SimWorld.hotbar`. `BuildGrid.toggle_door(key, from)` stores `"swing"` (1 = toward the door's own -Z side, -1 = +Z) via `swing_away_from(key, from)`; `door_pose(key)` gives the closed or open transform (hinged at the panel's -X end). `SimWorld.toggle_door(key, from)`. **Saves:** `SaveGame.VERSION` is 13: `hotbar` and each piece's `swing`. `test/fixtures/save_v12.json` was written by the pre-S3 code (the seed-1 town and park, a foundation with a door and a crate on it, day 5 09:00) and loads with the default hotbar; every older fixture still loads. World: `HotbarView` (new, `src/world/hotbar_view.gd`, HUD, never takes the mouse), `BuildMenu` (new, `src/world/build_menu.gd`: `GROUPS`, `BLURBS`, `pick`, `highlight`, `assign_slot`, `details_text`), `BuildController.select_id` (B and the number keys left it; `PIECES` is the wheel order), `InputSetup` (`hotbar_1..10` replace `build_pick_*`; `hotbar_slot(event)`), `Interactor` (the handled E; `door_blocked`), `BuildView._on_changed` (door pose, always on the BUILT layer), `InventoryScreen.assign_hotbar` + `icon_for`, `main.gd` (`_open_build_menu`, `_hotbar_press`, Esc order, `HOTBAR_BOTTOM`, `--build-menu`, `--build=` by id), `HelpScreen.ROWS`, `Hints`.

**Tests:** `test_hotbar.gd` (new): defaults, every refusal (planks, town pieces, unknown ids, nonsense, no slot 11), moving a thing between keys, save and load including the version-12 fixture, and door swings (from the south it swings north, from the north south, closing keeps the swing, no opener keeps the last one, SimWorld passes the opener's place, the swing survives a save). `test_doors_world.gd` (new, the real scene): opened from the lawn, a house door swings into the house and stays solid; you walk through the doorway but not the panel; looking at the panel offers to close it; it won't shut on you in the doorway; from inside it closes and blocks again; opened from inside it swings out. Checked adversarially: with open doors put back on no layer, 12 of its checks fail. `test_driving_input.gd` (new): a real E key through the viewport gets you in, you stay in over ten physics frames with the engine running, the driving keys show once, E again gets you out (fails on the old code). `test_build_menu.gd` (new): every piece is in one group with a blurb and no town piece is; B opens and closes the menu, Esc closes it without pausing, 5 in it puts the smelter on key 5, a click starts building that piece, Esc stops building and Esc again pauses; on foot 1 builds, 2 switches, 2 again stops, 3 eats the canned food on it, an empty key explains itself; the HUD rows; nothing from a car; Tab + 4 puts food on key 4 and planks are refused. `test_hud_layout.gd`: the hotbar keeps clear of the health line, key hints and look-at text at 1600x900 and 1280x720, and the first-game hints sit above it. `test_main_input.gd` and `test_help_screen.gd` follow the new keys. **8357 checks** (was 7986).

**Try it on the PC:** merge, then `play.bat`, New game. Walk up the street to the red sedan: E at its back searches the trunk (the key), E at its side gets you in, W drives, E gets out. Any house: E on the door, walk in, turn round, E on the open door closes it; stand in the doorway and try to close it: it won't. Press **1** and click the ground: a foundation. Press **B**: the build menu; point at the smelter and press **5**: it's on key 5; click it to build one. **Esc** stops building. **Tab**, click the bandage, press **0** (it's there already by default; try canned food on **9**). `play.bat --build-menu --time=12` opens the menu straight away for a look.

**Known gaps:** no pictures for pieces on the hotbar (names only; items have their icons). The hotbar can't be clicked or dragged, only keyed. A zombie standing where the door would swing is "in the way" too, so a door won't open onto one (fine; it was never going to end well). The town's furniture and the number keys inside other screens (skills, workbench) do nothing. The old driving message still shows every time you get in (once now, for six seconds).

**Next:** Playtest #2 on the merged build, then Sprint 3 tuning from it (docs/SPRINT.md).

## 2026-10-13 — Fix-up before Playtest #1: healing, cars stuck in zombies, the soak drives

Built by Opus 5.5 from a PR review Emmitt asked for (no lead brief). Small pre-playtest fixes; no save change (healing adds no saved state).

**Built:**
- **Natural healing.** Health used to never come back except from bandages. Now it slowly returns while food and water are both at least 30, you aren't bleeding and you aren't cold: 0.08 a second awake (about 5 an in-game hour), 0.25 a second asleep in a bed (a full night's sleep heals you completely). First Aid makes it 10% faster per level. The HUD shows "Health 60 (healing)" while it's happening. Numbers are in `data/survival.json` (`heal_rate`, `heal_sleep_rate`, `heal_min`) for tuning after the playtest.
- **Cars no longer get pinned by zombies.** Zombies are solid bodies a car can't move, so three standing against the bumper held a running car in place for good (found by the soak: "moved 0.1 m" with the engine on). While you're on the gas, a zombie touching the car is now nudged sideways off it (no damage; ramming at speed still hurts as before), so a car creeps out through a crowd (about 5 m in 3 seconds through three).
- **The soak bot really drives.** If it has no gas can left (the generator burned the one it siphoned) it is handed one; the drive line now says whether the engine was on, the fuel and car hp. `tools/soak.sh` and `tools/tour.sh` are executable again.

**Rules (sim, tested):** `PlayerStats.heal_mult` (set by SimWorld from the First Aid `heal_rate` effect) and `is_healing()`; healing runs in `tick()` only on a tick where nothing hurt you. `CarBody._shove_zombies()` (world): every 0.2 s while the throttle is held, each zombie in contact gets a 7 m/s sideways push through `ZombieBrain.knockback`.

**Tests:** `test_healing.gd` (new, 16 checks): awake and asleep rates, capped at max health, no healing when hungry, thirsty, bleeding, cold or dead, First Aid 5 heals 50% faster. `test_car_shove.gd` (new): the real game scene, three zombies at the bumper, the car moves more than 1.5 m in 3 s (0.1 m without the fix). 7986 checks green. Soak, one day: `SOAK OK`, drive step "engine on (fuel 1.0, hp 300); moved 4.7 m".

**Try it on the PC:** merge, then `play.bat --hurt=40 --time=12`: you start at 60 health and the HUD says "(healing)"; it creeps up. Sleep in a bed to heal fast. Drive a car into a few zombies slowly: it pushes through.

**Known gaps:** healing rates are guesses until Playtest #1. Early water is still tight (the soak bot dies of thirst on long runs) and infamy still climbs fast (about 200 after day 1); both are for the playtest to judge, not changed here.

**Next:** Playtest #1 with Emmitt (see `docs/DIRECTION.md`).

## 2026-10-13 — Q4 Rule fixes from the winter soak

From the Q4 brief by the project lead, on top of Q3 (PR #39). Three rule changes the lead decided after the Q3 soak (its Known gaps 1, 2, 3 and 6), each with a test. No balance tuning beyond what each fix needs.

**Built:**
- **Old Pete stays in the hall.** He is now a *guardian*: when the town plan places him it gives him the factory hall as his home area, and he never leaves it. He stands on his spot between the crates; he only goes to look at sounds made inside the hall (the starter factory's noise, a wave's lure or anything else outside no longer draws him); he only sees and chases you while you are inside the hall, gives up the moment you step out of a doorway, and walks back to his spot. Shooting him from outside doesn't bring him out either. His fire axe, his hit points and his damage are unchanged. Every other zombie behaves as before.
- **Zombies never wreck furniture, beds or stoves.** What a zombie may break is now one list: walls (town walls and the electric fence too), doors, windows, barricades, machines, generators, turrets, sensors, noisemakers and floodlights. Everything else (the house furniture, beds, storage crates, stoves, heaters, workbenches, power poles, the water tap, hoppers, the repair station, solar panels, belts and traps) is walked around, never broken: a chasing or investigating zombie that walks into one keeps going and its path goes round it. A lit stove's crackle still draws zombies to look, but they no longer wreck it when they get there.
- **A roof slows the cold; only heat warms you.** Under a roof with no heat source in reach, warmth now drains at a third of the outdoor rate for that season and time of day (a winter night indoors: about 6.7 an hour instead of 20; a winter day 4; autumn nights 1.7; summer nothing). Asleep in a bed indoors the drain halves again (3.3 an hour on a winter night). Within reach of a lit stove or a powered heater it rises by 60 an hour, indoors or out, as before. Outdoor rates are unchanged, and asleep outdoors it still never falls. It used to rise 20 an hour under any roof in any season, so a stove was pointless in a house. The freezing message now says "get to a fire or a heater".

**Rules (sim, tested):** `ZombieBrain`: `guard_area` (a Rect2 in metres, empty for ordinary zombies), `guard_spot`, `is_guardian()`, `set_guard()`, `in_guard()`; `hear()` and `hear_via()` ignore sounds from outside the area; `think()` takes no notice of a player outside it and, if it was chasing, attacking or breaking its way toward one, `_go_back()`s (WANDER to its spot, then IDLE there); an idle guardian away from its spot walks back; its home never moves; any wander target is clamped into the area. `TownPlan.factory()["pete"]["guard"]` = `factory_rect()`; `SimWorld.spawn_old_pete()` calls `set_guard`. `SaveGame`: a guardian's zombie entry carries `"guard": {"area": [x, z, w, d], "spot": [...]}`; an Old Pete from a save without it becomes a guardian of the hall on load (no version bump: the field is optional). `Horde.BREAKABLE_KINDS` (wall, door, window, barricade, fence, machine, generator, turret, sensor, noisemaker, floodlight) and `NEVER_BREAK_IDS` (water_tap, a "machine" by kind), `Horde.breakable(pieces, key)`; a bumped or targeted piece that isn't breakable is left (`leave_furniture()`, as M16 did for props), and a sound heard from a piece that isn't breakable is investigated without the "wreck the machine" step. `data/seasons.json` warmth: `indoor_gain` is gone; `indoor_cold` 0.3333 and `asleep_indoor_cold` 0.5 are new (checked to be in 0..1 by `GameData`); `Climate.warmth_rate()` applies them.

**Tests:** `test_old_pete_guard.gd` (new): the town plan makes Old Pete a guardian of the hall's footprint, standing on his spot, 200 hp; with a smelter running 14 m outside the doorway (loud enough to hear at his spot; an ordinary zombie beside him goes to it), over a whole game-day (bodies walked straight at their targets) Old Pete never steps or heads out of the hall, never investigates or breaks, and ends idle on his spot; a sound inside the hall draws him, one outside (and a wave's lure) doesn't; a player in plain sight 8 m outside the doorway is ignored, one who walks in is chased and attacked, and when they walk out he gives up while still inside at the doorway, heads for his spot and is back on it, idle, never having stepped out; shot from outside, he doesn't chase; the guard survives a save and load, and a save without the field gives Old Pete (and only him) the guard. `test_zombie_brain.gd`: the breakable list (13 kinds and pieces yes, 15 no); a chaser walking into a town bed for 15 s keeps chasing and never starts breaking it, the bed keeps every hit point, while one blocked by a town wall breaks it; a zombie beside a lit stove investigating a sound past it never starts breaking it, one sent to the stove's own crackle doesn't stay on it, and the stove keeps every hit point and keeps burning. `test_seasons.gd`: M16's "+20 a game-hour indoors" test is replaced: a winter night indoors without heat drains 20/3 in a game-hour, a winter day 4, asleep indoors half that again, an autumn night 5/3, summer indoors stays exactly flat; indoors an unlit stove does nothing and a lit one gives +60 a game-hour. **7968 checks** (was 7878).

**Soak (this PC, `tools/soak.sh --days=7 --start-day=12`, one run):** `SOAK FAILED: park zombie 14 (shambler, wander) left the park undrawn, at (-2.7, 0.1, -137.2), day 15 15:00 (NaN moves undone 0; 7 game-day(s) in 322 s wall (98 s per game-day); deaths 13, kills 31, waves 5, swings 83, gear 6, pieces 1133, bag taken)`. The soak stops at its first failed invariant, so this run played day 12 08:00 to day 15 15:00 (3 days 7 hours, 15 hours of winter), not the full week; see Known gaps for the failure. In that time: deaths 13 (day 12: 3, bleeding x2 and a shambler, all outdoors; day 13: 1 shambler; day 14: 6, bleeding x3 and shamblers x3; day 15 to 15:00: 3, dehydration, Old Pete, bleeding). **Cold deaths: 0** (warmth low 59, no cold trips; at 15:00 on the first winter day warmth was 94 with the stove lit and 8 planks in it). **Old Pete kills: 1**, on day 15 at 12:10 during the park trip, which walks through his hall (Q3: two every run on the first evening, at the base and in house 1's bed; none now). **Beds lost: 0, stoves lost: 0, furniture lost: 0.** The pieces that did go (the first eight, which is all the soak prints): four town walls and a town door by house zombies investigating the base's noise (zombie 9 twice and zombie 10 twice on day 12 evening, zombie 11 on day 14), one town wall by a chaser on day 14, and the player's smelter by a chaser on day 12 at 20:36. Wall time 98 s per game-day (Q3: 86-100 s).

**Soak re-run (after a fix to the soak's own bookkeeping, `test/stress/soak.gd` only):** at the save the soak now notes every live zombie's spot and whether it is a park zombie and has been drawn; after the load each zombie is matched to the one saved at its spot (within 0.5 m) and keeps that: a drawn park zombie stays drawn, a zombie that wasn't a park zombie isn't made one, and only one that matches nothing falls back to "standing in the park". Result: `SOAK OK: NaN moves undone 0; 7 game-day(s) in 612 s wall (87 s per game-day); deaths 13, kills 33, waves 5, swings 80, gear 6, pieces 1134, bag taken`, the full week to day 19 08:00. Deaths by day: 12: 3 (bleeding x2, a shambler), 13: 0, 14: 4 (shamblers x3, bleeding), 15: 2, 16: 1, 17: 1, 18: 2, all six dehydration in house 1 (Q3's thirst gap). **Cold deaths: 0; lowest warmth 48** (one cold trip, day 15 16:44 at warmth 50). Each winter night the stove runs out about 04:30 and warmth falls from 100 to about 78 by 08:00 (some 7 an hour), then the morning planks bring it back: the bot keeps its stove fed well enough. **Old Pete kills: 0.** **Pieces lost (all six): 3 town walls, 2 town doors, 1 smelter**; no beds, stoves or furniture. Five go on day 12 evening (house zombies 9 and 10 investigating the base's noise: three walls and a door; a chaser: the player's smelter), one town door to a chaser on day 15 at 12:47. Park zombies drawn 6 of 11.

**Try it on the PC:** merge, then in a terminal in the game folder:
- `play.bat --time=15 --cam=0,0,-116,0,-5`: you stand just inside the factory hall's doorway with Old Pete looking at you. He comes for you; walk back out of the doorway (south) and he stops at the door and walks back to his place between the crates. From outside he ignores you.
- `play.bat --demo-factory --time=21`: the noisy starter factory at night. Old Pete stays in the hall (the base log no longer says "Old Pete is on the move" unless you go in).
- `play.bat --day=16 --time=22 --inside=1`: a winter night in house 1. Warmth falls slowly (about 7 an hour) instead of filling up. Build a stove (B, mouse wheel to "Stove") and load planks with E: standing near it, warmth climbs.
- `play.bat --inside=0 --demo-stove --day=16 --time=22`: a lit stove in house 0's kitchen: warmth climbs while you stand by it.
- Lead a zombie into a house: it walks round the beds, couches and the stove and never smashes them; doors and windows still break.

**Known gaps:**
- *(Fixed in the soak re-run above: the soak now carries the park watch across a load.)* **The soak failed on its park-zombie invariant at day 15 15:00 and stopped there**, so it did not play the rest of winter (days 15-19). Most likely the Q3 gap below, not a rule change: after the 14:30 save and load the soak re-registers every zombie standing in the park as an undrawn park zombie (zombie ids are new after a load), including ones that had already chased the bot on its park trip that afternoon (the bot died twice on that trip). Zombie 14 was idle-wandering 0.8 m inside the hall's north doorway, just south of the park. Not re-run (one soak run per brief). The fix would be in `test/stress/soak.gd` (e.g. keep a drawn flag across loads by position, or allow the hall's north doorway). Repro: `tools/soak.sh --days=7 --start-day=12`.
- **The indoor-cold rule got little exercise from the soak** (15 winter hours, warmth never under 59), so whether the bot can keep its stove fed through a winter night is still open. Q3's numbers stand: a full stove (10 planks) lasts 20 game-hours, so the stove loaded at 08:30 is empty by about 04:30; asleep in house 1 by an empty stove on a winter night warmth now falls 3.3 an hour, so a full night by an empty stove costs about 13-17 warmth, not a death. The soak's "go indoors when warmth < 50" step only triggers outdoors; looting other houses below 50 it doesn't head for the stove.
- **House zombies drawn by the base's noise now break house walls instead of beds.** Zombie 9 (Q3: it broke the town bed on day 12) walks round the bed now and took out two walls of its house on the way to the noise; zombie 10 a wall and the door. Allowed by the rule (a wall in an investigator's way is broken, Q2). A rule call for the lead if houses should stay whole.
- **Unsure, for the lead:** the electric fence (kind "fence") is on the breakable list as a wall you build; solar panels, belts, traps and tripwires are not on it, so zombies now walk round them (before, a chaser or investigator could break any of them). The water tap is a "machine" by kind and is excepted by id.
- **Old Pete can be shot from outside the hall with no answer:** he gives up the moment you step out of the footprint, so standing outside a doorway you can shoot him while he walks back to his spot. By the rule as written.
- Old Pete's home area is the hall's footprint (`TownPlan.factory_rect()`), not a door-by-door check; a knockback that pushes him out of a doorway is undone by walking back on his next idle tick.
- The Q3 gap stands: park zombies are re-identified by position after each load (see the first line).
- Every other gap from the Q3, M17a, A2, M16, Q2, A1, Q1, P3, P2, M15 and M14 lists stands, except Q3's beds, stove, indoor-cold and Old Pete lines (fixed here).

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — Q3 Winter soak and tour

From the Q3 brief by the project lead, on top of M17a (PR #38). A QA pass: a week of play that reaches winter and the park, the screenshot tour again, fixes for what is small, the rest written down. No new content, no tuning.

**Built:**
- **`tools/soak.sh --days=7 --start-day=12`.** `--start-day=D` starts the soak on day D (it sets the clock's day the way the game's `--day` does) and turns on the winter steps, on top of the unchanged day-1 script: on the first evening the bot builds a planter and a rain collector in the base and a **stove in house 1** two metres from the bed (from the base crate's scrap, nails and planks; the crate gets 60 extra planks in this mode), loads it; every morning it fetches 10 planks and loads the stove (rebuilding it first if zombies broke it); every night at 22:00 it sleeps in house 1's bed; it eats and drinks every 12 hours; **whenever warmth drops under 50 in the open it goes into house 1** and stands by the stove; on day 15 (the first winter day) at noon it **walks into the park** through the factory hall's two doorways, into the nearest warehouse, searches one crate, delivers the water tower's phase-1 metal plates and walks back (after a death on the way it respawns and goes again); at 14:30 that day a second **save, load, continue** checks that projects and stoves round-trip.
- The hourly line now shows the season and warmth. New invariants (winter mode): warmth in [0, 100]; no death of cold in house 1 while its stove holds planks or burns; planters frozen in winter and only in winter; the rain collector's season speed differs between autumn and winter; the ground, town-roof and park-roof materials are the season's own `SeasonLook` materials a few frames after each hour, and the ground tint changes when the season does; every park zombie stays inside the park fence (plus 4 m) until it has been drawn (chase, attack, break or investigate); the save round-trip compares the projects, `projects_done`, stove planks and the season too. At the end it prints deaths per day with cause and place, and the wall time per game-day.
- **`tools/tour.sh`** has sixteen tiles (a 4x4 sheet): Q3 added the park from the hall's north doorway (`--park`), inside a warehouse with the flashlight (`--cam=-16,0,-152,0,-5 --flashlight`), the water tower (`--tower`) and the street in winter (`--day=16`).
- **Fix (soak): the day-2 wave was "lost" by a later load.** `RunStats` is new after a load in a headless run (only the session log carries it, and headless has none), so the mid-week load reset `waves` to 0 and the end check said no wave came. The soak now adds up waves across loads. The waves did come: zombies alive went 15 to 31 to 40 (the cap) between 21:00 and 23:00 on day 13 at heat 106.

**Rules:** none changed. The game code is untouched; everything is in `test/stress/soak.gd`, `tools/tour.sh`, `tools/contact_sheet.py` (docstring) and the docs.

**Tests:** 7878 checks (unchanged: no game code changed; the soak fixes are tested by the soak runs below).

**Soak (this PC, run 3 of 3):** `SOAK OK: NaN moves undone 0; 7 game-day(s) in 629 s wall (90 s per game-day); deaths 15, kills 48, waves 6, swings 64, gear 9, pieces 1136, bag taken`. Deaths by day: day 12: 5 (bleeding x2, shambler, Old Pete x2), 13: 1 (bleeding), 14: 3 (shambler x2, bleeding), 15: 2, 16: 1, 17: 1, 18: 1, 19 (to 08:00): 1, the last six all dehydration, in house 1. **No death of cold**; warmth low 50, one cold trip indoors (day 15 16:59). Collector speed autumn 1.0, winter 0.5; ground tint autumn then winter; park zombies stayed in the park. Wall time per game-day: 90 s (runs 1 and 2: 100 s and 86 s; Q1 53 s, M17a 102 s). Static memory 142-151 MB all week, first navmesh bake 71-78 ms, 3-4 bakes a run, worst physics frame under 3 ms. What the park added: 1118 town pieces at the start (Q1: about 780, so about 340 park pieces), 24 zombies alive at the start instead of 12 (the park's 12), the first bake 78 ms instead of 49. Nothing else grew over the week (memory flat after day 1, no extra bakes).

**Tour (this PC):** all sixteen tiles render. Nothing new is broken: the park from the doorway (warehouses, a wreck, zombies, the tower in the fog), a warehouse inside (brick walls, the doorway and back doorway, two windows, crates, two zombies), the tower with its "phase 1 of 3" prompt, the winter street (white ground and roof edges, cold sky). Two old notes stand: the hall is grey with fog (Q1), and the park's wreck reads as an ordinary dark car rather than burned out (M17a's gap: town car models in a rust tint).

**Try it on the PC:** merge, then in a terminal in the game folder:
- `bash tools/soak.sh --days=7 --start-day=12` (about 10-12 minutes; one heavy job at a time): one line per game-hour with season and warmth, ending in `SOAK OK`, the deaths per day and a `winter:` line.
- `bash tools/tour.sh`, then open `.shots/tour/contact.png` (sixteen tiles).

**Known gaps (findings not fixed; numbers from the three seven-day runs):**
- **Beds are not furniture, so zombies break them.** M16's rule spares counters, tables, couches, shelves, bathtubs and toilets (kind "prop"); a bed is kind "bed" and still a break target. Every run: `day 12 14:02 piece gone: bed o:-5:-11 (the town's; zombie 9, investigate)`; in run 1 house 1's own bed went too (`day 15 03:13 piece gone: bed o:5:-7 (zombie 50, chase)`), and the bot had no bed for the rest of the week. A rule call for the lead. Repro: `tools/soak.sh --days=7 --start-day=12`, the "piece gone" lines.
- **Zombies break the stove.** Run 2: `day 14 01:20 piece gone: stove o:4:-7 (the player's; zombie 55, investigate)`, a zombie from the day-13 wave, through house 1's open door (the bot leaves it open); the bot rebuilds it now. Stoves are machines-like break targets, and a lit one is a continuous sound (loudness 15). By the rule as written; worth knowing for Playtest #1.
- **Indoors, the cold never bites, and the stove adds nothing there.** Under a town roof warmth gains 20 a game-hour whatever the season, so the bot sat at warmth 100 indoors all winter with the stove empty or full; it only fell to 50 outdoors (winter day drain 12 an hour, night 20). The stove matters only for a base you built (no roof) or outdoors. Not tuned here.
- **One stove load does not last a day:** 10 planks at most, one per 2 game-hours = 20 hours, so a stove loaded at 08:30 is out by about 04:30 (`stove planks 0` in the 03:00-08:00 lines every night). Not tuned here.
- **The bot dies a lot, mostly of thirst after day 14:** 15-21 deaths a week (run 1: 21, run 2: 17, run 3: 15). Days 12-14 are zombies and bleeding (5, 0-1, 3-8); from day 14 03:00 it has nothing to eat or drink ("Nothing to eat, Nothing to drink"), because it only ever loots house 1 and car_0, and the rain collector's water is dirty (it needs a powered purifier). Six dehydration deaths in run 3, days 15-19. The bot's limit, not the game's.
- **Old Pete leaves the factory hall** and kills the bot twice on the first evening, outdoors at 21:35 and in house 1's bed at 22:24-22:37, every run (the day-1 factory's noise draws him). Zombies killing the bot, recorded for the lead.
- **The soak is not deterministic over a week:** the three runs diverge from day 13 night (deaths 21 / 17 / 15, the stove broken in run 2 only, the park trip died of thirst on the way in run 2). Each run is one sample.
- The day-1 script's drive step does nothing from day 12 on (`refuel: No gas cans; moved 0.0 m`): car_0 was siphoned at noon and the generator burned the crate's gas cans. The bot's limit.
- Park zombies are re-identified by position after each load (zombie ids are new after a load), so one that left the park undrawn before a load is no longer watched after it.
- Every other gap from the M17a, A2, M16, Q2, A1, Q1, P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M17a The industrial park and the water tower

From the M17a brief by the project lead, on top of A2 (PR #37). The first half of the design doc's M17 ("Further out"): a second, harder area north of the factory hall, and the first big project in it. Outposts and the substation are M17b.

**Built:**
- **The industrial park.** The road now carries on north out of the factory hall (which has a second 4 m doorway in its north wall) for 120 m, to z -258. On it, seeded from the world seed like the town: **four warehouses** (two each side of the road, 6 x 10 cells, 12 x 20 m, rows jittered a cell by the seed), built from the same grid pieces as the houses: a floor, outside walls in dark brick or corrugated metal, a 4 m open doorway facing the road, a one-cell back doorway, two windows in each end wall, a flat roof 5 m up with the wall carried up to it. Each warehouse has **3 to 5 supply crates** against its walls (a new "Warehouse crate" loot table, `industrial`). **Two or three wrecked cars** sit on the park road: burned out, never drivable, but their trunks can be searched and their tanks siphoned (G). A **grey wire fence** (the picket fence model in dark steel) runs along the park's west, east and north edges and the ends of its south edge, with a 4 m gap at a seeded place in every 16 m. The ground and the navmesh now reach z -275.
- **It's harder than the town:** twelve zombies stand there from the start, two in each warehouse (facing the doorway, they don't stroll) and four between the warehouses; one runner inside, one outside. Warehouse crates hold metal plates, wall panels, nails, gas, scrap and ammo; guns, gun parts and ammo turn up more often than anywhere else (gun 8%, part 25%, ammo 45% a crate), gear as often as in the factory's crates, and **gear and guns found in the park are Police tier three times as often** as in town (45% instead of 15%).
- **Waves walk the longer road.** The Director's north road end is now past the park's north fence. A group or horde from the north walks the park road south, round the hall's west side (as before), then down the town road; one from the south walks up through town, round the hall and into the park if the noise is there. Wanderers still come straight from any edge.
- **The water tower**, a 12.6 m kit model (a riveted tank on four braced legs, a ladder up the front to a catwalk, a riser pipe and a pump house at its foot) east of the park road between the two east warehouses. It's the first **big project**, with three phases. E on the tower opens the **project screen**: the phases, what the current one still needs (and how many you have), **Deliver** and **Start Work** buttons, and the work's progress.
  - Phase 1 "Patch the tank": 10 metal plates, then 1 game-hour of work at loudness 70 (hammering).
  - Phase 2 "Fix the pipes": 6 wall panels and 20 nails, then 1 game-hour at loudness 75.
  - Phase 3 "Run the pump": the tower must be on a power network with 60 W spare (a pole within 12 m of it counts), then 1 game-hour at loudness 85; the pump's 60 W are drawn from that network, so its generator runs (and roars) on top.
  - Delivering takes from your pockets and any storage crate within 30 m of the tower, part at a time if you like. **Work: press Start Work once (my call), then it runs while you stand within 6 m of the tower**, alive, on foot and awake; walk off and it pauses (and goes quiet), come back and it carries on by itself. The work is a continuous noise source like a machine: zombies hear it, the Director heats up. Zombies drawn in interrupt nothing but hurt as usual.
  - Each phase's start and finish goes on the HUD and in the base log ("The tower pump is running. Everything can hear it.").
- **The reward**, when phase 3 is done: the tower is **running**. Every rain collector in the world fills **three times as fast** (water pressure; it stacks with the season, so 1.5x in winter), a new cheap build piece, the **water tap** (4 scrap, 6 nails, no power, a kit model), gives a clean water every 30 s while the tower runs (before that it can't be built, and one that exists anyway stays dry and silent), and `projects_done` gains `water_tower` (saved; M17b reads it to open the next area). A glow lights the pump house while the pump runs and after.
- **Flags:** `--park` (start at the park's south entrance looking north), `--tower[=N]` (start beside the tower with N phases done and the next phase's materials in your pockets), `--project-screen` (open the project screen, with `--tower`).

**Rules (sim, tested):** `ParkPlan` (new, `src/sim/park_plan.gd`, pure): `generate(seed)` gives the warehouses (cells, rect, style, doorway and back-door edges), pieces, crates, zombies, wrecks, fence sections and the tower; `area()`, `road_rect()`, `tower_rect()`, `is_open_ground()`, `warehouse_at()`. `Projects` (new, `src/sim/projects.gd`): sites, per-project state (phase, delivered, progress, working), `deliver`, `start_work`, `tick` (work within `work_radius`, noise sources, power), `missing`, `rain_mult`, `unlocked`, save. `data/projects.json` (new): the water tower's phases, needs, work hours, loudness, watts, sounds, HUD lines and reward; `GameData.projects` + `_check_projects`, buildables' `needs_project`. `data/loot.json`: `industrial`; `data/guns.json`: `finds.industrial`; `data/gear.json`: `containers.industrial`, `police_by_source` (`Gear.police_chance(source)`, used by `roll_piece` and `roll_gun_piece`). `data/buildables.json`: `water_tap`; `data/recipes.json`: `tap_water`. `PowerGrid`: external loads (`external`, `external_on`, `external_spare`): a load joins the network of the nearest piece that reaches it and runs only with its watts spare. `Factory`: `rain_boost`, `tap_on`, a dry tap's status. `BuildGrid.projects`: a piece waiting for a project can't be placed ("Needs the water tower running"). `Director`: `EDGES[0]` at (0, -266), `ROAD_LINE` (park road, round the hall, town road), `road_route` walks it to the point nearest the lure. `TownPlan.factory()`: `north_doorway`. `SimWorld`: `projects`, `place_park(plan, lay_pieces)`, `park_crate_pos`, `spawn_park_zombies`, `project_deliver`, `project_start`, `_tick_projects` (messages, base log, rewards). **Saves:** `SaveGame.VERSION` is 12: `projects` and `projects_done`; the park's pieces are saved like the houses and its zombies like any zombie. A save from before 12 gets the park laid fresh with its zombies (main.gd), the hall's two north-doorway walls taken out, and the tower at phase 0. `test/fixtures/save_v11.json` was written by the A2 code before these changes (the seed-1 town, two foundations, a door, a stove with planks burning, a generator with 3 cans, a zombie, day 17 14:17). World: `ParkView` (new: roofs, crates, fence, the tower and its colliders), `ProjectScreen` (new), `main.gd` (`_build_park`, the bigger ground and `NAV_BOUNDS`, the flags, `_open_project`, `_setup_tower`, the console line now counts park pieces), `Interactor` (E on the tower, its look-at line), `BuildView` (`park_brick` and `corrugated` walls, the tap model), `BuildController.PIECES` (the tap), `SoundView` (hammering and the pump borrow the press and generator loops). Art: `tools/art/water_tower.py`, `tools/art/water_tap.py`, `assets/models/water_tower.glb`, `water_tap.glb`.

**Tests:** `test_park.gd` (new): same seed same park, another seed another; both wall styles turn up; for twelve seeds, warehouses inside the fence, off the factory hall, the road, the tower, every house and each other; no piece laid twice or on a town piece; each warehouse closed all round less its doorway and back door, four windows, 3-5 crates against walls; ten shamblers and two runners, eight inside their warehouses, four on open ground; 2-3 wrecks on the park road; fence lines with gaps; the north route starts at the park road's north end, walks it, goes round the hall and down to the noise; a noise at the tower is reached from both ends; no route runs into a wreck, a fence or a warehouse for any seed; real waves from the north spawn past the fence; the industrial table (never empty, common plates) and more guns, parts and ammo than any other source; Police three times as likely (rolled: in range over 2000 pieces, and gun parts ~45%); `place_park` lays the pieces as the town's, registers crates, wrecks (undrivable, trunks searchable) and the tower; a crate search finds things; the park zombies spawn, inside ones stay inside for a minute, and save and load brings back exactly them and the warehouses; the version-11 fixture loads with the park, its 12 zombies, the hall's north doorway open, its stove and day, and every older fixture still loads at phase 0; physics: you walk in through a west and an east warehouse's doorway and the wall beside it stops you; the tower model is ~12.6 m and fits its footprint, the tap has a model. `test_projects.gd` (new): the data and its checks; delivering from pockets, then a crate 9 m away but not one 46 m away, nothing more once it's in, refusing to start before; work only within 6 m (none at 10 m or 7 m, none asleep), a continuous source at 70 while it runs, a zombie 15 m away hears it, the HUD and base log lines, phase 1 done after a game-hour; phase 3 with no network, then with 20 W spare (nothing), then 60 W (runs at 85, the generator runs too, demand includes the pump's 60 W), the HUD line, done; before the reward a rain collector takes 20 s and a tap is dry, silent and can't be built; after, 6.7 s, the tap gives water and can be built, and winter halves the boost; save and load keep a part delivery, mid-work progress (which then finishes) and the reward; the project screen lists every phase, shows phase 1's and then phase 2's needs, and its buttons deliver and start the work. Changed: `test_road_hordes.gd` (the north route now starts in the park; the walking test starts at the hall's west side as before), `test_factory_hall.gd` (two doorways), `test_street_plan.gd` (the park's wrecks are cars too), and the old-fixture tests in `test_save`, `test_guns`, `test_automated_defense`, `test_town_salvage`, `test_seasons` expect the two north-doorway walls gone and a version of 11 or later. **7878 checks** (was 5325). Soak (`tools/soak.sh`, one day): `SOAK OK: NaN moves undone 0; 1 game-day(s) in 102 s wall; deaths 4, kills 11, waves 0, swings 32, gear 6, pieces 1134, bag -`.

**Screenshots (this PC):** the park from just inside the hall's north doorway at noon: the road between two brick warehouses with open doorways and windows, corrugated ones further on, a wreck on the road, a zombie by a warehouse, the tower on the right, the fence at the far end. Inside a warehouse with the flashlight: brick walls, three crates, the back doorway and a window, a zombie in a hard hat. The tower with the project screen open (phase 2: 6 wall panels and 20 nails, "you have" counts, both buttons). At 22:00 the park is dark, the tower a silhouette, the wreck lit by the torch.

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**. Walk up the road, through the factory hall and out of its north doorway: that's the park. Careful, it's busy. To start there, in a terminal in the game folder:
- `play.bat --park --time=12`: at the park's south entrance at noon.
- `play.bat --tower --time=12`: beside the water tower with 10 metal plates. Press E on the tower (a leg or the pump house), click **Deliver what it needs**, then **Start work**, and stay within 6 m for a game-hour (about a minute at the default day length). Hear the hammering, and watch for company.
- `play.bat --tower=2 --time=12`: phase 3. Build the generator (it needs a foundation), load gas (E), put a power pole within 12 m of the tower, then Start work.
- `play.bat --tower=3 --time=12`: the tower running; build a water tap (B, mouse wheel to the end) and a rain collector and watch them fill.

**Known gaps:**
- Not in M17a, as planned: outposts, the substation and radio tower projects, the area beyond the park, traders (M17b and later).
- The tower never stops running once it's done (no breakdowns, no sieges that knock it out), and taps don't need pipes to it.
- Work is press-once, stay-close; there's no animation or hammer in your hands, and the hammering and pump borrow the press and generator sounds.
- The park's twelve zombies count toward the Director's cap of 40 alive, so with a full park a horde still fits (8) but a town crowded by earlier waves can shrink later ones.
- The north route still comes round the hall's west side (through the open stretch between the fence's south-west end and the hall); it doesn't walk through the hall's two doorways. Fence sections are colliders on the navmesh like the street's, so zombies route round them through the gaps.
- Wrecks are ordinary cars marked burned out (the town's car models in a rust tint), not wreck models; their trunks are the town's car trunk table.
- Warehouse roofs, like the houses', have no collider, and the brick band above the wall pieces has the same faint seam at 2.8 m as the factory's. No props inside beyond the crates.
- Old saves: the park's crates, wrecks and zombies are new to them, and the hall's two north-doorway walls are taken out (walls you built there yourself aren't touched).
- The park costs time: the first navmesh bake is about 78 ms headless (was about 49), and the one-day soak took 102 s of wall time (was 59) with 24 zombies alive instead of 12. Worth a `tools/stress.sh` run before M17b adds more.
- Every other gap from the A2, M16, Q2, A1, Q1, P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1; M17b outposts and the substation after it.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — A2 Zombie variety

From the A2 brief by the project lead, on top of M16 (PR #36). A crowd of zombies looked like one person copied with a different shirt; now there are five different people. No new rules, animations or zombie kinds.

**Built:**
- **Five bodies from the one rigged script.** `tools/art/zombie.py` takes `-- --variant=NAME` (or a `VARIANT` environment variable; `--out=PATH` writes elsewhere). `default` is the original body, untouched, and still exports `zombie.glb`; the four new ones export `zombie_<variant>.glb`. All five are built by the same code: the same parts plus the outfit's extras, then reshaped bone by bone (joints move, each part stretches along its bone and scales across it, the head scales evenly, then the boots are put back on the floor), on the same 17 bones with the same seven animations, so any body plays any animation.
  - **heavy**: wider shoulders and hips, deeper belly, thicker limbs and neck; a faded orange hi-vis vest, a yellow hard hat, khaki work trousers.
  - **slim**: narrower, thinner limbs, longer legs (about 1.86 m); long sleeves to the wrist, charcoal trousers, grey hair.
  - **short**: shorter legs and torso in proportion, not just scaled (about 1.6 m), a slightly bigger head for its size; a navy ball cap, brown trousers.
  - **woman**: narrower shoulders, wider hips, slimmer limbs, a bust; a sleeveless, straight-cut top with a deep V neck instead of the torn shirt, long brown hair down the back and over the ears, black trousers.
  - Each stays under the script's triangle budget (2688-3060 triangles; the default is 2652), and each passes `verify_reimport()` (bones, materials, all seven actions and their lengths, rest height in its own range, the Death pose lying down).
- **Each zombie gets a body** from its id and kind (`ZombieBody.variant_for(id, type)`): ids come in blocks of five and each block is a hashed shuffle of the five bodies, so the same zombie always wears the same body (after a reload too) and any handful spawned together is a mix. `ZombieBody` preloads all five and swaps the body in `setup()`; the shirt colour and size jitter still apply on top.
- **Kinds keep their look on any body:** runners stay smaller with dark skin and dark shirts, and now their trousers, vest, hard hat or cap are dimmed too; screamers stay pale with blood-red shirts; Old Pete stays 1.25x big in his red shirt.

**Rules:** none (presentation only). World: `ZombieBody.BODIES`, `MODELS`, `BODY_CLOTHES`, `variant_for()`, `_set_body()`, `body_variant`, the runner's `"dim"`. Art: `tools/art/zombie.py` (`VARIANTS`, `DEFAULT_OUTFIT`, `reshape()`, outfit options in `build_character`, per-variant checks in `verify_reimport`), four new `assets/models/zombie_*.glb` with their `.import` files.

**Tests:** `test_art_models.gd`: every zombie body loads and is the model `ZombieBody` uses, has exactly the default's 17 bone names, all seven animations `ZombieBody._animate` plays, one mesh with the Shirt, Zombie Skin and Jeans materials, stands on the floor and is person-sized; the short body is shorter, the slim one taller, the heavy one wider, the woman a little shorter. `test_zombie_types_world.gd`: the same id gets the same body every time; ids 1-20 wear at least three bodies (they wear all five); a real `ZombieBody` wears its picked body, a second one with the same id the same body, only one model and one AnimationPlayer remain after the swap, and it walks; runners, screamers and Old Pete each come in all five bodies and keep their skin, shirt and size, and a runner's vest, hard hat and cap are dark. The existing zombie tests pass unchanged. **5325 checks** (was 5155).

**Screenshots (this PC):** eight zombies in a line facing you at noon and at 22:00 with the flashlight: a hard hat and vest, two navy caps, long hair, long sleeves and the old body side by side read as different people, in daylight and in the torch beam; idle poses look right, with no arms through bellies (the heavy body's arms sit further out). Eight runners in a line: all dark and small, still different builds and hats.

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**: the street zombies are now a mix of people. To see a line-up, in a terminal in the game folder:
- `play.bat --time=12 --zombies=0 --cam=0,0,0,0,-4 --zombie=-3.5,-6,-2.5,-6,-1.5,-6,-0.5,-6,0.5,-6,1.5,-6,2.5,-6,3.5,-6`: eight zombies in a row by day (they'll start walking at you).
- The same with `--time=22 --flashlight` instead of `--time=12`: the same row at night in the torch.
- Add `--zombie-type=runner` (or `screamer`) for a row of runners (or screamers) on mixed bodies.

**Known gaps:**
- Not in A2, as planned: new animations, new zombie kinds, textures (flat colours as before).
- The bodies share the default body's animations, so the heavy and woman bodies move exactly like the original townsperson; a heavy zombie's run looks as light as anyone's.
- Head hits still count above 1.45 m from the feet for every body (`ZombieBody.HEAD_Y`), so on the short body the lower part of the head counts as a body hit, and on the slim body the top of the shoulders can count as the head. The collision capsule is the same 1.8 m for every body.
- Each body has one fixed outfit (the shirt colour still varies per zombie); a second outfit per body would need more variants or tinting the extras in code.
- Hair isn't dimmed on runners, so a slim runner's grey hair stands out.
- Headless tests print a handful of "Parameter material is null" engine errors from the dummy renderer while the zombie-kind tests free bodies; no check fails and nothing shows in a normal run.
- Every other gap from the M16, Q2, A1, Q1, P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M16 Seasons

From the M16 brief by the project lead, on top of Q2 (PR #35). A calendar and four seasons that change the rules: winter stops crops, the cold needs heat, and sound carries farther on cold nights. Plus one rule change from the lead: zombies never break furniture.

**Built:**
- **Zombies never break furniture** (this reverses W1c's "bashed by zombies like a crate"). A counter, table, couch, shelf, bathtub or toilet is never a break target: a chasing or investigating zombie that walks into one forgets the bump and its navmesh path goes round it (furniture stays a navmesh obstacle); a wandering one turns away as before. Walls, doors, windows, barricades, machines, turrets and crates are still broken. The soak's house-1 counter now survives day 1.
- **A calendar.** A year is four seasons of 7 days: summer (days 1-7), autumn (8-14), winter (15-21), spring (22-28), then summer again. A new game starts on day 1, so winter arrives on day 15. The HUD clock reads "Day 16 · Winter 09:40".
- **The sun follows the season:** summer 05:00-21:00 (as before), autumn 06:00-19:00, winter 07:30-17:30, spring 06:00-20:00. Daylight, night, the sky and solar power all go with it.
- **Crops and water:** in winter planters freeze (the timer pauses, the HUD says "Frozen: nothing grows in winter", a frozen planter is silent); in summer they grow 25% faster. Rain collectors run at half speed in winter (snow) and 1.5x in spring.
- **Warmth**, a new meter (0-100, shown on the HUD once you've lost any). Outdoors it drains per game-hour: autumn 3 by day / 5 at night, winter 12 / 20, spring 1 / 2, summer none. Under a roof (on a house or factory floor) it comes back at 20 a game-hour; within reach of a heat source at 60. The jacket now gives "the cold gets to you 30% slower" (gear's `warmth` bonus; gear can cut the cold by 80% at most). Below 30: stamina comes back at half speed and "You're cold" once a game-hour. Below 10: 1 health every 20 s and "You're freezing: find a roof or a fire" (death by cold says "froze to death" in the session log). Asleep in a bed it never falls.
- **Stove** (new build piece: 6 scrap metal, 6 nails): E loads planks (pockets, then crates; holds 10). It burns one plank per 2 game-hours while it has any, heats 6 m, makes a quiet crackle (loudness 15, a continuous sound like a machine) and lights the room with a warm flickering light. Pulling it down gives back the planks still waiting. The model is the generator's body painted cast-iron black, with a glowing firebox window and a stovepipe added in code.
- **Electric heater** (new build piece: 4 metal plates, 6 nails): 40 W on the power grid, silent, heats 5 m while powered. The model is the purifier's body painted cream with a glowing grille.
- **Sound carries on cold, still nights:** on autumn nights every heard level gets +3 dB, on winter nights +6, in one place (`NoiseField.level()`), so zombies, the Director's heat, noise sensors and the noise overlay all agree.
- **Looks:** the ground goes straw-brown in autumn, white in winter and greener in spring; A1's trees go orange-brown in autumn, bare grey in winter and bright green in spring; house and factory roofs go white in winter; the daytime fog is warmer in summer and a colder blue in winter. All tints on the existing materials, no new textures. They change when the season does (at midnight).
- **Flags:** `--day=N` starts on day N (`play.bat --day=16 --time=12` is winter at noon); `--demo-stove` puts a burning stove in the room you stand in (with `--inside`).

**Rules (sim, tested):** `data/seasons.json` (new): days per season, the order, and per season its name, sunrise, sunset, crop_speed, rain_speed, cold_day, cold_night and hearing_night; warmth (indoor_gain, heat_gain, bonus_cap, cold_at, cold_stamina_regen, freezing_at, freeze_damage, freeze_every); stove (hours_per_fuel, cap, radius); heater radius. `GameData` loads and checks it (`_check_seasons`) and knows the kinds `stove` and `heater`. `GameClock`: `calendar`, `set_calendar()`, `season()`, `season_day()`, `season_name()`, `season_cfg()`, `day_of_year()`, `seconds_per_hour()`; setting `day` sets the season's sunrise and sunset. **`Climate`** (new, `src/sim/climate.gd`): stoves (`load_fuel`, burning, `hours_left`, `noise_sources`, refunds, save), heaters (`heater_on` from the power grid), `heat_near(pos)`, `warmth_rate(...)`. `PlayerStats`: `warmth`, `warmth_rate`, `cold_cfg`, `is_cold()`, `is_freezing()`, half stamina regen when cold, freezing damage (cause `"cold"`). `Factory`: `crop_speed`, `rain_speed`, `season_speed(m)`, `Machine.frozen`. `NoiseField`: `carry_bonus` and `level()`, used by `loudest_heard`, `outdoor_level`, `Director.gain_now` and the noise sensors; frozen machines are silent. `Horde` + `ZombieBrain.leave_furniture()`: furniture is never broken. `SimWorld`: wiring, `is_indoors(pos)`, `stove_interact(key)`, the cold messages, stove planks refunded on removal. `BuildGrid.is_object` knows stoves and heaters. `data/buildables.json`: `stove`, `electric_heater`; `data/gear.json`: the jacket's `"warmth": 0.3`. **Saves:** `SaveGame.VERSION` is 11: the player's warmth and each stove's planks and burning fuel. `test/fixtures/save_v10.json` was written by the Q2 code before these changes (the seed-1 town, a door, a growing planter and a generator with gas, day 3 20:30); it loads with full warmth and no stoves, and every older fixture still loads. World: `SeasonLook` (new, `src/world/season_look.gd`), `main.gd` (`apply_season`, `warmth_text`, the HUD clock, `--day`, `--demo-stove`), `StreetView.apply_season`, `TownView.apply_season`, `DefenseView` (fires and heater grilles), `BuildView` (models, tints, the stove's firebox and pipe), `Interactor` (E on a stove, both pieces' status lines), `BuildController.PIECES`.

**Tests:** `test_seasons.gd` (new): the season and day-of-season for days 1 to 57 and the year wrap, crossing midnight into winter; sunrise, sunset, noon daylight and dark/light either side for every season, 07:00 and 18:00 dark in winter and light in summer; a solar panel at 07:00 makes power in summer and none in winter; a winter planter grows nothing, says Frozen, is silent and thaws in spring where it stopped; a summer crop in 48 s, an autumn one in 60 s; rain collectors at 40 s in winter, 13.3 s in spring, 20 s otherwise; warmth outdoors for every season by day and night; +20 indoors on a house floor; a lit stove gives +60 even outdoors on a winter night, crackles at 15, burns one plank in two game-hours, goes out and goes silent, holds 10, burns 5 hours in 5 hours, and does nothing 30 m away; removing it refunds the waiting planks; the heater does nothing without power, warms at +60 on a generator's network, draws 40 W, is silent and doesn't reach 6 m; the jacket's bonus (8.4 a winter hour instead of 12), its card line and the 80% cap; at 25 warmth stamina comes back at half speed and "You're cold" once a game-hour; at 5, 1 health every 20 s, "You're freezing", cause "cold"; asleep, warmth holds on a winter night; the hearing bonus on winter (+6) and autumn (+3) nights and none on summer nights, winter noon or spring nights, a zombie hearing a sound 3 dB under its threshold on a winter night but not a summer one, and the Director's heat higher on a winter night; save and load keep warmth, stove planks and fuel, the day and the season; the version-10 fixture and every older one load with full warmth; `seasons.json` mistakes are flagged. `test_zombie_brain.gd`: the house zombie investigating a noise with its counter in the way, then chasing you across it, never starts breaking it and the counter keeps every hit point; one caught mid-break stops. `test_town_salvage.gd`: its version check now says "10 or later". **5155 checks** (was 4928).

**Soak (this PC):** `SOAK OK: NaN moves undone 0; 1 game-day(s) in 59 s wall; deaths 3, kills 11, waves 0, swings 32, gear 5, pieces 780, bag -`. The only "piece gone" line left is the town door broken by a chaser (`day 1 08:29 piece gone: door w:-4:-14:w (the town's; zombie 9, chase)`); house 1's counter survives. The soak plays day 1 (summer), so it doesn't exercise the cold.

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game** (it starts in summer; winter comes on day 15). To see the seasons now, in a terminal in the game folder:
- `play.bat --day=16 --time=12`: winter at noon: white ground and roofs, grey trees, a cold blue fog, "Day 16 · Winter 12:00". Walk around outside and watch Warmth appear on the bottom line and fall; step into a house and it climbs back.
- `play.bat --day=9 --time=12`: autumn: brown ground, orange-brown trees.
- `play.bat --inside=0 --demo-stove --day=16 --time=22`: a lit stove in house 0's kitchen on a winter night. Look at it for its status; E loads planks.
- `play.bat --demo-farm --day=16`: the planter says "Frozen". Build a stove (B, then the mouse wheel to "Stove") on a foundation and load planks with E; an electric heater needs a generator or solar panel next to it.
- `play.bat --day=16 --time=22 --noise-overlay`: the rings are bigger than on a summer night.

**Known gaps:**
- Not in M16, as planned: weather beyond the tint (no rain, wind or snowfall particles), ice on roads, crops dying in the cold, animals.
- Only town floors count as "under a roof" (as for the indoor fog and the house zombies): a base you build yourself has no roof, so out there it's the stove or the heater. Walls and closed doors don't stop a stove's heat; heat goes by distance only.
- The stove burns whenever it has planks (no off switch), in summer too; the heater draws its 40 W all year whenever it's powered, which keeps a generator running.
- Warmth drains and the stove burns per game-hour, so with a longer day (Settings) they're slower in real time; food and water drain per real second as before.
- Sun hours jump at midnight when a season changes (no gradual change across the week).
- A new game starts on day 1 = the first day of summer (the brief said "late summer"; this keeps winter on day 15, `--day=9` autumn and `--day=16` winter as the brief's screenshots ask). `data/seasons.json` `start_offset_days` moves it.
- The stove is the generator's body with a dark tint, so it still reads a bit like a generator; a proper kit model is a later art job. The heater is the purifier's body painted cream.
- Zombies don't feel the cold, and nothing changes for them by season except hearing.
- Every other gap from the Q2, A1, Q1, P3, P2, M15 and M14 lists stands, except Q2's counter line (fixed by the furniture rule).

**Next:** Playtest #1, then M17.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — Q2 Fixes from the soak

From the Q2 brief by the project lead, on top of A1 (PR #34). Four fixes for what the Q1 soak and tour found, each with a test. No tuning, no new content.

**Built:**
- **Idle zombies leave things alone.** Only a zombie that is chasing you or investigating a sound (a wave walking its road route included) may start breaking a piece, and only one it walked into on its way. A wandering zombie that bumps a piece now turns away and strolls to another spot (it used to stop and stand). Two holes are closed: a bump from a stroll no longer counts as "in the way" in the tick the zombie hears a sound or spots you, and when the piece it was breaking is gone an investigating zombie walks on to the sound (or, if it wrecked the noisy machine itself, it is done) instead of switching to a chase after nobody, toward wherever it last saw you (the world's centre if it never had), breaking everything on the way.
- **Thinner fog under a roof.** When the camera is under a house roof or the factory hall's roof, the fog and the volumetric fog thin to a fifth of outside's, eased over half a second, and thicken again when you step out. Light, colour and night darkness are unchanged. Before (the same as outside): fog 0.0071 and volumetric 0.0035 in the factory hall at 15:00, 0.0063 and 0.0024 in house 1 at 12:00. Now: 0.0014 / 0.0007 and 0.0013 / 0.0005. Old Pete is no longer grey at 7 m in the hall.
- **The heat warning has its own line**, under the pockets / weight / weapon block in the top right, wherever that block ends. The pockets block is now a 380 px column that wraps (right-aligned), so a long list can't reach the messages in the middle of the screen at 1280x720.
- **A parked car reports 0 m/s.** A frozen body gets no more physics callbacks, so the velocity a car had when you got out stayed cached in the node and the physics server: `forward_speed()` kept reporting it (4 m/s for a car left rolling), and it is what the engine hands a body touching the car. Getting out now zeroes the car's velocity before it freezes, and `forward_speed()` of a frozen car is 0. Q1's guards (no platform velocity for zombies and the player, undo a NaN move) stay.
- `tools/soak.sh`'s "piece gone" lines now say which zombie broke the piece and what it was doing when it started.

**Rules (sim, tested):** `ZombieBrain`: `_start_break` refuses unless the zombie is in CHASE or INVESTIGATE and records `break_from`; `_after_break` returns it to the chase, the investigation, or idle (the sound's machine wrecked); `_turn_away` picks a wander spot on the far side for a WANDER bump; `hear()` and the idle/wander-to-chase switch clear `blocked_by`. World: `TownView.is_under_roof(pos)` (house cells below the ceiling, the factory hall below its roof); `main.gd` `indoor_fog`, `indoor_fog_target()`, `fog_targets()`, `INDOOR_FOG = 0.2`, `FOG_EASE = 0.5`, `MATERIALS_WIDTH = 380`; `CarBody.drive(false)` zeroes velocities before freezing.

**Tests:** `test_zombie_brain.gd` (a wandering zombie that walks into a wall turns away to a spot on the far side and never hits it in a minute of pressing; town seed 1 through the real sim step: the house zombie leaning on its house's counter for ten minutes with no noise, idle and then strolling into it, never starts breaking it and the counter keeps every hit point; a chaser blocked by house 1's closed door breaks it; an investigator blocked by house 1's wall hits it; after breaking a wall an investigator goes back to its sound, and one that wrecked the noisy machine goes idle; a bump from a stroll is not broken when the zombie then hears a sound behind it or spots you). `test_indoor_fog.gd` (new, real scene: house 1's cells and the factory hall are under a roof, the spawn is not; inside, the fog eases (not a jump) and is a fifth of outside's after half a second, volumetric too, fog light as outside; back outside, both come back). `test_hud_layout.gd` (new: with text in all three, at every heat level and at 1600x900 and 1280x720, the heat warning, the pockets block and the messages never overlap, and the heat warning is under the pockets block). `test_car_exit.gd` (new, real scene: get into car_0, drive, handbrake to a stop and get out, then again getting out while rolling; with a body leaning on the car's side, the car's speed, velocity, server velocity, velocity at a point and what it hands the leaning body are finite on every frame for two seconds; the parked car reports 0 m/s and zero velocity in the node and the server). `test_automated_defense.gd`: its wall-hit zombie is put in a chase before it starts breaking. **4928 checks** (was 4843).

**Soak (this PC, after the fixes):** `SOAK OK: NaN moves undone 0; 1 game-day(s) in 57 s wall; deaths 2, kills 11, waves 0, swings 32, gear 5, pieces 779, bag -`. The town door and house 1's counter still go on day 1, and the new lines say why: `day 1 08:29 piece gone: door w:-4:-14:w (the town's; zombie 9, chase)` and `day 1 13:12 piece gone: counter o:6:-13 (the town's; zombie 10, investigate)`. Both are allowed by the rule (see Known gaps).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**:
- Walk into a house: the room clears up over half a second; step back out and the street fog comes back. The factory hall with Old Pete: `play.bat --time=15 --cam=0,0,-116,0,-5`.
- `play.bat --demo-factory`: the orange "The noise is being noticed" is on its own line under your weapon, top right.
- Drive car_0 (`play.bat --drive`) and get out (E) while still rolling: nothing new to see (the fix is under the hood); zombies keep walking round the parked car.
- Leave the street zombies alone for a while: wanderers bump fences and furniture and turn away; only one that is after you or a noise breaks through.

**Known gaps:**
- **The soak's door and counter still break on day 1, by the rule as written.** The door is broken by a zombie chasing the bot as it goes into house 1; the counter by house 1's own zombie, investigating the factory's noise from 13:00, which walks into its counter on the way out. Making the counter survive needs a rule change for the lead to decide (for example: furniture is never "in the way", or an investigator goes round it), not a fix. Repro: `tools/soak.sh`, the two "piece gone" lines. *(M16: decided: zombies never break furniture now, so only the door line is left.)*
- **The car's NaN was not reproduced.** Two attempts (the soak's own drive, handbrake and get out, and getting out while rolling, each with a body leaning on the car every frame for two seconds) never saw a NaN. What they did find is the stale velocity of a parked car, which is fixed above and is the value the engine hands a body touching the car. A likely remaining source is VehicleBody3D's own wheel solver, which divides by the chassis' inverse mass (0 once frozen) if it ever runs a step on the frame the freeze lands; Q1's guards stay for that.
- The pockets block now wraps at 380 px and is right-aligned; a very long message line in the middle of a 1280-wide screen could still reach it.
- Indoor fog goes by the camera's cell, so it changes as you cross a doorway (eased, so no pop). Under a roof you built yourself it stays outdoor fog; only town roofs count.
- Every other gap from the A1, Q1, P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — A1 Street dressing

From the A1 brief by the project lead, on top of Q1 (PR #33). The street looked like twelve houses, four cars and a road on flat ground; now it looks lived-in. No new rules beyond searchable trash cans, no tuning.

**Built:**
- **Five new Blender-kit models** (flat colours, low-poly, `tools/art/`): a **lamp post** with a lantern on top (4.1 m, its glass a separate "Lamp" part), a tin **mailbox** on a wooden post with a red flag, a 2 m section of white **picket fence**, a plastic **trash can** with a lid, and a low-poly **tree** (one model in three sizes: 0.75, 1 and 1.25).
- **Lamp posts** on the strip beside the road, between every second lot on each side (three a side, staggered). At night each lantern glows and lights the street around it with a small warm light (10 m), like the floodlight. No rule attached.
- **A mailbox for every house**, by the road a few metres along from its front door, each house its own colour, its door facing the road.
- **Picket fences** along the side boundary between neighbouring lots, from the house fronts back, ending 2 m short of the back of the lot so zombies and you can still get round. Never across the front.
- **Trash cans**, one or two behind every house, a little out from the back wall and clear of the back door. **E searches them** like a fridge: one roll from a new `trash` table, mostly nothing, sometimes scrap metal or a few nails, now and then a bandage or a can of food.
- **Trees**: one behind most houses, plus four past the spawn at the south end of the road and three beside the factory, off the hordes' road route. Only the trunk is solid.
- **Road markings**: a dashed white centre line and a concrete kerb along both edges of the asphalt (drawn only; nothing to trip on).
- Everything stands on the ground, has a box collider (the navmesh and the player go round it), and never sits on the road, a house, a car, the start crate's cell, a door's doorstep or the path from the road to a front door.

**Rules (sim, tested):** `StreetPlan` (new, `src/sim/street_plan.gd`, pure, seeded): `generate(seed, town)` gives `{"items": [{kind, pos, yaw, scale, color, id, house}], "markings": {dashes, dash_size, kerbs, kerb_height}}`, with `footprint(item)`, `road_rect()`, `house_rects()`, `door_zones()` (every door's cell and the cell outside it), `door_paths()` (road to front door) and `is_clear()`; the model boxes are `SIZES` and the colliders `COLLIDERS`. `SimWorld.place_street(street)` registers each trash can as a `"trash"` container (like the fridges; searched cans save by id like every container). `data/loot.json`: new table `trash` (`"rolls": [1, 1]`, `"empty": 12`, scrap 3, nails 3, bandage 1, canned food 1). `Loot.roll` reads a table's optional `"empty"` weight as "this pick finds nothing"; `GameData` checks it isn't negative. World: `StreetView` (new, `src/world/street_view.gd`; `MODELS`, colliders on the WORLD layer, `container_id` on cans, mailbox tint, lamp lights on at night, the markings); `main.gd` lays the street after the cars.

**Tests:** `test_street_plan.gd` (new: same seed same street, seeds differ; for seeds 1, 5 and 77 six lamp posts, twelve mailboxes in twelve colours within 5 m of their doors and facing the road, ten fence lines of six sections, one or two cans at every house, trees behind most houses and at the road's ends in more than one size, the centre line and kerbs; nothing on the road, the factory, a house, the start cell or the spawn, within 1.5 m of a front door's cell or the cell in front of it, on the path to a front door, or on another item; fences run back from the fronts and every one leaves a clear 2 m gap at the back; lamps on the strip by the road; the cans are registered `trash` containers you can search once; the trash table is one roll and mostly nothing; the Director's road route from both ends, points and legs, runs into no scenery; physics: you walk from the spawn to house 0's front door with every street collider in place; the real game draws every item, nothing stands on a car, the cans are registered and searchable bodies, and the six lamps are off at 08:00 and all lit at 22:00 with a 10 m range). `test_art_models.gd` (the five models load, fit their boxes, stand on the floor, are one mesh each plus the lamp post's Lamp, colliders inside the model boxes, and the mailbox's door is at its front). **4843 checks** (was 4713). With the scenery in place the first navmesh bake is 49 ms headless (`test_town_world.gd`; Q1 measured 42-47 ms).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**:
- Look up the street: lamp posts, mailboxes, fences, the centre line and kerbs. Walk round the back of a house: trash cans and a tree. Press **E** on a trash can to search it (mostly "Nothing useful").
- At night: `play.bat --time=22` (the lamps are lit), or `play.bat --time=22 --flashlight`.
- A house front with its mailbox and fence: `play.bat --cam=0,0,-6,-62,-6 --time=12 --zombies=0`. The backs of the lots: `play.bat --cam=30,0,-12,75,-8 --time=12 --zombies=0`.

**Known gaps:**
- Not in A1, as planned: textures (flat colours only), new buildings, a shop, and any tuning (the trash table's odds included).
- Scenery isn't a build piece: the build grid doesn't know about it, so you can place a foundation or wall through a fence, tree or trash can, and zombies walk round it but never break it. Cars hit it like a wall.
- A fence section's collider is one solid 2 m box, so a bullet stops at it even between the pickets (as at a lamp post, a mailbox or a tree trunk). Fences only run between neighbouring lots on the same side; there is no back fence and nothing past the last lot.
- Street lamps light nothing for the sim: zombies don't see you better under them, and they need no power.
- Trees don't block sight or sound, and their canopies have no collider (only the trunk).
- The kerbs are drawn only, so a car drives over them without a bump.
- Every other gap from the Q1, P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — Q1 Soak and tour

From the Q1 brief by the project lead, on top of P3 (PR #32), so the whole unmerged stack (M12 skills to P3) runs as one game. No new content, no tuning: a bot plays the game for days, a fix for what it found, and a screenshot tour.

**Built:**
- **`tools/soak.sh [--days=N]`** (`test/stress/soak.gd`): a headless bot plays the real game scene (`main.tscn`, `--fixed-fps 60`) from day 1 08:00. Once per game-hour it does the next thing on its list: walks up the street, opens house 1's door and goes in, searches its fridge and cabinets, comes out and closes the door, siphons car_0 and searches its trunk, builds a foundation row, a smelter, belts, a press, a generator and a pole from the starting crate and hand-feeds scrap, fits a muffler, builds a workbench and a wall, eats and drinks, draws the gun it found (or one through `--gun`'s path) and fires four shots at the nearest zombie, refuels and drives car_0, sleeps in house 1's bed, saves through F5's path and loads through F9's (the real scene reload) and carries on. With `--days=3` it also, at dusk on day 2, refuels the generator, feeds the smelter and sets heat 100 while standing in the base, and on day 3 stands still among six zombies until it dies, then picks up its bag. It walks by moving the player node 2 m at a time with physics running, swings at any zombie within reach (except while dying on purpose), and walks back for its bag after any death. Every game-hour it prints one line (time, health, food, water, energy, zombies, heat, infamy, pieces, deaths, static memory, worst physics frame, navmesh bakes and the first bake's time) and checks: health, food, water, energy, stamina and heat in range; carried weight not negative; no NaN or past-1000 m position for the player, zombies or cars; zombies alive at most the Director's cap plus the street and house zombies plus the bot's own; every piece has a drawn node. At the end it also checks that the save round-trip kept day, clock, pieces, zombies, gear, skill xp, infamy and base-log length; that static memory is under 1.6x the end of hour 1; and that the dusk wave came. It prints "SOAK OK" or "SOAK FAILED: <why>" and exits non-zero on failure or on any SCRIPT ERROR / Parse Error. It also prints every piece that disappears and how many NaN moves the zombie guard undid.
- **`tools/tour.sh`**: twelve screenshots, one Godot at a time, into `.shots/tour/` (street 08:00, street 22:00 with the flashlight, house 0 kitchen, house 0 bathroom, the factory hall with Old Pete, `--demo-factory`, `--demo-farm`, `--demo-defense` at 22:00, title, inventory with `--gear=yellow`, skills, help), then `tools/contact_sheet.py` (Pillow) lays them out as one labelled 4x3 sheet, `.shots/tour/contact.png`. About 40 s.
- **Fix: a zombie could turn into NaN for good.** After you got into car_0 and out again, a zombie scraping past the parked car picked up a NaN "platform velocity" from it (the engine carrying bodies along on moving floors), its position went NaN on its next move, its brain followed, and every frame after that logged "Vector3 cannot be normalized" (836,000 warnings in one soak hour, and it slowed the game right down). Zombies and the player now take no velocity from floors or walls (nothing in the game is a moving platform), and a zombie whose move still comes back NaN steps back to its last good spot.

**Rules:** none changed. World: `ZombieBody` and `Player` set `platform_floor_layers = 0`, `platform_wall_layers = 0` and `platform_on_leave = DO_NOTHING`; `ZombieBody` keeps its last finite position and undoes a NaN move (`nan_recoveries` counts them).

**Soak results (this PC):** one game-day: `SOAK OK: NaN moves undone 0; 1 game-day(s) in 53 s wall; deaths 2, kills 10, waves 0, swings 30, gear 2, pieces 779` (54 s). Three game-days: `SOAK OK: NaN moves undone 0; 3 game-day(s) in 176 s wall; deaths 7, kills 25, waves 1, swings 36, gear 2, pieces 778, bag taken`. Static memory 113 MB after hour 1 and 124-125 MB at the end; the worst physics frame in any hour 2.2 ms; first navmesh bake 42-47 ms.

**Tests:** `test_zombie_world.gd`: a zombie whose body is put on a NaN position is back on a finite one next to where it was, its brain too, the guard counted it, and it keeps chasing; zombies and the player take no platform velocity. **4713 checks** (was 4706).

**Try it on the PC:** merge, then in Git Bash in the game folder:
- `tools/soak.sh` (about a minute) or `tools/soak.sh --days=3` (about three minutes): watch the hourly lines; the last line says SOAK OK.
- `tools/tour.sh`, then open `.shots/tour/contact.png`.
- `play.bat`, get into the first car (E), get out again and let a zombie follow you round it: it keeps walking instead of freezing in place.

**Known gaps:**
- The bot dies a lot: 2 deaths on day 1 and 7 in three days, mostly to the 8 street zombies and the zombie in house 1 while it walks or searches (it only swings when one is within 2.2 m). Not a bug, but worth watching in Playtest #1. Repro: `tools/soak.sh --days=3`, the `deaths` column.
- Zombies break town furniture and doors while chasing: a town door (`w:-4:-14:w`) at 08:29 and house 1's kitchen counter (`o:6:-13`) at 13:12 on day 1, every run. Probably fine (it is what they do); listed so nobody is surprised. Repro: `tools/soak.sh`, the "piece gone" lines.
- Heat and infamy climb fast from the starter factory: heat 0 to 145 within the hour the smelter, press and unmuffled generator start (day 1 13:00-14:00) and infamy 2 to 187 in that hour; infamy 200 to 405 in the first hour of the day-2 dusk run. Not tuned here. Repro: `tools/soak.sh --days=3`, the 14:00 and day 2 22:00 lines.
- No wave comes from heat alone: waves need a running machine (`noise.continuous`), so heat 100 with the factory out of scrap and fuel sends nothing, and on day 1 the heat (145 at 14:00) has decayed to 25 by dark with no wave. Repro: the day-1 lines (waves 0), or `play.bat --heat=100` with no machines.
- With `--demo-factory` the orange heat warning ("The noise is being noticed") sits on the same line as the carry weight, right after "0.7 / 20 kg", in the top-right HUD. Repro: `tools/shot.sh f --demo-factory --advance=7.5 --time=12 --cam=0,0,6,0,-25`.
- Inside the factory hall the day fog is as thick as outside, so Old Pete is grey at 7 m. Repro: `tools/shot.sh hall --time=15 --cam=0,0,-116,0,-5`. CLAUDE.md's factory camera (`--cam=-3,0,-100,30,10`) looks at the hall's outside wall, so the tour uses this one instead.
- The `--demo-defense` night shot from CLAUDE.md's camera is very dark apart from one floodlight. Repro: `tools/shot.sh night --demo-defense --time=22 --advance=1 --cam=7,0,-13,148,-14`.
- The bot's sleep at 22:00 woke at energy 56-58 (a zombie or bleeding wakes you) and it never slept again, so energy sat at 0 from day 2 evening. The bot's limit, not the game's.
- The parked car's NaN platform velocity is an engine quirk (it reads NaN once, right after you get out) and is not fixed at its source; only its effect is.
- Every other gap from the P3, P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — P3 Playtest readiness

From the P3 brief by the project lead, on top of P2 (PR #31). No new content, no tuning: the game explains itself, and the session log says what happened.

**Built:**
- **A controls screen.** **F1** (or **Controls** on the title screen and in the pause menu) lists every control in seven groups: Move and look, Use and search, Build, Fight (pipe and guns), Cars, Screens, Game. The keys come from the actions the game registers, and every description lives in one table, so a new key without a description fails a test. F1 or Esc closes it. Opened in play the game keeps running underneath, like the other screens; opened from the title or the pause menu it goes back there. It fits a 1280x720 window.
- **A key hint line that fits the moment.** The crowded line of twenty keys at the bottom is now one short line of what applies: on foot WASD, E use, B build, Tab gear, K skills, L log, F light and F1 help; with a gun in hand LMB fire, R reload, RMB zoom (only with a scope fitted, since without one right click does nothing) and Q pipe; with the pipe in hand LMB swing (and Q gun if you own one); in build mode the piece keys, R rotate, LMB place, RMB remove, B leave; in a car its keys; looking at a machine, crate, door, turret, sensor or car, that thing's keys come first (E search, U fit muffler, T repair, R make...). It never goes past 110 characters: the least useful keys drop off the end, and F1 help is always last.
- **A fuller session log** (now under 55 lines, was 40). New lines: gear found by rarity (searches and zombie drops) and what you wore at the end; skill levels gained and perk points earned and spent (and on what); shots, hits and kills for each gun (the three you fired most); the five base-log events that mattered most while you were more than 40 m from them (destroyed, then under attack, waves, out of ammo, Old Pete, worn suppressors, traps and tripwires, then kills), with how many there were in all; and the houses you went into. The first-five-minutes timeline stays, and now also shows levels, perks and houses.
- **Town pieces salvage, they don't refund.** Pulling down a door the town put in gave its full build cost (6 planks and 8 nails, across 24 doors), a bed 6 planks and 10 nails (12 beds). Now every piece the town laid (houses, beds, the factory hall, furniture) is marked as the town's, and pulling one down gives its salvage: **2 planks** for a town door, **3 planks and 1 scrap** for a town bed; town walls, floors, windows and furniture give what W1a and W1c set (a plank, or a plank and a scrap). Pieces you build still give everything back.
- **A crosshair you can see in fog.** The ticks are 12 x 3 px (were 10 x 2) with a darker edge (80%, was 45%). Checked against the noon fog and at 22:00.

**Rules (sim, tested):** `data/buildables.json`: door `"salvage": {"plank": 2}`, bed `"salvage": {"plank": 3, "scrap_metal": 1}`; `GameData` loads and checks `salvage`. `BuildGrid.refund_for(piece)` (the salvage for a `"town": true` piece that has one, else the cost); `remove()` uses it. `SimWorld.place_town`, `place_factory` and `place_props` mark their pieces `"town": true`. **Saves:** `SaveGame.VERSION` is 10: pieces carry `"town"`. A version 3-9 save gets the flag on every piece standing where the seed's town plan puts one of the same kind (`_mark_town`); older ones get the town laid fresh, already flagged. `test/fixtures/save_v9.json` was written by the P2 code before these changes (the seed-1 town plus a door the player built at cell 0,0). `RunStats`: `note_gear`, `worn`, `note_level`, `note_perk_points`, `note_perk`, `note_shot`, `note_gun_hit`, `note_away` (keeps the five heaviest by `AWAY_WEIGHTS`), `note_house`, and the new summary lines. `SimWorld` feeds them from searches, zombie drops, practice, `spend_perk()` (new: the skills screen spends through it), `fire()`, `shoot_zombie()`, the base log's new entries (radio or not) and `know_houses(plan)` (checked every half second). World: `HelpScreen` (new, `src/world/help_screen.gd`), the `help` action (F1) in `InputSetup`, "Controls" buttons in `Menus`, `main.gd` (`key_hint_text()`, `fit_key_hint()`, `KEY_HINT_MAX`, F1, `--help`), `Interactor.keys()`, `SessionLog` fills in what you wear, `Crosshair` sizes.

**Tests:** `test_help_screen.gd` (new: every registered action has a row with a description and every row's actions are registered, every group has a column, keys come from `InputSetup`; in the real game F1 opens it with every row on screen and the game running, F1 and Esc close it without opening the pause menu, Controls on the title and in the pause menu go back there; the key hint line on foot, with a gun drawn and in build mode changes and holds only that moment's keys, stays one line under 110 characters, and a crowded line is cut to fit with F1 help last). `test_town_salvage.gd` (new: every town piece is flagged, 24 doors and 12 beds; a town door gives 2 planks and no nails, a town bed 3 planks and a scrap, a town wall its 1 plank and 1 scrap; your door gives back 6 and 8, your bed 6 and 10; the flag survives save and load and a loaded town door still salvages; the version-9 fixture loads with its 24 town doors flagged and the player's door not, and the older fixtures still load). `test_run_stats.gd` (gear by rarity, nothing counted while muted; levels and perk points from practice, a perk spent; shots and hits per gun; seven far events kept as the right five in order, a near one not counted; a house entered twice counts once, by a plain name). `test_session_log.gd` (the log is under 55 lines and shows the new lines; with every list at its longest it is still at most 55 and keeps the timeline). `test_automated_defense.gd` checks the current save version instead of 9. **4706 checks** (was 4371).

**Try it on the PC:** merge, then in a terminal in the game folder:
- `play.bat`, then **Controls** on the title screen. Start a new game and press **F1**; F1 or Esc closes it.
- `play.bat --gun --time=12`: the key line at the bottom shows the gun's keys; press **Q** for the pipe and it changes; press **B** and it shows the build keys. Look at the bright fog through the crosshair.
- `play.bat --inside=0 --time=12`: you're in a house. Press **B**, look at its front door and right-click: you get 2 planks, not 6 planks and 8 nails.
- Play a while, quit to the title, and open the newest file in `%APPDATA%\Godot\app_userdata\Noise Floor\sessions\`: the new lines are under the loudest sounds.

**Known gaps:**
- "Gear found" counts a zombie's drop when it drops, whether or not you pick up the bag.
- How much a base-log event matters is read from its words (`RunStats.AWAY_WEIGHTS`), so a new kind of event counts as 1 until it gets a weight.
- The house check is the cell you stand in, so standing in a doorway can count as going in.
- In a car the key line doesn't show R hotwire; the car's own prompt above it still does.
- Build mode's top-left line still lists the build keys too.
- In a pre-P3 save, a town door you pulled down and rebuilt yourself in the same spot counts as the town's (only its refund changes).
- Every other gap from the P2, M15 and M14 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — P2 Gun feel and screens

From the P2 brief by the project lead, on top of M15 (PR #30). A small polish pass: no new content, no tuning.

**Built:**
- **One roll, not two.** A shot used to need the ray inside the spread cone to meet a zombie *and then* a hit-chance roll by distance, which felt harsh (a scoped rifle could land the ray and still "miss"). Now the cone is the only roll: what the ray meets is hit. Everything that used to change the hit chance now changes the cone instead: **Firearms** (3% tighter a level, as before), the **scope** and "+% accuracy at range" rolls (a gun with +60% range has a cone 1/1.6 as wide), **recoil** (each shot widens it, it settles back in a second or two) and **distance** (the same cone covers more ground further out: a pistol's cone is about 0.4 m across at 10 m and 1.7 m at 40 m, so far shots still mostly miss).
- **A crosshair.** With a gun in hand four small ticks replace the centre dot. Their gap is the cone's real size on screen, so it opens after each shot, closes as you steady, and is tighter with a scope, with Firearms levels, or zoomed in. With the pipe in hand you get the old dot back. It never catches the mouse.
- **Scope zoom.** Hold **right click** with a scoped gun in hand to zoom in (75 to 35 degrees); let go to zoom out. Without a scope right click does nothing (in build mode it still removes pieces). The scope's tighter cone is always on, zoomed or not, so the zoom is for seeing.
- **The skills screen fits small windows.** The three perk trees now sit side by side, each with its perks' text wrapped to its column, and each tree (and the skills list) scrolls if the window is too short. It reads at 1280x720 as well as 1600x900, with six Fighter perks.
- **`noise.refresh` is back to its old cost.** The M15 stress run measured it at about 448 us a tick against 82 before. The cause was M12's Dampened Gears: every working machine and every running generator asked the skills for its "machine quiet" bonus, and that question walks all ten skills, every perk and (since M13) all your gear and gear sets. With 50 machines that was 50 walks a tick. It is now asked once a tick. Stress run on Emmitt's PC after the fix: **95 us** (town + 200 zombies), 94 (empty map), 96 (town + 20); average tick 3.2 ms (was 3.8), worst 11.4 ms. Turrets, furniture and the cache invalidation were not the cause (the empty map, with no town and no turrets, measured the same 446 before).
- Two new game flags for screenshots: `--aim` (fits a scope and holds the zoom) and `--window=1280x720` (a smaller window).

**Rules (sim, tested):** `Gunplay`: `hit_chance()` is gone; `sight_mult()` (base gun range / this gun's range, 0.1-1) now multiplies `spread_deg()` with `spread_mult()` (Firearms) and the recoil bloom; `cone_radius(distance)`; `scoped()` (a working sight part on the gun in hand). `SimWorld.shoot_zombie(id, head)` no longer takes a distance or rolls: a live zombie the ray met is hit. `data/guns.json` loses `hit_chance`. The Firearms skill's text no longer mentions hit chance. `NoiseField.refresh` and `PowerGrid.noise_sources` ask `Skills.bonus("machine_quiet")` once a tick (`machine_loudness(m, quiet)` takes it as an optional argument). World: `Crosshair` (new, `src/world/crosshair.gd`), `Shooter` (the `aim` action on right click, `aiming()`, `hold_aim`, the FOV zoom), `SkillsScreen` (trees in columns, scrolling, `fit()` on open and on a window resize), `InputSetup` (`aim`), `main.gd` (crosshair or dot, `--aim`, `--window`, "RMB scope" in the key hints).

**Tests:** `test_guns.gd`: the hit-chance test and the "mostly misses at 40 m" roll are gone; new: every shot the ray lands at 40 m hits (200 of 200), the cone is 4x as wide at 40 m as at 10 m, a dead or missing zombie can't be hit; Firearms 5 gives a 15% smaller cone than Firearms 0, a scope makes it 1/1.6 as wide, a shot's recoil grows the scoped cone and it settles back, a rifle's cone is far tighter, a holstered gun is never scoped. `test_guns_world.gd`: right click without a scope leaves the FOV at 75, with a scope it zooms to 35 while held and comes back on release, `--aim` holds it, the pipe in hand drops it; in the real game scene the crosshair is hidden and the dot shown with the pipe, the crosshair (and its ticks) ignore the mouse, a gun shows the crosshair and hides the dot, its gap matches the cone on screen, opens after a shot and closes as it settles. `test_skills_screen.gd`: at 1280x720 with six Fighter perks the panel fits the window, the three tree columns and the skills column sit inside it without overlapping, every perk row fits its column's width and doesn't overlap the one above, and a taller window gives the trees more room. **4371 checks** (was 4285).

**Try it on the PC:** merge, then in a terminal in the game folder:
- `play.bat --gun --time=12`: the crosshair. Fire a few quick shots at the street and watch it open, then close as you steady. Press **Q** for the pipe: the dot comes back.
- `play.bat --gun=rifle --aim --time=12`: a rifle with a scope fitted, held zoomed in (`--aim` holds the zoom for you). For the real thing, `play.bat --workbench --time=12`, fit the scope at the bench, close it, then hold **right click**.
- `play.bat --skills --window=1280x720`: the skills screen in a small window; scroll the Fighter tree with the mouse wheel.

**Known gaps:**
- Mouse look is not slowed while zoomed, so aiming at 35 degrees feels twitchy. Worth a look at the playtest.
- The zoom doesn't tighten the cone further: the scope's tighter cone applies whether or not you zoom. Decided so hip-firing a scoped gun didn't get worse; change it if the playtest wants "aim down sights" to matter.
- The crosshair is a fixed white; it doesn't turn red over a zombie or show a hit marker.
- The skills screen's columns are fixed widths (350 and 3 x 250 px), so on a very wide window it doesn't spread out, and below about 1220 px wide it would run off the sides.
- Every other gap from the M14 and M15 lists stands.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M15 Automated defense

From the M15 brief by the project lead, on top of M14 (PR #29).

**Built:**
- **Turrets fed by belts and hoppers.** A belt ending at a turret pushes its ammo in (as since M8, from any side), and E still loads it by hand. A new **ammo hopper** (4 planks + 6 nails, on a foundation) holds up to 100 rounds of one kind and feeds the turret on the cell in front of it, one round a tick; E loads it from your pockets and crates, and a belt can top it up.
- **Two new turrets.** The **crossbow turret** shoots **crossbow bolts** (the Press's new recipe: 1 plate makes 6): near silent (20), slow (one every 2 s), 60 damage, 20 m. The **rifle turret** shoots M14's **standard rounds**: loud (85), 50 damage every 1.5 s, 35 m, and it needs **20 W** of power. Shots still go through the noise system, so loud defense draws more dead.
- **Suppressors and scopes on turrets.** E on a turret with one in your pockets fits it: an oil-filter suppressor takes the rifle turret from 85 to 65 (the machined one to 55) and wears 0.5% a shot as on a gun; a scope adds 60% range. Pulling the turret down gives them back.
- **Sensors and one action each.** A **motion sensor** sees zombies within 12 m (walls and closed doors block it); a **noise sensor** hears one-off sounds of 30 or more within 20 m (not your machines' hum, not the noisemakers). **E** opens a small screen to pick its action: **quiet mode** (every machine and generator on the sensor's power network stops until it clears, plus 30 s), **floodlights** (every floodlight within 20 m comes on, at night only), **decoy** (every charged noisemaker within 60 m goes off) or **lock doors** (every door within 12 m shuts and E can't open it until 10 s after it clears).
- **Floodlight** (10 W, a pole with a lamp): lit only at night, by a sensor or set to light every night with E. Standing within 10 m of a lit one counts as having your flashlight on: zombies see you from further. **Noisemaker** (15 W, a box with a horn): once set off (by a decoy sensor, or E) it blares at 90 for 20 s, then needs 60 s of power to recharge. Zombies that hear it go there instead of your walls, and wreck it if they reach it.
- **Base log and radio.** The sim keeps the last 50 events with the game time: turret kills, a turret out of ammo, your walls, doors and machines under attack ("West wall under attack: 6 zombies", at most once per 30 s each) or destroyed, sensors going off and what they did, noisemakers, bear traps and tripwires, the repair station's work, waves arriving and Old Pete on the move. **L** (or **Base log** in the pause menu) opens it. A **handheld radio** (in the starting crate) in your pockets turns any event more than 40 m from you into a HUD line ("Radio: Nail turret out of nails").
- **Traps.** **Bear trap** (2 plates + 4 nails, on bare ground): the first zombie into its cell takes 10 and is pinned for 15 s; then it's sprung until you reset it with E. **Tripwire bell** (an edge piece, 2 nails + 1 scrap): a zombie crossing it rings it at 60 and sets off every sensor within 20 m. **Electric fence** (an edge piece on a power network, 15 W): a zombie touching it is stunned for 3 s (no walking, no biting) and takes 10; in a brownout it does nothing.
- **Repair station** (20 W, a machine body): takes **wall panels** by hand or from a belt (the Press's other new recipe: 2 plates make 1 panel) and every 10 s gives 50 hp back to the most damaged wall, door, barricade or fence within 12 m.
- **The Director's cache** (from the stress report): each continuous sound's outdoor wall count is kept until the build grid changes (a piece added, removed, opened or broken), so the once-a-second heat check no longer walks 8 x 50 m per machine. Same heat numbers as before.
- `--demo-defense` now also has a hopper behind the turret, two floodlights (set to light every night), a motion sensor on decoy, a noisemaker 30 m east on a pole line, a generator, a bear trap and two tripwires.
- **Models:** no Blender runs. The crossbow and rifle turrets reuse the nail turret's model with a bow or a long barrel added to the head in code; the floodlight is the power pole with a lamp box; the repair station is the purifier's body with a stack of panels on top. The hopper, sensors (a lamp that goes red when triggered), noisemaker (a lamp that flashes while it blares), bear trap, tripwire and fence are plain coloured boxes with a few parts. Bolts, wall panels and the radio have no icons yet.

**Rules (sim, tested):** `data/defense.json` (new): hopper cap and what it feeds, turret part slots, sensor check interval and noise threshold, the four actions (name, hold, radius, the screen's text), floodlight light radius, noisemaker blare, recharge and pulse, bear trap pin, tripwire trigger radius, fence stun and reach, repair station panels and hp, log size and attack throttle, radio range. `data/buildables.json`: the 11 new pieces (turret numbers stay here). `Factory`: `Turret.id` and `parts`; `Bin` (hoppers and repair stations: one item, a cap, fed by hand or belt); a hopper hands one round a tick to the turret in front. `PowerGrid`: any powered piece is a consumer (`wants`, `is_powered`); sensors join networks; `switched_off` for quiet mode. `Defense`: turret power, parts (`turret_stats`) and suppressor wear, bear traps (`sprung`, `reset_trap`), tripwires (`bells`), fences, repair stations, `most_damaged`, and a per-kind key cache so traps don't scan every piece each tick. **`Automation`** (new): sensors (`sense`, `set_action`), the actions, floodlights (`lit_positions`, `in_light`), noisemakers (`fire_noisemaker`), locked doors. **`BaseLog`** (new): entries with game time, `add_once` throttling, directions from the middle of your base. `ZombieBrain`: `pinned` (can't walk) and `stunned` (does nothing). `NoiseField`: `outdoor_walls`; a stopped machine (brownout, quiet mode) is silent. `Director`: the wall-count cache (`watch(build)`, `recounts`). `BuildGrid`: tripwire and fence are edge pieces that stand on bare ground and block neither sound nor sight; sensors, floodlights, noisemakers and bear traps stand on bare ground. `SimWorld`: wiring, `turret_interact`, `set_sensor_action`, `toggle_floodlight`, `fire_noisemaker`, `reset_trap`, locked doors in `toggle_door`, the radio, wall-hit, destroyed, wave and Old Pete log entries; the start crate gets a radio. **Saves:** `SaveGame.VERSION` is 9: turret parts, hoppers and repair stations (`bins`), sensors with their actions, floodlights' night setting, noisemakers, locked doors (`automation`), sprung traps and the base log. `test/fixtures/save_v8.json` was written by the M14 code before these changes and loads with none of these; the older fixtures still load.

World: `SensorScreen` and `BaseLogScreen` (new), `DefenseView` (new: floodlight spotlights and lamps, sensor and noisemaker lamps), the new pieces in `BuildView` (walk-over layer for bear traps and tripwires) and the build menu (mouse wheel, after the workbench), `Interactor` prompts and E actions for each, `L` in `InputSetup`, a "Base log (L)" pause button, `SoundView` plays the horn for a noisemaker and a click for a tripwire bell.

**Tests:** `test_automated_defense.gd` (a belt feeds a nail turret and it kills with those nails; the hopper loads 100, feeds one a tick, holds one kind, takes a belt; the crossbow's 60 / 2 s / 20 m / 20 and the rifle's 50 / 1.5 s / 35 m / 85, the rifle turret silent without power and drawing 20 W with it; a suppressor on a rifle turret: 65 loud, 0.5% wear a shot, a scope 56 m, parts back when it's pulled down; a motion sensor sees a zombie, quiet mode stops the generator and smelter and silences them, logs it, and they're back 30 s after it clears; walls block a motion sensor; a noise sensor's range and threshold; a decoy sensor sets off a noisemaker that pulls an investigating zombie away from a wall, blares 20 s at 90, then recharges 60 s; lock doors shuts a door, E can't open it, it opens 10 s after; floodlights dark and drawing nothing by day, lit and drawing 10 W at night, you stand in their light; the base log records a wall hit once with the game time and a turret kill, keeps 50; the radio calls out a turret out of nails 200 m away but not 10 m away, not without a radio, and the start crate has one; a bear trap pins for 15 s, catches nothing sprung, resets; a tripwire rings at 60 and sets off a sensor that can't see the zombie; an electric fence stuns and hurts, and does nothing in a brownout; the repair station spends a panel for 50 hp every 10 s, takes panels from a belt; the Press's bolts and panels; the Director's cached gain equals the uncached one, isn't recounted when asked again, and is after a wall goes up; save and load keeps sensor actions, floodlight setting, hopper nails, turret ammo and suppressor, sprung traps and the log; the version-8 fixture loads with none of it and the older fixtures still load), `test_automated_defense_world.gd` (the sensor screen lists four actions and a click picks Decoy; the base log screen lists newest first with times; every new piece gets a body, walk-over ones on the trap layer, the rifle turret's barrel, a lit floodlight's spotlight). `test_gear.gd` (the Press now cycles through bolts and panels), `test_guns.gd` (saves are version 9 now) and `test_art_models.gd` (the floodlight is a pole with a crossbar) updated. **4285 checks** (was 3995).

**Stress (`tools/stress.sh`, this PC, 4 game hours from 19:00):** worst tick 20.0 / 23.0 / 23.2 ms before (the 2026-10-13 report) and 11.7 / 11.2 / 9.7 ms now (town + 200 zombies / empty map + 200 / town + 20); average 4.63 -> 3.78 ms with the town and 200 zombies. `gain_now` costs 26 us from the cache, and 930 us when it has to recount everything (10,410 us before: the 8-direction walk now also stops at the first open side). The script has a new "gain_now us (recount)" column. Not looked into: `noise.refresh` measured 448 us here against 82 us in that report (M12-M14 sit between the two runs).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- The defended base at night: `play.bat --demo-defense --time=22`. Walk round to the barricade side: two floodlights, the turret with a hopper of nails behind it, spikes, a bear trap and two tripwires. Wait for the street zombies; look at the motion sensor (a short pole with a box, just west of the walls): its lamp goes red and the noisemaker 30 m east starts blaring. Press **L** for the base log.
- The sensor screen: `play.bat --demo-defense --time=12 --sensor-screen` (or E on any sensor). Click an action.
- The base log screen: `play.bat --base-log --time=12` (it fills in some example events).
- Build your own (B, mouse wheel past the workbench): crossbow and rifle turrets, hopper, motion and noise sensors, floodlight, noisemaker, bear trap, tripwire, electric fence, repair station. The Press (R on it) now also makes crossbow bolts and wall panels. Walk 40 m away from your base with the radio in your pockets (take it from the starting crate) and wait for the HUD's "Radio:" lines.

**Known gaps:**
- Not in M15, as planned: outposts (M17), the shotgun turret (there's no shotgun yet), turrets aiming at the player, and anything needing Codex (icons for bolts, wall panels and the radio).
- No new models (see Models above); a proper bell sound isn't synthesized yet (the tripwire uses the click).
- Turrets still take ammo from a belt on any side, not only the back (kept from M8, so old belt layouts keep working). The rifle turret takes standard rounds only (no subsonic).
- A part comes off a turret only by pulling the turret down. Parts on a turret don't show on its model.
- The noise sensor ignores continuous hums (machines, generators, engines) and the noisemakers' blare, so a sensor next to your factory doesn't keep switching it off, and a decoy can't set itself off.
- A noisemaker's blare is a string of one-off sounds (zombies hear it and come to wreck it; it adds to infamy), not a continuous source, so it doesn't add Director heat and the Director's waves still head for your loudest machine. Decided so one decoy at night doesn't summon a horde on its own; worth a look at the playtest.
- Floodlights make you "lit" within 10 m (like your flashlight); they don't light zombies up for turrets (turrets see in the dark already).
- Fences and tripwires on bare ground stand at foundation height, so they float 10 cm. Zombies bash a fence like a barricade; it blocks neither sound nor sight.
- Directions in the base log are from the middle of everything you built, so a town-sized base gives coarse directions. Only pieces you built are logged as under attack.
- Every number in `data/defense.json` and the new pieces is a first guess. Tune after the playtest.

**Next:** Playtest #1; then M16 seasons after the playtest.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M14 Guns

From the M14 brief by the project lead, on top of W1c (PR #28).

**Built:**
- **Two guns, both gear:** a **pistol** and a **hunting rifle**, in a new **gun** slot (the weapon slot stays melee). **Q** swaps what's in your hands, pipe or gun; the top-right HUD line says which ("Gun: Pistol 7/8 standard rounds (Q: Pipe)"). Raising a gun takes a moment (pistol 0.35 s, rifle 0.8 s).
- **Guns are loud.** Pistol 85, rifle 95: louder than a generator. A shot is a one-off noise where you stand, so it carries across town (a zombie 400 m away comes to look), raises the Director's heat and your infamy like any other sound.
- **Shooting:** left click fires. The game shoots a ray from the camera inside a cone as wide as the gun's spread; if it meets a zombie, the chance to hit falls with distance (pistol: half the time at 18 m, nearly always close up; rifle: half at 50 m). Headshots double. Each shot kicks the spread wider (recoil), and it settles back in a second or two. A brief muzzle flash, a recoil kick on the camera, and new shot sounds.
- **Magazines and ammo:** pistol 8 rounds, rifle 5. **R** reloads when you're on foot with a gun in hand (in a car R still refuels and hotwires; looking at a Press it still switches the recipe). Rounds are a stackable item per type: **standard**, **subsonic** (15 quieter, 25% weaker) and armour-piercing (in the data, does nothing yet). With no rounds of the loaded type, or a full magazine and another type in your pockets, R switches type and gives back what was in it.
- **Parts (gear, carried in pockets, fitted at a workbench):** muzzle (**oil-filter suppressor**: 20 quieter, wears 0.5% a shot; **machined suppressor**: 30 quieter, barely wears), **extended magazine** (+50% rounds), **scope** (+60% accuracy at range), **padded stock** (35% less recoil). Parts roll rarity and gun stats like other gear (+5-20% gun damage, 2-6 quieter shots, +5-20% accuracy, 5-20% less recoil). A gun's numbers are its base plus its parts, shown in Tab and at the bench.
- **The workbench:** a new piece in build mode (the last one, 6 planks + 10 nails). **E** opens it: your gun and its four part slots (click a slot to take a part off), the parts in your pockets (click to attach), and what it makes by hand from your pockets and crates nearby: **10 standard rounds** (10 casings + 1 scrap), **10 subsonic rounds** (10 casings + 2 scrap, needs Gunsmith), the **oil-filter suppressor** (3 scrap + 6 nails), the **machined suppressor** (4 plates + 2 scrap + 10 nails, needs Gunsmith) and a **padded stock** (2 planks + 6 nails).
- **The factory supplies the armoury:** the Press has a third recipe, **ammo casings** (1 metal plate → 10 casings, 3 s); R on a press cycles nails → repair kits → casings.
- **Firearms levels now:** 1 xp a shot, 3 a hit, 6 a kill; each level makes your spread 3% tighter. **Three new Fighter perks:** **Steady Hands** (8% less recoil a rank), **Quick Hands** (reloads 10% faster a rank) and **Gunsmith** (rank 1 unlocks subsonic rounds and the machined suppressor; each rank makes suppressed shots 2 quieter).
- **Where guns turn up:** car trunks (5% a gun, pistols three times as often as rifles, 2% a part, 25% a handful of standard rounds), factory crates (15% a part, 30% rounds), and a 2% Police-tier gun or part in any search. **Old Pete's Deer Rifle** (gold: +15-30% gun damage, +1-2 to Fighter perks, 5-10 quieter, and a threaded barrel: suppressors on it wear half as fast) is a **second drop from Old Pete**, with 10 rounds, in the same bag as his axe.
- **Models:** `tools/art/pistol.py` and `tools/art/hunting_rifle.py` (kit models, flat colours) held in view at the lower right like the pipe.

**Rules (sim, tested):** `data/guns.json` (new): gun bases (damage, range, spread, recoil, settle, handling, magazine, loudness, cooldown, reload, knockback, wear per shot, sound), part slots and parts, ammo types, hit-chance clamp, finds per loot table, the police find, gun and part weights, Old Pete's extra drop. `data/gear.json`: slot `gun`, gun and part bases, five gun-only stats (with `"slots"`; ordinary gear never rolls them and ordinary finds never roll guns or parts, so M13's seeded rolls are unchanged), the unique. `GameData` loads and validates guns.json, workbench recipes (`station`, `perk`, `gear` out), the `workbench` kind. `Gear`: gun pieces carry `parts`, `loaded`, `ammo`; `gun_stats(piece)` is the one query for base + tier + own rolls + working parts (the rules, the inventory screen and the workbench all read it); `attach`/`detach`, `wear_shot`, `roll_gun_piece`; gun-only stats never count in `bonus()`. **`Gunplay`** (new, `src/sim/gunplay.gd`): hands, raise time, cooldown, recoil bloom and settle, `spread_deg`, `hit_chance(d)` = 1 - 0.5 (d / reach)^2 clamped to 5-97% (reach = range / Firearms spread multiplier), `shot_loudness` (gun + parts + ammo - Gunsmith on suppressed shots), `damage`, reloads and ammo switching, the HUD line. `SimWorld`: `swap_hands`, `fire` (round, bloom, wear, noise through `noise.emit` minus Night Shift's quiet_all, Firearms xp), `shoot_zombie(id, head, distance)` next to `hit_zombie`, `reload` (a 15-loud click), `attach_part`/`detach_part`, `bench_recipes`/`can_bench_craft`/`bench_craft`, `_search_guns` (its own seeded stream), Old Pete's second drop. **Saves:** `SaveGame.VERSION` is 8: guns with their parts, rounds and ammo type ride inside `gear`, plus `hands`. `test/fixtures/save_v7.json` was written by the W1c code before these changes and loads with an empty gun slot; the older fixtures still load.

World: `Shooter` (new) does the raycast in the spread cone, the headshot test, the gun models, muzzle light and kick; `Melee` stands down while the gun is out; `WorkbenchScreen` (new); `Interactor` opens it on E and reloads on R; `InputSetup` adds Q (`swap_hands`); `SoundView` plays `shot_pistol`, `shot_rifle`, both suppressed, and `reload`, made by `tools/audio/synth.py` (new `--only` flag, so the other sounds weren't regenerated).

**Tests:** `test_guns.gd` (guns.json validates and a broken gun base is caught; base + parts: magazine 12 with the extended mag, range x1.6 with a scope, recoil x0.65 with the stock, 65 with the crude and 55 with the machined suppressor, Police x1.25, rolled gun stats count once; loudness 85 / 65 / 50 with subsonic / 46 with Gunsmith 2, and nothing off an unsuppressed shot; hit chance near 1 close up, 0.5 at range, floor 5%, higher with Firearms 5 and a scope; spread grows with each shot, settles back, kicks less with a stock and Steady Hands, 30% tighter at Firearms 10; empty click, reload time and rounds from pockets, top-up, type switch, Quick Hands, rounds back when the extended mag comes off, Q and raise time; wear 0.2% and 0.5% a shot, a worn-out suppressor stops working, a threaded barrel halves it; a pistol shot is heard 400 m away and raises infamy, a suppressed subsonic one 25 m away but not 60 m; damage, headshots, Firearms xp for shots, hits and kills, mostly misses at 40 m; workbench cost, recipes, the Gunsmith gate; the Press makes casings; trunk and crate finds, rifles rarer, Police finds, same seed same find, guns roll only gun stats; Old Pete's rifle and its stats; save and load keeps guns, parts, wear, rounds, ammo and hands; the version-7 fixture loads with no gun), `test_guns_world.gd` (physics: a pistol fired from the camera at a placed zombie kills it in a few shots; the model shows only with the gun out, a shot at the sky misses, the camera kicks and settles, R through the interactor reloads; both models load and are long front to back; every shot kind has its sound; the workbench screen attaches a suppressor by click, shows it in the muzzle slot, makes rounds, and takes it off). `test_gear.gd` and `test_skills.gd` updated for the gun slot, the casings recipe, Old Pete's second drop and the enabled Firearms skill. **3995 checks** (was 3794).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- A pistol straight away: `play.bat --gun --time=12`. Left click shoots, **R** reloads, **Q** swaps to the pipe and back. Shoot near the street zombies and watch the rest of the street come (N shows the noise rings). The rifle: `play.bat --gun=rifle --time=12`; Old Pete's: `play.bat --gun=pete --time=12`.
- The workbench screen: `play.bat --workbench --time=12`. Click **Scope** to fit it, click **Muzzle** to take the suppressor off, make some rounds.
- The whole chain: `play.bat --demo-factory --time=12`. Look at the press and press **R** twice ("Press now makes Ammo casings"), take metal plates from the crate by the spawn and **E** them into it. Build a **workbench** (B, scroll to the last piece), **E** on it and make standard rounds.
- Old Pete's rifle: `play.bat --cam=-1,0,-115,0,4 --time=12`, kill him, E on his bag, then Tab and **Equip** the rifle.
- Gunsmith: K, Fighter tree (needs a perk point).

**Known gaps:**
- Not in M14, as planned: belts feeding ammo and an automatic bench (M15), turrets using guns (M15), armour-piercing effects (needs brutes), gun repair beyond the repair kit (a kit works on a gun from Tab; a part has to come off the gun to be repaired).
- Bench recipes are made instantly by hand (each has a time in recipes.json for when M15 automates them).
- No crosshair, so the spread is felt rather than seen. A shot has two rolls: the ray in the cone must meet the zombie, then the sim's hit chance by distance.
- Parts don't show on the gun model (a suppressed pistol looks the same), and the scope doesn't zoom. Gun, part and ammo icons are placeholders (the rarity tile with a letter; ammo a colour).
- Old Pete's rifle comes only from killing him, so a version-7 save where he's already dead has no way to get it yet. Police-tier guns only come from the 2% police find; there's no police station.
- Shots don't go through a zombie into the next one, and don't damage walls. You can't shoot from a car.
- The Fighter tree now has six perks; the skills screen fits at 1600 x 900 but only just.
- `--shoot` fires before the physics world settles, so its screenshot says "Missed"; it's for the HUD line.
- Every number in `data/guns.json` is a first guess. Tune after the playtest.

**Next:** Playtest #1, then M15 automated defense.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1c Furniture

From the W1c brief by the project lead (the W1b "furniture props" line in `docs/plans/W1.md`), on top of M13 (PR #27).

**Built:**
- **Rooms have furniture now.** Six new Blender-kit models, flat colours, low-poly: a **kitchen counter** with a sink, tap and cupboards (1.76 m), a small **table with two chairs** (1.6 m), a three-seat **couch** (1.76 m), a **bookshelf** with rows of coloured books (1 m wide, 1.8 m tall), a **bathtub** (1.6 m) and a **toilet**. Each stands with its back to a wall and faces into the room.
- **Every house is furnished** (six pieces each, 72 in town): every kitchen has a counter (in the L-shaped house it's under the kitchen window, sink under the glass); living rooms have a couch and a bookshelf; bedrooms keep the bed and get a bookshelf; bathrooms have a bathtub and a toilet in the square house, and one of the two in the smaller bathrooms (the long house a tub, the L-shaped one a toilet). The long house's kitchen-living room has a table; the L-shaped house's table stands in the living room next to the kitchen.
- **The factory hall** has two bookshelves against its north wall and a table against its east wall, well away from the doorway and Old Pete.
- **Furniture is a piece, like a wall.** You bump into it, zombies walk round it (the navmesh reads it) or wreck it if it's in their way, and it's saved with the rest of the town. You can't build it, but in build mode right-click pulls it apart for salvage: 2-3 planks from wooden pieces, a plank and some scrap metal from a bathtub or toilet. Looking at one shows its name and hp ("Kitchen counter · 80/80 hp"); T repairs it like a wall.

**Rules (sim, tested):** furniture is six entries in `data/buildables.json` with `"kind": "prop"`, `"player_placeable": false`, a collision box, modest hp (40-120), a cost that is the removal refund, and a new generic flag `"against_wall": true`. `BuildGrid`: `prop` is an object kind (one per cell, on a floor, facing a side); `center_for` stands an `against_wall` object at the back of its cell (`WALL_HALF` + `WALL_GAP` off the edge) instead of its middle. `GameData` knows the kind and checks a prop fits along one wall (at most 1.8 x 0.9 m) and isn't player-placeable. `TownPlan`: each floor plan lists `"props"` ([id, u, v, wall], placed by hand like the containers), and `generate` returns `"props"` ({id, cell, side (facing), wall, house}); `factory()` returns its three; house zombies never stand in a furniture cell. `SimWorld.place_props(plan)` lays the houses' and the hall's furniture with `restore` (free, muted), skipping a cell that already has an object, has lost its floor or has a zombie in it. Nothing else in `src/sim` knows what furniture is. World: `BuildView.MODELS` draws the six models; `Interactor` treats a prop like a wall (no E action); `--inside=N,PROP` stands you in front of house N's PROP. **Saves:** `SaveGame.VERSION` is 7 (`FIRST_WITH_PROPS`, `holds_props`). A new game lays the furniture with the town. A save from before 7 loads, then gets furnished (after the save is applied, so a crate you built in a kitchen keeps its spot and that counter is skipped). `test/fixtures/save_v6.json` was written by the M13 code before these changes; the v2-v5 fixtures still load and get furnished too.

Where the brief and the houses differed: the brief asked for props never on "a doorway cell", checked by a whole-cell flood fill. The rooms are 2 x 2 cells, and plan A's kitchen holds the back door, the fridge, the cabinet and both doorways in its four cells (its bathroom is only reached through the fridge's cell), so that rule leaves no room for a counter and the whole-cell walk fails on the W1a layout before any furniture. Instead each piece takes the half of its cell along its wall, and the walk test runs on 1 m half-cells: from the front door every free square is reachable and everything has a reachable square beside it, so every doorway keeps a 1 m path. Props are still never on a door's cell, a container's cell or the bed's cell. No container or wall moved.

**Tests:** `test_furniture.gd` (the six are props, not buildable, modest hp, a few planks, drawn from models, and a too-wide prop is caught; same seed same furniture, six per house, a counter and a couch in every house; for seeds 1, 5 and 77 every prop is inside its house, back to a wall (a low one may be under a window), facing the room, not on a door, container, bed or other prop's cell; the half-cell walk test for every house; the hall's two shelves and table against its walls, off the crates and Pete, away from the doorway; `place_props` lays them all once, the box's back is at the wall and on the floor, not counted as your builds; you can't build a couch or build on one; pulling one apart refunds its planks; zombies wreck one at 0 hp; house zombies are never in furniture; a removed and a damaged piece survive save and load), `test_furniture_world.gd` (physics: you walk into a counter and stop in front of it; a zombie up the street comes in through the open front door and bites you at the sink of a furnished kitchen; the real game loads the version-6 fixture furnished, and a second save and load doesn't furnish it twice), `test_art_models.gd` (the six fit their boxes, stand on the floor and are merged; each faces the room: the cupboard doors at the front, the couch's back, the shelf's back panel, the tub's taps and the toilet's cistern at the back), `test_save.gd` (the version-6 fixture loads with its door, gear and pieces, then gets all 75 pieces of furniture, or one fewer with your crate on a counter's spot; the v2-v5 fixtures load and get furnished). `test_gear.gd` now accepts any version from 6. **3794 checks** (was 2367).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**. Walk up the street, open a front door (E) and look round: a counter in the kitchen, a couch and a bookshelf in the living room, a bookshelf by the bed, a tub or a toilet in the bathroom. Walk into the furniture (it's solid). In build mode (B), aim at a couch and right-click to pull it apart for planks. To start in front of a piece: `play.bat --inside=0,counter --time=12` (a counter under a window), `play.bat --inside=6,couch --time=12`, `play.bat --inside=6,bathtub --time=12`, `play.bat --inside=1,table --time=12`. At night: `play.bat --inside=6,shelf --time=22 --flashlight`. The factory's shelves and table: walk to the end of the road and in through the big doorway. An old save loads with its houses furnished.

**Known gaps:**
- Not in W1c, as planned: textures (flat colours only), a shop, a fifth house plan, furniture outside the houses and the hall, and any tuning.
- The rooms are small for one piece per cell: plan A's kitchen has no table (back door, fridge, cabinet and counter fill it), the long house's bathroom has no toilet and the L-shaped one's no bathtub. Bigger rooms or a fifth plan would fix that.
- The counter and couch are 1.76 m, not 2 m, so they fit between the side walls of a corner cell.
- Bathtubs and toilets refund a plank and scrap metal (wooden furniture refunds 2-3 planks), so the town holds a little free scrap. Tune after the playtest.
- Furniture laid into an old save skips any cell you built on and any cell a zombie was standing in when you saved, so a house can be one piece short.
- An open door has no collider, and in some houses an open door lies flat along the side of a couch; nothing clips through, but the swing isn't checked against furniture.
- Furniture doesn't block sight or muffle sound (only walls, doors and windows do).

**Next:** Playtest #1, then M14 guns.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M13 Loot

From the M13 brief by the project lead, on top of M12 (PR #26).

**Built:**
- **Gear is now things you find, each one rolled.** Scrap, nails, food and the like still stack as before. Weapons and things you wear are single pieces, each with its own rarity, rolled stats and condition, in the Diablo 2 colours: **white** (plain), **blue** (1-2 stats), **yellow** (3-5 stats, a random two-word name like "Rust Beacon"), **gold** (a named unique), **green** (a set piece); orange is kept for crafted gear later.
- **Stats roll in ranges:** +10-25% melee damage, +1-2 to Fighter / Ghost / Engineer perks (adds that many ranks to every perk you have at least one rank in, in that tree, and can push a perk past 5), +1-3 Strength (counts as levels for Strength's effects), 5-15 quieter footsteps and swings, +5-15 kg carry, +10-30% durability, +10-25% search speed.
- **Bases and tiers:** weapons pipe, baseball bat, axe and machete (each its own damage and speed); a hard hat or cap (head), hi-vis vest or jacket (body), work gloves (hands) and a headlamp (light), each with a small stat of its own (the hard hat: zombies hurt you 5% less; the cap: footsteps 1 quieter; the vest: +3 kg; the jacket: 8% less damage; gloves: +5% melee; headlamp: +5% search speed). **Police** pieces (15% of finds) have 25% better base stats and one extra rolled stat. Military is reserved for a later area.
- **Five slots you wear:** weapon, head, body, hands, light. **You start holding the pipe** as a white piece in the weapon slot (the M10b gap "the pipe isn't an inventory item yet" is closed). With nothing in the weapon slot you punch.
- **Condition (Mint, Good, Worn, Worn out):** your weapon loses 0.4% per hit, worn gear 3% per game day; durability slows it. Under 25% a piece's rolled stats stop working (its base stats stay) and the HUD says "Your Axe is worn out". A **repair kit** puts it back to mint from the inventory screen.
- **Repair kits come from the Press:** look at a press and press **R** to switch it between nails and repair kits (1 metal plate + 4 nails, 6 seconds). Whatever was waiting in it comes back to your pockets.
- **The first unique, Pete's Fire Axe** (gold): an axe with +15-30% melee damage, +1-2 to Fighter perks and 5-10 quieter. **Old Pete**, a named zombie (bigger, red shirt, 200 hp, hits for 16), stands in the middle of the factory hall facing the doorway, and always drops it. The HUD says "Old Pete drops something gold".
- **The first set, Night Shift** (green): hard hat, hi-vis vest, work gloves, headlamp. 2 pieces: +15% search speed; 3: +10 kg carry; all 4: every noise you make counts as 3 quieter. Set pieces turn up in factory crates, and anywhere as Police-tier finds.
- **Where gear comes from:** a search finds a piece now and then (kitchen and bathroom cabinets 5%, factory crates 25%, car trunks 15%; Lucky Find rolls again), with odds white 70 / blue 20 / yellow 8 / set 2. Zombies drop a piece 10% of the time (runners 20%) in a bag where they fell. The "Found ..." message names it; a gold or green find gets its own message.
- **Inventory screen (Tab):** gear pieces sit in your pockets after the stacks as a rounded tile in the rarity colour with the base's first letter and the condition. Click one to see its name in its colour, what it is, its condition and stats, and **Equip**, **Drop** or **Repair (1 kit)**. A new **Wearing** column on the right lists your five slots in colour; click one to **Unequip** or repair it.
- **HUD:** "Weapon: <name>" under the pocket weight at the top right. The pipe in your hand disappears when you have no weapon.
- **Death:** gear in your pockets goes into your death bag like everything else; what you're wearing stays on you.

**Rules (sim, tested):** `Gear` (`src/sim/gear.gd`, RefCounted) owns pieces `{uid, base, tier, rarity, stats, condition, name, set}`: `pieces` (pockets), `equipped` (slot -> piece), `roll_piece(rng, source)`, `roll_unique`, `roll_stats`, `equip`/`unequip`/`take`/`find`, `weight()` (pocket pieces only), `bonus(effect)` (base stats times the tier, working rolled stats, set bonuses), `weapon_stats()`, `wear_weapon()`/`wear_day()`, `repair(uid, inv)`, `to_dict`/`load_dict`. **Routing:** `SimWorld` gives `Skills` a reference (`skills.gear = gear`) and `Skills.bonus(effect)` adds `gear.bonus(effect)`, uses `effective_level(skill)` (+N Strength) and `effective_rank(perk)` (+N to a tree, only for ranked perks), so every rule still makes its one `skills.bonus(...)` call and none changed. New gear-only effects: `gear_quiet` (footsteps and melee hits in `SimWorld.noise_loudness`, which hits now go through) and `quiet_all` (every noise that goes through `noise_loudness`). `SimWorld`: `carried_kg()` (items + pocket gear; `carry_ratio`, the HUD and the screen use it), `weapon_stats()` from the equipped piece (fists in `weapons.json`), `equip_gear`, `unequip_gear`, `drop_gear`, `repair_gear` (trains Mechanics), `spawn_old_pete()` (at `TownPlan.factory()["pete"]`), `cycle_recipe(cell)`, `_search_gear` (its own seeded stream per container), `_zombie_drop` from `_count_kills` (seeded by zombie id, so car and turret kills drop too), bags carry `"gear"`. `Loot.tick` also returns the table and whether Lucky Find fired. `Factory.Machine.recipe_id` + `Factory.set_recipe`; a buildable's `"recipes"` lists what it can switch to. Data: `data/gear.json` (all the numbers), new weapons, the `old_pete` zombie, the `repair_kit` item and recipe; `GameData` validates gear.json and machine recipe lists. **Saves:** `SaveGame.VERSION` is 6 (gear, gear in bags, a press's recipe). A version-5 save loads with the pipe as a white mint piece in the weapon slot and Old Pete added to the hall (older saves too); `test/fixtures/save_v5.json` was written by the M12 code before these changes, and the v2-v4 fixtures still load.

**Tests:** `test_gear.gd` (gear.json validates and a broken one is caught; the starting pipe; every rolled stat and condition inside its range over 600 rolls, the unique's too; rarity odds over 6000 seeded rolls near 70/20/8/2 and Police near 15%; white 0, blue 1-2, yellow 3-5 stats, Police +1; set pieces rare outside the factory; Police damage x1.25; `Skills.bonus` includes worn gear (carry, melee, search time, the cap's footsteps, +2 Strength as 6 kg) and not pocket gear; +1 to Fighter perks raises Heavy Swing 5 to 6 and Thick Skin 1 to 2 but not an unranked perk or Ghost; Night Shift at 1/2/3/4 pieces; quieter footsteps and hits but not doors; wear per hit and with durability, per day only for worn non-weapons, stats off under 25% with the base kept, repair needs and uses a kit, the worn-out message; the Press switches to repair kits, makes one, gives back its input, and the switch is saved; Old Pete has 200 hp, stands in the hall and drops his gold axe in a bag with the message, which you can pick up and equip; zombie drops land in bags near 10% (runners 20%) and the same seed drops the same; searches find gear, Lucky Find rolls again, fridges hold none; carry weight counts pocket gear only; death drops pocket gear and keeps what you wear; save and load keep pieces, slots, condition, bag gear and uids; the version-5 fixture loads with the pipe and Old Pete, once). `test_inventory_screen.gd` (a yellow piece's tile in its colour with its letter and condition; a click shows its name in yellow and its stats; Equip puts it on and its stats count; the Wearing column shows it in colour; Repair with a kit, Unequip, Drop). `test_town_world.gd` (the real game has Old Pete in the hall, once after a save, and the pipe in your hand). `test_save.gd`/`test_skills.gd`: the v3 fixture now also gets Old Pete; a new save is the current version. **2367 checks** (was 2189).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- Press **Tab**: the Wearing column shows "Weapon: Pipe". To see a rolled piece straight away: `play.bat --gear` (a yellow one), or `play.bat --gear=gold` (Pete's Fire Axe), `play.bat --gear=set` (a Night Shift piece), `play.bat --gear=blue`. Click it, then **Equip**: watch the kg limit and the "Weapon:" line at the top right change.
- Old Pete: walk north up the road into the factory hall; he's in the middle, in a red shirt, bigger than the rest. Or start facing him: `play.bat --cam=-1,0,-115,0,4 --time=12`. He takes about six pipe hits; then press **E** on his bag and Tab to equip the axe.
- Search cupboards, trunks and the factory crates: now and then "Found ..." names a piece of gear.
- Repair kits: `play.bat --demo-factory --time=12`, look at the press, press **R** ("Press now makes Repair kit"), take some nails from the crate by the spawn, then **E** on the press to load them.

**Known gaps:**
- Gear icons are placeholders drawn in code (a rounded square in the rarity colour with the base's first letter); Codex pictures are a PC job. Every weapon still looks like the pipe in your hand, and Old Pete is the ordinary zombie model, scaled up with a red shirt.
- Worn gear doesn't count against your carry limit (only gear in your pockets does), and it doesn't show on your body.
- The skills screen still shows the ranks you bought, not the extra ranks gear adds (the effects do use them).
- The headlamp doesn't light anything yet (its base stat is +5% search speed); the flashlight is still F.
- No crafted (orange) gear, no Military tier, no guns or reload/recoil stats (M14), and only one unique and one set. Every number in `data/gear.json` is a first guess.
- Old Pete is added to a loaded pre-M13 save even if you'd already cleared the factory.
- Set pieces have no stats of their own beyond their base; the set bonus is what they're for.

**Next:** Playtest #1, then W1c furniture and M14 guns.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — M12 Skills and perks

From the M12 brief by the project lead, on top of W1b.

**Built:**
- **Ten skills that level by doing** (0-10, Zomboid style), each with one effect you can feel:
  - **Strength:** trained by swinging the pipe and by walking with more than half your carry limit. Carry limit is 20 kg + 3 kg per level (20-50 kg before bags), and melee damage and knockback go up 5% per level.
  - **Fitness:** trained by sprinting. Stamina comes back 5% faster per level.
  - **Building:** trained by placing pieces and repairing them. Repairs cost 5% less per level (rounded, never below half).
  - **Mechanics:** as before (repairs, car repairs, mufflers, hotwiring; hotwiring needs level 2 and gets quicker).
  - **Scavenging:** trained by each finished search. Searching takes 5% less time per level.
  - **Sneaking:** trained by each second you move crouched within 15 m of a zombie that hasn't noticed you. Walking footsteps are 1 quieter per level.
  - **Melee:** trained by each hit, more for a kill. Melee damage +4% per level (on top of Strength).
  - **Firearms:** listed, greyed out ("Comes with guns"); nothing trains it yet.
  - **First Aid:** trained by each bandage. A bandage also heals 5 health per level, and a zombie bite is 2 points less likely to make you bleed per level.
  - **Farming:** trained each time you take a planter's vegetables. Planters grow one extra vegetable per three levels.
- **Perk points:** every 3 skill levels you gain (all skills added up) earns 1 point. The HUD says "Strength 2" when a skill goes up and "Perk point earned: K to spend" when you get a point.
- **Three perk trees, three perks each, ranks 1-5,** spent on the skills screen and never refunded:
  - **Engineer:** Fast Lines (belts +10% speed per rank), Dampened Gears (machines and generators 2 quieter per rank, plus 1 more for every 3 points you've spent in Ghost), Tuned Machines (machines craft 5% faster per rank).
  - **Ghost:** Soft Step (walking and sprinting footsteps 3 quieter per rank), Quick Fingers (searches 10% faster per rank), Lucky Find (20% chance per rank that a search finds one extra item).
  - **Fighter:** Heavy Swing (melee damage +10% per rank), Second Wind (stamina back 10% faster per rank), Thick Skin (zombies hurt you 5% less per rank).
- **The skills screen (K, Esc or K closes):** every skill with its level, a bar to the next level and what it does; your perk points; the three trees with each perk's rank and a +1 button (greyed with no points or at rank 5). The game keeps running while it's open, like the inventory, and you stand still. The HUD's key line says "K skills".
- **You keep skills, perks and unspent points when you die.**

**Rules (sim, tested):** `Skills` holds xp, `perks` (ranks) and `perk_points`; `practice(skill, action, times)` adds xp from `data/skills.json` and earns points (`points_earned` = total levels / 3); `spend(perk)`/`can_spend`; and one query, `bonus(effect)`, sums every skill level and perk rank that gives `effect` (a `{"value", "every"}` spec gives "1 per 3 levels"; a perk's `synergy` adds per `every` points in another tree once you have a rank). The rules call it: `SimWorld.carry_limit` (carry_kg), `melee_damage`/`hit_zombie` (melee_damage, knockback), `PlayerStats.stamina_regen_mult` (stamina_regen), `BuildGrid.repair_cost(key, discount)` via `SimWorld.repair_cost` (repair_discount), `Loot.search_time` (search_speed, floor `search_time_min`) and a Lucky Find roll on the container's own seeded rng after the normal roll (lucky_find), `SimWorld.noise_loudness` for footsteps (walk_quiet, sprint_quiet), `bleed_chance` and `use_bandage` (bleed_cut, bandage_heal), zombie hits (damage_cut), `Factory` (belt_speed, craft_speed, planter_extra per craft), `NoiseField.machine_loudness` and `PowerGrid.noise_sources` (machine_quiet). New sim entry points: `SimWorld.swing()` (the world's swing now goes through it, for Strength xp), `machine_interact()` (E on a machine; Farming xp), `player_sneaking` (written by the world), `BuildGrid.piece_built` (only `place`, not `restore`, so loading a save or laying the town teaches nothing; demo bases are muted too). `GameData` validates the skills, trees and perks. **Saves:** `SaveGame.VERSION` is 5 (perks and perk points). A version-4 save loads with no perks and the points its skill levels are worth; a committed fixture `test/fixtures/save_v4.json` (written by the W1b code before these changes) is tested, and the v2 and v3 fixtures still load.

**Tests:** `test_skills.gd` (the ten skills in data; level thresholds; xp from swings, heavy steps, sprinting, placing and repairing, searching, sneaking near unaware zombies only, bandages, harvests; the level-up and perk-point messages; a point every 3 levels, even across a jump; spending, the rank-5 cap and no points no spend; each effect at level 0 vs 5: carry 20 -> 35 (50 at 10, bags on top), melee damage and knockback, stamina regen, repair cost and what's charged, search time and its floor, footstep loudness as zombies hear it, bandage heal and bleed chance, planter yield 3/4/4/5 at 0/3/5/6; Fast Lines, Tuned Machines, Dampened Gears with the Ghost synergy on machines and generators, Thick Skin, Lucky Find on the seeded rng; death keeps everything; save and load of xp, perks and points), `test_skills_screen.gd` (shows levels, greyed Firearms, ranks; the button spends a point and the rank shown changes; greyed with no points and at rank 5; in the real game K opens it, the player stands still, the game keeps running, Esc closes it without the pause menu, K toggles), `test_save.gd` (the version-4 fixture loads with a perk point for its Mechanics 3). `test_car_keys.gd` now expects "Mechanics 1". **2189 checks** (was 2022).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- Press **K** to see the skills screen. Or open it straight away: `play.bat --skills`.
- Sprint for 30 seconds: "Fitness 1" pops up. Hit a zombie a few times with the pipe: Strength and Melee go up. Search a few kitchen cupboards: Scavenging. Three levels in all and the HUD says "Perk point earned: K to spend"; press K and click +1 next to a perk.
- Strength: watch the "kg" number by your pockets (top right) go up from 20 as Strength levels.
- Farming: `play.bat --demo-farm --time=12`, wait for the planter, then E on it to take the vegetables.

**Known gaps:**
- Not in M12, as planned: items with "+1 to perks", respec (the Clean Slate), anything Firearms does, guns (M14). The design's other perk ideas (cheaper mufflers, see noise rings, harder to spot, recoil, reload, Gunsmith) aren't in yet.
- Every number is a first guess (xp per action in `data/skills.json`, e.g. a search 10, a bandage 15, a second of sprinting 1, level 1 at 30 xp). Tune after Playtest #1.
- Farming xp and the extra vegetables: xp only when you take the vegetables by hand (E), not when a belt carries them off; the extra vegetables are grown either way.
- Sneaking xp counts any zombie within 15 m that is idle, wandering or investigating (not one chasing you), with no line-of-sight check.
- The inventory screen still shows its own Mechanics line; the skills screen is the full list.
- No screenshot of a level-up message (no flag sets xp); the screen was checked by day and night.

**Next:** Playtest #1, then M13 loot.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1b Life inside

From the W1 plan (`docs/plans/W1.md`, "W1b — life inside"), on top of W1a and the stress test.

**Built:**
- **A zombie inside some houses.** In every town, 4 of the 12 houses have one shambler standing inside (never the two houses by the spawn). The world seed picks which houses and where, so the same seed always has them in the same places; in a new game (seed 1) they're in the 2nd house up on each side, the 4th on the left and the 6th on the right. Each one stands in the kitchen, next to the fridge or the kitchen cabinet, facing the front door. It just stands there: a zombie whose home is on a house floor doesn't go for strolls (my call: idle without wandering, rather than wandering inside the house's cells; it can't drift out and it's simpler). It's an ordinary zombie otherwise: it sees you through doorways and windows, hears you, and comes for you. Searching the fridge or cabinet next to it is loud enough to wake it by day.
- **The factory is a hall you can walk into.** The solid grey block at the north end of the road is gone. In its place: a 15 x 12-cell floor (30 x 24 m), walls in the old factory's grey brick, a 4 m wide open doorway (two empty edges, no door) where the road ends, three windows down each long side, and a roof with a dark ceiling about 6 m up (the brick carries on above the wall pieces up to the roof, and over the doorway). The three supply crates are inside now. It's built from the same grid pieces as the houses, so the walls muffle sound, zombies can bash them, and the navmesh runs in through the doorway.
- **Hordes come down the road.** Wanderers still come from any of the four edges, straight at the noise. Groups and hordes now come from the north or south end of the road only. From the north they appear behind the factory, come round its west side onto the road, and walk down it; from the south they walk up from the end of the asphalt. They follow the road to the point nearest the noise, then turn off toward it. The HUD still says "A horde is coming from the north...".

**Rules (sim, tested):** `TownPlan.generate` also returns `"zombies"` (house, cell, pos, facing; its own random stream, so the houses themselves don't change) and `"factory"` (`TownPlan.factory()`: cells, pieces, crates, doorway edges, windows; the same in every town). `SimWorld.place_factory(plan)` lays the hall like `place_town`; `SimWorld.spawn_house_zombies(plan)` spawns them through the horde. `ZombieBrain`: an idle zombie whose home is on a `town_floor` doesn't wander (`_indoors`); `hear_via(via, at, key, time)` gives it a short waypoint list (`route`) walked during INVESTIGATE, each waypoint consumed on arrival (each leg gets the full lure time), then `target_pos` becomes `sound_pos`; hearing the same sound again on the way keeps the route, a different sound drops it. `hear()` is still the entry point. `Director`: group and horde waves pick EDGES 0 or 1 (north or south) and call `hear_via(Director.road_route(edge, lure), ...)`; `road_route` is the corner behind the factory (north only), the road end, then road points at most 40 m apart down to the road point nearest the lure. The wave dict also carries its `route`. **Saves:** `SaveGame.VERSION` is 4 (`FIRST_WITH_FACTORY`, `holds_factory`). House zombies are ordinary saved zombies, and a loaded game doesn't spawn them again. A version-3 save (W1a) loads with the factory hall laid fresh under it; a committed fixture `test/fixtures/save_v3.json` (written by the W1a code) is tested. World: `main.gd` lays the hall, puts the crates on its floor and spawns the house zombies in a new game (not with `--zombies=0`); `TownView` draws the hall's roof, ceiling and upper brick; `BuildView` has a "factory" wall style.

**Tests:** `test_house_zombies.gd` (same seed same houses, 4 of 12, never lot 0, inside and not on a container or the doorway; one spawned per picked house; with no noise they stay idle and inside for five minutes while a street zombie wanders; searching the kitchen next to each one makes it investigate; a save brings them back once), `test_factory_hall.gd` (15 x 12 floor, walls and windows all round less the two-cell doorway, the doorway edges empty and on the road in the south wall, crates inside, no overlap with houses, sound gets out through the doorway but not the side walls; physics: you walk in through the doorway and the wall beside it stops you; a zombie on the road follows you in without breaking anything), `test_road_hordes.gd` (`road_route` from both ends; a north wave zombie with a smelter east of the road reaches the road point first, keeps to the asphalt, then reaches the smelter; same sound keeps the route, a new one replaces it; over six seeds the HUD's edge matches where the horde spawned and both ends get used; wanderers come straight), `test_save.gd` (the version-3 fixture loads with the hall added), `test_town_world.gd` (the whole game lays the hall and a zombie in each picked house, and a save brings the same zombies back, not doubled). **2022 checks** (was 1546).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**.
- House zombie: walk up the street to the second house on the right (east side), open the front door (E) and look left through the doorway into the kitchen. Or start there: `play.bat --cam=9,0.1,-22.6,-63,-3 --time=12`.
- Factory: walk north to the end of the road and go in through the big doorway; the three crates are inside. Or: `play.bat --cam=0,0,-98,0,6 --time=12`.
- Hordes: `play.bat --demo-factory --time=21 --heat=100 --noise-overlay` and wait up to 30 seconds for "A horde is coming from the north (or south)...". Press N to see them: they walk the road toward you before turning off it.

**Known gaps:**
- Not in W1b, as planned: furniture props (table, couch, shelves need Blender art on the PC), a fifth house plan, the shop, any zombie tuning, and no change to infamy or heat numbers.
- With today's numbers a house zombie mostly finds you by sight, not sound: a search (30) is only heard within about 3 m by day, footsteps (22) and a door opening (25) barely at all. That's why they stand next to the kitchen. Tune hearing after the playtest if they feel deaf.
- Any zombie that ends up idle on a house or factory floor stays there (e.g. one that chased you in and lost you), not only the planted ones.
- A wave's road route isn't saved: a zombie that was walking the road when you saved stands where it was after loading (as every investigating zombie already did).
- The north road end is behind the factory, so northern hordes come round its west side; there's no road there. Hordes don't avoid the houses' lawns other than by the waypoints, and nothing makes the road a preferred lane on the navmesh.
- The factory is empty apart from the crates: no machines, shelves or props, and the brick above the wall pieces has a faint seam line at 2.8 m. Its roof has no collider (like the houses').
- Town pieces go from 455 to 687 with the hall; the first navmesh bake is about 49 ms headless (the console line now says "town pieces").

**Next:** Playtest #1, then M12.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — Stress test (numbers only)

How expensive one sim tick is with many zombies and machines, before zombies inside houses, hordes and automated defense. No code changed outside the test; nothing optimised.

- `tools/stress.sh` runs `test/stress/stress_sim.gd` (headless, not part of `tools/test.sh`): the W1a town, `power.free`, 50 smelters and presses kept crafting, 200 shamblers on the main street, `sim.step()` in a loop. A full day would take ~113 s of wall time, so it runs **4 game hours** from 19:00. Full table: `docs/perf/stress-2026-10-13.md`.
- **Town + 200 zombies + 50 machines: 4.6 ms per tick on average, 20 ms worst** (the budget at 20 ticks per second is 50 ms). Empty map: 4.2 ms. Town + 20 zombies: 2.3 ms.
- Where the time goes: zombies listening (`loudest_heard`, ~170 us each, every half second; it grows with zombies x machines) and the Director's `gain_now` (~10 ms once a second, which makes the worst ticks). The town itself adds ~0.4 ms. Memory +1.4 MB.
- Not measured: zombie bodies, navmesh and physics (a sim-only run never moves zombies).

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-13 — W1a Into the houses

From Playtest #1 ("there are no doors or ways into the buildings") and the plan in `docs/plans/W1.md`.

**Built:**
- **Houses you can walk into.** The twelve box houses are gone. Each lot now has a real house built from the same 2 m grid pieces you build with: a floor, outside walls in brick or painted siding, a front door facing the road, a back door, three or four windows, and inside walls (pale plaster) with open doorways between the rooms. Three floor plans: A (8 x 8 m: living room, kitchen, bedroom, bathroom), B (10 x 6 m: kitchen-living room with a galley kitchen, bedroom, bathroom off the bedroom) and C (an L-shape: living room, kitchen and bathroom behind it, a bedroom wing). The world seed picks each lot's plan and whether it's mirrored, so the same seed always gives the same town. Each house has a flat roof with a ceiling under it, so rooms are dim by day and dark at night (the flashlight matters), and a strip of wall above each door.
- **The loot is inside.** Every house has a fridge and a kitchen cabinet in the kitchen and a cabinet in the bathroom (36 containers, was 12 on the lawns), back to the wall and facing the room, plus a real bed in the bedroom (sleep in it to make it your respawn point, like your own bed). A car key that lives "in the nearest house" is now in one of that house's containers.
- **Doors, windows and walls work like yours.** E opens and closes the doors. Closed doors, walls and whole windows muffle sound like your own walls, so closing the door behind you makes you harder to hear, and a loud machine indoors heats the Director up slower. Zombies bash doors, walls and windows. A window has 40 hp; when it breaks the glass is gone and it's an opening (sound, sight, zombies and you can go through). Build a barricade on that edge to board it up. You can see through glass, and so can zombies. You can't build town pieces yourself, but in build mode right-click knocks one down for a small refund: a plank from a floor or a window frame, a plank and a scrap from a house wall (a broken window gives nothing).
- **One new tip** after the crate tip in a new game: "Houses have food inside. E opens doors; close them behind you". It moves on when you search something in a house, or after 40 s.
- **Numbers for next time:** the town lays **455 pieces** (floors, walls, doors, windows and beds) and the first navmesh bake takes **about 48 ms** on Emmitt's PC. The console prints `Town: N house pieces laid, first navmesh bake N ms` at startup, and `test_town_world.gd` prints the same.

**Rules (sim, tested):** `TownPlan` (new, `src/sim/town_plan.gd`, pure): `generate(seed)` gives the pieces, containers, beds and houses for the twelve lots. `SimWorld.place_town(plan)` lays them into the `BuildGrid` with `restore` (free, full hp, not counted as your builds), and `SimWorld.town_container_pos` says where a container stands. New pieces in `buildables.json`: `town_floor` (kind foundation), `town_wall` (kind wall, 600 hp), `window` (a new kind, 40 hp), all `"player_placeable": false`. `BuildGrid`: windows are edge pieces; `edge_blocks` (whole glass blocks sound but not sight; broken blocks nothing), `is_broken`, `damage` leaves a broken window in place at hp 0 instead of wrecking it, `can_place` refuses town pieces ("Only found in town") and lets a barricade replace a broken window (no refund), `repair` on a broken window says to board it up, `remove` refunds nothing for a broken window. `ZombieBrain` stops bashing a window once it's broken. **Saves:** `SaveGame.VERSION` is 3. Town pieces are saved with the rest, so damage, open doors, broken windows and walls you knocked down stay that way. On load the town plan still runs (for the containers and roofs), but it only lays the houses when the save is older than version 3 (`SaveGame.holds_town`). A committed version-2 save (`test/fixtures/save_v2.json`, written by the pre-W1a code) still loads, with the houses laid fresh under it. World: `TownView` (roofs, ceilings, door lintels), `BuildView` draws town walls, floors and windows with the house's surface (`styles`), zombies see through window glass, and the `--inside[=N]` flag.

Where the plan and the code differed, I followed the code: `town_floor` is 0.1 m thick like `foundation` rather than flush, because walls and objects sit on `foundation_top()`. Containers and beds come with the wall `side` they stand against. The plans have two or three runs of inside wall (with doorways) rather than one or two, so each room reads as a room, and every plan has a wall straight behind the front door. The generator runs on every load, because containers aren't saved; only laying the pieces is skipped.

**Fixed on the way:** zombies treated the low edge of a floor they were stepping onto as a wall and started "breaking" it, standing still at the edge of houses and bases. Now they only count something they walk into face first.

**Tests:** `test_town_plan.gd` (same seed gives the same town; all three plans in use; every house closed all round with a floor under every cell; front door on the road side in the front row, a back door, 3-4 windows; containers and beds inside, against a wall; no shared cells; lots where the old houses stood; town pieces not in the build menu), `test_town_sound.gd` (for every house, a closed front door muffles and opening it lets sound out; a broken window lets it out and a barricade shuts it again; a smelter indoors is 10 dB quieter to the Director and heats it slower), `test_window.gd` (hp, breaking into an opening, sight vs sound, barricade over a broken window with no refund, can't build town pieces, refunds), `test_town_world.gd` (physics: walk in through the open door and stop at the wall behind the front room; a closed door keeps you out; a zombie on the street follows you in through the open door and bites; with the door shut it breaks the door; the whole game lays the houses once and a save brings them back with the open door and the damage), `test_save.gd` (the version-2 fixture loads; town damage, an open door, a broken window and a removed wall survive save and load). `test_hints.gd` now expects the new tip as step 2. **1546 checks** (was 1095).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**. Walk up the street: the houses have doors facing the road and windows. Press E on a front door to open it and go in: kitchen, bathroom, bedroom. Press E on the fridge and cabinets to search them. Close the door behind you (E). To start inside a house: `play.bat --inside=1` (any number 0 to 11). At night with the flashlight: `play.bat --inside=4 --time=22 --flashlight`. To see houses muffle sound: `play.bat --noise-overlay`, then open and close a door while a zombie is near. Old saves still load (the houses appear around your base, and house loot is fresh).

**Known gaps:**
- No new models or textures (as planned): windows are frame boxes with a glass pane, outside walls show brick or siding on the inside too, and there's no furniture beyond the fridge, cabinet and bed models.
- No zombies inside houses yet, the factory is still a solid block, hordes don't follow the road, and roofs don't affect sound (W1b).
- Town doors are ordinary doors and house beds are ordinary beds, so knocking them down refunds their full build cost (6 planks and 8 nails a door, 6 planks and 10 nails a bed). That's a lot of free material across 24 doors and 12 beds; tune it after the playtest.
- A broken window has no collider, so you can't aim at it to remove it with right-click. You can still board it up.
- The strip of wall above a door stays if the door is knocked down. Outside corners have a small notch where two walls meet (the same as your own walls).
- Containers you'd searched in a version-2 save stood on the lawns. Those are gone, so house loot is fresh after the upgrade.
- At 455 pieces the town's navmesh bake takes about 48 ms, and a rebake after each build still covers the whole town. The stress test in DIRECTION.md should measure it with many zombies.

**Next:** Playtest #1, then W1b.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — P1 Playtest fixes

From Playtest #1 (`docs/PLAYTESTS.md`): Emmitt pressed E on cars and couldn't drive them, and nobody could tell which build he was playing.

**Built:**
- **Cars explain themselves.** Looking at a car you have no key for now says `[E] get in   No key: search the trunk (E at the back) or the nearest house`. A wreck says what's wrong first, then what you can still do: `Flat tyres.   [E] search the trunk   [G] siphon gas`. A car you can start still just says `[E] get in`. The first time you sit in a keyless car, the HUD also says "No key. The glovebox is searched from the trunk, or try the nearest house" (once per car). The in-car line with `[R] hotwire` is unchanged.
- **Which build am I playing.** `play.bat` now writes two files next to itself on every run: `play-update.log` (when it ran and everything the update step said, including why it skipped or failed, plus git's own error text) and `version.txt` (the commit about to run, like `0c55be4 Merge pull request #18 ...`; "unknown build" without git). The title screen shows that line small in the bottom-right corner ("dev build" when there's no file), the session log's header starts with `Build: <that line>`, and the console prints `Noise Floor build: <that line>` at startup. The update itself is unchanged: clean `main` only, fast-forward only. Both files are git-ignored.

**Rules (sim, tested):** `Vehicles.start_hint(id, pockets)` (the one-line reason a car won't go: "" if it starts, the wreck text plus "you can still search the trunk and siphon its gas", or `Vehicles.NO_KEY_HINT`); `SimWorld.enter_car` adds `SimWorld.NO_KEY_MESSAGE` once per car. World: the car look-at prompt in `Interactor._car_status`, `GameSession.version_line()` / `version_path` (tests point it at their own file, like `save_path`), the title-screen label in `Menus`, the header line in `SessionLog`, and the console line in `main.gd`.

**Tests:** `test_car_keys.gd` (start_hint for no key, key in pockets, key in the ignition, hotwired and a wreck; the no-key message comes once per car and not for a car you can start), `test_car_prompts_world.gd` (loads the game, stands beside the first car and reads the prompt with no key, with the key, and as a wreck), `test_version.gd` (a temp version file shows on the title screen and in the session log header; no file or an empty one says "dev build"). 1095 checks (was 1067). `play.bat` was tried by hand on a branch (skips, logs why), a clean `main` one commit behind (fast-forwards, logs "Up to date"), and with local changes (skips, logs why).

**Try it on the PC:** merge, then double-click `play.bat`. The title screen's bottom-right corner shows the build; `play-update.log` and `version.txt` appear next to `play.bat` (open them with Notepad). Start a **New game**, walk up the street to the red sedan and look at its side: it says there's no key and where to look. Look at its back and press E to search the trunk (the glovebox key is there), then E at the side to get in and drive. To try a wreck, walk on down the street until a car says "Flat tyres", "The engine won't turn over" or "Smashed up too badly".

**Known gaps:** the no-key hint doesn't say which house, and a car whose key is lost gets the same hint (hotwiring with Mechanics 2 is its only way). The "told you once" memory isn't saved, so a loaded game may say it once more. `version.txt` is only written by `play.bat`, so running Godot directly shows "dev build". The houses are still closed boxes (W1).

**Next:** Playtest #1 on the merged build.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — P0 Playtest kit

**Built:**
- **Session log.** Every time you play, the game keeps a short plain-words diary of the session and saves it as a text file (under 40 lines): how long you played (real and game time), each death and what caused it (the zombie type, starvation, dehydration or bleeding), how hot the Director got and when, what you built (by kind), mufflers fitted, zombies killed, the loudest one-off sound and the loudest machine or engine, and a timeline of your first five real minutes (built X, searched Y, hit a zombie, died, siphoned, got in a car...). It's written when you die and again when you quit (closing the window, Quit on the title screen, or quitting to the title), to `sessions/<date_time>.txt` in the game's save folder; the console prints `Session log: <path>`. Loading a save during a sitting carries on the same log.
- **First-game hints.** A new game shows one tip at a time above the health line: find the crate and press E, build a foundation and a smelter, press N to see how far the noise carries, then wall it in or fit a muffler (U). Each moves on when you've done it, or after 90 seconds so it never nags (the noise tip after 40). They never take input. Not after loading a save, not with `--demo-*` or `--cam`, not in screenshots; `--no-hints` turns them off and `--hints` forces them on.

**Rules (sim, tested):** `RunStats` (new, in `src/sim`) records the session; `SimWorld.stats` is fed where things already happen (zombie hits and kills, deaths, builds, mufflers, searches, siphoning, getting in a car, crate use, Director waves and heat, the noise field each tick). `PlayerStats.last_cause` remembers what hurt you last, so the death cause is worked out in the sim. The game's own setup (start crate, demo bases, loading a save) is muted, so it isn't counted as yours. World: `SessionLog` (writes the file; off in headless runs and screenshots, tests use `path_override`), `Hints` (one label), `GameSession.skip_hints`, and the `--no-hints` / `--hints` flags.

**Tests:** `test_run_stats.gd` (death by a zombie vs starvation, thirst, bleeding; builds by kind, not counting the start crate; the five-minute timeline cut-off and repeats; peak heat and when; loudest sounds), `test_session_log.gd` (a death writes the log with the expected lines to a test path; off unless enabled), `test_hints.gd` (hints follow the crate, the smelter, the noise timeout and a muffler; time out; a new game shows them and a loaded save doesn't). 1013 checks (was 929).

**Try it on the PC:** merge, then double-click `play.bat` and pick **New game**: the first tip appears above your health. Play a while (die once if you can), then quit from the title screen. The log is in `%APPDATA%\Godot\app_userdata\Noise Floor\sessions\` (paste that into the Explorer address bar); the newest `.txt` is your session. To play without tips: `play.bat --no-hints`.

**Known gaps:** the game has no version string yet, so the log's header gives the date, world seed and game clock instead of a commit. One file per sitting, rewritten each time (deaths are listed inside it, not as separate files). Kills only count your pipe and your car, not turrets or spikes. The hints restart if you start another new game in the same sitting. Session logs are never uploaded anywhere: someone has to open the folder.

**Next:** Playtest #1.

- Built by Claude Opus 5.5 from a plan by Claude Fable 5.1.

## 2026-10-12 — M11 The world gets worse

**Built:**
- **Loot never comes back:** a searched container stays empty for good (it already worked that way; now there's a test).
- **Food spoils:** vegetables keep about 5 days (`spoil_days` in items.json), in your pockets and in crates, and rot into **rotten food**, which you can't eat. Fresh food you find in town from day 7 on is already rotten. Canned food, chips and soda keep forever, which is what the canner is for.
- **Stale gas:** on day 21 the gas left in the town's cars goes stale. Only gas you poured in yourself stays good, so siphoning dries up and generators eventually need another fuel source or solar.
- **Infamy:** a permanent score of all the noise you've made that the dead could hear: machine and generator noise reaching 50 m out, plus loud one-offs like the horn. It never cools off the way heat does; zombies' own bangs don't count. As it climbs, waves bring new kinds of zombie. **Runners** come at 3000 infamy (about a quarter of the wave), roughly a quarter of an hour of an unmuffled generator in the open. **Screamers** come at 8000 (about 1 in 8). Each one arrives with a warning message.
- **Runners:** they sprint at 3.6 m/s (shamblers do 1.3) but have 60 hp. They're smaller, dark-skinned and dark-clothed, and have a new **Run** animation.
- **Screamers:** when one spots you it stops and shrieks (a loudness-88 noise, then 25 s before it can again), and everything within earshot comes to investigate. They're pale with blood-red shirts, and have a new **Scream** animation and a high, warped moan.
- **Stats:** the pause menu shows the day, your deaths, zombies killed (by you, your turrets, traps or your car) and total noise made. Saved with the game.

**Rules (sim, tested):** `Director.infamy`/`unlocked`/`pick_type`, screamers in `ZombieBrain` (`screaming`), spoilage (`SimWorld._spoil`, `Inventory.spoil_debt`), `_rot_old_food`, `Vehicles.go_stale` (cars track the `fresh` gas you poured in), and kill and death `stats`. Data: runner and screamer in `zombies.json`, `infamy` in `noise.json`, `spoil_days` and `rotten_food` in items.json, and `gas_stale_day` and `found_food_rots_day` in survival.json. World: zombie looks and the Run/Scream animations in `ZombieBody`, the scream sound in `SoundView`, stats in the pause menu, and a new `--zombie-type=` flag.

**Tests:** `test_world_worse.gd` (loot stays gone, vegetables rot and canned food keeps, in crates too, late-found food is rotten, stale gas, infamy builds and never cools (the horn counts, wrecks don't), runners then screamers unlock, a screamer pulls in a zombie that couldn't see you, stats add up and are saved) and `test_zombie_types_world.gd` (runners run, screamers scream, the kinds look different). 978 checks.

**Try it on the PC:** merge, then double-click `play.bat`. To meet the new zombies straight away, run `play.bat --zombie=0,-10,2,-12 --zombie-type=runner` or `play.bat --zombie=0,-8 --zombie-type=screamer`. Press **Esc** to see your stats.

**Saves:** the save version is now 2. Saves from M9-M10c still load, and whatever they lack starts at its default (no stats, no infamy, fresh gas); a save from a newer game is refused.

**Known gaps:** rotten food has no use yet (compost for the planter would be a good one); only vegetables spoil; gas cans in pockets and crates never go stale; there's no infamy meter apart from the stats line; brutes, crawlers and listeners come later.

**Next:** M12, skills and carry weight (Mechanics already exists).

Built by Claude Opus 5.5.

## 2026-10-12 — M10c Wheels

**Built:**
- **Drivable cars.** The town has a sedan, a pickup, a van and another sedan (new Codex models, built by `tools/art/sedan.py`, `pickup.py` and `van.py`, with separate wheels that spin and steer). They have worn, rusty paint (a Codex texture mapped to the car, so it doesn't slide as the car moves) tinted per car, and see-through glass with a dashboard and steering wheel inside. Godot's `VehicleBody3D` does the physics (`CarBody`).
- **Driving:** look at the front or side of a car and press **E** to get in. **W/S** are gas and brake (hold S to reverse), **A/D** steer, **Space** is the handbrake, **H** the horn, **F** the headlights, **E** gets out beside the driver's door, and the mouse looks around the cab. The readout shows speed, gas, damage and what's wrong.
- **Noise:** a running engine is a continuous noise source as loud as a generator, so it draws zombies, and its sound revs with speed. The horn is very loud (95).
- **Fuel** is the same gas **G** siphons: siphoning strands a car, **R** pours gas cans back in, and driving burns gas by distance (plus a little idling). The tank's in gas cans; pickups are thirstier.
- **Keys, Zomboid style (Emmitt's call).** Every car has its own key: in the ignition, in the glovebox (search the car), in the nearest house, or lost. car_0's is always in its glovebox. Without it the engine won't start. **Hotwiring** (**R** in the car) needs **Mechanics 2**, takes 12 s (2 s less per level above 2, at least 4), makes a little noise, and stays hotwired. **Mechanics** levels by doing (`data/skills.json`): piece repairs, car repairs, mufflers, hotwiring. It shows in the inventory screen. This is the first M12 skill, brought forward.
- **Wrecks** (flat tyres, a dead engine, smashed) can be searched and siphoned but not driven. **Damage:** zombies hit the car, not you, while you're inside; running zombies over hurts them by speed and dents the car; **T** repairs a quarter for a metal plate and 4 nails.
- **The trunk** is searched from the back of the car (and moves with it). **Saved:** where each car is parked, its gas, damage, key and hotwiring, plus your Mechanics. Saving while driving loads you beside the car. Zombies path around a parked car (the navmesh is rebaked when you get out).
- **Footsteps** are redone: a soft, dull heel thud with a gentle scuff, much quieter (Emmitt: the old ones were "too loud and sharp"). Each sound now has its own random seed, so adding a sound never changes the others.
- **`play.bat` updates itself:** it fast-forwards a clean `main` checkout from GitHub before starting, so merging a PR is all you need to do. It skips other branches or local changes, and plays what you have if it's offline.

**Rules (sim, tested):** `Vehicles` (cars, fuel, keys, hotwiring state, ram damage, repair, engine noise, save), `Skills`, and in `SimWorld`: `enter_car`, `exit_car`, `car_moved`, `honk`, `hotwire`, `refuel_car`, `repair_car`, `car_hits_zombie`. `Loot.add_extra` (a key in a particular container). Data: `data/vehicles.json` and `data/skills.json`; the horn and wreck chance are in `noise.json` and `survival.json`. World: `CarBody`, plus driving in `main.gd`, car prompts in `Interactor`, engine and horn in `SoundView`, and `--drive[=car_N]`.

**Tests:** `test_vehicles.gd` (wrecks, getting in and out, fuel, engine noise and horn, out of gas, idling, siphon and refuel, zombies hitting the car, ramming, repair, save), `test_car_keys.gd` (key spots, glovebox search, ignition, hotwiring needs Mechanics 2 and is quicker with skill, Mechanics levels by doing, save), `test_driving.gd` (real physics: drives the way it faces, brakes then reverses, steers, no gas no go, parked cars stay put), `test_vehicle_models.gd`. 929 checks.

**Try it on the PC:** merge, then double-click `play.bat` (it pulls the update itself). Walk north up the street to the first car (a red sedan), look at its back, press **E** to search the trunk and you'll find its key. Then look at the side, press **E** to get in, and drive. `play.bat --drive` starts you in it (without the key: search for it, or level Mechanics by repairing things).

**Known gaps:** no crash damage from hitting walls or houses (only zombies dent it); no passengers; in a new game the van is a wreck (its engine won't turn over), the pickup's key is in its glovebox and the far sedan's is in its ignition; the zombie navmesh only updates when you get out, so zombies can bump into a car you're driving; you can't use the trunk as storage from the inventory screen yet. The sounds still need your ears: say if the engine or horn are off.

**Next:** M11, the world gets worse.

## 2026-10-12 — M10b Inventory screen

**Built:**
- **Tab** (or **I**) opens your pockets next to the nearest storage crate within arm's reach (3 m; arrows switch between crates if several are close). Every item shows its Codex-made icon and count. **Tab** or **Esc** closes it. You stand still while it's open, but the game keeps running, so a zombie can walk up while you sort.
- **Click** an item to see its weight and what it does (food, water, stops bleeding, or how much a bag adds to your carry limit), with buttons to **Use** it (eat, drink, bandage), **Move 1 / Move all** to the other side, or **Drop 1 / Drop all**. **Shift-click** moves the whole stack straight across; **ctrl-click** moves one.
- **Carry weight** shows at the top, with your best bag's bonus. It turns yellow near the limit and red when you're overloaded (slower and louder).
- **Dropping** puts items in a bag at your feet (into one already lying there if there is one), the same as a death bag: **E** picks it back up, and it's saved.
- The plan gained **M10c — Wheels**: drivable cars with better textures, loud engines, fuel shared with siphoning, wrecks, saved where you park.

**Rules (sim, tested):** `Inventory.move_to`, `SimWorld.use_item` / `can_use` (one particular item, not just the best one), `drop_items` (joins a nearby bag), `crates_near` (within `crate_reach`, nearest first). World: `InventoryScreen`, plus the new `--inventory[=ITEM]` screenshot flag.

**Tests:** `test_inventory_actions.gd` (moving, using, dropping, reach) and `test_inventory_screen.gd` (what the screen shows; shift-click and ctrl-click moves; use and drop; no crate in reach; bag limit). 785 checks.

**Try it on the PC:** merge, `git pull`, `play.bat`, walk up to the starting crate just east of where you spawn, and press **Tab**.

**Known gaps:** only storage crates appear on the right, not car trunks, fridges or ground bags (searching still drops loot straight into your pockets). There's no drag and drop yet, just clicks. The pipe isn't an inventory item yet.

**Next:** M10c — Wheels.

## 2026-10-12 — M10 Look and sound

**Built:**
- **Our own zombie** (`tools/art/zombie.py`): a rigged, animated low-poly townsperson (grey-green skin, torn work shirt, jeans, boots) that Codex built in Blender after Kaleb ruled the CC0 goblin "cursed". It has Idle, Walk, Punch, HitReact and Death animations. `ZombieBody` picks the animation from the brain's state and real speed (the walk speeds up and slows to match the feet), flinches when hit, and plays the death fall instead of tipping the body over. Each zombie gets its own shirt colour and a slightly different size.
- **Every building piece has a model now:** belt, bed, crate, door (hinge and handle on the right sides), barricade, spike strip, and a nail turret whose `Head` turns to aim. The Blender kit gained separate parts (`part()`, `SEPARATE`). Wrecked cars, fridges and cabinets in town are models too (`_dress()` in `main.gd` keeps the old colliders; missing models fall back to boxes).
- **Textures** (Codex photos, seamless via `make_tileable.py`, drawn by the new `Surfaces` helper): asphalt road, brick and painted-siding houses (every third house brick), a brick factory, dry grass and dirt ground, and corrugated scrap for built walls. A missing texture falls back to a plain colour.
- **Sound** (`SoundView`): every working machine and running generator hums with its own sound at its loudness in the noise system, so a muffler really makes it quieter and what you hear is what zombies hear. Footsteps (none while crouching, same as the noise system), pipe hits, wall bashes, doors and turret shots play from the sim's noise events. The wind turns into a colder howl at night. A hard limiter keeps a big factory from clipping. Zombies moan now and then (more often when chasing), grunt when they attack or get hit, and moan once when they die. Plus a pipe-swing whoosh, a build clunk and the flashlight click. All of these except the zombie voices are generated by `tools/audio/synth.py` (deterministic; loop points written into the WAVs). The zombie voices are a CC0 pack (`assets/CREDITS.md`).
- **Atmosphere:** fog thickens and darkens at night. On Forward+ (your GPU), volumetric fog makes the flashlight beam visible, machine lamps glow a little, and SSAO grounds things. The title screen now shows a foggy dusk view down the main street with a flickering title, and the HUD is hidden behind it. Starting a game switches straight back to your own view without touching the sim.
- **Item icons** for the coming inventory screen (M10b): all 16 items plus the pipe, made by Codex and cut out by `tools/art/make_icon.py` into `assets/icons/`.

**Tests:** new `test_sound_view.gd` (a working machine hums at its loudness, a muffler makes it quieter, an idle machine goes quiet, noise events play once), and `test_art_models.gd` now covers turret heads. The zombie-fall test checks the Death animation. Headless runs skip audio playback, because a sound still playing at quit is reported as a leak. 739 checks.

**Try it on the PC:** merge, `git pull`, then double-click `play.bat` for the new title screen. `play.bat --demo-factory` to hear machines (fit a muffler with **U** and listen), `play.bat --demo-defense` for the door, turret and spikes, and `play.bat --time=22` with **F** for the night fog. Use headphones for the moans and the wind.

**Known gaps:** the sounds were made by a script and checked by numbers, not by ear, so tell me which ones sound wrong. Houses are still plain textured boxes (no windows, doors or roofs). There's one zombie body (colour and size vary). The rigid-segment animation is stiff up close. Volumetric fog only shows on Forward+, so cloud screenshots look flatter.

**Next:** M10b, the inventory screen.

## 2026-10-12 — M9 Keep it

**Built:**
- **Title screen** when you double-click `play.bat`: Continue (your last save), New game, Settings, Quit.
- **Esc pauses** the game (time stops, mouse freed) and opens a menu: Resume, Save game, Load last save, Settings, Save and quit to title. Esc again resumes.
- **F5** quick-saves and **F9** loads the last save. The game also **autosaves every 5 minutes** of play, and when you quit to the title. There's one save slot. On the PC it's `%APPDATA%\Godot\app_userdata\Noise Floor\save.json`.
- **What's saved:** the time and day, your pockets and every meter (food, water, bleeding...), where you stand and look, everything you built (with damage, open doors, worn spikes), what's inside machines, on belts, in crates and turrets, generator fuel, the zombies (where they are and how hurt), the Director's heat, which containers you've searched, which cars you've siphoned, death bags, and the world seed. Loading rebuilds the town and puts all of that back.
- **Settings** (kept separately in `settings.cfg`, so they apply to every game): mouse sensitivity (0.2x-3x), volume (ready for when sounds arrive in M10), day length (24, 36, 48 or 72 real minutes per in-game day), fullscreen.

**Rules (sim, tested):** `SaveGame` (`src/sim/save_game.gd`) turns a `SimWorld` into JSON and back, with a version number so old saves are refused cleanly. World: `Menus`, `Settings`, `GameSession` (what survives a scene restart).

**Tests:** 634 checks. A busy base (machines mid-craft, items on belts, open door, damaged wall, turret ammo, crate contents, generator fuel, hurt zombie, heat, siphoned car, death bag, bleeding) survives a save → JSON text → load. **The loaded world then runs 30 s exactly like the original.** Searched containers stay searched; file write/read; other versions refused. Plus the real game scene: build, save, rebuild from the save, and find the wall, your position, facing and thirst; Esc pauses (time stops) and resumes.

**Try it on the PC:** merge, `git pull`, double-click `play.bat`. New game, build something, press F5, quit, start again and choose Continue.

**Known gaps:** one save slot (no named saves); zombies come back where they were but forget what they were doing; a save from an older version of the game won't load once the save format changes (it says so instead of crashing); volume has nothing to control yet.

**Next:** M10, look and sound: CC0 models (Emmitt to approve sources), machine hums and zombie moans, fog and flashlight atmosphere, a proper title screen.

## 2026-10-12 — M8 Defend

**Built:**
- **Door:** takes a wall's place on an edge (2 m gate). **E** opens or closes it, with a little noise. Open, it lets you through, and zombies too; the navmesh re-bakes so they path through it. Shut, it blocks and muffles like a wall, and zombies beat it down like one.
- **Barricade:** a cheap, low board wall (1.3 m). Zombies have to break it, it muffles sound, but turrets shoot over it.
- **Spike strip:** goes on bare ground (no foundation). A zombie on it moves at 40% speed and takes 8 damage a second. The strip wears down by the damage it deals (100 hp, so about 12 seconds of one zombie). You walk over it fine.
- **Nail turret:** on a foundation. **E** loads nails (from pockets or crates in range), or feed it with a belt from any side. Every 0.6 s it shoots the nearest zombie within 15 m that it can see: walls and closed doors block it, barricades don't. 25 damage a nail (4 nails per shambler). Each shot makes a quiet noise (35). A zombie it hits comes for the turret. The head swings to aim and shots leave a brief tracer.
- **Repair:** look at anything you built and press **T**. It costs that piece's build cost times the share of hp missing (at least 1 of each), from pockets and crates in range. Walls, doors, floors and every object now show their hp when damaged.
- Build pieces now go 1 foundation, 2 wall, 3 door, 4 barricade, 5 belt, 6 smelter, 7 press, 8 rain collector, 9 purifier, 0 planter; the mouse wheel reaches the rest (canner, bed, crate, generator, solar, pole, spikes, turret).

**Rules (sim, tested):** `Defense` (`src/sim/defense.gd`) for traps and turrets, turret magazines in `Factory` (belt-fed), doors, edge kinds and repair in `BuildGrid`, open doors and barricades in the noise and sight wall counts, zombie slow and trap damage in `ZombieBrain`.

**Tests:** 590 checks. Doors and barricades follow wall rules, door open/shut changes sound and tells the world, barricades block sound but not turret sight, spikes slow, hurt, kill and wear out, a turret picks the nearest, kills two zombies with 8 nails and makes quiet noise, can't shoot through walls, makes its target come for it, takes nails from a belt, repair costs and refusals, zombies breaking a closed door, plus a physics run: shut door blocks you, E opens it, you walk through, and spikes don't block you.

**Try it on the PC:** merge, `git pull`, `play.bat --demo-defense`. Walk to the far side and watch zombies come up the street onto the spikes and get shot over the barricades. Press T on anything they damaged.

**Known gaps:** only the nail turret (crossbow, rifle and shotgun turrets come with M15), only spike traps, no stairs or windows; turrets don't need power; a door is a full-width gate, not a doorway in a wall.

**Next:** M9, keep it: save and load, main menu, settings (mouse sensitivity, volume, day length), pause.

## 2026-10-12 — Machine art (Codex, not a milestone)

**Built:** real models for every machine and power piece (press, smelter, rain collector, purifier, planter, canner, generator, solar panel, power pole) plus concrete foundations, all made on Emmitt's PC with Codex on his ChatGPT plan (no API key).
- **Models:** each `tools/art/<id>.py` is a deterministic Blender 5.1 script that Codex wrote on the shared `tools/art/kit.py`. The kit gives one palette, merges each model into one mesh (one draw call per material), stands it on the floor of its collision box, checks that it fits, turns it to face the game's -Z front and exports `assets/models/<id>.glb`. Rebuild one with `"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --factory-startup --python tools/art/<id>.py`.
- **Conventions:** machines and generators carry a `Lamp` that `BuildView` hands to `FactoryView` with its own material, so status colours still work. Item machines show their input in INPUT_BLUE paint at the back and their output in OUTPUT_ORANGE at the front, replacing the old placeholder panels. Colliders didn't change.
- **Concrete:** a Codex photo made seamless by `tools/art/make_tileable.py` (plus a normal map), drawn world-space triplanar with one tile per 2 m cell.
- **Tests:** `test_art_models.gd` checks that every model loads, fits its box, stands on the floor, is merged into one mesh, has a lamp where needed, faces the right way (orange at -Z, blue at +Z; this caught every model facing backwards before the kit fix) and gets an unshared lamp material. 656 passed.

**Try it on the PC:** `play.bat --demo-factory` (smelter, press, generator, pole) and `play.bat --demo-farm` (rain collector, purifier, planter, canner, solar panel).

**Known gaps:** belts, walls, beds, crates and the M8 defences are still boxes. Textures import lossless with mipmaps; switch to VRAM compression after checking the cloud renderer. Codex and Blender exist only on the PC, so cloud sessions use the committed files and can't make new art. New pieces need a `tools/art/<id>.py` made on the PC (see the kit docstring) and an entry in `BuildView.MODELS`.

**Next:** M9 continues in the cloud; art for walls, belts and the defences can follow in M10.

## 2026-10-12 — M7 Power

**Built:**
- **Machines need power now:** the smelter (40 W), press (30 W), purifier (20 W) and canner (30 W). The rain collector and planter don't. A machine with no power shows a red lamp and "no power".
- **Generator** (build key, or wheel to it): 100 W, very loud (80, the design doc's example). Load it with gas cans (E). It only burns fuel in proportion to what's being used, and goes silent when nothing needs power, so turning machines off at night really does quiet the base. It takes a muffler (U) like machines do. Removing one gives back its full cans.
- **Gas:** press **G** on a car to siphon 1-3 gas cans (fixed per car by the world seed; once only; a little noise). Gas cans also turn up in car trunks and factory crates, and the starting crate has 3. They weigh 4 kg each.
- **Solar panel:** 60 W times the daylight, **completely silent**, nothing at night. Solar power is used first and generators cover the rest. This is the first quiet power source.
- **Power poles** stand on bare ground (no foundation) and link anything within 12 m, poles included. Other powered pieces link to anything right next door (3 m). Wires are drawn between linked pieces.
- **Brownouts:** if a network's machines want more than it makes, everything on that network stops and generators stop burning. The HUD shows "network: X W made / Y W wanted" and BROWNOUT when you look at anything powered.

**Rules (sim, tested):** `PowerGrid` (`src/sim/power_grid.gd`): networks (union-find), supply/demand per network, brownouts, solar-first load sharing, fuel burn, generator noise sources, muffler, refunds. Car fuel and siphoning in `SimWorld`. Numbers live in `data/buildables.json` (watts, watts_out, fuel, burn_time, reach) and `data/survival.json` (siphon noise, fuel per car).

**Tests:** 535 checks. Machines idle without power and planters don't care, a neighbour generator powers a smelter at 40% load and burns 0.4 s of fuel per second, an idle generator is silent and burns nothing, a muffled generator reads 65, poles bridge 20 m and removing one cuts power, 110 W on a 100 W generator browns everything out (and burns nothing) until the press goes, solar at noon runs a smelter, gives nothing at night and takes load off a generator at dusk, siphoning (range, once only, noise, same per seed), generator refunds, and poles needing no foundation. Older noise and factory tests run with free power.

**Try it on the PC:** merge, `git pull`, `play.bat --demo-factory` (now with a generator and pole). Look at the generator, then watch the heat with `--noise-overlay`. `play.bat --demo-farm` has a solar panel; wait for night and watch the purifier and canner stop. Siphon cars up the street with G.

**Known gaps:** no batteries or switches (a generator runs whenever something needs power); you can't choose which pole links where (it's automatic by distance); wires don't block or get cut; no wind power yet.

**Next:** M8, defend. Doors, barricades, traps, a nail turret fed by the press, structure HP and repair.

## 2026-10-12 — M6 Survive

**Built:**
- **Needs:** food, water and energy drain over time (water fastest, about a game day from full to empty). At empty food or water you lose health. **Z** eats your most filling food and **X** drinks your best drink; rainwater has to be purified first.
- **Stamina:** sprinting and swinging use it, and it comes back after a second's rest. Out of stamina: no sprint, no swing.
- **Bleeding:** zombie bites sometimes cause it (30%) and it drains health until you press **H** with a bandage.
- **Beds:** build one (**0** in build mode) and press E on it to sleep. Time runs about 8x faster while you sleep, any key or a hit wakes you, and the bed becomes where you respawn.
- **Carry weight:** every item has a weight. You can carry 20 kg, plus the best bag you have (school bag +8, hiking pack +18, military rucksack +25). Over the limit you're slower, tire faster and your footsteps are 10 louder. Over 150% you can't sprint. The HUD shows pockets and kg top right.
- **Scavenging:** a cabinet or fridge outside every house, every car's trunk and three crates by the factory can be searched (E, about 2.5 s, stay close, a little noise). Loot rolls from `data/loot.json` and never respawns.
- **Storage crates:** the starting kit now sits in a crate next to where you start. Building and hand-feeding machines use your pockets, then any crate within 30 m. Removing things refunds into the crate. E on a crate puts away building materials (food, drink, bandages and bags stay with you). A wrecked or removed crate spills its contents in a bag.
- **New machines:** rain collector (rainwater every 20 s from nothing; nearly silent), purifier (rainwater → clean water, 4 s, loud), planter (seeds + rainwater → 3 vegetables in 60 s; quiet), canner (2 vegetables + 1 metal plate → 2 canned food, 5 s; loud). Build keys go 1-9 and 0, and the mouse wheel cycles through all 11 pieces.

**Rules (sim, tested):** `PlayerStats` (all meters, stamina, bleeding, sleep, carry effects), `Loot` (tables, searching), `Stock` (pockets + nearby crates), storage, beds and respawn points in `SimWorld`. Numbers in `data/survival.json`, `data/loot.json`, `data/items.json` (weights, food/water values, bags), `data/recipes.json`.

**Tests:** 463 checks. Drain rates, starving, eating and drinking choices, stamina drain/recovery and swing cost, bites causing bleeding and bandages stopping it, sleeping and waking, respawning at the bed, weights and bag limits, overload slowing/louder steps/no sprint, building from a crate in range but not out of range, deposits, wrecked crates spilling, loot rolls staying in range and repeating with the seed, search timing, walking away cancelling a search, the water chain (3 clean water in ~65 s) and food chain (2 seeds → 6 vegetables → 6 cans), plus a physics run of searching, storing and sleeping with E, and Z/mouse-wheel through the real game.

**Try it on the PC:** merge, `git pull`, double-click `play.bat`. Walk up the street and press E on fridges, cabinets and cars. `play.bat --demo-farm` builds the water and food lines.

**Known gaps:** no inventory screen yet (Z/X/H pick the best item automatically; you can't drop or move single items); crates only take materials in, not out; loot containers stand outside houses because the houses have no insides yet; no sickness from rainwater; sleeping is 8x speed rather than an instant skip.

**Next:** M7, power. Generator, fuel siphoned from cars, poles and wires, brownouts, first quiet power source.

## 2026-10-12 — Fixes from the first PC playtest: mouse, play.bat

**Mouse didn't work (no turning, no swinging, no building):** the white crosshair dot was a HUD element that caught mouse input. A locked mouse sits in the middle of the screen, right on the dot, so the dot swallowed every look and click. Now nothing on the HUD catches the mouse. New test `test/test_main_input.gd` loads the real game scene and feeds it mouse moves and clicks the way Windows does (turn, look up, swing, build), so this can't slip past the cloud again. It failed before the fix and passes after.

**play.bat launcher:**

Problem: after pulling M5, launching Godot directly on the PC failed with "Could not find type NoiseOverlay". Godot only learns about new named scripts when it imports the project; the cloud test script does that, launching the game directly doesn't.

Fix: `play.bat` in the project folder. Double-click it to play. It refreshes Godot's script list, then starts the game. Options go after it in a terminal: `play.bat --demo-factory --noise-overlay`. If Godot ever moves, edit the path at the top of the file.

## 2026-10-12 — M5 Noise (first playable)

**Built:** the signature system. A working machine is loud (smelter 60, press 55; idle machines are silent). Sound fades with distance and each of your walls in the way takes 10 off: `heard = loudness - 20*log10(distance) - 10*walls`. Zombies listen every half second and hear anything at 20 or more by day, or 14 at night. When they hear something they walk to it; if it's a machine they wreck it, and if it's anything else they look around and wander off. Your footsteps make noise too: walking barely carries, sprinting does (a zombie 8 m away hears you sprint but not walk), and crouching is silent. Pipe hits, zombies bashing on walls and things being wrecked all make noise, so a fight draws a crowd. Look at a machine to see its loudness; **U** fits a **muffler** (4 metal plates, 8 nails): 15 quieter, 10% slower, refunded if you remove the machine. The **Director** keeps a heat score from how loud your machines are 50 m away through the leakiest side of your walls (1.5 times faster at night). Heat cools when things are quiet. Every 30 s it may send zombies in from a road end toward your loudest machine: 2 wanderers by day, and at night a group of 4 or a horde of 8. A message at the top says which way they're coming from, and a line under your materials warns when heat is building. **N** shows the noise overlay: hearing rings around machines (orange = day, blue = night, through your walls' leakiest side), white rings for one-off sounds, and a coloured mark over each zombie (grey idle, yellow investigating with a line to what it heard, red chasing, orange breaking).

**What it means in play:** a bare smelter gets noticed in about 30 s and draws wanderers. At night, groups and then hordes come. Walling a machine in on all four sides or fitting a muffler keeps the heat falling, but a single gap lets the noise out.

**Rules (sim, tested):** `NoiseField` (formula, wall counting along the grid, continuous and one-off sounds, outdoor level), `Director` (heat, waves, spending heat), `ZombieBrain` gains INVESTIGATE, and mufflers on factory machines. Tuning lives in `data/noise.json`; machine loudness in `data/buildables.json`; hearing thresholds in `data/zombies.json`. Machines now roll straight into their next item instead of pausing a tick between items. The tests caught this: the Director could look during that one silent tick.

**Tests:** 332 checks. Formula values from the design doc (80 at 1 km = 20; 60 at 100 m = 20), wall counting (straight, diagonal, through a room), machines noisy only while working, muffler numbers and refund, a zombie hearing a smelter 41 m away then wrecking it, walls stopping the sound by day but not at night, sprint vs walk, every zombie getting to hear one-off sounds, bashing drawing others, heat rising and cooling, walls or a muffler keeping things calm and a gap leaking, and day/night wave sizes.

**Try it on the PC:** merge, `git pull`, launch with `-- --demo-factory --noise-overlay` and watch the rings. Stand still and yellow lines appear as zombies come to look. Press U on the smelter, or build walls round it, and watch the heat line. Try a night with `-- --time=20 --demo-factory`.

**Known gaps:** the town's buildings don't muffle sound (only your walls do); no sound effects yet (M10); hordes don't take roads, they walk straight from a road end; zombies never stop investigating a machine that's still running unless they wreck it; a flashlight shadow glitch shows as stripes on distant faces in the cloud's software renderer (probably fine on the PC's GPU; tell me if you see it).

**Next:** First playable is done (M1–M5), so **play it** and say what feels off. Then M6, survival: hunger, thirst, fatigue, bleeding, searchable containers and loot.

## 2026-10-12 — M4 The dead

**Built:** 8 shamblers roam the sidewalks of the main street. They stroll near where they stand, spot you by sight (25 m by day, 12 m at night, but 25 m at night if your flashlight is on; they also notice you within 3 m whatever way they face), walk after you along a navmesh, and hit you for 10 every 1.2 s. If they lose you, they go to where they last saw you, look around for 4 s and give up (or give up after 20 s if they can't get there). If something you built is in the way, they hit it (10 per hit) until it breaks; wrecked pieces give no refund and lose whatever they held. Your **health** shows bottom left and the screen flashes red when you're hit. **Left-click** swings a pipe (34 damage, double on a head hit, 0.7 s between swings, knocks them back); three body hits or a head hit plus a body hit kill one, and it falls over. If you **die**, everything you carried drops in a glowing bag where you fell, and you respawn at the start 3 s later; walk back and press **E** on the bag.

**Rules (sim, tested):** `ZombieBrain` (idle → wander → chase → attack, break, dead), `Horde` (spawning, corpses cleared after 15 s), `PlayerStats` (health, swing timer, death and respawn), building hit points and wreckage in `BuildGrid`, death bags in `SimWorld`. Zombie and pipe numbers live in `data/zombies.json` and `data/weapons.json`; building hit points in `data/buildables.json`.

**World:** `NavBaker` bakes the zombie navmesh from the town at start and re-bakes in the background about a second after you build or something breaks. `ZombieBody` walks the path (or straight at you if there's no path) and reports what it sees and bumps into. `Melee`, `BagView`, health HUD and death screen. The ground is now a solid slab (the navmesh baker can't read an endless plane).

**Tests:** 263 checks. Brain: sight rules, wandering, chase → attack timing, losing you, breaking a wall, dying. Sim: dying drops a bag and respawns you at the start, swing cooldown, two zombies take a wall down, wreckage without refund. Physics runs: a zombie chases and bites, breaks a wall it can't get round, takes a head hit then a body hit and falls over, and follows the navmesh round a building to reach you. `tools/test.sh` now runs Godot with `--fixed-fps 60`, so those physics runs finish in seconds instead of in real time (the whole suite takes about 6 s).

**Try it on the PC:** merge, `git pull`, launch, walk north up the street. Back off to see them follow; swing with left-click. Build a little walled box (B) and stand inside to watch them hit the walls. `-- --zombie=0,-4` puts one right in front of you.

**Known gaps:** no stamina cost for swinging (stamina comes in M6); zombies are coloured capsules; no sounds; no zombie-on-machine attacks unless the machine is in the way; you respawn at the start, not at a bed (beds come with M6 or M9); corpses just vanish after 15 s.

**Next:** M5, noise. Machines get loud, zombies hear them, and a Director sends groups at night. That's the first playable.

## 2026-10-12 — M3 Machines and belts

**Built:** three new things in build mode: **3 belt**, **4 smelter**, **5 press**. They sit on foundations and face away from you (R turns them). A machine takes items in at its back (blue port) and pushes products out of its front (orange port). Belts carry items forward and can turn corners. The **Smelter** turns 1 scrap metal into 1 metal plate every 2 s; the **Press** turns 1 plate into 4 nails every 2 s. A lamp on each machine glows green while it works and amber when its output is full. Look at a machine (not in build mode) to see what's in it; **E** takes its output and loads it with what it needs from your pockets. E on a belt picks up the items on it. Removing a machine or belt gives back its build cost *and* everything inside it.

**Rules (sim, tested):** `Factory` (`src/sim/factory.gd`) with machines and belts on the fixed tick. Belts run at 1 cell (2 m) per second with items at least a quarter-cell apart. Each tick moves every item first, then does hand-offs, so results don't depend on build order. Recipes live in `data/recipes.json`, machines and belts in `data/buildables.json`, and item colours in `data/items.json`.

**Tests:** 169 checks. The M3 proof: smelter → 3 belts → press, hand-fed 10 scrap, gives 10 plates and then 40 nails within 28 s, with exactly 7 plates at 15 s. Also: belt speed (3 cells in 3 s), corners, no feeding a belt head-on, no feeding a machine from its side, belts backing up without overlap, output-full stop, input caps, refunds of contents including a half-made item, identical results whatever the frame rate, and a world test of looking at a machine, pressing E and seeing items drawn on belts.

**Try it on the PC:** merge, `git pull`, launch. Press B and build a row of foundations (1), a smelter (4) facing along the row, belts (3) after it, and a press (5) at the end. Press B to leave build mode, look at the smelter and press E to load scrap. Or launch with `-- --demo-factory` for a ready-made line.

**Known gaps:** each machine has one fixed recipe (no recipe picker yet); no splitters or mergers; no storage box at the end of a line; machines don't need power yet (M7) and aren't loud yet (M5); you can't place items onto a belt by hand.

**Next:** M4, the dead (zombies).

## 2026-10-12 — M2 Build

**Built:** press **B** for build mode. A see-through ghost snaps to the 2 m grid where you aim: green means you can build, red means you can't, and the HUD says why ("Needs a foundation", "Not enough materials", "Something's in the way"). **1** picks foundation, **2** picks wall, **R** turns the wall to the next edge of the square, **left-click** builds, **right-click** removes what you're looking at with a full refund. Your materials show top right; you start with a debug kit (100 planks, 100 nails, 20 scrap). Foundations are low enough to walk onto; walls are solid.

**Rules (sim, tested):** `Inventory` (all-or-nothing payments), `GameData` (loads and checks `data/items.json`, `data/buildables.json`, `data/debug_kit.json`), `BuildGrid` (grid snapping, walls need a foundation on one side, an edge shared by two squares holds only one wall, you can't pull a foundation out from under a wall, 100% refunds). Physics layers: built pieces are on their own layer so they never count as "in the way" of each other.

**Tests:** 120 checks. New: inventory, data validation (including a deliberately broken file), the build rules, and a scripted physics run: aim, build, wall on top, remove both, crate blocks placement, can't build under yourself, player walks up onto foundations and is stopped by a wall. Also a check that `main.gd` compiles, after a typo in it slipped past the tests once.

**Also:** fixed dark stripes the flashlight's shadow made on flat walls.

**Try it on the PC:** merge, `git pull`, launch, press B, look at the ground and left-click. Press 2 for walls and build them on the edges of your foundations.

**Known gaps:** no build menu yet (number keys only); no doorways, doors, windows or stairs (doors and barricades come in M8); nothing saves (M9); materials only come from the debug kit until scavenging (M6); foundations only sit at ground level (no stacking or second floors).

**Next:** M3, machines and belts.

## 2026-10-12 — M1 Walk the town

**Built:** first-person `Player` (`src/world/player.gd`): WASD, mouse look, Shift sprint, Space jump, Ctrl/C crouch (won't stand up under a low ceiling), F flashlight, Esc frees the mouse and a click grabs it back. Input keys are registered in one place (`src/world/input_setup.gd`). New `SimWorld` (`src/sim/sim_world.gd`) steps all game rules on a fixed 20-per-second tick; the clock now runs there, and later systems (machines, noise, zombies) hook into `SimWorld.step()`. HUD shows day + clock, a centre dot and a key-hint line. New screenshot flags `--cam=X,Y,Z,YAW,PITCH` and `--flashlight`.

**Tests:** 39 checks. New: fixed-tick determinism (same result however frames are sliced), and a scripted physics run proving the player walks forward, sprints faster, crouches slower, jumps and lands, is **blocked by a wall**, and stays crouched under a low slab. The test runner now supports tests that `await` physics frames.

**Cloud bootstrap verified:** first cloud session; the setup hook printed `godot 4.7-stable ok | screenshots ok`, tests and screenshots work in the cloud.

**Try it on the PC:** pull/merge, then `C:/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe --path C:/projects/noise-floor`. Click into the window, walk around, wait for night (about 11 real minutes from the 08:00 start, or launch with `-- --time=20`) and press F.

**Known gaps:** mouse sensitivity is fixed (settings come in M9); no stamina yet (sprint is unlimited until M6); no footstep sounds; nothing to do in town yet. Flashlight and lighting were tuned on the cloud's flat software renderer, so they may look brighter on the PC.

**Next:** M2 — Build.

## 2026-10-12 — M0 Skeleton

**Built:** Godot 4.7 project; greybox town (road, 12 block houses, 4 cars, the factory at the north end) built in code (`src/world/main.gd`); day/night sun + moon driven by `GameClock` (`src/sim/game_clock.gd`: 1 real minute = 1 hour, sun up 05:00–21:00); zero-dependency headless test runner (18 checks); screenshot tool; cloud bootstrap hook that installs pinned Godot + Xvfb/Mesa.

**Verified on Emmitt's PC:** `tools/test.sh` green; runner correctly reports a failing check and a crashing test; screenshots render in both Forward+ and the Compatibility renderer (the one cloud sessions use); nights are properly dark.

**Not yet verified:** the cloud bootstrap itself. The first cloud session should confirm the `cloud-setup:` status line says `ok` for both Godot and screenshots.

**Try it on the PC:** `C:/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe --path C:/projects/noise-floor` (camera is fixed; time passes at 1 hour per minute).

**Next:** M1 — Walk the town.
