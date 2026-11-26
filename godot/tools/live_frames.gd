## Motion strips of living hands taking hits (pass 15, the active bodies:
## src/live_body.gd on play's stagger, src/stagger.gd), in a real window:
## each row a hand on open ground watched side on from a still camera, hit
## (and hit again, or hit on the run) and pictured at fifteen moments, every
## tick drawn (<row>.png in out=: three lines of five, 320x200 each, the
## first the moment before the first hit). Read them: the body should lag,
## catch itself with real steps, hold the wound, buckle a knee.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/live_frames.gd -- out=<dir> [rows=chest,legs] [off] [kind=coot]
##
## off: the active bodies off (RAGDOLLS off: the old rigid flinch) for a
## side by side. Point APPDATA at a scratch folder.
extends "res://tools/death_frames.gd"

const Rows := preload("res://tools/death_rows.gd")
## Ticks after the first hit each picture is taken at (0: the tick before).
const AT := [0, 2, 4, 7, 10, 14, 19, 25, 32, 40, 50, 62, 76, 95, 125]
## [name, kind, [[tick, gun, zone, how far the shot came from, damage], ...],
## running at the shooter first].
const LIVE_ROWS := [
	["chest", "billy", [[0, "revolver", "body", 3.0, 22.0]], false],
	["legs", "billy", [[0, "revolver", "legs", 3.0, 22.0]], false],
	["head", "billy", [[0, "revolver", "head", 3.0, 18.0]], false],
	["arm", "billy", [[0, "revolver", "arms", 3.0, 22.0]], false],
	["running", "billy", [[0, "revolver", "body", 2.5, 22.0]], true],
	[
		"stacked",
		"billy",
		[[0, "revolver", "body", 3.0, 20.0], [16, "revolver", "body", 3.0, 20.0]],
		false
	],
	["buckshot", "billy", [[0, "shotgun", "body", 3.0, 40.0]], false],
	# Knocked down: both barrels close, then once more (the Meshy models track).
	[
		"knock",
		"billy",
		[[0, "shotgun", "body", 1.1, 90.0], [8, "shotgun", "body", 1.1, 90.0]],
		false
	],
	["coot_chest", "coot", [[0, "revolver", "body", 3.0, 18.0]], false],
	["coot_legs", "coot", [[0, "revolver", "legs", 4.0, 14.0]], false],
	["coot_down", "coot", [[0, "shotgun", "body", 1.2, 90.0]], false],
	["coot_running", "coot", [[0, "revolver", "body", 2.5, 18.0]], true],
	[
		"coot_stacked",
		"coot",
		[[0, "revolver", "body", 3.0, 16.0], [16, "revolver", "body", 3.0, 16.0]],
		false
	],
]
const HEIGHT := {"head": .93, "body": .6, "arms": .62, "legs": .3}
const ACROSS := {"head": 0.0, "body": .25, "arms": 1.0, "legs": .35}

var _rows: Rows
## kind=: every row with that kind instead (the Meshy models track).
var _kind := ""
var _video := false
## probe: after every picture, how deep the body's held things (the Meshy
## models' guns) are inside it (tools/meshy/gear_probe.gd); the row's worst.
var _probe_on := false
var _probe_worst := 0.0
var _probe_at := -1
var _piece_worst := 0.0
var _probe_key := ""
var _piece_said := ""
var _at: Array = AT.duplicate()


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("rows="):
			only = a.substr(5)
		elif a == "off":
			classic = true
		elif a.begins_with("kind="):
			_kind = a.substr(5)
		elif a == "probe":
			_probe_on = true
		elif a == "video":
			# Every other tick for two and a half seconds, each frame its own
			# picture (<row>/f_NNN.png), for a clip at real speed (30 a second).
			_video = true
			_at = [0]
			for k in range(2, 152, 2):
				_at.append(k)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	_rows = Rows.new(self)
	var wanted := Array(only.split(",", false))
	for row: Array in LIVE_ROWS:
		var name: String = row[0]
		if wanted.is_empty() or wanted.has(name):
			await _row(row)
	print("live frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _row(row: Array) -> void:
	var name: String = row[0]
	var kind: String = row[1] if _kind == "" else _kind
	var shots: Array = row[2]
	var running: bool = row[3]
	var spot: Dictionary = _rows._open("hickston", false)
	var g: Game = _level(spot["level"], [])
	g.spawn_grace = 99.0
	g.weapon_view = 2
	g.finish_slowmo = false
	var at: Vector2 = spot["at"]
	var top: float = spot["top"]
	var way: Vector2 = spot["way"]
	var first: Array = shots[0]
	var far: float = first[3]
	var start := at - way * (1.6 if running else 0.0)
	var e := Enemy.new(kind, start.x, start.y, atan2(-way.y, -way.x))
	e.floor_z = top
	e.hp = 400.0
	e.max_hp = 400.0
	g.enemies.append(e)
	e.alerted = running
	var shooter := at - way * far
	var cam: Vector3 = _rows._camera(g, at, way, top, 1.0)
	_rows._name = name
	_rows._body = e
	_rows._look = at
	_rows._look_z = NAN
	_rows._frames.clear()
	var p := g.player
	if running:
		p.x = shooter.x - way.x * 6.0
		p.y = shooter.y - way.y * 6.0
	for _k in 30 if running else 8:
		if running:
			# Coming on at a run toward where the shot comes from.
			e.alerted = true
			e.angle = atan2(-way.y, -way.x)
			e.advance(1.0 / 60.0, g, e.angle, 1.4)
			e.pose += 1.0 / 60.0
		else:
			e.x = at.x
			e.y = at.y
		await _rows._ticks(g, 1, cam, at, top)
	await _rows._snap()
	_probe(kind)
	var done := 0
	var next := 0
	for t: int in _at.slice(1):
		while next < shots.size():
			var shot: Array = shots[next]
			var when: int = shot[0]
			if when > done:
				break
			_hit(g, e, shot, way)
			next += 1
		while done < t:
			var step := t - done
			for k in range(next, shots.size()):
				var shot: Array = shots[k]
				var when: int = shot[0]
				step = mini(step, when - done)
			step = maxi(1, step)
			await _rows._ticks(g, step, cam, at, top)
			done += step
			while next < shots.size():
				var shot: Array = shots[next]
				var when: int = shot[0]
				if when > done:
					break
				_hit(g, e, shot, way)
				next += 1
		await _rows._snap()
		_probe(kind)
	_save15(name)
	if _probe_on:
		print(
			(
				"GEAR PROBE %s %s: worst %.3f m at picture %d (%s)"
				% [name, kind, _probe_worst, _probe_at, _probe_key]
			)
		)
		print("BODY PROBE %s %s: worst %.2f %s" % [name, kind, _piece_worst, _piece_said])
		_probe_worst = 0.0
		_probe_at = -1
		_piece_worst = 0.0
		_piece_said = ""


func _probe(kind: String) -> void:
	if not _probe_on:
		return
	var probe: GDScript = load("res://tools/meshy/gear_probe.gd")
	for n in root.find_children("*", "Node3D", true, false):
		if n is ActorView and (n as ActorView).kind == kind and (n as Node3D).is_visible_in_tree():
			var view := n as ActorView
			var info: Dictionary = view.models.kinds.get(kind, {})
			var d: float = probe.depth(view, info.get("labels", {}))
			if d > _probe_worst:
				_probe_worst = d
				_probe_at = _rows._frames.size() - 1
				_probe_key = (
					"key %.2f live %s blend %s"
					% [
						float(view.get("_seeked")) / ActorModels.KEY_TIME,
						str(view.live != null),
						str(float(view.get("_blend_at")) >= 0.0)
					]
				)
			var rig: RagdollRig = RagdollRig.of(kind, view, info)
			var bad: Array = probe.pieces(view, rig)
			var badness: float = bad[0]
			if badness > _piece_worst:
				_piece_worst = badness
				_piece_said = "%s at picture %d" % [bad[1], _rows._frames.size() - 1]


## One hit on `e` from the shooter along `way`: the player put there a moment
## (the hit's point where the zone is), then back.
func _hit(g: Game, e: Enemy, shot: Array, way: Vector2) -> void:
	var how: String = shot[1]
	var zone: String = shot[2]
	var far: float = shot[3]
	var amount: float = shot[4]
	var p := g.player
	var keep := Vector2(p.x, p.y)
	var from := Vector2(e.x, e.y) - way * far
	p.x = from.x
	p.y = from.y
	var feet: float = g.world.stand(e) + e.z
	var across := Vector2(-way.y, way.x)
	var spot := Vector2(e.x, e.y) - way * e.radius * .8 + across * e.radius * float(ACROSS[zone])
	g.hit_point = Vector3(spot.x, spot.y, feet + e.height * e.variant * float(HEIGHT[zone]))
	g.hit_from = from
	var pellets := 8 if how == "shotgun" else 1
	for k in pellets:
		g.hit_point = Vector3(spot.x, spot.y, feet + e.height * e.variant * float(HEIGHT[zone]))
		e.hurt(amount / pellets, g, false, false, null, how)
	e.hp = maxf(e.hp, 300.0)
	p.x = keep.x
	p.y = keep.y
	print("  hit %s %s zone %s" % [how, zone, e.last_zone])


func _save15(name: String) -> void:
	if _video:
		DirAccess.make_dir_recursive_absolute(out.path_join(name))
		for k in _rows._frames.size():
			_rows._frames[k].save_png(out.path_join(name).path_join("f_%03d.png" % k))
		return
	var sheet := Image.create(320 * 5, 202 * 3, false, Image.FORMAT_RGB8)
	sheet.fill(Color(.1, .1, .1))
	for k in _rows._frames.size():
		var f: Image = _rows._frames[k]
		f.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(f, Rect2i(0, 0, 320, 200), Vector2i((k % 5) * 320, (k / 5) * 202))
	sheet.save_png(out.path_join(name + ".png"))
