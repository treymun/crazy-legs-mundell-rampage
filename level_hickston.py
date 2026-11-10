"""Hickston's county road, rest stop, barn and alien cattle yard."""
from dataclasses import dataclass
import math

import numpy as np

from crossroads import TOWER_X, TOWER_Y, service_road, tank_faces
from county_detail import DETAIL_TILES
from level_buildings import BUILDING_TILES

TILES = ("wood", "barn", "tin", "brick", "plaster", "tile", "mirror", "floor_tile", "concrete",
         "dirt", "tracks", "grass", "asphalt", "road", "door", "gate", "liquor", "eat",
         "restroom", "barnsign", "warning", "wanted", "crack", "ship", "ceiling",
         "joists", "tavern", "shelves", "fascia", "window", "cinder",
         "porch", "counter", "counter_top", "crate_side", "steel_mesh",
         "shoulder", "gravel", "stockyard", "trailer", "trailer_window", "service",
         "dispatch", "feed", "orchard", "bleachers", "creek", "office_wall",
         "glazing", "powder_panel", "stanky_marquee", "feed_marquee", "cable", "oil_asphalt","hedgerow",
         "fair_booth", "fair_iron", "fair_gravel", "fair_gate", "fair_prize",
         "mill_tin", "mill_water", "mill_log", "mill_oil", "mill_pump", "mill_grit",
         "route_hickston", "route_fair", "route_sawmill", "route_quarry", "route_hub", "route_closed",
         "quarry_face", "quarry_dust", "quarry_iron", "quarry_copper", "quarry_shed",
         "feed_wash", "fair_marquee", "route_threshold", "hub_patch", "hub_service_wall",
         "hub_runoff", "hub_screen", "hub_tank_shell") + DETAIL_TILES + BUILDING_TILES
TILE = {name: i for i, name in enumerate(TILES)}
WALL_HEIGHT = 1.85
INDEX_RADIUS = .65
SPAWN = (10.45, 29.25, -1.54)
SECRET_TOTAL = 3
SECTOR_TINT = np.array([
    (.87, .94, 1.06), (1.05, .97, .83), (.92, 1.03, 1.03),
    (1.04, .95, .79), (1.03, .93, .82), (.88, .94, 1.04), (.83, .98, .91),
    (1.09, 1.00, .86), (1.05, .98, .88), (.88, 1.02, .96), (.91, .97, 1.04),
], dtype=np.float32)
EDGES = ((0, -1, 0, 0, 1, 0), (1, 0, 1, 0, 1, 1),
         (0, 1, 1, 1, 0, 1), (-1, 0, 0, 1, 0, 0))


@dataclass
class Door:
    x: int
    y: int
    style: str = "slide"
    vertical: bool = False
    key: str = ""
    secret: bool = False
    blast_only: bool = False
    progress: float = 0.0
    opened: bool = False
    discovered: bool = False
    texture: str = ""

    @property
    def center(self):
        return self.x + .5, self.y + .5

    def segment(self):
        if self.progress >= .995:
            return None
        x, y = self.x, self.y
        if self.style == "hinge":
            turn = self.progress * math.pi / 2
            if self.vertical:
                return x + .5, y, x + .5 + math.sin(turn), y + math.cos(turn)
            return x, y + .5, x + math.cos(turn), y + .5 + math.sin(turn)
        if self.vertical:
            return x + .5, y + self.progress, x + .5, y + 1
        return x + self.progress, y + .5, x + 1, y + .5

    def blocks(self,x,y,radius):
        if abs(x-self.x-.5)>1.3 or abs(y-self.y-.5)>1.3:
            return False
        seg=self.segment()
        if seg is None:
            return False
        ax,ay,bx,by=seg
        ex,ey=bx-ax,by-ay
        t=max(0,min(1,((x-ax)*ex+(y-ay)*ey)/(ex*ex+ey*ey)))
        return (x-ax-ex*t)**2+(y-ay-ey*t)**2 < (radius+.055)**2

    @property
    def material(self):
        if self.texture:
            return TILE[self.texture]
        if self.secret:
            return TILE["powder_panel" if self.blast_only else "crack"]
        return TILE["gate" if self.key or self.style == "slide" else "door"]


@dataclass(frozen=True)
class Fixture:
    x0: float
    y0: float
    x1: float
    y1: float
    top: float
    side: str
    cap: str = "counter_top"
    base: float = 0.


@dataclass(frozen=True)
class Portal:
    destination: str
    x: float
    y: float
    width: float = 3.8
    side: int = 1

    def approach(self, x, y, angle, reach):
        """Select a single lane from its approach, including just past an open threshold."""
        d = (y - self.y) * self.side
        facing = math.sin(angle)*self.side
        return (-1.55 < d < reach and abs(x-self.x) < self.width*.5
                and (facing > .34 if d < -.30 else facing < -.43))

    def frame(self, area, timber="barn"):
        left,right = self.x-self.width*.5,self.x+self.width*.5
        # Both edges are ordered in the direction seen from the approach.
        a,b = (right,left) if self.side == 1 else (left,right)
        return [
            (a,self.y,b,self.y,TILE["route_"+self.destination],1.29,1.83,2.34,area),
            (a,self.y,b,self.y,TILE[timber],1.08,2.34,2.53,area),
            (b,self.y-.035*self.side,a,self.y-.035*self.side,TILE[timber],.86,1.83,2.34,area),
        ]

    def posts(self, timber="barn"):
        return tuple(Fixture(x-.17,self.y-.17,x+.17,self.y+.17,2.37,timber)
                     for x in (self.x-self.width*.5-.17,self.x+self.width*.5+.17))

    def barrier(self):
        return (self.x+self.width*.5,self.y,self.x-self.width*.5,self.y,
                TILE["route_closed"],1.08,0.,1.34,11)

    def paint_threshold(self,floor):
        x0 = math.ceil(self.x-self.width*.5)
        x1 = math.floor(self.x+self.width*.5)
        floor[int(self.y),x0:x1] = TILE["route_threshold"]


class TileMap:
    def __init__(self, w, h):
        self.solid = np.full((h, w), TILE["wood"], dtype=np.int16)
        self.floor = np.full((h, w), TILE["dirt"], dtype=np.int16)
        self.ground = np.zeros((h, w), dtype=np.float32)
        self.roof = np.zeros((h, w), dtype=np.float32)
        self.ceiling = np.full((h, w), TILE["ceiling"], dtype=np.int16)
        self.wall_height = np.full((h, w), WALL_HEIGHT, dtype=np.float32)
        self.light = np.full((h, w), .97, dtype=np.float32)
        self.area = np.zeros((h, w), dtype=np.int8)
        self.doors = []
        self.near_doors = {}
        self.near_fixtures = {}
        self.pane_tiles = ()
        self.broken_panes = set()
        self.mirror = None
        self.fixtures = ()
        self.collision_volumes = ()
        self.tints = SECTOR_TINT
        self.sky = "sky"
        self.props = []
        self.pickups = []
        self.enemies = []
        self.enemy_ids = ()
        self.v2_new_enemies = frozenset()
        self.door_ids = {}
        self.patrols = {}
        self.fuel_drums = ()
        self.stations = ()
        self.reinforcements = ()
        self.extraction = None
        self.controlled_doors = frozenset()
        self.access_doors = {}
        self.objective_side_tasks = ()
        self.v2_implied_tasks = {}
        self.crouch_doors = frozenset()
        self.discovery_rooms = {}
        self.billboards = ()
        self.dress_marks = ()
        self.distant_cues = ()
        self.return_gate = None
        self.hub_gates = ()
        self.locked_gates = ()
        self.hub_clues = ()
        self.pressure_ports = ()
        self.boss_decoys = ()
        self.extension_doors = ()
        self.extension_enemies = ()
        self.extension_pickups = ()
        self.scenery = ()

    def room(self, x0, y0, x1, y1, floor, area, roof=0., light=.82, ceiling="ceiling"):
        ys, xs = slice(y0, y1 + 1), slice(x0, x1 + 1)
        self.solid[ys, xs] = -1
        self.floor[ys, xs] = TILE[floor]
        self.roof[ys, xs] = roof
        self.ceiling[ys, xs] = TILE[ceiling]
        self.light[ys, xs] = light
        self.area[ys, xs] = area

    def wall(self, x0, y0, x1, y1, texture, height=WALL_HEIGHT):
        ys, xs = slice(y0, y1 + 1), slice(x0, x1 + 1)
        self.solid[ys, xs] = TILE[texture]
        self.wall_height[ys, xs] = height

    def door(self, x, y, area=None, **options):
        self.solid[y, x] = -1
        self.floor[y, x] = TILE["concrete"]
        self.roof[y, x] = WALL_HEIGHT
        self.light[y, x] = .69
        if area is not None:
            self.area[y, x] = area
        door=Door(x,y,**options)
        self.doors.append(door)
        for yy in range(y-1,y+2):
            for xx in range(x-1,x+2):
                self.near_doors.setdefault((xx,yy),[]).append(door)

    def light_pool(self, x, y, strength, radius, area):
        yy, xx = np.indices(self.solid.shape)
        distance = (xx + .5 - x)**2 + (yy + .5 - y)**2
        self.light += (self.area == area) * strength * np.exp(-distance / radius**2)


    def wall_segments(self, hickston_facades=False):
        h, w = self.solid.shape
        # Wall sides plus the vertical risers between different ceiling heights.
        walls = []
        for y, x in zip(*np.where(self.solid >= 0)):
            for ox, oy, ax, ay, bx, by in EDGES:
                nx, ny = x + ox, y + oy
                if 0 <= nx < w and 0 <= ny < h and self.solid[ny, nx] < 0:
                    edge = (x + ax, y + ay, x + bx, y + by)
                    top = max(self.wall_height[y, x], self.roof[ny, nx])
                    material = self.solid[y, x]
                    light = self.light[ny, nx] * (1 if ox == 0 else .83)
                    area = self.area[ny, nx]
                    base = self.ground[ny, nx]
                    if hickston_facades and area == 0 and y == 20 and top > 2.05:
                        walls.append((*edge, material, light, base, 2.14, area))
                        walls.append((*edge, TILE["fascia"], light, 2.14, top, area))
                    else:
                        walls.append((*edge, material, light, base, top, area))
        for y, x in zip(*np.where(self.roof > 0)):
            for ox, oy, ax, ay, bx, by in EDGES:
                nx, ny = x + ox, y + oy
                if not (0 <= nx < w and 0 <= ny < h) or self.solid[ny, nx] >= 0 or self.roof[y, x] <= self.roof[ny, nx]:
                    continue
                bottom = self.roof[ny, nx]
                top = self.roof[y, x]
                if bottom == 0:
                    bottom, top = top, top + (.48 if hickston_facades and y == 20 and x == 23 else .35)
                area = self.area[ny, nx]
                walls.append((x + ax, y + ay, x + bx, y + by, TILE["fascia"],
                              self.light[ny, nx], bottom, top, area))
        for y, x in zip(*np.where(self.solid < 0)):
            for ox, oy, ax, ay, bx, by in EDGES:
                nx, ny = x + ox, y + oy
                if 0 <= nx < w and 0 <= ny < h and self.solid[ny, nx] < 0 and self.ground[ny, nx] < self.ground[y, x]:
                    riser = "shoulder" if self.ground[ny, nx] < 0 and self.floor[y, x] != TILE["porch"] else "porch"
                    walls.append((x + ax, y + ay, x + bx, y + by, TILE[riser],
                                  self.light[y, x], self.ground[ny, nx], self.ground[y, x],
                                  self.area[y, x]))
        for fixture in self.fixtures:
            x0, y0, x1, y1 = fixture.x0, fixture.y0, fixture.x1, fixture.y1
            iy, ix = int((y0 + y1) / 2), int((x0 + x1) / 2)
            perimeter = ((x0, y0, x1, y0), (x1, y0, x1, y1),
                         (x1, y1, x0, y1), (x0, y1, x0, y0))
            for i, edge in enumerate(perimeter):
                walls.append((*edge, TILE[fixture.side], self.light[iy, ix] * (1. if i % 2 == 0 else .84),
                              fixture.base, fixture.top, self.area[iy, ix]))
        return walls

    def finish_geometry(self, walls):
        self.walls = np.asarray(walls, dtype=np.float32)
        self.roof_heights = np.unique(self.roof[self.roof > 0])
        self.caps = {}
        for fixture in self.fixtures:
            if fixture.top < 1.40:
                self.caps.setdefault(fixture.top, []).append(fixture)
        self.ground_heights = sorted(set(map(float, np.unique(self.ground))) | self.caps.keys())
        for fixture in self.collision_volumes:
            x0,y0=math.floor(fixture.x0-INDEX_RADIUS),math.floor(fixture.y0-INDEX_RADIUS)
            x1,y1=math.floor(fixture.x1+INDEX_RADIUS),math.floor(fixture.y1+INDEX_RADIUS)
            for y in range(y0,y1+1):
                for x in range(x0,x1+1):
                    self.near_fixtures.setdefault((x,y),[]).append(fixture)

    def elevation(self, x, y):
        return float(self.ground[int(y), int(x)])

    def blocked(self, x, y, radius=.0, z=None):
        for dx, dy in ((-radius, -radius), (-radius, radius), (radius, -radius), (radius, radius)):
            ix, iy = int(x + dx), int(y + dy)
            if not (0 <= iy < self.solid.shape[0] and 0 <= ix < self.solid.shape[1]):
                return True
            if self.solid[iy, ix] >= 0:
                return True
        if self.pane_at(x,y,z,radius):
            return True
        for gate in self.locked_gates:
            if abs(y-gate.y) < radius+.09 and abs(x-gate.x) < gate.width*.5+radius:
                return True
        tile=int(x),int(y)
        fixtures=self.near_fixtures.get(tile,()) if radius<=INDEX_RADIUS else self.collision_volumes
        for fixture in fixtures:
            if (fixture.x0 - radius < x < fixture.x1 + radius
                    and fixture.y0 - radius < y < fixture.y1 + radius
                    and (z is None or fixture.base - radius < z < fixture.top + radius)):
                return True
        return any(door.blocks(x,y,radius) for door in self.near_doors.get(tile,()))

    def pane_at(self, x, y, z=None, radius=0.):
        for a,b in self.pane_tiles:
            if ((a,b) not in self.broken_panes and a-radius < x < a+1+radius
                    and abs(y-b-.5) < radius+.044
                    and (z is None or .30 < z < 1.83)):
                return a,b
        return None

    def visible(self, x, y, xx, yy, z=None, zz=None):
        distance = math.hypot(xx - x, yy - y)
        n = max(1, math.ceil(distance * 9))
        return not any(self.blocked(x + (xx - x) * i / n, y + (yy - y) * i / n, .023,
                                    None if z is None else z + (zz - z) * i / n)
                       for i in range(1, n))

    def move(self, body, dx, dy, radius, occupied=None):
        def can_walk(x,y):
            if self.blocked(x,y,radius) or (occupied and occupied(x,y)):
                return False
            if not hasattr(body,"air"):
                return True
            up = self.elevation(x,y)-self.elevation(body.x,body.y)
            return up <= .245+body.air

        if can_walk(body.x + dx, body.y):
            body.x += dx
        if can_walk(body.x, body.y + dy):
            body.y += dy

    def update(self, dt, player, enemies=()):
        for door in self.doors:
            if ((door.opened and door.progress>=1.) or (not door.opened and door.progress<=0.)):
                continue
            if not door.opened and math.hypot(player.x-door.center[0],player.y-door.center[1])<.8:
                continue
            direction = 1 if door.opened else -1
            previous=door.progress
            door.progress = max(0, min(1, door.progress + dt * 1.65 * direction))
            if not door.opened and any(e.alive and door.blocks(e.x,e.y,e.radius) for e in enemies):
                door.progress=previous

    def door_walls(self):
        values = []
        for door in self.doors:
            seg = door.segment()
            if seg:
                values.append((*seg, door.material, self.light[door.y, door.x], 0.,
                               WALL_HEIGHT, self.area[door.y, door.x]))
        for x,y in self.pane_tiles:
            if (x,y) not in self.broken_panes:
                values.append((x, y+.5, x+1, y+.5, TILE["glazing"], .98, .36, 1.78, 1))
        return np.asarray(values, dtype=np.float32).reshape(-1, 9)


class Hickston(TileMap):
    def __init__(self):
        from campaign import Billboard, return_marker
        from county_wings import hickston_wing

        w, h = 96, 56
        super().__init__(w, h)
        self.pane_tiles = ((13, 20),)
        room, wall, door = self.room, self.wall, self.door

        room(1, 21, 48, 32, "asphalt", 0, light=1.03)
        room(1, 21, 48, 22, "gravel", 0, light=.96)
        room(1, 25, 48, 25, "road", 0, light=1.04)
        room(1, 27, 48, 28, "shoulder", 0, light=1.00)
        room(1, 29, 48, 32, "grass", 0, light=.91)
        room(8,29,12,31,"gravel",0,light=1.10)
        room(6,31,10,32,"tracks",0,light=1.06)
        room(26,26,30,26,"oil_asphalt",0,light=.99)
        room(29,26,32,27,"gravel",0,light=1.04)
        room(31,28,34,31,"tracks",0,light=1.04)
        room(34,31,37,32,"dirt",0,light=.95)
        room(1, 16, 5, 20, "gravel", 0, light=.96)
        room(2, 19, 4, 20, "concrete", 0, 2.18, .88, "joists")
        room(5, 21, 14, 21, "porch", 0, 2.22, .88, "joists")
        self.ground[21, 5:15] = .10
        wall(0, 16, 0, 32, "hedgerow", 1.22)
        wall(1, 33, 48, 33, "hedgerow", 1.28)
        wall(6,33,13,33,"stockyard",.68)
        wall(49, 19, 49, 32, "hedgerow", 1.45)
        # The safe crossroads uses an extra district of the original map.
        room(4,39,45,50,"gravel",11,light=1.09)
        room(13,49,36,54,"tracks",11,light=.98)
        room(5,41,10,52,"dirt",11,light=1.03)
        room(38,44,44,51,"gravel",11,light=1.06)
        service_road(self)
        gate_centers = (8.5,19.,30.,40.5)
        self.return_gate = Portal("hub",10.5,30.64,3.25,-1)
        self.hub_gates = tuple(Portal(level,x,y,4.0) for level,x,y in zip(
            ("hickston","fair","sawmill","quarry"),gate_centers,(35.27,37.22,35.62,37.01)))
        for gate,floor in zip(self.hub_gates,("asphalt","fair_gravel","tracks","quarry_dust")):
            room(int(gate.x)-3,34,int(gate.x)+3,39,floor,11,light=1.17)
            for y in range(39,51):
                x = round(gate.x + (24.5-gate.x)*((y-39)/18))
                self.floor[y,x-1:x+2] = TILE["tracks"]
            gate.paint_threshold(self.floor)
        self.return_gate.paint_threshold(self.floor)
        wall(13,37,15,40,"stockyard",1.32)
        wall(23,36,25,40,"stockyard",1.28)
        wall(33,36,35,39,"mill_tin",1.46)
        wall(42,43,44,43,"quarry_shed",1.44)
        wall(24,43,26,45,"hedgerow",.94)
        wall(4,44,4,50,"hedgerow",1.28)
        self.hub_clues = (
            ("ledger",7.4,49.8,"READ THE WEATHERED LEDGER","COUNTY ROAD CREW: TAKE THE WEST TURN FOR TOWN."),
            ("survey",42.7,45.1,"CHECK THE SURVEY PEG","PIN NINETEEN. THE COUNTY LINE MOVED, NOT THE PIN."),
            ("washout",30.55,48.55,"READ THE ROAD CREW NOTICE","CULVERT OPEN. RETURN THE BORROWED TOOLS TO THE SHED."),
        )
        room(7, 15, 14, 19, "floor_tile", 1, 2.22, .77)
        room(10, 12, 14, 14, "floor_tile", 1, 2.22, .66)
        wall(6, 15, 6, 20, "brick")
        wall(7, 20, 14, 20, "brick", 2.52)
        wall(7, 20, 7, 20, "window", 2.52)
        wall(13, 20, 14, 20, "window", 2.52)
        wall(8, 20, 8, 20, "liquor", 2.52)
        wall(12, 20, 12, 20, "eat", 2.52)
        room(13, 20, 13, 20, "porch", 1, 2.22, .86, "joists")
        self.ground[20, 13] = .36
        wall(15, 12, 15, 20, "plaster")
        wall(15, 12, 15, 16, "cinder")
        wall(7, 14, 8, 14, "tile")
        wall(9, 15, 9, 15, "restroom")
        wall(10, 11, 14, 11, "shelves")
        wall(7, 16, 7, 16, "shelves")
        wall(6, 17, 6, 19, "tavern")
        room(3, 12, 8, 14, "floor_tile", 2, WALL_HEIGHT, .80)
        wall(2, 11, 2, 15, "tile")
        wall(2, 13, 2, 13, "mirror")
        wall(3, 11, 8, 11, "tile")
        wall(3, 15, 6, 15, "tile")
        wall(9, 12, 9, 13, "tile")
        door(10, 20, style="hinge")
        door(9, 14, style="hinge", vertical=True)
        room(16, 16, 17, 18, "concrete", 3, WALL_HEIGHT, .62)
        door(15, 17, secret=True, vertical=True)
        # A delivery office beyond the dining room; the bathroom has a keyed
        # back exit for a short walk back to the roadside.
        room(12, 8, 16, 10, "porch", 7, 2.12, .82, "joists")
        wall(11, 8, 11, 10, "office_wall")
        wall(12, 7, 16, 7, "office_wall")
        wall(14, 7, 14, 7, "dispatch")
        wall(15, 9, 15, 9, "shelves")
        wall(12, 11, 12, 11, "dispatch")
        door(13, 11, style="hinge", area=7)
        door(5, 15, style="hinge", key="key_brass", area=2)
        wall(18, 11, 29, 20, "barn", 3.08)
        wall(25,20,28,20,"feed_wash",3.08)
        room(19, 12, 28, 19, "dirt", 4, 2.86, .67, "joists")
        room(22, 11, 24, 12, "tracks", 4, 2.22, .73, "joists")
        self.ground[11, 22:25] = .16
        wall(21, 17, 21, 18, "tin")
        wall(26, 13, 26, 14, "tin")
        wall(24, 16, 25, 16, "wood")
        wall(19, 16, 19, 16, "wanted")
        wall(21, 20, 21, 20, "barnsign", 3.08)
        wall(25, 20, 25, 20, "wanted", 3.08)
        door(23, 20, key="key_brass")
        # Feed gallery. Three broad stair treads rise to the scale office.
        room(19, 12, 22, 15, "porch", 4, 2.86, .81, "joists")
        self.ground[15, 19:23] = .12
        self.ground[14, 19:23] = .24
        self.ground[13, 19:23] = .36
        self.ground[12, 19:23] = .48
        wall(20, 11, 20, 11, "feed", 3.08)
        wall(25, 13, 25, 13, "feed")
        # Side road, trailer lot and the barn's broad loading approach.
        room(30, 15, 48, 24, "gravel", 8, light=.99)
        room(33, 22, 46, 24, "asphalt", 8, light=1.04)
        room(34, 15, 36, 19, "shoulder", 8, light=.97)
        room(37, 12, 47, 19, "grass", 8, light=1.02)
        # Split the service turn into a delivery apron and a low orchard-side loop.
        room(36, 19, 42, 20, "gravel", 8, light=1.04)
        room(44, 18, 47, 22, "tracks", 8, light=1.02)
        room(45, 12, 47, 17, "tracks", 8, light=.98)
        room(43, 11, 46, 11, "shoulder", 8, light=.99)
        wall(38, 12, 44, 16, "trailer", 2.14)
        room(39, 13, 43, 15, "floor_tile", 8, 2.08, .84, "ceiling")
        wall(38, 16, 39, 16, "trailer_window", 2.14)
        wall(42, 16, 43, 16, "trailer_window", 2.14)
        room(39, 17, 43, 17, "porch", 8, 2.14, .91, "joists")
        self.ground[17, 39:44] = .12
        door(41, 16, style="hinge", area=8)
        wall(33, 14, 35, 14, "tin")
        wall(34, 14, 34, 14, "service")
        room(31, 12, 33, 13, "concrete", 3, 2.02, .73)
        wall(31, 14, 33, 14, "tin")
        door(32, 14, secret=True, blast_only=True, area=8)
        door(29, 17, vertical=True, key="key_brass", area=8)
        wall(4, 1, 47, 6, "hedgerow", 1.48)
        wall(33,1,47,1,"hedgerow",1.22)
        wall(5, 7, 11, 10, "stockyard", 1.62)
        wall(17, 7, 33, 10, "stockyard", 1.62)
        room(6, 2, 32, 6, "grass", 5, light=.95)
        room(18, 7, 32, 9, "grass", 5, light=.96)
        room(6, 7, 11, 8, "grass", 5, light=.96)
        room(21, 6, 25, 9, "tracks", 5)
        room(33, 2, 46, 9, "grass", 10, light=1.00)
        room(34, 4, 44, 5, "creek", 9, light=.91)
        room(33, 5, 33, 5, "creek", 9, light=.89)
        room(45, 4, 46, 4, "creek", 9, light=.89)
        room(38, 3, 39, 6, "porch", 10, light=1.02)
        self.ground[self.floor == TILE["creek"]] = -.14
        self.ground[3:7, 38:40] = .11
        room(35, 6, 37, 6, "shoulder", 10, light=.93)
        room(40, 3, 44, 3, "shoulder", 10, light=.93)
        room(40, 6, 42, 6, "shoulder", 10, light=.93)
        room(34,7,35,8,"orchard",10,light=.95)
        wall(33, 10, 46, 10, "stockyard", 1.46)
        wall(47, 7, 47, 9, "hedgerow", 1.45)
        room(7, 3, 12, 4, "orchard", 10, light=.94)
        wall(22, 10, 22, 10, "warning")
        door(23, 10, key="key_steel")
        wall(13, 3, 14, 5, "wood")
        wall(30, 7, 31, 8, "ship")
        wall(17, 6, 17, 9, "stockyard")
        wall(12, 7, 16, 7, "stockyard")
        wall(16, 8, 17, 8, "office_wall")
        room(16, 8, 16, 8, "porch", 7, 2.12, .82, "joists")
        # A bend under the packing shed connects the west pasture to the old cache.
        room(11, 6, 12, 6, "tracks", 5)
        wall(25, 2, 31, 2, "ship", 2.67)
        wall(30, 3, 31, 4, "ship")
        room(7, 6, 10, 8, "concrete", 6, 2.22, .72, "ship")
        wall(6, 5, 11, 5, "ship")
        wall(6, 6, 6, 8, "ship")
        wall(11, 6, 11, 8, "ship")
        wall(7, 9, 10, 9, "ship")
        door(11, 7, secret=True, vertical=True)
        room(12, 7, 12, 7, "tracks", 5)
        wall(12, 8, 12, 8, "office_wall")

        self.tints = np.vstack((self.tints,(1.03,1.00,.91))).astype(np.float32)
        wing = hickston_wing(self)
        self.fixtures = (
            Fixture(5.22, 21.75, 5.36, 21.89, 2.22, "wood", base=.10),
            Fixture(14.65, 21.75, 14.80, 21.89, 2.22, "wood", base=.10),
            Fixture(7.55, 18.03, 9.56, 18.74, .77, "counter"),
            Fixture(13.30, 15.28, 14.62, 15.78, .63, "counter"),
            Fixture(3.35, 14.62, 5.1, 14.81, 1.32, "steel_mesh"),
            Fixture(26.70, 19.16, 27.54, 19.85, .71, "crate_side", "porch"),
            Fixture(28.15, 12.26, 28.72, 13.40, .71, "crate_side", "porch"),
            Fixture(29.92, 5.45, 30.78, 6.36, .71, "crate_side", "porch"),
            Fixture(7.33, 6.37, 8.02, 7.11, .71, "crate_side", "porch"),
            Fixture(12.28, 8.79, 12.91, 10.05, .77, "counter"),
            Fixture(19.26, 12.19, 19.98, 12.73, 1.22, "counter", base=.48),
            Fixture(39.22, 13.3, 40.5, 13.96, .72, "counter"),
            Fixture(42.65, 14.7, 43.77, 15.61, .44, "crate_side", "porch"),
            Fixture(35.9, 20.55, 38.65, 21.25, .57, "stockyard", "porch"),
            Fixture(39.20, 20.30, 42.20, 20.61, .66, "stockyard", "porch"),
            Fixture(45.48, 16.07, 45.86, 16.92, .51, "crate_side", "porch"),
            Fixture(3.2, 27.05, 5.6, 27.84, .72, "bleachers", "porch"),
            Fixture(26.40, 4.86, 27.42, 5.14, .48, "stockyard", "porch"),
            # The tall feed stack covers the east turn around the rescue pen.
            Fixture(30.10, 3.5, 31.97, 4.3, 1.14, "stockyard", "porch"),
            Fixture(36.21, 2.80, 37.57, 3.12, .48, "stockyard", "porch"),
            Fixture(42.55, 6.2, 45.5, 6.55, .50, "stockyard", "porch"),
            Fixture(7.12,49.67,7.76,50.23,.65,"stockyard"),
            Fixture(42.9,45.35,44.28,46.1,.71,"crate_side"),
            Fixture(21.3,44.12,22.6,45.32,.58,"tin"),
            Fixture(34.7,42.25,36.42,43.12,.71,"stockyard"),
            Fixture(1.5,28.25,2.12,30.6,.78,"stockyard"),
            Fixture(34.8,30.0,38.4,30.49,.88,"stockyard"),
            Fixture(39.5,30.43,41.05,30.98,.73,"stockyard"),
            Fixture(32.10,30.51,33.96,31.05,.53,"stockyard"),
            Fixture(35.6,28.95,37.44,29.28,.76,"bleachers","porch"),
            Fixture(27.45,21.24,28.46,21.74,.54,"stockyard"),
            Fixture(23.34,47.10,23.58,49.80,.87,"hub_service_wall","hub_service_wall"),
            Fixture(29.4,43.7,30.5,44.35,.82,"counter","counter_top"),
            Fixture(32.0,43.1,33.48,43.65,.91,"crate_side","porch"),
            Fixture(33.92,48.56,34.76,48.83,.44,"hub_service_wall","hub_service_wall"),
            Fixture(6.86,41.03,8.20,41.56,.69,"hub_service_wall","counter_top"),
            Fixture(15.51,40.92,16.52,41.45,.56,"fair_iron","porch"),
            Fixture(27.93,39.04,28.86,39.55,.64,"mill_log","porch"),
            Fixture(43.84,42.52,44.48,43.18,.70,"quarry_face","quarry_face"),
            *tuple(Fixture(TOWER_X+x-.086,TOWER_Y+y-.086,TOWER_X+x+.086,TOWER_Y+y+.086,
                           3.57,"mill_tin") for x in (-.72,.72) for y in (-.52,.52)),
        )
        self.fixtures += self.return_gate.posts("stockyard")+wing.fixtures
        self.fixtures += tuple(post for gate in self.hub_gates for post in gate.posts())
        self.collision_volumes = self.fixtures + (
            Fixture(27.74,28.03,29.06,28.83,.98,"tin"),
            Fixture(45.30,22.34,46.66,23.21,.98,"tin"),
            Fixture(29.18,47.98,31.80,48.04,2.24,"hub_screen"),
        )

        # Baked pools from the porch bulbs, tavern fixtures, barn and gate.
        yy, xx = np.indices((h, w), dtype=np.float32)
        for lx, ly, strength, radius, area in ((10.5, 21.8, .28, 2.7, 0), (5.9, 21.6, .22, 2.1, 0),
                                                (10.4, 17.0, .25, 2.2, 1), (13.0, 12.5, .17, 1.7, 1),
                                                (4.2, 13.6, .22, 1.9, 2), (23.1, 18.4, .26, 2.7, 4),
                                                (20.2, 13.0, .18, 1.6, 4), (27.3, 15.6, .23, 1.9, 4),
                                                (23.3, 9.1, .27, 1.8, 5), (27.3, 3.6, .31, 2.3, 5),
                                                (13.8, 9.2, .20, 1.6, 7), (41.4, 14.4, .21, 1.4, 8),
                                                (41.1, 17.4, .18, 2.1, 8), (38.6, 5.5, .15, 2.3, 10)):
            distance = (xx + .5 - lx)**2 + (yy + .5 - ly)**2
            self.light += (self.area == area) * strength * np.exp(-distance / radius**2)
        # Unlit ground beneath the trees and an open strip along the bridge.
        for x,y,strength,radius,area in ((36.8,4.5,-.22,2.8,9),(45.5,5.8,-.22,2.6,10),
                                         (37.4,2.7,-.17,2.5,10),(39.0,6.4,.12,1.8,10)):
            self.light_pool(x,y,strength,radius,area)

        walls = self.wall_segments(hickston_facades=True)
        # The solid boundary still separates the two game districts. Omit only
        # its south faces inside the gates so their approaches continue to the horizon.
        walls = [edge for edge in walls if not (edge[1] == edge[3] == 34 and edge[8] == 11
                 and any(abs((edge[0]+edge[2])/2-x) < 2.5 for x in gate_centers))]
        # Diagonal braces and rafters give each structure a distinct profile.
        walls.extend(((5.33, 21.85, 6.10, 21.21, TILE["wood"], .91, 1.98, 2.19, 0),
                      (13.95, 21.21, 14.73, 21.85, TILE["wood"], .89, 1.98, 2.19, 0),
                      (19.10, 18.31, 20.75, 16.90, TILE["porch"], .68, 2.40, 2.68, 4),
                      (25.56, 4.05, 27.24, 2.96, TILE["ship"], .82, 1.91, 2.42, 5)))
        walls.extend((
            (12.95,22.032,7.00,22.032,TILE["stanky_marquee"],1.21,2.23,2.75,0),
            (26.3,21.058,20.65,21.058,TILE["feed_marquee"],1.12,2.03,2.57,0),
        ))
        poles = ((16.6,28.4),(33.6,28.2),(47.5,27.75))
        for (ax,ay),(bx,by) in zip(poles,poles[1:]):
            for segment in range(9):
                u,v=segment/9,(segment+1)/9
                z = 3.39-.44*math.sin(math.pi*(u+v)*.5)
                for shift in (0.,.20):
                    walls.append((ax+(bx-ax)*u,ay+(by-ay)*u+shift,
                                  ax+(bx-ax)*v,ay+(by-ay)*v+shift,
                                  TILE["cable"],.88,z,z+.027,0))
        for x,y in self.pane_tiles:
            walls.append((x, y+.5, x+1, y+.5, TILE["brick"], .88, 1.78, 2.37, 1))
        for gate in self.hub_gates:
            walls.extend(gate.frame(11))
        walls.extend((
            (29.18,48.,31.80,48.,TILE["hub_screen"],1.11,0.,2.23,11),
            (31.80,48.,31.80,48.35,TILE["barn"],.89,0.,2.53,11),
            (29.18,48.,34.,48.,TILE["mill_tin"],.94,2.24,2.55,11),
        ))
        for depth in (-.52,.52):
            y=TOWER_Y+depth
            for a,b in ((.73,2.14),(2.12,3.47)):
                for i in range(6):
                    z=a+(b-a)*(i+.5)/6
                    for side in (-1.,1.):
                        x=TOWER_X+side*(i/6-.5)*1.44
                        xx=TOWER_X+side*((i+1)/6-.5)*1.44
                        walls.append((x,y,xx,y,TILE["mill_tin"],.78,z-.21,z+.21,11))
        walls.extend(tank_faces(TILE["hub_tank_shell"]))
        utility = ((12.2,42.38),(22.84,40.82),(34.92,41.52),(44.48,42.36))
        for (ax,ay),(bx,by) in zip(utility,utility[1:]):
            for i in range(7):
                a,b = i/7,(i+1)/7
                z = 3.28-.31*math.sin(math.pi*(a+b)*.5)
                walls.append((ax+(bx-ax)*a,ay+(by-ay)*a,ax+(bx-ax)*b,ay+(by-ay)*b,
                              TILE["cable"],.86,z,z+.031,11))
        walls.extend(self.return_gate.frame(0,"stockyard"))
        self.finish_geometry(walls)
        self.mirror = (3., 13., 3., 14.)
        self.billboards = (
            Billboard(8.6,18.32,"story_food",.27,.78),
            Billboard(12.62,9.33,"story_dispatch",.27,.78),
            Billboard(27.16,19.46,"mill_timber",.38,.71),
            Billboard(20.15,12.07,"wing_town_register",.72,.98,signal="legacy-key",plane=0.),
            Billboard(27.04,7.98,"story_aftermath",.19,.025),
            Billboard(27.37,7.19,"story_aftermath",.17,.021),
            return_marker(self.return_gate),
            Billboard(32.89,31.15,"service_detour",.94,plane=.24),
            Billboard(27.88,21.52,"split_feed_sacks",.52,.43),
            Billboard(28.65,20.95,"delivery_plaque",.57,1.02,plane=0.),
            Billboard(33.18,14.84,"powder_notice",.62,.63,plane=0.),
            Billboard(10.74,6.42,"packing_notice",.53,.85,plane=.12),
            Billboard(24.70,46.15,"hub_directory",1.56,plane=.06,back="hub_directory_back"),
            Billboard(8.4,44.5,"hub_lamp",2.52,glow=True),
            Billboard(36.05,45.55,"hub_lamp",2.52,glow=True),
            Billboard(7.4,49.8,"story_dispatch",.25,.65),
            Billboard(42.7,45.1,"survey_peg",.58,plane=-.40),
            Billboard(TOWER_X,TOWER_Y+.915,"hub_tank_label",.35,3.49,plane=0.),
            Billboard(TOWER_X-.68,TOWER_Y+.85,"prop_reeds",.89),
            Billboard(TOWER_X+.72,TOWER_Y+.69,"prop_reeds",.71),
            Billboard(30.55,48.045,"hub_road_dept",.46,2.12,plane=0.),
            Billboard(33.52,44.49,"prop_tire",.49),
            Billboard(32.66,44.13,"mill_timber",.57,.008),
            Billboard(34.53,49.53,"prop_reeds",.61),
            Billboard(27.14,50.63,"prop_reeds",.52),
            Billboard(7.55,41.57,"hub_hickston_marker",.50,.50,plane=0.),
            Billboard(16.0,41.46,"hub_fair_marker",.48,.36,plane=0.),
            Billboard(28.44,39.56,"hub_mill_marker",.48,.42,plane=0.),
            Billboard(43.56,44.02,"hub_quarry_marker",.50,.68,plane=0.),
            *tuple(Billboard(x,y,"prop_utilitypole",3.57) for x,y in utility),
            *tuple(Billboard(gate.x+side*2.23,gate.y+.14,"hub_lamp",2.20,glow=True)
                   for gate in self.hub_gates for side in (-1,1)),
        )

        self.enemies = [
            # One sentry faces the road. Its backup starts off-angle near the feed store.
            ("coot", 12.8, 22.9), ("billy", 17.7, 23.8), ("clone", 27.15, 22.2),
            # A bar ambush and a separate guard in the back alley.
            ("billy", 12.8, 18.6), ("coot", 12.75, 13.35), ("chicken", 4.8, 23.4),
            # Two floor-level threats, a high-reach guard and a clear entry lane.
            ("billy", 20.45, 18.85), ("clone", 27.2, 17.85), ("coot", 21.35, 13.46),
            ("alien", 27.65, 13.35), ("chicken", 26.3, 19.1), ("pig", 22.5, 14.35),
            # Orchard approach and two sides of the arena, outside the locked gate.
            ("alien", 20.35, 5.06), ("alien", 26.90, 7.26), ("saucer", 24.7, 5.08),
            ("saucer", 15.52, 6.13), ("chicken", 20.35, 8.48), ("pig", 29.38, 5.1),
            ("skeeter", 18.85, 6.32), ("skeeter", 28.85, 7.43),
            ("coot", 14.86, 8.69), ("billy", 37.03, 17.6), ("coot", 43.03, 13.61),
            ("clone", 45.15, 18.8), ("chicken", 46.0, 17.2), ("billy", 9.4, 3.4),
            # The crossing has one close guard, a low flier and a long-range saucer.
            ("alien", 35.27, 5.0), ("skeeter", 42.34, 5.55), ("saucer", 45.42, 3.76),
            ("pig", 44.7, 8.4),
            ("boss", 26.6, 3.6), ("jerry", 28.65, 3.8), ("bessie", 28.2, 3.65),
        ]
        self.enemy_ids = (
            "road-coot","road-billy","feed-store-clone","tavern-billy","back-alley-coot",
            "road-chicken","barn-billy","barn-clone","scale-coot","barn-guard","barn-chicken",
            "barn-pig","orchard-guard","pasture-guard","pasture-saucer","orchard-saucer",
            "pasture-chicken","pen-pig","orchard-skeeter","pasture-skeeter","dispatch-coot",
            "trailer-billy","trailer-coot","trailer-clone","trailer-chicken","orchard-billy",
            "creek-guard","creek-skeeter","creek-saucer","creek-pig","sheriff","jerry","bessie",
        )
        self.door_ids = {
            **self.door_ids,
            (10,20):"tavern-front", (9,14):"restroom", (15,17):"supply-secret",
            (13,11):"dispatch", (5,15):"restroom-shortcut", (23,20):"barn-front",
            (41,16):"trailer", (32,14):"powder-secret", (29,17):"barn-loading",
            (23,10):"steel-gate", (11,7):"packing-secret",
        }
        # Roster order is stable for existing checkpoints. Waypoints are transient.
        self.patrols = {
            0: ((12.75,23.65),(13.65,23.1),(12.8,22.9)),
            1: ((17.1,24.6),(18.55,24.3),(17.7,23.8)),
            2: ((25.5,22.28),(26.1,22.7),(27.15,22.2)),
            3: ((12.1,18.62),(12.8,18.6)),
            4: ((12.32,14.48),(12.75,13.35)),
            6: ((20.4,19.46),(21.32,19.46),(20.4,19.46),(20.45,18.85)),
            7: ((25.63,17.61),(27.2,17.85)),
            8: ((21.28,14.52),(21.35,13.46)),
            9: ((27.54,14.52),(27.65,13.35)),
            12: ((19.55,5.42),(20.35,5.06)),
            13: ((26.96,8.24),(26.90,7.26)),
            14: ((24.7,6.09),(25.5,5.88),(24.7,5.08)),
            15: ((15.56,5.51),(15.52,6.13)),
            18: ((18.61,5.12),(19.30,5.76),(18.85,6.32)),
            19: ((29.45,8.26),(28.85,7.43)),
            20: ((13.70,8.65),(14.86,8.69)),
            21: ((36.0,18.71),(37.03,17.6)),
            22: ((42.42,14.04),(43.03,13.61)),
            23: ((44.63,20.28),(45.15,18.8)),
            25: ((10.25,3.82),(9.4,3.4)),
            26: ((35.65,6.21),(35.27,5.0)),
            27: ((41.32,5.84),(42.34,5.55)),
            28: ((44.7,4.48),(45.42,3.76)),
        }
        self.pickups = [
            ("slingblade",4.25,24.5),
            ("bullets", 10.4, 23.2), ("rinds", 8.2, 22.4), ("beer", 13.4, 22.4),
            ("dynamite", 5.8, 22.55), ("dynamite", 34.5, 16.7),
            ("rinds", 8.1, 17.6), ("beer", 13.5, 18.5), ("moonshine", 11.4, 14.4),
            ("key_brass", 13.65, 8.70), ("bullets", 12.2, 13.2), ("beer", 3.7, 12.6),
            ("shells", 16.6, 16.6), ("moonshine", 16.7, 17.4), ("rinds", 16.8, 18.4),
            ("rifle", 16.53, 17.61), ("rifle_ammo", 22.28, 18.8),
            ("shotgun", 23.3, 18.7), ("shells", 20.2, 19.3), ("rinds", 26.3, 18.4),
            ("crossbow", 27.3, 15.6), ("dynamite", 27.4, 14.7),
            ("shells", 23.7, 11.7), ("beer", 22.5, 11.6), ("rinds", 23.4, 8.4),
            ("ripsaw", 23.3, 13.27), ("saw_ammo", 24.45, 13.19),
            ("shells", 25.8, 7.6), ("dynamite", 23.7, 6.5), ("shells", 22.7, 4.6),
            ("moonshine", 28.5, 7.7), ("dynamite", 8.5, 7.7), ("rinds", 8.35, 6.8),
            ("armgun", 21.75, 7.0), ("arm_ammo", 10.26, 7.13), ("arm_ammo", 28.55, 6.3),
            ("rifle_ammo", 26.1, 5.8), ("saw_ammo", 22.5, 5.63),
            ("dynamite", 29.3, 4.7), ("bullets", 32.7, 22.6),
            ("shells", 3.5, 20.4), ("bullets", 15.74, 10.44), ("rinds", 39.8, 14.8),
            ("moonshine", 42.25, 13.8), ("shells", 45.7, 18.2), ("bullets", 34.5, 17.5),
            ("rifle_ammo", 31.8, 12.7), ("shells", 32.6, 13.0), ("moonshine", 33.4, 12.8),
            ("rinds", 9.5, 3.9), ("shells", 14.4, 2.65), ("saw_ammo", 39.2, 8.4),
            ("arm_ammo", 44.6, 3.3), ("beer", 45.1, 8.3),
        ]
        self.props = [("pump", 5.48, 21.55), ("pump_b", 6.5, 21.55), ("barrel", 15.5, 21.5),
                      ("barrel", 28.6, 21.6), ("hay", 19.9, 15.2), ("hay", 27.2, 18.79),
                      ("hay", 20.5, 12.9), ("barrel", 14.35, 16.23), ("sink", 3.2, 13.5),
                      ("barrel", 29.4, 6.1), ("hay", 16.4, 3.9),
                      ("crate", 10.0, 6.9), ("barrel", 6.3, 3.0), ("crate", 27.8, 8.1),
                      ("jukebox", 7.26, 17.14), ("lamp", 10.45, 17.02),
                      ("lamp", 23.15, 18.45), ("lamp", 27.25, 15.65), ("lamp", 4.25, 13.2),
                      ("lamp", 13.6, 9.25), ("lamp", 41.3, 14.5),
                      ("roadsign", 11.96, 27.83), ("utilitypole", 16.6, 28.4),
                      ("utilitypole", 33.6, 28.2), ("utilitypole", 47.5, 27.75),
                      ("water_tower", 33.87, 31.62),
                      ("pickup_truck", 28.4, 28.45), ("pickup_truck_b", 46.0, 22.8),
                      ("tree", 5.2, 31.1), ("tree", 19.4, 31.45), ("tree", 36.2, 31.7),
                      ("tree_b", 9.8, 2.75), ("tree", 11.9, 3.8), ("tree_b", 15.9, 2.8),
                      ("tree", 34.5, 2.9), ("tree_b", 46.1, 6.5), ("tree", 7.0, 4.3),
                      ("tree_b",37.25,2.44),("tree",43.38,2.22),
                      ("mailbox", 40.58, 19.45), ("hay", 35.6, 8.6), ("hay", 42.8, 8.4),
                      ("windmill", 41.8, 2.62), ("silo", 32.8, 15.55), ("silo", 31.95, 16.1),
                      ("reeds", 34.6, 4.2), ("reeds", 36.5, 5.82), ("reeds", 40.28, 5.67),
                      ("reeds", 43.65, 4.25), ("reeds", 45.84, 4.81), ("reeds", 43.95, 5.71),
                      ("reeds", 36.06, 4.28), ("reeds", 35.2, 5.73), ("reeds", 41.67, 4.22),
                      ("tire", 33.6, 16.45), ("tire", 45.5, 20.5),
                      ("bleacher_sign", 25.8, 3.15), ("barrel", 34.6, 15.85),
                      ("barrel", 21.5, 12.75), ("barrel", 37.4, 8.4)]
        self.props.extend((("tree",4.8,36.5),("tree",45.8,37.75),("tree",14.5,38.2),
                           ("tree",40.8,31.45),("tree",37.2,32.05),("tree",34.7,31.1),
                           ("reeds",14.1,31.5),("reeds",15.1,30.9),("reeds",35.8,7.4),
                           ("barrel",13.6,40.5),("crate",35.8,42.3),("barrel",43.1,43.4),
                           ("tree",5.7,46.5),("tree",44.2,47.7),("tree",45.3,51.3),
                           ("tire",14.3,48.4),("barrel",18.9,42.35)))
        self.fuel_drums = ((31.5, 22.18), (28.22, 17.20), (28.99, 5.58), (29.7, 4.65))
        wing.install(self)
        from county_detail import install
        install(self,"hickston")
        from engine import GroundMark
        self.dress_marks += tuple(GroundMark(x,y,self.elevation(x,y)+.003,heading,reach,width,"county_creek_shadow")
                                  for x,y,heading,reach,width in ((36.9,3.24,.64,2.2,.68),
                                                                 (44.87,7.52,2.51,2.7,1.06)))
        self.dress_marks += tuple(GroundMark(x,y,self.elevation(x,y)+.003,angle,1.64,.58,"fx_shadow")
                                  for x,y,angle in ((28.4,28.45,.18),(46.0,22.8,-.22),(61.76,23.47,.24)))
