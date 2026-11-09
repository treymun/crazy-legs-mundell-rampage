"""Static balance and viewmodel registration check.
Run:  python weapon_check.py
"""
import json
from pathlib import Path

from PIL import Image

from enemies import KINDS
from weapons import (CAPACITY, DAMAGE, FIRE_TIME, GUN_H, MAX_RESERVE, MELEE,
                     NAMES, PICKUP_RESERVE, RELOAD_TIME, SHOTGUN, VIEW,
                     VIEW_SCALE, VIEW_SCALES, view_point)

ROOT = Path(__file__).resolve().parent
ART = ROOT / "assets" / "art"


def per_shot(i):
    if i in MELEE:
        return max(MELEE[i])
    if i == SHOTGUN:
        return DAMAGE[SHOTGUN][0] * DAMAGE[SHOTGUN][1]
    if i in DAMAGE:
        return DAMAGE[i]
    return 0


def sustained(i):
    damage = per_shot(i)
    if not damage:
        return 0.
    if CAPACITY[i]:
        cycle = CAPACITY[i] * FIRE_TIME[i] + RELOAD_TIME[i]
        return CAPACITY[i] * damage / cycle
    return damage / max(.01, FIRE_TIME[i])


def main():
    print("WEAPON            SHOT   SUSTAIN  MAG  RESERVE  PICKUP")
    rows = []
    for i, name in enumerate(NAMES):
        dps = sustained(i)
        if not dps:
            continue
        rows.append((dps, name))
        print(f"  {name:16s} {per_shot(i):5.0f}  {dps:7.1f}  {CAPACITY[i]:3d}  "
              f"{MAX_RESERVE[i]:7d}  {PICKUP_RESERVE[i]:6d}")
    print("\nTIME TO KILL (sustained fire, no misses)")
    for kind in ("boss", "jerry", "rudy", "foreman", "baron"):
        hp = KINDS[kind][0]
        print(f"  {kind:8s} hp {hp:4d}  " + "  ".join(
            f"{name} {hp / dps:5.1f}s" for dps, name in rows[:5]))
    print("\nBALANCE FLAGS")
    flags = 0
    for dps, name in rows:
        if name in ("crowbar", "slingblade", "pressure_gun", "riveter"):
            continue
        if dps > 185 or dps < 55:
            print(f"  OUTLIER {name}: {dps:.1f} dps")
            flags += 1
    for kind in ("boss", "jerry"):
        hp = KINDS[kind][0]
        ttk = hp / rows[0][0]
        if ttk < 3.5 or ttk > 10.:
            print(f"  OUTLIER {kind} TTK: {ttk:.1f}s at best dps")
            flags += 1

    anchors = json.loads((ART / "weapon_anchors.json").read_text(encoding="utf-8"))
    base_y = VIEW - GUN_H
    for i, name in enumerate(NAMES):
        s = VIEW_SCALES.get(i, VIEW_SCALE)
        poses = anchors.get(name, {})
        if name not in ("shotgun", "revolver", "crossbow", "rifle", "ripsaw",
                        "armgun", "bottle_launcher", "riveter", "pressure_gun"):
            continue
        if not poses:
            print(f"  MISSING anchors: {name}")
            flags += 1
        for pose, (mx, my) in poses.items():
            px, py = view_point(0, base_y, mx, my, s)
            if not (0 <= px <= 320 and 0 <= py <= VIEW):
                print(f"  OFF-SCREEN {name}.{pose}: {px:.0f},{py:.0f}")
                flags += 1

    for name in NAMES:
        path = ART / f"gun_{name}_idle.png"
        if not path.exists():
            print(f"  MISSING cel: {path.name}")
            flags += 1
            continue
        image = Image.open(path)
        box = image.getchannel("A").point(lambda a: 255 if a >= 112 else 0).getbbox()
        if not box or box[2] - box[0] < 18 or box[3] - box[1] < 18:
            print(f"  TINY cel: {name} bbox {box}")
            flags += 1
    print(f"\n{flags} flag(s)")
    print("WEAPON CHECK PASSED" if not flags else "WEAPON CHECK FAILED")
    return 0 if not flags else 1


if __name__ == "__main__":
    raise SystemExit(main())
