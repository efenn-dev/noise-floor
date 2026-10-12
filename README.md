# Noise Floor

First-person survival automation. Scavenge to survive, build machines and belts to automate, and remember: **machines make noise, and noise draws the dead.**

- Design and milestones: [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)
- Progress log: [docs/DEVLOG.md](docs/DEVLOG.md)
- How Claude works on it: [CLAUDE.md](CLAUDE.md)

## Play on Windows

```bash
C:/projects/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64.exe --path C:/projects/noise-floor
```

Pull the latest first: `git -C C:/projects/noise-floor pull`.

## Develop

```bash
tools/test.sh               # headless tests
tools/shot.sh day --time=10 # screenshot to .shots/day.png
```

Built with Godot 4.7 (GDScript 2.0).
