"""Textured sprite cels for the fair and mill's own hostile roster."""
import math

import numpy as np
from PIL import Image, ImageDraw

from actor_models import (
    BRASS, INK, LEATHER, SHADOW, STEEL, SpriteCamera, band, fabric, flat, joint, metal, trouser, volume,
)
from expansion_art import ART, weather
from weapon_models import Mesh, render


def uniform(name, frame):
    mill = name == "millhand"
    walk = frame if isinstance(frame, int) else 0
    aim, fire, pain, recover = (frame==word for word in ("aim","fire","pain","recover"))
    shift = .06 if fire else -.09 if pain else .074 if recover else .02*walk
    drop = -.13 if fire and mill else -.06 if pain or recover else 0.
    m = Mesh()
    jacket = fabric(153,132,70) if mill else fabric(123,65,76)
    seam = fabric(218,177,81) if mill else fabric(188,147,110)
    denim = fabric(62,72,73) if mill else fabric(90,83,70)
    face = fabric(131,147,100) if mill else fabric(168,150,113)
    w = .42 if mill else .32
    for s in (-1,1):
        x = s*(w*.53) + shift*.35
        z = walk*.17*s - (.1 if fire and s>0 else 0.)
        lift = .036 if walk*s>0 else 0.
        volume(m,[(.04+lift,x,z-.10,.105,.16),(.15+lift,x,z-.03,.104,.12)], INK)
        trouser(m,(x,.15+lift,z),(x+s*.032,.50+s*.017,z*.4-.06),(x+shift*.7,.92+drop,.02),
                (.095,.108,.132),denim)
        band(m,(x-.075,.47,-.105+z*.4),(x+.071,.48,-.111+z*.4),LEATHER,.024)
    shoulder = shift+(.057 if mill else -.041)+(.042 if recover else 0.)
    volume(m,[(.68 if mill else .84,shift,.03,w*.81,.16),(.99+drop,shift-.019,.025,w*.72,.17),
              (1.21+drop,shift+.018,.006,w*.91,.186),(1.31+drop,shift,.01,w,.199),
              (1.50+drop,shoulder,.026,w*.92,.17),(1.58+drop,shoulder,.035,w*.53,.108)],jacket,n=16)
    for s in (-1,1):
        x = shift+s*.12
        band(m,(shift+s*.19,1.54+drop,-.09),(x,1.18+drop,-.184),seam,.040 if mill else .023)
        if mill:
            m.block(shift+s*.206,1.16+drop,-.169,.15,.11,.040,LEATHER)
        else:
            band(m,(shift+s*.16,1.29,-.187),(shift+s*.24,1.27,-.160),
                 fabric(101,133,130),.028)
    for i in range(5):
        m.block(shift, .92+i*.11+drop, -.181, .023,.024,.027,BRASS)
    if not mill:
        for s in (-1,1):
            flat(m,-.162,[(shift,1.49),(shift+s*.092,1.531),(shift+s*.092,1.456)],
                 fabric(167,179,149))
    eye = 1.75+drop
    hx = shift-(.07 if pain else 0)
    if mill:
        volume(m,[(eye-.23,hx,.016,.136,.115),(eye-.09,hx,.01,.203,.154),
                  (eye+.092,hx,.03,.193,.160),(eye+.16,hx,.045,.123,.102)],jacket)
        joint(m,(hx,eye-.065,-.11),(.125,.154,.082),face)
        volume(m,[(eye+.062,hx,.01,.226,.188),(eye+.094,hx,.01,.213,.184),
                  (eye+.183,hx,.037,.148,.119)],metal(194,154,78))
        m.block(hx+.08,eye+.074,-.158,.10,.046,.060,STEEL)
        band(m,(hx-.092,eye-.102,-.173),(hx+.09,eye-.108,-.173),LEATHER,.026)
    else:
        joint(m,(hx,eye-.048,.006),(.145,.193,.142),face)
        volume(m,[(eye+.086,hx,.012,.241,.171),(eye+.110,hx,.009,.242,.171)],LEATHER)
        volume(m,[(eye+.107,hx,.030,.163,.131),(eye+.256,hx+.022,.039,.129,.102)],jacket)
        volume(m,[(eye+.117,hx,.031,.165,.134),(eye+.153,hx,.031,.165,.134)],seam)
        joint(m,(hx-.011,eye-.075,-.134),(.05,.038,.042),fabric(148,71,64))
        band(m,(hx-.089,eye-.147,-.132),(hx+.078,eye-.130,-.133),
             fabric(188,170,124),.024)
    for s in (-1,1):
        band(m,(hx+s*.107,eye-.013,-.122),(hx+s*.032,eye-.027,-.143),INK,.021)
        joint(m,(hx+s*.065,eye-.037,-.153),(.020,.011,.018),fabric(205,169,99))
    if mill:
        blade_x = shift+(.50 if fire else -.15 if aim else .28 if recover else .37)
        blade_y = 1.28 if aim else .84 if fire else .94 if recover or pain else 1.10
        grip = (blade_x-.23,blade_y,-.30)
        for s in (-1,1):
            palm = (grip[0]+s*.13,grip[1]+s*.06,grip[2]+s*.06)
            m.link([(shift+s*w,1.44+drop,.016),(shift+s*.46,1.16+drop,-.045),palm],
                   [.122,.106,.079],jacket)
            joint(m,palm,(.078,.056,.077),LEATHER)
        m.block(blade_x-.10,blade_y,-.32,.33,.18,.24,metal(132,91,59))
        m.block(blade_x+.24,blade_y-.028,-.34,.45,.105,.052,STEEL)
        for i in range(8):
            m.block(blade_x+.04+i*.052,blade_y+.035,-.34,.027,.041,.051,SHADOW)
    else:
        y = 1.61 if fire else 1.50 if aim else 1.05 if recover else 1.11
        grip = (shift+.28 if pain else shift+.34,y,-.18 if fire else -.27)
        m.link([(shift+w,1.46+drop,.007),(shift+.46,1.20+drop,-.03),grip],[.099,.081,.058],jacket)
        joint(m,grip,(.073,.056,.062),face)
        m.link([(shift-w,1.43,.02),(shift-.42,1.18,-.04),(shift-.32,1.02,-.22)],
               [.104,.085,.061],jacket)
        for x in (shift-.306,shift-.338,shift-.366):
            band(m,(x,1.052,-.196),(x-.028,.971,-.278),face,.017)
        start=(grip[0],y+.06,grip[2]+.04)
        end=(grip[0]+.054,y+(.19 if fire else .117),grip[2]-.22)
        m.tube(start,end,.065,.129,metal(136,126,108),n=13)
        m.tube(end,(end[0]+.003,end[1]+.003,end[2]-.010),.108,.108,
               fabric(230,157,90) if fire else fabric(183,124,70) if aim else INK,n=13)
    return m


def creature(name, frame):
    lamp = name == "lantern"
    wind = frame=="aim"
    fire = frame=="fire"
    gait = frame if isinstance(frame, int) else 0
    lift = .14 if wind else .04 if fire else .0
    m = Mesh()
    hide = fabric(114,129,104) if lamp else fabric(139,116,88)
    plates = metal(190,146,82) if lamp else fabric(180,141,103)
    pulse = fabric(248,212,135) if fire or wind else fabric(198,177,110) if lamp else fabric(178,177,120)
    if lamp:
        volume(m,[(.21,0,.03,.21,.18),(.32,0,.03,.37,.27),(.52,0,.015,.41,.31),
                  (.70,0,0,.34,.27),(.82,0,.012,.16,.12)],hide)
        volume(m,[(.51,0,-.17,.244,.13),(.67,0,-.163,.268,.152),
                  (.74,0,-.17,.19,.103)],plates)
        for i in range(3):
            x=(i-1)*.122
            joint(m,(x,.621,-.318),(.067,.084,.052),pulse)
            band(m,(x-.035,.53,-.353),(x-.035,.71,-.353),SHADOW,.011)
        for s in (-1,1):
            m.link([(s*.20,.42,0),(s*.36,.30,-.09),(s*.48,.23+gait*.05,-.20),
                    (s*.44,.10+gait*.04,-.41)],[.097,.066,.045,.013],hide)
    else:
        joint(m,(.0,.38+lift,.066),(.46,.226,.28),hide)
        joint(m,(.03,.41+lift,-.231),(.237,.185,.16),plates)
        for s in (-1,1):
            joint(m,(s*.137,.48+lift,-.35),(.041,.028,.031),pulse)
            band(m,(s*.146,.412+lift,-.352),(s*.10,.34+lift,-.376),LEATHER,.041)
            band(m,(s*.10,.34+lift,-.376),(s*.036,.32+lift,-.413),fabric(199,176,125),.026)
            for i,z in enumerate((-.26,.020,.27)):
                knee = .35+(.04 if wind else .0)
                m.link([(s*.24,.34+lift,z),(s*(.48+.044*i),knee,z+.04*gait),
                        (s*(.57+.02*i),.062+(.05 if (i+gait)%2 else 0),z+.14*gait)],
                       [.067,.050,.026],hide)
        for x in (-.10,.08,.23):
            band(m,(x,.53+lift,.01),(x+.10,.50+lift,.19),fabric(142,103,83),.032)
    return m


def projectile(amber):
    image = Image.new("RGBA",(22,22))
    d = ImageDraw.Draw(image)
    for radius, color in ((9,"#987252" if amber else "#6e8c68"),
                          (7,"#c49456" if amber else "#8eb578"),
                          (3,"#f7d7a0" if amber else "#e2dc95")):
        d.arc((11-radius,11-radius,11+radius,11+radius),17,342,fill=color,width=2)
    d.ellipse((9,9,13,13),fill="#f0d8ab")
    return image


def make_enemies():
    from actor_finish import finish
    from actor_models import turn_cels
    for name in ("barker","millhand","crawler","lantern"):
        big = name in ("barker","millhand")
        for frame in (-1,0,1,"aim","fire","pain","down"):
            down = frame=="down"
            build = uniform if big else creature
            image = render(build(name,0 if down else frame),SpriteCamera(.32,down))
            if down:
                image = image.crop(image.getchannel("A").getbbox()).resize((96,32))
            elif big:
                image = image.crop((89,10,231,163))
            else:
                image = image.crop((104,91,216,163))
            image = weather(image,243,11,"corrugated_iron" if name=="lantern" else "weathered_plank_siding")
            image = finish(image,name,frame,sampled=True)
            image.save(ART/f"{name}_{frame}.png")
        if big:
            turn_cels(name,uniform,(81,10,239,163),lambda image,stem: image.save(ART/f"{stem}.png"),recover_pose=True)
    projectile(True).save(ART/"fx_barker_bolt.png")
    projectile(False).save(ART/"fx_lantern_bolt.png")


if __name__ == "__main__":
    make_enemies()
