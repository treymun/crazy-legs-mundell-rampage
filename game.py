"""Shared player, combat, interaction and objective state."""
from dataclasses import dataclass
import math
import random

import pygame as pg

from campaign import BY_ID, GATE_LABELS, HICKSTON, LEVELS, Station, Extraction
from chatter import EXCHANGES
from county_events import (CountyNote, GALLERY_STAND, Gallery, HUB_BOARD, HUB_DISPATCH,
                           INTERIORS, NOTES, PARTNERS, RECOVERY_ROOMS, RUPTURES)
from crossroads import HUB_WIDTH
from enemies import BOSS_TITLES, LOSS_RESPONDERS, RANGED, TELLS, Enemy
from engine import HEIGHT, VIEW, WIDTH, GroundMark, Renderer, Sprite, impact_surface
from hud import ITEMS, ITEM_LABELS
from rampage2 import Barks, Cheats, drunk_warp, look_pass
from level_hickston import TILE
from pixel_type import text_width
from scenery import REACTIONS
from weapons import ARMGUN, BOWLING, COW, CROSSBOW, DYNAMITE, KEG, PRESSURE, REVOLVER, RIFLE, RIPSAW, RIVETER, ROCKET, SHOTGUN, TEAT, Armory, NAMES
from populate2 import populate

PROP_HEIGHTS = {"barrel": 1.04, "hay": .91, "pump": 1.43, "pump_b": 1.43, "sink": .89, "crate": .75,
                "jukebox": 1.45, "lamp": .24, "tree": 3.65, "tree_b": 3.65, "utilitypole": 3.85,
                "pickup_truck": 1.31, "pickup_truck_b": 1.20, "roadsign": 1.67, "bleacher_sign": 1.58,
                "mailbox": 1.18, "tire": .40, "windmill": 4.65, "silo": 3.78, "reeds": .58,
                "water_tower": 5.1}
DISTRICTS = HICKSTON.districts
PLAYER_RADIUS = .19
SURFACE_SOUNDS = {TILE[name]: cue for cue, names in (
    ("wood", ("porch",)), ("tile", ("floor_tile", "concrete")),
    ("mud", ("dirt", "tracks", "shoulder")), ("grass", ("grass", "orchard")),
    ("water", ("creek", "mill_water")), ("gravel", ("fair_gravel", "mill_grit", "quarry_dust",
                                                   "quarry_face", "route_threshold")),
) for name in names}
PICKUP_NAMES = {"key_brass": "BRASS BARN KEY", "key_steel": "STEEL PASTURE KEY", "bullets": ".38 ROUNDS",
                "shells": "BUCKSHOT", "dynamite": "DYNAMITE STICKS", "rinds": "PORK RINDS",
                "moonshine": "MOONSHINE", "beer": "BEER", "rifle_ammo": "RIFLE CARTRIDGES",
                "saw_ammo": "SAW BLADES", "arm_ammo": "ALIEN CELLS",
                "rocket_ammo": "BOTTLE ROCKETS", "rivet_ammo": "MILL RIVETS",
                "pressure_ammo": "SEALED PRESSURE CHARGES", "pa_patch":"PA PATCH LEAD",
                "whiskey":"WHISKEY","cowpie":"COW PIE","milk_ammo":"FRESH MILK","bowling_ammo":"BOWLING BALLS",
                "keg_ammo":"POWDER KEGS","cow_ammo":"SPARE COWS"}
ALIAS = {"riveter":"bowling_ball","pressure_gun":"cow_launcher"}
TASK_ITEMS = {"pa_patch"}
AMMO = {"bullets": (REVOLVER, 11), "shells": (SHOTGUN, 10), "dynamite": (CROSSBOW, 6),
        "rifle_ammo": (RIFLE, 24), "saw_ammo": (RIPSAW, 5), "arm_ammo": (ARMGUN, 9),
        "rocket_ammo": (ROCKET, 4), "rivet_ammo": (BOWLING, 2), "pressure_ammo": (COW, 2),
        "milk_ammo": (TEAT, 40), "bowling_ammo": (BOWLING, 2), "keg_ammo": (KEG, 1), "cow_ammo": (COW, 1)}


@dataclass
class Controls:
    forward: float = 0.
    strafe: float = 0.
    turn: float = 0.
    look: float = 0.
    running: bool = False
    fire: bool = False
    alt_fire: bool = False
    jump: bool = False
    crouch: bool = False


@dataclass
class Player:
    x: float
    y: float
    angle: float
    health: int = 100
    gut: float = 0.
    drunk: float = 0.
    pitch: float = 0.
    eye: float = .95
    bob: float = 0.
    sway: float = 0.
    drift: float = 0.
    walk_phase: float = 0.
    motion: float = 0.
    air: float = 0.
    vertical_speed: float = 0.
    jump_held: bool = False
    vx: float = 0.
    vy: float = 0.
    crouched: bool = False

    @property
    def view_angle(self):
        return self.angle + self.drift


@dataclass
class Shot:
    x: float
    y: float
    z: float
    vx: float
    vy: float
    vz: float
    kind: str
    life: float
    enemy: bool
    damage: int
    bounces: int = 0
    travelled: float = 0.
    resting: bool = False


@dataclass
class Speck:
    x: float
    y: float
    z: float
    vx: float
    vy: float
    vz: float
    life: float
    kind: str


@dataclass
class Blast:
    x: float
    y: float
    z: float
    age: float = 0.
    kind: str = "fire"


@dataclass
class Hazard:
    kind: str
    x: float
    y: float
    radius: float
    warning: float
    life: float
    damage: int
    age: float = 0.
    next_hit: float = 0.


class Game:
    def __init__(self, art, hud, sound, level_id="hickston"):
        self.art, self.hud, self.sound = art, hud, sound
        self.level = BY_ID[level_id]
        self.world = self.level.build()
        self.renderer = Renderer(self.world, art)
        self.player = Player(*self.level.spawn)
        self.player.eye += self.world.elevation(self.player.x, self.player.y)
        self.armory = Armory()
        self.enemy_ids = self.world.enemy_ids
        self.enemies = [Enemy(kind, x, y, angle=(i * 2.3) % math.tau)
                        for i, (kind, x, y) in enumerate(self.world.enemies)]
        actors = dict(zip(self.enemy_ids,self.enemies))
        self.partners = {id(actors[advance]): (actors[cover],side)
                         for advance,cover,side in PARTNERS.get(level_id,())}
        for i, route in self.world.patrols.items():
            enemy = self.enemies[i]
            enemy.route = route
            enemy.patrol_pause = .32 + (i*.73)%1.85
            enemy.angle = math.atan2(route[0][1]-enemy.y,route[0][0]-enemy.x)
        self.wave = tuple(self.enemies[i] for i in self.world.reinforcements)
        for enemy in self.wave:
            enemy.dormant = True
        self.boss = self.jerry = self.bessie = None
        self.finale = next((e for e in self.wave if e.kind in TELLS),None)
        if self.level.rescue:
            self.enemies[0].angle = math.pi*.58
            self.boss = next(enemy for enemy in self.enemies if enemy.kind == "boss")
            self.boss.angle = math.pi*.49
            self.jerry = next(enemy for enemy in self.enemies if enemy.kind == "jerry")
            self.jerry.dormant = True
            self.bessie = next(enemy for enemy in self.enemies if enemy.kind == "bessie")
        self.props = [Sprite(x, y, "prop_" + name + ("_0" if name == "windmill" else ""), PROP_HEIGHTS[name],
                             self.world.roof[int(y), int(x)] - .25 if name == "lamp"
                             else self.world.elevation(x, y),
                             name == "lamp", plane=0. if name in ("roadsign","bleacher_sign") else None)
                      for name, x, y in self.world.props]
        self.pickups = [(ALIAS.get(n,n),x,y) for n,x,y in self.world.pickups]
        populate(self)
        self.drums = dict.fromkeys(self.world.fuel_drums, 18)
        self.inventory = {name: 0 for name in ITEMS}
        self.inventory["rinds"] = 1
        self.inventory_slot = 0
        self.keys = set()
        self.stations_done = set()
        self.total_secrets = sum(door.secret for door in self.world.doors)
        self.total_secrets += sum(station.reveals_secret for station in self.world.stations)
        self.history = ()
        self.replay = False
        self.revisiting = False
        self.retained = {}
        self.music_bookmark = None
        self.in_hub = False
        self.gallery = Gallery() if level_id=="fair" else None
        self.supply_rule = 0
        self.gate_modes = {}
        self.hub_findings = set()
        self.hub_milestone = 0
        self.hub_dispatch_until = 0.
        self.portal_request = None
        self.entry = self.loadout()
        self.kills = self.secrets = 0
        self.total_kills = sum(enemy.hostile for enemy in self.enemies)
        self.rng = random.Random(1997)
        self.barks = Barks()
        self.duck = 0.
        self.cheats = Cheats()
        self.last_low_bark = 0.
        self.clock = 0.
        self.face_until = self.message_until = 0.
        self.face = self.notice = ""
        self.hurt_flash = self.blast_flash = self.sprint = 0.
        self.damage_feedback = None
        self.item_feedback = None
        self.step_number = 0
        self.next_belch = 0.
        self.shots = []
        self.specks = []
        self.blasts = []
        self.hazards = []
        self.wall_marks = []
        self.wall_sound = 0.
        self.map = False
        self.won = False
        self.legacy_completed = False
        self.legacy_key_route = False
        self.task_items = set()
        self.valve_turns = {}
        self.next_valve_turn = 0.
        self.scenery_spent = set()
        self.bowled = {}
        self.exchanges = () if self.in_hub else EXCHANGES.get(self.level.id, ())
        self.heard_exchanges = set()
        self.exchange_next = 0.
        self.exchange_pending = None
        self.caption = ""
        self.caption_until = 0.
        self.visited = set()
        self.district = int(self.world.area[int(self.player.y), int(self.player.x)])
        self.district_until = 3.
        self.amb_clock = 3.
        self.jukebox_on = False
        self.flush_until = 0.
        self.map_panel = None
        self.map_signature = None
        self.radio_check = 0.
        self.configure({})
        self.message(self.level.introduction, 5.0)

    def loadout(self):
        return {"health": self.player.health, "owned": list(self.armory.owned),
                "loaded": list(self.armory.loaded), "reserve": list(self.armory.reserve),
                "active": self.armory.active, "inventory": dict(self.inventory),
                "slot": self.inventory_slot}

    def apply_loadout(self, kit):
        self.player.health = kit["health"]
        self.armory.owned = list(kit["owned"])
        self.armory.loaded = list(kit["loaded"])
        self.armory.reserve = list(kit["reserve"])
        self.armory.active = kit["active"]
        self.inventory = dict(kit["inventory"])
        self.inventory_slot = kit["slot"]

    def result(self):
        return (self.level.id, self.kills, self.total_kills,
                self.secrets, self.total_secrets, int(self.clock))

    @property
    def showing_tally(self):
        return self.won and not self.revisiting

    def move_actor(self, body, dx, dy, radius):
        player = self.player
        if body is player:
            neighbors = [enemy for enemy in self.enemies
                         if enemy.hostile and enemy.alive
                         and abs(body.x-enemy.x) < 1.1 and abs(body.y-enemy.y) < 1.1]
        elif body.hostile and abs(body.x-player.x) < 1.1 and abs(body.y-player.y) < 1.1:
            neighbors = [player]
        else:
            neighbors = []

        def occupied(x, y):
            for neighbor in neighbors:
                enemy = neighbor if body is player else body
                enemy_base = self.world.elevation(enemy.x, enemy.y) + enemy.z
                player_base = self.world.elevation(player.x, player.y) + player.air
                if enemy_base >= player_base + (.80 if player.crouched else 1.16):
                    continue
                if player_base >= enemy_base + enemy.height:
                    continue
                reach = PLAYER_RADIUS + min(enemy.radius, .37)
                distance = (x-neighbor.x)**2 + (y-neighbor.y)**2
                # An old checkpoint may already overlap a body. Allow motion outward.
                if distance < reach**2 and distance < (body.x-neighbor.x)**2 + (body.y-neighbor.y)**2:
                    return True
            return False

        self.world.move(body, dx, dy, radius, occupied if neighbors else None)

    def configure(self, options):
        self.incoming = (.66, 1., 1.34)[options.get("difficulty",1)]
        self.bob_scale = options.get("bob",100)/100
        self.flash_scale = (1.,.32,0.)[options.get("flashes",0)]
        self.gore = bool(options.get("gore",1))
        self.aim_assist = options.get("aim_assist",0)
        self.district_labels = bool(options.get("district_labels",1))
        self.hints = bool(options.get("hints",1))
        self.hud_style = options.get("hud_style",0)
        self.renderer.world_motion = options.get("world_motion",0)
        self.weapon_view = options.get("weapon_view",0)
        self.voice_captions = bool(options.get("voice_captions",1))
        self.bullet_marks = bool(options.get("bullet_marks",1))
        self.retro_look = bool(options.get("retro_look",1))
        self.flicker = bool(options.get("flicker",1))
        self.armory.auto_switch = bool(options.get("auto_switch",1))
        self.armory.auto_reload = bool(options.get("auto_reload",1))
        self.barks.enabled = bool(options.get("barks", 1)) and not getattr(self, "barks_off_by_code", False)

    def message(self, text, length=1.9):
        self.notice = text
        self.message_until = self.clock + max(length, .70 + .16 * len(text.split()))

    def sound_position(self, x, y, strength=1., muffle=True):
        p = self.player
        dx, dy = x - p.x, y - p.y
        distance = math.hypot(dx, dy)
        volume = strength / (1 + distance * .22)
        if muffle and distance > 1. and not self.world.visible(p.x, p.y, x, y):
            volume *= .43
        pan = (-math.sin(p.view_angle) * dx + math.cos(p.view_angle) * dy) / max(1., distance)
        return volume, pan

    def sound_at(self, name, x, y, strength=1.):
        volume, pan = self.sound_position(x,y,strength)
        self.sound.play(name, volume, pan)
        p = self.player
        if (name not in ("bessie",) and self.world.roof[int(p.y),int(p.x)]
                and f"room_{name}" in self.sound.samples):
            self.sound.play(f"room_{name}", volume*.55, pan)

    def report(self, name):
        p = self.player
        self.sound.play(name)
        roof = self.world.roof[int(p.y), int(p.x)]
        if roof:
            self.sound.play("room_"+name, .78)

    def wake_nearby(self, radius, x, y):
        for enemy in self.enemies:
            distance = math.hypot(enemy.x - x, enemy.y - y)
            if (enemy.alive and enemy.hostile and not enemy.alerted and distance < radius
                    and (distance < 1.45 or self.world.visible(x, y, enemy.x, enemy.y))):
                enemy.wake(self, x, y)

    def disturb(self,x,y,radius,z=None):
        source = self.world.elevation(x,y)+.78 if z is None else z
        for actor in self.enemies:
            if not actor.alive or actor.alerted or actor.heard or actor.kind in (*BOSS_TITLES,"bessie","saucer"):
                continue
            dx,dy = actor.x-x,actor.y-y
            reach = radius if actor.hostile else min(radius,3.5)
            if dx*dx+dy*dy>=reach*reach:
                continue
            ear = self.world.elevation(actor.x,actor.y)+actor.z+min(.90,actor.height*.76)
            if not self.world.visible(x,y,actor.x,actor.y,source,ear):
                continue
            ready = self.clock+.22+math.hypot(dx,dy)*.035
            actor.heard = (x,y,ready,self.clock+(2.6 if actor.hostile else 1.05))
            if not actor.hostile:
                self.sound_at("chicken" if actor.kind=="chicken" else "pig",actor.x,actor.y,.43)

    def enemy_down(self, enemy):
        self.kills += 1
        if enemy.hostile:
            self.barks.kill(self)
        if enemy.kind not in BOSS_TITLES:
            for actor in self.enemies:
                if (actor.kind in LOSS_RESPONDERS and actor.alive and actor.alerted and not actor.responded
                        and not actor.windup and math.hypot(actor.x-enemy.x,actor.y-enemy.y)<2.85
                        and self.world.visible(actor.x,actor.y,enemy.x,enemy.y)):
                    actor.retreat_from(self,enemy.x,enemy.y)
                    self.sound_at("county_fall_back",actor.x,actor.y,.67)
                    break
        if enemy is self.boss:
            self.jerry.dormant = False
            self.jerry.wake(self, self.player.x, self.player.y)
            self.jerry.cooldown = 1.25
            self.message("THE SHERIFF'S DOWN. HERE COMES JERRY!", 4.)
            self.sound.play("jerry_intro")
        elif enemy is self.jerry:
            self.message("THAT'S THE BALL GAME! GO GET BESSIE.", 5.)
            self.sound.play("yee_haw")
            self.sound.sting("shakedown_end")
        elif enemy is self.finale:
            self.hazards.clear()
            self.shots = [shot for shot in self.shots if shot.kind not in ("foreman_cut","rudy_horn")]
            reward = {"rudy":"rocket_ammo", "foreman":"rivet_ammo", "baron":"pressure_ammo"}[enemy.kind]
            self.add_pickup(reward,enemy.x,enemy.y)
            self.message(BOSS_TITLES[enemy.kind]+" IS DOWN. CLEAR THE LAST VARMINTS.",3.)
            self.sound.sting(enemy.kind+"_end")
        elif enemy.kind == "boilerback":
            self.add_pickup("pressure_ammo",enemy.x,enemy.y)
        elif enemy.kind == "chalk_spitter" and self.rng.random()<.42 and self.supply_rule!=2:
            self.add_pickup("bullets",enemy.x,enemy.y)
        elif enemy.kind in ("clone", "coot") and self.rng.random() < .65 and self.supply_rule!=2:
            self.add_pickup("bullets", enemy.x, enemy.y)
        elif enemy.kind == "billy" and self.rng.random() < .60 and self.supply_rule!=2:
            self.add_pickup("shells", enemy.x, enemy.y)
        if enemy.hostile and enemy.kind not in BOSS_TITLES and self.supply_rule != 2 and self.rng.random() < .07:
            self.add_pickup(self.rng.choice(("rinds", "beer", "moonshine", "whiskey", "cowpie")), enemy.x + .2, enemy.y)
            self.message("FEELIN' LUCKY. SOMETHING DROPPED.", 1.6)
        if (self.world.extraction and self.world.extraction.shutdown in self.stations_done
                and any(member is enemy for member in self.wave)
                and not any(member.alive for member in self.wave)):
            self.message("THE EXIT IS CLEAR. GET MOVING.", 4.)
            self.sound.play("gate")

    def set_face(self, face, duration):
        if self.face == "ouch_shock" and self.clock < self.face_until and face != "ouch_shock":
            return
        self.face = face
        self.face_until = self.clock + duration

    def face_name(self):
        health = self.player.health
        if health <= 0:
            return "dead"
        if self.face_until > self.clock:
            return self.face
        if self.player.drunk > 47:
            return "drunk_dizzy"
        if health <= 25:
            return "hurt_75"
        if health <= 50:
            return "hurt_50"
        if health <= 75:
            return "hurt_25"
        phase = self.clock % 5.9
        if 1.7 < phase < 2.04:
            return "look_left"
        if 3.3 < phase < 3.62:
            return "look_right"
        return "idle_blink" if phase > 5.75 else "idle_center"

    def damage(self,amount,source=None,cause="HIT"):
        if self.player.health <= 0:
            return
        p = self.player
        if self.cheats.god:
            return
        mellow = .10 * (15 <= p.drunk <= 56) + .09 * (16 <= p.gut <= 64)
        amount = max(1, round(amount * (1 - mellow) * self.incoming))
        p.health = max(0, p.health - amount)
        if self.gallery and self.gallery.active:
            self.gallery.finish(self,"GALLERY CLOSED. CLEAR THE BOOTH AND RETRY.")
        heading = None if source is None else math.atan2(source[1]-p.y,source[0]-p.x)
        self.damage_feedback = (heading,cause,self.clock+.64)
        self.hurt_flash = .27
        self.set_face("ouch_shock", .32)
        self.barks.say(self, "low" if p.health <= 25 else "hurt")
        self.sound.play("player_down" if p.health == 0 else "hurt")
        if p.health == 0:
            self.message("YOU BOUGHT THE FARM.", 8.)

    def add_pickup(self, name, x, y):
        self.pickups.append((name, x, y))

    def collect(self, name):
        name = ALIAS.get(name,name)
        if name in NAMES:
            self.armory.pickup(NAMES.index(name), self)
            self.barks.say(self, "pickup_weapon", True)
            self.set_face("grin_rampage", .6)
        elif name in ITEMS:
            if self.inventory[name] >= 5:
                return False
            self.inventory[name] += 1
            self.message(PICKUP_NAMES[name])
            self.barks.say(self, "pickup_food")
        elif name in TASK_ITEMS:
            self.task_items.add(name)
            self.message("PA PATCH LEAD. TAKE IT TO THE BACKSTAGE BOOTH.",3.)
        elif name.startswith("key_"):
            self.keys.add(name)
            self.message("BRASS KEY - OPEN THE BARN." if name.endswith("brass")
                         else "STEEL KEY - OPEN THE PASTURE GATE.", 4.)
        else:
            slot, amount = AMMO[name]
            if self.supply_rule==1:
                amount = max(1,round(amount*.70))
            if not self.armory.add_ammo(slot, amount):
                return False
            if name == "dynamite" and not self.armory.owned[DYNAMITE]:
                self.armory.owned[DYNAMITE] = True
                self.message("DYNAMITE [8] - HOLD FIRE, RELEASE TO THROW", 3.5)
            else:
                self.message(PICKUP_NAMES[name], 1.)
        self.sound.play("key_pickup" if name.startswith("key_") else
                        "weapon_pickup" if name in NAMES else "pickup", .8)
        return True

    def use_item(self, slot=None):
        if slot is not None:
            self.inventory_slot = slot
        i = self.inventory_slot
        name = ITEMS[i]
        if not self.inventory[name]:
            self.message("OUT OF " + ITEM_LABELS[i] + ".", 1.05)
            return
        self.inventory[name] -= 1
        p = self.player
        health = p.health
        if i == 0:
            p.gut = min(100, p.gut + 37)
            p.health = min(100, p.health + 28)
            if p.drunk > 52:
                p.drunk -= 13
            text = "PORK RINDS. GOOD EATIN'."
            state = "FULL GUT" if p.gut>=86 else ""
        elif i == 1:
            p.drunk = min(100, p.drunk + 36)
            p.health = min(100, p.health + 16)
            text = "COLD BEER. EASY ON THE STEERING."
            state = "WOBBLY" if p.drunk>82 else "BUZZED"
        elif i == 3:
            p.drunk = min(100, p.drunk + 55)
            p.health = min(100, p.health + 34)
            text = "WHISKEY. HAIR ON YER CHEST."
            state = "LOOSE" if p.drunk>70 else "WARM"
        elif i == 4:
            p.gut = min(100, p.gut + 48)
            p.drunk = max(0., p.drunk - 12)
            p.health = min(100, p.health + 12)
            text = "COW PIE. DON'T ASK."
            state = "FULL GUT" if p.gut>=86 else ""
        else:
            p.drunk = max(0., p.drunk - 70)
            p.gut = max(0., p.gut - 55)
            p.health = min(100, p.health + 24)
            self.sprint = 7.
            text = "THAT'LL PUT HAIR ON THE TRACTOR."
            state = "SPEED UP"
        self.sound.play(("crunch", "gulp", "moonshine", "whiskey_glug", "cowpie_pick")[i])
        self.message(text)
        change = f"+{p.health-health} HP" if p.health>health else ""
        self.item_feedback = (name,"  ".join(bit for bit in (change,state) if bit),self.clock+1.05)

    def use_target(self):
        p = self.player
        if self.gallery and self.gallery.active:
            return self.gallery,*GALLERY_STAND
        facing = (math.cos(p.view_angle),math.sin(p.view_angle))
        if self.bessie:
            dx, dy = self.bessie.x - p.x, self.bessie.y - p.y
            distance = math.hypot(dx,dy)
            if (distance<1.52 and (distance<.55 or dx*facing[0]+dy*facing[1]>distance*.40)
                    and self.world.visible(p.x,p.y,self.bessie.x,self.bessie.y)):
                return "bessie", self.bessie.x, self.bessie.y
        doors = ((door,*door.center) for door in self.world.doors
                 if not (door.opened and (door.blast_only or (door.x,door.y) in self.world.controlled_doors)))
        devices = [(station, station.x, station.y) for station in self.world.stations
                   if not station.reveals_secret or station.id not in self.stations_done]
        if self.world.extraction:
            exit = self.world.extraction
            devices.append((exit, exit.x, exit.y))
        if self.level.rescue:
            devices.extend((("jukebox",7.26,17.14),("sink",3.2,13.5)))
        if self.gallery:
            devices.append((self.gallery,*GALLERY_STAND))
        devices.extend((note,note.x,note.y) for note in NOTES.get(self.level.id,()))
        best = (True,math.inf)
        result = None
        for candidates,reach,touch,cone in ((doors,1.57,.50,.48),(devices,1.45,.52,.40)):
            for target,x,y in candidates:
                dx,dy = x-p.x,y-p.y
                distance = math.hypot(dx,dy)
                aimed = dx*facing[0]+dy*facing[1]>distance*cone
                rank = (not aimed,distance)
                if (distance<reach and (aimed or distance<touch) and rank<best
                        and self.world.visible(p.x,p.y,x,y)):
                    best,result = rank,(target,x,y)
        return result

    def use_prompt(self):
        found = self.use_target()
        if not found:
            return ""
        target,_,_ = found
        if target == "bessie":
            return "CLEAR THE PEN FIRST" if self.boss.alive or self.jerry.alive else "E  RESCUE BESSIE"
        if target == "jukebox":
            return "E  STOP JUKEBOX" if self.jukebox_on else "E  PLAY JUKEBOX"
        if target == "sink":
            return "E  USE SINK"
        if isinstance(target,Gallery):
            return target.prompt()
        if isinstance(target,CountyNote):
            return "E  READ "+target.label
        if isinstance(target, Station):
            if target.id in self.stations_done:
                return "ALREADY SET"
            if target.reveals_secret:
                return "E  CHECK THE LOOSE PANEL"
            if not all(key in self.stations_done for key in target.requires):
                return self.objective()
            if target.held and target.held not in self.task_items:
                return "FIND THE PATCH LEAD AT THE RAFFLE OFFICE"
            if target.action=="strike":
                return "STRIKE THE BELT RELEASE"
            if target.action=="crank":
                return f"E  TURN THE CONDENSER  {self.valve_turns.get(target.id,0)}/3"
            return "E  " + target.label
        if isinstance(target, Extraction):
            return "E  " + target.label if self.exit_ready() else "EXIT LOCKED / CHECK TAB MAP"
        if (target.x, target.y) in self.world.controlled_doors:
            return "" if target.opened else "CONTROLLED BY A REMOTE SWITCH"
        if target.blast_only:
            return "POWDER STORE  /  BLAST PANEL"
        if target.key and target.key not in self.keys:
            return "BRASS KEY NEEDED" if target.key.endswith("brass") else "STEEL KEY NEEDED"
        if target.secret and not target.discovered:
            if (target.x,target.y) in self.world.crouch_doors:
                return "CROUCH / USE THE LOW HATCH"
            return ""
        return "E  CLOSE DOOR" if target.opened else "E  OPEN DOOR"

    def interact(self):
        if self.showing_tally or self.player.health <= 0:
            return
        gate = self.portal_target()
        if gate:
            if gate in self.world.locked_gates:
                self.message(self.gate_text(gate), 3.)
                self.sound.play("empty")
            elif self.armory.fuse:
                self.message("THROW THE LIT STICK BEFORE LEAVING.", 3.)
            else:
                self.portal_request = gate.destination
            return
        if self.in_hub:
            clue = self.hub_clue()
            if clue:
                self.message(clue[4],4.)
                if clue[0]=="dispatch":
                    if self.clock>=self.hub_dispatch_until:
                        self.hub_dispatch_until=self.clock+6.
                        volume,pan=self.sound_position(*HUB_BOARD,.64)
                        self.sound.play_voice(f"county_dispatch_{self.hub_milestone}",volume,pan)
                        if self.voice_captions:
                            self.caption=HUB_DISPATCH[self.hub_milestone][2]
                            self.caption_until=self.clock+2.4
                else:
                    self.hub_findings.add(clue[0])
                    self.sound.play("menu_accept",.55)
            return
        found = self.use_target()
        if not found:
            return
        target,x,y = found
        if target == "bessie":
            if self.boss.alive or self.jerry.alive:
                self.message("CLEAR THE PASTURE BEFORE YOU FREE BESSIE.", 2.4)
            elif self.revisiting:
                self.message("BESSIE IS SAFE. RETURN VIA THE ROAD GATE.", 2.4)
            else:
                self.finish_level("got_bessie")
            return
        if target == "jukebox":
            self.jukebox_on = not self.jukebox_on
            self.radio_check = 0.
            self.sound_at("menu_accept",x,y,.54)
            self.message("JUKEBOX: HICKSTON SHUFFLE" if self.jukebox_on else "JUKEBOX OFF",1.45)
            return
        if target == "sink":
            if self.clock >= self.flush_until:
                self.flush_until = self.clock+1.35
                self.sound_at("sink_flush",x,y,.83)
                self.burst(x,y,.86,"splash",8,.47)
                self.message("WASH UP, YOU ANIMAL.",1.5)
            return
        if isinstance(target,Gallery):
            target.toggle(self)
            return
        if isinstance(target,CountyNote):
            self.message(target.text,4.)
            self.sound.play("menu_move",.40)
            return
        if isinstance(target, Station):
            self.operate_station(target)
            return
        if isinstance(target, Extraction):
            if self.revisiting:
                self.message("SHIFT DONE. RETURN VIA THE ROAD GATE.", 2.4)
            elif self.exit_ready():
                self.finish_level("gate")
            else:
                self.message(self.objective(), 3.)
            return
        door = target
        if (door.x, door.y) in self.world.controlled_doors:
            if not door.opened:
                self.message("THAT GATE HAS A REMOTE SWITCH.", 2.5)
            return
        if door.key and door.key not in self.keys:
            self.message("NEEDS THE BRASS BARN KEY." if door.key.endswith("brass")
                         else "NEEDS THE STEEL PASTURE KEY.", 2.7)
            self.sound.play("empty")
            return
        if door.blast_only:
            self.message("POWDER STORE. THAT PANEL NEEDS DYNAMITE.", 2.65)
            self.sound.play("empty",.56)
            return
        if (door.x, door.y) in self.world.crouch_doors and not self.player.crouched and not door.discovered:
            self.message("GET LOW AND TRY THE HATCH AGAIN.", 3.)
            return
        self.toggle_door(door, not door.opened)

    def set_station_lights(self, station):
        for sector in station.sectors:
            self.world.light[self.world.area == sector] += .26
            self.world.walls[self.world.walls[:, 8] == sector, 5] += .26

    def activate_station(self, station):
        if station.id in self.stations_done:
            return
        if not all(key in self.stations_done for key in station.requires):
            self.message(self.objective(), 3.)
            self.sound.play("empty")
            return
        self.stations_done.add(station.id)
        self.set_station_lights(station)
        for door in self.world.doors:
            point = (door.x, door.y)
            required = self.world.access_doors.get(point)
            if point in station.opens or required and self.stations_done.issuperset(required) and not door.opened:
                self.toggle_door(door, True)
        if station.reveals_secret:
            self.secrets += 1
        if self.world.extraction and station.id == self.world.extraction.shutdown:
            for enemy in self.wave:
                enemy.dormant = False
                enemy.wake(self, self.player.x, self.player.y)
                enemy.cooldown = 2.05 if enemy is self.finale else 1.15
            if self.finale:
                self.sound.sting(self.finale.kind+"_intro")
        self.sound_at(station.cue, station.x, station.y, .95)
        self.message(station.message, 4.)

    def operate_station(self, station):
        if station.id in self.stations_done:
            return
        if station.action=="strike":
            self.message("THE HANDLE'S STRIPPED. HIT THE BELT RELEASE.",3.)
            return
        if station.held and station.held not in self.task_items:
            self.message("NEEDS THE PATCH LEAD FROM THE RAFFLE OFFICE.",3.)
            return
        if station.action=="crank":
            if self.clock<self.next_valve_turn:
                return
            self.next_valve_turn = self.clock+.20
            turns = self.valve_turns.get(station.id,0)+1
            if turns<3:
                self.valve_turns[station.id] = turns
                self.sound_at("scenery_pipe",station.x,station.y,.67)
                self.message(f"CONDENSER VALVE  {turns}/3. KEEP TURNING.",2.)
                return
            self.valve_turns.pop(station.id,None)
        self.activate_station(station)

    def exit_ready(self):
        exit = self.world.extraction
        return bool(exit and exit.shutdown in self.stations_done and not any(e.alive for e in self.wave))

    def finish_level(self, cue):
        if not self.won:
            self.won = True
            self.shots.clear()
            self.hazards.clear()
            self.blasts.clear()
            self.specks.clear()
            self.sound.pause_world()
            self.sound.set_score("victory")
            self.sound.play(cue)

    def portal_target(self, reach=2.62):
        portals = self.world.hub_gates if self.in_hub else (self.world.return_gate,)
        p = self.player
        for gate in portals:
            if gate and gate.approach(p.x,p.y,p.view_angle,reach):
                face=gate.y+math.copysign(.17,p.y-gate.y)
                if self.world.visible(p.x,p.y,p.x,face,p.eye,self.world.elevation(p.x,face)+.93):
                    return gate
        return None

    def hub_clue(self):
        p = self.player
        label,text,_=HUB_DISPATCH[self.hub_milestone]
        candidates=(*self.world.hub_clues,("dispatch",*HUB_BOARD,"READ "+label,text))
        closest,nearest = None,1.32**2
        for clue in candidates:
            x,y = clue[1:3]
            dx,dy = x-p.x,y-p.y
            if (dx*dx+dy*dy < nearest and dx*math.cos(p.view_angle)+dy*math.sin(p.view_angle) > .22
                    and self.world.visible(p.x,p.y,x,y,p.eye,self.world.elevation(x,y)+.96)):
                closest,nearest=clue,dx*dx+dy*dy
        return closest

    def gate_text(self, gate):
        if gate.destination == "hub":
            return "E  RETURN TO COUNTY CROSSROADS"
        level = BY_ID[gate.destination]
        if gate in self.world.locked_gates:
            previous = LEVELS[LEVELS.index(level)-1]
            return f"LOCKED / FINISH {previous.title}"
        return f"E  {self.gate_modes.get(gate.destination,'ENTER')} {level.title}"

    def toggle_door(self, door, opened):
        door.opened = opened
        if door.blast_only and opened:
            door.progress = 1.
            self.burst(*door.center,.86,"dust",11,1.6)
        else:
            self.sound_at("secret_slide" if door.secret else "gate" if door.key else "door", *door.center)
        if door.secret and not door.discovered:
            door.discovered = True
            self.secrets += 1
            self.message("YOU FOUND A SECRET!", 2.4)
            self.barks.say(self, "secret")
            self.sound.play("yee_haw")

    def launch(self, x, y, z, angle, speed, kind, vz=0., enemy=False, damage=0, life=None):
        if life is None:
            life = 2.6 if kind == "blade" else 3.8 if enemy else 1.55
        self.shots.append(Shot(x, y, z, math.cos(angle) * speed, math.sin(angle) * speed,
                               vz, kind, life, enemy, damage, 3 if kind == "blade" else 0))

    def throw_dynamite(self, remaining):
        p = self.player
        aim = p.view_angle
        dx, dy = math.cos(aim), math.sin(aim)
        x, y = p.x + dx*.21, p.y + dy*.21
        if self.world.blocked(x, y, .05):
            x,y = p.x,p.y
        if remaining <= 0.:
            self.explode(Shot(p.x,p.y,p.eye-.30,0.,0.,0.,"tnt",0.,False,0))
            self.damage(21,(p.x,p.y),"LIT DYNAMITE")
            return
        self.shots.append(Shot(x, y, p.eye-.17, dx*6.1, dy*6.1,
                               1.55 + p.pitch*.037, "tnt", remaining, False, 0, 5))

    def hitscan(self, angle, slope, amount, max_range, spread, spark=True, pressure=False):
        p = self.player
        ax, ay = math.cos(angle), math.sin(angle)
        best = None
        near = max_range
        for enemy in self.enemies:
            if not enemy.alive or enemy.kind == "bessie":
                continue
            dx, dy = enemy.x - p.x, enemy.y - p.y
            d = dx * ax + dy * ay
            z = p.eye + d * slope
            feet = enemy.z + self.world.elevation(enemy.x, enemy.y)
            if (0 < d < near and abs(dx * ay - dy * ax) < enemy.radius + spread
                    and feet - .10 < z < feet + enemy.height + .10
                    and self.world.visible(p.x, p.y, enemy.x, enemy.y, p.eye, z)):
                best, near = enemy, d
        drum = None
        for x, y in self.drums:
            dx, dy = x - p.x, y - p.y
            d = dx * ax + dy * ay
            base = self.world.elevation(x, y)
            z = p.eye + d * slope
            if (0 < d < near and abs(dx * ay - dy * ax) < .24 + spread
                    and base <= z <= base + 1.10 and self.world.visible(p.x, p.y, x, y, p.eye, z)):
                drum, near = (x, y), d
        scenery = None
        for prop in self.world.scenery:
            if self.scenery_used(prop):
                continue
            dx,dy = prop.x-p.x,prop.y-p.y
            d = dx*ax+dy*ay
            height = p.eye+d*slope
            base = self.world.elevation(prop.x,prop.y)+prop.z
            if (0<d<near and abs(dx*ay-dy*ax)<prop.radius+spread
                    and base-.08<height<base+prop.height+.08
                    and self.world.visible(p.x,p.y,prop.x,prop.y,p.eye,height)):
                scenery,near = prop,d
        if scenery is not None:
            self.hit_scenery(scenery)
            return True
        if drum is not None:
            self.drum_hit(drum, amount)
            return True
        if best:
            best.hurt(amount, self, pressure=pressure)
            return True
        if spark:
            steps = math.ceil(max_range / .105)
            for i in range(1, steps + 1):
                d = i * max_range / steps
                x,y,z = p.x+ax*d,p.y+ay*d,p.eye+d*slope
                ix = max(0,min(int(x),self.world.solid.shape[1]-1))
                iy = max(0,min(int(y),self.world.solid.shape[0]-1))
                floor_z,roof_z = self.world.ground[iy,ix],self.world.roof[iy,ix]
                surface_tile = (self.world.floor[iy,ix] if z<floor_z else
                                self.world.ceiling[iy,ix] if 0<roof_z<z else None)
                if surface_tile is not None or self.world.blocked(x, y, .024, z):
                    pane = self.world.pane_at(x,y,z,.025)
                    if pane:
                        self.shatter(pane,z)
                        return True
                    mark = None if surface_tile is not None else self.renderer.wall_mark(p.x,p.y,p.eye,ax,ay,slope,d)
                    if mark:
                        surface = mark.material
                    else:
                        tile = self.world.solid[iy,ix]
                        if surface_tile is None and tile<0:
                            tile = next((door.material for door in self.world.near_doors.get((ix,iy),())
                                         if door.blocks(x,y,.024)),self.world.floor[iy,ix])
                        surface = impact_surface(int(tile if surface_tile is None else surface_tile))
                    if mark is not None and self.armory.active in (REVOLVER,RIFLE,SHOTGUN):
                        self.wall_marks.append(mark)
                        if len(self.wall_marks)>38:
                            self.wall_marks.pop(0)
                    d = (i - .70) * max_range / steps
                    x, y = p.x + ax * d, p.y + ay * d
                    if len(self.specks)<144:
                        particle,speed={"wood":("chips",.64),"metal":("spark",1.21),
                                        "plaster":("powder",.53),"dirt":("soil",.48)}[surface]
                        self.burst(x,y,max(.04,min(1.8,p.eye+d*slope)),particle,3,speed)
                    if self.armory.active in (REVOLVER,RIFLE,SHOTGUN,RIVETER,PRESSURE) and self.clock>=self.wall_sound:
                        self.wall_sound=self.clock+.08
                        cue = {"wood":"impact_wood","metal":"ricochet",
                               "plaster":"impact_plaster","dirt":"impact_dirt"}[surface]
                        cue = {RIVETER:"impact_rivet",PRESSURE:"impact_pressure"}.get(self.armory.active,cue)
                        self.sound_at(cue,x,y,.64)
                    break
        return False

    def assisted_aim(self, angle, slope):
        if not self.aim_assist:
            return angle,slope
        p = self.player
        threshold = .047 if self.aim_assist == 2 else .025
        best = math.inf
        correction = None
        for e in self.enemies:
            if not e.hostile or not e.alive:
                continue
            dx,dy = e.x-p.x,e.y-p.y
            distance = math.hypot(dx,dy)
            if not .46 < distance < 18.:
                continue
            yaw = math.atan2(dy,dx)
            error = abs((yaw-angle+math.pi)%math.tau-math.pi)
            if error > threshold:
                continue
            target = self.world.elevation(e.x,e.y)+e.z+e.height*.58
            vertical = (target-p.eye)/distance
            if abs(vertical-slope) > .19:
                continue
            score = error*12+abs(vertical-slope)*.4+distance*.009
            if score < best and self.world.visible(p.x,p.y,e.x,e.y,p.eye,target):
                correction = (yaw if self.aim_assist == 2 else angle,vertical)
                best = score
        return correction if correction is not None else (angle,slope)

    def shatter(self, pane, z=.99):
        if pane in self.world.broken_panes:
            return
        self.world.broken_panes.add(pane)
        x,y = pane[0]+.5,pane[1]+.5
        self.sound_at("glass_break",x,y,.96)
        self.burst(x,y,min(1.6,max(.38,z)),"glass",17,1.95)
        self.disturb(x,y,6.8,min(1.6,max(.38,z)))

    def burst(self, x, y, z, kind, count, speed):
        if kind=="gore" and not self.gore:
            return
        for _ in range(count):
            angle = self.rng.random() * math.tau
            v = self.rng.uniform(.24, speed)
            self.specks.append(Speck(x, y, z, math.cos(angle) * v, math.sin(angle) * v,
                                     self.rng.uniform(.2, speed * 1.3), self.rng.uniform(.18, .68), kind))

    def drum_hit(self, point, damage):
        if point not in self.drums:
            return
        self.drums[point] -= damage
        x, y = point
        z = self.world.elevation(x, y) + .57
        if self.drums[point] <= 0:
            del self.drums[point]
            self.explode(Shot(x, y, z, 0., 0., 0., "fuel", 0., False, 0))
        else:
            self.sound_at("ricochet", x, y, .6)
            self.burst(x, y, z, "spark", 4, .8)

    def explode(self, shot):
        x, y, z = shot.x, shot.y, max(.07, shot.z)
        energy = shot.kind == "arm_bolt"
        radius, strength = (1.40, shot.damage) if energy else (2.8, 125 if shot.kind == "fuel" else 160)
        if shot.kind == "bottle_rocket":
            radius, strength = 1.72, shot.damage
        elif shot.kind == "keg":
            radius, strength = 3.7, 240
        elif shot.kind == "cow":
            radius, strength = 2.3, shot.damage
            self.sound_at("cow_moo",x,y,.9)
        self.blast_flash = max(self.blast_flash, .14 if energy else .27)
        self.duck = max(self.duck, 1.1 if not energy else .5)
        self.blasts.append(Blast(x, y, z, kind="energy" if energy else "fire"))
        cue = "arm_impact" if energy else "rocket_pop" if shot.kind=="bottle_rocket" else "explosion"
        self.sound_at(cue,x,y)
        self.burst(x, y, z, "plasma" if energy else "spark", 12 if energy else 23, 2.2 if energy else 3.3)
        self.burst(x, y, z, "dust", 6 if energy else 16, 2.3)
        self.wake_nearby(8. if energy else 16., x, y)
        if not energy:
            self.disturb(x,y,3.5,z)
        for enemy in self.enemies:
            distance = math.hypot(enemy.x - x, enemy.y - y)
            if enemy.alive and distance < radius and self.world.visible(x, y, enemy.x, enemy.y):
                enemy.hurt(max(1, int(strength * (1 - distance / (radius + .3)))), self, not energy)
        for prop in self.world.scenery:
            if (math.hypot(prop.x-x,prop.y-y)<radius
                    and self.world.visible(x,y,prop.x,prop.y)):
                self.hit_scenery(prop)
        p = self.player
        distance = math.hypot(p.x - x, p.y - y)
        if distance < radius * .75 and self.world.visible(x, y, p.x, p.y):
            self.damage(max(2,int((13 if energy else 30)*(1-distance/(radius*.75)))),
                        (x,y),"BLAST" if shot.enemy or shot.kind=="fuel" else "BACKBLAST")
        if not energy:
            for pane in self.world.pane_tiles:
                if math.hypot(pane[0]+.5-x,pane[1]+.5-y) < 2.0:
                    self.shatter(pane)
            for tx, ty in tuple(self.drums):
                if math.hypot(tx - x, ty - y) < 2.2 and self.world.visible(x, y, tx, ty):
                    self.drum_hit((tx, ty), 20)
            for door in self.world.doors:
                if ((self.level.rescue or door.blast_only) and shot.kind != "bottle_rocket" and door.secret and not door.opened
                        and math.hypot(door.center[0] - x, door.center[1] - y) < 1.27):
                    self.toggle_door(door, True)

    def scenery_used(self, prop):
        return prop.id in self.scenery_spent or prop.station in self.stations_done

    def hit_scenery(self, prop):
        if self.scenery_used(prop):
            return
        self.scenery_spent.add(prop.id)
        cue,particle,count = REACTIONS[prop.kind]
        height = self.world.elevation(prop.x,prop.y)+prop.z+prop.height*.51
        self.sound_at(cue,prop.x,prop.y,.72)
        if prop.kind in ("pipe","belt","cans","bottles"):
            self.disturb(prop.x,prop.y,5.2,height)
        if prop.id in RUPTURES:
            vent_x,vent_y,warning = RUPTURES[prop.id]
            self.add_hazard("steam",vent_x,vent_y,.48,.66,2.20,8)
            self.sound_at("pressure_vent",vent_x,vent_y,.52)
            self.message(warning,2.2)
        self.burst(prop.x,prop.y,height,particle,count,1.1)
        if prop.opens:
            for door in self.world.doors:
                if (door.x,door.y) in prop.opens:
                    self.toggle_door(door,True)
            self.message("THE SERVICE CUT IS OPEN.",2.8)
        if prop.station:
            self.activate_station(next(station for station in self.world.stations if station.id==prop.station))

    def finish_shot(self, shot):
        if shot.kind in ("bolt", "arm_bolt", "tnt", "bottle_rocket", "keg", "cow"):
            self.explode(shot)
        elif shot.kind == "football":
            self.burst(shot.x, shot.y, shot.z, "dust", 8, 1.3)
            self.sound_at("football_bounce", shot.x, shot.y)
        elif shot.kind == "chalk_lob":
            self.add_hazard("chalk",shot.x,shot.y,.89,.08,2.75,6)
            self.sound_at("chalk_pop",shot.x,shot.y,.67)
        elif shot.kind == "fair_bottle":
            self.burst(shot.x,shot.y,shot.z,"glass",13,1.7)
            self.sound_at("tosser_glass",shot.x,shot.y,.8)
            p = self.player
            if (p.air<.27 and math.hypot(p.x-shot.x,p.y-shot.y)<.77
                    and self.world.visible(shot.x,shot.y,p.x,p.y,shot.z,p.eye)):
                self.damage(10,(shot.x,shot.y),"GLASS")
        elif shot.kind in ("deputy_slug","chain_hook","valve_slug"):
            self.burst(shot.x,shot.y,shot.z,"spark" if shot.kind=="chain_hook" else "dust",3,.75)

    def move_shot(self, shot, dt):
        # Small swept steps catch narrow doors, shallow floors and fast enemies.
        distance = math.sqrt(shot.vx**2 + shot.vy**2 + shot.vz**2) * dt
        steps = max(1, math.ceil(distance / .09))
        dt /= steps
        gravity = {"bolt": 2.2, "football": 2.4, "tnt": 6.9, "chalk_lob":4.2,"fair_bottle":5.5,"keg":5.0,"cow":1.8}.get(shot.kind, 0.)
        tnt = shot.kind == "tnt"
        for _ in range(steps):
            shot.life -= dt
            if shot.life <= 0:
                self.finish_shot(shot)
                return False
            if shot.resting:
                continue
            x = shot.x + shot.vx * dt
            y = shot.y + shot.vy * dt
            z = shot.z + shot.vz * dt
            shot.vz -= dt * gravity
            wall = self.world.blocked(x, y, .045, z)
            if wall and not shot.enemy and not tnt:
                pane = self.world.pane_at(x,y,z,.045)
                if pane:
                    self.shatter(pane,z)
                    wall = self.world.blocked(x,y,.045,z)
            roof = self.world.roof[int(y), int(x)] if not wall else 0.
            plane = not wall and (z < self.world.elevation(x, y) + .045 or (0. < roof <= z + .045))
            if wall or plane:
                if tnt and (shot.bounces <= 0 or (plane and abs(shot.vz) < .77 and not wall)):
                    shot.vx = shot.vy = shot.vz = 0.
                    shot.resting = True
                    continue
                if shot.bounces <= 0:
                    self.finish_shot(shot)
                    return False
                if wall:
                    across_x = self.world.blocked(x, shot.y, .045, z)
                    across_y = self.world.blocked(shot.x, y, .045, z)
                    if across_x or not across_y:
                        shot.vx *= -.57 if tnt else -.86
                    if across_y or not across_x:
                        shot.vy *= -.57 if tnt else -.86
                else:
                    shot.vz *= -.46 if tnt else -.88
                    if tnt:
                        shot.vx *= .64
                        shot.vy *= .64
                shot.bounces -= 1
                self.sound_at("tnt_bounce" if tnt else "saw_bounce", shot.x, shot.y)
                if not tnt:
                    self.burst(shot.x, shot.y, shot.z, "spark", 6, 1.4)
                continue
            travel = math.hypot(x-shot.x,y-shot.y)
            if shot.kind=="bottle_rocket" and shot.travelled<.78<=shot.travelled+travel:
                self.sound_at("rocket_whistle",x,y,.68)
            shot.travelled += travel
            shot.x, shot.y, shot.z = x, y, z
            p = self.player
            ricochet = shot.kind == "blade" and shot.bounces < 3 and shot.travelled > .72
            if ((shot.enemy and shot.kind not in ("chalk_lob","fair_bottle") or ricochet)
                    and math.hypot(p.x - x, p.y - y) < .28
                    and p.eye - (.80 if not p.crouched else .55) < z < p.eye + .32):
                self.damage(shot.damage if shot.enemy else 24,(shot.x-shot.vx*.18,shot.y-shot.vy*.18),
                            "FIRE" if shot.enemy else "RICOCHET")
                self.finish_shot(shot)
                return False
            if shot.enemy or tnt:
                continue
            drum = next(((tx, ty) for tx, ty in self.drums if math.hypot(tx - x, ty - y) < .27
                         and 0 <= z - self.world.elevation(tx, ty) <= 1.07), None)
            if drum is not None:
                self.drum_hit(drum, 25)
                return False
            for enemy in self.enemies:
                if not enemy.alive or enemy.kind == "bessie":
                    continue
                dz = z - enemy.z - self.world.elevation(enemy.x, enemy.y)
                if -.07 < dz < enemy.height + .05 and math.hypot(enemy.x - x, enemy.y - y) < enemy.radius + .10:
                    if shot.kind == "blade":
                        enemy.hurt(shot.damage, self)
                        self.sound_at("saw_hit", x, y)
                    elif shot.kind == "bowling":
                        seen = self.bowled.setdefault(id(shot), set())
                        if id(enemy) not in seen:
                            seen.add(id(enemy))
                            enemy.hurt(shot.damage, self)
                            self.sound_at("bowling_hit", x, y)
                            self.burst(x, y, z, "dust", 6, 1.4)
                            shot.vx *= .8
                            shot.vy *= .8
                    else:
                        self.finish_shot(shot)
                    return False
        return True

    def update_shots(self, dt):
        self.shots = [shot for shot in self.shots if self.move_shot(shot, dt)]
        if self.finale and not self.finale.alive:
            self.shots = [shot for shot in self.shots if shot.kind not in ("foreman_cut","rudy_horn")]
        for speck in self.specks:
            speck.life -= dt
            speck.z += speck.vz * dt
            speck.vz -= dt * 6.
            x, y = speck.x + speck.vx * dt, speck.y + speck.vy * dt
            if not self.world.blocked(x, y):
                speck.x, speck.y = x, y
        self.specks = [speck for speck in self.specks if speck.life > 0 and speck.z >= -.05]
        for blast in self.blasts:
            blast.age += dt
        self.blasts = [blast for blast in self.blasts if blast.age < .64]

    def add_hazard(self,kind,x,y,radius,warning,life,damage):
        if not self.world.blocked(x,y,.04):
            self.hazards.append(Hazard(kind,x,y,radius,warning,life,damage))
            if len(self.hazards)>7:
                self.hazards.pop(0)

    def update_hazards(self,dt):
        p = self.player
        for hazard in self.hazards:
            hazard.age += dt
            if (hazard.warning<=hazard.age<hazard.life and hazard.age>=hazard.next_hit
                    and p.air<.28 and math.hypot(p.x-hazard.x,p.y-hazard.y)<hazard.radius
                    and self.world.visible(hazard.x,hazard.y,p.x,p.y)):
                self.damage(hazard.damage,(hazard.x,hazard.y),"STEAM" if hazard.kind=="steam" else "CHALK")
                hazard.next_hit = hazard.life if hazard.kind=="steam" else hazard.age+.68
        self.hazards = [hazard for hazard in self.hazards if hazard.age<hazard.life]

    def relief_open(self):
        return "relief-west" in self.stations_done or "relief-east" in self.stations_done

    def pressure_ports(self, attacks):
        ports = self.world.pressure_ports
        count = 1 if self.relief_open() else 2
        offset = attacks//2%len(ports) if ports else 0
        return (ports[(offset+i)%len(ports)] for i in range(count) if ports)

    def ground_marks(self):
        p = self.player
        marks = [mark for mark in self.world.dress_marks
                 if (not self.level.rescue or (mark.y>33)==self.in_hub)
                 and (mark.x-p.x)**2+(mark.y-p.y)**2<(196. if mark.image=="fx_shadow" else 90.)]
        if self.in_hub:
            return marks
        def spot(x,y,r,kind):
            return GroundMark(x,y,self.world.elevation(x,y)+.003,0.,r,r,"mark_"+kind)
        marks.extend(spot(h.x,h.y,h.radius,h.kind if h.age>=h.warning else "warning") for h in self.hazards)
        if self.player.y<13:
            marks.extend(spot(x,y,.38,"outlet") for x,y in self.world.pressure_ports)
        for enemy in self.enemies:
            if not enemy.alive or not enemy.windup or not enemy.aim_mark:
                continue
            x,y,_=enemy.aim_mark
            if enemy.kind=="chalk_spitter":
                marks.append(spot(x,y,.89,"warning"))
            elif enemy.kind=="bottle_tosser":
                marks.append(spot(x,y,.77,"warning"))
            elif enemy.kind=="baron" and enemy.attacks%2==0:
                marks.extend(spot(px,py,.94,"warning") for px,py in self.pressure_ports(enemy.attacks))
            elif enemy.kind=="foreman":
                direction=math.atan2(y-enemy.y,x-enemy.x)
                for sx,sy,bearing in enemy.saw_lanes(direction,enemy.attacks+1):
                    length=0.
                    while length<10.0:
                        step=length+.32
                        if self.world.blocked(sx+math.cos(bearing)*step,sy+math.sin(bearing)*step,.03):
                            break
                        length=step
                    if length>.4:
                        hx,hy=sx+math.cos(bearing)*length/2,sy+math.sin(bearing)*length/2
                        marks.append(GroundMark(hx,hy,self.world.elevation(sx,sy)+.003,
                                                bearing,length/2,.30,"mark_lane"))
        nearby = sorted((distance, i, enemy) for i,enemy in enumerate(self.enemies) if enemy.alive
                        and (distance := (enemy.x-p.x)**2+(enemy.y-p.y)**2)<64.)
        for _,_,enemy in nearby[:6]:
            radius = enemy.radius*(1.03 if enemy.z<=.02 else 1.28)
            marks.append(GroundMark(enemy.x,enemy.y,self.world.elevation(enemy.x,enemy.y)+.003,
                                    enemy.angle,radius*1.24,radius,"fx_shadow"))
        return marks

    def tick_exchanges(self, combat):
        if not self.exchanges or (not self.voice_captions and not self.sound.voice_gain):
            return
        if combat or self.won:
            if self.caption_until > self.clock or self.exchange_pending:
                self.sound.stop_voice()
                self.caption_until = 0.
                self.exchange_pending = None
            self.exchange_next = self.clock+3.5
            return
        if self.clock < self.exchange_next:
            return
        self.exchange_next = self.clock+.55
        pending = self.exchange_pending
        self.exchange_pending = None
        for exchange in (pending,) if pending else self.exchanges:
            if exchange.stop_at in self.stations_done or (not pending and exchange.id in self.heard_exchanges):
                continue
            p = self.player
            if (math.hypot(p.x-exchange.x,p.y-exchange.y)>4.25
                    or not self.world.visible(p.x,p.y,exchange.x,exchange.y,p.eye,
                                              self.world.elevation(exchange.x,exchange.y)+.95)):
                continue
            index = int(pending is not None)
            gain,pan = self.sound_position(exchange.x,exchange.y,.74,muffle=False)
            length = self.sound.play_voice(f"talk_{exchange.id}_{index}",gain,pan)
            self.caption = exchange.lines[index]
            self.caption_until = self.clock+max(1.35,length+.15)
            if pending is None:
                self.heard_exchanges.add(exchange.id)
                self.exchange_pending = exchange
                self.exchange_next = self.caption_until+.18
            else:
                self.exchange_next = self.caption_until+8.
            break

    def tick(self, dt, controls):
        p = self.player
        if self.showing_tally or p.health <= 0 or self.portal_request:
            self.sound.set_fuse(False)
            self.sound.set_tool(False)
            self.sound.stop_voice()
            return
        self.clock += dt
        self.duck = max(0., self.duck - dt)
        sp = getattr(self.sound, "score_player", None)
        if sp is not None:
            sp.level(self.sound.music_gain * (1 - .5 * min(1., self.duck) - (.2 if self.barks.visible(self) else 0.)))
        self.hurt_flash = max(0, self.hurt_flash - dt)
        self.blast_flash = max(0, self.blast_flash - dt)
        p.gut = max(0., p.gut - dt * .40)
        p.drunk = max(0., p.drunk - dt * (2.4 if self.sprint else .77))
        self.sprint = max(0., self.sprint - dt)
        intoxication = max(0., (p.drunk - 23) / 77)
        if p.gut >= 66 and self.clock >= self.next_belch:
            self.next_belch = self.clock + 5.6
            self.sound.play("belch", .76)
            self.wake_nearby(5.7, p.x, p.y)
        if p.drunk > 62:
            self.barks.say(self, "drunk")
        p.sway = math.sin(self.clock * 3.15) * intoxication * 11
        p.drift = math.sin(self.clock * 2.3) * intoxication**2 * .12
        p.angle = (p.angle + controls.turn) % math.tau
        p.pitch = max(-53, min(53, p.pitch + controls.look))
        forward = controls.forward
        strafe = controls.strafe + (math.sin(self.clock * 4.) * .39 if p.drunk > 82 else 0.)
        magnitude = max(1., math.hypot(forward, strafe))
        speed = (3.85 if controls.running else 2.75) * (1.42 if self.sprint else 1.) / magnitude
        speed *= 1 - max(0., p.gut - 65) * .004 - max(0., p.drunk - 70) * .004
        if SURFACE_SOUNDS.get(self.world.floor[int(p.y), int(p.x)]) == "water":
            speed *= .69
        p.crouched = controls.crouch and p.air <= .01
        if p.crouched:
            speed *= .51
        vx, vy = math.cos(p.view_angle), math.sin(p.view_angle)
        ox, oy = p.x, p.y
        response = 1 - math.exp(-dt * (7 if p.air else 23 if forward or strafe else 30))
        p.vx += (speed * (forward * vx - strafe * vy) - p.vx) * response
        p.vy += (speed * (forward * vy + strafe * vx) - p.vy) * response
        self.move_actor(p, p.vx * dt, p.vy * dt, PLAYER_RADIUS)
        if p.x == ox and abs(p.vx) > .02:
            p.vx = 0.
        if p.y == oy and abs(p.vy) > .02:
            p.vy = 0.
        if controls.jump and not p.jump_held and p.air == 0. and not controls.crouch:
            p.vertical_speed = 2.7
        p.jump_held = controls.jump
        landed = False
        if p.air > 0 or p.vertical_speed > 0:
            p.air = max(0., p.air + p.vertical_speed * dt)
            p.vertical_speed -= dt * 9.2
            if p.air == 0:
                p.vertical_speed = 0.
                landed = True
        ground = self.world.elevation(p.x, p.y)
        eye = (.68 if p.crouched else .95) + ground + p.air
        roof = self.world.roof[int(p.y), int(p.x)]
        if roof and eye > roof - .22:
            eye = roof - .22
            p.vertical_speed = min(0., p.vertical_speed)
        p.eye += (eye - p.eye) * min(1, dt * 17)
        p.motion = min(1., math.hypot(p.x - ox, p.y - oy) / max(dt * 2, .0001))
        if p.air == 0:
            p.walk_phase += dt * 11 * p.motion * (1.25 if controls.running else .80 if p.crouched else 1.)
        p.bob = math.sin(p.walk_phase * 2) * p.motion * (0 if p.air else 1.9) * self.bob_scale
        iy, ix = int(p.y), int(p.x)
        area = self.world.area[iy, ix]
        ambience = self.level.ambience
        if ambience == "mill" and ("relay" in self.stations_done
                                  or (not roof and math.hypot(p.x-24.3,p.y-6.7)>13)):
            ambience = "mill_bank"
        elif ambience=="quarry":
            ambience = "quarry_after" if "bottling" in self.stations_done else "quarry_line" if roof else "quarry"
        elif ambience=="fair" and "broadcast" in self.stations_done:
            ambience = "fair_after"
        recovery = RECOVERY_ROOMS.get(self.level.id)
        if recovery and ambience not in ("quarry_after","fair_after"):
            left,top,right,bottom,bed = recovery
            if left<=p.x<=right and top<=p.y<=bottom:
                ambience = bed
        self.sound.set_room(ambience or
                            ("creek" if area == 9 else "barn" if area == 4 else "room" if roof else "yard"))
        if self.clock >= self.radio_check:
            self.radio_check = self.clock+.045
            if self.level.rescue and self.jukebox_on and math.hypot(p.x-7.26,p.y-17.14) < 11.:
                volume,pan = self.sound_position(7.26,17.14,.60)
                self.sound.set_radio(True,volume,pan)
            else:
                self.sound.set_radio(False)
        if area != self.district and p.motion > .15:
            self.district = area
            self.district_until = self.clock + 2.1
        if self.clock >= self.amb_clock:
            self.amb_clock = self.clock + 5.9
            if self.world.distant_cues:
                for x, y, cue in self.world.distant_cues:
                    if math.hypot(p.x-x, p.y-y) < 10.:
                        if ((cue=="distant_mill_pump" and "relay" in self.stations_done)
                                or (cue in ("distant_quarry_bottler","distant_quarry_pipe")
                                    and "bottling" in self.stations_done)
                                or (cue in ("distant_fair_motif","distant_fair_generator")
                                    and "broadcast" in self.stations_done)):
                            continue
                        if cue == "distant_fair_pa":
                            if ("broadcast" in self.stations_done or math.hypot(p.x-x,p.y-y) > 5.
                                    or not self.world.visible(p.x,p.y,x,y) or self.clock < self.message_until):
                                continue
                            self.message("PA: WINNERS MUST FEED THEIR PRIZES.", 3.5)
                        self.sound_at(cue, x, y, .55)
            elif self.level.rescue and area in (0, 5, 8, 9, 10) and not roof:
                cue = "distant_dog" if area in (0, 8) else "distant_crow"
                self.sound.play(cue, .24, .7 if int(self.clock) % 2 else -.64)
        step = int(p.walk_phase / math.pi)
        if landed or step != self.step_number:
            floor = self.world.floor[iy, ix]
            surface = SURFACE_SOUNDS.get(floor, "gravel")
            self.sound.play(f"step_{surface}_{step % 2}", .77 if landed else .31 if controls.crouch else .55)
            if surface == "water":
                self.burst(p.x,p.y,ground+.16,"splash",5 if landed else 3,.52)
            self.step_number = step
        self.visited.add((int(p.x), int(p.y)))
        if self.in_hub:
            return
        for point,(x0,y0,x1,y1) in self.world.discovery_rooms.items():
            if x0<=ix<=x1 and y0<=iy<=y1:
                door=next(door for door in self.world.doors if (door.x,door.y)==point)
                if not door.discovered:
                    self.toggle_door(door,True)
        self.world.update(dt,p,self.enemies)
        remaining = []
        for name, x, y in self.pickups:
            if ((p.x - x)**2 + (p.y - y)**2 >= .43**2
                    or not self.world.visible(p.x, p.y, x, y) or not self.collect(name)):
                remaining.append((name, x, y))
        self.pickups = remaining
        self.armory.tick(dt, self)
        if self.gallery and self.gallery.active:
            self.gallery.tick(dt,self,controls.fire or controls.alt_fire)
        elif controls.fire or controls.alt_fire:
            self.armory.fire(self, controls.alt_fire)
        else:
            self.armory.release_dynamite(self)
        self.sound.set_fuse(bool(self.armory.fuse))
        self.sound.set_tool(self.armory.active==RIPSAW and controls.alt_fire and self.armory.grinding
                            and not self.armory.holstered and not self.armory.reload and p.health>0)
        for enemy in self.enemies:
            enemy.tick(dt, self)
        self.update_shots(dt)
        if self.hazards:
            self.update_hazards(dt)
        self.tick_exchanges(controls.fire or controls.alt_fire or self.hurt_flash>0 or
                            any(enemy.alive and enemy.hostile and (enemy.windup or enemy.recovery)
                                and abs(enemy.x-p.x)<6 and abs(enemy.y-p.y)<6 for enemy in self.enemies))

    def reflection(self):
        if not self.world.mirror:
            return None
        p = self.player
        facing = (math.tau-p.angle)%math.tau-math.pi
        direction = min(4,int(abs(facing)/(math.pi/4)+.5))
        heading = ("front","quarter","side","away","back")[direction]
        stride = round(math.sin(p.walk_phase)) if p.motion>.15 and not p.air else 0
        height = 1.24 if p.crouched else 1.65
        feet = self.world.elevation(p.x,p.y)+p.air
        return Sprite(p.x,p.y,f"player_{heading}_{stride}",height,feet,flip=facing<0 and direction<4)

    def sprites(self):
        sprites = [sprite for sprite in self.props if sprite.y >= 28 and sprite.x < HUB_WIDTH] if self.in_hub else self.props.copy()
        for board in self.world.billboards:
            if (self.in_hub and board.y < 33) or (self.level.rescue and not self.in_hub and board.y >= 34):
                continue
            image = board.image
            if board.signal=="legacy-key":
                if self.legacy_key_route:
                    image = "wing_town_legacy_key"
            elif board.signal:
                active = (self.exit_ready() if board.signal=="exit" else self.won if board.signal=="cleared"
                          else board.signal in self.stations_done)
                image += "_on" if active else "_off"
            z = self.world.elevation(board.x, board.y)+board.z
            sprites.append(Sprite(board.x,board.y,image,board.height,z,board.glow,plane=board.plane))
            if board.back:
                sprites.append(Sprite(board.x,board.y,board.back,board.height,z,plane=board.plane+math.pi))
        sprites.extend(Sprite(x, y, "prop_fuel", 1.04, self.world.elevation(x, y))
                       for x, y in self.drums)
        for sprite in sprites:
            if sprite.image.startswith("prop_windmill_"):
                sprite.image = f"prop_windmill_{int(self.clock * 5) % 3}"
        if self.in_hub:
            x,y=HUB_BOARD
            sprites.append(Sprite(x,y,f"county_dispatch_{self.hub_milestone}",.46,1.02,plane=0.))
            if self.hub_milestone:
                trunk = self.hub_milestone in (2,3)
                prop = "county_dispatch_trunk" if trunk else "county_dispatch_tag"
                sprites.append(Sprite(29.67,44.12,prop,.31 if trunk else .24,.83,plane=0.))
            detail = self.renderer.world_motion
            speed = (1.,.32,0.)[detail]
            dust = [Sprite(x+.11*math.sin(self.clock*speed*.68+y),y,"hub_dust",height,z,
                           translucent=True,plane=0.)
                    for x,y,height,z in ((30.40,46.85,1.46,.19),(30.48,45.95,1.64,.28),
                                         (30.73,44.95,1.48,.37))[:3-detail]]
            dust.sort(key=lambda s: -math.hypot(s.x-self.player.x,s.y-self.player.y))
            sprites.extend(dust)
            return sprites
        for note in NOTES.get(self.level.id,()):
            sprites.append(Sprite(note.x,note.y,"county_note",.23,
                                  self.world.elevation(note.x,note.y)+.90,plane=note.plane))
        if self.gallery:
            sprites.append(Sprite(25.95,32.72,"county_gallery_sign",.51,1.03,plane=0.))
            sprites.append(Sprite(29.90,33.48,"county_gallery_backstop",1.49,.19,plane=math.pi/2))
            if self.gallery.active:
                sprites.append(self.gallery.sprite(self))
        for room in INTERIORS.get(self.level.id,()):
            sprites.append(Sprite(room.x,room.y,f"county_room_{room.art}",room.height,
                                  self.world.elevation(room.x,room.y)+room.z,plane=room.plane))
        for prop in self.world.scenery:
            state = "spent" if self.scenery_used(prop) else "whole"
            sprites.append(Sprite(prop.x,prop.y,f"scenery_{prop.kind}_{state}",prop.height,
                                  self.world.elevation(prop.x,prop.y)+prop.z))
        if self.finale and self.finale.kind=="rudy" and self.finale.alive:
            sprites.extend(Sprite(x,y,"rudy_decoy",1.65,self.world.elevation(x,y),plane=0.)
                           for x,y in self.world.boss_decoys)
        for h in self.hazards:
            if h.age>=h.warning:
                sprites.append(Sprite(h.x,h.y,"fx_"+h.kind+"_mist",.47 if h.kind=="steam" else .32,
                                      self.world.elevation(h.x,h.y)+.03,translucent=True))
        observer = (self.player.x,self.player.y)
        relieved = bool(self.world.pressure_ports) and self.relief_open()
        for enemy in self.enemies:
            sprite = enemy.sprite(observer,relieved)
            if sprite:
                ground = self.world.elevation(sprite.x, sprite.y)
                sprite.z += ground
                sprites.append(sprite)
        for name, x, y in self.pickups:
            hover = .06 + math.sin(self.clock * 3.5 + x) * .035
            sprites.append(Sprite(x, y, "item_" + name, .33, self.world.elevation(x, y) + hover))
        for shot in self.shots:
            if shot.enemy or shot.kind == "tnt" or math.hypot(shot.x - self.player.x, shot.y - self.player.y) > .95:
                name = "blade_" + str(int(shot.travelled * 9) % 3) if shot.kind == "blade" else shot.kind
                if shot.kind == "tnt":
                    name += "_" + str((int(shot.travelled * 12) if not shot.resting else int(shot.life*9)) % 3)
                size = {"keg": .26, "cow": .30, "bowling": .18, "milk": .08, "football": .20, "blade": .15, "arm_bolt": .18, "tnt": .19,
                        "barker_bolt": .24, "lantern_bolt": .18,
                        "fair_bottle":.25,"chain_hook":.17,"valve_slug":.16,"deputy_slug":.10,
                        "bottle_rocket": .22}.get(shot.kind, .14 if shot.enemy else .10)
                sprites.append(Sprite(shot.x, shot.y, "fx_" + name, size, shot.z,
                                      shot.kind in ("plasma", "arm_bolt", "barker_bolt", "lantern_bolt")))
        for fx in self.specks:
            sprites.append(Sprite(fx.x, fx.y, "fx_" + fx.kind, .095, fx.z, fx.kind == "spark"))
        for blast in sorted(self.blasts, key=lambda b: -math.hypot(b.x - self.player.x, b.y - self.player.y)):
            smoke = blast.age >= .27
            age = blast.age - .27 if smoke else blast.age
            frame = min(3, int(age * (11 if smoke else 16)))
            size = .55 + blast.age * 1.3
            z = max(.03, blast.z - size * .43 + blast.age * .63)
            sprites.append(Sprite(blast.x, blast.y, f"fx_{'smoke' if smoke else blast.kind}_{frame}",
                                  size, z, not smoke, translucent=True))
        return sprites

    def objective(self):
        if self.in_hub:
            return "FACE A GATE AND PRESS E OR SPACE"
        if self.revisiting:
            return "COMPLETED / RETURN AT THE ROAD GATE"
        if not self.level.rescue:
            exit = self.world.extraction
            shutdown = next(s for s in self.world.stations if s.id == exit.shutdown)
            primary = tuple(key for key in shutdown.requires if key not in self.world.objective_side_tasks)
            pending = [key for key in primary if key not in self.stations_done]
            if len(pending)==1:
                station = next(station for station in self.world.stations if station.id==pending[0])
                if station.held and station.held not in self.task_items:
                    return "FIND THE PA PATCH LEAD AT THE RAFFLE OFFICE"
                return station.label
            if pending:
                return self.world.control_name
            for station in self.world.stations:
                if station.id in self.world.objective_side_tasks and station.id not in self.stations_done:
                    return station.label
            if shutdown.id not in self.stations_done:
                return shutdown.label
            threats = sum(enemy.alive for enemy in self.wave)
            return f"CLEAR EXIT THREATS: {threats}" if threats else exit.label
        if not self.boss.alive and not self.jerry.alive:
            return "RESCUE BESSIE"
        if self.jerry.alive and not self.jerry.dormant:
            return "PASTURE / BEAT JERRY"
        if "key_steel" in self.keys:
            return "PASTURE / FIND BESSIE"
        if "key_brass" in self.keys:
            return ("BARN / STEEL KEY AT THE FEED SCALE" if self.legacy_key_route
                    else "STEEL KEY / EAST AT THE STOCK REGISTRY")
        return "STANKY'S / BRASS KEY IN DISPATCH"

    def objective_target(self):
        """World point for the HUD objective pin, mirroring objective()'s choice."""
        if self.in_hub or self.revisiting:
            return None
        if not self.level.rescue:
            exit = self.world.extraction
            if exit is None:
                return None
            shutdown = next((s for s in self.world.stations if s.id == exit.shutdown), None)
            if shutdown is None:
                return None
            primary = tuple(key for key in shutdown.requires
                            if key not in self.world.objective_side_tasks)
            pending = [key for key in primary if key not in self.stations_done]
            if len(pending) == 1:
                station = next((s for s in self.world.stations if s.id == pending[0]), None)
                if station and not (station.held and station.held not in self.task_items):
                    return station.x, station.y
            if pending:
                p = self.player
                options = [s for s in self.world.stations if s.id in pending]
                if not options:
                    return None
                near = min(options, key=lambda s: (s.x - p.x) ** 2 + (s.y - p.y) ** 2)
                return near.x, near.y
            for station in self.world.stations:
                if station.id in self.world.objective_side_tasks and station.id not in self.stations_done:
                    return station.x, station.y
            if shutdown.id not in self.stations_done:
                return shutdown.x, shutdown.y
            threats = [enemy for enemy in self.wave if enemy.alive]
            if threats:
                p = self.player
                near = min(threats, key=lambda e: (e.x - p.x) ** 2 + (e.y - p.y) ** 2)
                return near.x, near.y
            return exit.x, exit.y
        if self.boss and getattr(self.boss, "alive", False):
            return self.boss.x, self.boss.y
        if self.jerry and getattr(self.jerry, "alive", False):
            return self.jerry.x, self.jerry.y
        bessie = getattr(self, "bessie", None)
        if bessie is not None and getattr(bessie, "alive", False):
            return bessie.x, bessie.y
        return None

    def gate_prompt(self):
        gate = self.portal_target()
        if gate:
            return self.gate_text(gate)
        clue = self.hub_clue() if self.in_hub else None
        return "E  "+clue[3] if clue else ""

    def feedback(self,screen):
        if not self.in_hub:
            p=self.player
            alert,nearest=None,10.5**2
            for enemy in self.enemies:
                if not (enemy.alive and enemy.windup and enemy.player_seen
                        and (enemy.kind in RANGED or enemy.kind in ("clone","billy","coot"))):
                    continue
                dx,dy=enemy.x-p.x,enemy.y-p.y
                square=dx*dx+dy*dy
                turn=(math.atan2(dy,dx)-p.view_angle+math.pi)%math.tau-math.pi
                if abs(turn)>.70 and square<nearest:
                    alert,nearest=turn,square
            if alert is not None:
                side = "REAR" if abs(alert)>2.41 else "LEFT" if alert<0 else "RIGHT"
                label = "WINDUP " + side
                width = 10+text_width(label,"mini")
                x = (WIDTH-width)//2 if side=="REAR" else 6 if side=="LEFT" else WIDTH-width-6
                self.hud.panel(screen,(x,74,width,14),(40,29,22))
                self.hud.text(screen,label,(x+5,78),"mini",(233,188,111),shadow=False)
        if self.item_feedback:
            name,text,end = self.item_feedback
            if self.clock<end:
                # The first few frames settle upward. Bob zero keeps this anchored.
                y = 102+round(max(0.,end-self.clock-.79)*25*self.bob_scale)
                label = text or ITEM_LABELS[ITEMS.index(name)]
                self.hud.panel(screen,(8,y,29+text_width(label,"mini"),20),(38,27,21))
                icon = pg.transform.scale(self.art.get("item_"+name),(16,16))
                screen.blit(icon,(11,y+2))
                self.hud.text(screen,label,(30,y+7),"mini",(249,205,144),shadow=False)
        if self.damage_feedback:
            heading,cause,end = self.damage_feedback
            if self.clock>=end:
                return
            side = ""
            if heading is not None and cause not in ("BACKBLAST","LIT DYNAMITE","STEAM","CHALK"):
                turn = (heading-self.player.view_angle+math.pi)%math.tau-math.pi
                side = " REAR" if abs(turn)>2.41 else " LEFT" if turn<-.40 else " RIGHT" if turn>.40 else " FRONT"
            self.hud.banner(screen,cause+side,87,color=(244,160,108))

    def draw(self, screen, crosshair=True, grade=None):
        p = self.player
        if self.showing_tally:
            self.hud.intermission(screen, self)
            return
        practice = self.gallery and self.gallery.active
        weapon = self.gallery.pistol if practice else self.armory
        flash = (weapon.flash * 4 + self.blast_flash * .85)*self.flash_scale
        self.renderer.time = self.clock
        marks = self.ground_marks()
        wall_marks = self.wall_marks if self.bullet_marks else ()
        screen.blit(self.renderer.draw(p,self.sprites(),self.reflection(),flash,wall_marks,marks),(0,0))
        if p.health > 0 and not self.in_hub and (self.weapon_view!=2 or self.armory.fuse):
            weapon.draw(screen,self.art,p,self.world.light[int(p.y),int(p.x)],
                        self.bob_scale,self.flash_scale,12 if self.weapon_view==1 else 0)
        if self.hurt_flash and self.flash_scale:
            overlay = pg.Surface((WIDTH, VIEW), pg.SRCALPHA)
            overlay.fill((131, 27, 17, round(self.hurt_flash * 310*self.flash_scale)))
            screen.blit(overlay, (0, 0))
        if p.drunk >= 38 and self.flash_scale:
            drunk_warp(screen.subsurface((0,0,WIDTH,VIEW)), p.drunk, self.clock)
        if self.retro_look and self.flash_scale:
            look_pass(screen.subsurface((0,0,WIDTH,VIEW)), self.level.id, self.clock,
                      bool(self.world.roof[int(p.y),int(p.x)]), self.flicker and self.flash_scale==1.,
                      self.blast_flash)
        if grade:
            grade(screen.subsurface((0,0,WIDTH,VIEW)))
        if p.health > 0:
            if crosshair == 2:
                pg.draw.circle(screen,(188,168,132),(160,VIEW//2),4,1)
            elif crosshair:
                screen.set_at((160, VIEW // 2), (188, 168, 132))
            after_notice=5
            if not self.map:
                if practice:
                    after_notice=self.hud.banner(screen,self.gallery.hud(),5)+3
                elif self.message_until > self.clock and (self.hints or self.notice != self.level.introduction):
                    after_notice=self.hud.banner(screen,self.notice,5)+3
                elif self.district_labels and self.district_until > self.clock:
                    after_notice=self.hud.banner(screen,self.level.districts[self.district],5,color=(245,196,122))+3
                boss = self.finale or (self.jerry if self.jerry and self.jerry.alive else self.boss)
                in_finale = boss and (math.hypot(boss.x-p.x,boss.y-p.y)<14. if self.finale else p.y<10)
                if in_finale and boss.alive and boss.alerted and not self.in_hub:
                    y=after_notice
                    tell = TELLS.get(boss.kind,"PLASMA CHARGE" if boss is self.boss else "WHISTLE")
                    if boss.kind=="baron" and boss.attacks%2:
                        tell="STEAM SWEEP"
                    if boss.kind=="foreman" and boss.attacks%2:
                        tell="GAP IN THE MIDDLE"
                    if boss.kind=="rudy":
                        tell="LEFT HORN" if boss.attacks%2 else "RIGHT HORN"
                    phase = tell if boss.windup else "RECOVERING" if boss.recovery > .16 else ""
                    self.hud.panel(screen,(193,y,122,27 if phase else 20),(35,24,20),(126,85,57))
                    self.hud.text(screen,BOSS_TITLES[boss.kind],(253,y+3),center=True,shadow=False)
                    pg.draw.rect(screen,(70,42,32),(199,y+12,110,4))
                    pg.draw.rect(screen,(236,143,69) if boss.windup > 0 else (204,77,47),
                                 (199,y+12,round(110*boss.hp/boss.max_hp),4))
                    if phase:
                        self.hud.text(screen,phase,(253,y+19),"mini",(249,194,124),center=True,shadow=False)
            if not self.map and not self.armory.fuse:
                hint = self.gate_prompt() or (self.use_prompt() if self.hints and not self.in_hub else "")
                if hint:
                    self.hud.banner(screen,hint,137,color=(251,207,142))
                if self.voice_captions and self.caption_until > self.clock:
                    self.hud.banner(screen,self.caption,121 if hint else 137,color=(209,221,179))
                elif self.barks.visible(self) and not hint:
                    self.hud.banner(screen,"\""+self.barks.text+"\"",137,color=(255,214,150))
            if not self.map:
                self.feedback(screen)
        else:
            self.hud.panel(screen,(27,54,266,52),(43,26,22))
            self.hud.text(screen,"YOU BOUGHT THE FARM",(160,64),"heading",center=True)
            self.hud.text(screen,"ENTER CROSSROADS  /  ESC TITLE" if self.revisiting else
                          "ENTER RETRY  /  F9 QUICKLOAD  /  ESC TITLE",(160,90),center=True)
        if self.map and p.health > 0:
            self.automap(screen)
        self.hud.draw(screen, self, weapon)

    def automap(self, screen):
        rooms = dict(self.level.hidden_rooms)
        height, width = self.world.solid.shape
        start_y = 33 if self.in_hub else 0
        if self.level.rescue:
            height = height - start_y if self.in_hub else 34
        if self.in_hub:
            width = HUB_WIDTH
        scale_x, scale_y = min(4, 208 / width), min(3, 102 / height)
        left = (246 - width * scale_x) / 2
        def tile_rect(x, y):
            x0 = round(left+x*scale_x)
            y0 = round(5+(y-start_y)*scale_y)
            x1 = round(left+(x+1)*scale_x)
            y1 = round(5+(y-start_y+1)*scale_y)
            return x0,y0,max(1,x1-x0),max(1,y1-y0)
        signature = tuple((door.x,door.y) for door in self.world.doors if door.secret and not door.discovered)
        if self.map_panel is None or self.map_signature != signature:
            base = pg.Surface((246,149),pg.SRCALPHA)
            base.fill((30,24,19,251))
            pg.draw.rect(base,(149,117,81),base.get_rect(),1)
            concealed = set(signature)
            for key in signature:
                x0,y0,x1,y1=rooms[key]
                concealed.update((x,y) for x in range(x0,x1+1) for y in range(y0,y1+1))
            for y in range(start_y, start_y + height):
                for x in range(width):
                    if self.world.solid[y,x] < 0 and (x,y) not in concealed:
                        color = (74,86,76) if not self.world.roof[y,x] else (104,85,66)
                        if SURFACE_SOUNDS.get(self.world.floor[y,x]) == "water":
                            color=(67,104,106)
                        pg.draw.rect(base,color,tile_rect(x,y))
            self.map_signature,self.map_panel=signature,base
        panel=self.map_panel.copy()
        for x,y in self.visited:
            if 0 <= x < width and start_y <= y < start_y + height:
                pg.draw.rect(panel,(152,120,75),tile_rect(x,y))
        for door in self.world.doors if not self.in_hub else ():
            if not door.secret or door.discovered:
                color = (110, 120, 88) if door.opened else (200, 119, 56) if door.key else (146, 112, 77)
                pg.draw.rect(panel, color, tile_rect(door.x, door.y))
        if self.in_hub:
            labels = ((GATE_LABELS[gate.destination],gate.x,gate.y,gate not in self.world.locked_gates)
                      for gate in self.world.hub_gates)
            for clue,x,y,_,_ in self.world.hub_clues:
                if clue in self.hub_findings:
                    cx,cy=tile_rect(x,y)[:2]
                    pg.draw.polygon(panel,(200,173,111),((cx,cy-3),(cx+3,cy),(cx,cy+3),(cx-3,cy)))
        else:
            labels = ((label,x,y,True) for label,x,y in self.level.map_labels)
        for label, x, y, open_gate in labels:
            at=tile_rect(x,y)[:2]
            left_edge=at[0]-text_width(label)//2 if self.in_hub else at[0]
            pg.draw.rect(panel,(35,27,22),(left_edge-2,at[1]-1,text_width(label)+4,9))
            self.hud.text(panel,label,(left_edge,at[1]),color=(244,223,185) if open_gate else (185,123,85),shadow=False)
        for station in self.world.stations:
            if not station.reveals_secret and (not station.hidden or station.id in self.stations_done):
                x,y=tile_rect(station.x,station.y)[:2]
                color=(151,187,110) if station.id in self.stations_done else (230,163,83)
                pg.draw.rect(panel,color,(x-2,y-2,4,4))
        if self.world.extraction:
            x,y=tile_rect(self.world.extraction.x,self.world.extraction.y)[:2]
            pg.draw.circle(panel,(151,187,110) if self.exit_ready() else (170,103,82),(x,y),3,1)
        x, y = left + self.player.x * scale_x, 5 + (self.player.y-start_y) * scale_y
        pg.draw.circle(panel, (235, 154, 78), (x, y), 2)
        pg.draw.line(panel, (235, 154, 78), (x, y),
                     (x + math.cos(self.player.angle) * 6, y + math.sin(self.player.angle) * 6), 1)
        pg.draw.line(panel,(120,87,59),(11,109),(234,109))
        self.hud.text(panel,self.objective() if self.hints else self.level.title,(123,116),
                      color=(248,199,127),center=True)
        footer = (f"ROAD NOTES {len(self.hub_findings)}/{len(self.world.hub_clues)}   /   TAB TO CLOSE"
                  if self.in_hub else f"SECRETS {self.secrets}/{self.total_secrets}   /   TAB TO CLOSE")
        self.hud.text(panel,footer,(123,132),center=True)
        screen.blit(panel, (37, 5))

