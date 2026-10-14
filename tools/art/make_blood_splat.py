"""Draw a blood splat (dark red, soft-edged, with droplets) as an RGBA PNG for decals.

V7 (Sprint 4). A lumpy central blob made from a few overlapping soft circles, roughened by noise,
with a scatter of small droplets flung out to one side. Deterministic (fixed seed).

    python tools/art/make_blood_splat.py            -> assets/textures/blood_splat.png
"""

import argparse
import logging
from pathlib import Path

import numpy as np
from PIL import Image

LOG = logging.getLogger("splat")
OUT = Path(__file__).resolve().parents[2] / "assets" / "textures" / "blood_splat.png"
COLOUR = (78, 6, 6)  # dried-dark red; the decal's own tint and the light do the rest


def blob(xs: np.ndarray, ys: np.ndarray, cx: float, cy: float, r: float) -> np.ndarray:
    """A soft disc, 1 inside, fading to 0 just past r."""
    d = np.hypot(xs - cx, ys - cy) / r
    return np.clip(1.4 - d, 0.0, 1.0)


def splat(size: int, seed: int) -> np.ndarray:
    """Alpha 0-1 for a size x size splat."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64) / size
    a = np.zeros((size, size))
    for _ in range(7):  # the main pool: overlapping lumps near the middle
        cx, cy = 0.5 + rng.normal(0, 0.07, 2)
        a = np.maximum(a, blob(xs, ys, cx, cy, rng.uniform(0.12, 0.22)))
    angle = rng.uniform(0, 2 * np.pi)
    for _ in range(26):  # droplets flung out, mostly one way
        dist = rng.uniform(0.22, 0.46)
        spread = rng.normal(0, 0.6)
        cx = 0.5 + np.cos(angle + spread) * dist
        cy = 0.5 + np.sin(angle + spread) * dist
        a = np.maximum(a, blob(xs, ys, cx, cy, rng.uniform(0.008, 0.03)))
    coarse = Image.fromarray(((rng.normal(0, 1, (size // 16, size // 16)) * 40) + 128).clip(0, 255).astype(np.uint8))
    grain = (np.asarray(coarse.resize((size, size), Image.BICUBIC), dtype=np.float64) - 128.0) / 40.0
    raw = a + grain * 0.18  # smooth noise: ragged edges instead of perfect circles
    a = np.clip((raw - 0.45) / 0.18, 0.0, 1.0)  # a fairly crisp edge, like a real stain
    a = a * a * (3.0 - 2.0 * a)
    edge = np.hypot(xs - 0.5, ys - 0.5)
    return a * (edge < 0.49)  # nothing touches the border (decals clamp at their edges)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--size", type=int, default=256, help="square size in pixels")
    parser.add_argument("--seed", type=int, default=3, help="shape seed")
    parser.add_argument("--out", type=Path, default=OUT, help="output PNG")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    alpha = splat(args.size, args.seed)
    rgba = np.zeros((args.size, args.size, 4), dtype=np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = COLOUR
    rgba[..., 3] = (alpha * 255.0 + 0.5).astype(np.uint8)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba).save(args.out)
    LOG.info("wrote %s", args.out)


if __name__ == "__main__":
    main()
