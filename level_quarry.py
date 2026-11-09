"""Stillwater Cut's weigh road, stepped limestone benches and bootleg works."""
import numpy as np

from level_hickston import Fixture, Portal, TILE, TileMap


class StillwaterCut(TileMap):
    def __init__(self):
        from campaign import Billboard, Extraction, Station, return_marker
        from county_wings import quarry_wing

        super().__init__(84,46)
        self.sky = "quarry_sky"
        self.tints = np.asarray(((1.07,1.01,.93),(.98,1.02,1.04),(1.08,1.02,.93),
                                 (1.10,.99,.88),(.99,1.02,1.02),(1.08,1.02,.96)),
                                dtype=np.float32)
        room,wall,door = self.room,self.wall,self.door

        # Truck scale and its disused switchback. The return lane has a short apron.
        room(21,34,34,41,"quarry_dust",0,light=1.09)
        room(25,41,29,42,"gravel",0,light=1.04)
        room(29,41,32,42,"quarry_dust",0,light=1.03)
        wall(25,43,32,43,"quarry_face",.46)
        self.return_gate = Portal("hub",27.5,40.58,3.5,-1)
        self.return_gate.paint_threshold(self.floor)
        room(21,34,24,37,"quarry_shed",0,2.12,1.02,"quarry_iron")
        wall(24,35,24,36,"quarry_iron",2.13)
        room(18,35,19,38,"quarry_shed",0,1.74,.86)
        door(20,36,0,vertical=True,secret=True)
        wall(31,39,34,39,"quarry_face",.52)

        # The cut yard follows an old haul bend. Bench layers change elevation
        # in short, walkable steps and frame the condenser silhouette.
        room(16,24,37,34,"quarry_dust",1,light=1.13)
        room(23,21,32,24,"tracks",1,light=1.14)
        room(24,20,29,21,"quarry_dust",1,light=1.12)
        room(22,25,27,27,"quarry_face",1,light=1.12)
        self.ground[25:28,22:28] = .17
        wall(17,23,22,23,"quarry_face",2.65)
        wall(15,27,15,30,"quarry_face",1.13)
        wall(33,24,35,24,"quarry_face",1.20)
        wall(36,31,37,34,"quarry_face",2.39)
        wall(17,34,20,34,"quarry_face",2.88)

        # Limestone shed: the south entry climbs to the breaker; the back
        # shutter gives a straight walk back to the middle once power is cut.
        room(11,26,16,29,"quarry_dust",2,light=1.06)
        room(11,17,16,27,"quarry_face",2,light=1.07)
        room(8,13,16,20,"quarry_shed",2,2.32,.97,"quarry_iron")
        room(16,15,21,18,"quarry_dust",2,light=1.06)
        room(19,18,21,22,"quarry_dust",2,light=1.04)
        room(21,21,23,22,"quarry_dust",1,light=1.08)
        wall(16,14,16,17,"quarry_iron",2.43)
        wall(10,19,12,19,"quarry_shed",1.12)
        wall(11,22,12,23,"quarry_face",.62)
        wall(19,18,21,18,"quarry_iron",2.31)
        door(19,18,2)
        room(5,14,6,17,"quarry_shed",2,2.,.86)
        door(7,15,2,vertical=True,secret=True,blast_only=True,texture="powder_panel")
        wall(7,17,7,19,"quarry_face",2.25)

        # Condenser yard: a low spill trench bends past two horizontal vats.
        room(35,25,45,28,"quarry_dust",3,light=1.01)
        room(39,15,47,27,"quarry_dust",3,light=1.08)
        room(41,15,47,19,"quarry_shed",3,2.14,.96,"quarry_iron")
        room(34,17,41,20,"quarry_dust",3,light=1.02)
        room(33,20,35,24,"quarry_dust",3,light=1.09)
        self.ground[21:25,41:45] = -.15
        wall(43,21,44,22,"quarry_copper",.96)
        wall(39,22,39,24,"quarry_face",.77)
        wall(33,20,36,20,"quarry_iron",2.20)
        door(35,20,3)
        room(49,16,51,19,"quarry_shed",3,2.,.92)
        door(48,17,3,vertical=True,secret=True)

        # Bottling line: clear aisle between low benches, then two chutes
        # opening to a court with offset limestone and sheet-metal cover.
        room(21,10,34,18,"quarry_shed",4,2.60,1.02,"quarry_iron")
        wall(22,19,31,19,"quarry_iron",2.76)
        door(26,19,4,texture="quarry_copper")
        wall(20,10,20,16,"quarry_face",2.84)
        wall(35,10,35,17,"quarry_face",2.66)
        room(15,3,39,8,"quarry_dust",5,light=1.09)
        room(19,8,35,9,"quarry_dust",5,light=1.09)
        wall(20,9,34,9,"quarry_iron",2.16)
        door(23,9,5,texture="quarry_iron")
        door(31,9,5,texture="quarry_iron")
        wall(15,1,39,2,"quarry_face",3.6)
        wall(14,3,14,8,"quarry_face",2.91)
        wall(40,3,40,8,"quarry_face",3.06)
        self.access_doors = {(26,19):("stone","stills")}
        self.controlled_doors = frozenset({(20,36),(19,18),(35,20),(26,19),(23,9),(31,9)})
        self.door_ids = {(20,36):"scale-cache",(7,15):"cut-cache",(48,17):"condensate-stash",
                         (19,18):"bench-shutter",(35,20):"stills-shutter",
                         (26,19):"bottling-entry",(23,9):"court-west",(31,9):"court-east"}
        wing = quarry_wing(self)

        self.fixtures = (
            Fixture(21.20,35.28,22.15,36.35,.82,"quarry_shed"),
            Fixture(28.7,32.0,30.55,32.72,.76,"quarry_face"),
            Fixture(18.5,25.75,20.30,26.6,.69,"quarry_face"),
            Fixture(30.2,25.40,31.60,27.05,.77,"quarry_iron"),
            Fixture(9.35,14.12,10.2,15.40,.78,"quarry_iron"),
            Fixture(40.9,22.25,41.48,25.05,.69,"quarry_copper"),
            Fixture(44.9,18.25,45.52,19.85,.78,"quarry_copper"),
            Fixture(22.0,13.3,24.65,14.16,.74,"quarry_shed"),
            Fixture(29.6,13.9,32.85,14.80,.74,"quarry_copper"),
            Fixture(20.5,5.5,22.6,6.38,.89,"quarry_face"),
            Fixture(25.0,4.05,27.4,4.88,.72,"quarry_iron"),
            # The loading pump screens the east bay; its perimeter still leaves
            # a route around both ends during the Baron's steam sweep.
            Fixture(29.7,6.37,31.55,7.27,1.19,"quarry_copper"),
            Fixture(34.40,5.05,36.2,5.90,.80,"quarry_face"),
        ) + self.return_gate.posts("quarry_iron") + wing.fixtures
        self.collision_volumes = self.fixtures
        for x,y,gain,radius,sector in (
            (26.5,34.5,.20,3,0),(26.6,21.5,.22,4,1),(12.3,14.5,.34,3,2),
            (45.6,16.9,.29,4,3),(28.2,12.3,.37,4,4),(33.1,5.2,.29,4,5),
        ):
            self.light_pool(x,y,gain,radius,sector)
        walls = self.wall_segments()
        walls.extend(self.return_gate.frame(0,"quarry_iron"))
        walls.extend((
            (33.7,23.,28.6,23.,TILE["quarry_copper"],1.06,2.58,2.91,1),
            (33.7,23.,37.2,21.4,TILE["quarry_copper"],.93,2.58,2.91,1),
            (33.4,18.8,22.4,18.8,TILE["quarry_iron"],1.10,2.12,2.68,4),
        ))
        self.finish_geometry(walls)
        self.stations = (
            Station("stone",12.65,14.45,"DISENGAGE THE CUTTING FEED",
                    "CUTTING FEED OFF. BENCH SHUTTER OPEN.",opens=((19,18),),sectors=(2,),cue="mill_isolate"),
            Station("stills",71.7,17.19,"DIVERT THE COPPER CONDENSER",
                    "PRESSURE DIVERTED. TAKE THE RECOVERY GATE.",
                    opens=((35,20),(52,14)),sectors=(3,8),cue="pressure_vent",action="crank"),
            Station("bottling",27.7,11.02,"VENT THE BOTTLING RELAY",
                    "COPPER BARON! USE THE RELIEF VALVES.",
                    requires=("stone","stills"),opens=((23,9),(31,9)),sectors=(4,5),cue="mill_trip"),
            Station("relief-west",19.4,7.75,"OPEN WEST RELIEF VALVE",
                    "RELIEF OPEN. FEWER OUTLETS UNDER PRESSURE.",requires=("bottling",),cue="pressure_vent"),
            Station("relief-east",34.15,7.64,"OPEN EAST RELIEF VALVE",
                    "RELIEF OPEN. FEWER OUTLETS UNDER PRESSURE.",requires=("bottling",),cue="pressure_vent"),
            Station("scale-drawer",21.95,36.75,"SLIDE THE SCALE DRAWER",
                    "CACHE UNLATCHED. THE SCALE HOUSE KEEPS TWO SETS OF BOOKS.",
                    opens=((20,36),),cue="secret_slide",hidden=True),
        )
        self.extraction = Extraction(37.0,3.6,"SIGN THE LOAD TICKET","bottling")
        self.control_name = "QUARRY FEEDS ISOLATED"
        self.billboards = (
            return_marker(self.return_gate),
            Billboard(26.0,35.85,"quarry_scale",1.08,.35,plane=0.),
            Billboard(34.10,21.07,"quarry_tower",3.35,.05,plane=0.),
            Billboard(16.65,25.5,"quarry_cut_arrow",1.34,plane=.40,back="wayfinding_back"),
            Billboard(35.6,25.5,"quarry_stills_arrow",1.34,plane=-.39,back="wayfinding_back"),
            Billboard(26.5,19.43,"quarry_bottling",.72,1.82,plane=0.),
            Billboard(12.65,14.23,"mill_control",1.10,signal="stone",glow=True,plane=0.),
            Billboard(46.50,16.25,"wing_quarry_cut",.82,.62,plane=0.),
            Billboard(27.7,10.8,"mill_relay",1.46,signal="bottling",glow=True,plane=0.),
            Billboard(37.0,3.36,"mill_exit",1.42,signal="exit",glow=True,plane=0.),
            Billboard(19.4,7.5,"mill_control",.76,signal="relief-west",plane=0.),
            Billboard(34.15,7.4,"mill_control",.76,signal="relief-east",plane=0.),
            Billboard(47.33,17.5,"quarry_safety",.84,.26,plane=-1.57),
            Billboard(20.94,36.7,"quarry_ledger",.64,.82,plane=-1.57),
            Billboard(7.75,15.4,"quarry_blast",.88,.39,plane=-1.57),
            Billboard(26.2,13.85,"quarry_bottles",.45,.04),
            Billboard(33.3,15.75,"quarry_bottles",.44),
            Billboard(18.3,31.0,"mill_pylon",2.4,glow=True),
            Billboard(27.9,20.5,"mill_pylon",2.4,glow=True),
            Billboard(41.7,19.2,"mill_pylon",2.2,glow=True),
        )
        self.props = [("barrel",31.35,34.52),("crate",25.6,36.7),("barrel",31.36,17.2),
                      ("crate",10.6,14.05),("barrel",46.35,15.5),("crate",23.0,6.7)]
        self.props += [("barrel",59.5,12.5),("crate",76.5,17.5),("tire",76.5,14.5),
                       ("barrel",62.5,10.5),("crate",37.5,30.5),("tire",17.5,15.5),
                       ("barrel",15.5,8.5),("crate",11.5,29.5),("tire",81.5,37.5),
                       ("barrel",81.5,27.5),("crate",81.5,22.5),("tire",76.5,42.5),
                       ("barrel",53.5,34.5),("crate",48.5,34.5),("tire",47.5,13.5),
                       ("barrel",39.5,15.5),("crate",34.5,40.5),("tire",76.5,10.5),
                       ("barrel",53.5,12.5),("crate",39.5,8.5),("tire",39.5,3.5),
                       ("barrel",21.5,10.5),("crate",8.5,20.5),("tire",48.5,43.5)]
        self.fuel_drums = ((18.4,27.85),(41.8,26.25),(34.2,4.07),(8.65,15.53))
        self.pickups = [
            ("rinds",25.4,38.5),("shotgun",26.3,38.5),("shells",27.2,38.5),("bullets",28.1,38.5),
            ("pressure_gun",26.7,34.6),("pressure_ammo",13.2,15.25),("pressure_ammo",44.1,17.4),
            ("pressure_ammo",24.65,11.55),
            ("rifle",24.85,30.45),("rifle_ammo",25.45,30.44),("shells",20.35,29.9),
            ("rinds",13.6,26.5),("shells",12.4,18.4),("rifle_ammo",13.6,16.55),
            ("beer",38.9,26.1),("shells",44.75,25.55),("bullets",41.0,20.55),
            ("rinds",34.6,21.65),("shells",25.15,17.7),("beer",27.1,15.85),
            ("rifle_ammo",30.75,15.4),("shells",25.7,11.7),("rinds",29.55,11.35),
            ("rifle_ammo",23.5,7.86),("shells",31.8,8.22),("rinds",35.55,7.15),
            ("moonshine",19.3,37.16),("dynamite",18.6,35.8),("rivet_ammo",6.3,15.26),
            ("rinds",5.8,16.7),("arm_ammo",50.4,18.2),("beer",49.6,16.25),
        ]
        self.enemies = [
            ("coot",20.3,30.45),("clone",31.8,29.65),("boilerback",12.1,25.15),
            ("alien",11.65,16.24),("coot",15.25,13.75),("chalk_spitter",39.9,25.8),
            ("billy",46.8,21.45),("coot",41.9,16.8),("boilerback",23.6,12.05),
            ("billy",31.9,11.85),("chalk_spitter",33.45,15.55),("alien",18.25,5.45),
            ("chalk_spitter",34.9,6.75),("baron",30.5,3.65),("boilerback",24.1,4.9),
        ]
        self.enemy_ids = ("yard-coot","yard-clone","cut-sentinel","cut-guard","shed-coot",
                          "spill-skeeter","vat-sentinel","stills-coot","line-guard","line-billy",
                          "line-coot","court-guard","court-clone","court-center","court-billy")
        self.patrols = {
            0:((20.1,31.3),(20.3,30.45)),1:((30.8,30.3),(31.8,29.65)),
            2:((13.25,25.4),(12.1,25.15)),4:((14.15,14.35),(15.25,13.75)),
            5:((40.05,26.65),(39.9,25.8)),6:((46.15,22.4),(46.8,21.45)),
            10:((33.45,16.5),(33.45,15.55)),
        }
        self.reinforcements = (11,12,13,14)
        self.pressure_ports = ((21.65,7.65),(25.85,6.8),(32.1,4.1),(36.7,6.4))
        self.distant_cues = ((35.1,23.1,"distant_quarry_pipe"),(27.7,11.02,"distant_quarry_bottler"))
        wing.install(self)
        from county_detail import install
        install(self,"quarry")
