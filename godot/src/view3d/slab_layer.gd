## The world's flat pictures that the 3D view draws as slabs (SlabModels):
## pickups, loose things (brass, gibs, bits, chips, hats, dropped guns) and
## the firing range's targets, each where its sprite stood and the same size
## from the front. One MultiMesh per mesh; the art comes from the sprites'
## texture array (SpriteLayer3D slots), so the light, tint, fog and palette
## are the sprites' own (slab.gdshader). Looks only, and nothing is kept from
## frame to frame: each slab's turn comes from its sprite.
##
## - A pickup turns slowly on the game clock (the bob is the sprite's,
##   game_view.gd). EASY ON THE EYES (View.world_motion) slows the turn
##   (REDUCED) or stops it (STILL), where a pickup faces the eye as the
##   sprite did.
## - A loose thing in the air tumbles: it turns over about its face by the
##   sprite's `spin` and end over end by PITCH of it, heading where its place
##   says (HEADING: it turns as it flies and slides, and lies still at rest).
##   On its floor (`lying`) it lies flat, face up (face down when flipped).
##   Either way its lowest corner is on the sprite's z, as the turned
##   billboard's was.
## - A target stands on its foot along its `plane` (facing the eye when it has
##   none), turned round when flipped, leaning back by `tilt` about its foot;
##   a gong's plate (SlabModels.PARTS) leans by `tilt` from its bar instead.
class_name SlabLayer3D
extends Node3D

## A pickup's turn, radians a second at full motion (one turn in seven seconds).
const TURN := .9
## How fast each EASY ON THE EYES step turns a pickup (FULL, REDUCED, STILL).
const MOTION := [1.0, .4, 0.0]
## As far ahead as the sprites are drawn (sprite_layer.gd; a target as far
## as a tall sprite, so the rifle range's far gongs show from the line), and
## how far behind the eye a slab's near side may still reach into the view.
const REACH := 32.0
const TARGET_REACH := 51.0
const BEHIND := -.3
## A loose thing's heading, radians for each cell of its place along x and y.
const HEADING := Vector2(3.1, 4.3)
## In the air a loose thing turns end over end this much for each radian it
## turns about its face (and from PITCH_FROM): a tumble, not a flat spin.
const PITCH := .7
const PITCH_FROM := .9
## How far a lying thing is propped up off flat: from x, up to x + y radians,
## by its place.
const PROP := Vector2(.1, .35)
## Coming to its floor: seconds to ease from the tumble to lying, and the
## rock after (radians at first, radians a second, how fast it dies, and
## when it is over).
const SETTLE := .28
const ROCK := .3
const ROCK_RATE := 21.0
const ROCK_DAMP := 6.5
const ROCK_TIME := .9

var models: SlabModels
var material: ShaderMaterial
var _sprites: SpriteLayer3D
## mesh key -> MultiMeshInstance3D
var _shown: Dictionary = {}
## picture -> its mesh's box (sprite units)
var _boxes: Dictionary = {}


func _init(p_models: SlabModels, sprites: SpriteLayer3D) -> void:
	models = p_models
	_sprites = sprites
	material = ShaderMaterial.new()
	material.shader = load("res://src/view3d/slab.gdshader")
	material.set_shader_parameter("art", sprites.art)


## True when sprite `s` is drawn here (a slab picture with a mesh; a pickup
## only when it is not a board).
func takes(s: View.Sprite) -> bool:
	if s.translucent:
		return false
	var kind := SlabModels.family(s.image)
	if kind == SlabModels.NONE or (kind == SlabModels.PICKUP and not is_nan(s.plane)):
		return false
	return models.mesh(s.image) != null


## Show these sprites (each one `takes`) and no other slabs, seen from `cam`
## looking along `angle`; `everywhere` keeps the ones behind the eye (the
## mirror may show them). Call after SpriteLayer3D.show_sprites.
func show_slabs(
	list: Array,
	level: LevelData,
	cam: Vector3,
	angle: float,
	clock: float,
	motion: int,
	everywhere := false
) -> void:
	var fx := cos(angle)
	var fy := sin(angle)
	var speed: float = MOTION[clampi(motion, 0, 2)]
	# Square to the view, its front (+Z) toward the eye, as the sprite stood.
	var facing := atan2(-fx, -fy)
	var rows := {}
	for item: Variant in list:
		var s: View.Sprite = item
		var kind := SlabModels.family(s.image)
		var ahead := (s.x - cam.x) * fx + (s.y - cam.y) * fy
		var reach := TARGET_REACH if kind == SlabModels.TARGET else REACH
		if ahead >= reach or (ahead <= BEHIND and not everywhere):
			continue
		var tone := SpriteLayer3D.tone_at(level, s.x, s.y, s.glow)
		var slot := _sprites.slot(s.image)
		var size := _sprites.slot_size(slot)
		var art := Vector4(float(slot), float(size.x), float(size.y), 0.0)
		art.w = float(SpriteLayer3D.GLOW if s.glow else 0)
		match kind:
			SlabModels.PICKUP:
				var turn := facing
				if speed > 0.0:
					turn = fposmod(clock * TURN * speed + s.x * 1.7 + s.y * 2.3, TAU)
				var basis := Basis(Vector3.UP, turn).scaled(Vector3.ONE * s.height)
				_add(rows, s.image, Transform3D(basis, Vector3(s.x, s.z, s.y)), tone, art)
			SlabModels.LOOSE:
				_add(rows, s.image, _loose(s), tone, art)
			_:
				_target(rows, s, facing, tone, art)
	for key: String in rows:
		var node: MultiMeshInstance3D = _shown.get(key)
		if node == null:
			node = _layer(models.mesh(key))
			_shown[key] = node
		var filled: PackedFloat32Array = rows[key]
		SpriteLayer3D.fill(node, filled)
	for key: String in _shown:
		if not rows.has(key):
			var idle: MultiMeshInstance3D = _shown[key]
			idle.multimesh.visible_instance_count = 0


## A loose thing: tumbling in the air, flat on its floor, its lowest corner
## on the sprite's z and its middle over the sprite's x, y.
func _loose(s: View.Sprite) -> Transform3D:
	var box: AABB = _boxes.get(s.image, AABB())
	if not _boxes.has(s.image):
		box = models.mesh(s.image).get_aabb()
		_boxes[s.image] = box
	var basis := turn_of(s)
	var half := box.size * .5 * s.height
	var low := absf(basis.x.y) * half.x + absf(basis.y.y) * half.y + absf(basis.z.y) * half.z
	var middle := basis * (box.get_center() * s.height)
	var at := Vector3(s.x, s.z + low, s.y) - middle
	return Transform3D(basis.scaled(Vector3.ONE * s.height), at)


## How a loose thing's slab is turned (view axes, y up): tumbling in the air
## by its `spin`, settling onto its floor or lying there.
static func turn_of(s: View.Sprite) -> Basis:
	var heading := s.x * HEADING.x + s.y * HEADING.y
	var basis := Basis(Vector3.UP, heading)
	var air := (
		basis * Basis(Vector3.RIGHT, s.spin * PITCH + PITCH_FROM) * Basis(Vector3.BACK, s.spin)
	)
	if not s.lying:
		return air
	if s.settle >= 0.0:
		return settled(air, heading, s.settle, s.roll)
	# Flat, or propped a little on something under one end (a lump lies so):
	# the picture still reads from a standing eye.
	var prop := PROP.x + PROP.y * fposmod(heading * .618, 1.0)
	basis = basis * Basis(Vector3.RIGHT, prop - PI * .5)
	if s.flip:
		basis = basis * Basis(Vector3.UP, PI)
	return basis


## A loose thing `since` seconds on its floor (View.Sprite.settle) that was
## turned `air` as it came down: it eases over onto the face nearer the
## floor in SETTLE (no snap), turned about the floor's normal no more than it
## must, and rocks a little on it, less each time (ROCK); `roll` turns a
## round thing (a shell) about its length as it rolls. At rest it lies flat
## or propped on one end by its place (PROP), as before, the same each frame.
static func settled(air: Basis, heading: float, since: float, roll: float) -> Basis:
	var down := air.z.y < 0.0
	var along := -air.x if down else air.x
	var yaw := heading
	if Vector2(along.x, along.z).length() > .2:
		yaw = atan2(-along.z, along.x)
	# (By a smooth function of its place: one rolling props up smoothly.)
	var prop := PROP.x + PROP.y * (.5 + .5 * sin(heading * 3.9))
	var lie := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, prop - PI * .5)
	if down:
		lie = lie * Basis(Vector3.UP, PI)
	if roll != 0.0:
		lie = lie * Basis(Vector3.RIGHT, roll)
	if since >= ROCK_TIME:
		return lie
	var w := smoothstep(0.0, SETTLE, since)
	var out := air.slerp(lie, w) if w < 1.0 else lie
	var rock := ROCK * exp(-since * ROCK_DAMP) * sin(since * ROCK_RATE)
	return Basis(lie.x.normalized(), rock) * out


## A target on its stand, and its swinging part when it has one.
func _target(rows: Dictionary, s: View.Sprite, facing: float, tone: Color, art: Vector4) -> void:
	var turn := Basis(Vector3.UP, facing if is_nan(s.plane) else -s.plane)
	var about := Basis(Vector3.UP, PI) if s.flip else Basis.IDENTITY
	var lean := Basis(Vector3.RIGHT, -s.tilt)
	var foot := Vector3(s.x, s.z, s.y)
	var grow := Vector3.ONE * s.height
	var hang := models.pivot(s.image)
	if is_nan(hang):
		var whole := (turn * lean * about).scaled(grow)
		_add(rows, s.image, Transform3D(whole, foot), tone, art)
		return
	_add(rows, s.image, Transform3D((turn * about).scaled(grow), foot), tone, art)
	if models.mesh(s.image + SlabModels.PART) == null:
		return
	var part := turn * lean * about
	var bar := Vector3(0.0, hang * s.height, 0.0)
	var at := foot + turn * bar - part * bar
	_add(rows, s.image + SlabModels.PART, Transform3D(part.scaled(grow), at), tone, art)


## One instance's 20 numbers into its mesh's row: its transform, its tint and
## light, its art slot and size, its flags.
static func _add(rows: Dictionary, key: String, t: Transform3D, tone: Color, art: Vector4) -> void:
	var buf: PackedFloat32Array = rows.get(key, PackedFloat32Array())
	var b := t.basis
	buf.append_array(
		PackedFloat32Array(
			[
				b.x.x,
				b.y.x,
				b.z.x,
				t.origin.x,
				b.x.y,
				b.y.y,
				b.z.y,
				t.origin.y,
				b.x.z,
				b.y.z,
				b.z.z,
				t.origin.z,
				tone.r,
				tone.g,
				tone.b,
				tone.a,
				art.x,
				art.y,
				art.z,
				art.w
			]
		)
	)
	rows[key] = buf


func _layer(mesh: ArrayMesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The slabs are spread over the level: the box is set wide.
	node.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	add_child(node)
	return node
