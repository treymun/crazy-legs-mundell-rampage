"""Textured, hand-built character models baked to period sprite cels."""
import math
from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from weapon_models import Mesh, render


def fabric(r, g, b):
    return r, g, b, "hide", .06


def metal(r, g, b):
    return r, g, b, "iron", .36


INK = fabric(39, 35, 30)
LEATHER = fabric(65, 47, 35)
BRASS = metal(194, 151, 74)
STEEL = metal(116, 118, 112)
SHADOW = metal(49, 52, 53)


class SpriteCamera:
    side = False
    natural = True

    def __init__(self, yaw, down=False):
        a = .40 if down else .09
        c, s = math.cos(yaw), math.sin(yaw)
        u, v = math.cos(a), math.sin(a)
        self.rotation = np.array(((c, 0, s), (v*s, u, -v*c), (-u*s, v, u*c)))
        self.down = down

    def project(self, xyz):
        x, y, z = (np.asarray(xyz) @ self.rotation.T).T
        if self.down:
            return np.stack((160 + y*66, 119 + x*53 - z*23, 3+z*.5+x*.08), axis=-1)
        return np.stack((160+x*70, 162-y*70, 3+z*.55), axis=-1)


def volume(mesh, sections, color, n=10):
    """Rings of height, center, width and depth, from the feet upward."""
    phi = np.arange(n) * math.tau / n
    mesh.rings([[(x+r*math.cos(a), y, z-d*math.sin(a)) for a in phi]
                for y,x,z,r,d in sections], color)


def joint(mesh, at, size, color):
    x,y,z = at
    r,h,d = size
    volume(mesh, [(y+t*h,x,z,r*s,d*s) for t,s in
                  ((-1,.26),(-.66,.77),(0,1),(.60,.82),(1,.29))], color)


def flat(mesh, z, pts, color):
    mesh.face([(x,y,z) for x,y in reversed(pts)], color)


def band(mesh, a, b, mat, width=.026):
    mesh.tube(a, b, width, width*.95, mat, n=7)


def trouser(mesh,ankle,knee,hip,radii,color):
    """Bunched cuffs and a bent, loaded knee, aligned to each footfall."""
    ankle,knee,hip = map(np.asarray,(ankle,knee,hip))
    cuff,patella,thigh = radii
    shin = knee-ankle
    rise = hip-knee
    mesh.link((ankle,ankle+.17*shin+(.011,0,-.012),knee-.19*shin,
               knee+(0,0,-.023),knee+.18*rise,hip-.29*rise,hip),
              (cuff*.85,cuff*1.18,cuff*.90,patella,patella*.82,thigh*.94,thigh),color)


def star(mesh, x, y, z, radius, color):
    for i in range(10):
        angles = [(i+j)*math.tau/10 + math.pi/2 for j in (0, 1)]
        points = [(x,y,z)] + [(x+math.cos(a)*radius*(1 if (i+j)%2==0 else .44),
                               y+math.sin(a)*radius*(1 if (i+j)%2==0 else .44), z)
                              for j,a in enumerate(angles)]
        mesh.face(points, color)


def humanoid(name, frame):
    if name == "coot":
        return lanky_shooter(frame)
    m = Mesh()
    sheriff, guard, heavy = name == "boss", name == "alien", name == "billy"
    clone = name=="clone"
    aim, fire, pain, recover = (frame==pose for pose in ("aim","fire","pain","recover"))
    ready = aim or fire
    fidget = frame=="fidget"
    walk = frame if isinstance(frame, int) else 0
    shift = (-.127 if pain else -.072 if fire else .042 if aim else -.037 if fidget else .068 if recover else 0) + .028*walk
    drop = (-.101 if pain else -.034 if fire else -.060 if recover else -.014*abs(walk)) - (.14 if heavy else 0.)
    navy = fabric(82, 97, 110)
    duster = fabric(117, 103, 71)
    lining = fabric(79, 68, 54)
    green = fabric(105, 102, 68)
    denim = (77,96,114,"denim",.05) if heavy else (71,89,102,"denim",.05)
    rust = fabric(143, 72, 52)
    armor = metal(99,113,88)
    edge = metal(147,147,111)
    rubber = fabric(59,62,48)
    alien_skin = (130,142,103,"skin",.11)
    skin = (167,118,80,"skin",.09)
    face = (157,149,103,"skin",.09) if sheriff else skin
    pants = navy if sheriff else rubber if guard else denim
    shirt = duster if sheriff else rubber if guard else skin if heavy else (112,90,66,"flannel",.05)
    spread = .27 if heavy else .20 if sheriff else .17
    width = .37 if sheriff else .47 if heavy else .32
    eye = (1.70 if heavy else 1.77)+drop
    stoop = -.18 if heavy else -.07 if clone else 0.
    for s in (-1,1):
        strike = s*walk
        toe = strike*.21 + ((-.122 if s<0 else .074) if heavy else s*.058 if clone else 0.)
        kx = s*(spread+.028) + shift*.44 + (.036 if heavy else 0.)
        ax = s*(spread+.044+(.032 if heavy and s<0 else 0.))
        sole = (.134,.197) if heavy else (.114,.174)
        lift = max(0,strike)*.055
        volume(m, [(.05+lift,ax,toe-.050,*sole),(.105+lift,ax,toe-.061,*sole),
                   (.173+lift,ax,toe+.013,.097,.102)],LEATHER if heavy else INK)
        leg = ((ax,.16+lift,toe+.025),(kx,.46+s*.021,-strike*.073-.08*heavy),
               (s*spread+shift,.91+drop,0))
        if guard:
            m.link(leg,(.092,.118,.125),pants)
        else:
            trouser(m,*leg,(.112,.148,.175) if heavy else (.090,.113,.125),pants)
        if heavy:
            band(m,(kx-.111,.43,-strike*.073-.17),(kx+.09,.50,-strike*.073-.20),
                 fabric(145,134,97) if s<0 else fabric(67,65,54),.027)
        if sheriff:
            band(m,(ax+s*.078,.23,toe-.027),(kx+s*.100,.55,-strike*.073-.032),
                 fabric(131,112,75),.012)
            band(m,(kx+s*.100,.55,-strike*.073-.032),(s*(spread+.106)+shift,.84,0),
                 fabric(131,112,75),.012)
        if guard:
            joint(m,(kx,.51,-strike*.073-.108),(.111,.115,.057),armor)
            band(m,(ax,.21,toe-.067),(kx,.45,-strike*.073-.113),armor,.049 if s>0 else .035)
        else:
            z = -strike*.073-.108
            band(m,(kx-.071,.45,z),(kx+.063,.49,z+.012),fabric(114,108,83) if heavy else pants,.013)
    twist = -.066 if pain else .047 if recover else .027 if aim else .011*walk
    volume(m, [(.78+drop,shift,.016,width*.83,.178),(.93+drop,shift-.019,.012,width*.99,.202),
               (1.035+drop,shift+.012,.024,width*.93,.211),
               (1.20+drop,shift+twist*.45,.016+stoop*.51,width,.236 if heavy else .198),
               (1.37+drop,shift+twist,.018+stoop,width*(.87 if heavy else .95),.198 if heavy else .176),
               (1.47+drop,shift+twist,.025+stoop,width*(.77 if heavy else .97),.202 if heavy else .182),
               (1.54+drop,shift+twist*.81,.034+stoop,width*.70,.133)],shirt,n=16)
    volume(m, [(.94+drop,shift,.019,width*.91,.181), (1.015+drop,shift,.019,width*.91,.179)], LEATHER)
    m.block(shift,.975+drop,-.166,.118,.060,.037,BRASS)
    if guard:
        volume(m,[(1.05+drop,shift,-.101,.198,.112),(1.22+drop,shift+.038,-.108,.232,.123),
                  (1.39+drop,shift-.038,-.091,.245,.122),(1.50+drop,shift-.038,-.071,.139,.119)],
               armor,n=18)
        band(m,(shift-.15,1.421+drop,-.181),(shift+.101,1.366+drop,-.216),edge,.027)
        joint(m,(shift-.345,1.443+drop,.017),(.148,.124,.152),armor)
        joint(m,(shift+.326,1.427+drop,-.014),(.095,.084,.142),alien_skin)
        for s in (-1,1):
            band(m,(shift+s*.185,1.13+drop,-.17),(shift+s*.23,1.40+drop,-.12),LEATHER,.019)
    elif sheriff:
        # A county-issue coat repaired with whatever was on hand.
        for s in (-1,1):
            x = shift+s*.166
            m.block(x,1.27+drop,-.161,.145,.125,.038,fabric(134,115,76))
            band(m,(x-.075,1.323+drop,-.186),(x+.071,1.340+drop,-.187),lining,.015)
            band(m,(shift+s*.064,1.55+drop,-.098),(shift+s*.127,1.397+drop,-.203),
                 fabric(153,128,87),.029)
        flat(m,-.202,[(shift-.123,1.51+drop),(shift+.105,1.514+drop),
                      (shift+.088,1.44+drop),(shift-.056,1.361+drop)],rust)
        band(m,(shift-.104,1.48+drop,-.211),(shift+.054,1.437+drop,-.216),
             fabric(176,94,65),.013)
        star(m,shift+.205,1.405+drop,-.217,.078,BRASS)
        m.block(shift-.270,1.373+drop,-.177,.080,.160,.066,SHADOW)
        band(m,(shift-.293,1.442+drop,-.187),(shift-.311,1.599+drop,-.155),SHADOW,.013)
        band(m,(shift+.053,1.225+drop,-.193),(shift+.033,1.029+drop,-.181),lining,.016)
        m.block(shift+.309,.955+drop,-.064,.15,.23,.14,LEATHER)
        band(m,(shift+.291,1.020+drop,-.148),(shift+.372,1.066+drop,-.140),
             fabric(145,105,66),.019)
    else:
        bib = denim
        bib_z = -.285 if heavy else -.203
        half = .324 if heavy else .234
        if heavy:
            volume(m,[(.76+drop,shift,.014,half*.93,.17),(.91+drop,shift,-.034,half*1.25,.211),
                      (1.13+drop,shift,-.052,half*1.08,.248),(1.31+drop,shift-.045,-.087,half*.74,.196)],
                   bib,n=18)
        else:
            flat(m,bib_z,[(shift-half,.94+drop),(shift+half,.94+drop),(shift+half*.68,1.338+drop),
                         (shift-half*.68,1.338+drop)],bib)
        m.block(shift,1.171+drop,bib_z-.013,.201,.130,.021,fabric(97,107,110))
        for s in (-1,1):
            band(m,(shift+s*.24,1.508+drop,-.076+stoop),(shift+s*half*.67,1.32+drop,bib_z),bib,.044)
            band(m,(shift+s*.24,1.50+drop,.11+stoop),(shift+s*.14,1.04+drop,.198),bib,.043)
            m.block(shift+s*half*.67,1.315+drop,bib_z-.028,.050,.054,.026,BRASS)
            if heavy:
                m.block(shift+s*.329,1.06+drop,-.166,.055,.155,.036,fabric(121,79,52))
        band(m,(shift-.103,1.546+drop,-.104),(shift+.114,1.524+drop,-.102),
             rust if heavy else LEATHER,.035)
    for s in (-1,1):
        shoulder=(shift+s*(width+.004),1.416+drop,.005+stoop)
        if ready:
            elbow=(shift+s*(width+.10),1.24+drop+(.10 if fire and s>0 else 0),-.20 if s<0 else -.13)
            palm=(shift+s*(.21 if sheriff or guard else .13),1.40+drop+(.16 if fire else 0.),
                  -(.51 if s==1 else .34)+(.13 if fire else 0.))
        elif pain:
            elbow=(shift+s*(width+.095),1.20+drop,.106)
            palm=(shift+s*(.22 if s<0 else .43),1.205+drop+(.19 if s<0 else -.06),-.123)
        elif recover:
            elbow=(shift+s*(width+.04),1.28+drop,-.07)
            palm=(shift+s*.164,1.05+drop+(.14 if s<0 else 0),-.40)
        else:
            elbow=(shift+s*(width+.066),1.18+drop,-.017+.08*s*walk)
            palm=(shift+s*.22,1.122+drop,-.29+.045*s*walk)
        if fidget and s<0:
            elbow=(shift-width-.12,1.31+drop,-.09+stoop)
            palm=(shift-.148,eye+.064,-.044+stoop)
        if heavy:
            shoulder=(shoulder[0]-.067*s,shoulder[1]+s*.044,shoulder[2])
            elbow=(elbow[0]-.025*s,elbow[1]-.062-.067*s,elbow[2]-.047)
            palm=(palm[0]-.027*s,palm[1]-.050+s*.087,palm[2]-.095)
            upper=(np.asarray(shoulder)*.55+np.asarray(elbow)*.45)
            joint(m,upper,(.124,.157,.13),skin)
            m.link([shoulder,elbow,palm],[.119,.103,.062],skin)
            if s<0:
                a=np.asarray(elbow)*.65+np.asarray(palm)*.35
                m.tube(a,a+(np.asarray(palm)-a)*.22,.086,.083,lining,n=9)
        elif clone and s>0:
            cuff=np.asarray(elbow)*.62+np.asarray(palm)*.38
            m.link((shoulder,elbow,cuff),(.103,.083,.061),shirt)
            m.tube(cuff,palm,.061,.055,skin,n=11)
            band(m,elbow,cuff,green,.065)
        else:
            start,hinge,end = map(np.asarray,(shoulder,elbow,palm))
            m.link((start,.64*start+.36*hinge,hinge,.56*hinge+.44*end,end),
                   (.104,.111,.076,.089 if sheriff else .079,.059),shirt)
        if guard or sheriff:
            m.tube(elbow, tuple(np.asarray(elbow)*.42+np.asarray(palm)*.58), .088,.077,
                   armor if guard else lining if s==1 else fabric(137,116,75),n=8)
        if sheriff and s==1:
            band(m,(shoulder[0]+.006,shoulder[1]-.024,shoulder[2]-.096),
                 (elbow[0]-.014,elbow[1]+.050,elbow[2]-.084),navy,.046)
        joint(m,palm,(.073,.060,.081),face if sheriff else alien_skin if guard else skin)
    if not pain:
        # Physical receiver and bores; aiming changes hands as well as the weapon.
        x=shift+.115
        y=(1.576 if fire else 1.415 if aim else 1.105 if recover else 1.151)+drop-(.07 if heavy else 0.)
        z=(-.274 if fire else -.398 if aim else -.35 if recover else -.245)+stoop*.62
        if sheriff or guard:
            m.block(x,y,z,.221,.148,.302,armor if guard else STEEL)
            for i in range(3):
                m.block(x,y+.013,z-.04-i*.063,.229,.041,.026,SHADOW)
            m.tube((x,y,z-.125),(x,y,z-.34),.091,.069,SHADOW)
            m.tube((x,y,z-.306),(x,y,z-.361),.072,.068,STEEL)
            m.tube((x,y,z-.361),(x,y,z-.374),.041,.039,
                   fabric(255,151,75) if fire or aim and sheriff else
                   fabric(160,203,165) if aim else INK)
            m.block(x,y+.087,z-.12,.089,.028,.16,BRASS if sheriff else edge)
            m.flash_origin = (x,y,z-.382)
        else:
            a=(x-.252,y-.04,z+.11)
            b=(x+.101,y+.03,z-.14)
            end=(x+.195,y+.079,z-(.52 if heavy and ready else .36 if ready else .28 if heavy else .21))
            m.tube(a,b,.060,.044,LEATHER,n=7)
            m.tube(b,end,.038,.028,SHADOW)
            if heavy:
                m.tube((b[0]+.049,b[1],b[2]),(end[0]+.040,end[1],end[2]),.031,.025,STEEL)
            m.flash_origin = end
    hx = shift + (.024 if not pain else -.085)
    if guard:
        volume(m,[(eye-.204,hx,.028,.096,.102),(eye-.11,hx,.017,.151,.139),
                  (eye+.02,hx,.022,.153,.139),(eye+.14,hx,.043,.113,.117)],alien_skin,n=17)
        volume(m,[(eye+.031,hx,.039,.161,.130),(eye+.112,hx+.014,.046,.155,.125),
                  (eye+.206,hx+.030,.063,.095,.096)],armor,n=16)
        joint(m,(hx,eye-.095,-.127),(.090,.089,.067),rubber)
        for s in (-1,1):
            joint(m,(hx+s*.153,eye-.054,-.045),(.058,.062,.066),armor)
            band(m,(hx+s*.119,eye+.019,-.115),(hx+s*.035,eye-.008,-.156),INK,.024)
            band(m,(hx+s*.092,eye-.007,-.144),(hx+s*.045,eye-.016,-.161),
                 fabric(236,198,112) if ready else fabric(181,154,87),.012)
            band(m,(hx+s*.105,eye-.063,-.159),(hx+s*.071,eye-.145,-.177),edge,.015)
        band(m,(hx-.040,eye-.114,-.188),(hx+.040,eye-.117,-.190),fabric(154,142,94),.013)
    else:
        neck = eye-.25
        joint(m,(hx,neck,-.009+stoop),(.085,.109,.083),face)
        w = .158 if sheriff else .137 if heavy else .124
        volume(m, [(eye-.190,hx,-.046,w*.63,.089),
                   (eye-.131,hx,-.020,w*.82,.132),
                   (eye-.050,hx,.009,w,.142),
                   (eye+.065,hx,.019,w*.97,.139),
                   (eye+.121,hx,.026,w*.68,.105)],face)
        for s in (-1,1):
            joint(m,(hx+s*w*.96,eye-.041,.01),(.044 if sheriff else .026,.072,.035),face)
            joint(m,(hx+s*.071,eye-.076,-.101),(.053,.045,.036),face)
            a=(hx+s*.100,eye+.020,-.111)
            b=(hx+s*.021,eye-.007,-.134)
            band(m,a,b,LEATHER,.020 if sheriff else .013)
            band(m,(a[0],a[1]-.020,a[2]-.012),(b[0],b[1]-.015,b[2]-.008),
                 fabric(220,130,62) if sheriff else fabric(83,63,52),.009)
        joint(m,(hx,eye-.063,-.132),(.036,.055,.043),face)
        band(m,(hx-.056,eye-.143,-.121),(hx+.052,eye-.135,-.127),
             fabric(81,64,42) if sheriff else LEATHER,.016)
        if sheriff:
            # A broken brim, sunken cheek and mismatched tooth read through the VGA shading.
            felt=fabric(143,117,80)
            volume(m,[(eye+.093,hx-.032,.019,.334,.218),(eye+.114,hx-.024,.017,.322,.225),
                      (eye+.130,hx+.008,.024,.280,.205)],felt,n=22)
            band(m,(hx-.246,eye+.102,-.124),(hx-.161,eye+.112,-.177),lining,.024)
            band(m,(hx+.137,eye+.118,-.164),(hx+.239,eye+.139,-.096),felt,.027)
            volume(m,[(eye+.123,hx,.027,.176,.136),(eye+.208,hx+.012,.040,.143,.121),
                       (eye+.270,hx+.033,.048,.101,.098)],felt,n=14)
            volume(m,[(eye+.126,hx,.028,.178,.140),(eye+.155,hx,.030,.168,.138)],LEATHER)
            star(m,hx+.026,eye+.166,-.121,.047,BRASS)
            band(m,(hx+.108,eye-.054,-.120),(hx+.076,eye-.131,-.150),fabric(98,67,50),.015)
            band(m,(hx-.102,eye-.087,-.122),(hx-.073,eye-.114,-.141),fabric(174,152,104),.012)
            band(m,(hx+.015,eye-.150,-.137),(hx+.043,eye-.145,-.135),fabric(199,176,125),.011)
        else:
            cap = rust if heavy else fabric(120,113,79)
            volume(m,[(eye+.069,hx,.018,w*1.12,.142),(eye+.143,hx,.036,w,.133),
                       (eye+.177,hx,.041,w*.54,.077)],cap)
            m.loft([(-.213,hx-.012,eye+.059,.089,.012),(-.075,hx,eye+.083,w,.015)],cap,box=True)
            m.block(hx,eye+.105,-.113,.073,.038,.016,fabric(181,146,98))
            band(m,(hx-.065,eye-.101,-.131),(hx+.065,eye-.103,-.133),LEATHER,.015)
            if heavy:
                joint(m,(hx,eye-.149,-.082),(.118,.116,.109),fabric(66,49,37))
                band(m,(hx-.069,eye-.114,-.171),(hx+.060,eye-.108,-.173),skin,.015)
                band(m,(hx-.103,eye-.006,-.138),(hx+.102,eye-.010,-.142),fabric(78,57,40),.018)
    return m


def lanky_shooter(frame):
    m = Mesh()
    walk = frame if isinstance(frame,int) else 0
    ready = frame in ("aim","fire")
    flinch = frame=="pain"
    x = .057*walk-.08*flinch
    drop = .075*flinch
    pants, shirt = fabric(77,79,57),fabric(121,109,79)
    skin, stubble = (157,119,87,"skin",.09),fabric(101,92,76)
    strap = fabric(97,65,51)
    for s in (-1,1):
        foot=(s*.117,.122+max(0,s*walk)*.036,s*walk*.19)
        knee=(s*.137+x*.3,.49,foot[2]*.35-.10)
        hip=(s*.119+x,.92-drop,.085)
        trouser(m,foot,knee,hip,(.061,.078,.103),pants)
        volume(m,[(.04+foot[1]-.122,foot[0],foot[2]-.052,.082,.137),
                  (foot[1],foot[0],foot[2]-.024,.080,.115)],LEATHER)
        band(m,(knee[0]-.046,.482,knee[2]-.058),(knee[0]+.048,.51,knee[2]-.059),strap,.016)
    volume(m,[(.87-drop,x,.064,.205,.124),(1.08-drop,x,.011,.182,.142),
              (1.31-drop,x,-.078,.218,.141),(1.49-drop,x-.021,-.156,.179,.120)],shirt)
    for s in (-1,1):
        band(m,(x+s*.108,1.45-drop,-.208),(x+s*.137,.94-drop,-.058),strap,.022)
        band(m,(x+s*.104,1.44-drop,-.041),(x+s*.13,.92-drop,.176),strap,.019)
    y=1.54-drop
    head_x=x-.058
    joint(m,(head_x,y,-.194),(.077,.100,.075),skin)
    joint(m,(head_x,y+.14,-.211),(.107,.164,.104),skin)
    joint(m,(head_x-.004,y+.053,-.258),(.091,.073,.082),stubble)
    band(m,(head_x-.075,y+.17,-.293),(head_x+.073,y+.148,-.305),LEATHER,.018)
    joint(m,(head_x+.010,y+.112,-.310),(.034,.046,.059),skin)
    for s in (-1,1):
        joint(m,(head_x+s*.096,y+.109,-.22),(.027,.039,.024),skin)
        band(m,(head_x+s*.093,y+.178,-.229),(head_x+s*.085,y+.126,-.234),stubble,.022)
    grip=(x+.31,1.60 if frame=="fire" else 1.47 if ready else 1.032,
          -.34 if frame=="fire" else -.46 if ready else -.16)
    for s in (-1,1):
        shoulder=(x+s*.216,1.36-drop,-.13)
        elbow=(x+s*.29,1.14-drop,-.095+.073*s*walk)
        hand=grip if s>0 else (x-.253,.91+.08*walk,-.165+.14*walk)
        if frame=="fidget" and s<0:
            elbow=(x-.39,1.30,-.10)
            hand=(head_x-.092,y+.032,-.28)
        if flinch:
            hand=(x+s*(.16 if s<0 else .31),1.43 if s<0 else 1.14,-.21)
        forearm=np.asarray(elbow)*.70+np.asarray(hand)*.30
        m.link((shoulder,elbow,forearm),(.073,.066,.046),shirt)
        m.link((forearm,hand),(.045,.036),skin)
        joint(m,hand,(.040,.044,.043),skin)
    if not flinch:
        gx,gy,gz=grip
        muzzle=(gx+.035,gy+(.15 if frame=="fire" else .042) if ready else gy-.13,
                gz-.245 if ready else gz-.067)
        m.tube((gx,gy,gz+.019),muzzle,.032,.022,STEEL)
        m.block(gx,gy,gz+.011,.064,.059,.082,SHADOW)
        if frame=="fire":
            joint(m,muzzle,(.040,.041,.030),fabric(247,183,101))
    return m


def saucer(frame):
    m=Mesh()
    phase=frame if isinstance(frame,int) else 0
    firing=frame in ("aim","fire")
    shell=metal(154,153,131)
    trim=metal(66,79,75)
    volume(m,[(.30,0,0,.25,.25),(.42,0,0,.41,.40),(.50,0,0,.83,.81),
              (.56,0,0,.94,.91),(.61,0,0,.92,.89),(.72,0,0,.60,.57)],shell,n=24)
    volume(m,[(.535,0,0,.938,.915),(.574,0,0,.947,.924)],trim,n=24)
    volume(m,[(.578,0,0,.942,.922),(.598,0,0,.935,.915)],metal(167,134,83),n=24)
    volume(m,[(.698,0,.04,.46,.42),(.85,0,.055,.36,.35),(.941,0,.05,.23,.23)],
           metal(85,119,110),n=18)
    for i in range(14):
        a = i*math.tau/14+.015*phase
        joint(m,(.91*math.cos(a),.554,.89*math.sin(a)),(.043,.024,.043),
              fabric(218,172,88) if i%3==phase+1 or firing else BRASS)
    volume(m,[(.212 if firing else .28,0,0,.13,.13),(.364,0,0,.26,.26)],
           fabric(243,159,75) if firing else metal(93,116,88))
    return m


def baked_actor(name, frame):
    down=frame=="down"
    model=saucer(frame) if name=="saucer" else humanoid(name,0 if down else frame)
    yaw=-.29 if name in ("boss","billy","clone") else -.46 if name=="coot" else -.35
    camera=SpriteCamera(yaw,down)
    image=render(model,camera)
    if name=="saucer":
        image=image.crop((87,94,233,157)).resize((132,57),Image.Resampling.LANCZOS)
    elif down:
        bounds=image.getchannel("A").getbbox()
        image=image.crop(bounds).resize((92,31),Image.Resampling.LANCZOS)
    else:
        image=image.crop(actor_bounds(name))
        if name=="boss":
            make_up_sheriff(image,camera,frame)
    if frame=="fire" and name!="coot":
        d=ImageDraw.Draw(image)
        if name=="saucer":
            cx,cy=68,32
        else:
            cx,cy,_ = camera.project(model.flash_origin)
            left,top,_,_ = actor_bounds(name)
            cx,cy = round(cx-left),round(cy-top)
        d.polygon([(cx-8,cy),(cx-2,cy-3),(cx,cy-9),(cx+3,cy-3),(cx+9,cy-2),
                   (cx+3,cy+3),(cx+2,cy+8),(cx-2,cy+3)],fill="#e3a14e")
        d.ellipse((cx-3,cy-3,cx+3,cy+3),fill="#ffe2a7")
    return image


@lru_cache(maxsize=1)
def sheriff_prosthetic():
    path = Path(__file__).resolve().parent/"source_art"/"alien_plate.png"
    plate = Image.open(path).convert("RGBA").crop((64,28,146,74))
    yy,xx=np.indices((plate.height,plate.width),dtype=np.float32)
    edge=np.clip(1.5-((xx-plate.width*.5)/(plate.width*.52))**2-
                 ((yy-plate.height*.51)/(plate.height*.59))**2,0,1)
    rgba=np.array(plate)
    rgba[:,:,:3]=np.clip(rgba[:,:,:3]*[.89,.93,.90]+[9,14,6],0,255)
    rgba[:,:,3]=(rgba[:,:,3]*edge*.83).astype(np.uint8)
    return Image.fromarray(rgba).resize((25,18),Image.Resampling.LANCZOS)


def make_up_sheriff(image,camera,frame):
    step = frame if isinstance(frame,int) else 0
    pain,fire,aim = (frame==name for name in ("pain","fire","aim"))
    shift = (-.127 if pain else -.072 if fire else .042 if aim else 0)+.028*step
    eye = 1.77-(.101 if pain else .034 if fire else .014*abs(step))
    x,y,_=camera.project((shift+(-.085 if pain else .024),eye-.087,-.128))
    left,top,_,_=actor_bounds("boss")
    image.alpha_composite(sheriff_prosthetic(),(round(x-left)-12,round(y-top)-9))


def actor_bounds(name):
    return {"billy":(83,28,237,163),"coot":(102,27,222,163)}.get(name,(100,16,220,163))


def turn_cels(kind, make, bounds, save, *, recover_pose=False):
    """Bake symmetric direction groups from the original actor's model."""
    from actor_finish import finish

    if make is humanoid and kind!="coot":
        recover = baked_actor(kind,"recover")
    elif recover_pose:
        recover = render(make(kind,"recover"),SpriteCamera(-.24)).crop(bounds)
    else:
        recover = render(make(kind,0),SpriteCamera(-.24)).crop(bounds)
        recover = recover.transform(recover.size,Image.Transform.AFFINE,(1,.072,-8,0,1,-4),
                                    Image.Resampling.BICUBIC)
    save(finish(recover,kind,"recover"),f"{kind}_recover")
    for step in (-1,0,1):
        mesh = make(kind,step)
        for suffix,yaw in (("quarter",-.78),("side",-1.57),("away",-2.36),("back",-math.pi)):
            sprite = render(mesh,SpriteCamera(yaw)).crop(bounds)
            sprite = finish(sprite,kind,step)
            save(sprite,f"{kind}_{suffix}_{step}")
