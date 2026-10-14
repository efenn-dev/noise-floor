"""Draw the flashlight's beam pattern (a light "cookie") as a grey PNG for SpotLight3D.light_projector.

V1 (Sprint 4). A real torch beam isn't a flat disc: a bright hot spot, a faint ring from the reflector,
a darker band, then a wide dim spill that fades out, with a few soft smudges from a dirty lens.
Deterministic (fixed seed), so re-running gives the same file.

    python tools/art/make_flashlight_cookie.py            -> assets/textures/flashlight_cookie.png
"""

import argparse
import logging
from pathlib import Path

import numpy as np
from PIL import Image

LOG = logging.getLogger("cookie")
OUT = Path(__file__).resolve().parents[2] / "assets" / "textures" / "flashlight_cookie.png"


def smooth(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    """Hermite smoothstep, like GLSL's."""
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def beam(size: int, seed: int) -> np.ndarray:
    """Brightness 0-1 for a size x size cookie; r = 1 at the edge of the spotlight's cone."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    c = (size - 1) / 2.0
    r = np.hypot(xs - c, ys - c) / c
    hot = 1.0 - smooth(0.0, 0.42, r) * 0.45          # hot spot easing to 0.55
    ring = np.exp(-((r - 0.5) / 0.035) ** 2) * 0.18  # the reflector's bright ring
    band = np.exp(-((r - 0.58) / 0.05) ** 2) * 0.12  # the darker band just outside it
    spill = (1.0 - smooth(0.55, 1.0, r)) * 0.3        # wide dim spill
    v = np.maximum(hot * (1.0 - smooth(0.5, 0.62, r)), spill) + ring - band
    rng = np.random.default_rng(seed)
    smudge = np.zeros_like(r)
    for _ in range(6):  # a few soft lens smudges, a couple of percent each
        cx, cy = rng.uniform(0.25, 0.75, 2) * size
        rad = rng.uniform(0.08, 0.2) * size
        smudge += np.exp(-(((xs - cx) ** 2 + (ys - cy) ** 2) / (2 * rad**2))) * rng.uniform(-0.05, 0.04)
    v = (v + smudge) * (1.0 - smooth(0.96, 1.0, r))  # nothing at the very edge of the cone
    return np.clip(v, 0.0, 1.0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--size", type=int, default=256, help="square size in pixels")
    parser.add_argument("--seed", type=int, default=7, help="smudge pattern seed")
    parser.add_argument("--out", type=Path, default=OUT, help="output PNG")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    img = (beam(args.size, args.seed) * 255.0 + 0.5).astype(np.uint8)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img).save(args.out)
    LOG.info("wrote %s", args.out)


if __name__ == "__main__":
    main()
