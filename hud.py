"""Rusted status plate, player mugshot, title menu and tally screen."""
import math
import pygame as pg

from engine import VIEW
from campaign import BY_ID, next_level
from pixel_type import label, text_width, wrap
from weapons import ARMGUN, BOWLING, COW, CROWBAR, CROSSBOW, DYNAMITE, KEG, PRESSURE, REVOLVER, RIFLE, RIPSAW, RIVETER, ROCKET, SHOTGUN, SLING, TEAT

INK = (250, 232, 193)
SHADE = (27, 19, 15)
AMBER = (251, 183, 98)
ITEMS = ("rinds", "beer", "moonshine", "whiskey", "cowpie")
ITEM_LABELS = ("PORK RINDS", "BEER", "MOONSHINE", "WHISKEY", "COW PIE")
BELT = (REVOLVER, SHOTGUN, CROSSBOW, RIFLE, RIPSAW, ARMGUN, DYNAMITE)
TITLE_FIRST, TITLE_ROW = 101, 9


def title_row_height(entries):
    return TITLE_ROW - (len(entries)>9)


class HUD:
    def __init__(self, art):
        self.art = art
        self.plate = art.get("status_panel").convert()
        self.faces = {}
        self.icons = {}
        self.ammo_icons = self.make_ammo_icons()
        for title, x in (("HEALTH",29),("AMMO",77),("KEYS",115),("YER STUFF",292)):
            self.text(self.plate,title,(x,14 if title=="YER STUFF" else 13),
                      "mini" if title=="YER STUFF" else "body",center=True)

    @staticmethod
    def text(surface, text, position, style="body", color=INK, center=False, shadow=True, right=False):
        image = label(text, style, color)
        rect = image.get_rect()
        if center:
            rect.midtop = position
        elif right:
            rect.topright = position
        else:
            rect.topleft = position
        if shadow:
            surface.blit(label(text,style,SHADE),(rect.x+1,rect.y+1))
        surface.blit(image, rect)
        return rect

    @staticmethod
    def panel(screen, rect, face=(40,29,23), edge=(141,102,65)):
        rect=pg.Rect(rect)
        pg.draw.rect(screen,(22,16,13),rect.move(1,2))
        pg.draw.rect(screen,face,rect)
        pg.draw.rect(screen,edge,rect,1)
        pg.draw.line(screen,(79,53,38),(rect.left+2,rect.bottom-2),(rect.right-3,rect.bottom-2))

    def banner(self,screen,text,top,limit=288,color=INK):
        lines=wrap(text,limit-14)
        if not lines:
            return top
        width=max(text_width(line) for line in lines)+14
        height=10*len(lines)+4
        middle=screen.get_width()//2
        self.panel(screen,(middle-width//2,top,width,height),(32,23,19),(128,88,57))
        for i,line in enumerate(lines):
            self.text(screen,line,(middle,top+4+i*10),color=color,center=True,shadow=False)
        return top+height

    def number(self, screen, value, center, y, low=False):
        self.text(screen,str(value),(center,y),"heading",(255,113,64) if low else (238,89,52),center=True)

    def icon(self, name, width, height):
        key=(name,width,height)
        if key not in self.icons:
            source=self.art.get("item_"+name)
            source=source.subsurface(source.get_bounding_rect(min_alpha=128))
            scale=min(width/source.get_width(),height/source.get_height())
            self.icons[key]=pg.transform.smoothscale(source,(max(1,round(source.get_width()*scale)),
                                                             max(1,round(source.get_height()*scale))))
        return self.icons[key]

    def ammo_rail(self,screen,armory):
        for i,slot in enumerate(BELT):
            x=6+i*45
            if slot == DYNAMITE and armory.active in (SLING,ROCKET,RIVETER,PRESSURE,BOWLING,KEG,COW,TEAT):
                pg.draw.rect(screen,(51,33,25),(x,VIEW+1,39,6))
                token = {SLING:"9",ROCKET:"0",RIVETER:"-",PRESSURE:"=",BOWLING:"-",KEG:"=",COW:"\\",TEAT:"`"}[armory.active]
                self.text(screen,token,(x+8,VIEW+1),color=AMBER,center=True,shadow=False)
                value = "-" if armory.active==SLING else str(armory.reserve[armory.active])
                self.text(screen,value,(x+25,VIEW+1),center=True,shadow=False)
                continue
            if armory.active==slot:
                pg.draw.line(screen,(189,132,79),(x,VIEW+7),(min(314,x+39),VIEW+7))
                pg.draw.rect(screen,(51,33,25),(x,VIEW+1,39,6))
            if armory.owned[slot]:
                icon=self.ammo_icons[i]
                screen.blit(icon,icon.get_rect(center=(x+8,VIEW+4)))
            pool=CROSSBOW if slot==DYNAMITE else slot
            text=str(armory.reserve[pool]) if armory.owned[slot] else "-"
            color=INK if armory.owned[slot] else (163,134,99)
            self.text(screen,text,(x+25,VIEW+1),color=color,center=True,shadow=False)

    @staticmethod
    def make_ammo_icons():
        icons=[pg.Surface((12,6),pg.SRCALPHA) for _ in BELT]
        silver,brass,lead,red,green=(185,174,145),(183,141,81),(115,119,107),(171,74,50),(129,152,79)
        for i in (0,3):
            a=icons[i]
            pg.draw.rect(a,brass,(1,2,6,3))
            pg.draw.line(a,(210,180,123),(1,2),(6,2))
            pg.draw.polygon(a,silver if i==0 else lead,((7,2),(9,2),(11,3),(9,4),(7,4)))
            if i==3:
                pg.draw.line(a,lead,(3,1),(9,1))
        for i in (1,2,6):
            a=icons[i]
            pg.draw.rect(a,red,(2,2,8,3))
            pg.draw.line(a,brass if i==1 else silver,(1,2),(1,4))
            if i!=1:
                pg.draw.line(a,brass,(5,1),(5,5))
                pg.draw.line(a,lead,(10,2),(11,1))
            if i==2:
                pg.draw.line(a,silver,(1,1),(8,1))
        a=icons[4]
        pg.draw.ellipse(a,lead,(1,0,10,6))
        pg.draw.line(a,silver,(3,1),(8,1))
        a.set_at((6,3),(45,39,32))
        a=icons[5]
        for x in (2,5,8):
            pg.draw.rect(a,green,(x,1,2,4))
            a.set_at((x,1),silver)
        return icons

    def meter(self, screen, x, y, label, value, colors):
        pg.draw.rect(screen,(57,46,38),(x,y,91,12),border_radius=2)
        pg.draw.line(screen,(172,159,132),(x+2,y),(x+88,y))
        pg.draw.line(screen,(100,92,76),(x+1,y+1),(x+1,y+9))
        pg.draw.line(screen,(125,111,92),(x+2,y+10),(x+88,y+10))
        self.text(screen,label,(x+4,y+2),shadow=False)
        x += 32
        pg.draw.rect(screen,(29,23,19),(x-2,y+2,58,8))
        for i in range(11):
            active = value > i * 9
            ink = colors[min(2, i // 4)]
            shade = ink if active else tuple(c // 4 for c in ink)
            pg.draw.rect(screen,shade,(x+i*5,y+3,4,6))
            if active:
                pg.draw.line(screen, tuple(min(255, c + 24) for c in shade),
                             (x + i * 5, y + 3), (x + i * 5 + 3, y + 3))

    def gauge(self, screen,x,y,label,value):
        key = "_dial_"+label
        if key not in self.faces:
            dial = pg.Surface((44,31),pg.SRCALPHA)
            pg.draw.polygon(dial,(128,124,106),((0,23),(4,5),(9,0),(35,0),(41,6),(43,23),(38,27),(6,27)))
            pg.draw.line(dial,(192,180,146),(7,1),(36,1))
            pg.draw.line(dial,(62,54,44),(4,26),(39,26))
            pg.draw.rect(dial,(50,43,37),(5,3,34,20),border_radius=5)
            pg.draw.ellipse(dial,(189,172,132),(6,4,32,21))
            pg.draw.rect(dial,(50,43,37),(5,17,34,6))
            colors = ((167,152,57),(109,139,68),(163,68,48))
            if label == "DRUNK":
                colors = ((170,151,65),(180,125,60),(172,62,42))
            def ring(a,r):
                return 22+round(math.cos(a)*r),17-round(math.sin(a)*r*.80)
            for i in range(30):
                a = math.radians(153-126*i/30)
                b = math.radians(153-126*(i+1)/30)
                pg.draw.polygon(dial,colors[min(2,i//10)],(ring(a,16),ring(b,16),ring(b,10),ring(a,10)))
            for i in range(0,31,5):
                a = math.radians(153-126*i/30)
                pg.draw.line(dial,(69,59,42),ring(a,17),ring(a,15))
            self.text(dial,label,(22,19),"mini",center=True,shadow=False)
            for v in (3,40):
                pg.draw.circle(dial,(72,57,42),(v,22),2)
                dial.set_at((v-1,21),(170,149,102))
            self.faces[key] = dial
        screen.blit(self.faces[key],(x,y))
        a = math.radians(153-126*max(0,min(100,value))/100)
        center = x+22,y+17
        end = center[0]+round(math.cos(a)*16),center[1]-round(math.sin(a)*12)
        pg.draw.line(screen,(68,45,34),center,end,2)
        pg.draw.line(screen,(235,194,116),center,end)
        pg.draw.circle(screen,(102,84,57),center,2)
        for i,color in enumerate(((162,141,66),(127,145,68),(184,108,55),(191,65,42))):
            px=x+10+8*i
            py=y+29
            pg.draw.circle(screen,(50,36,28),(px,py),3)
            pg.draw.circle(screen,color if min(3,int(value/25))==i else (77,60,46),(px,py),2)

    def objective_pin(self, screen, game):
        """Thin compass chevron toward the live objective, with distance."""
        target = game.objective_target()
        if not target:
            return
        p = game.player
        dx, dy = target[0] - p.x, target[1] - p.y
        distance = math.hypot(dx, dy)
        if distance < .8:
            return
        rel = (math.atan2(dy, dx) - p.view_angle + math.pi) % math.tau - math.pi
        x = 160 + max(-1., min(1., rel / math.pi)) * 118
        color = (244, 194, 116)
        pg.draw.polygon(screen, (38, 27, 21), ((x, 7), (x - 4, 13), (x + 4, 13)))
        pg.draw.polygon(screen, color, ((x, 8), (x - 3, 12), (x + 3, 12)))
        self.text(screen, f"{int(distance)}", (int(x), 14), "mini", color,
                  center=True, shadow=True)

    def draw(self, screen, game, armory):
        screen.blit(self.plate, (0, VIEW))
        self.ammo_rail(screen,armory)
        if game.hints and not game.map and game.clock > game.message_until and game.clock > game.district_until:
            self.objective_pin(screen, game)
        slot = armory.active
        amount = armory.reserve[CROSSBOW] if slot == DYNAMITE else armory.loaded[slot] if slot not in (0,SLING) else "-"
        health=max(0,game.player.health)
        self.number(screen,health,29,VIEW+23,health<=25)
        if health<=25 and int(game.clock*3)%2==0:
            pg.draw.line(screen,(214,74,48),(14,VIEW+37),(44,VIEW+37),2)
        self.number(screen,amount,77,VIEW+23,amount==0)
        if slot not in (DYNAMITE,SLING,CROWBAR) and armory.loaded[slot]==0 and armory.reserve[slot]>0:
            self.text(screen,"RELOAD",(77,VIEW+36),"mini",AMBER,center=True,shadow=False)
        for i, name in enumerate(("key_brass", "key_steel")):
            center=(111+8*i,VIEW+28+3*i)
            if name in game.keys:
                icon=self.icon(name,9,12)
                screen.blit(icon,icon.get_rect(center=center))
            else:
                pg.draw.circle(screen,(68,53,43),center,2,1)
                pg.draw.line(screen,(68,53,43),center,(center[0],center[1]+4))
        face_name = game.face_name()
        if face_name not in self.faces:
            image = self.art.get("face_" + face_name)
            canvas = pg.Surface((41,36), pg.SRCALPHA)
            image=image.subsurface(image.get_bounding_rect(min_alpha=128))
            h=35
            image = pg.transform.smoothscale(image, (round(image.get_width() * h / image.get_height()), h))
            canvas.blit(image, image.get_rect(center=(20,18)))
            self.faces[face_name] = canvas
        screen.blit(self.faces[face_name], (129, VIEW + 7))
        if game.hud_style:
            self.gauge(screen,176,VIEW+10,"GUT",game.player.gut)
            self.gauge(screen,222,VIEW+10,"DRUNK",game.player.drunk)
        else:
            self.meter(screen, 176, VIEW + 12, "GUT", game.player.gut,
                       ((104, 132, 65), (155, 149, 67), (188, 146, 65)))
            self.meter(screen, 176, VIEW + 27, "DRUNK", game.player.drunk,
                       ((180, 131, 54), (193, 100, 46), (182, 60, 46)))
        active = ITEMS[game.inventory_slot]
        icon = self.icon(active,13,13)
        screen.blit(icon,icon.get_rect(center=(283,VIEW+27)))
        count=game.inventory[active]
        self.text(screen,str(count),(300,VIEW+24),color=AMBER if count else (191,161,119),center=True)
        self.text(screen,("RINDS","BEER","SHINE","WHSKY","PIE")[game.inventory_slot],(291,VIEW+34),
                  "mini",center=True,shadow=False)

    def title(self, screen, index, entries, note=""):
        screen.blit(self.art.get("title_backdrop"), (0, 0))
        screen.blit(self.art.get("title_logo"), (9, 9))
        self.panel(screen,(16,85,154,14),(42,28,21))
        self.text(screen,"THE HICKSTON INCIDENT",(23,89),shadow=False)
        row = title_row_height(entries)
        self.panel(screen,(16,100,174,len(entries)*row+3),(38,26,22),(115,79,53))
        for i, entry in enumerate(entries):
            y = TITLE_FIRST + row * i
            if i == index:
                pg.draw.rect(screen,(94,56,31),(17,y,172,row))
                pg.draw.line(screen,(181,125,72),(17,y),(188,y))
                self.text(screen,">",(24,y+1),color=AMBER)
            self.text(screen,entry,(37,y+1),color=AMBER if i==index else INK)
        if note:
            self.banner(screen,note,185)
        else:
            self.panel(screen,(16,187,123,12),(37,26,21))
            self.text(screen,"ARROWS / ENTER",(22,190),shadow=False)

    def intermission(self, screen, game):
        following = next_level(game.level.id)
        if not following and game.history and not game.replay:
            self.campaign_report(screen, game)
            return
        screen.blit(self.art.get("title_backdrop"), (0, 0))
        self.panel(screen,(10,9,211,177))
        for line, y in zip(game.level.heading, (20, 38)):
            self.text(screen,line,(21,y),"heading",AMBER)
        self.text(screen,game.level.title,(21,61))
        pg.draw.line(screen,(135,95,63),(21,72),(208,72))
        minutes, seconds = divmod(int(game.clock), 60)
        for i,(key,value) in enumerate((
                ("VARMINTS",f"{game.kills:02d} / {game.total_kills:02d}"),
                ("SECRETS",f"{game.secrets:02d} / {game.total_secrets:02d}"),
                ("TIME",f"{minutes:02d}:{seconds:02d}"),
        )):
            y=79+i*18
            pg.draw.rect(screen,(30,21,17),(21,y,187,15))
            self.text(screen,key,(26,y+4))
            self.text(screen,value,(202,y+4),color=AMBER,right=True)
        self.text(screen,game.level.ending,(22,142),color=AMBER)
        action = "ENTER  CONTINUE TO CROSSROADS" if following and not game.replay else "ENTER  RETURN TO TITLE"
        self.text(screen,action,(22,165))

    def campaign_report(self, screen, game):
        screen.blit(self.art.get("title_backdrop"), (0, 0))
        self.panel(screen, (10, 9, 300, 180))
        self.text(screen, "SHIFT COMPLETE", (160, 20), "heading", AMBER, center=True)
        self.text(screen, "MAP", (21,53))
        for column, label in zip((186, 237, 296), ("KILLS", "SECRETS", "TIME")):
            self.text(screen,label,(column,53),right=True)
        results = (*game.history, game.result())
        for i, (level_id, kills, total, secrets, secret_total, seconds) in enumerate(results):
            y = 70 + 18*i
            pg.draw.rect(screen,(30,21,17),(17,y-4,286,16))
            self.text(screen,BY_ID[level_id].title,(21,y))
            for column, value in zip((186, 237, 296),
                                     (f"{kills}/{total}", f"{secrets}/{secret_total}",
                                      f"{seconds//60}:{seconds%60:02}")):
                self.text(screen,value,(column,y),color=AMBER,right=True)
        kills, total, secrets, secret_total, seconds = (sum(row[i] for row in results) for i in range(1,6))
        total_y = 70 + 18*len(results)+6
        self.text(screen,"TOTAL",(21,total_y),color=AMBER)
        for column,value in zip((186,237,296),(f"{kills}/{total}",f"{secrets}/{secret_total}",
                                               f"{seconds//60}:{seconds%60:02}")):
            self.text(screen,value,(column,total_y),color=AMBER,right=True)
        self.text(screen,game.level.ending,(21,total_y+15),color=AMBER)
        self.text(screen,"ENTER  RETURN TO CROSSROADS",(160,175),center=True)

