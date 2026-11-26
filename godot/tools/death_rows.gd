## death_frames.gd's `audit`: rows of deaths, each a kind shot by a gun where
## it struck (head, body, arms, legs) standing somewhere (open ground, by a
## wall, on stairs, a ramp, a deck, a loft by its rail), pictured side on from
## a still camera at ten moments, every tick drawn (<row>.png in out=: two
## lines of five, 320x200 each, the first the moment before the shot).
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/death_frames.gd -- out=<dir> audit [rows=billy,wall]
extends RefCounted

## Ticks after the shot each picture is taken at (0: the tick before it).
const TICKS := [0, 2, 5, 9, 14, 20, 30, 45, 75, 140]
## [name, kind, gun (hurt()'s how), zone, place, how far the shot came from,
## turn of the shot about the body (radians, 0 its face)].
const ROWS := [
	["billy_pistol", "billy", "revolver", "body", "flat", 3.0, 0.0],
	["billy_pistol_slowmo", "billy", "revolver", "body", "flat", 3.0, 0.0],
	["billy_pistol_b", "billy", "revolver", "body", "flat", 3.0, 0.9],
	["billy_shotgun_far", "billy", "shotgun", "body", "flat", 4.5, 0.0],
	["billy_shotgun_near", "billy", "shotgun", "body", "flat", 1.3, 0.0],
	["billy_rifle", "billy", "rifle", "body", "flat", 6.0, 0.0],
	["billy_head", "billy", "revolver", "head", "flat", 3.0, 0.0],
	["billy_legs", "billy", "revolver", "legs", "flat", 3.0, 0.0],
	["billy_arms", "billy", "revolver", "arms", "flat", 3.0, 0.0],
	["billy_blast", "billy", "blast", "body", "flat", 2.0, 0.0],
	["billy_wall", "billy", "shotgun", "body", "wall", 1.3, 0.0],
	["billy_stairs", "billy", "shotgun", "body", "stairs", 1.5, 0.0],
	["billy_rail", "billy", "shotgun", "body", "rail", 1.4, 0.0],
	["billy_ramp", "billy", "revolver", "body", "ramp", 3.0, 0.0],
	["billy_deck", "billy", "shotgun", "body", "deck", 2.0, 0.0],
	["coot_shotgun_near", "coot", "shotgun", "body", "flat", 1.3, 0.0],
	["coot_head", "coot", "rifle", "head", "flat", 5.0, 0.0],
	["yard_deputy_pistol", "yard_deputy", "revolver", "body", "flat", 3.0, 0.0],
	["flagman_rifle", "flagman", "rifle", "body", "flat", 5.0, 0.0],
	["chain_hand_shotgun", "chain_hand", "shotgun", "body", "flat", 3.2, 0.0],
	["noodler_blast", "noodler", "blast", "body", "flat", 2.0, 0.0],
	["pit_mechanic_legs", "pit_mechanic", "shotgun", "legs", "flat", 3.0, 0.0],
	["tough_bubba_shotgun", "tough_bubba", "shotgun", "body", "flat", 1.5, 0.0],
	["revenue_man_head", "revenue_man", "revolver", "head", "flat", 3.0, 0.0],
	["big_billy_shotgun", "big_billy", "shotgun", "body", "flat", 3.2, 0.0],
	["big_billy_head", "big_billy", "revolver", "head", "flat", 3.0, 0.5],
	["millhand_shotgun", "millhand", "shotgun", "body", "flat", 3.2, 0.0],
	["millhand_pistol", "millhand", "revolver", "body", "flat", 3.0, -0.6],
	["tin_guard_shotgun", "tin_guard", "shotgun", "body", "flat", 3.2, 0.0],
	["tin_guard_rifle", "tin_guard", "rifle", "head", "flat", 5.0, 0.7],
	["shield_deputy_pistol", "shield_deputy", "revolver", "body", "flat", 3.0, 0.0],
	["gator_shotgun", "gator", "shotgun", "body", "flat", 3.2, 0.0],
	["crawler_shotgun", "crawler", "shotgun", "body", "flat", 3.2, 0.0],
	# Pass 13: the beasts (gators, crawlers, the cow, the herd's hogs) by
	# pistol, buckshot near, rifle, a head shot and a blast, on flat ground, a
	# ramp, a water's edge and in the water.
	["gator_pistol", "gator", "revolver", "body", "flat", 3.0, 0.0],
	["gator_pistol_b", "gator", "revolver", "body", "flat", 3.0, 1.4],
	["gator_shotgun_near", "gator", "shotgun", "body", "flat", 1.3, 0.0],
	["gator_rifle", "gator", "rifle", "body", "flat", 6.0, 0.0],
	["gator_head", "gator", "revolver", "head", "flat", 3.0, 0.0],
	["gator_blast", "gator", "blast", "body", "flat", 2.0, 0.0],
	["gator_slope", "gator", "shotgun", "body", "ramp", 2.0, 0.0],
	["gator_bank", "gator", "shotgun", "body", "bank", 1.8, 0.0],
	["gator_water", "gator", "revolver", "body", "water", 3.0, 0.0],
	["crawler_pistol", "crawler", "revolver", "body", "flat", 3.0, 0.0],
	["crawler_pistol_b", "crawler", "revolver", "body", "flat", 3.0, 1.2],
	["crawler_shotgun_near", "crawler", "shotgun", "body", "flat", 1.3, 0.0],
	["crawler_rifle", "crawler", "rifle", "body", "flat", 6.0, 0.0],
	["crawler_head", "crawler", "revolver", "head", "flat", 3.0, 0.0],
	["crawler_blast", "crawler", "blast", "body", "flat", 2.0, 0.0],
	["crawler_slope", "crawler", "shotgun", "body", "ramp", 2.0, 0.6],
	["crawler_ramp", "crawler", "revolver", "body", "ramp", 3.0, 0.0],
	["cow_pistol", "cow", "revolver", "body", "flat", 3.0, 1.57],
	["cow_shotgun_near", "cow", "shotgun", "body", "flat", 1.6, 1.57],
	["cow_rifle", "cow", "rifle", "head", "flat", 6.0, 1.2],
	["cow_blast", "cow", "blast", "body", "flat", 2.0, 0.0],
	["cow_slope", "cow", "shotgun", "body", "ramp", 2.4, 1.57],
	["hog_blast", "hog", "blast", "body", "herd", 0.0, 0.0],
	["hog_blast_b", "hog", "blast", "body", "herd", 0.0, 1.0],
]
## Each zone's height on the body (shares of its height) and how far off its
## middle across the shot (shares of its radius).
const ZONES := {"head": [.93, 0.0], "body": [.6, 0.0], "arms": [.62, 1.0], "legs": [.24, .3]}

## A killing hit's usual damage by gun.
const DAMAGE := {"shotgun": 70.0, "revolver": 30.0, "rifle": 45.0, "blast": 29.0}

var tool: SceneTree
var _frames: Array[Image] = []
var _way := Vector2.ZERO
var _name := ""
var _body: Enemy
var _look := Vector2.INF
var _look_z := NAN


func _init(owner: SceneTree) -> void:
	tool = owner


func run(row: Array) -> void:
	var name: String = row[0]
	_name = name
	var kind: String = row[1]
	var how: String = row[2]
	var zone: String = row[3]
	var place: String = row[4]
	var far: float = row[5]
	var turn: float = row[6]
	if place == "herd":
		await _herd(name, turn)
		return
	var spot := _place(place)
	if spot.is_empty():
		print("  %s: no %s to stand on" % [name, place])
		return
	var g: Game = tool.call("_level", spot["level"], [])
	g.spawn_grace = 99.0
	g.weapon_view = 2
	# At the game's own pace (a finisher's slow motion has a row of its own).
	g.finish_slowmo = name.ends_with("_slowmo")
	var at: Vector2 = spot["at"]
	var top: float = spot["top"]
	# The shot comes along `way` (from the shooter to the body).
	var way: Vector2 = spot["way"]
	var e := Enemy.new(kind, at.x, at.y, atan2(-way.y, -way.x) + turn)
	e.floor_z = top
	g.enemies.append(e)
	e.alerted = false
	var shooter := at - way * far
	# Small bodies (a gator, a crawler) are watched from nearer.
	var near := clampf(maxf(e.height * e.variant / 1.2, e.radius * 2.2), .55, 1.0)
	var cam := _camera(g, at, way, top, near)
	_way = way
	_body = e
	_look = Vector2.INF
	_look_z = NAN
	_frames.clear()
	for _k in 8:
		await _ticks(g, 1, cam, at, top)
		e.x = at.x
		e.y = at.y
	await _snap()
	# The shot: the player where it came from, the hit where the zone is.
	var p := g.player
	var keep := Vector2(p.x, p.y)
	p.x = shooter.x
	p.y = shooter.y
	var z: Array = ZONES[zone]
	var feet: float = g.world.stand(e) + e.z
	var across := Vector2(-way.y, way.x)
	var hit := at - way * e.radius * .8 + across * e.radius * float(z[1])
	g.hit_point = Vector3(hit.x, hit.y, feet + e.height * e.variant * float(z[0]))
	g.hit_from = shooter
	# A killing hit of the gun's usual weight that leaves the body whole (an
	# overkill takes it apart: HitZones.overkill, blast_gibs).
	var amount: float = DAMAGE.get(how, 30.0)
	amount = minf(amount, maxf(48.0, e.max_hp * .7) - 1.0)
	e.hp = minf(e.hp, amount * .5)
	if how == "blast":
		var mid := at - way * .7
		g.hit_point = Vector3(mid.x, mid.y, feet)
		g.blast_kind = "tnt"
		e.hurt(minf(amount, maxf(30.0, e.max_hp * .45) - 1.0), g, true, false, null, "blast")
	else:
		e.hurt(amount, g, false, false, null, how)
		if e.alive:
			# A shield took it (the tin guard's, the shield deputy's door): the
			# body's own hp gone, struck again past it.
			e.hp = .1
			e.angle = atan2(way.y, way.x)
			g.hit_point = Vector3(hit.x, hit.y, feet + e.height * e.variant * float(z[0]))
			e.hurt(amount, g, false, false, null, how)
	p.x = keep.x
	p.y = keep.y
	print("  %s: %s zone %s, killed by %s" % [name, kind, e.last_zone, e.killed_by])
	var done := 0
	for t: int in TICKS.slice(1):
		await _ticks(g, t - done, cam, at, top)
		done = t
		if OS.get_environment("ROW_DEBUG") != "":
			print("    t%d body %.2f %.2f toss %.2f" % [t, e.x, e.y, e.toss])
		await _snap()
	_save(name)


## Where to stand for `place`: {level, at, top, way}.
func _place(place: String) -> Dictionary:
	match place:
		"stairs":
			return {
				"level": "feedstore", "at": Vector2(10.9, 4.6), "top": 1.7, "way": Vector2(-1, 0)
			}
		"rail":
			return {
				"level": "hickston", "at": Vector2(44.0, 8.6), "top": 1.55, "way": Vector2(0, 1)
			}
		"flat":
			return _open("hickston", false)
		"wall":
			return _open("hickston", true)
		"bank", "water":
			return _wet("bayou", place == "water")
		"ramp", "deck":
			for id: String in ["hickston", "quarry", "sawmill", "feedstore"]:
				var found := _slab(id, place)
				if not found.is_empty():
					return found
	return {}


## Open ground on level `id` (nothing near for 3.5 cells; `wall`: a wall a
## cell ahead along the way, open behind).
func _open(id: String, wall: bool) -> Dictionary:
	var g: Game = tool.call("_level", id, [])
	var w := g.world
	var start := Vector2(g.player.x, g.player.y)
	var best := {}
	var best_d := INF
	for y in range(3, w.height - 3):
		for x in range(3, w.width - 3):
			var at := Vector2(x + .5, y + .5)
			var d := at.distance_to(start)
			if d > best_d:
				continue
			var z := w.elevation(at.x, at.y)
			for k in 4 if wall else 1:
				var way := Vector2.from_angle(k * PI * .5)
				if _clear_round(w, at, z, way, wall):
					best = {"level": id, "at": at, "top": z, "way": way}
					best_d = d
					break
	return best


func _clear_round(w: LevelData, at: Vector2, z: float, way: Vector2, wall: bool) -> bool:
	for k in 16:
		var dir := Vector2.from_angle(k * TAU / 16.0)
		var ahead := dir.dot(way) > .9
		for r: float in [.5, 1.0, 1.6, 2.4, 3.4]:
			if wall and ahead and r > 1.0:
				break
			var q := at + dir * r
			if q.x < 1 or q.y < 1 or q.x > w.width - 1 or q.y > w.height - 1:
				return false
			if w.blocked(q.x, q.y, .2, z + .4) or absf(w.elevation(q.x, q.y) - z) > .03:
				return false
	if not wall:
		return PhysCore.plain_rect(
			w, int(at.x - 3.5), int(at.y - 3.5), int(at.x + 3.5), int(at.y + 3.5)
		)
	var q := at + way * 1.35
	return w.blocked(q.x, q.y, .1, z + .6)


## A slab to stand on: a ramp (shot down its slope) or a deck.
func _slab(id: String, what: String) -> Dictionary:
	var g: Game = tool.call("_level", id, [])
	var w := g.world
	for s: LevelGeometry.Slab in w.geo.slabs:
		if not s.walk:
			continue
		if (
			(what == "ramp") != s.sloped()
			or (what == "deck" and (s.kind == "stair" or s.thick <= 0.0))
		):
			continue
		var mid := Vector2((s.x0 + s.x1) * .5, (s.y0 + s.y1) * .5)
		if not s.inside(mid.x, mid.y) or minf(s.x1 - s.x0, s.y1 - s.y0) < 2.0:
			continue
		var top := s.top_at(mid.x, mid.y)
		if w.blocked(mid.x, mid.y, .4, top + .4):
			continue
		var way := Vector2(-s.gx, -s.gy)
		if way.length() < .01:
			way = Vector2(1, 0)
		return {"level": id, "at": mid, "top": top, "way": way.normalized()}
	return {}


## Where the camera stands: side on to the shot, 3.2 off, on open floor that
## sees the body (else behind the shooter's shoulder).
func _camera(g: Game, at: Vector2, way: Vector2, top: float, near := 1.0) -> Vector3:
	var w := g.world
	# (ROW_SIDE=other: watched from the other side, the Meshy track's look at
	# the far arm.)
	var across := (
		Vector2(-way.y, way.x) * (-1.0 if OS.get_environment("ROW_SIDE") == "other" else 1.0)
	)
	for c: Vector2 in [
		at + (across * 4.0 + way * .8) * near,
		at - (across * 4.0 - way * .8) * near,
		at + (across * 2.4 - way * 1.6) * near,
		at - (across * 2.4 + way * 1.6) * near,
		at - (way * 3.4 - across * .8) * near,
	]:
		if c.x < 1 or c.y < 1 or c.x > w.width - 1 or c.y > w.height - 1:
			continue
		var z := w.floor_under(c.x, c.y, top + .6)
		if w.blocked(c.x, c.y, .2, z + .4):
			continue
		if w.visible(c.x, c.y, at.x, at.y, z + .95, top + .5):
			return Vector3(c.x, c.y, z)
	var c := at + across * 3.2
	return Vector3(c.x, c.y, top)


func _ticks(g: Game, n: int, cam: Vector3, at: Vector2, top: float) -> void:
	var held := Game.Controls.new()
	for i in n:
		var body := Vector2(_body.x, _body.y) if _body != null else at
		_look = body if _look == Vector2.INF else _look.lerp(body, .2)
		# (Looked at a little under its top: a gator's back, a man's chest.)
		var high := .6 if _body == null else clampf(_body.height * _body.variant * .6, .2, .6)
		var lz := top + high
		if _body != null:
			var bz: float = (
				g.world.floor_under(_body.x, _body.y, g.world.stand(_body) + .3) + _body.toss
			)
			_look_z = bz + high if is_nan(_look_z) else lerpf(_look_z, bz + high, .2)
			lz = _look_z
		var look := _look
		g.tick(1.0 / 60.0, held)
		tool.call("_stand", g, cam.x, cam.y, look.x, look.y, lz)
		tool.call("_lift", g, cam.z, look.x, look.y, lz)
		g.player.floor_z = cam.z
		g.message_until = 0.0
		g.barks.until = 0.0
		(tool.get("main") as Node).call("render")
		if OS.get_environment("ROW_DEBUG") != "" and _body != null and not _body.alive:
			_probe(g)
	await RenderingServer.frame_post_draw


func _snap() -> void:
	(tool.get("main") as Node).call("render")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = tool.root.get_texture().get_image()
	if OS.get_environment("ROW_FULL") != "":
		img.save_png(String(tool.get("out")).path_join("full_%s_%d.png" % [_name, _frames.size()]))
	var w := img.get_width()
	var h := img.get_height()
	# The middle of the view, where the body is.
	# Half the view across, its upper middle (above the status bar): every
	# one of the game's own pixels kept.
	var cw := w / 2
	var ch := int(cw * .625)
	var part := img.get_region(Rect2i((w - cw) / 2, int(h * .12), cw, ch))
	part.resize(320, 200, Image.INTERPOLATE_NEAREST)
	_frames.append(part)


func _save(name: String) -> void:
	var sheet := Image.create(320 * 5, 200 * 2 + 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(.1, .1, .1))
	for k in _frames.size():
		var f := _frames[k]
		f.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(f, Rect2i(0, 0, 320, 200), Vector2i((k % 5) * 320, (k / 5) * 202))
	sheet.save_png(String(tool.get("out")).path_join(name + ".png"))


## The body's ragdoll this tick (ROW_DEBUG).
func _probe(g: Game) -> void:
	var layers := tool.root.find_children("*", "ActorLayer3D", true, false)
	if layers.is_empty():
		return
	var shown: Dictionary = layers[0].get("_shown")
	var view: ActorView = shown.get(_body.get_instance_id())
	if view == null or view.doll == null:
		print("    %.3f no doll" % (g.clock - _body.died_at))
		return
	var d := view.doll
	var sk: Skeleton3D = view.find_children("*", "Skeleton3D", true, false)[0]
	var rig: RagdollRig = view.get("_rig")
	var bone := rig.anchors[0]
	var g3 := sk.global_transform * sk.get_bone_global_pose(bone)
	var hp := (d.pos[0] + d.pos[1]) * .5
	var up := ((d.pos[2] + d.pos[3]) * .5 - hp).normalized()
	var th := (d.pos[9] - d.pos[0]).normalized()
	print(
		(
			"    age %.2f up %.2f hipz %.2f elb %.2f %.2f hand %.2f %.2f sh %.2f %.2f awake %s"
			% [
				d.age,
				up.z,
				hp.z,
				d.pos[5].z,
				d.pos[7].z,
				d.pos[6].z,
				d.pos[8].z,
				d.pos[2].z,
				d.pos[3].z,
				d.awake
			]
		)
	)
	var head := d.pos[RagdollRig.HEAD]
	var hips := (d.pos[0] + d.pos[1]) * .5
	print(
		(
			"    %.3f steps %d awake %s head %.2f %.2f %.2f hips %.2f %.2f %.2f body %.2f %.2f"
			% [
				g.clock - _body.died_at,
				d.steps,
				d.awake,
				head.x,
				head.y,
				head.z,
				hips.x,
				hips.y,
				hips.z,
				_body.x,
				_body.y
			]
		)
	)


## Gator Bayou's water: a body on the bank with the water a cell behind it
## (shot toward it), or one out in the water.
func _wet(id: String, in_water: bool) -> Dictionary:
	var g: Game = tool.call("_level", id, [])
	var w := g.world
	var start := Vector2(g.player.x, g.player.y)
	var best := {}
	var best_d := INF
	for y in range(3, w.height - 3):
		for x in range(3, w.width - 3):
			var at := Vector2(x + .5, y + .5)
			var d := at.distance_to(start)
			if d > best_d or BayouBrains.wet_at(w, at.x, at.y) != in_water:
				continue
			var z := w.elevation(at.x, at.y)
			if w.blocked(at.x, at.y, .35, z + .4):
				continue
			for k in 4:
				var way := Vector2.from_angle(k * PI * .5)
				var behind := at + way * 1.1
				var front := at - way * 2.0
				if w.blocked(front.x, front.y, .3, z + .4) or w.blocked(behind.x, behind.y, .3):
					continue
				var ok := (
					(
						BayouBrains.wet_at(w, behind.x, behind.y)
						and BayouBrains.wet_at(w, behind.x + way.x, behind.y + way.y)
					)
					if not in_water
					else (
						BayouBrains.wet_at(w, behind.x, behind.y)
						and BayouBrains.wet_at(w, front.x, front.y)
					)
				)
				if ok:
					best = {"level": id, "at": at, "top": z, "way": way}
					best_d = d
					break
	return best


## The herd's hogs (event_herd.gd): a stampede let go on Hickston, watched
## side on halfway down its run, and a blast set off by the lead hog (`turn`
## the blast's way round it).
func _herd(name: String, turn: float) -> void:
	var main: Node = tool.get("main")
	var opts: Dictionary = main.get("options")
	opts["events"] = 2
	var g: Game = tool.call("_level", "hickston", [])
	opts.erase("events")
	g.spawn_grace = 99.0
	g.weapon_view = 2
	g.finish_slowmo = false
	for _k in 4:
		g.tick(1.0 / 60.0, Game.Controls.new())
	var ev: CountyEvents = g.features.get("events")
	if ev == null or not ev.begin("hogs"):
		print("  %s: no stampede" % name)
		return
	var mid := ev.herd_from + ev.herd_way * minf(ev.herd_len * .5, 10.0)
	var top := g.world.elevation(mid.x, mid.y)
	var cam := _camera(g, mid, ev.herd_way, top, 1.1)
	_frames.clear()
	_body = null
	_look = Vector2.INF
	# The last of them, the rest gone by.
	var lead: Array = ev.herd[ev.herd.size() - 1]
	for _t in 60 * 10:
		var at := Vector2(EventHerd.f(lead, 0), EventHerd.f(lead, 1))
		if (at - ev.herd_from).dot(ev.herd_way) > minf(ev.herd_len * .5, 10.0) - .6:
			break
		await _ticks(g, 1, cam, mid, top)
	await _snap()
	var hog := Vector2(EventHerd.f(lead, 0), EventHerd.f(lead, 1))
	var way := Vector2.from_angle(EventHerd.f(lead, 2) + PI * .5 + turn)
	var blast := hog - way * .8
	g.events.exploded.emit(blast.x, blast.y, 0.5, false)
	print("  %s: hog down %s" % [name, lead[EventHerd.STATE] == EventHerd.DOWN])
	var done := 0
	for t: int in TICKS.slice(1):
		await _ticks(g, t - done, cam, hog, top)
		done = t
		await _snap()
	_save(name)
