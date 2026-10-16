"""Prepare the first-person arms' textures from Davlet's Modular FPS Arms Pack 06 (paid, royalty-free).

The pack ships 4K PNGs (local-only, under C:/projects/assets-src/fps-arms/extracted, never in git). This turns the
ones fp_arm_fps06.py uses into game-sized JPEGs in the pack's "prepared" folder: base colours with the pack's
baked ambient occlusion multiplied in (glTF has no slot Godot reads for a separate AO map here), normal maps
(OpenGL, which is glTF's convention), and roughness packed into the green channel of a glTF
metallic-roughness map (blue, metallic, is 0).

Run with Python 3.12 and Pillow, before the Blender script:
    python tools/art/fp_arm_fps06_textures.py
"""

import argparse
import logging
from pathlib import Path

from PIL import Image, ImageChops

Image.MAX_IMAGE_PIXELS = None
PACK = Path("C:/projects/assets-src/fps-arms")
SLEEVE_COLOUR = "c3"  # olive canvas; the others are camo prints, c4 is khaki
GLOVE_COLOUR = "02"  # tan leather; 01 olive, 03 black
BASE_SIZE = 2048
DETAIL_SIZE = 1024
## The glove's grey, glossy brand tag (UV box as fractions of the texture): in game it flashed like a chip of
## metal at the wrist, so its grey is tinted to the leather and made matte.
TAG_BOX = (0.665, 0.585, 0.82, 0.745)
TAG_TINT = (78, 56, 40)
TAG_ROUGHNESS = 215


def textures_dir(pack: Path) -> Path:
    """Where the pack's UE5 texture folders were unpacked."""
    return pack / "extracted" / "textures" / "FPS06_Textures" / "FPS06_Textures_UE5"


def base_with_ao(colour: Path, ao: Path, out: Path, size: int) -> None:
    """Base colour times its baked AO (softened, so creases darken without going black), as an sRGB JPEG."""
    base = Image.open(colour).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    shade = Image.open(ao).convert("L").resize((size, size), Image.Resampling.LANCZOS)
    shade = shade.point(lambda v: int(90 + v * (255 - 90) / 255))
    Image.merge("RGB", [ImageChops.multiply(channel, shade) for channel in base.split()]).save(
        out, quality=90, optimize=True)


def normal_map(source: Path, out: Path, size: int) -> None:
    """An OpenGL (Y up) normal map, resized, as a high-quality JPEG."""
    Image.open(source).convert("RGB").resize((size, size), Image.Resampling.LANCZOS).save(out, quality=95, optimize=True)


def roughness_map(source: Path, out: Path, size: int) -> None:
    """glTF metallic-roughness: red unused (white), green roughness, blue metallic (0)."""
    rough = Image.open(source).convert("L").resize((size, size), Image.Resampling.LANCZOS)
    Image.merge("RGB", [Image.new("L", rough.size, 255), rough, Image.new("L", rough.size, 0)]).save(
        out, quality=92, optimize=True)


def tag_mask(image: Image.Image) -> tuple[tuple[int, int, int, int], Image.Image]:
    """The tag's pixel box in `image` and a mask of its grey (unsaturated) pixels, leaving the leather round it."""
    w, h = image.size
    box = (int(TAG_BOX[0] * w), int(TAG_BOX[1] * h), int(TAG_BOX[2] * w), int(TAG_BOX[3] * h))
    saturation = image.crop(box).convert("HSV").split()[1]
    return box, saturation.point(lambda v: 255 if v < 56 else 0)


def matte_tag(base_path: Path, rm_path: Path) -> None:
    """Tints the glove's tag to dark leather (keeping its shading) and makes it as rough as the leather."""
    base = Image.open(base_path).convert("RGB")
    box, mask = tag_mask(base)
    shade = base.crop(box).convert("L").point(lambda v: int(140 + v * 115 / 255))
    tinted = Image.merge("RGB", [ImageChops.multiply(Image.new("L", shade.size, c), shade) for c in TAG_TINT])
    base.paste(tinted, box, mask)
    base.save(base_path, quality=90, optimize=True)
    rm = Image.open(rm_path).convert("RGB")
    scale = rm.size[0] / base.size[0]
    rm_box = tuple(int(v * scale) for v in box)
    red, rough, metal = rm.split()
    rough.paste(TAG_ROUGHNESS, rm_box, mask.resize((rm_box[2] - rm_box[0], rm_box[3] - rm_box[1])))
    Image.merge("RGB", [red, rough, metal]).save(rm_path, quality=92, optimize=True)


def main() -> None:
    """Writes the prepared textures; the Blender script reads them by these names."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--pack", type=Path, default=PACK, help="the folder holding extracted/ (default %(default)s)")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    src = textures_dir(args.pack)
    out = args.pack / "prepared"
    out.mkdir(parents=True, exist_ok=True)
    clothes = src / "FPS06_Clothes"
    gloves = src / "FPS06_GL06_Textures" / "Textures"
    jobs = [
        (base_with_ao, clothes / f"T_Clothes_FPS06_{SLEEVE_COLOUR}_Base_color.png", clothes / "T_Clothes_FPS06_Mixed_AO.png",
         out / "sleeve_base.jpg", BASE_SIZE),
        (normal_map, clothes / "T_Clothes_FPS06_Normal_OpenGL.png", None, out / "sleeve_normal.jpg", DETAIL_SIZE),
        (roughness_map, clothes / "T_Clothes_FPS06_Roughness.png", None, out / "sleeve_rm.jpg", DETAIL_SIZE),
        (base_with_ao, gloves / f"M_Gloves06_{GLOVE_COLOUR}_Base_color.png", gloves / "M_Gloves06_01_Mixed_AO.png",
         out / "glove_base.jpg", BASE_SIZE),
        (normal_map, gloves / "M_Gloves06_01_Normal_OpenGL.png", None, out / "glove_normal_left.jpg", DETAIL_SIZE),
        (normal_map, gloves / "M_Gloves06_01_Right_Fix_Normal_OpenGL.png", None, out / "glove_normal_right.jpg", DETAIL_SIZE),
        (roughness_map, gloves / "M_Gloves06_01_Roughness.png", None, out / "glove_rm.jpg", DETAIL_SIZE),
    ]
    for job, source, extra, target, size in jobs:
        if extra is None:
            job(source, target, size)
        else:
            job(source, extra, target, size)
        logging.info("%s  %d KB", target, target.stat().st_size // 1024)
    matte_tag(out / "glove_base.jpg", out / "glove_rm.jpg")
    logging.info("glove tag tinted to leather and made matte")


if __name__ == "__main__":
    main()
