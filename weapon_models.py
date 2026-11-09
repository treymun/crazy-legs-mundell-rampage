"""Original, textured meshes rasterized offline into DOS-sized weapon cels."""
from functools import lru_cache
from pathlib import Path
import math

import numpy as np
from PIL import Image


SOURCE = Path(__file__).resolve().parent / "source_art" / "materials"
SIZE = (320, 174)
METAL = (55, 59, 65, "iron", .63)
STEEL = (84, 90, 96, "iron", .77)
BLACK = (28, 30, 30, "iron", .24)
WOOD = (103, 62, 36, "wood", .29)
DARK_WOOD = (78, 49, 32, "wood", .25)
SKIN = (149,104,76,"skin",.12)
NAIL = (175, 138, 108, "hide", .34)
CLOTH = (97,63,53,"flannel",.06)
BRASS = (141, 109, 53, "iron", .67)


@lru_cache(maxsize=None)
def texture(kind):
    if kind in ("skin","flannel","denim"):
        plate = Image.open(SOURCE.parent/"body_plate.png")
        crop = {"skin":(53,169,91,195),"flannel":(27,69,77,133),"denim":(68,264,119,380)}[kind]
        ar = np.array(plate.crop(crop).convert("L").resize((128,128),Image.Resampling.LANCZOS),dtype=np.float32)
        return (ar-np.median(ar))*.61
    name = {"iron":"corrugated_iron","blued":"corrugated_iron","wood":"weathered_plank_siding",
            "hide":"worn_concrete_floor","rubber":"asphalt_02","enamel":"old_linoleum_flooring_01",
            "paper":"worn_concrete_floor","copper":"red_bricks_04"}.get(kind,"forest_ground_04")
    im = Image.open(SOURCE / (name + ".png")).convert("L")
    ar = np.array(im.resize((128, 128), Image.Resampling.LANCZOS), dtype=np.float32)
    return (ar - np.median(ar)) / 2.3


class Mesh:
    def __init__(self):
        self.faces = []

    def face(self, pts, mat, smooth=None):
        a, b, c = np.asarray(pts[:3], dtype=float)
        n = np.cross(b - a, c - a)
        if np.linalg.norm(n) > 1e-7:
            n /= np.linalg.norm(n)
            for j in range(1, len(pts) - 1):
                normals = None if smooth is None else np.asarray((smooth[0],smooth[j],smooth[j+1]))
                self.faces.append((np.asarray((pts[0], pts[j], pts[j+1])),n,mat,normals))

    def rings(self, rings, mat, ends=True, smooth=True):
        if ends:
            self.face(list(reversed(rings[0])), mat)
            self.face(rings[-1], mat)
        if smooth:
            positions = np.asarray(rings,dtype=float)
            along = positions[1:] - positions[:-1]
            around = np.roll(positions,-1,axis=1) - np.roll(positions,1,axis=1)
            axial = np.concatenate((along[:1],along[:-1]+along[1:],along[-1:]),axis=0)
            normals = np.cross(around,axial)
            normals /= np.maximum(1e-9,np.linalg.norm(normals,axis=2,keepdims=True))
        for k,(lo,hi) in enumerate(zip(rings,rings[1:])):
            for i in range(len(lo)):
                j = (i + 1) % len(lo)
                corners = (normals[k,i],normals[k,j],normals[k+1,j],normals[k+1,i]) if smooth else None
                self.face([lo[i],lo[j],hi[j],hi[i]],mat,corners)

    def tube(self, a, b, r, tip, mat, n=12, ratio=1.0, caps=True):
        a, b = np.asarray(a), np.asarray(b)
        axis = (b - a) / np.linalg.norm(b - a)
        up = np.array([0., 1., 0.]) if abs(axis[1]) < .93 else np.array([0., 0., 1.])
        u = np.cross(up, axis)
        u /= np.linalg.norm(u)
        v = np.cross(axis, u)
        angles = np.arange(n) * math.tau / n
        ring = np.cos(angles[:, None]) * u + np.sin(angles[:, None]) * v * ratio
        self.rings([list(a + r*ring), list(b + tip*ring)], mat, caps)

    def loft(self, sections, mat, box=False, n=12):
        if box:
            xy = np.array([(.70, -1), (1, -.66), (1, .66), (.70, 1),
                           (-.70, 1), (-1, .66), (-1, -.66), (-.70, -1)])
        else:
            a = np.arange(n) * math.tau / n
            xy = np.stack((np.cos(a), np.sin(a)), axis=1)
        self.rings([[(x + u*rx, y + v*ry, z) for u, v in xy]
                    for z, x, y, rx, ry in sections],mat,smooth=not box)

    def block(self, x, y, z, w, h, length, mat):
        self.loft([(z-length/2, x, y, w/2, h/2), (z+length/2, x, y, w/2, h/2)], mat, box=True)

    def link(self, pts, widths, mat):
        if mat[3] in ("skin","denim","flannel") or mat[3]=="hide" and mat[4]<=.08:
            centers=np.asarray(pts,dtype=float)
            span=centers[-1]-centers[0]
            up=np.array((0.,0.,1.) if abs(span[1])>abs(span[2]) else (0.,1.,0.))
            turn=np.linspace(0,math.tau,12,endpoint=False)
            rings=[]
            for index,(center,radius) in enumerate(zip(centers,widths)):
                axis=centers[min(index+1,len(centers)-1)]-centers[max(0,index-1)]
                axis/=max(1e-8,np.linalg.norm(axis))
                u=np.cross(up,axis)
                if np.linalg.norm(u)<1e-5:
                    u=np.cross((1.,0.,0.),axis)
                u/=max(1e-8,np.linalg.norm(u))
                v=np.cross(axis,u)
                rings.append([center+radius*(math.cos(a)*u+.94*math.sin(a)*v) for a in turn])
            self.rings(rings,mat)
            return
        for a, b, r, s in zip(pts, pts[1:], widths, widths[1:]):
            self.tube(a, b, r, s, mat, n=7, ratio=.95)


class Camera:
    natural = True

    def __init__(self, yaw=0., pitch=0., roll=0., x=0., y=0., z=0., side=False):
        cos, sin = math.cos, math.sin
        a = np.array([[cos(yaw), 0, sin(yaw)], [0, 1, 0], [-sin(yaw), 0, cos(yaw)]])
        b = np.array([[1, 0, 0], [0, cos(pitch), -sin(pitch)], [0, sin(pitch), cos(pitch)]])
        c = np.array([[cos(roll), -sin(roll), 0], [sin(roll), cos(roll), 0], [0, 0, 1]])
        self.rotation = c @ b @ a
        self.move = (x, y, z)
        self.side = side

    def project(self, model):
        xyz = (np.asarray(model) - [0, 0, .93]) @ self.rotation.T + [0, 0, .93] + self.move
        x, y, z = xyz.T
        if self.side:
            depth = 6.0 - x + .09*z
            return np.stack((232 - z*56 - x*21, 83 - y*60 - x*21 + z*7, depth), axis=-1)
        depth = .66 + z
        scale = 98 / np.maximum(.14, depth)
        return np.stack((160 + (x + .89 - .26*z) * scale,
                         117 + (.34 - y - .57*z) * scale, depth), axis=-1)


def render(mesh, camera):
    zoom = 2
    w, h = (size*zoom for size in SIZE)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    zbuffer = np.zeros((h, w), dtype=np.float32)
    light = np.asarray([-.41, .83, -.37])
    view = np.array([.75,.13,-.66]) if camera.side else np.array([-.37,.26,-.89])
    half = light+view
    half /= np.linalg.norm(half)
    natural = getattr(camera,"natural",False)
    for pts, normal, mat, normals in mesh.faces:
        projected = camera.project(pts)
        if np.min(projected[:, 2]) <= .12:
            continue
        (x0,y0), (x1,y1), (x2,y2) = projected[:, :2]*zoom
        denom = (y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
        if abs(denom) < .03:
            continue
        lx = max(0, int(min(x0,x1,x2))); rx = min(w, math.ceil(max(x0,x1,x2)))
        ly = max(0, int(min(y0,y1,y2))); ry = min(h, math.ceil(max(y0,y1,y2)))
        if rx <= lx or ry <= ly:
            continue
        yy, xx = np.ogrid[ly:ry, lx:rx]
        a = ((y1-y2)*(xx+.5-x2)+(x2-x1)*(yy+.5-y2))/denom
        b = ((y2-y0)*(xx+.5-x2)+(x0-x2)*(yy+.5-y2))/denom
        c = 1-a-b
        recip = 1/projected[:, 2]
        depth = a*recip[0] + b*recip[1] + c*recip[2]
        buf = zbuffer[ly:ry, lx:rx]
        mask = (a >= -1e-4) & (b >= -1e-4) & (c >= -1e-4) & (depth > buf)
        if not mask.any():
            continue
        depth = depth[mask]
        weights = np.stack((a[mask], b[mask], c[mask]), axis=1)*recip/depth[:,None]
        u, v, q = (weights @ pts).T
        r,g,blue,kind,gloss = mat
        n = camera.rotation @ normal
        if natural and normals is not None:
            n = (weights @ normals) @ camera.rotation.T
            n /= np.maximum(1e-9,np.linalg.norm(n,axis=-1,keepdims=True))
        diffuse = np.maximum(0.,n @ light)
        spec = np.maximum(0.,n @ half) ** (8 if kind=="wood" else 19)
        tx = (q*60 + u*143 - v*50).astype(int) & 127
        ty = (v*164 + u*173 + q*(16 if kind == "wood" else 51)).astype(int) & 127
        grain = texture(kind)[ty, tx]
        if kind == "wood":
            waves = np.sin((v*.80+u)*126 + np.sin(q*5)*1.8 + np.cos(v*12+q*4)*1.3)
            grain = grain*1.48 + waves*7 + (np.sin(v*54 + np.cos(q*4)*1.7)*6)
        if kind == "flannel":
            weave = (np.sin((u+q*.32)*75)>.49).astype(float)+(np.cos(v*73)>.58)
            grain = grain*.58-weave*16
        if kind in ("blued","copper"):
            grain = grain*1.40+7*np.sin((v+u*.36)*139+np.sin(q*23))
        elif kind=="enamel":
            grain = grain*.66-11*np.maximum(0.,np.sin(q*53-v*69)**8)
        elif kind=="paper":
            grain = grain*.81+5*np.sin(q*99+u*23)
        ambient = .47 + .66*diffuse + .14*np.abs(n[...,1])
        if natural:
            ambient *= .90 + .11*np.clip(v/.95,0.,1.)
            grain *= 1.25
        noise = np.sin((u*752+v*985+q*1325))*1.7
        scratch = np.maximum(grain-13, 0)*gloss*.28
        illum = grain*.53 + noise + spec*(80*gloss) + scratch
        pixel = np.clip(np.array([r,g,blue])*np.asarray(ambient)[...,None] + illum[:,None]*[.91,.96,1],0,255)
        target = out[ly:ry, lx:rx]
        target[mask,:3] = pixel
        target[mask,3] = 255
        buf[mask] = depth
    return Image.fromarray(out).resize(SIZE, Image.Resampling.LANCZOS)


def glove(mesh, palm, wrist, fingers):
    mesh.tube(wrist, palm, .105, .106, SKIN, n=10, ratio=.75)
    mesh.tube((wrist[0]+.018, wrist[1]-.17, wrist[2]-.20), wrist, .125, .115, CLOTH, n=10)
    for j, path in enumerate(fingers):
        thick = .032 if j == 0 else .026
        mesh.link(path, (thick, thick, thick*.73), SKIN)
        tip = np.asarray(path[-1])
        mesh.tube(tip+[-.013,.010,-.011], tip+[.009,.009,.010], .015, .011, NAIL, n=7)


RIFLE_CAM = {
    "idle": {"yaw": -.059,"y": .185,"z": .030},
    "kick": {"pitch": -.074,"z": -.095,"x": .019,"yaw": -.065,"y": .207,"roll": -.026},
    "recover": {"pitch": -.024,"z": -.016,"x": .007,"yaw": -.062,"y": .193,"roll": -.008},
    "open": {"roll": -.18,"yaw": -.13,"pitch": .037,"y": .23},
    "eject": {"roll": -.37,"yaw": -.23,"pitch": .045,"y": .31},
    "load": {"roll": -.28,"yaw": -.19,"pitch": .042,"y": .29},
    "close": {"roll": -.10,"yaw": -.072,"pitch": -.020,"y": .21},
}
RIFLE_WALNUT = (89,58,39,"wood",.19)
RIFLE_OIL = (62,42,30,"wood",.13)
RIFLE_RECEIVER = (46,48,52,"blued",.42)
RIFLE_EDGE = (79,83,90,"blued",.64)


def rifle_mesh(pose):
    m = Mesh()
    m.tube((0,.035,1.19),(0,.035,2.58),.043,.035,RIFLE_RECEIVER, n=16)
    m.tube((0,.035,2.46),(0,.035,2.60),.055,.052,STEEL, n=16)
    m.tube((0,.035,2.598),(0,.035,2.606),.025,.026,BLACK, n=16)
    m.tube((0,.131,1.37),(0,.131,2.02),.033,.038,METAL)
    m.block(0,.082,2.01,.15,.18,.105,METAL)
    m.block(0,.096,2.39,.116,.16,.086,METAL)
    for x in (-.041,.041):
        m.block(x,.196,2.39,.027,.082,.066,STEEL)
    m.block(0,.195,2.391,.017,.083,.018,STEEL)
    m.loft([(1.25,0,-.004,.121,.137),(1.34,0,-.015,.144,.144),
            (1.69,0,-.017,.117,.118),(1.96,0,-.018,.093,.097)],RIFLE_WALNUT,box=True)
    m.loft([(1.33,0,.135,.090,.058),(1.45,0,.14,.111,.057),
            (1.85,0,.138,.088,.052)],RIFLE_OIL,box=True)
    for z in (1.53,1.68,1.81):
        m.block(0,.031,z,.231-(z-1.53)*.14,.025,.019,RIFLE_OIL)
    m.block(0,-.008,1.93,.187,.186,.031,RIFLE_RECEIVER)
    m.loft([(.50,0,-.005,.112,.103),(.61,0,0,.139,.139),
            (1.19,0,0,.139,.123),(1.31,0,.006,.120,.114)],RIFLE_RECEIVER,box=True)
    m.loft([(.56,0,.112,.093,.045),(.68,0,.140,.125,.052),
            (1.18,0,.135,.117,.054),(1.32,0,.127,.089,.038)],RIFLE_EDGE)
    m.block(0,.205,1.18,.12,.046,.124,BLACK)
    for x in (-.050,.050):
        m.block(x,.235,1.192,.019,.046,.055,STEEL)
    m.block(-.140,.040,1.03,.023,.088,.31,BLACK)
    m.block(-.151,.091,1.02,.011,.012,.28,RIFLE_EDGE)
    m.block(-.151,-.003,1.01,.013,.012,.24,RIFLE_EDGE)
    m.block(-.148,.014,.848,.012,.120,.045,RIFLE_RECEIVER)
    for z in (.83,.884,.938,1.002,1.074,1.126):
        m.tube((-.135,-.048,z),(-.146,-.046,z+.003),.009,.007,BRASS,n=6)
    m.block(-.152,-.025,1.024,.012,.013,.241,METAL)
    for z in (.66,.90,1.237):
        m.tube((-.135,.012,z),(-.150,.012,z),.019,.016,STEEL,n=8)
    offset = -.16 if pose == "kick" else -.075 if pose in ("recover","close") else 0.
    m.tube((-.142,.072,1.12+offset),(-.211,.072,1.12+offset),.032,.028,STEEL)
    m.loft([(.05,0,-.119,.105,.132),(.37,0,-.068,.098,.103),
            (.58,0,-.021,.080,.075)],RIFLE_WALNUT,n=12)
    m.loft([(.028,0,-.118,.107,.140),(.055,0,-.118,.113,.143)],BLACK,n=12)
    m.tube((0,-.12,.67),(0,-.38,.57),.081,.072,DARK_WOOD)
    m.link([(-.03,-.10,.96),(-.04,-.25,.95),(-.04,-.262,.78),(-.03,-.14,.73)],
           (.024,.025,.024,.021), METAL)
    m.tube((0,-.126,.847),(0,-.202,.812),.019,.013,STEEL)
    # Curved stamped magazine, separate from the rifle throughout the reload.
    d = -.28 if pose == "eject" else -.13 if pose == "load" else 0.
    dz = -.10 if pose == "eject" else -.044 if pose == "load" else 0.
    mag = [(0,-.14+d,1.08+dz),(0,-.29+d,1.10+dz),
           (0,-.44+d,1.18+dz),(0,-.58+d,1.30+dz)]
    profiles = []
    for x,y,z in reversed(mag):
        profiles.append([(-.076,y,z-.13),(-.076,y,z+.13),(.076,y,z+.13),(.076,y,z-.13)])
    m.rings(profiles, METAL)
    for x in (-.078,.078):
        for shift in (-.075,.0,.075):
            m.link([(x,y,z+shift) for _,y,z in mag], (.012,.013,.013,.012),STEEL)
    m.block(0,mag[-1][1],mag[-1][2],.17,.04,.29,BLACK)
    if pose == "load":
        m.block(0,-.136+d,1.07+dz,.083,.019,.10,BRASS)
    if pose == "pickup":
        return m
    # Wrist and finger joints follow the furniture rather than floating over it.
    glove(m, (-.105,-.26,.65), (-.057,-.44,.35), [
        [(-.13,-.22,.67),(-.13,-.18,.74),(-.088,-.188,.81)],
        [(-.13,-.24,.70),(-.11,-.23,.78),(-.046,-.226,.80)],
        [(-.13,-.285,.69),(-.10,-.268,.758),(-.050,-.268,.772)],
        [(-.12,-.32,.68),(-.10,-.301,.733),(-.051,-.299,.748)]])
    if pose in ("open","eject","load"):
        y,z = mag[2][1],mag[2][2]
        glove(m, (-.15,y,z),(-.39,y-.21,z-.17),[
            [(-.14,y+.035,z-.045),(-.07,y+.067,z-.08),(-.035,y+.060,z-.08)],
            [(-.16,y+.004,z+.049),(-.072,y+.010,z+.10),(-.017,y+.004,z+.11)],
            [(-.15,y-.051,z+.048),(-.07,y-.049,z+.10),(-.018,y-.054,z+.106)],
        ])
    else:
        glove(m, (-.086,-.19,1.60),(-.18,-.44,.94),[
            [(-.152,-.11,1.63),(-.163,.013,1.65),(-.119,.063,1.70)],
            [(-.106,-.18,1.73),(-.042,-.152,1.76),(.018,-.129,1.78)],
            [(-.110,-.19,1.66),(-.046,-.148,1.67),(.018,-.128,1.67)],
            [(-.12,-.19,1.59),(-.052,-.156,1.58),(.014,-.131,1.58)],
        ])
    return m


def rifle_frames():
    frames, anchors = {}, {}
    for name, options in RIFLE_CAM.items():
        camera = Camera(**options)
        frames[name] = render(rifle_mesh(name), camera)
        anchors[name] = [round(float(v), 1) for v in camera.project((0,.035,2.61))[:2]]
        if name == "kick":
            anchors["case"] = [round(float(v), 1) for v in camera.project((-.159,.040,1.03))[:2]]
    pickup = render(rifle_mesh("pickup"), Camera(side=True))
    # The arm-free side render comes from the same geometry as the viewmodel.
    return frames, anchors, pickup


SAW_IRON = (64,67,69,"blued",.57)
SAW_GUARD = (102,81,57,"enamel",.43)
BLADE = (155,148,127,"blued",.71)
MEAT = (112,65,46,"skin",.14)
TENDON = (148,104,65,"skin",.19)
BONE = (165, 130, 82, "hide", .29)
ALIEN_ARMOR = (53, 51, 41, "iron", .78)


def disc(mesh, at, phase=0., cant=-.68):
    x, y, z = at
    # The disk stands vertically in the metal guide, with individual set teeth.
    for i in range(26):
        a = math.tau * i / 26 + phase
        step = math.tau / 26
        def point(side, r, angle):
            q = r*math.cos(angle)
            return (x+side*math.cos(cant)+q*math.sin(cant), y+r*math.sin(angle),
                    z+q*math.cos(cant)-side*math.sin(cant))
        profile = ((.326,a),(.354,a+step*.32),(.379,a+step*.60),(.320,a+step))
        lo = [point(-.021,r,angle) for r,angle in profile]
        hi = [point(.021,r,angle) for r,angle in profile]
        mesh.face([(x-.021,y,z),*lo], BLADE)
        mesh.face([(x+.021,y,z),*reversed(hi)], BLADE)
        for k in range(3):
            mesh.face([lo[k],lo[k+1],hi[k+1],hi[k]], STEEL)
    for side in (-1,1):
        mesh.tube((x,y,z),(x+.030*side,y,z),.132,.132,SAW_IRON,n=18)
        mesh.tube((x+.032*side,y,z),(x+.048*side,y,z),.051,.044,STEEL,n=8)


def saw_mesh(pose):
    m = Mesh()
    angle = {"grind": .072, "grind_hot": .18, "load": .038}.get(pose,0.)
    if pose in ("idle","pickup","grind","grind_hot","close"):
        disc(m,(-.23,.16,1.69),angle)
    elif pose == "load":
        disc(m,(-.31,.207,1.55),angle)
    m.loft([(.54,.04,-.016,.118,.108),(.64,.05,-.010,.162,.154),
            (1.12,.04,-.021,.164,.143),(1.37,.03,-.038,.124,.100),
            (1.58,-.019,-.041,.067,.071)],SAW_GUARD,n=14)
    m.link([(.10,-.062,1.15),(.139,-.044,1.40),(.041,-.025,1.74),
            (-.025,-.032,1.96)],(.044,.045,.034,.025),SAW_IRON)
    m.link([(-.22,.004,1.44),(-.28,.084,1.62),(-.25,.061,1.85),(-.20,.04,1.97)],
           (.042,.040,.035,.028),SAW_IRON)
    m.link([(-.081,.084,1.04),(-.066,.226,1.20),(.117,.226,1.20),(.155,.083,1.10)],
           (.035,.044,.044,.033), BLACK)
    for z in (.69,.79,.90,.99,1.10):
        m.block(-.136,-.038,z,.054,.037,.025,BLACK)
        m.block(-.145,.014,z,.030,.015,.020,STEEL)
    for z in (.71,1.16,1.42):
        m.tube((-.146,.049,z),(-.17,.049,z),.032,.026,STEEL,n=8)
    m.tube((.068,-.08,.58),(.07,-.35,.51),.078,.072,BLACK)
    m.loft([(.28,.07,-.10,.079,.088),(.57,.071,-.071,.08,.10)],SAW_IRON,box=True)
    if pose == "pickup":
        return m
    glove(m,(-.04,-.26,.59),(.04,-.41,.30),[
        [(-.091,-.24,.63),(-.085,-.204,.69),(-.022,-.20,.689)],
        [(-.079,-.27,.62),(-.076,-.241,.67),(-.026,-.235,.67)],
        [(-.069,-.314,.63),(-.065,-.28,.659),(-.022,-.277,.663)],
    ])
    if pose in ("load", "eject"):
        x,y,z = -.25,.135,1.36
    else:
        x,y,z = -.083,.172,1.16
    glove(m,(x,y,z),(x+.09,y-.44,z-.35),[
        [(x-.05,y+.014,z+.045),(x-.009,y+.062,z+.086),(x+.033,y+.041,z+.094)],
        [(x-.052,y+.033,z-.009),(x-.008,y+.068,z+.02),(x+.040,y+.029,z+.023)],
        [(x-.065,y+.03,z-.059),(x-.010,y+.067,z-.036),(x+.035,y+.040,z-.027)],
    ])
    return m


def arm_mesh(pose):
    m = Mesh()
    hot = pose in ("kick","recover","eject","load","close")
    glow = (166, 193, 97, "hide", .21) if hot else (98, 125, 58, "hide", .25)
    m.loft([(.32,.046,-.092,.173,.144),(.51,.023,-.072,.159,.153),
            (.70,0,-.057,.123,.129),(.98,0,-.02,.116,.110),
            (1.26,.00,-.035,.109,.112),(1.48,0,-.048,.089,.099)],MEAT)
    for side in (-1,1):
        m.link([(side*.08,-.003,.41),(side*.14,-.034,.58),(side*.116,-.073,.82),
                (side*.084,-.078,1.04),(side*.09,-.06,1.33)],
               (.030,.035,.029,.021,.018),TENDON)
        m.link([(side*.135,-.088,.37),(side*.15,-.12,.49),(side*.12,-.138,.77),
                (side*.11,-.12,1.02)],(.026,.033,.022,.012),BONE)
    # Reinforced wrist cuffs and a dark receiver bolted to the forearm.
    for z, r in ((.60,.156),(.865,.141),(1.22,.134),(1.46,.123)):
        m.tube((0,-.027,z-.024),(0,-.027,z+.024),r,r,BRASS,n=16)
        m.tube((0,-.027,z-.010),(0,-.027,z+.010),r+.009,r+.009,ALIEN_ARMOR,n=16)
    m.loft([(.84,.041,.091,.134,.093),(.94,.032,.131,.172,.131),
            (1.35,-.018,.110,.174,.130),(1.64,-.016,.093,.119,.103)],ALIEN_ARMOR,n=16)
    m.loft([(1.57,-.025,.073,.112,.101),(1.74,-.028,.069,.119,.104),
            (1.99,0,.071,.081,.079),(2.06,0,.071,.072,.069)],METAL,n=16)
    m.tube((0,.071,2.015),(0,.071,2.091),.107,.092,STEEL,n=18)
    m.tube((0,.071,2.09),(0,.071,2.101),.069,.066,BLACK,n=18)
    m.tube((0,.071,2.103),(0,.071,2.11),.046 if hot else .037,.044 if hot else .034,glow,n=14)
    for side in (-1,1):
        m.link([(side*.118,.122,1.68),(side*.158,.149,1.90),(side*.138,.123,2.05),
                (side*.107,.084,2.19)],(.041,.033,.022,.007),BONE)
        m.link([(side*.099,-.032,1.55),(side*.121,-.064,1.72),
                (side*.075,-.037,1.97)],(.029,.028,.018),TENDON)
        m.link([(side*.147,.074,.54),(side*.180,.055,.77),(side*.191,.047,1.13),
                (side*.146,.052,1.68),(side*.095,.060,1.98)],
               (.040,.042,.032,.035,.020),BRASS)
        m.link([(side*.137,.160,.94),(side*.182,.156,1.24),
                (side*.165,.151,1.56),(side*.121,.123,1.77)],(.026,.039,.040,.025),STEEL)
    for z in (.99,1.10,1.21,1.32,1.43,1.54):
        m.block(-.161,.174,z,.066,.044,.039,BLACK)
        m.block(-.176,.180,z,.038,.022,.019,glow)
    # Breech is open during the charge cycle, exposing the cylinder.
    cell_y = .319 if pose in ("eject","load") else .237
    cell_z = 1.19 if pose == "eject" else 1.30
    m.tube((-.056,cell_y,cell_z-.15),(-.056,cell_y,cell_z+.13),.055,.049,glow,n=14)
    for offset in (-.14,.095):
        m.tube((-.056,cell_y,cell_z+offset),(-.056,cell_y,cell_z+offset+.043),.062,.061,BRASS,n=14)
    if pose == "pickup":
        return m
    glove(m,(-.131,-.155,.68),(-.027,-.43,.43),[
        [(-.194,-.097,.69),(-.155,.044,.64),(-.082,.101,.654)],
        [(-.146,-.135,.74),(-.077,-.161,.81),(.014,-.146,.82)],
        [(-.148,-.186,.71),(-.070,-.188,.75),(.014,-.174,.77)],
        [(-.14,-.219,.68),(-.071,-.211,.715),(.014,-.201,.72)],
    ])
    return m


SAW_CAM = {
    "idle": {"x":-.155,"y":.13,"yaw":-.21,"roll":-.16},
    "kick": {"x":-.139,"y":.17,"yaw":-.20,"roll":-.20,"z":-.13},
    "grind": {"x":-.22,"y":.18,"yaw":-.21,"roll":-.12,"z":.07},
    "grind_hot": {"x":-.217,"y":.176,"yaw":-.23,"roll":-.13,"z":.072},
    "open": {"x":-.17,"y":.19,"yaw":-.14,"roll":-.20},
    "eject": {"x":-.20,"y":.17,"yaw":-.18,"roll":-.27},
    "load": {"x":-.20,"y":.19,"yaw":-.14,"roll":-.26},
    "close": {"x":-.19,"y":.13,"yaw":-.105,"roll":-.16},
}
ARM_CAM = {
    "idle": {"x":.14,"y":.089,"yaw":-.13,"roll":.08},
    "kick": {"x":.167,"y":.15,"yaw":-.145,"pitch":-.071,"z":-.08,"roll":.113},
    "recover": {"x":.154,"y":.12,"yaw":-.135,"pitch":-.019,"z":-.03,"roll":.095},
    "open": {"x":.048,"y":.14,"roll":.19,"yaw":.09},
    "eject": {"x":.043,"y":.16,"roll":.28,"yaw":.13},
    "load": {"x":.03,"y":.17,"roll":.21,"yaw":.10},
    "close": {"x":.04,"y":.12,"roll":.09,"yaw":.04},
}
CROSSBOW_CAM = {
    "idle":dict(x=-.02,y=.235,yaw=-.11,roll=-.055),
    "kick":dict(x=.025,y=.19,yaw=-.10,pitch=-.04,roll=-.09,z=-.04),
    "open":dict(x=.055,y=.22,yaw=-.13,roll=-.175),
    "eject":dict(x=.055,y=.30,yaw=-.15,roll=-.23),
    "load":dict(x=.036,y=.28,yaw=-.17,roll=-.175),
    "close":dict(x=.021,y=.24,yaw=-.13,roll=-.11),
}


def modeled_weapon(name):
    if name == "rifle":
        return rifle_frames()
    geometry, cameras, muzzle = {
        "ripsaw": (saw_mesh, SAW_CAM, (-.35,.192,1.96)),
        "armgun": (arm_mesh, ARM_CAM, (0,.071,2.11)),
        "crossbow": (crossbow_mesh, CROSSBOW_CAM, (0,.10,2.13)),
    }[name]
    frames, anchors = {}, {}
    for pose, options in cameras.items():
        camera = Camera(**options)
        frames[pose] = render(geometry(pose), camera)
        anchors[pose] = [round(float(v),1) for v in camera.project(muzzle)[:2]]
    return frames, anchors, render(geometry("pickup"), Camera(side=True))


def crossbow_mesh(pose):
    m = Mesh()
    m.loft([(.25,0,-.06,.11,.115),(.69,0,-.045,.105,.135),
            (1.44,0,-.04,.092,.068),(1.84,0,-.026,.064,.054)],WOOD,n=14)
    m.block(0,.028,1.19,.132,.067,1.11,METAL)
    for s in (-1,1):
        m.block(s*.035,.072,1.30,.022,.018,.92,STEEL)
    m.tube((.019,-.09,.72),(.039,-.31,.65),.070,.053,DARK_WOOD,n=11)
    seat = {"kick":1.41,"open":1.40,"eject":1.07}.get(pose,.90)
    for side in (-1,1):
        pull=(1.41-seat)*.29
        p = [(0,.038,1.61),(side*.26,.041,1.62),(side*.51,.063,1.54-pull*.23),
             (side*.79,.114,1.41-pull*.58),(side*.98,.139,1.32-pull)]
        m.link(p,(.061,.058,.047,.037,.025),RIFLE_EDGE)
        m.link(p[1:],(.019,.019,.018,.016),STEEL)
        m.tube(p[-1],(0,.073,seat),.009,.008,BRASS,n=7)
        m.tube((side*.30,.042,1.60),(side*.30,.056,1.60),.022,.020,STEEL,n=9)
    if pose in ("idle","pickup","close","load"):
        lead = -.21 if pose=="load" else 0.
        m.tube((0,.084,.97+lead),(0,.084,2.10+lead),.021,.018,STEEL,n=10)
        m.tube((0,.105,1.54+lead),(0,.105,2.08+lead),.057,.055,(149,62,37,"paper",.14),n=14)
        for z in (1.59,1.93):
            m.tube((0,.105,z+lead),(0,.105,z+.043+lead),.061,.059,
                   (168,137,91,"paper",.07),n=13)
        m.link([(0,.104,2.07+lead),(-.018,.126,2.13+lead),(-.047,.128,2.14+lead)],
               (.012,.010,.006),BRASS)
    if pose=="pickup":
        return m
    grip=(.041,-.179,.69)
    glove(m,grip,(.095,-.367,.41),[
        [(.004,-.133,.71),(-.038,-.113,.77),(-.032,-.12,.82)],
        [(.011,-.172,.74),(-.035,-.161,.77),(-.047,-.16,.78)],
        [(.008,-.201,.73),(-.025,-.193,.756),(-.046,-.182,.752)],
    ])
    y,z = (.125,1.24) if pose=="load" else (.066,1.05) if pose=="eject" else (-.098,1.25)
    glove(m,(-.141,y,z),(-.253,y-.28,z-.25),[
        [(-.139,y+.055,z+.043),(-.098,y+.106,z+.074),(-.029,y+.098,z+.093)],
        [(-.14,y-.025,z+.078),(-.077,y-.015,z+.102),(.021,y+.025,z+.099)],
        [(-.13,y-.029,z+.004),(-.071,y-.034,z+.024),(.019,y+.003,z+.027)],
    ])
    return m
