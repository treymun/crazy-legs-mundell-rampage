"""Bake the county's improvised weapons and their registered reload cels."""
import json
import math

from PIL import Image, ImageDraw

from expansion_art import ART, weather
from weapon_art import digitized_pose
from weapon_models import BLACK, BRASS, METAL, STEEL, WOOD, Camera, Mesh, glove, render

OXIDE = (109,67,43,"iron",.46)
ASH = (97,81,56,"wood",.19)
PIPE = (77,82,83,"blued",.63)
PAPER = (157,64,43,"paper",.11)
LABEL = (191,155,100,"paper",.11)
RUBBER = (48,47,44,"rubber",.06)
HAMMER_CASE = (77,101,99,"enamel",.33)
COPPER = (122,81,52,"copper",.51)
VERDIGRIS = (73,97,82,"enamel",.27)


def hand(mesh, x, y, z):
    glove(mesh, (x,y,z), (x+.10,y-.14,z-.16), [
        [(x-.03,y+.03,z+.022),(x-.08,y+.06,z+.06),(x-.089,y+.05,z+.091)],
        [(x-.03,y-.035,z+.04),(x-.089,y+.011,z+.10),(x-.110,y+.019,z+.10)],
        [(x-.03,y-.077,z+.045),(x-.081,y-.023,z+.097),(x-.108,y-.022,z+.090)],
        [(x-.031,y-.096,z+.017),(x-.078,y-.064,z+.076),(x-.101,y-.047,z+.073)],
    ])


def sling(pose):
    m = Mesh()
    m.tube((-.05,-.12,.24),(-.07,.15,2.14),.059,.046,WOOD,n=11)
    m.tube((-.071,.15,1.91),(-.073,.18,2.24),.061,.058,OXIDE,n=10)
    points = [(-.075,.14,1.98),(-.094,.23,2.19),(-.187,.36,2.38),
              (-.411,.47,2.56),(-.499,.437,2.52),(-.433,.324,2.32),
              (-.296,.233,2.15),(-.187,.182,2.07)]
    underside = [(x,y-.028,z) for x,y,z in points]
    m.face(points,OXIDE)
    m.face(list(reversed(underside)),METAL)
    for i in range(len(points)):
        j=(i+1)%len(points)
        m.face([points[i],points[j],underside[j],underside[i]],STEEL if 2<=i<=5 else METAL)
    for (x,y,z),(a,b,c) in zip(points[2:6],points[3:7]):
        m.tube((x,y+.003,z),(a,b+.003,c),.013,.009,STEEL,n=6)
    if pose != "pickup":
        hand(m,.00,-.071,.74)
    return m, (-.42,.42,2.49)


def bottle_launcher(pose):
    m=Mesh()
    # Fence-pipe launcher on a split plank, with a hinge below the bore.
    tilt={"open":.26,"eject":.43,"load":.39,"close":.09}.get(pose,0.)

    def tube_point(z,x=-.035,y=.086):
        return x,y-(z-1.42)*math.sin(tilt),1.42+(z-1.42)*math.cos(tilt)

    m.loft([(.37,.019,-.102,.092,.142),(.63,.010,-.086,.115,.133),
            (1.08,-.023,-.045,.108,.084),(1.71,-.034,-.035,.093,.067)],ASH,n=12)
    m.tube((-.023,-.06,.78),(.015,-.34,.65),.079,.062,ASH,n=12)
    for z in (.85,.96,1.43):
        m.loft([(z,-.023,-.055,.117,.097),(z+.054,-.023,-.054,.118,.092)],RUBBER,n=12)
    m.loft([(1.023,-.023,-.051,.115,.096),(1.093,-.023,-.051,.114,.092)],PAPER,n=12)
    m.block(-.032,.012,1.377,.247,.137,.188,OXIDE)
    m.tube((-.172,.022,1.416),(.113,.022,1.416),.045,.046,STEEL,n=12)
    # A folded fence strap supports the pipe while leaving a visible gap above the plank.
    m.link([(-.108,-.030,1.25),(-.147,.006,1.30),(-.169,.097,1.39),
            tube_point(1.51,-.146,.121)],(.023,.027,.025,.018),OXIDE)
    m.block(-.141,-.034,1.26,.041,.028,.096,STEEL)
    m.tube((-.164,-.018,1.246),(-.181,-.018,1.246),.023,.019,BRASS,n=9)
    m.tube(tube_point(1.41),tube_point(2.24),.134,.111,PIPE,n=20)
    for z,r in ((1.45,.145),(1.66,.133),(1.91,.122),(2.16,.126)):
        m.tube(tube_point(z),tube_point(z+.045),r,r*.98,OXIDE if z in (1.45,2.16) else STEEL,n=18)
    m.tube(tube_point(2.218),tube_point(2.249),.123,.117,STEEL,n=22)
    m.tube(tube_point(2.25),tube_point(2.252),.076,.072,BLACK,n=20)
    m.tube(tube_point(1.407),tube_point(1.399),.117,.106,STEEL,n=18)
    m.tube(tube_point(1.398),tube_point(1.396),.077,.071,BLACK,n=18)
    latch = tube_point(1.46,-.119,.15)
    m.link([latch,tube_point(1.38,-.162,.134),tube_point(1.30,-.172,.104)],
           (.027,.025,.019),STEEL)
    m.link([tube_point(1.50,-.14,.135),tube_point(1.73,-.15,.164),tube_point(2.14,-.113,.173)],
           (.013,.016,.010),STEEL)
    for z in (1.67,1.91):
        m.tube(tube_point(z,-.18,.077),tube_point(z,-.139,.077),.026,.023,BRASS,n=9)
    if pose in ("idle","close","pickup","load","eject"):
        z={"load":1.17,"eject":1.07}.get(pose,2.15)
        x=-.098 if pose=="eject" else -.035
        y=.13 if pose=="eject" else .086
        m.tube(tube_point(z,x,y),tube_point(z+.25,x,y),.076,.071,RUBBER if pose=="eject" else PAPER,n=16)
        m.tube(tube_point(z+.147,x,y),tube_point(z+.195,x,y),.076,.074,LABEL,n=16)
        m.tube(tube_point(z+.248,x,y),tube_point(z+.332,x,y),.071,.009,BRASS,n=14)
        if pose=="load":
            m.link([tube_point(z+.012,x,y),tube_point(z-.069,x-.014,y+.045),
                    tube_point(z-.11,x-.046,y+.036)],(.011,.008,.005),VERDIGRIS)
    if pose!="pickup":
        hand(m,.032,-.195,.68)
        if pose in ("eject","load"):
            hand(m,-.194,.050,1.13 if pose=="load" else 1.01)
        else:
            hand(m,-.113,-.133,1.37)
    return m,tube_point(2.254)


def riveter(pose):
    m=Mesh()
    # A short pneumatic tool with an enamel hammer case and a side-fed strip.
    slide=.13 if pose=="kick" else .052 if pose=="recover" else 0.
    m.tube((.031,-.10,.84),(.090,-.36,.77),.097,.081,RUBBER,n=12)
    m.tube((.089,-.349,.76),(.104,-.44,.68),.047,.034,BRASS,n=11)
    m.link([(.10,-.43,.68),(.13,-.52,.52),(.095,-.57,.40)],(.038,.038,.032),RUBBER)
    m.loft([(.65,.005,.030,.084,.107),(.77,0,.030,.163,.149),
            (1.24,0,.039,.169,.147),(1.43,-.009,.047,.117,.091)],HAMMER_CASE,n=12)
    # Exposed gunmetal collar with a stepped driving jaw and return springs.
    m.loft([(1.29,-.012,.051,.101,.098),(1.44,-.012,.052,.105,.092),
            (1.49,-.013,.052,.081,.071)],PIPE,n=12)
    for side in (-1,1):
        m.link([(side*.104,.053,1.30),(side*.109,.061,1.45),
                (side*.074,.072,1.59-slide*.40)],(.024,.026,.017),STEEL)
        m.tube((side*.101,.054,1.48),(side*.094,.061,1.55-slide*.20),.032,.027,OXIDE,n=9)
    m.tube((-.012,.052,1.28),(-.016,.052,1.68-slide),.079,.063,PIPE,n=18)
    m.tube((-.016,.052,1.66-slide),(-.016,.052,1.77-slide),.076,.070,STEEL,n=18)
    m.tube((-.016,.052,1.77-slide),(-.016,.052,1.775-slide),.043,.039,BLACK,n=18)
    lift={"open":.14,"eject":.24,"load":.17,"close":.05}.get(pose,0.)
    m.block(-.145,.025+lift,.986,.07,.074,.43,PIPE)
    m.block(-.181,.076+lift,1.002,.024,.029,.40,STEEL)
    m.block(-.171,.120+lift,1.147,.069,.030,.086,OXIDE)
    for z in (.86,.93,1.00,1.07,1.14):
        m.tube((-.158,.082+lift,z),(-.158,.115+lift,z),.022,.013,BRASS,n=8)
        m.tube((.143,.051,z),(.167,.051,z),.017,.014,STEEL,n=8)
    m.block(-.043,.184,.950,.12,.019,.19,LABEL)
    m.block(.098,.112,.918,.164,.060,.244,OXIDE)
    m.block(.098,.144,.917,.145,.013,.211,STEEL)
    for z in (.859,.911,.965):
        m.block(.104,.152,z,.079,.009,.014,PIPE)
    m.block(-.045,.195,.963,.075,.007,.021,OXIDE)
    for z in (1.14,1.21,1.28):
        m.block(0,.166,z,.115,.018,.018,BLACK)
    if pose!="pickup":
        hand(m,.046,-.218,.76)
        if lift:
            hand(m,-.207,.044+lift,.94 if pose!="load" else 1.04)
    return m,(-.016,.052,1.779-slide)


def pressure_gun(pose):
    m=Mesh()
    # Orchard sprayer reservoir, braided hose and a visible dial set high on the left.
    m.loft([(.59,.053,-.061,.096,.101),(.69,.060,-.061,.179,.157),
            (1.23,.055,-.058,.185,.163),(1.44,.058,-.058,.112,.112)],VERDIGRIS,n=20)
    for z,r in ((.73,.183),(1.17,.189),(1.34,.154)):
        m.tube((.057,-.06,z),(.057,-.06,z+.042),r,r*.98,PIPE,n=18,ratio=.87)
    m.tube((.062,-.091,.62),(.073,-.298,.63),.083,.069,RUBBER,n=12)
    m.tube((.026,.074,1.20),(-.021,.080,1.59),.091,.081,COPPER,n=17)
    m.tube((-.021,.081,1.55),(-.021,.082,1.83),.076,.047,PIPE,n=17)
    m.tube((-.021,.082,1.79),(-.021,.082,1.88),.079,.068,BRASS,n=16)
    m.tube((-.021,.082,1.88),(-.021,.082,1.886),.037,.032,BLACK,n=17)
    pump={"kick":.12,"recover":.17,"load":.21,"open":.10}.get(pose,0.)
    m.tube((-.024,-.123,1.24-pump),(-.024,-.123,1.70-pump),.070,.065,RUBBER,n=14)
    for z in (1.30,1.37,1.44,1.51,1.58):
        m.tube((-.024,-.123,z-pump),(-.024,-.123,z+.028-pump),.075,.073,PIPE,n=14)
    m.link([(.207,-.105,.72),(.272,-.193,.86),(.252,-.192,1.25),(.151,-.109,1.53),
            (.029,.008,1.63)],(.034,.039,.038,.032,.025),RUBBER)
    gx,gy=-.140,.228
    m.tube((-.068,.065,1.10),(gx,gy,1.15),.034,.034,COPPER,n=12)
    m.tube((gx,gy,1.18),(gx,gy,1.113),.112,.110,BRASS,n=20)
    m.tube((gx,gy,1.112),(gx,gy,1.107),.087,.087,(185,170,126,"paper",.09),n=20)
    needle=(gx+.051,gy+.029) if pose in ("kick","recover") else (gx-.045,gy+.032)
    m.link([(gx+.013,gy-.014,1.104),(gx,gy,1.103),(*needle,1.103)],
           (.008,.009,.007),OXIDE)
    for dx,dy in ((-.05,.05),(0.,.069),(.053,.05),(.07,0.)):
        m.tube((gx+dx,gy+dy,1.106),(gx+dx,gy+dy,1.102),.006,.006,BLACK,n=6)
    stem={"open":.214,"eject":.317,"load":.259,"close":.147}.get(pose,.126)
    m.tube((.10,.085,.92),(.10,stem,.92),.056,.052,BRASS,n=14)
    m.tube((.10,stem,.92),(.10,stem+.045,.92),.073,.068,PIPE,n=13)
    if pose in ("load","eject"):
        m.tube((.103,stem+.038,.905),(.106,stem+.18,.93),.042,.036,
               COPPER if pose=="load" else RUBBER,n=13)
    if pose!="pickup":
        hand(m,.094,-.172,.60)
        if pose in ("load","eject"):
            hand(m,-.061,stem+.044,.91)
        else:
            hand(m,-.099,-.173,1.48-pump)
    return m,(-.021,.082,1.89)


VIEW_POSES = {
    "bottle_launcher": {
        "idle":dict(x=.06,y=.165,yaw=-.11,roll=-.085),
        "kick":dict(x=.095,y=.22,yaw=-.13,pitch=-.074,z=-.14,roll=-.116),
        "recover":dict(x=.076,y=.185,yaw=-.12,pitch=-.023,z=-.043,roll=-.102),
        "open":dict(x=.06,y=.275,yaw=-.19,roll=-.24),
        "eject":dict(x=.03,y=.29,yaw=-.27,roll=-.35),
        "load":dict(x=.03,y=.30,yaw=-.26,roll=-.30),
        "close":dict(x=.06,y=.22,yaw=-.15,roll=-.16),
    },
    "riveter": {
        "idle":dict(x=.025,y=.168,yaw=.095,roll=.045,z=.11),
        "kick":dict(x=.057,y=.190,yaw=.10,pitch=-.11,roll=.026,z=.034),
        "recover":dict(x=.038,y=.172,yaw=.10,pitch=-.038,roll=.040,z=.072),
        "open":dict(x=.06,y=.21,yaw=-.031,roll=-.12),
        "eject":dict(x=.055,y=.24,yaw=-.155,roll=-.27),
        "load":dict(x=.046,y=.244,yaw=-.144,roll=-.225),
        "close":dict(x=.04,y=.18,yaw=.030,roll=-.07),
    },
    "pressure_gun": {
        "idle":dict(x=-.20,y=.122,yaw=-.22,roll=-.075,z=.14),
        "kick":dict(x=-.15,y=.165,yaw=-.23,pitch=-.068,roll=-.09,z=.02),
        "recover":dict(x=-.18,y=.15,yaw=-.21,pitch=-.023,roll=-.10,z=.08),
        "open":dict(x=-.20,y=.22,yaw=-.18,roll=-.205),
        "eject":dict(x=-.19,y=.25,yaw=-.19,roll=-.32),
        "load":dict(x=-.18,y=.23,yaw=-.14,roll=-.30),
        "close":dict(x=-.18,y=.15,yaw=-.18,roll=-.17),
    },
}


def ammo(rocket):
    im = Image.new("RGBA",(42,29))
    d = ImageDraw.Draw(im)
    for y in (4,11,18):
        d.line((7,y+4,35,y+4),fill="#594d39",width=5)
        d.line((13,y+2,32,y+2),fill="#985642" if rocket else "#a49f83",width=4)
        d.polygon(((31,y),(39,y+2),(32,y+4)),fill="#c4a466" if rocket else "#ccc5a3")
    return weather(im,125,9)


def make_weapons():
    anchor_file = ART/"weapon_anchors.json"
    anchors = json.loads(anchor_file.read_text(encoding="utf-8"))
    for name,make in (("slingblade",sling),("bottle_launcher",bottle_launcher),
                      ("riveter",riveter),("pressure_gun",pressure_gun)):
        blade = name=="slingblade"
        poses = (("idle","wind","strike","follow","recover") if blade else
                 ("idle","kick","recover","open","eject","load","close"))
        anchors[name] = {}
        for pose in (*poses,"pickup"):
            mesh,muzzle = make(pose)
            if pose == "pickup":
                image = render(mesh,Camera(side=True, yaw=.12))
                image = image.crop(image.getchannel("A").getbbox())
                image.thumbnail((50,35),Image.Resampling.LANCZOS)
                image.save(ART/f"item_{name}.png")
                continue
            if blade:
                roll, yaw, height = {
                    "idle":(-.15,.11,.15),"wind":(-.38,-.17,.31),"strike":(.36,.21,.37),
                    "follow":(.52,.37,.25),"recover":(.13,.19,.17),
                }[pose]
                camera = Camera(roll=roll,yaw=yaw,y=height)
            else:
                camera = Camera(**VIEW_POSES[name][pose])
            image = render(mesh,camera)
            digitized_pose(image,name,pose).save(ART/f"gun_{name}_{pose}.png")
            if not blade:
                anchors[name][pose] = [round(float(n),1) for n in camera.project(muzzle)[:2]]
    anchor_file.write_text(json.dumps(anchors,separators=(",",":")),encoding="utf-8")
    ammo(True).save(ART/"item_rocket_ammo.png")
    ammo(False).save(ART/"item_rivet_ammo.png")
    charges=Image.new("RGBA",(44,30))
    d=ImageDraw.Draw(charges)
    for x in (3,15,27):
        d.rounded_rectangle((x+1,5,x+13,26),3,fill="#8c654a",outline="#423328")
        d.line((x+4,10,x+4,24),fill="#bf9262",width=2)
        d.rectangle((x+3,4,x+11,8),fill="#a7926b",outline="#685c47")
    weather(charges,73,16,"corrugated_iron").save(ART/"item_pressure_ammo.png")
    rocket = ammo(True).crop((6,0,40,9))
    rocket = rocket.rotate(-32,Image.Resampling.BICUBIC,expand=True)
    rocket.save(ART/"fx_bottle_rocket.png")


if __name__ == "__main__":
    make_weapons()
