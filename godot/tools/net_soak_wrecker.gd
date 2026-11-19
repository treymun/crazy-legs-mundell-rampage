## net_soak_all.gd's director: destruction on purpose, the same on every
## machine: hooked to a game's `ticked` (inside the tick, after the features), it acts only on the
## game's own clock and carried state, so the server and every copy that
## plays the tick do the same. Each `every` seconds an event: a chain of
## blasts nobody threw (`beats`, GAP apart) at the next thing on its list.
extends RefCounted

const GAP := .075
const KINDS := ["breakables", "set_pieces", "hands", "vehicles", "fences"]
var game: Game
var every := 4.0
var fired := 0
var busy := false


func _init(g: Game, each: float) -> void:
	game = g
	every = each
	g.events.ticked.connect(_ticked)


func _ticked(dt: float) -> void:
	if dt <= 0.0:
		return
	var c := game.clock
	var k := floori(c / every)
	if k <= 0:
		return
	var j := floori((c - k * every) / GAP)
	var t := k * every + j * GAP
	if not (c - dt < t and t <= c):
		return
	var spots := _spots(k)
	if j >= spots.size():
		return
	var at: Vector2 = spots[j]
	var shot := Game.Shot.new(at.x, at.y, .4, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0)
	shot.owner = -1
	game.explode(shot)
	fired += 1
	busy = true


## Where event k's blasts go (worked out afresh at each beat from the
## game as it stands: the same on every machine): the first kind on the
## list from k's that has something left to break.
func _spots(k: int) -> Array:
	for n in KINDS.size():
		var kind: String = KINDS[(k + n) % KINDS.size()]
		var out: Array = call("_" + kind, k)
		if not out.is_empty():
			return out
	# Nothing left: among the players (versus) or where they stand.
	var p: Player = game.players[k % game.players.size()]
	return [Vector2(p.x + 1.5, p.y), Vector2(p.x - 1.5, p.y + 1.0)]


func _breakables(k: int) -> Array:
	var f = game.features.get("breakables")
	if f == null:
		return []
	var standing: Array = []
	for i in f.pieces.size():
		if not f.pieces[i].broken:
			standing.append(i)
	if standing.is_empty():
		return []
	var first: int = standing[k * 7 % standing.size()]
	var p0 = f.pieces[first]
	var near: Array = standing.duplicate()
	near.sort_custom(
		func(a: int, b: int) -> bool:
			var da: float = Vector2(f.pieces[a].x - p0.x, f.pieces[a].y - p0.y).length()
			var db: float = Vector2(f.pieces[b].x - p0.x, f.pieces[b].y - p0.y).length()
			return da < db or (da == db and a < b)
	)
	var out: Array = []
	for i: int in near.slice(0, 4):
		out.append(Vector2(f.pieces[i].x + .6, f.pieces[i].y + .3))
	return out


func _set_pieces(k: int) -> Array:
	var f = game.features.get("set_pieces")
	if f == null or f.pieces.is_empty():
		return []
	for n in f.pieces.size():
		var i: int = (k + n) % f.pieces.size()
		var st: Dictionary = f.pieces[i]
		if int(st["stage"]) != SetPiecesFeature.STANDING:
			continue
		var spec: Dictionary = f.spec_of(i)
		var x: float = spec.get("x", 0.0)
		var y: float = spec.get("y", 0.0)
		if str(st["kind"]) == "fuel":
			var pts: Array = spec.get("points", [])
			var out: Array = []
			for q: Variant in pts.slice(0, 3):
				if q is Array and q.size() >= 2:
					out.append(Vector2(float(q[0]), float(q[1])))
			if not out.is_empty():
				return out
		return [Vector2(x, y), Vector2(x + 1.2, y + .4), Vector2(x - 1.0, y - .6)]
	return []


func _hands(_k: int) -> Array:
	var out: Array = []
	for e: Enemy in game.enemies:
		if e.alive and e.hostile:
			out.append(Vector2(e.x + .4, e.y))
			if out.size() >= 3:
				break
	return out


func _vehicles(_k: int) -> Array:
	var f = game.features.get("vehicles")
	if f == null:
		return []
	for v in f.rides:
		if float(v.wreck) < 0.0:
			return [Vector2(v.x + 1.0, v.y), Vector2(v.x, v.y + 1.0), Vector2(v.x - 1.0, v.y)]
	return []


func _fences(k: int) -> Array:
	var f = game.features.get("wall_breaks")
	if f == null or f.fences.is_empty():
		return []
	var cells: Array = f.fences.keys()
	cells.sort()
	var whole: Array = []
	for cell: Variant in cells:
		if int(f.fences[cell].stage) < 2:
			whole.append(f.fences[cell])
	if whole.is_empty():
		return []
	var fc = whole[k * 5 % whole.size()]
	return [Vector2(fc.cell.x + .5, fc.cell.y + 1.2), Vector2(fc.cell.x + 1.5, fc.cell.y + 1.2)]
