## Marks on the 3D view's modelled things: bullet holes where a marking shot
## met a prop, a vehicle (a prop too) or a wreck piece, scorch where a blast
## went off beside one, and char on what fire burned (features/fire.gd: its
## cell burning or burnt out; a vehicle burning or burnt out), as wall marks
## are on walls.
##
## The shots and blasts come from features/impacts.gd (`thing_hits`, each
## taken once by its serial); the shot's line from the gun to where it ended
## is met with each nearby part's own triangles (a TriangleMesh a mesh, made
## the first time), so a hole sits on the model where the bullet went in,
## kept in that part's own space: it moves with a carried, thrown or flung
## thing and a driving car. A part keeps its marks in its meta (`marks`, at
## most MOST, the oldest going first; `char`) and hands them to its shader
## (thing_marks.gdshaderinc: mark0..mark5, char_k). PropLayer3D keeps the
## marks of props out of view and passes them on to a prop made again where
## one went; at most MOST_MARKED parts carry marks, the oldest cleared first.
## Looks only: nothing here changes play or is saved.
class_name ThingMarks
extends RefCounted

const ImpactsFeature := preload("res://src/features/impacts.gd")
const FireFeature := preload("res://src/features/fire.gd")
const Vehicles := preload("res://src/features/vehicles.gd")

## Marks a part keeps (the shader's mark0..mark5).
const MOST := 6
## Parts carrying marks at once.
const MOST_MARKED := 64
## A bullet hole's and a scorch's radius (cells).
const HOLE := .05
const SCORCH := .32
## How far round a blast things are scorched (cells), and how many at most.
const BLAST_REACH := 2.6
const BLAST_MOST := 8
## How burnt a thing gets: in a burning cell, a burnt-out one; a vehicle
## burning out, and one badly hurt.
const CHAR_BURNING := .45
const CHAR_BURNT := .85
const CHAR_WRECK := .9
const CHAR_HURT := .3
## Seconds between looks at what fire has burned.
const CHAR_EVERY := .3

var _seen := 0
var _tris := {}
var _marked: Array[int] = []
var _char_next := 0.0


## This frame: mark what the new shots and blasts met, char what burned.
func update(game: Game, props: PropLayer3D, wrecks: WreckLayer3D) -> void:
	var impacts: ImpactsFeature = game.features.get("impacts")
	if impacts != null and impacts.thing_serial != _seen:
		if impacts.thing_serial < _seen:
			_seen = 0
		var parts := _parts(props, wrecks)
		for row: Array in impacts.thing_hits:
			var serial: int = row[0]
			if serial <= _seen:
				continue
			var from: Vector3 = row[1]
			var to: Vector3 = row[2]
			if from == to:
				_blast(from, parts)
			else:
				_shot(from, to, parts)
		_seen = impacts.thing_serial
	var all := game.clock >= _char_next or game.clock < _char_next - 1.0
	if all:
		_char_next = game.clock + CHAR_EVERY
	var nodes: Array = props.shown() if all else props.made
	_char(game, nodes, all, wrecks)


## Every shown part: [part, the prop it belongs to or null].
func _parts(props: PropLayer3D, wrecks: WreckLayer3D) -> Array:
	var out: Array = []
	for item: Variant in props.shown():
		var node: PropView = item
		if not node.is_inside_tree():
			continue
		for mesh: MeshInstance3D in node.meshes():
			if mesh.is_visible_in_tree() and mesh.mesh != null:
				out.append(mesh)
	for item: Variant in wrecks.shown():
		var piece: MeshInstance3D = item
		if piece.is_inside_tree() and piece.visible and piece.mesh != null:
			out.append(piece)
	return out


## A shot from `from` to `to` (map axes): a hole in the first part it met.
func _shot(from: Vector3, to: Vector3, parts: Array) -> void:
	var a := Vector3(from.x, from.z, from.y)
	var b := Vector3(to.x, to.z, to.y)
	var length := a.distance_to(b)
	if length < .01:
		return
	var dir := (b - a) / length
	var box := AABB(a, Vector3.ZERO).expand(b).grow(2.5)
	var best_d := length + .4
	var best: MeshInstance3D = null
	var best_at := Vector3.ZERO
	for item: Variant in parts:
		var mesh: MeshInstance3D = item
		var xf := mesh.global_transform
		if not box.has_point(xf.origin):
			continue
		var reach := mesh.get_aabb().size.length() * xf.basis.get_scale().x
		var middle := xf * mesh.get_aabb().get_center()
		if middle.distance_to(Geometry3D.get_closest_point_to_segment(middle, a, b)) > reach:
			continue
		var hit := _hit(mesh, xf, a, dir)
		if hit.is_empty():
			continue
		var own: Vector3 = hit["position"]
		var d := a.distance_to(xf * own)
		if d < best_d:
			best_d = d
			best = mesh
			best_at = own
	if best != null:
		_add(best, best_at, 1, HOLE / maxf(.05, best.global_transform.basis.get_scale().x))


## A blast at `at` (map axes): scorch on the side facing it of each part near.
func _blast(at: Vector3, parts: Array) -> void:
	var c := Vector3(at.x, at.z, at.y)
	var near: Array = []
	for item: Variant in parts:
		var mesh: MeshInstance3D = item
		var middle := mesh.global_transform * mesh.get_aabb().get_center()
		var d := middle.distance_to(c)
		if d < BLAST_REACH:
			near.append([d, mesh, middle])
	near.sort_custom(func(m: Array, n: Array) -> bool: return ViewShadows.nearer(m, n, 0))
	for k in mini(BLAST_MOST, near.size()):
		var row: Array = near[k]
		var mesh: MeshInstance3D = row[1]
		var middle: Vector3 = row[2]
		var xf := mesh.global_transform
		var way := middle - c
		if way.length() < .05:
			continue
		var hit := _hit(mesh, xf, c, way.normalized())
		if hit.is_empty():
			continue
		var own: Vector3 = hit["position"]
		_add(mesh, own, 2, SCORCH / maxf(.05, xf.basis.get_scale().x))


## Where the ray from `from` along `dir` (Godot axes) meets the part, in its
## own space ({} when it misses).
func _hit(mesh: MeshInstance3D, xf: Transform3D, from: Vector3, dir: Vector3) -> Dictionary:
	var inv := xf.affine_inverse()
	var local_dir := inv.basis * dir
	if local_dir.length() < 1e-6:
		return {}
	var tris: TriangleMesh = _tris.get(mesh.mesh)
	if tris == null:
		tris = mesh.mesh.generate_triangle_mesh()
		if tris == null:
			return {}
		_tris[mesh.mesh] = tris
	return tris.intersect_ray(inv * from, local_dir.normalized())


## A mark of `kind` (1 hole, 2 scorch) at `own` (the part's space), `r` its
## own units.
func _add(mesh: MeshInstance3D, own: Vector3, kind: int, r: float) -> void:
	var marks: PackedVector4Array = mesh.get_meta("marks", PackedVector4Array())
	marks.append(Vector4(own.x, own.y, own.z, kind * 10.0 + clampf(r, .005, 9.9)))
	if marks.size() > MOST:
		marks.remove_at(0)
	mesh.set_meta("marks", marks)
	apply(mesh)
	var id := mesh.get_instance_id()
	_marked.erase(id)
	_marked.append(id)
	while _marked.size() > MOST_MARKED:
		var old_id: int = _marked.pop_front()
		var old := instance_from_id(old_id) as MeshInstance3D
		if old != null:
			old.set_meta("marks", PackedVector4Array())
			apply(old)


## Char the props `nodes` (and with `all` the wreck pieces) by what burned.
func _char(game: Game, nodes: Array, all: bool, wrecks: WreckLayer3D) -> void:
	var fire: FireFeature = game.features.get("fire")
	var cars: Vehicles = game.features.get("vehicles")
	var burning := fire != null and (not fire.burning.is_empty() or not fire.charred.is_empty())
	var wrecked := cars != null and not cars.rides.is_empty()
	if not burning and not wrecked:
		return
	var level: LevelData = game.level
	for item: Variant in nodes:
		var node: PropView = item
		var at := node.position
		var k := _burnt(level, fire, at.x, at.z) if burning else 0.0
		if wrecked:
			k = maxf(k, _car_char(cars, at.x, at.z))
		if k > 0.0:
			for mesh: MeshInstance3D in node.meshes():
				_char_to(mesh, k)
	if all and burning:
		for item: Variant in wrecks.shown():
			var piece: MeshInstance3D = item
			var k := _burnt(level, fire, piece.position.x, piece.position.z)
			if k > 0.0:
				_char_to(piece, k)


## How burnt what stands at map (x, y) is.
static func _burnt(level: LevelData, fire: FireFeature, x: float, y: float) -> float:
	if x < 0.0 or y < 0.0 or x >= level.width or y >= level.height:
		return 0.0
	var c := level.cell(x, y)
	if fire.charred.has(c):
		return CHAR_BURNT
	return CHAR_BURNING if fire.burning_at(x, y) else 0.0


## How burnt the vehicle at map (x, y) is, if one stands there.
static func _car_char(cars: Vehicles, x: float, y: float) -> float:
	for item: Variant in cars.rides:
		var v: VehicleDrive.Ride = item
		if absf(v.x - x) > .8 or absf(v.y - y) > .8:
			continue
		if v.wreck >= 0.0:
			return CHAR_WRECK
		if v.hp < VehicleDrive.spec(v.kind).hp * .25:
			return CHAR_HURT
	return 0.0


## Burn a part to `k` (never back).
static func _char_to(mesh: MeshInstance3D, k: float) -> void:
	var had: float = mesh.get_meta("char", 0.0)
	if k > had + .001:
		mesh.set_meta("char", k)
		mesh.set_instance_shader_parameter("char_k", k)


## Hand a part's marks and char to its shader.
static func apply(mesh: MeshInstance3D) -> void:
	var marks: PackedVector4Array = mesh.get_meta("marks", PackedVector4Array())
	for i in MOST:
		mesh.set_instance_shader_parameter(
			"mark%d" % i, marks[i] if i < marks.size() else Vector4.ZERO
		)
	var burnt: float = mesh.get_meta("char", 0.0)
	mesh.set_instance_shader_parameter("char_k", burnt)


## A part with no marks and no char (a wreck piece's node handed on).
static func clear(mesh: MeshInstance3D) -> void:
	if not mesh.has_meta("marks") and not mesh.has_meta("char"):
		return
	mesh.remove_meta("marks")
	mesh.remove_meta("char")
	apply(mesh)


## The marks of these parts, to keep: [[part index, marks, char], ...].
static func saved(meshes: Array[MeshInstance3D]) -> Array:
	var out: Array = []
	for i in meshes.size():
		var mesh := meshes[i]
		var marks: PackedVector4Array = mesh.get_meta("marks", PackedVector4Array())
		var burnt: float = mesh.get_meta("char", 0.0)
		if not marks.is_empty() or burnt > 0.0:
			out.append([i, marks, burnt])
	return out


## Put kept marks back on parts of the same model (saved()).
static func restore(meshes: Array[MeshInstance3D], kept: Array) -> void:
	for row: Array in kept:
		var i: int = row[0]
		if i >= meshes.size():
			continue
		var mesh := meshes[i]
		var marks: PackedVector4Array = row[1]
		var burnt: float = row[2]
		mesh.set_meta("marks", marks)
		mesh.set_meta("char", burnt)
		apply(mesh)
