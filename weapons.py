"""The Hickston arsenal and its low-resolution viewmodel animations."""
from dataclasses import dataclass
from functools import lru_cache
import json
import math

import pygame as pg

from engine import ASSETS, FOCAL, VIEW

CROWBAR, REVOLVER, SHOTGUN, CROSSBOW, RIFLE, RIPSAW, ARMGUN, DYNAMITE, SLING, ROCKET, RIVETER, PRESSURE = range(12)
BOWLING, KEG, COW, TEAT = range(12, 16)
RETIRED = (RIVETER, PRESSURE)
NAMES = ("crowbar", "revolver", "shotgun", "crossbow", "rifle", "ripsaw", "armgun", "tnt",
         "slingblade", "bottle_launcher", "riveter", "pressure_gun",
         "bowling_ball", "powder_keg", "cow_launcher", "teat_gun")
LABELS = ("RUSTED CROWBAR", ".38 SPECIAL", "SAWED-OFF", "DYNAMITE CROSSBOW",
          "RANCH RIFLE", "RIP SAW", "ALIEN ARM GUN", "DYNAMITE", "SLING BLADE [9]",
          "BOTTLE ROCKET LAUNCHER [0]", "MILL RIVETER", "COPPERHEAD",
          "BOWLING BALL [-]", "POWDER KEG [=]", "COW LAUNCHER [\\]", "TEAT GUN [`]")
CAPACITY = (0, 6, 2, 1, 18, 1, 6, 0, 0, 1, 8, 3, 1, 1, 1, 30)
RELOAD_TIME = (0., .88, 1.10, .68, 1.30, .58, .88, 0., 0., .79, .94, 1.18, .72, .95, 1.10, 1.25)
FIRE_TIME = (.33, .34, .55, .62, .125, .32, .34, .46, .49, .65, .24, .68, .70, .80, .95, .095)
MAX_RESERVE = (0, 90, 48, 30, 108, 22, 32, 0, 0, 16, 52, 24, 9, 6, 6, 120)
PICKUP_RESERVE = (0, 12, 15, 8, 20, 5, 8, 0, 0, 6, 16, 6, 3, 2, 2, 30)
RECOIL = (.60, .70, 1.03, .8, .44, .55, .42, .25, .87, .74, .65, .82, .55, .75, 1.1, .30)
SHOT_NOISE = (2.8, 10., 14., 4., 13., 7., 8., 1., 2.9, 8.5, 7., 7.5, 4., 6., 12., 6.)
KICK_HOLD = (.0, .073, .095, .11, .052, .09, .075, .14, .0, .095, .086, .125, .12, .12, .12, .04)
VIEW_RISE = (4, 6, 10, 5, 6, 4, 5, 5, 7, 6, 8, 8, 3, 5, 9, 2)
SETTLE = (.21,.17,.24,.24,.10,.19,.22,.19,.27,.23,.13,.29,.25,.25,.30,.08)
RETREAT = (3,3,7,2,4,4,2,4,4,6,3,5,3,4,8,1)
RAISE_DEPTH = (42,36,45,43,47,49,40,36,49,46,45,50,44,44,46,42)
DYNAMITE_FUSE = 2.65
# Per-shot damage, tunned so every weapon has a role rather than a runaway
# damage-per-second number. Shotgun is (per pellet, pellet count).
DAMAGE = {REVOLVER: 34, SHOTGUN: (12, 10), RIFLE: 21, RIVETER: 32, PRESSURE: 24,
          ARMGUN: 50, RIPSAW: 54, TEAT: 10, BOWLING: 108, COW: 150, ROCKET: 120}
GRIND_DAMAGE = 21
MELEE = {CROWBAR: (44, 58), SLING: (58, 72)}
RECOVERY_GUNS = (REVOLVER, SHOTGUN, RIFLE, ARMGUN, ROCKET, RIVETER, PRESSURE, BOWLING, KEG, COW, TEAT)
RELOAD_POSES = ("open", "eject", "load", "close")
MUZZLES = {REVOLVER: (182, 73, 32), SHOTGUN: (181, 75, 48),
           RIFLE: (173, 63, 32), ARMGUN: (171, 79, 31),
           ROCKET: (165,70,25), RIVETER: (174,75,23), PRESSURE: (173,76,19), COW: (163,69,26),
           TEAT: (280, 82, 18)}
# Viewmodels are cut at 320x120 and drawn from the bottom of the view. A small
# uniform enlargement plus a warm rim keeps the dark steel readable against the
# county's night interiors without touching the source cels or their anchors.
GUN_W, GUN_H = 320, 120
VIEW_SCALE = 1.12
VIEW_SCALES = {CROWBAR: 1.22, REVOLVER: 1.22, SHOTGUN: 1.20, RIFLE: 1.20,
               CROSSBOW: 1.30, RIPSAW: 1.30, ARMGUN: 1.26, DYNAMITE: 1.24,
               SLING: 1.32, ROCKET: 1.32, BOWLING: 1.40, KEG: 1.36,
               COW: 1.34, TEAT: 1.34}
VIEW_PIVOT = (160., 120.)
# The 3D view ends at the HUD line. Sink the cutouts a few pixels past that line
# (they clip at the view edge) so the grip disappears and the gun never hovers.
VIEW_SINK = 4.
HOLD_FLOOR = 3.


def view_point(x, y, px, py, s=VIEW_SCALE):
    """Map a source-cel coordinate through the viewmodel presentation transform."""
    return (x + VIEW_PIVOT[0] * (1 - s) + px * s,
            y + VIEW_PIVOT[1] * (1 - s) + VIEW_SINK + py * s)
MUZZLE_STYLE = {
    REVOLVER:("fire",.81,0.76),SHOTGUN:("fire",.91,1.24),RIFLE:("fire",.65,.69),
    ARMGUN:("energy",1.06,0.),ROCKET:("rocket",1.07,1.14),
    RIVETER:("forge",.58,.62),PRESSURE:("steam",.86,1.23),COW:("rocket",1.07,1.14),
    TEAT:("steam",.74,.55),
}
RELOAD_BEATS = {
    REVOLVER:(.22,.48,.83),SHOTGUN:(.23,.46,.80),CROSSBOW:(.26,.51,.82),
    RIFLE:(.27,.49,.85),RIPSAW:(.22,.47,.80),ARMGUN:(.29,.52,.85),
    ROCKET:(.26,.49,.83),RIVETER:(.23,.48,.82),PRESSURE:(.30,.52,.84),
    BOWLING:(.25,.50,.82),KEG:(.25,.50,.82),COW:(.26,.50,.83),TEAT:(.28,.52,.84),
}
RELOAD_AUDIO = {REVOLVER: ("rev_extract","rev_cylinder","rev_lock"),
                SHOTGUN: ("shot_extract","shot_shell","shot_lock"),
                CROSSBOW: ("bow_pull", "bow_seat", "bow_latch"),
                RIFLE: ("mag_out", "mag_in", "bolt_rack"),
                RIPSAW: ("saw_latch", "saw_seat", "saw_latch"),
                ARMGUN: ("arm_vent", "arm_cell", "arm_ready"),
                ROCKET: ("rocket_case","rocket_seat","rocket_lock"),
                RIVETER: ("rivet_mag","rivet_strip","rivet_lock"),
                PRESSURE: ("pressure_vent","pressure_charge","pressure_pump"),
                BOWLING: ("eject","load","close"), KEG: ("shot_hinge","load","close"),
                COW: ("rocket_case","rocket_seat","rocket_lock"), TEAT: ("mag_out","gulp","bolt_rack")}
OPEN_AUDIO = {REVOLVER:"rev_cylinder",SHOTGUN:"shot_hinge",CROSSBOW:"bow_hook",RIFLE:"reload",
              RIPSAW:"saw_latch",ARMGUN:"arm_vent",ROCKET:"rocket_breech",RIVETER:"rivet_mag",
              PRESSURE:"pressure_seal",BOWLING:"load",KEG:"shot_hinge",COW:"rocket_breech",TEAT:"reload"}


@lru_cache(maxsize=1)
def muzzle_anchors():
    return json.loads((ASSETS / "art" / "weapon_anchors.json").read_text(encoding="utf-8"))


@dataclass
class Armory:
    active: int = 1

    def __post_init__(self):
        self.owned = [i in (CROWBAR, REVOLVER) for i in range(len(NAMES))]
        self.loaded = [6 if i == REVOLVER else 0 for i in range(len(NAMES))]
        self.reserve = [30 if i == REVOLVER else 0 for i in range(len(NAMES))]
        self.cooldown = 0.
        self.reload = 0.
        self.recoil = 0.
        self.flash = 0.
        self.switch = 0.
        self.empty = 0.
        self.shot_age = 1.
        self.last_spent = 0
        self.holstered = False
        self.lower = 0.
        self.rifle_heat = 0.
        self.grinding = False
        self.swing_hit = False
        self.fuse = 0.
        self.tnt_latched = False
        self.auto_switch = True
        self.auto_reload = True
        self.graded = {}

    def tick(self, dt, game):
        self.cooldown = max(0, self.cooldown - dt)
        self.recoil = max(0, self.recoil - 5.2 * dt)
        self.flash = max(0, self.flash - dt)
        self.switch = max(0, self.switch - dt)
        self.empty = max(0, self.empty - dt)
        self.shot_age += dt
        if self.fuse:
            self.fuse -= dt
            if self.fuse <= 0:
                self.fuse = 0.
                self.cooldown = FIRE_TIME[DYNAMITE]
                self.shot_age = 0.
                game.throw_dynamite(0.)
        swing_at = .118 if self.active == SLING else .061
        if self.active in (CROWBAR, SLING) and self.swing_hit and self.shot_age >= swing_at:
            self.swing_hit = False
            p = game.player
            sling = self.active == SLING
            damage = MELEE[SLING if sling else CROWBAR][1 if game.sprint else 0]
            if game.hitscan(p.view_angle, (p.pitch + p.sway) / FOCAL, damage,
                            2.15 if sling else 1.65, .30 if sling else .34):
                game.sound.play("sling_hit" if sling else "crowbar_hit")
        self.rifle_heat = max(0., self.rifle_heat - dt * 1.8)
        self.lower = max(0., min(1., self.lower + dt * (5.5 if self.holstered else -5.5)))
        if self.reload > 0:
            before = 1 - self.reload / RELOAD_TIME[self.active]
            self.reload -= dt
            progress = 1 - self.reload / RELOAD_TIME[self.active]
            cues = RELOAD_AUDIO.get(self.active, ("eject", "load", "close"))
            for trigger, cue in zip(RELOAD_BEATS[self.active],cues):
                if before < trigger <= progress:
                    game.sound.play(cue, .78)
            if self.reload <= 0:
                i = self.active
                count = min(CAPACITY[i] - self.loaded[i], self.reserve[i])
                self.loaded[i] += count
                self.reserve[i] -= count
                self.reload = 0.

    def select(self, slot, game):
        if slot != self.active and self.owned[slot]:
            if self.fuse:
                game.message("THROW THAT STICK FIRST!", .85)
                return
            self.active = slot
            self.reload = self.cooldown = self.flash = self.recoil = 0.
            self.shot_age = 1.
            self.grinding = False
            self.swing_hit = False
            self.tnt_latched = False
            self.holstered = False
            self.switch = .23
            game.sound.play("equip_"+NAMES[slot],.61)
            game.message(LABELS[slot], .95)
        elif not self.owned[slot]:
            game.message("YOU AIN'T GOT THAT ONE.", .85)

    def pickup(self, slot, game):
        fresh = not self.owned[slot]
        self.owned[slot] = True
        self.add_ammo(slot, PICKUP_RESERVE[slot])
        if fresh:
            self.loaded[slot] = CAPACITY[slot]
            if self.auto_switch:
                self.select(slot, game)
            else:
                game.message(LABELS[slot], 1.35)
        return fresh

    def add_ammo(self, slot, amount):
        old = self.reserve[slot]
        self.reserve[slot] = min(MAX_RESERVE[slot], old + amount)
        return self.reserve[slot] > old

    def cycle(self, direction, game):
        for offset in range(1, len(NAMES)):
            slot = (self.active + offset * direction) % len(NAMES)
            if self.owned[slot]:
                self.select(slot, game)
                return

    def start_reload(self, game):
        i = self.active
        if CAPACITY[i] and self.reload <= 0 and self.reserve[i] and self.loaded[i] < CAPACITY[i]:
            self.reload = RELOAD_TIME[i]
            self.grinding = False
            game.sound.play(OPEN_AUDIO[i],.85)
            return True
        return False

    def fire(self, game, both=False):
        i = self.active
        if self.holstered:
            self.holstered = False
            self.switch = .20
            return
        if self.cooldown or self.reload or self.switch or game.player.health <= 0:
            return
        if i == DYNAMITE:
            if not self.fuse and not self.tnt_latched:
                if self.reserve[CROSSBOW]:
                    self.reserve[CROSSBOW] -= 1
                    self.fuse = DYNAMITE_FUSE
                    self.tnt_latched = True
                    game.sound.play("match_strike")
                    game.set_face("grin_rampage", .35)
                elif not self.empty:
                    self.empty = .32
                    game.sound.play("dry_tnt")
                    game.message("OUT OF STICKS.", .72)
            return
        grind = i == RIPSAW and both
        if CAPACITY[i] and not self.loaded[i] and not grind:
            if not (self.auto_reload and self.start_reload(game)) and self.empty == 0:
                self.empty = .34
                game.sound.play("dry_"+NAMES[i])
                game.message("DRY AS A BONE.", .7)
                game.barks.say(game, "empty")
            return
        pair = both and ((i == SHOTGUN and self.loaded[i] == 2) or (i == RIVETER and self.loaded[i] >= 2))
        spent = 0 if grind or i in (CROWBAR,SLING) else 2 if pair else 1
        self.cooldown = (.135 if grind else .26 if i == SHOTGUN and spent == 1 and self.loaded[i] == 2
                         else FIRE_TIME[i] + (.18 if spent == 2 else 0))
        self.recoil = RECOIL[i] + (.19 if spent == 2 else 0)
        self.flash = (.078 if spent == 2 else .052) if i in MUZZLES else 0.
        self.grinding = grind
        self.last_spent = spent
        self.shot_age = 0.
        self.loaded[i] -= spent
        game.set_face("yell_fire" if i >= SHOTGUN else "grin_rampage", .29)
        cue = ("shotgun_both" if i==SHOTGUN and spent==2 else "riveter_pair" if i==RIVETER and spent==2
               else NAMES[i])
        if not grind:
            if i in MUZZLES and i != ARMGUN:
                game.report(cue)
            else:
                game.sound.play(cue)
        player = game.player
        aim = player.view_angle
        slope = (player.pitch + player.sway) / FOCAL
        if i in (REVOLVER,SHOTGUN,RIFLE):
            aim,slope = game.assisted_aim(aim,slope)
        game.wake_nearby(SHOT_NOISE[i], player.x, player.y)
        if i in (CROWBAR, SLING):
            self.swing_hit = True
        elif i == REVOLVER:
            game.hitscan(aim + game.rng.uniform(-.009, .009), slope, DAMAGE[REVOLVER], 23., .055)
        elif i == SHOTGUN:
            pellet_damage, pellets = DAMAGE[SHOTGUN]
            for pellet in range(pellets * spent):
                dx = game.rng.uniform(-.135, .135)
                dy = game.rng.uniform(-.09, .09)
                game.hitscan(aim + dx, slope + dy, pellet_damage, 11.5, .04, spark=pellet < 4)
        elif i == RIFLE:
            spread = .009 + self.rifle_heat * .027
            game.hitscan(aim + game.rng.uniform(-spread, spread),
                         slope + game.rng.uniform(-spread, spread), DAMAGE[RIFLE], 27., .045)
            player.pitch = min(53., player.pitch + .70 + self.rifle_heat * 1.2)
            self.rifle_heat = min(1., self.rifle_heat + .29)
        elif i == RIVETER:
            for offset in ((-.031,.031) if spent==2 else (0.,)):
                game.hitscan(aim+offset, slope, DAMAGE[RIVETER], 16., .042)
        elif i == PRESSURE:
            game.hitscan(aim,slope,DAMAGE[PRESSURE],8.5,.035,pressure=True)
        elif i == TEAT:
            game.hitscan(aim + game.rng.uniform(-.05,.05), slope + game.rng.uniform(-.04,.04), DAMAGE[TEAT], 9., .06)
        elif i in (BOWLING, KEG, COW):
            kind, speed, damage, lift = {BOWLING: ("bowling", 7.4, DAMAGE[BOWLING], .0), KEG: ("keg", 6.2, 0, .55),
                                         COW: ("cow", 8.6, DAMAGE[COW], .30)}[i]
            game.launch(player.x + math.cos(aim) * .25, player.y + math.sin(aim) * .25,
                        (game.world.elevation(player.x, player.y) + .22) if i == BOWLING else player.eye - .12, aim, speed, kind,
                        vz=(slope * speed + lift) if i != BOWLING else 0., damage=damage,
                        life=4.5 if i == BOWLING else None)
        elif grind:
            game.hitscan(aim, slope, GRIND_DAMAGE, 1.45, .36)
        else:
            kind, speed, damage = {CROSSBOW: ("bolt", 10.8, 0),
                                   RIPSAW: ("blade", 15., DAMAGE[RIPSAW]),
                                   ARMGUN: ("arm_bolt", 12.2, DAMAGE[ARMGUN]),
                                   ROCKET: ("bottle_rocket", 9.6, DAMAGE[ROCKET])}[i]
            lift = .34 if i in (CROSSBOW,ROCKET) else 0.
            game.launch(player.x + math.cos(aim) * .23, player.y + math.sin(aim) * .23,
                        player.eye - .09, aim, speed, kind, vz=slope * speed + lift, damage=damage)

    def release_dynamite(self, game):
        if self.fuse:
            game.throw_dynamite(self.fuse)
            self.fuse = 0.
            self.cooldown = FIRE_TIME[DYNAMITE]
            self.recoil = RECOIL[DYNAMITE]
            self.shot_age = 0.
            game.sound.play("tnt_throw")
            game.set_face("yell_fire", .3)
        self.tnt_latched = False

    def pose(self):
        if self.reload:
            progress = 1 - self.reload / RELOAD_TIME[self.active]
            pose = RELOAD_POSES[sum(progress>=beat for beat in RELOAD_BEATS[self.active])]
            return pose + "_one" if (self.active == SHOTGUN and self.loaded[SHOTGUN] == 1
                                     and pose in ("eject", "load")) else pose
        if self.active in (CROWBAR,SLING):
            if self.active == SLING and self.shot_age < .40:
                return ("wind","strike","follow","recover")[
                    (self.shot_age >= .118)+(self.shot_age >= .18)+(self.shot_age >= .29)]
            if self.active == CROWBAR and self.shot_age < .29:
                return ("wind", "strike", "follow", "recover")[
                    (self.shot_age >= .061) + (self.shot_age >= .115) + (self.shot_age >= .198)]
        elif self.active == DYNAMITE:
            if self.fuse:
                return "lit" if int(self.fuse * 24) % 2 else "lit_alt"
            if self.shot_age < .065:
                return "throw"
            if self.shot_age < .16:
                return "kick"
            return "idle" if self.reserve[CROSSBOW] else "dry"
        elif self.active == RIPSAW and self.grinding and self.shot_age < .19:
            return "grind_hot" if int(self.shot_age * 40) % 2 else "grind"
        elif self.shot_age < KICK_HOLD[self.active] or (self.active in (CROSSBOW, RIPSAW) and not self.loaded[self.active]):
            return "kick"
        elif self.active in RECOVERY_GUNS and self.shot_age < (.103 if self.active == RIFLE else .16):
            return "recover"
        return "idle"

    def draw(self, screen, art, player, light=1., bob=1., flashes=1., offset=0):
        if self.lower >= 1.:
            return
        i = self.active
        pose = self.pose()
        s = VIEW_SCALES.get(i, VIEW_SCALE)
        name = f"gun_{NAMES[i]}_{pose}"
        level = max(11, min(18, round((.68 + .38 * light + self.flash * flashes * 1.6) * 16)))
        cache_key = name, level
        if cache_key not in self.graded:
            image = art.get(name).copy()
            image.fill((min(255, level * 15 + 11), min(255, level * 15 + 8),
                        min(255, level * 16 + 3), 255), special_flags=pg.BLEND_RGBA_MULT)
            image.fill((11, 8, 4), special_flags=pg.BLEND_RGB_ADD)
            image = pg.transform.smoothscale(
                image, (round(GUN_W * s), round(GUN_H * s)))
            rim = pg.mask.from_surface(image).to_surface(
                setcolor=(205, 168, 116, 42), unsetcolor=(0, 0, 0, 0))
            self.graded[cache_key] = image, rim
        image, rim = self.graded[cache_key]
        gait = player.motion * (0.35 if player.air else 1.)*bob
        progress = min(1.,self.shot_age/SETTLE[i])
        settling = ((1-progress)**2-.32*math.sin(math.pi*progress))*self.recoil
        lift = min(1.,self.switch/.23)
        lift = lift*lift*(3.-2.*lift)*RAISE_DEPTH[i]
        reload_sway = math.sin(math.pi*self.reload/RELOAD_TIME[i]) if self.reload else 0.
        x = round(math.sin(player.walk_phase) * gait * 5 + player.sway * .7
                  + settling*RETREAT[i] + reload_sway*(2 if i==CROSSBOW else 4))
        y = VIEW - GUN_H + offset + round(
            (abs(math.cos(player.walk_phase)) * 4 - 1.7) * gait + player.air * 5
            - VIEW_RISE[i] * settling + lift + self.lower * 88 + reload_sway * 2)
        y = max(y, VIEW - GUN_H - HOLD_FLOOR)
        bx = round(x + VIEW_PIVOT[0] * (1 - s))
        by = round(y + VIEW_PIVOT[1] * (1 - s) + VIEW_SINK)
        view = screen.subsurface((0, 0, screen.get_width(), VIEW))
        source = NAMES[i]
        if i in MUZZLES and self.shot_age < .31 and self.lower < .2 and not self.reload:
            mx, my, radius = MUZZLES[i]
            mx, my = muzzle_anchors().get(source, {}).get(pose, (mx,my))
            prefix,aspect,smoke_scale = MUZZLE_STYLE[i]
            if self.flash and flashes:
                index = min(3, int(self.shot_age * 48))
                size = round((radius + 8 * (self.last_spent == 2)) * s)
                flash = pg.transform.scale(art.get(f"fx_{prefix}_{index}"),(size,round(size*aspect)))
                if flashes<1.:
                    flash.set_alpha(round(255*flashes))
                ax, ay = view_point(x, y, mx, my, s)
                front = (round(ax - 3 * s), round(ay - 2 * s))
                view.blit(flash, flash.get_rect(center=front))
                if i == SHOTGUN and self.last_spent == 2:
                    size = round(size * .76)
                    twin = pg.transform.scale(art.get(f"fx_{prefix}_{min(3,index+1)}"), (size, size))
                    if flashes<1.:
                        twin.set_alpha(round(255*flashes))
                    view.blit(twin, twin.get_rect(center=(front[0]+round(6*s),
                                                          front[1]+round(1*s))))
            elif smoke_scale and self.shot_age>=.048:
                index = min(3, max(0, int((self.shot_age - .055) * 16)))
                size = round((21+index*6)*smoke_scale)
                cloud = pg.transform.scale(art.get(f"fx_smoke_{index}"), (size, size))
                sx, sy = view_point(x, y, mx - 4 - index * 2, my - 9 - index * 4, s)
                view.blit(cloud, cloud.get_rect(center=(round(sx), round(sy))))
        view.blit(rim, (bx, by - 1))
        view.blit(image, (bx, by))
        if i==RIPSAW and self.grinding and flashes and self.shot_age<.135 and self.lower<.2:
            cx,cy=muzzle_anchors()[source].get(pose,(155,79))
            ax, ay = view_point(x, y, cx, cy, s)
            for spark in range(6):
                spread=(spark-2.5)*4
                rise=5+int(self.shot_age*56)+spark%3*2
                color=(224,160,83) if spark%2 else (247,209,134)
                start=(round(ax+spread*.42*s),round(ay-2*s))
                end=(round(ax+spread*s),round(ay-rise*s))
                pg.draw.line(view,color,start,end)
        if i == DYNAMITE and self.fuse and self.lower < .25:
            fx, fy = view_point(x, y, 144, 137, s)
            width = max(1, round(32*self.fuse/DYNAMITE_FUSE*s))
            pg.draw.rect(view, (62,37,25), (round(fx),round(fy),round(33*s),round(4*s)))
            pg.draw.rect(view, (215,130,58) if self.fuse > .75 else (220,69,40),
                         (round(fx),round(fy+s),width,round(2*s)))
        if i == RIFLE and .016 < self.shot_age < .123 and not self.reload and self.lower < .2:
            t = self.shot_age - .016
            origin_x, origin_y = muzzle_anchors()["rifle"].get("case", (208,97))
            ax, ay = view_point(x, y, origin_x, origin_y, s)
            cx = ax + t * 337 * s
            cy = ay - t * 244 * s + 980 * s * t*t
            angle = t * 61 - .6
            tip = (round(cx + math.cos(angle)*3), round(cy + math.sin(angle)*3))
            tail = (round(cx - math.cos(angle)*3), round(cy - math.sin(angle)*3))
            pg.draw.line(view, (119, 86, 46), tail, tip, 3)
            pg.draw.line(view, (216, 170, 83), tail, tip)
            view.set_at(tip, (233, 193, 112))

