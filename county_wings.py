"""Authored chapter districts. Original map coordinates and entity IDs stay stable."""
from dataclasses import dataclass
import math

import numpy as np

from campaign import Billboard, Station
from level_hickston import Fixture
from scenery import Reactive


@dataclass(frozen=True)
class Wing:
    fixtures: tuple
    boards: tuple
    props: tuple
    pickups: tuple
    enemies: tuple
    stations: tuple = ()

    def install(self, world):
        world.billboards += self.boards
        world.props.extend(self.props)
        world.pickups.extend(self.pickups)
        world.extension_enemies = tuple(key for key, *_ in self.enemies)
        world.enemy_ids += world.extension_enemies
        world.enemies.extend((kind,x,y) for _,kind,x,y in self.enemies)
        world.extension_pickups = self.pickups
        world.stations += self.stations


def shortcut(world, x, y, district, name, texture, **options):
    world.door(x,y,district,texture=texture,**options)
    world.door_ids[x,y] = name
    world.extension_doors += ((x,y),)
    world.controlled_doors |= {(x,y)}


def fair_wing(world):
    r,w = world.room,world.wall
    world.tints = np.vstack((world.tints,((1.05,.93,.90),(.94,.96,1.08),(1.08,.94,.85)))).astype(np.float32)
    r(40,24,47,27,"fair_gravel",6,light=1.00)
    r(43,23,54,33,"fair_gravel",6,light=1.05)
    r(47,31,62,39,"tracks",6,light=.91)
    r(51,37,65,41,"fair_gravel",6,light=.98)
    r(60,28,66,39,"fair_gravel",6,light=.99)
    r(52,20,66,32,"porch",7,light=1.04)
    r(49,14,56,23,"fair_gravel",7,light=.95)
    r(56,12,65,20,"fair_gravel",7,light=1.01)
    r(60,7,66,14,"fair_gravel",8,light=.90)
    r(54,7,59,12,"floor_tile",8,2.25,1.08,"joists")
    r(45,14,49,22,"fair_gravel",7,light=.95)
    r(40,17,45,19,"porch",7,light=1.03)
    r(55,14,60,19,"porch",7,2.38,1.02,"joists")
    r(45,29,50,32,"floor_tile",6,2.12,.94,"fair_iron")
    w(44,29,44,32,"fair_booth",2.38)
    w(45,33,49,33,"fair_booth",2.38)
    w(45,28,47,28,"fair_booth",2.32)
    w(53,22,53,24,"fair_booth",1.81)
    w(57,24,59,25,"fair_iron",.88)
    w(61,29,62,34,"fair_booth",2.25)
    w(50,34,53,35,"fair_booth",1.76)
    w(58,36,61,37,"fair_prize",1.05)
    w(56,15,56,17,"fair_booth",2.42)
    w(60,14,60,17,"fair_iron",2.42)
    w(54,7,58,7,"fair_booth",2.39)
    w(54,8,54,11,"fair_booth",2.39)
    w(56,12,59,12,"fair_booth",2.39)
    w(65,17,65,18,"fair_prize",1.66)
    w(63,21,66,21,"fair_iron",2.05)
    w(43,16,43,20,"fair_iron",2.12)
    r(43,18,43,18,"porch",7,light=.98)
    shortcut(world,43,18,7,"backstage-pa-shortcut","fair_iron",vertical=True)
    shortcut(world,53,23,7,"sideshow-panel-flank","fair_iron",vertical=True)
    world.scenery = (
        Reactive("fair-soda-case","bottles",16.15,29.1,.41,.09),
        Reactive("fair-raffle-tins","cans",48.16,30.72,.32,.56),
        Reactive("fair-prize-counterweight","prize",52.86,23.5,1.08,.12,.32,((53,23),)),
    )
    world.light_pool(58.75,10.1,.29,4,8)
    world.light_pool(47.25,30.2,.30,4,6)
    world.light_pool(63.3,23.5,.23,4,7)
    return Wing(
        (
            Fixture(45.55,30.95,48.4,31.35,.78,"counter"),
            Fixture(47.4,26.35,49.1,27.19,.66,"fair_prize"),
            Fixture(62.32,24.05,64.2,24.8,.63,"fair_booth"),
            Fixture(57.3,17.9,58.7,18.36,.86,"fair_iron"),
            Fixture(55.13,8.1,56.42,8.55,.84,"counter"),
            Fixture(52.5,39.1,54.7,39.77,.69,"fair_prize"),
            Fixture(63.62,35.2,65.17,35.66,.88,"fair_booth"),
        ),
        (
            Billboard(42.74,25.9,"wing_fair_freight",.80,1.39,plane=math.pi/2),
            Billboard(47.45,27.975,"wing_fair_receipts",.60,1.06,plane=math.pi),
            Billboard(52.60,22.63,"wing_fair_sideshow",.83,.82,plane=-math.pi/2),
            Billboard(59.14,17.23,"fair_prize_pile",.62),
            Billboard(60.6,30.70,"wing_fair_rope",.78,.16,plane=-math.pi/2),
            Billboard(56.55,8.025,"wing_fair_pa",.65,1.31,signal="broadcast",plane=0.),
            Billboard(58.8,9.78,"fair_relay",1.28,signal="games",plane=0.),
            Billboard(64.0,23.54,"fair_pylon",2.55,glow=True),
            Billboard(63.28,24.821,"wing_fair_double_hog",1.22,.40,plane=0.),
            Billboard(48.84,32.53,"fair_prize_pile",.53,.008),
            Billboard(63.3,37.7,"fair_lost_property",.80,.59,plane=math.pi),
        ),
        (("crate",46.0,30.55),("barrel",55.2,26.5),("crate",62.35,27.50),
         ("tire",60.8,38.3),("crate",64.5,23.9),("crate",54.75,10.8)),
        (("bullets",44.4,25.15),("shells",48.35,28.2),("rinds",52.6,27.9),
         ("bullets",57.3,16.26),("shells",63.3,22.7),("beer",63.3,35.22),
         ("rocket_ammo",55.52,10.64),("rinds",55.7,38.3),("pa_patch",47.84,30.47)),
        (("freight-shooter","bottle_tosser",46.8,24.55),("catwalk-barker","barker",54.7,24.1),
         ("sideshow-crawler","crawler",63.8,25.55),("print-shop-coot","bottle_tosser",58.9,14.82),
         ("pa-stair-clone","clone",63.1,10.7),("raffle-skeeter","skeeter",58.3,34.55)),
    )


def mill_wing(world):
    r,w = world.room,world.wall
    world.tints = np.vstack((world.tints,((.94,1.07,1.04),(1.12,1.02,.91),(.91,1.01,1.08)))).astype(np.float32)
    r(38,19,46,21,"mill_grit",6,light=.99)
    r(43,18,57,30,"mill_grit",6,light=.95)
    r(49,26,66,36,"tracks",6,light=.98)
    r(43,30,51,41,"mill_grit",8,light=.91)
    r(46,40,64,44,"mill_grit",8,light=.99)
    r(57,34,67,41,"mill_oil",8,light=.95)
    r(58,21,69,30,"mill_grit",7,light=.95)
    r(54,15,67,22,"mill_grit",7,light=1.0)
    r(43,13,53,18,"mill_grit",7,light=.94)
    r(38,14,43,16,"porch",7,light=.92)
    r(59,28,65,33,"porch",7,2.36,.98,"mill_tin")
    r(58,16,64,20,"porch",7,2.65,.90,"joists")
    r(47,36,55,39,"porch",8,2.27,.86,"mill_tin")
    r(47,8,62,12,"mill_grit",8,light=.96)
    r(59,9,69,15,"tracks",8,light=.94)
    r(64,9,68,12,"porch",8,2.06,.93,"mill_tin")
    r(44,33,46,36,"mill_water",8,light=.91)
    world.ground[33:37,44:47] = -.14
    w(42,22,42,29,"mill_tin",2.08)
    w(46,21,50,22,"mill_log",.94)
    w(53,25,54,30,"mill_log",1.23)
    w(57,29,58,32,"mill_tin",1.98)
    w(51,33,55,34,"mill_log",1.11)
    w(56,36,57,41,"mill_tin",1.41)
    w(60,39,62,40,"mill_log",1.24)
    w(49,35,55,35,"mill_tin",2.54)
    w(47,36,47,38,"mill_tin",2.40)
    w(59,27,62,27,"mill_tin",2.28)
    w(65,29,65,32,"mill_tin",2.40)
    w(59,16,63,16,"mill_tin",2.72)
    w(64,16,64,19,"mill_tin",2.72)
    w(49,13,51,15,"mill_log",1.11)
    w(53,10,55,11,"mill_log",.85)
    w(64,8,68,8,"mill_tin",2.25)
    w(68,9,68,11,"mill_tin",2.25)
    w(42,14,42,16,"mill_tin",2.22)
    shortcut(world,42,15,7,"kiln-return-shutter","mill_tin",vertical=True)
    r(56,38,56,38,"mill_grit",8,light=.96)
    shortcut(world,57,38,8,"dry-stacks-breakout","mill_tin",vertical=True)
    world.scenery = (
        Reactive("mill-leaky-standpipe","pipe",22.3,16.6,.99,.12,.22),
        Reactive("mill-log-scrap","scrap",56.53,38.47,.81,.04,.33,((57,38),)),
        Reactive("mill-drive-belt-release","belt",61.45,31.45,.73,.55,.29,station="east"),
    )
    world.light_pool(62.1,31.2,.36,4,7)
    world.light_pool(60.0,19.2,.27,4,7)
    world.light_pool(49.9,37.2,.26,4,8)
    return Wing(
        (Fixture(47.5,24.4,50.6,25.24,.86,"mill_log","porch"),
         Fixture(46.2,31.12,47.65,32.5,.58,"mill_tin","mill_oil"),
         Fixture(55.35,23.11,56.75,24.37,.73,"mill_log","porch"),
         Fixture(67.2,25.9,68.22,28.6,1.12,"mill_log","mill_oil"),
         Fixture(63.6,28.9,64.67,30.53,.88,"mill_tin","mill_oil"),
         Fixture(59.1,18.02,61.88,18.76,.86,"mill_tin","porch"),
         Fixture(48.2,36.15,50.9,37.03,.73,"mill_log","porch"),
         Fixture(49.9,41.64,52.25,42.47,.63,"mill_log","porch"),
         Fixture(64.6,36.32,66.14,37.1,.70,"mill_log","mill_oil")),
        (Billboard(41.71,19.22,"wing_mill_sort",.80,.72,plane=math.pi),
         Billboard(51.25,25.1,"mill_log_ends",.96,.07),
         Billboard(49.05,24.377,"wing_mill_sort_rollers",.74,.17,plane=math.pi),
         Billboard(58.5,20.3,"wing_mill_kiln",.82,1.34,plane=0.),
         Billboard(60.4,18.5,"mill_timber",.46,.84),
         Billboard(61.45,31.07,"mill_control",1.11,signal="east",plane=0.),
         Billboard(60.56,28.025,"wing_mill_belt",.80,1.20,signal="east",plane=0.),
         Billboard(51.20,36.025,"wing_mill_rain",.69,1.31,plane=0.),
         Billboard(44.75,34.47,"mill_pilings",1.43),
         Billboard(53.15,41.25,"mill_log_ends",.86),
         Billboard(66.4,12.15,"wing_mill_ledger",.71,1.24,plane=0.),
         Billboard(66.34,22.07,"mill_pylon",2.45,glow=True)),
        (("crate",44.8,23.4),("barrel",51.24,30.56),("crate",60.45,32.75),
         ("tire",45.78,39.0),("crate",50.15,38.5),("barrel",66.65,38.0),
         ("crate",65.54,10.91),("barrel",55.5,9.6)),
        (("shells",44.8,20.2),("bullets",48.7,23.2),("rivet_ammo",55.91,32.55),
         ("rinds",62.28,32.1),("shells",66.16,30.24),("beer",54.3,37.25),
         ("rifle_ammo",58.65,17.38),("rinds",53.6,41.62),("beer",66.6,10.7)),
        (("sortyard-millhand","chain_hand",46.6,23.6),("pond-bank-lantern","lantern",51.5,28.0),
         ("drying-lantern","lantern",61.8,21.8),("kiln-hand","millhand",62.75,31.53),
         ("stack-rifle","chain_hand",65.0,35.8),("spill-track-coot","coot",53.1,38.6),
         ("mill-roof-skeeter","skeeter",48.3,17.5)),
    )


def quarry_wing(world):
    r,w = world.room,world.wall
    world.tints = np.vstack((world.tints,((1.08,1.03,.90),(.95,1.04,1.05),(1.12,.98,.82)))).astype(np.float32)
    r(46,22,55,26,"quarry_dust",6,light=1.08)
    r(51,19,69,32,"quarry_dust",6,light=1.14)
    r(59,31,76,42,"quarry_face",7,light=1.06)
    r(48,34,61,43,"quarry_dust",7,light=1.00)
    r(54,29,59,38,"quarry_dust",7,light=1.04)
    r(68,20,77,34,"quarry_dust",7,light=1.11)
    r(76,22,81,37,"quarry_dust",7,light=1.03)
    r(77,29,81,34,"quarry_shed",7,2.29,.96,"quarry_iron")
    r(62,10,76,21,"quarry_dust",8,light=1.05)
    r(53,12,65,19,"tracks",8,light=.98)
    r(47,13,54,15,"quarry_dust",8,light=1.03)
    r(56,14,61,17,"quarry_shed",8,2.26,.94,"quarry_iron")
    r(68,13,74,19,"quarry_shed",8,2.53,.99,"quarry_iron")
    r(71,33,75,39,"quarry_shed",7,2.20,.89,"quarry_iron")
    r(53,35,57,40,"quarry_shed",7,2.15,.92,"quarry_iron")
    r(61,37,65,42,"quarry_dust",7,light=1.00)
    world.ground[39:43,61:66] = .15
    world.ground[40:43,62:65] = .29
    w(49,24,50,26,"quarry_face",1.27)
    w(55,20,56,23,"quarry_face",1.17)
    w(61,26,64,28,"quarry_face",1.12)
    w(65,31,67,34,"quarry_face",1.36)
    w(56,33,58,34,"quarry_face",1.64)
    w(52,35,52,40,"quarry_shed",2.33)
    w(53,35,56,35,"quarry_shed",2.33)
    w(72,33,75,33,"quarry_iron",2.41)
    w(71,34,71,36,"quarry_shed",2.30)
    w(69,14,69,16,"quarry_iron",2.53)
    w(70,12,74,12,"quarry_shed",2.53)
    w(75,14,75,18,"quarry_face",2.56)
    w(79,28,81,28,"quarry_iron",2.54)
    w(81,29,81,33,"quarry_iron",2.54)
    w(57,13,61,13,"quarry_shed",2.42)
    w(49,15,51,15,"quarry_face",2.27)
    w(52,13,52,15,"quarry_iron",2.29)
    shortcut(world,52,14,8,"condenser-recovery-gate","quarry_iron",vertical=True)
    shortcut(world,71,35,7,"wash-bench-latch","quarry_iron",vertical=True)
    world.scenery = (
        Reactive("quarry-tasting-bottles","bottles",26.2,13.91,.39),
        Reactive("quarry-cut-leak","pipe",58.55,24.67,1.09,.05,.24),
        Reactive("quarry-wash-pipe","pipe",73.19,36.83,.88,.15,.24),
    )
    world.light_pool(71.2,17.3,.28,4,8)
    world.light_pool(72.9,36.8,.31,4,7)
    world.light_pool(57.4,15.2,.26,4,8)
    return Wing(
        (Fixture(52.25,23.35,53.58,24.73,.77,"quarry_face","quarry_dust"),
         Fixture(59.30,25.30,60.17,26.89,.96,"quarry_iron","quarry_shed"),
         Fixture(67.2,23.56,68.67,24.45,.73,"quarry_face","quarry_dust"),
         Fixture(70.24,17.3,71.23,18.7,.76,"quarry_copper","quarry_shed"),
         Fixture(73.5,17.68,74.44,18.43,.71,"quarry_iron","quarry_shed"),
         Fixture(54.25,38.22,56.28,39.27,.76,"crate_side","quarry_shed"),
         Fixture(72.45,35.25,74.52,36.16,.88,"quarry_copper","quarry_shed"),
         Fixture(67.78,37.59,69.45,38.58,.69,"quarry_iron","quarry_dust")),
        (Billboard(48.15,22.98,"wing_quarry_cut",.80,.77,plane=math.pi/2),
         Billboard(56.35,22.25,"wing_quarry_danger",.64,1.04,plane=0.),
         Billboard(64.32,27.78,"wing_quarry_terrace",.82,.34,plane=-.53),
         Billboard(74.48,33.55,"wing_quarry_wash",.76,1.30,plane=0.),
         Billboard(72.6,15.7,"quarry_tower",4.35,plane=.17),
         Billboard(72.95,17.39,"wing_quarry_still",1.80,plane=.12),
         Billboard(71.7,16.82,"mill_control",1.26,signal="stills",plane=0.),
         Billboard(69.65,16.78,"wing_quarry_condenser",.73,1.45,signal="stills",plane=0.),
         Billboard(59.72,15.41,"quarry_bottles",.47,.008),
         Billboard(72.86,36.46,"quarry_bottles",.47,.008),
         Billboard(73.42,36.184,"wing_quarry_wash_rack",1.08,.29,plane=0.),
         Billboard(61.8,38.2,"wing_quarry_weight",.61,.42,plane=-.26),
         Billboard(71.05,35.50,"wing_quarry_latch",.48,.64,signal="wash-latch",plane=math.pi/2)),
        (("barrel",51.55,25.8),("crate",57.29,24.7),("barrel",69.2,23.85),
         ("crate",62.55,31.83),("barrel",74.9,34.75),("crate",54.1,36.7),
         ("crate",79.24,31.72)),
        (("shells",51.23,25.06),("pressure_ammo",55.92,27.45),("bullets",62.36,22.66),
         ("rinds",67.65,24.82),("rifle_ammo",71.7,19.66),("beer",65.67,15.73),
         ("pressure_ammo",73.0,37.95),("shells",56.17,38.1),("rinds",63.66,41.32),
         ("beer",80.05,32.9)),
        (("lower-cut-chalk","valve_rat",54.12,26.7),("bench-boilerback","boilerback",60.7,22.1),
         ("upper-cut-chalk","chalk_spitter",71.1,25.6),("condenser-guard","valve_rat",72.5,19.39),
         ("terrace-saucer","saucer",65.25,35.7),("wash-yard-coot","coot",73.23,38.7),
         ("quarry-store-coot","coot",55.4,37.22)),
        (Station("wash-latch",70.61,35.5,"LIFT THE CART LATCH","OPEN CUT TO THE BOTTLE WASH.",
                 opens=((71,35),),cue="scenery_pipe",hidden=True),),
    )


def hickston_wing(world):
    r,w = world.room,world.wall
    world.tints = np.vstack((world.tints,((.94,.96,1.04),(1.10,1.01,.89),(.97,1.06,.96)))).astype(np.float32)
    r(47,22,61,26,"asphalt",12,light=1.03)
    r(49,24,65,25,"road",12,light=1.09)
    r(51,16,63,23,"gravel",12,light=.99)
    r(51,27,62,31,"tracks",12,light=.94)
    r(60,19,82,31,"dirt",13,light=1.04)
    r(62,22,80,25,"gravel",13,light=1.06)
    r(69,11,82,21,"grass",13,light=1.02)
    r(64,8,78,15,"gravel",14,light=.96)
    r(53,7,66,16,"gravel",14,light=.98)
    r(47,11,54,13,"shoulder",14,light=.94)
    r(56,3,74,8,"tracks",14,light=.97)
    r(70,4,81,11,"grass",14,light=1.00)
    r(80,9,94,19,"gravel",14,light=.94)
    r(82,18,94,30,"grass",13,light=1.02)
    r(84,7,91,11,"tracks",14,light=.91)
    r(83,11,88,15,"floor_tile",14,2.20,.92,"tin")
    r(88,25,93,29,"porch",13,2.18,.89,"joists")
    r(56,17,61,21,"floor_tile",12,2.34,1.02,"joists")
    r(64,26,71,30,"porch",13,2.62,.96,"joists")
    r(71,10,77,14,"floor_tile",14,2.34,1.10,"joists")
    r(57,9,63,12,"concrete",14,2.20,.92,"mill_tin")
    r(53,27,56,29,"creek",12,light=.92)
    world.ground[27:30,53:57] = -.14
    w(50,16,51,19,"hedgerow",1.11)
    w(56,16,60,16,"brick",2.56)
    w(55,17,55,20,"brick",2.56)
    w(59,20,61,20,"tin",2.33)
    w(65,19,67,21,"tin",2.06)
    w(73,23,76,24,"stockyard",.98)
    w(72,27,77,27,"stockyard",1.12)
    w(66,26,66,28,"barn",2.62)
    w(64,30,70,30,"barn",2.62)
    w(79,16,82,17,"hedgerow",1.18)
    w(70,10,70,13,"brick",2.43)
    w(71,9,76,9,"brick",2.43)
    w(77,10,77,13,"brick",2.43)
    w(73,14,76,14,"brick",2.43)
    w(57,8,62,8,"tin",2.21)
    w(56,9,56,11,"tin",2.21)
    w(61,11,63,11,"tin",2.21)
    w(65,5,67,7,"stockyard",1.24)
    w(76,5,78,7,"hedgerow",1.19)
    w(83,10,87,10,"tin",2.42)
    w(82,11,82,13,"brick",2.33)
    w(88,12,88,15,"tin",2.42)
    w(87,18,88,23,"stockyard",1.24)
    w(90,20,92,21,"hedgerow",1.18)
    w(88,24,92,24,"barn",2.36)
    w(93,25,93,28,"barn",2.36)
    w(50,11,50,13,"tin",2.02)
    world.door(50,12,14,vertical=True,key="key_steel",texture="gate")
    world.door_ids[50,12] = "registry-service-return"
    world.extension_doors += ((50,12),)
    shortcut(world,66,27,13,"pen-feed-hatch","barn",vertical=True)
    world.scenery = (
        Reactive("town-road-feed-can","cans",5.74,23.89,.40,.02),
        Reactive("town-stankys-empties","bottles",8.91,18.85,.42,.03),
        Reactive("town-tire-shop-cans","cans",57.11,20.26,.42,.03),
        Reactive("town-registry-scraps","scrap",74.0,14.63,.71,.05),
        Reactive("town-railhead-cans","cans",89.2,27.3,.42,.04),
    )
    world.light_pool(57.3,18.9,.27,4,12)
    world.light_pool(71.7,25.6,.30,4,13)
    world.light_pool(74.7,12.9,.32,4,14)
    return Wing(
        (Fixture(50.83,23.01,50.94,23.13,1.75,"wood","wood"),
         Fixture(50.83,24.74,50.94,24.86,1.75,"wood","wood"),
         Fixture(56.11,18.1,57.63,18.62,.81,"counter","counter_top"),
         Fixture(57.8,23.05,59.5,23.63,.56,"stockyard","porch"),
         Fixture(60.25,28.5,61.9,29.18,.70,"crate_side","porch"),
         Fixture(67.25,29.01,69.31,29.58,.74,"counter","porch"),
         Fixture(74.2,19.3,75.3,20.66,.61,"bleachers","porch"),
         Fixture(80.2,22.2,81.43,24.4,.90,"stockyard","porch"),
         Fixture(75.67,10.3,76.6,11.5,.80,"counter","counter_top"),
         Fixture(71.15,11.46,72.06,12.45,.76,"counter","counter_top"),
         Fixture(58.5,9.16,59.75,9.8,.68,"mill_tin","counter_top"),
         Fixture(84.21,11.17,85.62,11.86,.77,"counter","counter_top"),
         Fixture(90.72,27.46,92.04,28.08,.72,"stockyard","porch"),
         Fixture(71.34,5.10,73.55,5.74,.69,"stockyard","porch")),
        (Billboard(50.8,23.95,"wing_town_service",.87,.88,plane=math.pi/2),
         Billboard(56.022,18.67,"wing_town_tires",.74,1.39,plane=-math.pi/2),
         Billboard(57.02,19.2,"prop_tire",.43),
         Billboard(64.2,21.82,"wing_town_feed",.87,.63,plane=math.pi/2),
         Billboard(69.7,25.86,"wing_town_pen",.73,1.43,signal="cleared",plane=0.),
         Billboard(68.44,29.4,"split_feed_sacks",.46,.74),
         Billboard(68.25,28.986,"wing_town_scale",.92,.48,plane=math.pi),
         Billboard(74.45,15.025,"wing_town_registry",.77,1.40,plane=0.),
         Billboard(75.86,11.01,"wing_town_register",.57,.94,plane=0.),
         Billboard(59.18,9.7,"wing_town_tow",.66,1.19,plane=0.),
         Billboard(63.7,7.93,"prop_utilitypole",3.71),
         Billboard(73.92,5.88,"prop_tree",3.60),
         Billboard(85.0,14.27,"wing_town_radio",.81,1.28,plane=0.),
         Billboard(90.8,25.025,"wing_town_rail",.78,1.23,plane=0.),
         Billboard(90.2,18.8,"prop_utilitypole",3.71),
         Billboard(81.23,26.24,"prop_utilitypole",3.74),
         Billboard(65.96,27.47,"wing_town_hatch",.47,.53,signal="feed-hatch",plane=-math.pi/2)),
        (("pickup_truck_b",61.76,23.47),("tire",55.28,20.92),("crate",61.5,29.93),
         ("barrel",70.9,26.95),("crate",77.45,19.34),("barrel",60.16,12.05),
         ("crate",73.35,10.88),("tire",79.8,6.05),("crate",86.7,12.77),
         ("barrel",89.67,27.35)),
        (("bullets",51.87,24.67),("rinds",58.6,21.88),("shells",60.3,22.18),
         ("rifle_ammo",68.85,27.4),("beer",70.74,18.0),("rinds",76.85,18.17),
         ("shells",74.61,15.3),("key_steel",74.57,12.15),("dynamite",58.1,10.3),
         ("rifle_ammo",70.89,6.81),("rinds",85.9,12.68),("beer",91.75,26.93)),
        (("service-road-billy","billy",53.65,22.42),("tire-garage-coot","yard_deputy",59.4,18.65),
         ("salvage-lot-clone","clone",63.6,25.65),("feed-pens-billy","yard_deputy",70.05,28.64),
         ("registry-coot","coot",74.45,17.33),("weigh-lane-clone","clone",79.15,20.4),
         ("office-guard","alien",75.34,12.72),("towyard-skeeter","skeeter",61.45,10.35),
         ("north-pen-guard","alien",77.6,8.76),("radio-shack-coot","coot",84.8,13.4),
         ("railhead-skeeter","skeeter",91.65,25.53)),
        (Station("feed-hatch",65.57,27.47,"UNBOLT THE FEED HATCH","FEED HATCH OPEN. TAKE THE SHORT CUT.",
                 opens=((66,27),),cue="scenery_scrap",hidden=True),),
    )
