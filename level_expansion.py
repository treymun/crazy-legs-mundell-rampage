"""The county fair and the flooded sawmill, built from the existing tile geometry."""
import math

import numpy as np

from level_hickston import Fixture, Portal, TILE, TileMap


class CountyFair(TileMap):
    def __init__(self):
        # Late imports keep the map geometry independent of the registry.
        from campaign import Billboard, Extraction, Station, return_marker
        from county_wings import fair_wing

        super().__init__(69, 44)
        self.sky = "fair_sky"
        self.tints = np.asarray(((1.04,.94,1.04), (.96,1.02,1.08), (1.07,1.03,.89),
                                 (.87,1.03,1.10), (1.12,.93,1.02), (.92,1.06,1.02)),
                                dtype=np.float32)
        room, wall, door = self.room, self.wall, self.door

        # The old parking lane converges on the narrow admission arch.
        room(15, 34, 28, 38, "fair_gravel", 0, light=.99)
        room(19, 38, 23, 40, "fair_gravel", 0, light=1.10)
        room(23,39,26,40,"fair_gravel",0,light=1.03)
        wall(19,41,26,41,"stockyard",.55)
        self.return_gate = Portal("hub",21.5,38.48,3.45,-1)
        self.return_gate.paint_threshold(self.floor)
        room(18, 31, 25, 34, "fair_gravel", 0, light=.93)
        room(25, 31, 29, 35, "floor_tile", 0, 2.12, .81)
        wall(25, 31, 29, 31, "fair_booth", 2.28)
        wall(25, 34, 29, 34, "fair_booth", 2.28)
        room(25, 33, 25, 33, "porch", 0, 2.12, .91)
        wall(25, 32, 25, 32, "fair_booth", 2.28)
        wall(25, 35, 29, 35, "fair_iron", 2.28)
        room(11, 18, 32, 30, "fair_gravel", 1, light=1.10)
        room(15, 29, 27, 32, "fair_gravel", 1, light=1.04)
        room(18, 19, 25, 28, "porch", 1, light=1.08)
        wall(12, 27, 13, 30, "fair_booth", 2.4)
        wall(29, 27, 31, 29, "fair_booth", 2.4)
        wall(13, 18, 16, 20, "fair_iron", 2.26)
        wall(26, 20, 27, 22, "fair_booth", 1.88)
        wall(30, 18, 32, 19, "fair_iron", 2.23)
        # A low raffle island makes an actual loop around the midway.
        wall(19,26,19,27,"fair_prize",.83)
        wall(23,24,24,24,"fair_booth",.79)
        room(15,27,16,28,"porch",1,light=1.08)

        # West concession: the counter lane wraps around the service wall.
        room(5, 20, 10, 28, "fair_gravel", 2, light=.95)
        room(6, 21, 9, 25, "floor_tile", 2, 2.16, .88)
        wall(8, 23, 9, 23, "fair_booth", 1.78)
        wall(10, 19, 10, 24, "fair_iron", 2.18)
        wall(10, 27, 10, 29, "fair_iron", 2.18)
        room(10, 25, 12, 26, "porch", 2, light=1.)
        room(10, 20, 12, 20, "porch", 2, light=1.)
        door(10, 20, 2, vertical=True, texture="fair_iron")
        room(2, 22, 3, 25, "porch", 2, 1.15, .91)
        door(4, 23, 2, vertical=True, secret=True)

        # East game court: walls and a low divider make the two entries play differently.
        room(34, 16, 40, 28, "fair_gravel", 3, light=.89)
        room(36, 19, 40, 23, "porch", 3, 2.27, .94)
        wall(36, 21, 38, 21, "fair_booth", 1.49)
        wall(33, 16, 33, 28, "fair_iron", 2.05)
        room(33, 24, 34, 26, "fair_gravel", 3, light=.90)
        room(32, 20, 33, 20, "fair_gravel", 3, light=.92)
        door(33, 20, 3, vertical=True, texture="fair_iron")
        room(38, 13, 40, 14, "porch", 3, 2.06, .81)
        door(39, 15, 3, secret=True)

        # Pavilion is visible from the first long midway sightline. It has two open bays.
        room(15, 8, 27, 16, "porch", 4, 2.65, .89, "joists")
        wall(15, 17, 27, 17, "fair_prize", 2.85)
        door(21, 17, 4, texture="fair_gate")
        door(22, 17, 4, texture="fair_gate")
        wall(15, 7, 27, 7, "fair_prize", 3.15)
        room(29, 14, 31, 16, "floor_tile", 4, 2.20, .85)
        door(28, 15, 4, vertical=True, secret=True)
        room(29, 8, 39, 11, "fair_gravel", 5, light=.97)
        room(36, 8, 39, 10, "porch", 5, 2.14, .97)
        door(28, 9, 5, vertical=True, texture="fair_iron")
        self.crouch_doors = frozenset({(4, 23)})
        self.objective_side_tasks = ("bell",)
        self.v2_implied_tasks = {"broadcast":("bell",)}
        self.controlled_doors = frozenset({(10,20), (33,20), (21,17), (22,17), (28,9)})
        self.door_ids = {(10,20):"concession-shortcut", (4,23):"low-hatch", (33,20):"games-shortcut",
                         (39,15):"lost-socks", (21,17):"pavilion-left", (22,17):"pavilion-right",
                         (28,15):"prize-shelf", (28,9):"service-alley"}
        wing = fair_wing(self)

        self.fixtures = (
            Fixture(19.10, 24.1, 20.65, 24.9, .66, "fair_booth"),
            Fixture(23.50, 22.0, 24.90, 22.85, .61, "fair_booth"),
            Fixture(16.3, 27.45, 17.15, 28.55, .77, "fair_iron"),
            Fixture(7.25, 24.45, 8.40, 25.30, .80, "fair_booth"),
            Fixture(35.1, 25.6, 35.65, 27.1, .63, "fair_iron"),
            Fixture(16.6, 12.1, 18.8, 12.85, .67, "fair_prize"),
            # The low prize shelf lets the east approach see the booth; the
            # tall divider at the ring breaks the central horn's sightline.
            Fixture(23.9, 13.1, 25.8, 13.85, .55, "fair_prize"),
            Fixture(20.0, 9.4, 21.1, 10.2, 1.13, "fair_gate"),
            Fixture(25.75, 32.10, 27.6, 32.7, .78, "fair_booth"),
        )
        self.fixtures += self.return_gate.posts("fair_iron")+wing.fixtures
        self.collision_volumes = self.fixtures
        for x, y, power, size, area in (
            (21.5,34.5,.30,3,0), (20.1,26.5,.26,3,1), (22.2,18.6,.35,4,1),
            (7.2,22.1,.37,3,2), (38.4,17.8,.34,3,3),
            (22.7,11.6,.31,4,4), (36.8,9.6,.30,4,5),
        ):
            self.light_pool(x,y,power,size,area)
        walls = self.wall_segments()
        walls.extend(self.return_gate.frame(0,"fair_iron"))
        # Segments here are overhead fascia. Walking and use tests still see the grid.
        walls.extend((
            (24.9,33.4,18.1,33.4,TILE["fair_gate"],1.24,2.15,3.10,0),
            (26.7,17.94,15.4,17.94,TILE["fair_prize"],1.25,2.36,3.30,4),
            (25.45,18.18,18.75,18.18,TILE["fair_marquee"],1.45,1.98,2.62,4),
            (20.8,34.0,20.8,33.3,TILE["fair_iron"],.94,2.03,3.12,0),
        ))
        self.finish_geometry(walls)

        self.stations = (
            Station("concession", 6.15,21.0,"SET CONCESSION BREAKER",
                    "CONCESSION LIVE. NORTH GATE IS OPEN.", opens=((10,20),), sectors=(2,),
                    cue="breaker_thunk"),
            Station("games",58.8,10.22,"PATCH THE BACKSTAGE PA",
                    "PA PATCHED. TAKE THE SERVICE CUT BACK TO THE MIDWAY.",
                    opens=((33,20),(43,18)),sectors=(3,8),cue="broadcast_cut",held="pa_patch"),
            Station("broadcast", 22.65,10.55,"CUT THE PRIZE BROADCAST",
                    "RUDY RACKET! GET BEHIND THE PRIZE STALLS.",
                    requires=("concession","games","bell"), opens=((28,9),), sectors=(4,5),
                    cue="broadcast_cut"),
            Station("bell",22.10,19.15,"RING THE MIDWAY BELL",
                    "SHOW BELL RUNG. THE PRIZE PAVILION IS OPEN.",
                    requires=("concession","games"),opens=((21,17),(22,17),),cue="fair_bell"),
        )
        self.extraction = Extraction(38.15,9.5,"USE SERVICE EXIT","broadcast")
        self.control_name = "CONCESSION AND BACKSTAGE PA"
        self.billboards = (
            return_marker(self.return_gate),
            Billboard(34.2,12.0,"fair_wheel",7.8,.1,plane=-.19),
            Billboard(21.5,32.06,"fair_entry",.64,1.65,plane=0.),
            Billboard(22.10,18.92,"fair_bell",1.12,signal="bell",plane=0.),
            Billboard(11.55,25.3,"fair_concession_arrow",1.34,plane=.38,back="wayfinding_back"),
            Billboard(32.45,24.3,"fair_games_arrow",1.34,plane=-.38,back="wayfinding_back"),
            Billboard(6.15,20.81,"fair_control",1.03,signal="concession",glow=True),
            Billboard(39.42,20.34,"wing_fair_freight",.91,.40,plane=-.22),
            Billboard(22.65,10.35,"fair_relay",1.47,signal="broadcast",glow=True),
            Billboard(39.96,9.72,"fair_exit",.82,.72,signal="exit",plane=math.pi/2),
            Billboard(26.4,32.38,"fair_ticket_rule",.70,.86,plane=-1.57),
            Billboard(24.40,10.2,"fair_redemption",1.20,.43,plane=0.),
            Billboard(39.35,16.4,"fair_lost_property",.80,.46,plane=0.),
            Billboard(18.0,12.35,"fair_prize_pile",.68,.68),
            Billboard(25.33,13.42,"fair_prize_pile",.62,.56),
            Billboard(8.05,24.78,"fair_spill",.20,.81),
            Billboard(30.55,28.1,"fair_bulbs",.44,1.85,glow=True),
            Billboard(12.8,27.25,"fair_bulbs",.44,1.85,glow=True),
            Billboard(21.0,19.5,"fair_bulbs",.37,1.85,glow=True),
            Billboard(32.5,20.45,"fair_bulbs",.39,1.67,signal="games",glow=True),
            Billboard(11.25,20.45,"fair_bulbs",.39,1.67,signal="concession",glow=True),
            Billboard(18.8,32.2,"fair_pylon",2.4,glow=True),
            Billboard(24.4,32.2,"fair_pylon",2.4,glow=True),
        )
        self.props = [("barrel",14.5,29.45), ("crate",28.9,30.5),
                      ("barrel",31.5,23.9), ("crate",18.6,15.65),
                      ("crate",25.8,8.45), ("barrel",34.5,8.6)]
        self.props += [("crate",43.5,31.5), ("barrel",32.5,30.5),
                       ("hay",11.5,29.5), ("tire",55.5,8.5),
                       ("crate",28.5,36.5), ("barrel",15.5,38.5),
                       ("hay",15.5,8.5), ("tire",9.5,22.5),
                       ("crate",66.5,22.5), ("barrel",66.5,7.5),
                       ("hay",65.5,41.5), ("tire",17.5,18.5),
                       ("crate",12.5,18.5), ("barrel",45.5,14.5),
                       ("hay",39.5,8.5), ("tire",15.5,34.5),
                       ("crate",47.5,39.5), ("barrel",39.5,11.5),
                       ("hay",34.5,16.5), ("tire",29.5,11.5),
                       ("crate",51.5,41.5), ("barrel",66.5,14.5),
                       ("hay",40.5,28.5), ("tire",61.5,35.5)]
        self.fuel_drums = ((12.8,23.7), (27.15,11.85))
        self.pickups = [
            ("rinds",20.72,36.18), ("bullets",21.76,36.1), ("shotgun",22.64,36.1),
            ("shells",23.2,35.92), ("bullets",26.65,33.45),
            ("shells",15.45,28.7), ("rinds",17.6,26.5), ("beer",27.55,23.9),
            ("shells",5.55,24.45), ("bullets",6.5,20.55), ("rinds",8.75,27.6),
            ("bottle_launcher",7.15,22.20), ("rocket_ammo",20.65,15.18), ("rocket_ammo",30.45,9.45),
            ("rifle",38.82,18.45), ("rifle_ammo",39.40,18.86), ("bullets",37.45,26.7),
            ("shells",20.4,18.7), ("rinds",23.1,18.5), ("shells",22.45,13.8),
            ("rifle_ammo",19.25,11.75), ("beer",26.65,15.75), ("shells",33.3,10.1),
            ("dynamite",3.20,24.26), ("beer",2.65,22.75),
            ("arm_ammo",30.55,15.55), ("moonshine",29.55,14.55),
            ("rinds",40.45,13.65), ("rifle_ammo",38.64,13.65),
        ]
        self.enemies = [
            ("coot", 13.7,23.9), ("barker", 31.0,23.35), ("billy", 17.45,20.55),
            ("billy", 8.4,26.55), ("coot", 5.55,21.75), ("crawler", 6.6,27.55),
            ("clone", 35.75,18.65), ("coot", 39.8,24.85), ("skeeter", 37.7,19.6),
            ("alien", 18.5,10.5), ("coot", 26.6,15.55),
            ("barker", 15.55,14.1), ("alien", 26.8,9.65), ("crawler", 19.5,8.65),
            ("rudy",22.2,8.45),
        ]
        self.enemy_ids = ("midway-coot","midway-barker","midway-billy","concession-billy",
                          "concession-coot","concession-crawler","games-clone","games-coot",
                          "games-skeeter","pavilion-guard","pavilion-coot","wave-barker",
                          "wave-guard","wave-crawler","show-ringmaster")
        self.v2_new_enemies = frozenset({"show-ringmaster"})
        self.patrols = {
            0: ((12.8,22.1),(15.0,23.15),(13.7,23.9)),
            1: ((31.1,24.5),(31.0,23.35)),
            3: ((8.45,27.65),(8.4,26.55)),
            6: ((35.1,18.6),(35.75,18.65)),
            8: ((37.75,20.3),(37.7,19.6)),
            10: ((25.65,15.55),(26.6,15.55)),
        }
        self.reinforcements = (11,12,13,14)
        self.boss_decoys = ((17.25,11.98),(25.95,10.20))
        self.distant_cues = ((25.6,30.1,"distant_fair_motif"),
                             (17.2,24.0,"distant_fair_rattle"),
                             (39.3,17.4,"distant_fair_generator"),
                             (22.65,10.55,"distant_fair_pa"))
        wing.install(self)
        from county_detail import install
        install(self,"fair")


class BlackwaterMill(TileMap):
    def __init__(self):
        from campaign import Billboard, Extraction, Station, return_marker
        from county_wings import mill_wing

        super().__init__(72, 47)
        self.sky = "mill_sky"
        self.tints = np.asarray(((.96,1.01,1.07), (.89,1.08,1.02), (.98,1.05,.95),
                                 (.88,1.01,1.06), (1.10,1.01,.85), (.96,1.02,1.07)),
                                dtype=np.float32)
        room, wall, door = self.room, self.wall, self.door

        room(13, 27, 32, 36, "mill_grit", 0, light=.94)
        room(19, 36, 23, 38, "mill_grit", 0, light=1.05)
        room(16,37,19,38,"mill_grit",0,light=1.02)
        wall(16,39,23,39,"stockyard",.54)
        self.return_gate = Portal("hub",21.5,36.56,3.45,-1)
        self.return_gate.paint_threshold(self.floor)
        room(8, 19, 15, 31, "mill_grit", 2, light=.99)
        room(30, 18, 38, 30, "mill_grit", 3, light=.97)
        room(16, 17, 29, 27, "mill_water", 1, light=.93)
        room(15, 21, 15, 25, "mill_water", 1, light=.91)
        room(30, 21, 30, 26, "mill_water", 1, light=.91)
        self.ground[self.floor == TILE["mill_water"]] = -.16
        room(17, 23, 19, 25, "mill_grit", 1, light=1.01)
        room(25, 20, 27, 21, "mill_grit", 1, light=.97)
        room(27,22,28,23,"mill_grit",1,light=1.0)
        self.ground[23:26,17:20] = -.03
        self.ground[20:22,25:28] = -.03
        self.ground[22:24,27:29] = -.035
        wall(17, 18, 18, 22, "mill_log", .92)
        wall(26, 24, 28, 25, "mill_log", .74)
        wall(11, 25, 12, 27, "mill_log", .83)
        wall(33, 21, 34, 23, "mill_log", 1.12)
        wall(35, 27, 36, 28, "mill_tin", 2.37)

        # Banks reach their isolation controls without entering the pond.
        room(8, 13, 13, 20, "mill_grit", 2, light=.98)
        room(8, 14, 11, 17, "mill_oil", 2, 2.15, 1.01, "mill_tin")
        wall(8, 13, 10, 13, "mill_tin", 2.33)
        room(5, 16, 6, 18, "porch", 2, 2.08, .87)
        door(7, 16, 2, vertical=True, secret=True)
        room(33, 13, 38, 21, "mill_grit", 3, light=.92)
        room(35, 16, 38, 19, "mill_oil", 3, 2.19, .98, "mill_tin")
        room(39, 23, 41, 26, "mill_grit", 3, light=.90)
        door(38, 25, 3, vertical=True, secret=True)
        wall(38, 22, 38, 24, "mill_tin", 1.75)
        wall(38, 26, 38, 27, "mill_tin", 1.75)
        # The log cache is found by following the overflow channel from the
        # east bank. The rusted panel only opens as a shortcut from the inside.
        room(37,28,40,28,"mill_water",3,light=.91)
        room(39,27,40,27,"mill_water",3,light=.89)
        self.ground[27:29,38:41] = -.13
        self.discovery_rooms = {(38,25):(39,23,41,26)}

        # Cutting shed is split by a static saw bed. Opening the service loop
        # connects both banks above the pond without any room-over-room geometry.
        room(15, 12, 28, 16, "mill_oil", 4, 2.85, .86, "mill_tin")
        room(21, 16, 23, 19, "mill_grit", 4, light=1.02)
        # Maintenance boards connect the east bank to the shed above the pond.
        # The higher service door is still the quickest way between controls.
        room(29,16,31,16,"porch",4,light=.88)
        room(29,17,31,17,"porch",3,light=.90)
        self.ground[16,29:32] = 0.
        self.ground[17,29:32] = 0.
        self.ground[17:20,21:24] = -.06
        room(11, 12, 14, 15, "porch", 2, light=.94)
        room(29, 12, 35, 15, "porch", 3, light=.97)
        wall(14,12,14,15,"mill_tin",2.2)
        wall(29,12,29,15,"mill_tin",2.2)
        door(14, 13, 2, vertical=True, texture="mill_tin")
        door(29, 13, 3, vertical=True, texture="mill_tin")
        door(23, 11, 4, texture="mill_pump")

        room(19, 6, 29, 10, "mill_oil", 4, 2.28, 1.05, "mill_tin")
        wall(18, 6, 18, 10, "mill_pump", 2.33)
        room(15, 8, 17, 10, "floor_tile", 4, 2.1, .86)
        door(18, 9, 4, vertical=True, secret=True)
        room(9, 2, 35, 4, "mill_grit", 5, light=1.03)
        room(12, 4, 18, 6, "mill_grit", 5, light=.98)
        room(26, 4, 33, 6, "mill_grit", 5, light=1.00)
        wall(18,6,18,6,"mill_pump",2.33)
        wall(30,6,30,6,"mill_pump",2.33)
        wall(19,5,29,5,"mill_pump",2.43)
        door(20, 5, 5, texture="mill_pump")
        door(28, 5, 5, texture="mill_pump")
        # Leave a real horizontal sight slot toward the cutter yard. The base
        # and lintel share the original solid footprint for player collision.
        room(24,5,24,5,"mill_oil",4,2.28,.84,"mill_tin")
        wall(12, 1, 16, 1, "mill_log", 1.52)
        wall(32, 1, 35, 1, "mill_tin", 1.80)
        self.objective_side_tasks = ("brake",)
        self.v2_implied_tasks = {"relay":("brake",)}
        self.controlled_doors = frozenset({(14,13), (29,13), (23,11), (20,5), (28,5),(38,25)})
        self.door_ids = {(7,16):"dry-alcove", (38,25):"log-cache", (14,13):"west-service-loop",
                         (29,13):"east-service-loop", (23,11):"pump-entry", (18,9):"pump-cache",
                         (20,5):"apron-west", (28,5):"apron-east"}
        wing = mill_wing(self)

        self.fixtures = (
            Fixture(17.5, 29.0, 19.2, 29.64, .71, "mill_log", "mill_oil"),
            Fixture(25.3, 31.05, 27.4, 31.55, .64, "mill_log", "mill_oil"),
            Fixture(10.7, 21.2, 11.22, 23.24, .58, "mill_tin", "mill_grit"),
            Fixture(31.75, 24.4, 32.35, 26.50, .83, "mill_log", "mill_oil"),
            Fixture(29.63,16.02,30.85,16.30,.58,"mill_log","mill_oil"),
            Fixture(16.45, 13.15, 20.35, 14.15, .91, "mill_tin", "mill_oil"),
            Fixture(24.40, 14.30, 26.95, 15.20, .72, "mill_log", "mill_oil"),
            Fixture(19.45, 7.35, 21.20, 7.95, .85, "mill_pump", "mill_oil"),
            Fixture(25.55, 8.85, 27.85, 9.50, .75, "mill_pump", "mill_oil"),
            Fixture(24.0,5.0,25.0,6.0,.83,"mill_pump","mill_oil"),
            Fixture(24.0,5.0,25.0,6.0,2.43,"mill_pump",base=1.24),
            Fixture(14.1, 4.1, 16.35, 4.65, .76, "mill_log", "mill_oil"),
            # Distinguish the high north stack from the low lateral cutter lanes.
            Fixture(23.30, 2.35, 25.3, 3.13, 1.21, "mill_log", "mill_oil"),
            Fixture(29.1, 3.8, 30.62, 4.45, .74, "mill_tin", "mill_oil"),
        )
        self.fixtures += self.return_gate.posts("mill_tin")+wing.fixtures
        self.collision_volumes = self.fixtures
        for x,y,power,size,area in (
            (21.5,31.4,.26,4,0), (9.4,16.1,.38,4,2), (37.0,17.4,.30,3,3),
            (22.6,15.6,.30,4,4), (24.0,7.3,.32,4,4), (31.65,3.4,.32,4,5),
        ):
            self.light_pool(x,y,power,size,area)
        walls = self.wall_segments()
        walls.extend(self.return_gate.frame(0,"mill_tin"))
        self.finish_geometry(walls)
        self.stations = (
            Station("west",9.55,15.10,"ISOLATE WEST FEED","WEST FEED ISOLATED. SERVICE GATE OPEN.",
                    opens=((14,13),),sectors=(2,),cue="mill_isolate"),
            Station("east",61.45,31.45,"STRIKE THE KILN BELT RELEASE",
                    "KILN STOPPED. THE RETURN SHUTTER IS OPEN.",
                    opens=((29,13),(42,15)),sectors=(3,7),cue="brake_ratchet",action="strike"),
            Station("relay",24.3,6.7,"SHUT DOWN THE MILL RELAY",
                    "SPLINTER FOREMAN! WATCH THE CUT MARKS.",
                    requires=("west","east","brake"), opens=((20,5),(28,5)), sectors=(4,5),cue="mill_trip"),
            Station("brake",24.15,14.1,"RELEASE THE LOG CARRIAGE BRAKE",
                    "CARRIAGE STOPPED. PUMP HOUSE ACCESS OPEN.",requires=("west","east"),
                    opens=((23,11),),sectors=(4,),cue="brake_ratchet"),
        )
        self.extraction = Extraction(33.75,3.15,"USE EXTRACTION CONTROL","relay")
        self.control_name = "SLUICE FEED AND DRY-KILN BELT"
        self.billboards = (
            return_marker(self.return_gate),
            Billboard(23.9,30.50,"mill_entry",1.36,plane=0.),
            Billboard(21.62,16.25,"mill_shed",.93,1.6,plane=0.),
            Billboard(20.25,16.72,"mill_saw",1.42,.008,plane=0.),
            Billboard(23.85,11.23,"mill_pump_sign",.90,1.28,plane=0.),
            Billboard(29.67,16.31,"county_mill_bypass",.27,.59,plane=0.),
            Billboard(9.55,14.9,"mill_control",1.12,signal="west",glow=True),
            Billboard(37.58,18.33,"wing_mill_sort",.87,.56,plane=math.pi/2),
            Billboard(24.3,6.50,"mill_relay",1.54,signal="relay",glow=True),
            Billboard(35.96,3.50,"mill_exit",.78,.71,signal="exit",plane=math.pi/2),
            Billboard(19.1,8.74,"mill_notice",.95,.38,plane=1.57),
            Billboard(13.25,28.30,"mill_west_arrow",1.39,plane=.37,back="wayfinding_back"),
            Billboard(30.6,28.05,"mill_east_arrow",1.39,plane=-.39,back="wayfinding_back"),
            Billboard(21.8,19.8,"mill_pilings",1.77),
            Billboard(15.6,26.0,"mill_pilings",1.77),
            Billboard(28.35,17.6,"mill_pilings",1.7),
            Billboard(20.4,14.35,"mill_saw",1.15,.008,plane=0.),
            Billboard(24.15,13.89,"mill_brake",.98,signal="brake",plane=0.),
            Billboard(17.1,13.65,"mill_timber",.53,.93),
            Billboard(26.6,14.65,"mill_timber",.60,.73),
            Billboard(19.2,23.0,"mill_log_ends",.72),
            Billboard(34.5,24.3,"mill_log_ends",1.15),
            Billboard(37.67,27.27,"mill_overflow",.64,.43,plane=.26),
            Billboard(24.9,15.45,"mill_pylon",2.1,glow=True),
            Billboard(15.15,20.15,"mill_pylon",2.1,glow=True),
            Billboard(30.85,20.15,"mill_pylon",2.1,glow=True),
        )
        self.props = [("crate",13.3,32.0),("barrel",29.65,33.20),("crate",37.70,20.35),
                      ("barrel",13.60,17.8),("crate",27.7,7.55),("crate",30.8,5.45)]
        self.props += [("crate",69.5,10.5),("barrel",54.5,12.5),("tire",46.5,44.5),
                       ("reeds",43.5,41.5),("crate",33.5,6.5),("barrel",13.5,36.5),
                       ("tire",9.5,2.5),("reeds",8.5,31.5),("crate",69.5,30.5),
                       ("barrel",69.5,15.5),("tire",66.5,32.5),("reeds",47.5,8.5),
                       ("crate",11.5,12.5),("barrel",8.5,14.5),("tire",67.5,41.5),
                       ("reeds",63.5,17.5),("crate",50.5,34.5),("barrel",32.5,36.5),
                       ("tire",12.5,6.5),("reeds",69.5,21.5),("crate",41.5,23.5),
                       ("barrel",38.5,30.5),("tire",16.5,38.5),("reeds",64.5,44.5)]
        self.fuel_drums = ((12.7,24.35), (35.30,24.2), (17.90,3.55))
        self.pickups = [
            ("rinds",20.76,34.05),("shotgun",21.70,33.83),("shells",22.33,33.98),
            ("bullets",22.72,34.45),("shells",15.25,28.46),("rifle_ammo",29.6,29.35),
            ("beer",9.55,19.7),("shells",12.75,15.57),("bullets",10.25,16.95),
            ("rifle_ammo",36.5,18.3),("shells",35.65,20.2),
            ("rifle",18.6,24.45),("rifle_ammo",18.9,24.8),("rinds",25.8,20.65),
            ("riveter",22.60,15.65),("rivet_ammo",24.52,8.15),("rivet_ammo",27.7,3.5),
            ("shells",22.2,15.1),("bullets",24.75,13.45),("rinds",27.2,15.9),
            ("arm_ammo",26.35,7.9),("shells",23.3,7.55),("beer",29.55,6.65),
            ("moonshine",5.6,17.3),("saw_ammo",6.35,17.9),
            ("dynamite",40.1,25.2),("shells",39.45,24.7),
            ("rinds",15.6,9.4),("rifle_ammo",16.7,9.8),
        ]
        self.enemies = [
            ("clone",16.45,27.8),("coot",28.2,29.1),("millhand",13.95,21.85),
            ("coot",8.65,17.6),("skeeter",15.4,23.5),("lantern",28.85,20.2),
            ("billy",36.7,24.6),("lantern",32.1,19.25),("clone",34.5,16.45),
            ("alien",17.6,15.55),("billy",26.8,12.62),("coot",20.7,9.5),
            ("alien",12.7,3.6),("millhand",17.1,5.2),("billy",31.6,3.25),("lantern",27.3,2.75),
            ("foreman",21.25,3.15),
        ]
        self.enemy_ids = ("yard-clone","yard-coot","west-millhand","west-coot","pond-skeeter",
                          "pond-lantern","east-billy","east-lantern","east-clone","shed-guard",
                          "shed-billy","pump-coot","wave-guard","wave-millhand","wave-billy","wave-lantern",
                          "loading-foreman")
        self.v2_new_enemies = frozenset({"loading-foreman"})
        self.patrols = {
            0: ((15.45,26.1),(16.45,27.8)),
            2: ((13.85,20.9),(13.95,21.85)),
            4: ((15.75,24.5),(15.4,23.5)),
            7: ((31.4,19.25),(32.1,19.25)),
            8: ((34.1,17.15),(34.5,16.45)),
            10: ((27.5,12.6),(26.8,12.62)),
        }
        self.reinforcements = (12,13,14,15,16)
        self.distant_cues = ((13.4,23.5,"distant_mill_timber"),
                             (25.2,8.3,"distant_mill_pump"))
        wing.install(self)
        from county_detail import install
        install(self,"sawmill")
