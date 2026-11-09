"""Stable map IDs and the data the campaign, automap and save file share."""
from dataclasses import dataclass
import math
from typing import Callable

from level_hickston import Hickston, SPAWN, TileMap
from level_expansion import BlackwaterMill, CountyFair
from level_quarry import StillwaterCut


@dataclass(frozen=True)
class Station:
    id: str
    x: float
    y: float
    label: str
    message: str
    requires: tuple[str, ...] = ()
    opens: tuple[tuple[int, int], ...] = ()
    sectors: tuple[int, ...] = ()
    cue: str = "menu_accept"
    reveals_secret: bool = False
    hidden: bool = False
    action: str = "use"
    held: str = ""


@dataclass(frozen=True)
class Extraction:
    x: float
    y: float
    label: str
    shutdown: str


@dataclass(frozen=True)
class Billboard:
    x: float
    y: float
    image: str
    height: float
    z: float = 0.
    signal: str = ""
    glow: bool = False
    plane: float | None = None
    back: str = ""


def return_marker(gate):
    return Billboard(gate.x+gate.width*.34,gate.y+.79,"hub_road_stake",.97,
                     plane=math.pi,back="hub_road_stake_back")


@dataclass(frozen=True)
class Level:
    id: str
    title: str
    heading: tuple[str, str]
    build: Callable[[], TileMap]
    spawn: tuple[float, float, float]
    districts: tuple[str, ...]
    map_labels: tuple[tuple[str, int, int], ...]
    hidden_rooms: tuple[tuple[tuple[int, int], tuple[int, int, int, int]], ...]
    introduction: str
    ending: str
    score: str = "music"
    ambience: str = ""
    rescue: bool = False


HICKSTON = Level(
    "hickston", "THE HICKSTON INCIDENT", ("BESSIE'S", "COMIN' HOME"), Hickston, SPAWN,
    ("COUNTY ROAD", "STANKY'S BAR & GRILL", "RESTROOM", "SUPPLY ROOM", "FEED BARN",
     "HOG PEN", "PACKING SHED", "DISPATCH OFFICE", "TRAILER LOT", "DRY CREEK", "NORTH PASTURE",
     "COUNTY CROSSROADS","COUNTY SERVICE ROAD","LIVESTOCK LOTS","STOCK REGISTRY"),
    (("STANKY'S", 4, 18), ("BARN", 25, 19), ("TRAILERS", 37, 20),
     ("HOG PEN", 26, 3), ("CREEK", 36, 7), ("ORCHARD", 4, 3),
     ("GARAGE",54,17),("LOTS",69,26),("REGISTRY",70,9)),
    (((15, 17), (16, 16, 17, 18)), ((11, 7), (7, 6, 10, 8)), ((32, 14), (31, 12, 33, 13))),
    "BRASS KEY: STANKY'S BACK OFFICE", '"NEXT TIME, TAKE THE TRACTOR."', rescue=True,
)

FAIR = Level(
    "fair", "POSSUM COUNTY FAIR", ("LAST CALL", "ON THE MIDWAY"), CountyFair,
    (21.5,37.1,-1.571),
    ("TICKET SHACK","THE MIDWAY","CONCESSION ALLEY","GAME COURT","PRIZE PAVILION","SERVICE EXIT",
     "FREIGHT AND RAFFLE LOT","BACKSTAGE SIDESHOWS","PA BOOTH"),
    (("GATE",18,35),("MIDWAY",18,27),("FOOD",5,27),("GAMES",33,25),
     ("PRIZES",17,11),("EXIT",32,8),("FREIGHT",43,29),("SIDESHOW",53,23),("PA",56,8)),
    (((4,23),(2,22,3,25)), ((28,15),(29,14,31,16)), ((39,15),(38,13,40,14))),
    "SET CONCESSION POWER AND PATCH THE BACKSTAGE PA.", '"NO REFUNDS AFTER THE ABDUCTION."',
    score="fair_score", ambience="fair",
)
SAWMILL = Level(
    "sawmill", "BLACKWATER TIMBER", ("BLACKWATER", "TIMBER"), BlackwaterMill,
    (21.45,35.35,-1.571),
    ("DELIVERY YARD","FLOODED LOG POND","WEST BANK","EAST BANK","THE CUTTING SHED","LOADING APRON",
     "GREEN CHAIN SORT","DRY KILNS","RAIN STORAGE"),
    (("YARD",18,33),("POND",18,23),("WEST",7,18),("EAST",34,19),
     ("PUMP",20,8),("APRON",10,2),("SORT",44,20),("KILN",60,29),("DRY STACKS",49,40)),
    (((7,16),(5,16,6,18)), ((38,25),(39,23,41,26)), ((18,9),(15,8,17,10))),
    "ISOLATE THE WEST FEED AND TRIP THE DRY-KILN BELT.", '"CLOCK OUT. LEAVE THE BOOTS OUTSIDE."',
    score="mill_score", ambience="mill",
)

QUARRY = Level(
    "quarry", "STILLWATER CUT", ("STILLWATER CUT","BOOTLEG WORKS"), StillwaterCut,
    (27.45,38.85,-1.571),
    ("COUNTY WEIGH STATION","LIMESTONE CUT YARD","CUTTING SHED","CONDENSER YARD",
     "BOTTLING WORKS","LOADING COURT","LOWER CUT","CHALK TERRACES","COPPER RECOVERY"),
    (("SCALES",21,38),("CUT YARD",25,29),("SHED",9,17),
     ("STILLS",42,19),("BOTTLING",25,13),("COURT",17,4),
     ("LOWER CUT",51,26),("WASH",70,37),("COPPER",67,12)),
    (((20,36),(18,35,19,38)),((7,15),(5,14,6,17)),((48,17),(49,16,51,19))),
    "STOP THE CUTTING FEED AND DIVERT THE COPPER CONDENSER.",'"WEIGHT INCLUDES CONTENTS AND DEBTS."',
    score="quarry_score",ambience="quarry",
)

LEVELS = (HICKSTON, FAIR, SAWMILL, QUARRY)
BY_ID = {level.id: level for level in LEVELS}
GATE_LABELS = {"hickston":"HICKSTON","fair":"FAIR","sawmill":"MILL","quarry":"QUARRY"}


def next_level(level_id):
    index = LEVELS.index(BY_ID[level_id]) + 1
    return LEVELS[index] if index < len(LEVELS) else None
