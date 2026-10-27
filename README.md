# Noise Floor

First-person survival automation. Scavenge to survive, build machines and belts to automate, and remember: **machines make noise, and noise draws the dead.**

- Design and milestones: [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)
- Progress log: [docs/DEVLOG.md](docs/DEVLOG.md)
- How Claude works on it: [CLAUDE.md](CLAUDE.md)

## Play on Windows

**Download:** [NoiseFloor-windows.zip](https://github.com/efenn-dev/noise-floor/releases/latest) (under "Assets"). Unzip it and double-click `NoiseFloor.exe`. If Windows says it protected your PC, click **More info**, then **Run anyway**. Nothing else to install. It's rebuilt automatically every time `main` changes.

Developing on the PC instead: double-click `play.bat` in a clone of this repo (needs Godot 4.7).

## Develop

```bash
tools/test.sh               # headless tests
tools/shot.sh day --time=10 # screenshot to .shots/day.png
```

Built with Godot 4.7 (GDScript 2.0).

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Emmitt Fennessey.
