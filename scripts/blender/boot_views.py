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


DENIM = lambda: mat("denim", (60, 70, 94), .85, weave=True, grain=(78, 88, 110), scale=18.)
PATCH = lambda: mat("patch", (176, 160, 124), .9, scale=24.)
STITCH = lambda: mat("stitch", (196, 150, 70), .8, scale=60.)
LEATHER = lambda: mat("leather", (112, 62, 30), .85, grain=(140, 86, 44), scale=22., bump=.4)
DARK_LEATHER = lambda: mat("dark_leather", (70, 38, 18), .8, grain=(110, 70, 40), scale=26.)
SOLE = lambda: mat("sole", (34, 28, 24), .9, scale=40., bump=.8)
LACE = lambda: mat("lace", (150, 120, 76), .9, scale=50.)
EYELET = lambda: mat("eyelet", (150, 120, 60), .35, metal=1.)
MUD = lambda: mat("mud", (92, 72, 48), 1., grain=(60, 46, 30), scale=12., bump=1.)


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


def boot(m):
    """A brown work boot in the frame `m`: the foot runs along local +y (toe),
    the sole is under local z = 0, the ankle's top at z = .2. Lengths in map
    units: a boot about .3 long."""
    # The sole and the heel, chunky lug rubber, rounded at the toe and heel.
    ball((0, .045, .012), 1.0, SOLE(), (.066, .175, .022), m)
    ball((0, -.085, -.004), 1.0, SOLE(), (.06, .075, .03), m)
    for k in range(6):
        ball((0, -.03 + k * .04, -.006), 1.0, SOLE(), (.06, .009, .012), m)
    # The welt round the foot, stitched.
    ball((0, .04, .032), 1.0, DARK_LEATHER(), (.069, .178, .012), m)
    for k in range(24):
        a = k / 24 * math.tau
        ball((math.cos(a) * .068, .04 + math.sin(a) * .177, .036), .0026, STITCH(), (1, 1, 1), m)
    # The foot: a squashed ball for the toe cap, a box for the vamp, the
    # shaft up the ankle.
    ball((0, .11, .07), .062, LEATHER(), (.95, 1.25, .72), m)
    ball((0, .11, .074), .056, DARK_LEATHER(), (.98, 1.3, .7), m)  # the toe cap's seam shows dark
    ball((0, .115, .076), .055, DARK_LEATHER(), (.96, 1.22, .69), m)
    box((0, .01, .075), (.112, .2, .09), LEATHER(), m, bevel=.03)
    rod(m @ Vector((0, -.04, .06)), m @ Vector((0, -.03, .23)), .066, .058, LEATHER(), squash=.92)
    # The tongue and the laces up its front, the eyelets.
    box((0, .05, .12), (.05, .12, .03), DARK_LEATHER(), m @ Matrix.Rotation(math.radians(-38), 4, "X"), bevel=.01)
    for k in range(5):
        y = .07 - k * .03
        z = .11 + k * .026
        box((0, y, z), (.048, .006, .006), LACE(), m @ Matrix.Rotation(math.radians(-30), 4, "X"), bevel=.002)
        for s in (1, -1):
            ball((s * .026, y, z), .006, EYELET(), (1, 1, 1), m)
    # A pull loop at the back, the ankle's padded collar.
    rod(m @ Vector((0, -.095, .2)), m @ Vector((0, -.1, .25)), .01, .01, DARK_LEATHER(), seg=8)
    rod(m @ Vector((0, -.035, .225)), m @ Vector((0, -.032, .245)), .068, .066, DARK_LEATHER(), squash=.92)
    # Dried mud on the welt and the toe.
    ball((.03, .14, .03), .03, MUD(), (1.4, 1, .4), m)
    ball((-.04, -.06, .03), .025, MUD(), (1.6, 1.2, .4), m)


def leg(hip, knee, ankle, foot_m):
    """The right leg from `hip` (under the eye) through `knee` to `ankle`, in
    the overalls; the boot at `foot_m`."""
    rod(hip, knee, .1, .08, DENIM(), squash=.95)
    ball(knee, .08, DENIM(), (1, 1, 1))
    rod(knee, ankle, .074, .064, DENIM(), squash=.95)
    # The tan patch on the thigh and the outside seam, stitched.
    mid = (Vector(hip) * .55 + Vector(knee) * .45)
    along = (Vector(knee) - Vector(hip)).normalized()
    side = along.cross(Vector((0, 0, 1))).normalized()
    out = side if side.x > 0 else -side
    patch_m = frame_along(mid + out * .06, mid + out * .06 + along)
    box((0, 0, 0), (.085, .02, .12), PATCH(), patch_m @ Matrix.Rotation(math.radians(90), 4, "Z"), bevel=.004)
    rod(Vector(hip) + out * .098, Vector(knee) + out * .08, .005, .005, STITCH(), seg=6)
    rod(Vector(knee) + out * .076, Vector(ankle) + out * .068, .005, .005, STITCH(), seg=6)
    # The cuff rolled once over the boot's top.
    a = Vector(ankle)
    up = (Vector(knee) - a).normalized()
    rod(a - up * .01, a + up * .05, .076, .074, DENIM(), squash=.95)
    boot(foot_m)


def foot_frame(ankle, toe_dir, sole_up):
    """The boot's frame: its ankle top at `ankle`, the toe along `toe_dir`,
    the top of the foot along `sole_up` (away from the sole)."""
    y = Vector(toe_dir).normalized()
    z = Vector(sole_up).normalized()
    z = (z - y * z.dot(y)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = Vector(ankle) - z * .2 * BOOT + y * .03 * BOOT
    return m @ Matrix.Scale(BOOT, 4)


# Mundell's boots, a size up on the eye (they read from the view as the
# gun cels' hands do).
BOOT = 1.3


# The poses (eye at the origin, looking along +y). Each: hip, knee, ankle,
# the toe's way and the top of the foot's way.
POSES = {
    # The boot driven out ahead: the cuff near, the laces and the toe cap up,
    # the sole's edge and the welt round it, the shin under it.
    "kick_1": ((.16, -.2, -.9), (.14, -.05, -.34), (.09, .36, -.14), (-.4, .25, 1), (.4, -1, -.15)),
}
# A pose's camera may look down (radians of pitch): none do now.
LOOK_DOWN = {}


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
    for name, (hip, knee, ankle, toe, top) in POSES.items():
        if WANT and name not in WANT:
            continue
        doomed = list(PARTS)
        meshes = [ob.data for ob in doomed]
        PARTS.clear()
        bpy.data.batch_remove(doomed)
        bpy.data.batch_remove([me for me in meshes if me.users == 0])
        leg(Vector(hip), Vector(knee), Vector(ankle), foot_frame(ankle, toe, top))
        camera.rotation_euler = (math.pi / 2 - LOOK_DOWN.get(name, 0.0), 0, 0)
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
    json.dump(list(POSES), open(os.path.join(OUT, "poses.json"), "w"))


main()
