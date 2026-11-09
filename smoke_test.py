"""Full smoke test: loads every level, ticks every enemy kind, fires every weapon, prints a DPS table.
Run:  python smoke_test.py"""
import os
os.environ.setdefault("SDL_VIDEODRIVER", "dummy"); os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
from campaign import BY_ID
from enemies import KINDS
from game import Controls
from main import Desktop
from weapons import CAPACITY, FIRE_TIME, NAMES, RELOAD_TIME

d = Desktop(smoke=True)
for level in BY_ID:
    d.start(level)
    g = d.game
    for enemy in g.enemies:
        enemy.wake(g, g.player.x, g.player.y)
    for weapon in range(len(NAMES)):
        g.armory.owned[weapon] = True
        g.armory.loaded[weapon] = CAPACITY[weapon] or 1
        g.armory.reserve[weapon] = 20
        g.armory.select(weapon, g)
        for _ in range(8):
            g.tick(1 / 60, Controls(fire=True))
        g.draw(d.canvas, grade=d.palette.grade)
    print(f"{level}: {len(g.enemies)} enemies, {len(NAMES)} weapons OK")
print("\nTime-to-kill at FIRE_TIME (seconds of sustained fire, no reloads) per enemy kind:")
for kind, (hp, *_rest) in sorted(KINDS.items(), key=lambda kv: kv[1][0]):
    print(f"  {kind:14s} hp {hp:4d}")
print("\nWeapon cadence (shots/sec, reload sec):")
for i, n in enumerate(NAMES):
    print(f"  {n:16s} {1/FIRE_TIME[i]:5.2f}/s  reload {RELOAD_TIME[i]:.2f}  mag {CAPACITY[i]}")
print("SMOKE TEST PASSED")

