"""Small authored encounters that reuse the county's real geometry."""
from dataclasses import dataclass
import math

from engine import FOCAL, Sprite
from weapons import Armory, REVOLVER


GALLERY_STAND = (25.96,33.42)
GALLERY_TARGETS = ((29.54,32.99,.68),(29.54,33.56,1.14),
                   (29.54,33.79,.65),(29.54,33.15,1.32))
RUPTURES = {
    "mill-leaky-standpipe": (22.72,16.69,"STANDPIPE SHUDDERS. STEP OFF THE GRATE."),
    "quarry-cut-leak": (58.26,24.98,"COPPER JOINT WHISTLES. GIVE IT ROOM."),
}
HUB_BOARD = (30.36,44.13)
HUB_DISPATCH = (
    ("MISSING HOG","COUNTY DISPATCH / MISSING HOG. LAST SEEN NEAR STANKY'S.","RADIO: LOOK FOR THE HOG."),
    ("HOG HOME","HOG HOME. THE FAIR STILL HAS BESSIE'S PRIZE TAG.","RADIO: THE HOG IS HOME."),
    ("BLUE TRUNK","FAIR CLOSED. BLUE TRUNK SHIPPED TO BLACKWATER.","RADIO: CHECK THE BLUE TRUNK."),
    ("LAST LOAD","MILL QUIET. THE LAST LOAD WENT TO STILLWATER CUT.","RADIO: KEEP THE LAST LOAD."),
    ("ALL CLEAR","BESSIE'S TAG IS BACK. MUNDELL STILL OWES FOR THE JUGS.","RADIO: THE TAG IS HOME."),
)

# An advance starts during the partner's visible windup. The left/right choice
# is authored for the approach lane, and ordinary pathing still owns collision.
PARTNERS = {
    "hickston": (("road-billy","road-coot",-1),),
    "fair": (("concession-crawler","concession-billy",1),),
    "sawmill": (("east-billy","east-lantern",-1),),
    "quarry": (("line-billy","line-coot",1),),
}

# Existing side rooms give the player a brief change of acoustic space on the
# way between pressure points. Only the ambient bed changes, through its fade.
RECOVERY_ROOMS = {
    "fair": (25.05,32.73,29.8,34.07,"room"),
    "sawmill": (21.46,6.09,24.89,8.02,"mill_bank"),
    "quarry": (20.68,34.85,23.39,37.22,"room"),
}


@dataclass(frozen=True)
class CountyNote:
    x: float
    y: float
    label: str
    text: str
    plane: float = 0.


@dataclass(frozen=True)
class Interior:
    art: str
    x: float
    y: float
    z: float
    height: float
    plane: float = 0.


INTERIORS = {
    "hickston": (Interior("dispatch",12.63,9.60,.78,.59,math.pi/2),),
    "fair": (Interior("tickets",27.09,32.71,.78,.44),),
    "sawmill": (Interior("break",25.97,14.76,.73,.54),),
    "quarry": (Interior("bunk",21.38,35.82,.83,.52),),
}

NOTES = {
    "hickston": (CountyNote(13.03,9.32,"DISPATCH STUB",
                            "MUNDELL / YOUR HOG TAG WENT TO THE FAIR. CHECK THE BLUE TRUNK.",math.pi/2),),
    "fair": (CountyNote(26.70,32.75,"BLUE TRUNK TAG",
                        "BESSIE'S TAG / FOUND UNDER THE PRIZE RIBBONS. SENT TO BLACKWATER WITH THE CRATES."),),
    "sawmill": (CountyNote(25.60,15.28,"SHIFT TICKET",
                           "BLUE TRUNK / WENT TO STILLWATER. TAG TOO TOUGH FOR THE SAW."),),
    "quarry": (CountyNote(22.22,35.63,"WEIGH SLIP",
                           "BLUE TRUNK / ONE HOG TAG AND SIX EMPTY JUGS. BILL THE SHERIFF.",math.pi/2),),
}


class Gallery:
    goal = 4
    limit = 16.
    rounds = 6
    radius = .135

    def __init__(self):
        self.rewarded = False
        self.active = False

    def toggle(self, game):
        if self.active:
            self.finish(game,"GALLERY CLOSED. E TO TRY AGAIN.")
            return
        if game.armory.fuse:
            game.message("THROW THE LIT STICK FIRST.")
            return
        self.active = True
        self.clock = 0.
        self.next_target = 2.35
        self.hits = self.spent = self.index = 0
        self.held = True
        self.pistol = Armory(REVOLVER)
        game.message("TIN ROOSTER / 4 HITS, 6 BORROWED ROUNDS.",2.1)
        game.sound.play("menu_accept")

    def prompt(self):
        return "E  CLOSE GALLERY" if self.active else "E  PLAY TIN ROOSTER"

    def hud(self):
        return f"TIN ROOSTER  {self.hits}/4  ROUNDS {self.rounds-self.spent}  TIME {math.ceil(self.limit-self.clock):02d}"

    def sprite(self,game):
        x,y,z = GALLERY_TARGETS[self.index]
        return Sprite(x,y,"county_gallery_target",self.radius*2,
                      game.world.elevation(x,y)+z-self.radius,plane=math.pi/2)

    def finish(self,game,message):
        self.active = False
        game.message(message,2.6)

    def advance_target(self):
        self.index = (self.index+1)%len(GALLERY_TARGETS)
        self.next_target = self.clock+2.35

    def tick(self,dt,game,fire):
        p = game.player
        self.clock += dt
        self.pistol.tick(dt,game)
        if not (25.10<=p.x<=28.66 and 32.77<=p.y<=33.94):
            self.finish(game,"LEFT THE GALLERY. E AT THE TICKET BOOTH TO RETRY.")
            return
        if self.clock>=self.limit:
            self.finish(game,"TIME. E AT THE TICKET BOOTH TO RETRY.")
            return
        if self.clock>=self.next_target:
            self.advance_target()
        tap = fire and not self.held
        self.held = fire
        if not tap or self.pistol.cooldown:
            return
        self.spent += 1
        self.pistol.loaded[REVOLVER] = self.rounds-self.spent
        self.pistol.recoil, self.pistol.flash, self.pistol.cooldown = .54,.034,.18
        self.pistol.shot_age = 0.
        game.sound.play("revolver",.56)
        x,y,z = GALLERY_TARGETS[self.index]
        z += game.world.elevation(x,y)
        dx,dy = x-p.x,y-p.y
        ax,ay = math.cos(p.view_angle),math.sin(p.view_angle)
        reach = dx*ax+dy*ay
        hit_z = p.eye+reach*(p.pitch+p.sway)/FOCAL
        if (reach>0 and abs(dx*ay-dy*ax)<self.radius and abs(z-hit_z)<self.radius
                and game.world.visible(p.x,p.y,x,y,p.eye,z)):
            self.hits += 1
            game.sound_at("ricochet",x,y,.55)
            self.advance_target()
        if self.hits==self.goal:
            if self.rewarded:
                self.finish(game,"NICE SHOOTING. PRIZE ALREADY CLAIMED.")
            else:
                # Claim once. A full pocket leaves the original prize on the booth floor.
                self.rewarded = True
                if not game.collect("rinds"):
                    game.add_pickup("rinds",26.47,33.64)
                self.finish(game,"TIN ROOSTER WINNER. ONE BAG OF RINDS.")
            game.sound.play("menu_accept")
        elif self.spent==self.rounds:
            self.finish(game,"OUT OF BORROWED ROUNDS. E TO TRY AGAIN.")
