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

## 2026-10-13 — Emmitt, length not recorded (verbal with a screenshot, relayed by the lead), build 23f1433 (everything through PR #41)
- First five minutes: not recorded. "The game is pretty cool now."
- Fun: not recorded.
- Confusing: **driving does not work.** The screenshot shows him standing beside the red sedan with a car key in his pockets, the car at gas 1.0 and the driving-keys message ("W/S gas and brake · A/D steer ...") stacked eight times down the screen: eight presses of E, each one in and straight back out. Cause found in the code: the Interactor got him in, then the same E press reached main.gd, where E while driving means get out. **Doors:** once a door is open you can't close it (the open door was on no collision layer, so the look ray never found it again) and you walk straight through the open panel.
- Death: not recorded.
- Wanted: **a hotbar for items like Satisfactory, and a build menu**, where anything from the build menu or any usable item can be put on a hotbar key.
- Fix first: driving, then doors, then the hotbar and build menu (all three in S3, the first Sprint 3 pull request).
- Session log: not supplied.

## 2026-10-12 — Emmitt, length not recorded (verbal, relayed by the lead), build 15f2c95 (M10c: play.bat had not picked up PRs #16–#18)
- First five minutes: looked for a way into the houses; there is none. The houses are closed boxes.
- Fun: not recorded.
- Confusing: cars. Pressed E on cars and could not drive them (most need a key from the trunk or a house, and one is a wreck; nothing on screen said so).
- Death: not recorded.
- Wanted: to go inside buildings; to drive a car.
- Fix first: doors and interiors (Sprint 2, W1). Car prompts that explain keys, and a visible build version (P1).
- Session log: none (the build predates P0).
