"""Hickston's townsfolk, flying pests and the pasture bosses."""
from dataclasses import dataclass
import math

from engine import Sprite

# Health, speed, collision radius, height, hostility.
KINDS = {
    "clone": (60, 1.25, .26, 1.55, True),
    "billy": (70, 1.40, .28, 1.58, True),
    "coot": (53, 1.06, .22, 1.51, True),
    "skeeter": (36, 2.55, .20, .46, True),
    "alien": (91, 1.40, .28, 1.56, True),
    "saucer": (75, 1.55, .32, .45, True),
    "boss": (620, 1.08, .52, 2.24, True),
    "jerry": (720, 1.16, .43, 1.94, True),
    "barker": (80, 1.15, .27, 1.69, True),
    "crawler": (34, 2.01, .21, .58, True),
    "millhand": (98, 1.31, .33, 1.73, True),
    "lantern": (69, 1.20, .28, .78, True),
    "boilerback": (99, .99, .34, 1.77, True),
    "chalk_spitter": (52, 1.43, .24, 1.38, True),
    "yard_deputy": (64, 1.23, .25, 1.63, True),
    "bottle_tosser": (51, 1.31, .23, 1.54, True),
    "chain_hand": (78, 1.03, .29, 1.72, True),
    "valve_rat": (63, 1.20, .26, 1.19, True),
    "rudy": (360, 1.28, .35, 1.85, True),
    "foreman": (420, .91, .42, 1.91, True),
    "baron": (480, .96, .43, 1.96, True),
    "chicken": (11, 1.05, .13, .52, False),
    "pig": (22, .70, .23, .66, False),
    "bessie": (100, 0, .22, .70, False),
}
BOSS_TITLES = {"boss":"ALIEN SHERIFF","jerry":"JERRY JONES","rudy":"RUDY RACKET",
               "foreman":"SPLINTER FOREMAN","baron":"COPPER BARON"}
SIGNATURES = {
    # Reach, stand-off, windup, recovery, cooldown, warning, release.
    "yard_deputy": (7.3,4.1,.61,.52,1.54,"deputy_work","deputy_shot"),
    "bottle_tosser": (7.8,5.5,.73,.50,1.86,"tosser_rattle","tosser_throw"),
    "chain_hand": (4.15,2.9,.82,.74,1.65,"chain_raise","chain_crack"),
    "valve_rat": (7.4,4.2,.67,.60,1.72,"rat_hiss","rat_blow"),
}
RANGED = {"alien","saucer","barker","lantern","chalk_spitter",*SIGNATURES,*BOSS_TITLES}
TELLS = {"rudy":"HORN SWEEP","foreman":"CLEAR THE SAW LANES","baron":"PIPE OUTLETS"}
TURN_CELS = frozenset(("clone","billy","coot","alien","boss","barker","millhand","boilerback",
                       "chalk_spitter","yard_deputy","bottle_tosser","chain_hand","valve_rat",
                       "rudy","foreman","baron"))
FIDGET_CELS = frozenset(("clone","billy","coot"))
RECOVERY_TIMES = {
    "boilerback":.64,"rudy":.75,"foreman":.82,"baron":.91,"boss":.33,"jerry":.38,
    "skeeter":.15,"crawler":.20,"millhand":.20,
    **{kind: spec[3] for kind,spec in SIGNATURES.items()},
}
SHELL_ACTORS = frozenset(("alien","saucer","boss","crawler","lantern","skeeter","valve_rat"))
TOOL_ACTORS = frozenset(("boilerback","foreman","baron","chain_hand","millhand"))
LOSS_RESPONDERS = frozenset(("coot","yard_deputy","bottle_tosser"))
LUNGES = {
    "skeeter": (.22, 2.32, .93, 10, "skeeter_bite", 1.05),
    "crawler": (.25, 2.75, 1.02, 11, "crawler_click", 1.15),
    "millhand": (.24, 2.48, 1.28, 16, "millhand_hit", 1.46),
}
AWAKE = {"clone": "clone_alert", "billy": "billy_alert", "coot": "coot_alert",
         "skeeter": "skeeter", "alien": "alien_alert", "saucer": "saucer_spot",
         "boss": "sheriff_spot", **{kind: spec[5] for kind,spec in SIGNATURES.items()}}
REACH = {"clone": 5.5, "billy": 4.5, "coot": 7.3, "skeeter": 2.15,
         "alien": 8.4, "saucer": 7.6, "boss": 10.0, "jerry": 9.5,
         "barker": 8., "crawler": 2.25, "millhand": 2.15, "lantern": 7.4,
         "boilerback":4.35,"chalk_spitter":8.0,"rudy":10.2,"foreman":10.3,"baron":10.5}
WINDUP = {"clone": (.25, "clone_bolt"), "billy": (.34, "enemy_pump"),
          "coot": (.32, "coot_cock"), "skeeter": (.37, "skeeter_dive"),
          "alien": (.35, "guard_charge"), "saucer": (.56, "saucer_charge"),
          "boss": (.53, "sheriff_siren"), "jerry": (.54, "whistle"),
          "barker": (.63, "barker_wind"), "crawler": (.36, "crawler_click"),
          "millhand": (.60, "millhand_rev"), "lantern": (.48, "lantern_charge"),
          "boilerback":(.78,"boiler_priming"),"chalk_spitter":(.64,"chalk_cough"),
          "rudy":(.86,"rudy_warn"),"foreman":(.95,"foreman_warn"),"baron":(.95,"baron_warn")}
COMFORT = {"clone": 3.1, "billy": 1.7, "coot": 4.8, "skeeter": .95,
           "alien": 4.7, "saucer": 5.0, "boss": 4.45, "jerry": 4.0,
           "barker": 4.1, "crawler": .80, "millhand": 1.30, "lantern": 4.2,
           "boilerback":3.15,"chalk_spitter":5.6,"rudy":6.2,"foreman":6.9,"baron":5.25}
for kind,(reach,comfort,windup,_,_,warning,_) in SIGNATURES.items():
    REACH[kind],COMFORT[kind],WINDUP[kind] = reach,comfort,(windup,warning)


def angle_delta(a, b):
    return (a-b+math.pi) % math.tau-math.pi


@dataclass
class Enemy:
    kind: str
    x: float
    y: float
    timer: float = 0.
    pose: float = 0.
    stun: float = 0.
    alerted: bool = False
    cooldown: float = .75
    angle: float = 0.
    hp: float = 0.
    explosive: bool = False
    gait: float = 0.
    face_left: bool = False
    dormant: bool = False
    windup: float = 0.
    attacks: int = 0
    target: tuple | None = None

    def __post_init__(self):
        self.hp, self.speed, self.radius, self.height, self.hostile = KINDS[self.kind]
        self.max_hp = self.hp
        self.route = ()
        self.route_slot = 0
        self.patrol_pause = 0.
        self.aim_mark = None
        self.recovery = 0.
        self.chase_turn = 0.
        self.see_time = 0.
        self.player_seen = False
        self.last_stride = 0.
        self.pressure_guard = 0.
        self.volley = 0
        self.volley_timer = 0.
        self.volley_angle = 0.
        self.volley_slope = 0.
        self.heard = None
        self.retreat = None
        self.responded = False
        self.hit_flash = 0.
        # Deterministic silhouette jitter keeps same-kind crowds from cloning.
        self.variant = 1. if self.kind in BOSS_TITLES else .94 + ((self.x * 13.1 + self.y * 7.7) % 1.) * .11

    @property
    def alive(self):
        return self.hp > 0 and not self.dormant

    @property
    def z(self):
        if self.kind == "saucer":
            return .76 + .10 * math.sin(self.pose * 2.4)
        if self.kind == "skeeter":
            return (.61 if self.windup or self.recovery else .84) + .13 * math.sin(self.pose * 6.5)
        if self.kind == "lantern":
            return .13 + .09 * math.sin(self.pose * 4.3)
        return 0.

    def wake(self, game, x, y):
        if self.dormant:
            return
        self.target = (x, y)
        self.heard = None
        if not self.alerted:
            self.alerted = True
            self.cooldown = max(.65, self.cooldown)
            if self.hostile and self.kind not in ("boss","jerry"):
                for ally in game.enemies:
                    if (ally is not self and ally.hostile and ally.alive and not ally.alerted and not ally.dormant
                            and math.hypot(ally.x-self.x,ally.y-self.y) < 4.2
                            and game.world.visible(ally.x,ally.y,self.x,self.y)):
                        ally.wake(game,x,y)
            if self.kind in AWAKE:
                game.sound_at(AWAKE[self.kind], self.x, self.y, .9)
            if self.kind=="boss":
                game.message("THE COUNTY SHAKEDOWN / ALIEN SHERIFF",3.5)
                game.sound.sting("shakedown_intro")

    def hurt(self, amount, game, explosive=False, *, pressure=False):
        if not self.alive or self.kind == "bessie":
            return
        was_stunned = self.stun > 0
        self.hp = max(0, self.hp - amount)
        self.hit_flash = min(.18, self.hit_flash + .075 + min(.06, amount * .0016))
        if self.hp > 0 and self.hostile and self.kind not in BOSS_TITLES and amount >= 20:
            away = math.atan2(self.y-game.player.y, self.x-game.player.x)
            game.move_actor(self, math.cos(away)*.10*min(3,amount/30), math.sin(away)*.10*min(3,amount/30), self.radius)
        if (self.hp > 0 and self.hostile and self.kind not in BOSS_TITLES and self.kind not in ("skeeter","saucer","crawler")
                and self.hp < self.max_hp*.22 and not getattr(self,'fled',False) and game.rng.random() < .55):
            self.fled = True
            self.retreat_from(game, game.player.x, game.player.y)
        champion = self.kind in BOSS_TITLES
        interrupt = pressure and not champion and not self.pressure_guard and self.windup > 0
        if interrupt:
            self.pressure_guard = 1.75
            self.stun = .36
            game.sound_at("pressure_interrupt",self.x,self.y,.76)
        elif not pressure:
            self.stun = .065 if champion else .13
        if self.hostile:
            self.wake(game, game.player.x, game.player.y)
            if self.windup and not champion and (interrupt or not pressure and
                    (amount >= 26 or self.kind in ("skeeter","crawler"))):
                self.windup = 0.
                self.aim_mark = None
                self.cooldown = .65 if interrupt else .32
        floor = game.world.elevation(self.x, self.y)
        kind = "plasma" if self.kind in ("alien", "saucer", "boss", "crawler", "lantern") else "gore"
        game.burst(self.x, self.y, floor + self.z + .56 * self.height, kind, 4, .9)
        material = ("shell" if self.kind in SHELL_ACTORS else
                    "tool" if self.kind in TOOL_ACTORS else "cloth")
        if self.alive:
            if self.hostile and amount >= 14 and not was_stunned and not interrupt:
                game.sound_at(f"actor_{material}_pain",self.x,self.y,.47)
            return
        self.explosive = explosive
        game.burst(self.x, self.y, floor + self.z + .5*self.height, kind, 22 if explosive else 9, 2.6 if explosive else 1.5)
        if self.hostile:
            cue = "skeeter_pop" if self.kind == "skeeter" else f"actor_{material}_down"
            game.sound_at(cue,self.x,self.y,.83)
            game.enemy_down(self)
        else:
            game.sound_at("chicken" if self.kind == "chicken" else "pig", self.x, self.y, .9)
            game.burst(self.x, self.y, floor + self.height * .6,
                       "feather" if self.kind == "chicken" else "gore",
                       27 if explosive else 9, 2.8 if explosive else 1.4)

    def advance(self, dt, game, direction, pace=1.):
        x, y = self.x, self.y
        game.move_actor(self, math.cos(direction) * self.speed * dt * pace,
                        math.sin(direction) * self.speed * dt * pace, self.radius)
        moved = math.hypot(self.x - x, self.y - y)
        if moved > .001:
            self.gait += moved * 6
            self.last_stride = self.pose
            self.angle = direction
            if abs(math.cos(direction)) > .38:
                self.face_left = math.cos(direction) < 0
        return moved

    def sidestep(self, dt, game, angle, pace, allow_reverse=True):
        if self.advance(dt, game, angle, pace) > dt * .12:
            return
        if allow_reverse:
            self.advance(dt, game, angle + math.pi, pace*.8)

    def follow(self, dt, game, angle, pace):
        if not self.chase_turn and self.advance(dt, game, angle, pace) > dt*.13:
            return
        bias = 1 if math.sin(self.x*1.3+self.y*.93+self.attacks) >= 0 else -1
        self.chase_turn = self.chase_turn or bias
        for amount in (.61, 1.15, 1.60, -1.03, -1.58):
            if self.advance(dt, game, angle+self.chase_turn*amount, pace*.83) > dt*.15:
                break
        # Clear the avoidance bias once the route ahead opens up again.
        if not game.world.blocked(self.x+.46*math.cos(angle),self.y+.46*math.sin(angle),self.radius):
            self.chase_turn=0.

    def patrol(self, dt, game):
        if not self.route:
            return
        self.patrol_pause -= dt
        if self.patrol_pause > 0:
            return
        x,y = self.route[self.route_slot]
        if math.hypot(x-self.x,y-self.y) < .19:
            self.route_slot = (self.route_slot+1) % len(self.route)
            self.patrol_pause = .5 if self.kind in ("skeeter","saucer") else 1.3
            return
        self.follow(dt,game,math.atan2(y-self.y,x-self.x), .45 if self.kind=="coot" else .55)

    def noise_step(self,dt,game):
        if self.heard is None:
            return False
        x,y,ready,end = self.heard
        if game.clock>=end:
            self.heard = None
            return False
        heading = math.atan2(y-self.y,x-self.x)
        if not self.hostile:
            self.sidestep(dt,game,heading+math.pi,1.55,False)
        else:
            self.angle = heading
            if game.clock>=ready and math.hypot(x-self.x,y-self.y)>.48:
                self.follow(dt,game,heading,.76)
        return True

    def retreat_from(self,game,x,y):
        self.responded = True
        bearing = math.atan2(self.y-y,self.x-x)
        if self.target:
            tx,ty = self.target
            for offset in (0.,.58,-.58,1.08,-1.08):
                dx,dy = math.cos(bearing+offset),math.sin(bearing+offset)
                probe = self.x+dx*.96,self.y+dy*.96
                if (not game.world.blocked(*probe,self.radius)
                        and game.world.visible(self.x,self.y,*probe)
                        and not game.world.visible(tx,ty,*probe)):
                    # Keep the persisted retreat vector as a point behind us.
                    x,y = self.x-dx*.42,self.y-dy*.42
                    break
        self.retreat = x,y,game.clock+1.20

    def tick(self, dt, game):
        if not self.alive or self.kind == "bessie":
            return
        self.pose += dt
        self.stun = max(0., self.stun - dt)
        self.recovery = max(0.,self.recovery-dt)
        self.pressure_guard = max(0.,self.pressure_guard-dt)
        self.hit_flash = max(0., self.hit_flash - dt)
        if self.volley:
            self.volley_timer -= dt
            if self.volley_timer <= 0.:
                deputy = self.kind=="yard_deputy"
                sweep = 1 if self.attacks%2 else -1
                bearing = self.volley_angle + (.023 if deputy else sweep*(.153 - self.volley*.061))
                ground = game.world.elevation(self.x,self.y)
                x,y = self.x+math.cos(bearing)*.42,self.y+math.sin(bearing)*.42
                z = ground+(.91 if deputy else 1.30)
                if not game.world.blocked(x,y,.045,z):
                    game.launch(x,y,z,bearing,8.4 if deputy else 6.8,
                                "deputy_slug" if deputy else "rudy_horn",vz=self.volley_slope,enemy=True,damage=8)
                if deputy:
                    game.sound_at("deputy_shot",self.x,self.y,.82)
                self.volley -= 1
                self.volley_timer += .078
            return
        p = game.player
        dx, dy = p.x - self.x, p.y - self.y
        distance = math.hypot(dx, dy)
        direction = math.atan2(dy, dx)
        if not self.hostile:
            if self.noise_step(dt,game):
                return
            self.timer -= dt
            if self.timer <= 0:
                self.timer = game.rng.uniform(.7, 2.1)
                self.angle += game.rng.uniform(-1.9, 1.9)
            shy = 2.2 if self.kind=="chicken" else 1.35
            if distance < shy:
                self.angle = direction + math.pi
            elif self.kind=="pig" and self.timer > 1.05:
                return
            if self.advance(dt, game, self.angle, 1.42 if distance < shy else .72) < .0003:
                self.angle += math.pi * .71
            return

        self.cooldown -= dt
        eye = game.world.elevation(self.x, self.y) + self.z + min(.92, self.height * .72)
        self.see_time -= dt
        if self.see_time <= 0 or 0 < self.windup <= dt:
            self.see_time = .079 + (self.radius-.2)*.051
            self.player_seen = distance < 14. and game.world.visible(self.x,self.y,p.x,p.y,eye,p.eye)
        can_see = self.player_seen and distance < 14.
        aggro_range = (5.5 if p.crouched else 8.4) + 2.2 * (p.gut >= 66)
        if self.kind in ("skeeter","saucer"):
            aggro_range += .9
        watching = abs(angle_delta(direction,self.angle)) < 1.55 or distance < 2.65
        if can_see and (self.alerted or distance < aggro_range and watching):
            self.wake(game, p.x, p.y)
        if not self.alerted:
            if not self.noise_step(dt,game):
                self.patrol(dt,game)
            return

        attack_range = REACH[self.kind]
        if self.windup > 0:
            tx,ty,tz = self.aim_mark or (p.x,p.y,p.eye)
            aimed = math.atan2(ty-self.y,tx-self.x)
            lunge = LUNGES.get(self.kind)
            if lunge and self.windup < lunge[0] and math.hypot(tx-self.x,ty-self.y) > .36:
                self.advance(dt,game,aimed,lunge[1])
            self.windup = max(0., self.windup - dt)
            if self.windup == 0:
                committed = self.kind in (*TELLS,*SIGNATURES,"boilerback","chalk_spitter")
                if self.stun == 0 and (lunge or committed or can_see and distance < attack_range + .90):
                    self.attack(game, aimed, math.hypot(tx-self.x,ty-self.y), eye, tz)
                    self.recovery = self.recovery_time(self.kind=="baron" and game.relief_open())
                else:
                    self.cooldown = .43
                self.aim_mark = None
            return
        if self.stun > 0:
            return
        if self.recovery > .17 and (self.kind in BOSS_TITLES or self.kind in SIGNATURES or self.kind=="boilerback"):
            return
        if self.retreat:
            x,y,end = self.retreat
            if game.clock<end:
                self.follow(dt,game,math.atan2(self.y-y,self.x-x),.88)
                return
            self.retreat = None
        if can_see and distance <= attack_range and self.cooldown <= 0:
            self.windup,cue = WINDUP[self.kind]
            if self.kind == "boss" and self.hp < self.max_hp/2:
                self.windup *= .83
            self.aim_mark = (p.x,p.y,p.eye)
            self.angle = direction
            self.face_left = math.cos(direction) < -.24
            game.sound_at(cue, self.x, self.y, .72)
            return

        if not self.target:
            return
        tx, ty = self.target
        goal = COMFORT[self.kind]
        approach = math.atan2(ty - self.y, tx - self.x)
        strafe = math.pi/2 if (self.attacks + int(self.pose/1.45) + int(self.y))%2 else -math.pi/2
        if not can_see or distance > goal:
            if math.hypot(tx - self.x, ty - self.y) > .36:
                pace = 1.21 if self.kind == "boss" and self.hp < 145 else 1.
                partner = game.partners.get(id(self)) if can_see else None
                if partner and partner[0].alive and partner[0].player_seen and partner[0].windup:
                    approach += partner[1]*.48
                elif can_see and self.kind in ("skeeter","saucer","billy","crawler") and self.cooldown > .32:
                    approach += strafe*(.39 if self.kind in ("skeeter","crawler") else .23)
                self.follow(dt,game,approach,pace)
        elif self.kind in ("coot","skeeter","chalk_spitter") and distance < {"coot":3.,"skeeter":1.18,"chalk_spitter":3.3}[self.kind]:
            self.sidestep(dt,game,direction+math.pi+strafe*.26, .80 if self.kind=="coot" else 1.16,False)
        elif self.kind in RANGED or self.kind == "clone" and self.cooldown > .55:
            pace = {"saucer": 1.24,"alien": .62,"boss": .70,"jerry": .78}.get(self.kind,.42)
            self.sidestep(dt,game,direction+strafe,pace)
            if self.kind in TURN_CELS:
                self.angle = direction+strafe*.29

    def attack(self, game, direction, distance, eye, aim_z=None):
        self.attacks += 1
        if self.kind in SIGNATURES:
            self.signature_attack(game,direction,distance,eye,aim_z)
            return
        if self.kind in ("boilerback","chalk_spitter",*TELLS):
            self.special_attack(game,direction,distance,eye,aim_z)
            return
        if self.kind in LUNGES:
            _, _, reach, damage, cue, cooldown = LUNGES[self.kind]
            p=game.player
            angle = math.atan2(p.y-self.y, p.x-self.x)
            swing = self.kind == "skeeter" or abs(angle_delta(angle,direction)) < .61
            if swing and math.hypot(p.x-self.x,p.y-self.y) < reach and game.world.visible(self.x,self.y,p.x,p.y,eye,p.eye):
                game.damage(damage,(self.x,self.y),"STRIKE")
                game.sound_at(cue, self.x, self.y)
            self.cooldown = cooldown
            return
        if self.kind in RANGED:
            self.fire_projectiles(game, direction, distance, eye, aim_z)
            return

        if self.kind == "billy":
            chance = max(.24, .88 - distance * .104)
            damage, cue, delay = (14 if distance < 2.4 else 8), "enemy_scatter", 1.45
        elif self.kind == "coot":
            chance = max(.34, .83 - distance * .060)
            damage, cue, delay = 7, "enemy_pistol", 1.58
        else:
            chance = max(.39, 1 - distance * .115)
            damage, cue, delay = (7 if distance > 2.0 else 10), "enemy", 1.36 if self.attacks%2 else 1.77
        self.cooldown = delay + game.rng.uniform(.04, .33)
        game.sound_at(cue, self.x, self.y, .90)
        game.burst(self.x + math.cos(direction) * self.radius, self.y + math.sin(direction) * self.radius,
                   eye, "spark", 3, 1.2)
        p=game.player
        miss=abs(angle_delta(math.atan2(p.y-self.y,p.x-self.x),direction))
        spread=.23 if self.kind=="billy" else .11 if self.kind=="coot" else .15
        chance *= (.79 if p.crouched else 1.) * max(0.,1-miss/spread*.60)
        if miss < spread and game.rng.random() < chance:
            game.damage(damage,(self.x,self.y),"FIRE")

    def signature_attack(self,game,direction,distance,eye,aim_z):
        p = game.player
        self.cooldown = SIGNATURES[self.kind][4]
        game.sound_at(SIGNATURES[self.kind][6],self.x,self.y,.9)
        x = self.x+math.cos(direction)*.34
        y = self.y+math.sin(direction)*.34
        if game.world.blocked(x,y,.045,eye):
            return
        if self.kind=="yard_deputy":
            target = p.eye if aim_z is None else aim_z
            slope = (target-eye)*8.4/max(distance-.34,.6)
            game.launch(x,y,eye,direction-.023,8.4,"deputy_slug",vz=slope,enemy=True,damage=8,life=1.08)
            self.volley,self.volley_timer,self.volley_angle,self.volley_slope = 1,.23,direction,slope
        elif self.kind=="bottle_tosser":
            flight = min(1.32,max(.48,distance/6.1))
            speed = max(.45,(distance-.34)/flight)
            target = game.world.elevation(*self.aim_mark[:2]) if self.aim_mark else game.world.elevation(p.x,p.y)
            game.launch(x,y,eye,direction,speed,"fair_bottle",vz=(target+.06-eye)/flight+2.75*flight,
                        enemy=True,damage=0,life=flight)
        elif self.kind=="chain_hand":
            for swing in (-.19,0.,.19):
                game.launch(x,y,eye-.12,direction+swing,8.0,"chain_hook",enemy=True,damage=7,life=.44)
        else:
            ground = game.world.elevation(self.x,self.y)
            game.launch(x,y,ground+.31,direction,6.3,"valve_slug",enemy=True,damage=12,life=1.17)

    def special_attack(self,game,direction,distance,eye,aim_z):
        p = game.player
        if self.kind == "chalk_spitter":
            flight = min(1.25,max(.51,distance/6.15))
            speed = max(.5,(distance-.18)/flight)
            target_z = game.world.elevation(*self.aim_mark[:2]) if self.aim_mark else game.world.elevation(p.x,p.y)
            game.launch(self.x,self.y,eye,direction,speed,"chalk_lob",enemy=True,damage=0,
                        vz=(target_z+.07-eye)/flight+2.1*flight,life=flight)
            self.cooldown = 1.88
            game.sound_at("chalk_spit",self.x,self.y)
        elif self.kind == "rudy":
            self.volley = 5
            self.volley_timer = .02
            self.volley_angle = direction if self.attacks%2 else direction+.095
            self.volley_slope = ((p.eye if aim_z is None else aim_z)-eye)*6.8/max(1.,distance)
            self.cooldown = 1.42 if self.attacks%2 else 1.73
            game.sound_at("rudy_horn",self.x,self.y)
        elif self.kind == "foreman":
            for x,y,bearing in self.saw_lanes(direction):
                if not game.world.blocked(x,y,.04):
                    game.launch(x,y,game.world.elevation(x,y)+.58,bearing,7.6,
                                "foreman_cut",enemy=True,damage=13,life=1.38)
            self.cooldown = 1.69
            game.sound_at("foreman_cut",self.x,self.y)
        elif self.kind == "baron" and self.attacks%2:
            ports = game.pressure_ports(self.attacks-1)
            relieved = game.relief_open()
            for x,y in ports:
                game.add_hazard("steam",x,y,.94,.69,1.08 if relieved else 1.35,15)
                game.sound_at("pressure_vent",x,y,.76)
            self.cooldown = 1.95 if relieved else 1.58
        else:
            radius = 4.45 if self.kind=="boilerback" else 5.45
            for spread in (-.23,0.,.23):
                x = self.x+math.cos(direction+spread)*.72
                y = self.y+math.sin(direction+spread)*.72
                if not game.world.blocked(x,y,.04):
                    game.burst(x,y,eye-.20,"dust",6,1.45)
            angle = math.atan2(p.y-self.y,p.x-self.x)
            if (math.hypot(p.x-self.x,p.y-self.y) < radius and abs(angle_delta(angle,direction)) < .47
                    and game.world.visible(self.x,self.y,p.x,p.y,eye,p.eye)):
                game.damage(15 if self.kind=="boilerback" else 18,(self.x,self.y),"STEAM")
            self.cooldown = 1.60
            game.sound_at("boiler_release",self.x,self.y)

    def saw_lanes(self, direction, attack=None):
        side = (-math.sin(direction),math.cos(direction))
        index = self.attacks if attack is None else attack
        for nudge in ((-.85,.85) if index%2==0 else (-.70,0.,.70)):
            x,y = self.x+side[0]*nudge,self.y+side[1]*nudge
            yield x,y,direction

    def fire_projectiles(self, game, direction, distance, eye, aim_z=None):
        football = self.kind == "jerry"
        kind, spread = ("football" if football else "plasma"), .15
        if football:
            count = 3 if self.hp < self.max_hp / 2 else 1
            speed, damage = 7.1, 13
            self.cooldown = 1.02 if count == 3 else 1.32
        elif self.kind == "boss":
            count = 3 if self.hp < self.max_hp / 2 else 1
            speed, damage = 5.7, 13
            self.cooldown = 1.28
        elif self.kind == "saucer":
            count, speed, damage = 2, 3.7, 8
            self.cooldown = 1.74
        elif self.kind == "barker":
            count, speed, damage, spread = 3, 4.7, 8, .27
            self.cooldown = 1.70
            kind = "barker_bolt"
        elif self.kind == "lantern":
            count, speed, damage, spread = 2, 4.15, 9, .12
            self.cooldown = 1.52
            kind = "lantern_bolt"
            aim_z = (game.player.eye if aim_z is None else aim_z) - .37
        else:
            count, speed, damage = 1, 4.4, 9
            self.cooldown = .99 if self.attacks%2 else 1.84
        for i in range(count):
            theta = direction + (i - (count - 1) / 2) * spread
            dx = math.cos(theta) * (self.radius + .055)
            dy = math.sin(theta) * (self.radius + .055)
            t = max(.12, distance / speed)
            lift = ((game.player.eye if aim_z is None else aim_z) - eye) / t + (1.2 * t if football else 0.)
            game.launch(self.x + dx, self.y + dy, eye, theta, speed, kind,
                        vz=lift, enemy=True, damage=damage)
        cue={"jerry":"football_throw","saucer":"saucer_shot","boss":"sheriff_shot",
             "barker":"barker_blast","lantern":"lantern_spit"}.get(self.kind,"plasma")
        game.sound_at(cue, self.x, self.y)

    def recovery_time(self, relieved=False):
        if self.kind=="baron" and relieved:
            return 1.23
        if self.kind=="boss" and self.hp<self.max_hp/2:
            return .51
        return RECOVERY_TIMES.get(self.kind,.095)

    def sprite(self, observer=None, relieved=False):
        if self.dormant:
            return None
        if not self.alive:
            if self.explosive or self.kind in ("saucer", "skeeter"):
                return None
            return Sprite(self.x, self.y, f"{self.kind}_down", self.height * .25, -.07,
                          flip=self.face_left)
        recovery = self.recovery_time(relieved) if self.recovery>0. else 0.
        release = min(.14,recovery*.53)
        if self.hostile and self.stun > 0:
            frame = "pain"
        elif recovery and self.recovery>recovery-release:
            frame = "fire"
        elif self.windup > 0:
            frame = "aim"
        elif recovery and self.kind in TURN_CELS:
            frame = "recover"
        elif self.kind in ("saucer", "skeeter", "lantern"):
            frame = int(self.pose * (16 if self.kind == "skeeter" else 5)) % 3 - 1
        elif self.stun or self.kind == "bessie" or self.pose-self.last_stride > .18:
            frame = 0
        else:
            frame = round(math.sin(self.gait))
        stem = self.kind
        flip = self.face_left
        if observer is not None and frame in (-1,0,1) and self.kind in TURN_CELS:
            bearing = math.atan2(observer[1]-self.y,observer[0]-self.x)
            relative = angle_delta(bearing,self.angle)
            direction = min(4,int(abs(relative)/(math.pi/4)+.5))
            if direction:
                stem += ("","_quarter","_side","_away","_back")[direction]
            flip = relative<0 and direction<4
        if (frame==0 and stem==self.kind and self.kind in FIDGET_CELS and not self.alerted
                and (self.pose+self.x*.37+self.y*.13)%5.2>4.68):
            frame = "fidget"
        return Sprite(self.x,self.y,f"{stem}_{frame}",self.height*self.variant,self.z,
                      flip=flip,body=self.hostile,hurt=self.hit_flash)

