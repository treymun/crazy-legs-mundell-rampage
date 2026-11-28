"""The painted boards as models for the 3D view: signs whose face is a picture
painted by the 2D art tools (godot/tools/art/build_town_signs.gd), given a
body here so they read from every side. Their face is the picture itself
(an emitter, so the bake keeps its colours: pre-graded so that the mesh
tool's photo grade lands back on them); their edges and back are modelled.

Not a sprite library: the pictures stay the 2D tools' own. Only
scripts/blender/export_meshes.py runs it:

    blender -b -P scripts/blender/export_meshes.py -- <out dir> <names|all> painted_boards.py

(godot/tools/art/build_prop_meshes.gd does). Not named props_*.py, so
town_props.py does not load it as a chapter's props.
"""
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(os.path.dirname(_HERE))
with open(os.path.join(_HERE, "town_props.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
# The library without its last line (main()).
exec(_source[: _source.rstrip().rfind("\n")], globals())


def _ungraded(c):
    """The colour that Paint.photo_grade (build_prop_meshes.gd) turns into
    `c` (0..1 each): its contrast and saturation undone; bright colours it
    leaves alone."""
    if max(c) > .93:
        return c
    c1 = [(v - .52) / 1.18 + .42 for v in c]
    grey = sum(c1) / 3.0
    return [min(1.0, max(0.0, grey + (v - grey) / .86)) for v in c1]


def picture(name):
    """The art picture assets/art/<name>.png as an emitting face material,
    laid once across a box() face (its own coordinates, -.5 to .5, which the
    faithful bake keeps: export_meshes.py). Returns (material, width px,
    height px)."""
    path = os.path.join(_REPO, "assets", "art", name + ".png")
    src = bpy.data.images.load(path)
    w, h = src.size
    px = list(src.pixels)
    img = bpy.data.images.new(name + "_face", w, h, alpha=False)
    out = [0.0] * (w * h * 4)
    for i in range(w * h):
        # Byte images hold display values (sRGB) as they are.
        rgb = _ungraded(px[i * 4: i * 4 + 3])
        for k in range(3):
            out[i * 4 + k] = rgb[k]
        out[i * 4 + 3] = 1.0
    img.pixels = out
    img.update()
    m = bpy.data.materials.new(name + "_face")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    nt.links.new(emit.outputs[0], o.inputs[0])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    split = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(coord.outputs["Object"], split.inputs[0])
    u = nt.nodes.new("ShaderNodeMath")
    u.operation = "ADD"
    u.inputs[1].default_value = .5
    v = nt.nodes.new("ShaderNodeMath")
    v.operation = "ADD"
    v.inputs[1].default_value = .5
    nt.links.new(split.outputs["X"], u.inputs[0])
    nt.links.new(split.outputs["Z"], v.inputs[0])
    join = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(u.outputs[0], join.inputs["X"])
    nt.links.new(v.outputs[0], join.inputs["Y"])
    nt.links.new(join.outputs[0], tex.inputs["Vector"])
    return m, w, h


def line_sign():
    """The town line sign, HICKSTON POP. 212 (the number crossed out): a
    pressed tin road sign, its picture on the front, a rolled edge, the
    galvanised back with two strap rails and their bolts."""
    face, w, h = picture("town_line_sign")
    height = .86
    width = height * w / h
    thick = .025
    green = mat(44, 92, 64, metal=.3, rough=.5, grime=.5)
    box(width, thick, height, (0, 0, height / 2), green)
    # The face: a thin plate just proud of the tin, the picture on it.
    box(width, .004, height, (0, -thick / 2 - .002, height / 2), face)
    back = mat(150, 152, 150, metal=.6, rough=.45, grime=.7)
    box(width - .02, .004, height - .02, (0, thick / 2 + .002, height / 2), back)
    steel = mat(96, 98, 100, metal=.7, rough=.4, grime=.6)
    for z in (height * .25, height * .75):
        box(width * .86, .03, .06, (0, thick / 2 + .019, z), steel)
        for x in (-width * .36, width * .36):
            cyl(.018, .02, (x, thick / 2 + .04, z), mat(*CHROME, metal=.8, grime=.5), (90, 0, 0), seg=8)
    for x in (-width * .34, width * .34):
        box(.046, .025, height * .86, (x, thick / 2 + .036, height / 2), steel)
        for z in (.128, height - .13):
            cyl(.012, .011, (x, -thick / 2 - .011, z), steel, (90, 0, 0), seg=6)
    for side in (-1, 1):
        box(width * .982, .022, .013, (0, -.002, height / 2 + side * .425), green)
        box(.013, .022, .832, (side * (width / 2 - .005), -.002, height / 2), green)
    return width + .2, height + .1


PROPS.clear()
PROPS.update({"line_sign": line_sign})
FLAT = {"line_sign"}
