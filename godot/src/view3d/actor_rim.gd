## A body's own rim (pass 15, effects.cfg [rim]; ENEMY RIM on the DISPLAY
## page: OFF, SOFT the default, BOLD): a hostile hand awake wears a warm edge
## round his outline, a little stronger far off so a far hand reads; the
## animals a cool one. Drawn by actor_rim.gdshader as each part's next pass
## (its back faces swollen out about one pixel at 320 wide (SOFT) or a
## little more (BOLD), thinner far off: only the outline shows, never a speck
## inside the figure nor a filled cutout of a far one), hung on a part only while it has a rim and
## LIGHTS AND GLOW is on (QUALITY LOW drops it), and taken off under a hit's
## wash and as a wind-up's amber rises. Looks only: it reads the hand, never
## play's dice; nothing is kept but when each model's rim came up
## (ActorView.rim_since), for its fade.
class_name ActorRim
extends RefCounted

const SHADER := preload("res://src/view3d/actor_rim.gdshader")
## A part's rim material (its own), kept on the part.
const META := "rim_pass"

## ENEMY RIM (game_world.gd configure): 0 OFF, 1 SOFT, 2 BOLD.
const OFF := 0
const SOFT := 1
const BOLD := 2
static var mode := SOFT

static var _version := -1
## Each mode's look (the pass's `look`) and the share of the fog it shows
## through: [OFF, SOFT, BOLD].
static var _looks: Array[Vector4] = [
	Vector4.ZERO, Vector4(.6, .3, .6, .3), Vector4(1.0, .45, 1.0, .45)
]
static var _fog_cuts: Array[float] = [0.0, .35, .6]
static var _awake := Color(1, .5, .18, .3)
static var _critter := Color(.62, .78, 1, .24)
static var _reach := Vector4(.75, 3.0, 15.0, .6)
static var _fade := .3
static var _critters := {}
## Mesh -> which way its normals point (normal_out): +1 or -1.
static var _outs := {}


static func _read() -> void:
	if _version == Effects.version:
		return
	_version = Effects.version
	var awake: Color = Effects.num("rim", "awake", Color(1, .5, .18))
	var near: float = Effects.num("rim", "near", .3)
	_awake = Color(awake.r, awake.g, awake.b, near)
	var cool: Color = Effects.num("rim", "critter", Color(.62, .78, 1))
	var cool_k: float = Effects.num("rim", "critter_strength", .24)
	_critter = Color(cool.r, cool.g, cool.b, cool_k)
	var far: float = Effects.num("rim", "far", .75)
	var near_at: float = Effects.num("rim", "near_at", 3.0)
	var far_at: float = Effects.num("rim", "far_at", 15.0)
	_reach = Vector4(far, near_at, far_at, 0.0)
	for k: int in [SOFT, BOLD]:
		var row: Array = Effects.num("rim", "soft" if k == SOFT else "bold", [])
		if row.size() >= 5:
			var swell: float = row[0]
			var lo: float = row[1]
			var hi: float = row[2]
			var share: float = row[3]
			var cut: float = row[4]
			_looks[k] = Vector4(swell, lo, hi, share)
			_fog_cuts[k] = cut
	_fade = Effects.num("rim", "fade", .3)
	_critters = {}
	var kinds: Array = Effects.num("rim", "critters", [])
	for kind: Variant in kinds:
		_critters[str(kind)] = true


## The rim `who` wears (rgb, a how much up close; a 0: none), without the fade.
static func wanted(who: Object) -> Color:
	_read()
	if not Effects.enabled or mode == OFF:
		return Color(0, 0, 0, 0)
	var e: Enemy = who as Enemy
	if e == null or not e.alive or e.dormant:
		return Color(0, 0, 0, 0)
	if e.hostile:
		return _awake if e.alerted else Color(0, 0, 0, 0)
	if _critters.has(e.kind):
		# The far reach is a hand's: an animal's rim stays as it is up close.
		return _critter
	return Color(0, 0, 0, 0)


## The rim for model `view` showing `who` now. One that comes up while the
## model is in sight (a hand waking) fades in over `fade` seconds; a body
## first seen with one has it whole.
static func of(view: ActorView, who: Object) -> Color:
	var want := wanted(who)
	if want.a <= 0.0:
		view.rim_since = -1.0
		view.rim_off_seen = true
		return want
	if view.rim_since < 0.0 or view.rim_since > view.shown_at:
		view.rim_since = view.shown_at if view.rim_off_seen else view.shown_at - _fade
	var up := clampf((view.shown_at - view.rim_since) / maxf(_fade, .001), 0.0, 1.0)
	return Color(want.r, want.g, want.b, want.a * up)


## How the rim of `who` reaches far off (the rim pass's `reach`): a hand's
## grows with distance, an animal's does not.
static func reach(who: Object) -> Vector4:
	_read()
	var e: Enemy = who as Enemy
	var cut: float = _fog_cuts[clampi(mode, OFF, BOLD)]
	if e != null and e.hostile:
		return Vector4(_reach.x, _reach.y, _reach.z, cut)
	return Vector4(_critter.a, _reach.y, _reach.z, cut)


## The pass's `look` for ENEMY RIM's `mode`: [most swelling (view pixels),
## brightness up close, far off, most share of the body's height].
static func look_of(rim_mode: int) -> Vector4:
	_read()
	return _looks[clampi(rim_mode, OFF, BOLD)]


## The rim under a hit's wash (`hurt` above 0: none) and a wind-up's amber
## (`tell`: it gives way as the amber rises, gone at .38), so the tell reads.
static func quieted(rim: Color, hurt: float, tell: float) -> Color:
	var k := 0.0 if hurt > 0.0 else 1.0 - clampf(tell / .38, 0.0, 1.0)
	return Color(rim.r, rim.g, rim.b, rim.a * k)


## Hang the rim on part `mesh` (its material's next pass) or take it off (a 0).
static func dress(mesh: GeometryInstance3D, rim: Color, far: Vector4) -> void:
	var own := mesh.material_override as ShaderMaterial
	if own == null:
		return
	if rim.a <= 0.0:
		own.next_pass = null
		return
	var pass_of: ShaderMaterial = mesh.get_meta(META) if mesh.has_meta(META) else null
	if pass_of == null:
		pass_of = ShaderMaterial.new()
		pass_of.shader = SHADER
		mesh.set_meta(META, pass_of)
	pass_of.set_shader_parameter("rim", rim)
	pass_of.set_shader_parameter("reach", far)
	pass_of.set_shader_parameter("look", look_of(mode))
	var part := mesh as MeshInstance3D
	if part != null and part.mesh != null:
		pass_of.set_shader_parameter("normal_out", normal_out(part.mesh))
	own.next_pass = pass_of


## Which way to swell `mesh` along its normals (the pass's `normal_out`): the
## other way from where its normals point out of its first surface (summed
## from the middle of its points), as the pictures found the shader sees them
## turned round from the arrays; worked out once a mesh.
static func normal_out(mesh: Mesh) -> float:
	var known: Variant = _outs.get(mesh)
	if known != null:
		var sign: float = known
		return sign
	var out := 1.0
	if mesh.get_surface_count() > 0:
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if not points.is_empty() and normals.size() == points.size():
			var middle := Vector3.ZERO
			for v in points:
				middle += v
			middle /= points.size()
			var sum := 0.0
			for i in points.size():
				sum += normals[i].dot(points[i] - middle)
			out = 1.0 if sum < 0.0 else -1.0
	_outs[mesh] = out
	return out
