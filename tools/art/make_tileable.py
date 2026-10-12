"""Turn a generated texture into a seamless tile plus a matching normal map.

Image generators don't make textures that repeat cleanly, so this blends the image with a
half-offset copy of itself (the copy's edges already wrap, and its own seam sits under the
untouched centre of the original). The blend keeps the grain's contrast so the join doesn't
go soft. The normal map comes from the tile's brightness (dark = low), computed with
wrap-around so it tiles too. Godot uses the OpenGL convention (green = up).

Usage:
    python tools/art/make_tileable.py assets/textures/concrete_floor_raw.png assets/textures/concrete_floor
    -> concrete_floor_albedo.png, concrete_floor_normal.png, and a 2x2 preview in .shots/
"""

import argparse
import logging
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

log = logging.getLogger("make_tileable")


def _edge_mask(size: int, blend: float) -> np.ndarray:
    """1.0 in the middle, easing to 0.0 at both edges over `blend` of the width."""
    t = np.minimum(np.arange(size) + 0.5, size - np.arange(size) - 0.5) / (size * blend)
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def make_seamless(img: np.ndarray, blend: float) -> np.ndarray:
    """Blend `img` (H x W x C floats, 0-1) with its half-offset copy so its edges wrap cleanly."""
    h, w = img.shape[:2]
    shifted = np.roll(img, (h // 2, w // 2), axis=(0, 1))
    m = np.outer(_edge_mask(h, blend), _edge_mask(w, blend))[..., None]
    mean = img.reshape(-1, img.shape[2]).mean(axis=0)
    # Variance-preserving blend: a plain average of two textures loses contrast in the join.
    mixed = (img - mean) * m + (shifted - mean) * (1.0 - m)
    mixed = mixed / np.sqrt(m * m + (1.0 - m) ** 2) + mean
    return np.clip(mixed, 0.0, 1.0)


def normal_from_albedo(img: np.ndarray, strength: float) -> np.ndarray:
    """Tileable OpenGL-style normal map from brightness (H x W x 3 floats, 0-1)."""
    lum = img[..., :3] @ np.array([0.299, 0.587, 0.114])
    # Remove broad stains so only small-scale relief (pits, cracks, trowel marks) becomes bumps.
    pil = Image.fromarray((lum * 255).astype(np.uint8))
    broad = np.asarray(pil.filter(ImageFilter.GaussianBlur(12)), dtype=np.float64) / 255.0
    height = np.asarray(pil.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float64) / 255.0 - broad
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.stack([-dx * strength, dy * strength, np.ones_like(height)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(arr: np.ndarray, path: Path) -> None:
    """Write a 0-1 float array as an 8-bit PNG."""
    Image.fromarray((arr * 255.0 + 0.5).astype(np.uint8)).save(path)
    log.info("wrote %s", path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("src", type=Path, help="generated image")
    parser.add_argument("out_stem", type=Path, help="output path without suffix, e.g. assets/textures/concrete_floor")
    parser.add_argument("--size", type=int, default=1024, help="output edge length in pixels")
    parser.add_argument("--blend", type=float, default=0.3, help="fraction of the edge used for the blend")
    parser.add_argument("--strength", type=float, default=6.0, help="normal map bump strength")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    src = Image.open(args.src).convert("RGB")
    side = min(src.size)  # centre-crop to square, then resize
    left, top = (src.width - side) // 2, (src.height - side) // 2
    src = src.crop((left, top, left + side, top + side)).resize((args.size, args.size), Image.LANCZOS)
    img = np.asarray(src, dtype=np.float64) / 255.0

    albedo = make_seamless(img, args.blend)
    args.out_stem.parent.mkdir(parents=True, exist_ok=True)
    save(albedo, args.out_stem.with_name(args.out_stem.name + "_albedo.png"))
    save(normal_from_albedo(albedo, args.strength), args.out_stem.with_name(args.out_stem.name + "_normal.png"))

    preview = Path(".shots") / f"{args.out_stem.name}_tile2x2.png"
    preview.parent.mkdir(exist_ok=True)
    save(np.tile(albedo, (2, 2, 1)), preview)


if __name__ == "__main__":
    main()
