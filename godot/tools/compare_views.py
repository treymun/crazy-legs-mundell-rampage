"""Compare the shader's view with the software view, frame by frame.

    python godot/tools/compare_views.py <dir> [--strong-max 1.5] [--mean-max 0.1]

<dir> holds <tag>_gpu.png and <tag>_cpu.png pairs, as main.gd's
--view-tour=<views.json> --view-out=<dir> writes them (a real window: the
shader only runs with a graphics card, or Mesa's software one under xvfb).
A pixel "strongly" differs when a channel is more than 40 apart. Fails when
one pair strongly differs in more than --strong-max percent of its pixels, or
the pairs on average in more than --mean-max percent. Writes <tag>_diff.png
for every pair that fails.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--strong-max", type=float, default=1.5)
    parser.add_argument("--mean-max", type=float, default=0.1)
    args = parser.parse_args()
    pairs = sorted(args.folder.glob("*_gpu.png"))
    if not pairs:
        print(f"no *_gpu.png frames in {args.folder}")
        return 1
    strong_all = []
    failed = []
    for gpu in pairs:
        tag = gpu.name[: -len("_gpu.png")]
        cpu = gpu.with_name(f"{tag}_cpu.png")
        if not cpu.exists():
            print(f"{tag:34s} no software frame")
            failed.append(tag)
            continue
        a = np.asarray(Image.open(gpu).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(cpu).convert("RGB"), dtype=np.int16)
        apart = np.abs(a - b).max(axis=2)
        strong = float((apart > 40).mean() * 100)
        any_diff = float((apart > 0).mean() * 100)
        strong_all.append(strong)
        verdict = ""
        if strong > args.strong_max:
            verdict = "  FAIL"
            failed.append(tag)
            mask = np.zeros(apart.shape + (3,), dtype=np.uint8)
            mask[apart > 40] = (255, 60, 60)
            Image.fromarray(mask).save(gpu.with_name(f"{tag}_diff.png"))
        print(f"{tag:34s} {any_diff:6.2f}% differ {strong:6.2f}% strongly{verdict}")
    mean = float(np.mean(strong_all)) if strong_all else 100.0
    print(f"mean strongly differing {mean:.3f}% over {len(strong_all)} pairs")
    if mean > args.mean_max:
        print(f"FAIL: mean above {args.mean_max}%")
        return 1
    if failed:
        print("FAIL: " + ", ".join(failed))
        return 1
    print("VIEWS MATCH")
    return 0


if __name__ == "__main__":
    sys.exit(main())
