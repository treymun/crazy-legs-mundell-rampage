"""One-shot, persistent scenery reactions and optional route triggers."""
from dataclasses import dataclass


@dataclass(frozen=True)
class Reactive:
    id: str
    kind: str
    x: float
    y: float
    height: float
    z: float = 0.
    radius: float = .25
    opens: tuple = ()
    station: str = ""


REACTIONS = {
    "bottles": ("glass_break","glass",8),
    "cans": ("scenery_cans","spark",5),
    "prize": ("scenery_prize","dust",7),
    "scrap": ("scenery_scrap","dust",9),
    "pipe": ("scenery_pipe","splash",8),
    "belt": ("scenery_belt","spark",6),
    "tv": ("tv_pop","spark",9),
    "toilet": ("toilet_burst","splash",14),
    "vending": ("vending_clunk","dust",8),
    "window": ("window_smash","glass",14),
    "cancan": ("can_kick","spark",5),
    "jukebox": ("jukebox_hit","spark",7),
}
