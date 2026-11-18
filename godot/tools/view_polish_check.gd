## The view polish (track L) headless, run by tools/camera_check.gd:
## - SHADOWS (view3d/view_shadows.gd): a hand by a strong light makes a pair
##   with that light (its own light, a far one and a weak one make none), the
##   sky lays a blob under it, a dead body lies along its heading; SHADOWS off,
##   or LIGHTS AND GLOW off, makes none; QUALITY LOW turns SHADOWS off.
## - Marks on modelled things (view3d/thing_marks.gd): a marking shot puts a
##   hole on the prop's model where the line meets it, a blast a scorch, both
##   in the part's own space; the marks come back when the prop is shown again
##   and move on to a prop made again where one went (a car stood again at
##   its next place); a burnt-out cell chars what stands in it; BULLET MARKS
##   off records no shots.
## - The storm front's wall (world_view.gd _storm): both curtains stand round
##   the ring while a stage is called, the ring is handed to the shaders, and
##   only the front curtain with LIGHTS AND GLOW off.
extends RefCounted

const ImpactsFeature := preload("res://src/features/impacts.gd")
const FireFeature := preload("res://src/features/fire.gd")


static func run(main, check: Callable) -> void:
	print("VIEW POLISH (shadows, marks on props, the storm wall)")
	_shadows(main, check)
	_marks(main, check)
	_storm(main, check)


static func _shadows(main, check: Callable) -> void:
	main.start("hickston")
	var g: Game = main.game
	var lights_were := Effects.enabled
	Effects.enabled = true
	View.shadows = true
	var e := Enemy.new("billy", 20.5, 20.5)
	var s := View.Sprite.new(e.x, e.y, "billy", 1.0, 0.0)
	s.who = e
	var eye := Vector3(24.5, 20.5, .95)
	var models := PropModels.new(g.art)
	var sh := ViewShadows.new()
	var near := [21.5, 20.5, 1.4, 5.0, Color.WHITE, 1.0, 0]
	var own := [20.5, 20.5, .8, 5.0, Color.WHITE, 1.0, 0]
	var far := [60.5, 20.5, 1.4, 5.0, Color.WHITE, 1.0, 0]
	var weak := [21.0, 21.0, 1.4, 1.0, Color.WHITE, .1, 0]
	sh.collect(g, [s], [], [], eye, models)
	sh.pair([near, own, far, weak])
	var lights_of := {}
	for k in sh.pair_count:
		lights_of[int(sh.pair_b[k].w)] = true
	check.call(
		lights_of.has(0) and not lights_of.has(1) and not lights_of.has(2) and not lights_of.has(3),
		"a hand by a strong light throws a shadow; its own, a far and a weak light none"
	)
	var under := false
	for k in sh.blob_count:
		var b: Vector4 = sh.blobs[k]
		under = under or (absf(b.x - e.x) < .01 and absf(b.y - e.y) < .01 and absf(b.z) < .01)
	check.call(under, "the sky lays a blob under the hand, on its floor")
	e.hp = 0.0
	e.angle = 0.0
	sh.collect(g, [s], [], [], eye, models)
	sh.pair([near])
	var lying := sh.pair_count > 0 and absf(sh.pair_a[0].z - sh.pair_b[0].z) < .01
	lying = lying and absf(sh.pair_a[0].x - sh.pair_b[0].x) > .3
	check.call(lying, "a dead hand's shadow lies along its heading")
	View.shadows = false
	sh.collect(g, [s], [], [], eye, models)
	sh.pair([near])
	check.call(sh.pair_count == 0 and sh.blob_count == 0, "SHADOWS off: none")
	View.shadows = true
	Effects.enabled = false
	sh.collect(g, [s], [], [], eye, models)
	sh.pair([near])
	check.call(sh.pair_count == 0 and sh.blob_count == 0, "LIGHTS AND GLOW off: none")
	Effects.enabled = lights_were
	var low := Quality.preset(Quality.LOW)
	check.call(low["shadows"] == 0, "QUALITY LOW turns SHADOWS off")


## A prop layer of its own over hickston, a barrel shot, blasted and burnt.
static func _marks(main, check: Callable) -> void:
	main.start("hickston")
	var g: Game = main.game
	var models := PropModels.new(g.art)
	var name := ""
	for n: String in ["warning_barrel", "mash_barrel", "tnt_crate"]:
		if name == "" and models.sizes.has(n):
			name = n
	if name == "":
		check.call(false, "a barrel model to mark")
		return
	var layer := PropLayer3D.new(models)
	var wrecks := WreckLayer3D.new(g.art)
	main.add_child(layer)
	main.add_child(wrecks)
	var at := Vector2(30.5, 30.5)
	var s := View.Sprite.new(at.x, at.y, "town_" + name, 1.0, 0.0)
	layer.show_props([s], g.level)
	var node: PropView = layer.shown()[0]
	var impacts: ImpactsFeature = g.features["impacts"]
	var marks := ThingMarks.new()
	var tall: float = models.sizes[name][2] * models.scale_of(name, 1.0)
	# A shot from 3 cells west at half its height, into its middle.
	impacts.thing_serial += 1
	impacts.thing_hits.append(
		[impacts.thing_serial, Vector3(at.x - 3.0, at.y, tall * .5), Vector3(at.x, at.y, tall * .5)]
	)
	marks.update(g, layer, wrecks)
	var found := _marks_of(node)
	var hole := found.size() == 1 and int(found[0].w / 10.0) == 1
	var west := false
	if hole:
		var mesh: MeshInstance3D = _marked_part(node)
		var where := mesh.global_transform * Vector3(found[0].x, found[0].y, found[0].z)
		west = where.x < at.x - .05 and absf(where.y - tall * .5) < .3
	check.call(hole and west, "a shot holes the barrel's model on the side it came from")
	impacts.thing_serial += 1
	var blast := Vector3(at.x, at.y + 1.2, .4)
	impacts.thing_hits.append([impacts.thing_serial, blast, blast])
	marks.update(g, layer, wrecks)
	found = _marks_of(node)
	check.call(
		found.size() == 2 and int(found[1].w / 10.0) == 2, "a blast beside it scorches it too"
	)
	layer.show_props([], g.level)
	check.call(not node.visible and layer.parked() == 1, "out of view it is parked, hidden")
	layer.show_props([s], g.level)
	var again: PropView = layer.shown()[0]
	check.call(
		again == node and again.visible and _marks_of(again).size() == 2,
		"back in view: the same model, its marks on it"
	)
	layer.park_most = 0
	layer.show_props([], g.level)
	layer.park_most = PropLayer3D.PARK
	layer.show_props([s], g.level)
	again = layer.shown()[0]
	check.call(
		again != node and _marks_of(again).size() == 2, "let go of and made again: its marks kept"
	)
	var moved := View.Sprite.new(at.x + .4, at.y, "town_" + name, 1.0, 0.0)
	layer.show_props([moved], g.level)
	var next: PropView = layer.shown()[0]
	check.call(_marks_of(next).size() == 2, "and move on with it stood again nearby")
	var fire: FireFeature = g.features.get("fire")
	if fire != null:
		fire.charred[g.level.cell(moved.x, moved.y)] = 0.0
		g.clock += 1.0
		marks.update(g, layer, wrecks)
		var burnt: float = _marked_part(next).get_meta("char", 0.0)
		check.call(burnt > .5, "a burnt-out cell chars what stands in it (%.2f)" % burnt)
		fire.charred.clear()
	g.bullet_marks = false
	var before := impacts.thing_serial
	impacts.call("_thing_hit", Vector3.ZERO, Vector3.ONE)
	check.call(impacts.thing_serial == before, "BULLET MARKS off: no marks on props")
	g.bullet_marks = true
	layer.queue_free()
	wrecks.queue_free()


static func _marks_of(node: PropView) -> PackedVector4Array:
	var all := PackedVector4Array()
	for mesh: MeshInstance3D in node.meshes():
		var marks: PackedVector4Array = mesh.get_meta("marks", PackedVector4Array())
		all.append_array(marks)
	return all


static func _marked_part(node: PropView) -> MeshInstance3D:
	for mesh: MeshInstance3D in node.meshes():
		if mesh.has_meta("marks") or mesh.has_meta("char"):
			return mesh
	return node.meshes()[0]


## The storm front's wall round a County Run's ring.
static func _storm(main, check: Callable) -> void:
	main.start_county("county_hickston")
	var g: Game = main.game
	for i in 3:
		g.tick(1.0 / 60.0, Game.Controls.new())
	var f = g.features["county"]
	f.storm_warned = true
	var view := WorldView3D.new(g.art)
	main.add_child(view)
	var lights_were := Effects.enabled
	Effects.enabled = true
	view.call("_storm", g, Vector3(f.storm_at.x, f.storm_at.y, 1.0))
	var walls: Array = view.get("_storm_walls")
	var ring: Vector4 = view.shared("storm_ring")
	check.call(
		walls[0].visible and walls[1].visible and absf(ring.z - f.storm_r) < .01 and ring.w > 0.0,
		"the storm's two curtains stand round its ring, the ring handed to the shaders"
	)
	Effects.enabled = false
	view.call("_storm", g, Vector3(f.storm_at.x, f.storm_at.y, 1.0))
	check.call(walls[0].visible and not walls[1].visible, "LIGHTS AND GLOW off: the front alone")
	f.storm_on = false
	view.call("_storm", g, Vector3(f.storm_at.x, f.storm_at.y, 1.0))
	ring = view.shared("storm_ring")
	check.call(not walls[0].visible and ring == Vector4.ZERO, "no storm: no wall, no ring")
	Effects.enabled = lights_were
	view.queue_free()
