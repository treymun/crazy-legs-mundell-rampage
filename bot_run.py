"""Scripted bot: walks each level toward the nearest enemy, shoots, logs deaths/damage, saves a contact sheet.
Run: python bot_run.py"""
import math, os, sys
os.environ.setdefault("SDL_VIDEODRIVER", "dummy"); os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
import pygame as pg
from campaign import BY_ID
from game import Controls
from main import Desktop

d = Desktop(smoke=True)
out = os.path.join("bot_shots"); os.makedirs(out, exist_ok=True)
frames = []
for level in BY_ID:
    d.start(level)
    g = d.game
    g.cheats.god = False
    p = g.player
    for w in range(len(g.armory.owned)):
        g.armory.owned[w] = True
    g.armory.reserve = [99] * len(g.armory.reserve)
    g.armory.select(2, g)
    stuck = 0; last = (p.x, p.y); log = []
    for step in range(60 * 40):
        live = [e for e in g.enemies if e.alive and e.hostile and not e.dormant]
        t = min(live, key=lambda e: math.hypot(e.x - p.x, e.y - p.y)) if live else None
        c = Controls()
        if t:
            want = math.atan2(t.y - p.y, t.x - p.x)
            diff = (want - p.angle + math.pi) % math.tau - math.pi
            c.turn = max(-.05, min(.05, diff)); c.forward = 1. if math.hypot(t.x - p.x, t.y - p.y) > 2.2 else 0.
            c.fire = abs(diff) < .2
        else:
            c.forward = 1.; c.turn = .01
        g.tick(1 / 60, c)
        if g.player.health <= 0:
            log.append(f"died at step {step}"); break
        if step % 60 == 0:
            if math.hypot(p.x - last[0], p.y - last[1]) < .3: stuck += 1
            last = (p.x, p.y)
        if step in (120, 900, 2000):
            g.draw(d.canvas, grade=d.palette.grade)
            path = os.path.join(out, f"{level}_{step}.png")
            pg.image.save(d.canvas, path); frames.append(path)
    print(f"{level}: kills {g.kills}/{g.total_kills} health {g.player.health} stuck-seconds {stuck} {log}")
imgs = [pg.image.load(f) for f in frames]
cols = 3; w, h = imgs[0].get_size()
sheet = pg.Surface((w * cols, h * math.ceil(len(imgs) / cols)))
for i, im in enumerate(imgs): sheet.blit(im, ((i % cols) * w, (i // cols) * h))
pg.image.save(pg.transform.scale(sheet, (sheet.get_width() * 2, sheet.get_height() * 2)), os.path.join(out, "contact_sheet.png"))
print("BOT RUN DONE")
