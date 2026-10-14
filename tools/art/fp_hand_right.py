"""Right first-person forearm and work-gloved hand gripping a 34 mm handle."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from melee_common import build_fp_hand  # noqa: E402

build_fp_hand("fp_hand_right", side=1)
