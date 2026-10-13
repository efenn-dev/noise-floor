"""Make the game's machine, ambience and impact sounds from scratch (no samples, deterministic).

Loops are built by shaping noise in the frequency domain over exactly one loop length, which makes
them wrap around without a click; every periodic part has a whole number of cycles per loop. Loop
points are written into the WAV ("smpl" chunk), so Godot's importer loops them by itself.
Zombie voices are CC0 recordings instead (assets/CREDITS.md): made-up moans sound fake.

Usage:
    python tools/audio/synth.py            -> assets/sounds/*.wav
    python tools/audio/synth.py --only shot_pistol reload   -> just those (M14 added the guns this way)
"""

import argparse
import logging
import struct
import zlib
from pathlib import Path

import numpy as np

log = logging.getLogger("synth")
SR = 32000
OUT = Path(__file__).resolve().parents[2] / "assets" / "sounds"
rng = np.random.default_rng(7)  # reseeded per sound in main(), so adding a sound never changes the others


# ---------- building blocks ----------

def seconds(n: float) -> int:
    """Sample count for a duration."""
    return int(round(n * SR))


def t_axis(n: int) -> np.ndarray:
    """Time in seconds for n samples."""
    return np.arange(n) / SR


def noise(n: int) -> np.ndarray:
    """White noise, deterministic across runs."""
    return rng.standard_normal(n)


def shape(x: np.ndarray, gain) -> np.ndarray:
    """Filter by multiplying the spectrum by gain(freqs). Circular, so a loop-length input stays loopable."""
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    f[0] = 1e-3
    return np.fft.irfft(spec * gain(f), len(x))


def lp(fc: float, order: int = 2):
    """Low-pass gain curve."""
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def hp(fc: float, order: int = 2):
    """High-pass gain curve."""
    return lambda f: (f / fc) ** order / np.sqrt(1 + (f / fc) ** (2 * order))


def bp(fc: float, octaves: float):
    """Band-pass gain curve: a bell `octaves` wide around fc."""
    return lambda f: np.exp(-0.5 * (np.log2(f / fc) / octaves) ** 2)


def pink(f: np.ndarray) -> np.ndarray:
    """1/f power (pink) tilt."""
    return 1 / np.sqrt(f)


def oneshot_noise(n: int, gain) -> np.ndarray:
    """Filtered noise for a one-shot: padded so the circular filter can't wrap the tail onto the head."""
    return shape(noise(n * 2), gain)[:n]


def decay(n: int, tau: float, attack: float = 0.002) -> np.ndarray:
    """Exponential decay envelope with a short linear attack."""
    t = t_axis(n)
    return np.minimum(t / attack, 1.0) * np.exp(-t / tau)


def place(buf: np.ndarray, sound: np.ndarray, at: float, wrap: bool = True) -> None:
    """Add `sound` into `buf` starting at `at` seconds, wrapping past the end (loops) or cutting it off."""
    i = seconds(at)
    for k in range(len(sound)):
        j = i + k
        if j >= len(buf):
            if not wrap:
                break
            j %= len(buf)
        buf[j] += sound[k]


def thump(length: float, f0: float, f1: float, tau: float) -> np.ndarray:
    """A low hit: a sine sliding from f0 to f1 under a fast decay."""
    n = seconds(length)
    t = t_axis(n)
    freq = f1 + (f0 - f1) * np.exp(-t / (tau * 0.6))
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * decay(n, tau)


def clank(length: float, partials: list[tuple[float, float, float]]) -> np.ndarray:
    """A metal or wood knock from inharmonic partials: (frequency, level, decay seconds)."""
    n = seconds(length)
    t = t_axis(n)
    out = sum(a * np.sin(2 * np.pi * f * t) * decay(n, d) for f, a, d in partials)
    return out + 0.3 * oneshot_noise(n, bp(2500, 1.2)) * decay(n, 0.01)


def periodic_wobble(n: int, cycles: list[tuple[int, float]]) -> np.ndarray:
    """Slow amplitude movement that repeats exactly once per loop: (cycles per loop, depth)."""
    t = np.arange(n) / n
    return 1 + sum(d * np.sin(2 * np.pi * c * t + c) for c, d in cycles)


def tone(n: int, harmonics: list[tuple[float, float]]) -> np.ndarray:
    """Sum of sines (frequency, level); pick frequencies with whole cycles per loop."""
    t = t_axis(n)
    return sum(a * np.sin(2 * np.pi * f * t) for f, a in harmonics)


def normalize(x: np.ndarray, peak_db: float = -3.0) -> np.ndarray:
    """Scale to a peak level in dBFS."""
    return x / (np.max(np.abs(x)) + 1e-9) * 10 ** (peak_db / 20)


def fade_edges(x: np.ndarray, ms: float = 4.0) -> np.ndarray:
    """Short fades on a one-shot so it never starts or stops with a click."""
    k = min(len(x) // 2, int(SR * ms / 1000))
    x = x.copy()
    x[:k] *= np.linspace(0, 1, k)
    x[-k:] *= np.linspace(1, 0, k)
    return x


def write_wav(name: str, x: np.ndarray, loop: bool) -> None:
    """16-bit mono WAV; loops get a "smpl" chunk spanning the whole file."""
    pcm = np.clip(x * 32767, -32768, 32767).astype("<i2").tobytes()
    fmt = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, SR, SR * 2, 2, 16)
    data = struct.pack("<4sI", b"data", len(pcm)) + pcm
    smpl = b""
    if loop:
        body = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        body += struct.pack("<6I", 0, 0, 0, len(x) - 1, 0, 0)
        smpl = struct.pack("<4sI", b"smpl", len(body)) + body
    chunks = fmt + data + smpl
    path = OUT / f"{name}.wav"
    path.write_bytes(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)
    log.info("%-18s %5.2f s %s %4d KiB", name, len(x) / SR, "loop" if loop else "    ", path.stat().st_size // 1024)


# ---------- the sounds ----------

def smelter() -> np.ndarray:
    """Furnace roar: dark rumbling noise that breathes, mains hum, and crackles."""
    n = seconds(6)
    roar = shape(noise(n), lambda f: pink(f) * lp(700, 2)(f) * (1 + 1.5 * bp(250, 0.8)(f)))
    roar = normalize(roar, 0) * periodic_wobble(n, [(3, 0.18), (7, 0.07)])
    hum = tone(n, [(50, 0.10), (100, 0.07), (150, 0.03)])
    crackle = np.zeros(n)
    pop = oneshot_noise(seconds(0.03), hp(1800)) * decay(seconds(0.03), 0.006)
    for at in rng.uniform(0, 6, 40):
        place(crackle, pop * rng.uniform(0.2, 0.7), at)
    return normalize(roar * 0.8 + hum + crackle * 0.5, -4)


def press() -> np.ndarray:
    """Hydraulic press: motor drone, then two strokes per loop (hiss, slam, ring)."""
    n = seconds(2.4)
    motor = tone(n, [(120, 0.12), (240, 0.06), (360, 0.03), (480, 0.015)])
    motor += 0.04 * normalize(shape(noise(n), bp(900, 1.5)), 0)
    out = motor * periodic_wobble(n, [(2, 0.1)])
    hiss_n = seconds(0.35)
    hiss = oneshot_noise(hiss_n, bp(4000, 1.0)) * np.sin(np.linspace(0, np.pi, hiss_n)) ** 2
    for start in (0.25, 1.45):
        place(out, 0.25 * normalize(hiss, 0), start)
        place(out, 0.9 * thump(0.4, 110, 45, 0.12), start + 0.36)
        place(out, 0.35 * clank(0.5, [(523, 1.0, 0.12), (1310, 0.6, 0.08), (2270, 0.4, 0.05)]), start + 0.36)
    return normalize(out, -4)


def purifier() -> np.ndarray:
    """Water pump: a low pulsing thrum, a faint motor whine and bubbling water."""
    n = seconds(3)
    t = t_axis(n)
    pulse = (0.5 + 0.5 * np.sin(2 * np.pi * 8 * t)) ** 4  # 8 pump strokes a second
    thrum = normalize(shape(noise(n), lp(160, 3)), 0) * pulse * 0.7
    whine = tone(n, [(440, 0.02), (880, 0.008)])
    bubbles_env = normalize(np.abs(shape(noise(n), lp(9, 2))), 0)
    water = normalize(shape(noise(n), bp(1200, 1.2)), 0) * bubbles_env * 0.35
    return normalize(thrum + whine + water, -5)


def canner() -> np.ndarray:
    """Canning line: a motor bed under a rhythm of tin clinks and one sealing thunk per loop."""
    n = seconds(2)
    out = tone(n, [(90, 0.08), (180, 0.04)]) + 0.03 * normalize(shape(noise(n), bp(700, 1.5)), 0)
    tins = [[(1800, 1.0, 0.08), (2950, 0.7, 0.05), (4100, 0.4, 0.03)],
            [(1650, 1.0, 0.08), (2700, 0.6, 0.06), (3900, 0.4, 0.03)]]
    for i, at in enumerate((0.0, 0.5, 1.0, 1.5)):
        place(out, 0.4 * clank(0.25, tins[i % 2]), at)
    place(out, 0.7 * thump(0.3, 150, 70, 0.07), 1.02)
    return normalize(out, -5)


def generator() -> np.ndarray:
    """Small petrol engine: 25 firing pops a second through a boxy resonance, with valve clatter."""
    n = seconds(2)
    out = np.zeros(n)
    pop_n = seconds(0.05)
    for k in range(50):
        pop = oneshot_noise(pop_n, lambda f: lp(900, 2)(f) * (1 + 3 * bp(170, 0.5)(f))) * decay(pop_n, 0.012)
        place(out, pop * (0.8 + 0.3 * np.sin(k * 1.7)), k / 25 + 0.002 * np.sin(k * 2.3))
    out = normalize(out, 0)
    clatter = normalize(shape(noise(n), hp(2500)), 0) * 0.05
    rumble = tone(n, [(25, 0.25), (50, 0.15)])
    return normalize(out + clatter + rumble, -3)


def car_engine() -> np.ndarray:
    """A worn four-cylinder at idle: 26 smooth firing pulses a second through a low exhaust resonance.
    The game raises its pitch with speed."""
    n = seconds(2)
    out = np.zeros(n)
    pop_n = seconds(0.06)
    for k in range(52):
        pop = oneshot_noise(pop_n, lambda f: lp(500, 2)(f) * (1 + 4 * bp(120, 0.45)(f))) * decay(pop_n, 0.02, attack=0.004)
        place(out, pop * (0.85 + 0.15 * np.sin(k * 0.9)), k / 26 + 0.0015 * np.sin(k * 1.7))
    out = normalize(out, 0)
    rumble = tone(n, [(26, 0.3), (52, 0.18), (78, 0.08)])
    hiss = 0.03 * normalize(shape(noise(n), bp(1800, 1.2)), 0)
    return normalize(out + rumble + hiss, -4)


def horn() -> np.ndarray:
    """A car horn: two buzzy tones a little under a minor third apart, through a tinny resonance."""
    n = seconds(0.75)
    t_ = t_axis(n)
    buzz = sum(np.sign(np.sin(2 * np.pi * f * t_)) * a for f, a in ((415, 1.0), (494, 0.8)))
    out = np.concatenate([buzz, np.zeros(n)])
    out = shape(out, lambda f: bp(1400, 1.3)(f) + 0.4 * lp(900, 2)(f))[:n]
    env = np.minimum(t_ / 0.012, 1.0) * np.minimum((t_[-1] - t_) / 0.04, 1.0)
    return fade_edges(normalize(out * env, -3))


def wind(night: bool) -> np.ndarray:
    """Wind bed. Night is colder: whistling bands that swell in turn over a low rumble."""
    n = seconds(10 if night else 8)
    base = normalize(shape(noise(n), lambda f: pink(f) * lp(500 if night else 700, 2)(f)), 0)
    out = base * periodic_wobble(n, [(2, 0.35), (3, 0.2)]) * 0.6
    if night:
        for fc, c in ((310, 3), (430, 4), (585, 5)):
            band = normalize(shape(noise(n), bp(fc, 0.08)), 0)
            out += 0.22 * band * np.clip(periodic_wobble(n, [(c, 0.9)]) - 0.6, 0, None)
        out += 0.4 * normalize(shape(noise(n), lp(90, 3)), 0)
    else:
        rustle = normalize(shape(noise(n), bp(4500, 0.6)), 0)
        out += 0.08 * rustle * np.clip(periodic_wobble(n, [(5, 0.8)]) - 0.5, 0, None)
    return normalize(out, -8)


def footstep(variant: int) -> np.ndarray:
    """A step on grit and asphalt: a soft, dull heel thud, then a gentle scuff. Nothing sharp or clicky
    (the first version's bright grit crackle read as a click, not a step)."""
    n = seconds(0.34)
    heel = oneshot_noise(n, lp(130 + 15 * variant, 2)) * decay(n, 0.03, attack=0.007)
    thud = thump(0.34, 90 + 6 * variant, 55, 0.035)
    lag = seconds(0.03 + 0.006 * variant)  # the scuff comes as the foot rolls
    scuff_env = np.concatenate([np.zeros(lag), decay(n - lag, 0.06, attack=0.025)])
    scuff = oneshot_noise(n, bp(650 + 70 * variant, 1.1)) * scuff_env
    out = 0.7 * normalize(heel, 0) + 0.45 * thud + 0.16 * normalize(scuff, 0)
    out = np.concatenate([out, np.zeros(n)])
    out = shape(out, lp(2500, 2))[:n]  # dull it: nothing bright left
    return fade_edges(normalize(out, -12))


def swing() -> np.ndarray:
    """Pipe swing whoosh: a noise band that rises and swells."""
    n = seconds(0.32)
    t = np.linspace(0, 1, n)
    low = oneshot_noise(n, bp(450, 0.7)) * np.sin(np.pi * np.clip(t * 1.6, 0, 1)) ** 2
    high = oneshot_noise(n, bp(1400, 0.7)) * np.sin(np.pi * np.clip(t * 1.6 - 0.5, 0, 1)) ** 2
    return fade_edges(normalize(low + high, -8))


def hit_body() -> np.ndarray:
    """Pipe hitting a zombie: a heavy dull thud with a wet slap."""
    n = seconds(0.3)
    slap = oneshot_noise(n, bp(1100, 0.8)) * decay(n, 0.018)
    return fade_edges(normalize(thump(0.3, 140, 55, 0.08) + 0.5 * normalize(slap, 0), -3))


def bash() -> np.ndarray:
    """Something heavy hitting a wall or barricade: wood knock, rattle and a low boom."""
    knock = clank(0.5, [(185, 1.0, 0.09), (410, 0.7, 0.06), (690, 0.4, 0.04), (1250, 0.2, 0.03)])
    n = len(knock)
    rattle = oneshot_noise(n, bp(3000, 1.0)) * decay(n, 0.06, attack=0.01)
    return fade_edges(normalize(knock + 0.8 * thump(0.5, 90, 40, 0.15) + 0.2 * normalize(rattle, 0), -3))


def turret_shot() -> np.ndarray:
    """Pneumatic nail gun: a sharp clack, a burst of air and a thunk."""
    n = seconds(0.3)
    clack = oneshot_noise(n, hp(2000)) * decay(n, 0.004)
    air = oneshot_noise(n, bp(5000, 1.0)) * decay(n, 0.04, attack=0.003)
    return fade_edges(normalize(normalize(clack, 0) + 0.5 * normalize(air, 0) + 0.6 * thump(0.3, 220, 90, 0.04), -3))


def door() -> np.ndarray:
    """A scrap door: a short hinge creak, then the latch clacks shut."""
    n = seconds(0.7)
    t = t_axis(n)
    rate = 55 + 25 * np.sin(2 * np.pi * 1.3 * t) + 8 * shape(noise(n), lp(20, 2)) / 0.02
    phase = np.cumsum(np.clip(rate, 20, 140)) / SR
    creak = shape(((phase % 1.0) < 0.08).astype(float) - 0.08, bp(1500, 0.7))
    creak *= np.sin(np.pi * np.clip(t / 0.5, 0, 1)) ** 2
    out = 0.6 * normalize(creak, 0)
    place(out, clank(0.2, [(900, 1.0, 0.03), (2300, 0.6, 0.02)]), 0.5, wrap=False)
    return fade_edges(normalize(out, -5))


def build_place() -> np.ndarray:
    """A piece set down: a woody clunk."""
    knock = clank(0.3, [(240, 1.0, 0.06), (530, 0.5, 0.04), (960, 0.25, 0.02)])
    return fade_edges(normalize(knock + 0.6 * thump(0.3, 120, 60, 0.06), -6))


def click() -> np.ndarray:
    """Flashlight switch."""
    n = seconds(0.05)
    return fade_edges(normalize(oneshot_noise(n, bp(3500, 0.8)) * decay(n, 0.003), -10), ms=1)


def gunshot(rifle: bool, suppressed: bool) -> np.ndarray:
    """A gunshot (M14). Open: a hard crack, a low boom and a long rolling tail off the houses (the rifle
    deeper and longer). Suppressed: no crack, a muffled thump and a short puff of gas with the action's clack."""
    length = 1.6 if rifle else 1.1
    n = seconds(length)
    if suppressed:
        puff = oneshot_noise(n, bp(900 if rifle else 1300, 1.2)) * decay(n, 0.05 if rifle else 0.035, attack=0.002)
        clack = clank(length, [(2400, 1.0, 0.012), (3900, 0.6, 0.008)])
        out = normalize(puff, 0) + 0.8 * thump(length, 160 if rifle else 220, 60, 0.05) + 0.35 * normalize(clack, 0)
        return fade_edges(normalize(out, -6))
    crack = oneshot_noise(n, hp(1800)) * decay(n, 0.006, attack=0.0005)
    boom = thump(length, 110 if rifle else 150, 38 if rifle else 50, 0.16 if rifle else 0.1)
    tail = oneshot_noise(n, lp(700 if rifle else 1000, 2)) * decay(n, 0.45 if rifle else 0.3, attack=0.02)
    out = normalize(crack, 0) + 1.2 * boom + 0.45 * normalize(tail, 0)
    return fade_edges(normalize(out, -1))


def reload_click() -> np.ndarray:
    """A magazine going in and the slide racking: two metal clicks."""
    n = seconds(0.45)
    out = np.zeros(n)
    place(out, clank(0.12, [(1800, 1.0, 0.015), (3100, 0.5, 0.01)]), 0.02, wrap=False)
    place(out, clank(0.15, [(1200, 1.0, 0.02), (2600, 0.7, 0.012)]) + 0.4 * thump(0.15, 300, 150, 0.02), 0.27, wrap=False)
    return fade_edges(normalize(out, -8))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", nargs="*", default=None, help="make only these sounds (by file name)")
    only = parser.parse_args().only
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    OUT.mkdir(parents=True, exist_ok=True)
    loops = {"hum_smelter": smelter, "hum_press": press, "hum_purifier": purifier, "hum_canner": canner,
             "engine_generator": generator, "engine_car": car_engine, "wind_day": lambda: wind(False),
             "wind_night": lambda: wind(True)}
    shots = {"swing": swing, "hit_body": hit_body, "bash": bash, "turret_shot": turret_shot, "door": door,
             "build_place": build_place, "click": click, "horn": horn,
             "shot_pistol": lambda: gunshot(False, False), "shot_rifle": lambda: gunshot(True, False),
             "shot_pistol_suppressed": lambda: gunshot(False, True), "shot_rifle_suppressed": lambda: gunshot(True, True),
             "reload": reload_click}
    global rng
    for name, make in loops.items():
        if only is not None and name not in only:
            continue
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write_wav(name, make(), loop=True)
    for i in range(4):
        if only is not None and f"step_{i + 1}" not in only:
            continue
        rng = np.random.default_rng(zlib.crc32(f"step_{i + 1}".encode()))
        write_wav(f"step_{i + 1}", footstep(i), loop=False)
    for name, make in shots.items():
        if only is not None and name not in only:
            continue
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write_wav(name, make(), loop=False)


if __name__ == "__main__":
    main()
