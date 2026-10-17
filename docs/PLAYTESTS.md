# Playtests

Newest first. Every session reads the top entry before doing anything else (see `docs/DIRECTION.md`).
Add an entry after playing at least 30 minutes on `main` via `play.bat`. Short answers are fine; "I don't know" is fine.

## Template

```
## YYYY-MM-DD — who, minutes played, commit (git log -1 --format=%h on main)
- First five minutes: what did you do, and did you know what to do?
- Fun: the moment you'd tell someone about.
- Confusing: what you couldn't work out, or expected to work and didn't.
- Death: what killed you, and did it feel fair?
- Wanted: the thing you tried to do and couldn't.
- Fix first: the one change you most want next.
- Session log: paste user://sessions/<date>.txt here if the game wrote one.
```

## 2026-10-16 (night) — Emmitt, screenshots, build 43be875
- Hands: "much better but the left hand should be palm up and the arm is floating. the axe has a finger that looks off, maybe rethink the grip with 2 hands. pistol looks a bit weird but acceptable for now."
- Scope: "I found a scope but it doesn't zoom in much and has no reticle".
- Fixed in V39.

## 2026-10-16 (late) — Emmitt watching his son's stream (screenshots), son's PC
- Broken: "those hands and arms look cursed. theres a white pole going through them and the fingers still look like before" (fists and the police pump shotgun).
- Cause: his copy ran the new arm models with the OLD hands.gd. The old code always adds a sleeve tube (white, since the new model has no "Arm Sleeve" for it to borrow) and the old loose fist. An update closed halfway: robocopy copies `assets\` before `src\`, and the old Expand-Archive takes 25 s on this PC, longer on his. His logs never arrived either, because the new update.ps1 is only installed at the very end of an update. Fixed in P7 (the updater swaps whole folders).

## 2026-10-16 (night) — Emmitt, verbal (relayed in the session), build dc78b2d (V37 arms)
- Arms: "those models don't really look like the ones we purchased but its much better than before".
- Fix first: "the axe, it looks more like a sledgehammer". Fixed in V38.

## 2026-10-16 (evening) — Emmitt's son with Emmitt, verbal (relayed in the session), build 6bda979 (P5)
- Confusing: "we removed a door and added our own and it disappeared when using it. Then we couldnt add a new door." He got frustrated. The logs were on his PC, which never sent them anywhere.
- Reproduced in the game scene: taking a piece down (right-click in build mode) said nothing, so a door clicked on in build mode just vanished. Then, looking at the empty doorway, the door ghost went past it onto a wall inside the house ("Already built"). Building on the lawn just outside was the only way in. Fixed in P6. The launcher now copies his session logs to R:/Reserve/Noise Floor/logs/.

## 2026-10-16 — Emmitt, verbal (relayed in the session), build 6c486b6 (F6 part 2)
- Confusing: "one of the reasons I didn't like building in the game was because the conveyor belts were hard to tell if they snapped into a machine like in satisfactory. I just built a machine with conveyor belts around all sides and still didn't know how it worked." Machines take input only at the back and give output at the front, and nothing showed which side was which or whether a belt connected. Fixed in P4: IN/OUT arrows on every machine and its ghost, belts that snap, a green tick or red X at every belt end, look-at lines that say what feeds what. Then (after seeing it): "can we make the graphics a bit better where the belt actually connects to the machines so items don't look like they float over the belts?" (P4: chutes and port frames) and "how should we make users gather materials for things like the smelter?" (P5: gather by hand at resource nodes, and the build line says what's missing and where it comes from).

## 2026-10-13 (late) — Emmitt, about 20 minutes, build 2761b62 (everything through #51)
- Broken: walking over dead bodies pushes them around ("make them much more grounded"). Fixed in S5.
- Broken: got into the car and couldn't drive. The log showed the pickup going NaN every tick. Fixed in S5 (grounded bodies, fresh wheels, Jolt Physics).
- Asked: "Is there any physics engine we could use?" Jolt Physics (built into Godot 4.7), adopted in S5.
- Asked: "lets work on making things destructible like windows". That's W2.

## 2026-10-13 (night) — Emmitt, about 1 minute (session log 2026-10-13_1929), build 1c6ffcd (V1 lighting + V3 game feel)
- Liked: "looks good" (the Sprint 4 lighting and feel).
- Broken: "when I got into the car the game bugged out". The log shows a NaN car and 28,000 warnings in a minute. Contained in the car NaN fix (see DEVLOG).

## 2026-10-13 — Emmitt, length not recorded (verbal with a screenshot, relayed by the lead), build 23f1433 (everything through PR #41)
- First five minutes: not recorded. "The game is pretty cool now."
- Fun: not recorded.
- Confusing: **driving does not work.** The screenshot shows him standing beside the red sedan with a car key in his pockets, the car at gas 1.0 and the driving-keys message ("W/S gas and brake · A/D steer ...") stacked eight times down the screen: eight presses of E, each one in and straight back out. Cause found in the code: the Interactor got him in, then the same E press reached main.gd, where E while driving means get out. **Doors:** once a door is open you can't close it (the open door was on no collision layer, so the look ray never found it again) and you walk straight through the open panel.
- Death: not recorded.
- Wanted: **a hotbar for items like Satisfactory, and a build menu**, where anything from the build menu or any usable item can be put on a hotbar key.
- Fix first: driving, then doors, then the hotbar and build menu (all three in S3, the first Sprint 3 pull request).
- Session log: not supplied.
- **Second message, same evening (after S3 was up):** "give the hotbar pictures and work on better textures for the gun and zombies. Zombies look great but I want them to be lootable like in Zomboid and we will eventually add clothes so each one can be unique. There is a lot of work to do and I don't want to get crazy on you. I'd like jumpscare sounds when a zombie surprises you around a corner or a large mob gets aggroed like in Zomboid. I was also not able to figure out the building and machines." → S4: pictures, lootable corpses, the two stings, and a first-factory walkthrough in the hints, the build menu and F1. Textures and clothes: an art pass with Codex, next.

## 2026-10-12 — Emmitt, length not recorded (verbal, relayed by the lead), build 15f2c95 (M10c: play.bat had not picked up PRs #16–#18)
- First five minutes: looked for a way into the houses; there is none. The houses are closed boxes.
- Fun: not recorded.
- Confusing: cars. Pressed E on cars and could not drive them (most need a key from the trunk or a house, and one is a wreck; nothing on screen said so).
- Death: not recorded.
- Wanted: to go inside buildings; to drive a car.
- Fix first: doors and interiors (Sprint 2, W1). Car prompts that explain keys, and a visible build version (P1).
- Session log: none (the build predates P0).
