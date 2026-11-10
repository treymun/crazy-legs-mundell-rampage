"""Dump the Python game's level data to JSON for the Godot port.

Run with the reference project's venv:
  <reference>\\.venv\\Scripts\\python.exe tools/export_levels.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

def _find_ref() -> Path:
    """Reference project: env override, then the repository this folder sits in."""
    import os
    env = os.environ.get("CRAZY_LEGS_REF")
    if env:
        return Path(env)
    here = Path(__file__).resolve().parent
    # godot/tools/ lives inside the Python project it is ported from; the
    # reference/ candidates cover a standalone copy of the godot folder.
    for candidate in (here.parent.parent, here.parent / "reference",
                      here.parent.parent / "reference"):
        if (candidate / "main.py").is_file():
            return candidate
    raise SystemExit("Python reference project not found: set CRAZY_LEGS_REF to its folder.")


REF = _find_ref()
OUT = Path(__file__).resolve().parent.parent / "data"
sys.path.insert(0, str(REF))

import numpy as np  # noqa: E402

import campaign  # noqa: E402
import county_events  # noqa: E402
import level_hickston  # noqa: E402
import populate2  # noqa: E402


def r(value, places=4):
    return round(float(value), places)


def grid(arr, places=None):
    flat = arr.reshape(-1)
    if places is None:
        return [int(v) for v in flat]
    return [r(v, places) for v in flat]


class Stub:
    """Just enough of Game for populate2.populate()."""

    def __init__(self, world, level):
        self.world = world
        self.level = level
        self.enemies = [type("E", (), {"x": x, "y": y}) for _, x, y in world.enemies]
        self.pickups = list(world.pickups)
        self.props = [type("P", (), {"x": x, "y": y}) for _, x, y in world.props]


def dump_level(level):
    world = level.build()
    stub = Stub(world, level)
    populate2.populate(stub)
    # populate2 mutates game.pickups; push the result back so the dump carries it.
    world.pickups = list(stub.pickups)

    h, w = world.solid.shape
    data = {
        "id": level.id,
        "title": level.title,
        "heading": list(level.heading),
        "intro": level.introduction,
        "ending": level.ending,
        "score": level.score,
        "ambience": level.ambience,
        "rescue": bool(level.rescue),
        "spawn": [r(level.spawn[0]), r(level.spawn[1]), r(level.spawn[2])],
        "districts": list(level.districts),
        "map_labels": [list(x) for x in level.map_labels],
        "hidden_rooms": [[list(a), list(b)] for a, b in level.hidden_rooms],
        "width": w,
        "height": h,
        "sky": world.sky,
        "control_name": getattr(world, "control_name", ""),
        "mirror": [r(v) for v in world.mirror] if world.mirror else None,
        "solid": grid(world.solid),
        "floor": grid(world.floor),
        "ceiling": grid(world.ceiling),
        "ground": grid(world.ground, 4),
        "roof": grid(world.roof, 4),
        "wall_height": grid(world.wall_height, 4),
        "light": grid(world.light, 4),
        "area": grid(world.area),
        "tints": [[r(v) for v in row] for row in np.asarray(world.tints)],
        "ground_heights": [r(v) for v in world.ground_heights],
        "roof_heights": [r(v) for v in world.roof_heights],
        "walls": [[r(v) if i != 4 else int(v) for i, v in enumerate(row)]
                  for row in np.asarray(world.walls)],
        "doors": [{
            "x": d.x, "y": d.y, "style": d.style, "vertical": bool(d.vertical),
            "key": d.key, "secret": bool(d.secret), "blast_only": bool(d.blast_only),
            "progress": r(d.progress), "opened": bool(d.opened),
            "discovered": bool(d.discovered), "texture": d.texture,
            "material": int(d.material),
            "id": world.door_ids.get((d.x, d.y), ""),
        } for d in world.doors],
        "fixtures": [[r(f.x0), r(f.y0), r(f.x1), r(f.y1), r(f.top), f.side,
                      f.cap, r(f.base)] for f in world.fixtures],
        "collision_volumes": [[r(f.x0), r(f.y0), r(f.x1), r(f.y1), r(f.top), f.side,
                               f.cap, r(f.base)] for f in world.collision_volumes],
        "caps": {str(r(height)): [[r(f.x0), r(f.y0), r(f.x1), r(f.y1), f.cap]
                                  for f in caps]
                 for height, caps in world.caps.items()},
        "pane_tiles": [list(p) for p in world.pane_tiles],
        "enemies": [{"kind": k, "x": r(x), "y": r(y),
                     "id": world.enemy_ids[i] if i < len(world.enemy_ids) else ""}
                    for i, (k, x, y) in enumerate(world.enemies)],
        "patrols": {str(k): [[r(px), r(py)] for px, py in route]
                    for k, route in world.patrols.items()},
        "pickups": [[n, r(x), r(y)] for n, x, y in world.pickups],
        "props": [[n, r(x), r(y)] for n, x, y in world.props],
        "fuel_drums": [[r(x), r(y)] for x, y in world.fuel_drums],
        "billboards": [{
            "x": r(b.x), "y": r(b.y), "image": b.image, "height": r(b.height),
            "z": r(b.z), "signal": b.signal, "glow": bool(b.glow),
            "plane": None if b.plane is None else r(b.plane), "back": b.back,
        } for b in world.billboards],
        "scenery": [{
            "id": s.id, "kind": s.kind, "x": r(s.x), "y": r(s.y),
            "height": r(s.height), "z": r(s.z), "radius": r(s.radius),
            "opens": [list(p) for p in s.opens], "station": s.station,
        } for s in world.scenery],
        "stations": [{
            "id": s.id, "x": r(s.x), "y": r(s.y), "label": s.label,
            "message": s.message, "requires": list(s.requires),
            "opens": [list(p) for p in s.opens], "sectors": list(s.sectors),
            "cue": s.cue, "reveals_secret": bool(s.reveals_secret),
            "hidden": bool(s.hidden), "action": s.action, "held": s.held,
        } for s in world.stations],
        "extraction": None if not world.extraction else {
            "x": r(world.extraction.x), "y": r(world.extraction.y),
            "label": world.extraction.label, "shutdown": world.extraction.shutdown,
        },
        "reinforcements": list(world.reinforcements),
        "controlled_doors": [list(p) for p in world.controlled_doors],
        "access_doors": {f"{p[0]},{p[1]}": list(v) for p, v in world.access_doors.items()},
        "objective_side_tasks": list(world.objective_side_tasks),
        "v2_implied_tasks": {k: list(v) for k, v in world.v2_implied_tasks.items()},
        "crouch_doors": [list(p) for p in world.crouch_doors],
        "discovery_rooms": {f"{p[0]},{p[1]}": list(v) for p, v in world.discovery_rooms.items()},
        "dress_marks": [[r(m.x), r(m.y), r(m.z), r(m.angle), r(m.reach), r(m.width), m.image]
                        for m in world.dress_marks],
        "distant_cues": [[r(x), r(y), n] for x, y, n in world.distant_cues],
        "return_gate": None if not world.return_gate else {
            "destination": world.return_gate.destination,
            "x": r(world.return_gate.x), "y": r(world.return_gate.y),
            "width": r(world.return_gate.width), "side": world.return_gate.side,
        },
        "hub_gates": [{
            "destination": g.destination, "x": r(g.x), "y": r(g.y),
            "width": r(g.width), "side": g.side,
        } for g in world.hub_gates],
        "hub_clues": [[c[0], r(c[1]), r(c[2]), c[3], c[4]] for c in world.hub_clues],
        "pressure_ports": [[r(x), r(y)] for x, y in world.pressure_ports],
        "boss_decoys": [[r(x), r(y)] for x, y in world.boss_decoys],
        "extension_doors": [list(p) for p in world.extension_doors],
        "extension_enemies": list(world.extension_enemies),
        "extension_pickups": [[n, r(x), r(y)] for n, x, y in world.extension_pickups],
        "notes": [[r(n.x), r(n.y), n.label, n.text, r(n.plane)]
                  for n in county_events.NOTES.get(level.id, ())],
        "interiors": [[i.art, r(i.x), r(i.y), r(i.z), r(i.height), r(i.plane)]
                      for i in county_events.INTERIORS.get(level.id, ())],
        "partners": [[a, b, s] for a, b, s in county_events.PARTNERS.get(level.id, ())],
        "ruptures": {k: [r(v[0]), r(v[1]), v[2]]
                     for k, v in county_events.RUPTURES.items()},
        "recovery_room": (list(county_events.RECOVERY_ROOMS[level.id])
                          if level.id in county_events.RECOVERY_ROOMS else None),
        "exchanges": [{"id": e.id, "x": r(e.x), "y": r(e.y),
                       "stop_at": e.stop_at, "lines": list(e.lines)}
                      for e in _exchanges(level.id)],
    }
    return data


def _exchanges(level_id):
    import chatter
    return chatter.EXCHANGES.get(level_id, ())


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    index = {
        "tiles": list(level_hickston.TILES),
        "tile": level_hickston.TILE,
        "wall_height": level_hickston.WALL_HEIGHT,
        "secret_total_default": level_hickston.SECRET_TOTAL,
        "levels": [],
    }
    for level in campaign.LEVELS:
        data = dump_level(level)
        path = OUT / f"{level.id}.json"
        path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        index["levels"].append(level.id)
        print(f"{level.id}: {path.stat().st_size/1024:.0f} KB  walls={len(data['walls'])} "
              f"enemies={len(data['enemies'])} pickups={len(data['pickups'])} "
              f"scenery={len(data['scenery'])} props={len(data['props'])} "
              f"doors={len(data['doors'])} boards={len(data['billboards'])}")
    (OUT / "index.json").write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
    print("index tiles:", len(index["tiles"]))


if __name__ == "__main__":
    main()
