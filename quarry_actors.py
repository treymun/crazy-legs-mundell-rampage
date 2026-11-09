"""Bake distinct digitized cels for the quarry crew and three new finales."""
import math

from PIL import Image, ImageDraw

from actor_models import BRASS, INK, LEATHER, SHADOW, STEEL, SpriteCamera, band, fabric, joint, metal, trouser, volume
from expansion_art import ART, weather
from weapon_models import Mesh, render


LOOK = {
    "boilerback": ((102,116,87),(162,124,72),.40,.84),
    "chalk_spitter": ((155,151,115),(177,150,113),.235,.94),
    "rudy": ((138,66,56),(191,152,113),.34,.88),
    "foreman": ((67,95,94),(164,126,71),.44,.89),
    "baron": ((113,80,53),(173,132,74),.51,.69),
}


def actor(kind,frame):
    uniform,trim,w,hip=LOOK[kind]
    m=Mesh()
    chalk=kind=="chalk_spitter"
    performer=kind=="rudy"
    steam=kind in ("baron","boilerback")
    baron=kind=="baron"
    foreman=kind=="foreman"
    stride=frame if isinstance(frame,int) else 0
    aim,fire,pain,recover=(frame==pose for pose in ("aim","fire","pain","recover"))
    clothing=fabric(*uniform)
    high=fabric(*trim)
    shift=.064*stride+(.13 if pain else -.123 if fire else .067 if aim else .087 if recover else 0.)
    drop=(-.19 if chalk else -.12 if baron else 0.)+(-.12 if pain or fire else -.070 if recover else 0.)
    chest=1.32+drop
    tilt=-.112 if foreman else -.085 if baron else -.10 if chalk else 0.
    for s in (-1,1):
        x=s*w*.62
        foot=stride*s*.18+(.063*s if baron or foreman else 0.) + s*(.076 if fire else .04 if recover else 0.)
        boot=INK if not chalk else fabric(112,103,83)
        volume(m,[(.035,x,foot-.081,.122,.167),(.18,x,foot,.104,.116)],boot)
        trouser(m,(x,.16,foot),(x+.064*s,.47+.029*s,foot*.52-.04),(x+shift*.46,hip,.015),
                (.086,.102,.132) if not chalk else (.063,.077,.117),fabric(85,89,78) if not chalk else clothing)
        if steam or kind=="foreman":
            joint(m,(x+s*.032,.52,-.096),(.070,.089,.048),high)
            band(m,(x-s*.054,.31,-.078),(x+s*.08,.36,-.100),LEATHER,.024)
        if performer:
            band(m,(x+.085*s,.81,-.095),(x+.106*s,.26,-.084),high,.014)
    lean = (.055 if performer else -.048 if foreman else .031)+(.045 if recover else 0.)
    volume(m,[(hip,shift,.025,w*.71,.147),(hip+.16,shift-.028,.019,w*.82,.168),
              (1.10+drop,shift,.035+tilt*.35,w*.96,.178),
              (chest+.05,shift+lean*.4,.048+tilt,w*.93,.205),
              (1.46+drop,shift+lean,.049+tilt,w*.79,.177),
              (1.53+drop,shift+lean,.047+tilt,w*.71,.161),
              (1.60+drop,shift+lean*.82,.05+tilt,w*.46,.121)],clothing,n=16)
    for s in (-1,1):
        hand=(shift+s*(.34 if aim else .44),chest-(.04 if aim else .26),-.29 if aim or fire else -.13)
        if chalk:
            hand=(shift+s*(.35 if aim and s>0 else .44),chest-(.03 if aim and s>0 else .51),
                  -.38 if s>0 else -.19)
        elif performer and s==1:
            hand=(shift+.31,chest+(.28 if aim else .11 if fire else -.17),-.37)
        elif foreman and (aim or fire):
            hand=(shift+s*.39,chest+(.26 if aim else -.26),-.32 if fire else -.14)
        elif baron:
            hand=(shift+s*(.41 if aim else .49),chest+(.11 if aim else -.23),-.34 if aim or fire else -.13)
        if pain:
            hand=(shift+s*(.32 if s<0 else .48),chest+(.11 if s<0 else -.34),-.18)
        elif recover:
            hand=(shift+s*(.39 if s<0 else .31),chest-(.35 if s<0 else .23),-.28)
        elbow=(shift+s*(w+(.052 if s<0 else .11)),chest-.17+s*.035,-.08)
        m.link([(shift+s*w*.83,chest+.13,.033+tilt),elbow,hand],
               [.101,.097,.062] if chalk else [.135,.107,.076],clothing)
        joint(m,hand,(.080,.071,.072),high if chalk else LEATHER)
        band(m,(shift+s*.27,1.52+drop,-.11),(shift+s*.17,1.18+drop,-.177),high,.026)
        for y in (chest-.23,chest-.38):
            band(m,(shift+s*.19,y,-.169),(shift+s*.28,y+.038,-.128),LEATHER,.017)
    if chalk:
        jaw_y=1.48+(.09 if aim else -.062 if fire else 0)
        joint(m,(shift-.022,jaw_y,.003),(.175,.192,.180),fabric(184,169,130))
        joint(m,(shift,jaw_y-.064,-.161),(.191,.100,.176),fabric(193,169,119))
        m.block(shift,jaw_y-.068,-.312,.25,.093 if aim else .050,.028,INK)
        for i in (-2,-1,1,2):
            joint(m,(shift+i*.037,jaw_y-.066,-.328),(.016,.025,.012),fabric(203,184,129))
        for s in (-1,1):
            band(m,(shift+s*.134,jaw_y+.035,-.123),(shift+s*.051,jaw_y+.013,-.164),SHADOW,.022)
            joint(m,(shift+s*.093,jaw_y+.014,-.173),(.028,.019,.018),fabric(211,189,108))
        for i in range(4):
            band(m,(shift-.16+i*.10,1.49,.10),(shift-.19+i*.10,1.16,.227),high,.027)
        for s in (-1,1):
            for i in (0,1,2):
                band(m,(shift+s*(.075+i*.049),chest-.048-i*.066,-.181),
                     (shift+s*(.168+i*.040),chest-.072-i*.063,-.151),fabric(138,132,99),.024)
            joint(m,(shift+s*.43,chest-.55,-.23),(.061,.099,.068),fabric(180,164,122))
        return m
    head_y=1.68+drop
    if performer:
        skin=fabric(182,149,111)
        joint(m,(shift,head_y,.022),(.139,.168,.126),skin)
        joint(m,(shift+.009,head_y-.015,-.107),(.040,.052,.053),skin)
        band(m,(shift-.092,head_y-.057,-.103),(shift+.081,head_y-.063,-.116),LEATHER,.019)
        for s in (-1,1):
            band(m,(shift+s*.089,head_y+.035,-.096),(shift+s*.026,head_y+.029,-.125),INK,.013)
            joint(m,(shift+s*.053,head_y+.018,-.12),(.017,.011,.018),fabric(212,188,140))
        volume(m,[(head_y+.09,shift,.022,.203,.156),(head_y+.133,shift,.022,.205,.161),
                  (head_y+.15,shift,.012,.140,.113),(head_y+.33,shift,.012,.156,.12)],INK)
        volume(m,[(head_y+.151,shift,.012,.145,.119),(head_y+.194,shift,.012,.150,.12)],high)
        for s in (-1,1):
            for i in (0,1,2):
                band(m,(shift+s*(.086+i*.055),chest+.18,-.170),
                     (shift+s*(.055+i*.055),hip-.06,-.148),high,.014)
        m.block(shift,1.52,-.157,.26,.104,.040,fabric(216,191,143))
        for y in (1.19,1.29,1.40):
            joint(m,(shift+.014,y,-.192),(.016,.018,.015),BRASS)
        y=chest+(.26 if aim else .11 if fire else -.17)
        tip_y = y+(.23 if aim else .034)
        m.tube((shift+.29,y,-.25),(shift+.39,tip_y,-.56),.062,.174,metal(169,138,88),n=18)
        m.tube((shift+.39,tip_y,-.56),(shift+.394,tip_y+.004,-.572),.144,.144,
               fabric(235,189,107) if aim or fire else SHADOW,n=14)
    elif kind=="foreman":
        joint(m,(shift,head_y+.017,.024),(.211,.173,.158),metal(109,123,104))
        volume(m,[(head_y+.079,shift,-.027,.245,.176),(head_y+.119,shift,-.024,.248,.173),
                  (head_y+.185,shift+.024,.008,.186,.148)],STEEL,n=18)
        m.tube((shift,head_y-.021,-.135),(shift,head_y-.019,-.168),.168,.169,INK,n=15,ratio=.33)
        band(m,(shift-.118,head_y-.014,-.176),(shift+.103,head_y-.025,-.178),high,.018)
        volume(m,[(chest-.36,shift+.03,-.101,.217,.122),(chest-.16,shift,-.108,.246,.128),
                  (chest+.12,shift-.047,-.111,.203,.123)],LEATHER,n=14)
        m.link([(shift-.31,head_y+.10,.142),(shift-.40,head_y-.15,.147),
                (shift-.44,chest-.33,-.112)],[.043,.047,.034],SHADOW)
        band(m,(shift+.31,head_y-.02,.16),(shift+.56,head_y+.145,.085),STEEL,.048)
        for s in (-1,1):
            joint(m,(shift+s*.208,chest+.048,-.174),(.078,.102,.065),STEEL)
            y=chest+(.25 if aim else -.25 if fire else -.07)
            m.tube((shift+s*.23,y,-.21),(shift+s*.35,y,-.43),.068,.11,metal(145,114,76),n=11)
            m.block(shift+s*.47,y+.014,-.44,.33,.071,.045,high)
            for tooth in range(5):
                x = shift+s*(.36+tooth*.059)
                band(m,(x,y+.05,-.45),(x+s*.019,y+.075,-.45),STEEL,.013)
    else:
        bowl=metal(153,114,73) if kind=="baron" else metal(117,128,106)
        if baron:
            hood=fabric(81,64,48)
            volume(m,[(head_y-.207,shift,.044,.268,.169),(head_y-.06,shift,.048,.252,.181),
                      (head_y+.071,shift-.034,.081,.203,.155),(head_y+.175,shift-.059,.090,.148,.106)],
                   hood,n=17)
            band(m,(shift-.18,head_y-.13,-.124),(shift+.159,head_y-.095,-.145),LEATHER,.039)
            for s in (-1,1):
                m.link([(shift+s*.237,head_y-.02,.02),(shift+s*.36,head_y-.153,.086),
                        (shift+s*.39,chest-.35,.102)],[.040,.049,.038],BRASS)
            band(m,(shift-.20,chest-.31,-.165),(shift+.19,chest-.31,-.165),STEEL,.039)
            # Salvaged asymmetric still, shoulder straps and an exposed bleed valve.
            volume(m,[(chest-.32,shift-.44,.153,.123,.149),(chest-.19,shift-.46,.168,.193,.166),
                      (chest+.29,shift-.47,.168,.187,.162),(chest+.45,shift-.47,.171,.125,.119),
                      (chest+.54,shift-.47,.171,.086,.081)],bowl,n=19)
            band(m,(shift-.48,chest+.53,.159),(shift-.49,chest+.76,.10),BRASS,.043)
            m.tube((shift-.49,chest+.76,.10),(shift-.59,chest+.80,-.07),.040,.032,STEEL,n=12)
            for y in (chest-.15,chest+.17):
                volume(m,[(y,shift-.46,.166,.192,.166),(y+.044,shift-.46,.166,.197,.171)],STEEL,n=19)
            band(m,(shift+.07,chest+.21,-.158),(shift+.33,chest-.34,-.156),high,.061)
            m.tube((shift+.35,chest-.19,-.13),(shift+.46,chest+(.045 if aim else -.23),-.48),
                   .104,.081,BRASS,n=15)
            m.tube((shift+.46,chest+(.045 if aim else -.23),-.48),
                   (shift+.465,chest+(.052 if aim else -.224),-.496),.056,.059,INK,n=15)
        else:
            joint(m,(shift,head_y-.02,.018),(.168,.171,.144),fabric(154,125,93))
            volume(m,[(head_y+.073,shift,.017,.203,.163),(head_y+.126,shift,.023,.207,.170),
                      (head_y+.168,shift-.019,.061,.135,.102)],bowl)
            m.block(shift,head_y-.075,-.132,.268,.111,.071,SHADOW)
            for s in (-1,1):
                m.tube((shift+s*.104,head_y-.099,-.13),(shift+s*.105,head_y-.103,-.214),
                       .066,.058,STEEL,n=12)
        m.tube((shift,head_y+.045,-.132),(shift,head_y+.043,-.181),
               .174 if baron else .126,.163 if baron else .120,INK,n=14,ratio=.33)
        for s in (-1,1):
            m.block(shift+s*.074,head_y+.047,-.190,.104 if kind=="baron" else .052,.036 if kind=="baron" else .018,.019,
                    fabric(214,163,87) if aim or fire else fabric(145,145,100))
            if baron and s<0:
                continue
            x=shift+s*w*.80
            m.tube((x,chest-.31,.16),(x,chest+.41,.18),.11,.103,bowl,n=13)
            m.tube((x,chest+.39,.178),(x,chest+.53,.184),.057,.056,STEEL,n=11)
        m.tube((shift,chest-.078,-.201),(shift,chest-.078,-.263),.109,.105,BRASS,n=16)
        m.tube((shift,chest-.078,-.265),(shift,chest-.078,-.272),.079,.079,
               fabric(223,182,110) if aim or fire else high,n=16)
        band(m,(shift,chest-.082,-.277),(shift+(.061 if aim else -.036),chest-.043,-.277),INK,.014)
        band(m,(shift-.17,chest+.17,-.19),(shift-.30,chest-.19,-.176),STEEL,.037)
    return m


def effect_art():
    for name,inside,border in (
        ("warning",(186,129,69,40),(237,184,96,210)),
        ("chalk",(134,146,87,140),(192,192,122,200)),
        ("steam",(162,127,89,100),(230,176,102,220)),
    ):
        im=Image.new("RGBA",(64,64))
        d=ImageDraw.Draw(im)
        d.ellipse((2,2,61,61),fill=inside,outline=border,width=3)
        for i in range(7):
            angle=i*math.tau/7
            x,y=(32+24*math.cos(angle),32+24*math.sin(angle))
            d.line((x,y,x-6*math.cos(angle),y-6*math.sin(angle)),fill=border,width=2)
        im.save(ART/f"mark_{name}.png")
    im=Image.new("RGBA",(72,12))
    d=ImageDraw.Draw(im)
    for x in range(0,72,11):
        d.polygon(((x,1),(x+5,1),(x+12,10),(x+7,10)),fill=(232,168,85,212))
    im.save(ART/"mark_lane.png")
    im=Image.new("RGBA",(56,56))
    d=ImageDraw.Draw(im)
    d.ellipse((1,1,54,54),fill="#4b4740",outline="#82745a",width=3)
    for i in range(13,46,7):
        d.line((12,i,44,i),fill="#211e1a",width=3)
        d.line((14,i+2,42,i+2),fill="#9c8968")
    weather(im,62,17,"corrugated_iron").save(ART/"mark_outlet.png")
    for name,color in (("chalk",(191,183,125)),("steam",(214,196,157))):
        im=Image.new("RGBA",(64,39))
        d=ImageDraw.Draw(im)
        for x,y,rx,ry,opacity in ((7,34,7,3,55),(18,29,11,5,53),(30,24,14,10,52),
                                  (45,29,12,7,47),(55,32,7,4,44),(38,13,9,7,40),(24,9,5,6,28)):
            d.ellipse((x-rx,y-ry,x+rx,y+ry),fill=(*color,opacity))
        im.save(ART/f"fx_{name}_mist.png")
    for name,body,edge in (("chalk_lob","#9e9f67","#d6c586"),
                           ("rudy_horn","#c27c47","#eed39a"),
                           ("foreman_cut","#938b6c","#e4d2a0")):
        im=Image.new("RGBA",(24,22))
        d=ImageDraw.Draw(im)
        d.ellipse((2,4,21,18),fill=body,outline=edge,width=2)
        d.line((6,8,16,7),fill=edge,width=2)
        if name=="foreman_cut":
            d.line((1,12,22,9),fill=edge,width=2)
        im.save(ART/f"fx_{name}.png")


def bake():
    from actor_finish import finish
    from actor_models import turn_cels
    for kind in LOOK:
        for frame in (-1,0,1,"aim","fire","pain","down"):
            down=frame=="down"
            yaw={"boilerback":.40,"chalk_spitter":.43,"rudy":.21,"foreman":.41,"baron":.28}[kind]
            image=render(actor(kind,0 if down else frame),SpriteCamera(yaw,down))
            if down:
                image=image.crop(image.getchannel("A").getbbox()).resize((100,32),Image.Resampling.LANCZOS)
            else:
                image=image.crop((74,8,246,163) if kind=="baron" else (79,8,241,163) if kind=="foreman"
                                 else (85,8,234,163))
            image=weather(image,142+len(kind),17,"corrugated_iron" if kind in ("baron","foreman") else
                          "weathered_plank_siding")
            image=finish(image,kind,frame,sampled=True)
            image.save(ART/f"{kind}_{frame}.png")
            if frame==0 and kind=="rudy":
                grain=ImageDraw.Draw(image)
                for y in range(49,135,8):
                    grain.line((41,y,101,y),fill=(120,92,64,180))
                grain.polygon(((45,135),(109,135),(117,150),(43,151)),fill="#705b43")
                image.save(ART/"rudy_decoy.png")
        turn_cels(kind,actor,(72,8,248,163),lambda image,stem: image.save(ART/f"{stem}.png"),recover_pose=True)
    effect_art()


if __name__=="__main__":
    bake()
