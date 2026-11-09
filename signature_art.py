"""Original model poses, textured cloth and projectile cels for wing enemies."""
from PIL import Image, ImageDraw

from actor_models import BRASS, INK, LEATHER, STEEL, SpriteCamera, band, fabric, joint, metal, star, trouser, volume
from expansion_art import ART, weather
from weapon_models import Mesh, render

UNIFORMS = {
    "yard_deputy": ((127,108,69),(55,65,56),(165,131,96),.29,1.66),
    "bottle_tosser": ((100,51,55),(107,100,78),(174,138,103),.255,1.57),
    "chain_hand": ((70,100,86),(90,75,50),(159,128,101),.34,1.70),
    "valve_rat": ((121,102,67),(75,82,79),(151,121,86),.31,1.26),
}


def actor(kind, frame):
    mesh = Mesh()
    shirt,pants,skin,w,head = UNIFORMS[kind]
    shirt,pants,skin = fabric(*shirt),fabric(*pants),fabric(*skin)
    aim,fire,pain = (frame==pose for pose in ("aim","fire","pain"))
    stride = frame if isinstance(frame,int) else 0
    shift = .054*stride + (-.10 if fire else .09 if pain else .02)
    head += -.065 if pain else -.052 if fire else .024 if aim else 0.
    chest = head-.39
    hip = chest-.43
    deputy,tosser,chain,rat = (kind==key for key in UNIFORMS)
    if rat and (aim or fire):
        head -= .10
        chest -= .085
        shift += .10 if aim else -.02
    for side in (-1,1):
        x = side*w*.57
        foot = stride*side*.19
        volume(mesh,[(.027,x,foot-.085,.112,.156),(.124,x,foot-.023,.102,.131),
                     (.173,x,foot+.012,.091,.091)],LEATHER,n=12)
        knee = (.21 if rat else .47+side*.031,x+side*.057,foot*.62-.047)
        trouser(mesh,(x,.141,foot),(knee[1],knee[0],knee[2]),(x+shift*.41,hip,.015),
                (.086,.105,.134),pants)
        for offset in (0,.075):
            band(mesh,(knee[1]-.077,knee[0]+offset,-.108+foot*.59),
                 (knee[1]+.052,knee[0]+.025+offset,-.125+foot*.59),LEATHER,.011)
    volume(mesh,[(hip,shift,.017,w*.71,.141),(hip+.15,shift,.020,w*.82,.173),
                 (chest,shift,.017,w,.191),(chest+.132,shift,.037,w*.83,.167),
                 (chest+.205,shift,.047,w*.48,.118)],shirt,n=16)
    for side in (-1,1):
        x = shift+side*w
        hand = (x+side*.11,chest-.24,-.26)
        if deputy and (aim or fire):
            hand = (shift+side*.145,chest-.02,-.28 if fire else -.37)
        if tosser and side==1:
            hand = (x+.16,chest+(.46 if aim else .17 if fire else -.31),-.47 if fire else -.12)
        if chain and (aim or fire):
            hand = (x+side*.15,chest+(.40 if aim else -.12),.07 if aim else -.44)
        if rat:
            hand = (shift+side*.19,chest-(.18 if aim or fire else .33),-.39)
        if pain:
            hand = (x+side*.15,chest+.10,-.10)
        elbow = (x+side*.084,(chest+hand[1])*.5-.095,-.08)
        mesh.link([(x,chest+.095,.044),elbow,hand],[.115,.091,.053],shirt)
        joint(mesh,hand,(.068,.058,.068),LEATHER if chain or rat else skin)
        if not deputy:
            band(mesh,(shift+side*.19,chest+.14,-.124),(shift+side*.115,hip+.02,-.148),
                 LEATHER if chain or rat else pants,.035)
        for fold in (0,1,2):
            y = chest-.12-fold*.061
            band(mesh,(shift+side*.11,y,-.172),(shift+side*(.24+.012*fold),y+.033,-.131),
                 fabric(*(int(value*.71) for value in shirt[:3])),.012)
    joint(mesh,(shift,head,.024),(.135,.167,.122),skin)
    joint(mesh,(shift+.006,head-.043,-.022),(.115,.10,.106),skin)
    joint(mesh,(shift+.012,head-.017,-.104),(.041,.047,.048),skin)
    for side in (-1,1):
        band(mesh,(shift+side*.105,head+.034,-.092),(shift+side*.032,head+.020,-.105),LEATHER,.014)
        joint(mesh,(shift+side*.057,head+.009,-.101),(.024,.012,.018),INK)
    band(mesh,(shift-.057,head-.079,-.121),(shift+.068,head-.068,-.122),LEATHER,.011)

    if deputy:
        volume(mesh,[(head+.066,shift,.018,.211,.163),(head+.103,shift,.018,.216,.175),
                     (head+.114,shift,.029,.140,.107),(head+.243,shift+.011,.028,.124,.096)],pants,n=16)
        star(mesh,shift-.145,chest+.015,-.15,.064,BRASS)
        band(mesh,(shift-.24,hip+.03,-.142),(shift+.245,hip+.02,-.154),LEATHER,.028)
        y = chest+(.017 if aim or fire else -.26)
        z = -.37 if aim else -.28 if fire else -.25
        mesh.loft([(z+.21,shift+.095,y-.015,.075,.066),(z+.01,shift+.10,y,.041,.034)],LEATHER,box=True)
        mesh.tube((shift+.10,y,z+.03),(shift+.105,y+.025,z-.31),.034,.021,STEEL)
        mesh.tube((shift+.10,y+.005,z),(shift+.105,y+.015,z-.25),.020,.015,INK)
    elif tosser:
        volume(mesh,[(head+.056,shift,.030,.153,.13),(head+.147,shift-.015,.040,.163,.139),
                     (head+.182,shift-.041,.053,.102,.083)],pants,n=14)
        mesh.block(shift+.053,head+.063,-.104,.24,.032,.151,pants)
        for i in range(3):
            y = chest-.08-i*.08
            band(mesh,(shift-.19,y,-.133),(shift+.15,y-.015,-.174),fabric(160,106,83),.024)
        for x in (shift-.24,shift-.14,shift+.20):
            mesh.tube((x,hip-.10,-.14),(x+.02,hip+.10,-.181),.047,.046,metal(98,116,86),n=11)
            mesh.tube((x+.02,hip+.09,-.18),(x+.035,hip+.19,-.19),.024,.020,BRASS,n=9)
        if not fire:
            x,y,z = shift+w+.16,chest+(.46 if aim else -.31),-.13
            mesh.tube((x,y-.09,z),(x+.12,y+.13,z-.04),.054,.043,metal(99,117,89),n=13)
            mesh.tube((x+.12,y+.13,z-.04),(x+.17,y+.204,z-.055),.022,.019,BRASS,n=9)
    elif chain:
        volume(mesh,[(head+.053,shift,.043,.210,.185),(head+.099,shift,.051,.221,.193),
                     (head+.178,shift-.028,.063,.158,.151)],metal(157,143,93),n=14)
        mesh.block(shift,head-.023,-.119,.258,.073,.05,INK)
        for i in range(7):
            y = chest+(.43 if aim else -.06 if fire else -.12)-.052*i
            x = shift+.36 + i*(.032 if fire else -.021)
            joint(mesh,(x,y,-.32 if aim or fire else -.199),(.053,.025,.036),STEEL if i%2 else LEATHER)
        mesh.block(shift-.12,chest-.15,-.19,.24,.23,.053,LEATHER)
    else:
        hood = fabric(86,86,62)
        volume(mesh,[(head-.15,shift,.057,.183,.124),(head+.02,shift,.068,.196,.157),
                     (head+.156,shift-.023,.084,.149,.138)],hood,n=14)
        mesh.block(shift,head+.005,-.107,.260,.062,.048,INK)
        for side in (-1,1):
            joint(mesh,(shift+side*.061,head+.007,-.136),(.029,.020,.014),BRASS)
        mesh.tube((shift-.22,hip-.12,.16),(shift-.21,chest+.18,.20),.113,.098,metal(104,126,116),n=14)
        mesh.link([(shift-.2,chest+.16,.19),(shift-.33,chest+.00,-.10),(shift+.12,chest-.19,-.27)],
                  [.034,.040,.038],LEATHER)
        y = chest-(.22 if aim or fire else .10)
        mesh.tube((shift+.17,y+.02,-.16),(shift+.19,y-.21,-.53 if aim else -.38),.069,.045,BRASS,n=14)
    return mesh


def projectile(name):
    image = Image.new("RGBA",(23,24))
    d = ImageDraw.Draw(image)
    if name=="fair_bottle":
        d.polygon(((2,18),(10,9),(15,8),(18,3),(21,5),(17,10),(16,15),(8,22)),fill="#3a4939")
        d.line((5,19,11,13,15,12),fill="#8c9e73",width=2)
        d.line((15,8,19,4),fill="#bba37b",width=2)
        d.polygon(((6,15),(10,11),(14,15),(10,19)),fill="#928257")
    elif name=="chain_hook":
        for x,y in ((4,16),(9,12),(14,8),(19,5)):
            d.ellipse((x-3,y-2,x+3,y+2),outline="#958d76",width=2)
        d.point((20,4),fill="#e8c394")
    else:
        d.line((3,16,18,7),fill="#67705b" if name=="valve_slug" else "#a77543",width=3)
        d.ellipse((12,5,21,12),fill="#abc4a0" if name=="valve_slug" else "#e7ba7e")
    return image


def bake():
    from actor_finish import finish
    from actor_models import turn_cels
    for kind in UNIFORMS:
        for frame in (-1,0,1,"aim","fire","pain","down"):
            down = frame=="down"
            yaw = {"yard_deputy":.29,"bottle_tosser":-.30,"chain_hand":.37,"valve_rat":-.36}[kind]
            image = render(actor(kind,0 if down else frame),SpriteCamera(yaw,down))
            bounds = image.getchannel("A").getbbox()
            if down:
                image = image.crop(bounds).resize((99,32),Image.Resampling.LANCZOS)
            else:
                half = 75 if kind in ("chain_hand","bottle_tosser") else 64
                top = 9 if kind=="bottle_tosser" else 22 if kind!="valve_rat" else 55
                image = image.crop((160-half,top,160+half,163))
            image = weather(image,175+len(kind),13,"weathered_plank_siding")
            image = finish(image,kind,frame,sampled=True)
            image.save(ART/f"{kind}_{frame}.png")
        turn_cels(kind,actor,(82,9 if kind=="bottle_tosser" else 55 if kind=="valve_rat" else 22,238,163),
                  lambda image,stem: image.save(ART/f"{stem}.png"))
    for name in ("fair_bottle","chain_hook","deputy_slug","valve_slug"):
        projectile(name).save(ART/f"fx_{name}.png")


if __name__ == "__main__":
    bake()
