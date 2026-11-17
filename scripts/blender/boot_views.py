"""Model and render Mundell's own boot in first person, for the kick and the
stomp (godot/src/features/brawl_looks.gd draws them over the view).

    blender -b -P scripts/blender/boot_views.py -- <out dir> [names|all]

His leg as the player pictures and his 3D model wear it (actors_mundell.py:
denim bib overalls (60, 70, 94) with the tan patch on the right thigh, brown
work boots (80, 54, 36)), seen from his own eye: the camera is the eye at the
origin looking along +y, z up, map units (a door is 1.85 tall). Each pose
renders the 320x200 view four times over (1280x800) with nothing else in it;
godot/tools/art/build_boot_views.gd shrinks each to the game's size with the
gun cels' grade and notes where it sits. Lit by the same three suns as the
gun views (weapon_views.py stage()). Everything is modelled here from plain
shapes; nothing is traced from another game.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(ARGS[0])
WANT = ARGS[1].split(",") if len(ARGS) > 1 and ARGS[1] != "all" else None
CANVAS = (1280, 800)
MATS = {}
PARTS = []


def lin(c):
    c /= 255.0
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def mat(key, rgb, rough=.7, metal=0., grain=None, scale=30., bump=.3, weave=False):
    """A worn surface: `rgb` mottled darker by noise; `grain` (r, g, b) the
    colour of its scuffs; `weave` crosses it finely like denim."""
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(key)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    base = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    dark = (lin(rgb[0]) * .55, lin(rgb[1]) * .52, lin(rgb[2]) * .5, 1)
    ramp.color_ramp.elements[0].position = .3
    ramp.color_ramp.elements[1].position = .7
    ramp.color_ramp.elements[0].color = dark
    ramp.color_ramp.elements[1].color = base
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    colour = ramp.outputs["Color"]
    if grain is not None:
        scuff = nt.nodes.new("ShaderNodeTexNoise")
        scuff.inputs["Scale"].default_value = scale * 2.6
        nt.links.new(coord.outputs["Object"], scuff.inputs["Vector"])
        cut = nt.nodes.new("ShaderNodeValToRGB")
        cut.color_ramp.elements[0].position = .62
        cut.color_ramp.elements[1].position = .7
        cut.color_ramp.elements[0].color = (0, 0, 0, 1)
        cut.color_ramp.elements[1].color = (1, 1, 1, 1)
        nt.links.new(scuff.outputs["Fac"], cut.inputs["Fac"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        nt.links.new(cut.outputs["Color"], mix.inputs["Factor"])
        nt.links.new(colour, mix.inputs["A"])
        mix.inputs["B"].default_value = (lin(grain[0]), lin(grain[1]), lin(grain[2]), 1)
        colour = mix.outputs["Result"]
    if weave:
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.inputs["Scale"].default_value = 260.0
        wave.inputs["Distortion"].default_value = .6
        nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = .22
        nt.links.new(colour, mix.inputs["A"])
        nt.links.new(wave.outputs["Color"], mix.inputs["B"])
        colour = mix.outputs["Result"]
    nt.links.new(colour, bsdf.inputs["Base Color"])
    bnode = nt.nodes.new("ShaderNodeBump")
    bnode.inputs["Strength"].default_value = bump
    nt.links.new(noise.outputs["Fac"], bnode.inputs["Height"])
    nt.links.new(bnode.outputs["Normal"], bsdf.inputs["Normal"])
    MATS[key] = m
    return m


DENIM = lambda: mat("denim", (52, 62, 86), .85, weave=True, grain=(64, 74, 98), scale=18.)
PATCH = lambda: mat("patch", (176, 160, 124), .9, scale=24.)
STITCH = lambda: mat("stitch", (150, 112, 62), .8, scale=60.)
LEATHER = lambda: mat("leather", (124, 68, 30), .7, grain=(146, 88, 44), scale=22., bump=.5)
DARK_LEATHER = lambda: mat("dark_leather", (70, 38, 18), .8, grain=(110, 70, 40), scale=26.)
SOLE = lambda: mat("sole", (104, 90, 70), .9, scale=40., bump=.6)
LUG = lambda: mat("lug", (20, 17, 14), .95, scale=60., bump=.4)
HEEL = lambda: mat("heel", (70, 44, 26), .85, grain=(96, 64, 40), scale=30.)
HEEL_EDGE = lambda: mat("heel_edge", (34, 22, 14), .9, scale=40.)
LACE = lambda: mat("lace", (150, 120, 76), .9, scale=50.)
EYELET = lambda: mat("eyelet", (150, 120, 60), .35, metal=1.)
MUD = lambda: mat("mud", (66, 50, 34), 1., grain=(60, 46, 30), scale=12., bump=1.)


def place(bm, matrix, material, smooth=True):
    me = bpy.data.meshes.new("part")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("part", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    ob.matrix_world = matrix
    if smooth:
        for poly in ob.data.polygons:
            poly.use_smooth = True
    PARTS.append(ob)
    return ob


def frame_along(a, b):
    """A matrix at `a` whose +z runs to `b`."""
    a, b = Vector(a), Vector(b)
    z = (b - a).normalized()
    up = Vector((0, 0, 1)) if abs(z.z) < .9 else Vector((1, 0, 0))
    x = up.cross(z).normalized()
    y = z.cross(x)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = a
    return m


def rod(a, b, ra, rb, material, seg=32, squash=1.0):
    """A tapered tube from a to b (radius ra to rb), flattened by `squash`
    across its local y."""
    length = (Vector(b) - Vector(a)).length
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=ra, radius2=rb, depth=length)
    for v in bm.verts:
        v.co.z += length / 2
        v.co.y *= squash
    return place(bm, frame_along(a, b), material)


def ball(c, r, material, scale=(1, 1, 1), m=None):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    matrix = (m if m is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(c))
    return place(bm, matrix, material)


def box(c, size, material, m=None, bevel=.006):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    matrix = (m if m is not None else Matrix.Identity(4)) @ Matrix.Translation(Vector(c))
    return place(bm, matrix, material, smooth=False)


def hull(points, material, m, smooth=True):
    """The convex hull of `points` (the boot's frame) as one part."""
    bm = bmesh.new()
    for q in points:
        bm.verts.new(Vector(q))
    bmesh.ops.convex_hull(bm, input=list(bm.verts))
    return place(bm, m, material, smooth)


def outline(scale=1.0, z=0.0, inset=0.0):
    """The sole's outline (x across, y heel to toe) as points at height z:
    a round heel, a waist under the arch, the ball widest, a round toe."""
    half = [(-.02, .0), (-.012, .036), (.02, .042), (.07, .038), (.12, .04), (.17, .05),
            (.21, .052), (.25, .046), (.28, .034), (.3, .016), (.306, .0)]
    pts = []
    for y, w in half:
        pts.append(((w - inset) * scale, y * scale, z))
    for y, w in reversed(half):
        pts.append((-(w - inset) * scale * .92, y * scale, z))
    return pts


def boot(m):
    """A worn brown work boot in the frame `m`: the heel's bottom at the
    origin, the toe along +y, the top of the foot +z. About .31 long, its
    shaft .24 high (a size up again in BOOT)."""
    # The sole, worn brown-grey rubber: the forefoot slab, a thin waist under
    # the arch, the heel a block of its own (stacked, darker) with a step at
    # its breast, so the arch shows as a recess between them.
    hull([q for q in outline(1.0, -.01) + outline(1.0, .026) if q[1] > .13], SOLE(), m, False)
    hull([q for q in outline(.96, .012) + outline(.96, .026) if .07 < q[1] < .15], SOLE(), m, False)
    hull([q for q in outline(1.0, -.034) + outline(1.0, .026) if q[1] < .085], HEEL(), m, False)
    for k in range(3):
        hull([(x, y, z + .006 + k * .009) for x, y, z in outline(1.012, -.0) if y < .085]
             + [(x, y, z + .009 + k * .009) for x, y, z in outline(1.012, -.0) if y < .085], HEEL_EDGE(), m, False)
    # The lugs: chevrons down the forefoot, a grid on the heel, standing
    # proud and darker so the tread reads.
    for k in range(6):
        y = .15 + k * .026
        for side in (1, -1):
            box((0, 0, 0), (.036, .011, .014), LUG(),
                m @ Matrix.Translation((side * .022, y, -.016)) @ Matrix.Rotation(math.radians(28 * side), 4, "Z"),
                bevel=.002)
    for row in range(3):
        for col in (-1, 0, 1):
            box((col * .026, .0 + row * .026, -.04), (.02, .02, .014), LUG(), m, bevel=.002)
    hull(outline(1.045, .024) + outline(1.045, .036), DARK_LEATHER(), m, smooth=False)
    for k, (x, y, z) in enumerate(outline(1.05, .036)):
        if k % 2 == 0:
            box((x, y, z), (.006, .006, .004), STITCH(), m, bevel=0)
    # The upper: the hull of the foot's edge, a low round toe box, the
    # vamp sloping up to the shaft round the ankle.
    upper = outline(.9, .036, .006)
    for k in range(9):
        a = math.pi * k / 8
        upper.append((math.cos(a) * .04, .25 + math.sin(a) * .042, .09))
        upper.append((math.cos(a) * .032, .23 + math.sin(a) * .05, .112))
        upper.append((math.cos(a) * .018, .21 + math.sin(a) * .046, .122))
    for k in range(16):
        a = math.tau * k / 16
        for z in (.12, .24):
            upper.append((math.cos(a) * .046, .025 + math.sin(a) * .06, z))
    hull(upper, LEATHER(), m)
    # The toe cap: its own hull a hair proud, darker, so its seam shows.
    cap = [(x * 1.02, y, z + .002) for x, y, z in upper if y > .225]
    cap += [(x * 1.02, .225, z + .002) for x, y, z in outline(.99, .04) if y > .2]
    hull(cap, DARK_LEATHER(), m)
    # A scuff worn pale across the cap, a heel counter stitched on.
    ball((.0, .28, .08), .028, mat("scuff", (150, 104, 66), .9, scale=30.), (1.3, .7, .45), m)
    hull([(x * 1.03, y, z) for x, y, z in upper if y < .03 and z < .16], DARK_LEATHER(), m)
    # The tongue standing up out of the lacing, the padded collar, the pull loop.
    box((0, .07, .23), (.05, .02, .06), DARK_LEATHER(), m, .01)
    rod(m @ Vector((0, .025, .235)), m @ Vector((0, .025, .262)), .064 * BOOT, .062 * BOOT, DARK_LEATHER(), squash=1.1)
    rod(m @ Vector((0, -.042, .25)), m @ Vector((0, -.05, .29)), .012 * BOOT, .012 * BOOT, DARK_LEATHER(), seg=8)
    # The laces crossed up the vamp, brass eyelets either side, a bow on top.
    slope = math.atan2(.24 - .1, .2 - .06)
    for k in range(5):
        y = .19 - k * .03
        z = .122 + (.21 - y) * (.118 / .119) + .006
        for side in (1, -1):
            turn = Matrix.Rotation(-slope * .0, 4, "X") @ Matrix.Rotation(math.radians(28 * side), 4, "Z")
            box((0, 0, .008), (.066, .011, .011), LACE(), m @ Matrix.Translation((0, y, z)) @ turn, bevel=.003)
            ball((side * .034, y, z + .004), .008, EYELET(), (1, 1, 1), m)
    for side in (1, -1):
        rod(m @ Vector((0, .055, .24)), m @ Vector((side * .05, .02, .27)), .006 * BOOT, .005 * BOOT, LACE(), seg=6)
    # Mud dried on the welt and the toe.
    ball((.045, .2, .03), .024, MUD(), (1.6, 1.2, .5), m)
    ball((-.04, .05, .03), .02, MUD(), (1.8, 1.4, .5), m)


def leg(knee, m):
    """The right leg in the overalls from `knee` (below the view) up to the
    boot's shaft in the frame `m`, the cuff turned up once at the ankle."""
    top = m @ Vector((0, .0, .2))
    knee = Vector(knee)
    along = (top - knee).normalized()
    rod(knee, top, .1, .08, DENIM(), squash=.9)
    side = along.cross(Vector((0, 1, 0)))
    if side.length > 1e-4:
        side = side.normalized() * .082
        rod(knee + side, top - along * .05 + side, .003, .003, STITCH(), seg=6)
    # The cuff: a turned-up hem just short of the boot, paler on its fold.
    rod(top - along * .1, top - along * .03, .094, .092, DENIM(), squash=.92)
    rod(top - along * .1, top - along * .088, .096, .095, mat("hem", (104, 116, 140), .9, scale=20.),
        squash=.92)


def foot_frame(heel, toe_dir, up_dir):
    """The boot's frame: the heel's bottom at `heel`, the toe along `toe_dir`,
    the top of the foot as near `up_dir` as it can be."""
    y = Vector(toe_dir).normalized()
    z = Vector(up_dir).normalized()
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(heel)
    # A work boot read from its sole: a size up, and broad across the tread.
    return m @ Matrix.Scale(BOOT, 4) @ Matrix.Scale(WIDE, 4, Vector((1, 0, 0)))


# Mundell's boots, a size up on the eye (they read from the view as the
# gun cels' hands do).
BOOT = 1.3
WIDE = 1.5

# The kick from his own eye (at the origin, looking along +y, z up, map
# units; the game's view is the top 156 of the 200 rows rendered): the boot
# comes up from the bottom of the view sole first, its tread to the man
# kicked, the toe up, the stacked heel down and the overalls' cuff under it.
# Each: the heel, the toe's way, the top of the foot's way, the knee. Six
# frames since polish pass 9 (lifted and pulled back between the four).
POSES = {
    # Lifted: the knee coming up, the boot only just in the bottom of the view.
    "kick_5": ((.11, .66, -.42), (.05, .4, 1), (.35, .92, -.2), (.2, .15, -1.55)),
    # Chambered: the boot coming up low from the bottom of the view.
    "kick_0": ((.07, .78, -.35), (0, .45, 1), (.4, .9, -.3), (.18, .2, -1.5)),
    # Driven out, rising, the tread to him.
    "kick_1": ((.03, 1.05, -.28), (0, .55, 1), (.45, .8, -.5), (.14, .3, -1.45)),
    # The blow: the sole flat to him in the lower middle of the view, the
    # toe up, the stacked heel down, the cuff under it.
    "kick_2": ((.0, 1.28, -.2), (-.05, .6, 1), (.5, .8, -.5), (.12, .45, -1.45)),
    # Pulled back off him, the knee bending again, the toe tipping forward.
    "kick_4": ((.06, 1.0, -.3), (.08, .75, .75), (.45, .7, -.6), (.18, .28, -1.5)),
    # Back down and away to the right.
    "kick_3": ((.14, .88, -.34), (.25, .5, 1), (.1, .9, -.4), (.24, .25, -1.5)),
}
LOOK_DOWN = {}
# Every pose pushed this much further from the eye (the boot drawn this much
# smaller where it falls on the view): at 1.0 it covered half the view.
AWAY = 1.0


def stage():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = CANVAS
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (.60, .58, .54, 1)
    bg.inputs[1].default_value = .9
    nt.links.new(bg.outputs[0], out.inputs[0])
    for name, travel, power, color, spread in (("key", (.45, .35, -.82), 3.2, (1, .95, .86), 40),
                                               ("fill", (-.75, .45, -.3), 1.0, (.82, .88, 1), 60),
                                               ("kick", (-.3, -.8, -.35), 1.2, (1, .92, .8), 30)):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = power
        light.color = color
        light.angle = math.radians(spread)
        ob = bpy.data.objects.new(name, light)
        ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)
    cam = bpy.data.cameras.new("cam")
    cam.clip_start = .01
    cam.sensor_width = 36.0
    # The game's 3D view: 320 wide, about 74 degrees across.
    cam.lens = 36.0 / (2 * math.tan(math.radians(74) / 2))
    camera = bpy.data.objects.new("cam", cam)
    camera.location = (0, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera


def main():
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    for name, (heel, toe, top, knee) in POSES.items():
        if WANT and name not in WANT:
            continue
        doomed = list(PARTS)
        meshes = [ob.data for ob in doomed]
        PARTS.clear()
        bpy.data.batch_remove(doomed)
        bpy.data.batch_remove([me for me in meshes if me.users == 0])
        m = foot_frame(Vector(heel) * AWAY, toe, top)
        boot(m)
        leg(Vector(knee) * AWAY, m)
        camera.rotation_euler = (math.pi / 2 - LOOK_DOWN.get(name, 0.0), 0, 0)
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
    json.dump(list(POSES), open(os.path.join(OUT, "poses.json"), "w"))


main()
