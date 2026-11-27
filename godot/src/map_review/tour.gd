## The pictures a map check takes, worked out from the review (no guessing
## where to stand): viewpoints for main.gd's --view-tour, each with a `tag`
## naming what it shows (the object id where there is one) and `what`, a
## line for the report. In order, up to tour_most:
## - the start looking along the way;
## - each stop (station, key, exit) from tour_back cells back along the way;
## - each fight from where the way meets it, looking at the hands;
## - the two highest places to stand, looking over the map;
## - each deck from its middle, along its long side;
## - each door from a cell inside, looking in;
## - each district's middle, looking at its nearest building.
## Angles in radians (as the tour reads them), pitch as picture_views.json.
class_name MapTour
extends RefCounted

const L := preload("res://src/map_review/review_lines.gd")


static func views(r: MapReview) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lv := r.lv
	var id := r.level_id
	var ahead := Vector2(r.spawn.x + cos(lv.spawn[2]), r.spawn.y + sin(lv.spawn[2]))
	if r.steps.size() > 6:
		ahead = MapReview.centre(r.steps[6])
	_add(out, r, "%s_start" % id, r.spawn, ahead, "the start, looking along the way")
	for k in r.stops.size():
		var stop: Array = r.stops[k]
		var at: Vector3 = stop[1]
		var from := _back_from(r, k, at)
		_add(
			out,
			r,
			"%s_%s_%s" % [id, stop[2], _slug(str(stop[0]))],
			from,
			Vector2(at.x, at.y),
			"%s %s from the way in" % [stop[2], stop[0]]
		)
	var n := 0
	for fight in r.fights:
		var meet: int = fight["meet"]
		if meet < 0:
			continue
		n += 1
		var c: Vector3 = fight["centre"]
		var p := _fight_spot(r, fight)
		var here := Vector3(p.x, p.y, lv.floor_under(p.x, p.y, c.z + .05))
		var members: Array = fight["hands"]
		var count: int = members.size()
		_add(
			out,
			r,
			"%s_fight_%d" % [id, n],
			here,
			Vector2(c.x, c.y),
			"fight %d (%d hands, first %s) as the way meets it" % [n, count, _first(r, fight)]
		)
	var high := 0
	for spot in _high(r):
		high += 1
		_add(
			out,
			r,
			"%s_high_%d" % [id, high],
			spot,
			_open_way(r, Vector2(spot.x, spot.y)),
			"from one of the highest places to stand",
			-12.0
		)
	if lv.geo != null:
		# The biggest decks first, at most tour_decks of them, none narrower than a
		# cell (a kit house's sills and ledges are slabs too, pass 16).
		var decks: Array[LevelGeometry.Slab] = []
		for s: LevelGeometry.Slab in lv.geo.slabs:
			if s.thick < 0.0 or not s.walk or s.top < 1.0:
				continue
			if minf(s.x1 - s.x0, s.y1 - s.y0) < 1.0:
				continue
			decks.append(s)
		decks.sort_custom(
			func(a: LevelGeometry.Slab, b: LevelGeometry.Slab) -> bool:
				var aa := (a.x1 - a.x0) * (a.y1 - a.y0)
				var ab := (b.x1 - b.x0) * (b.y1 - b.y0)
				return aa > ab or (aa == ab and a.id < b.id)
		)
		for s: LevelGeometry.Slab in decks.slice(0, L.whole("tour_decks")):
			var mid := Vector3((s.x0 + s.x1) * .5, (s.y0 + s.y1) * .5, s.top)
			var long := Vector2(1, 0) if s.x1 - s.x0 >= s.y1 - s.y0 else Vector2(0, 1)
			var from := Vector3(mid.x - long.x, mid.y - long.y, s.top)
			_add(
				out,
				r,
				"%s_deck_%s" % [id, _slug(s.id)],
				from,
				Vector2(mid.x + long.x * 4.0, mid.y + long.y * 4.0),
				"on the deck %s" % s.id
			)
	for d: LevelData.Door in lv.doors:
		var inside := _inside_of(lv, d)
		if inside == Vector2.INF:
			continue
		var look := inside + (inside - d.center()).normalized() * 3.0
		var tag := d.id if d.id != "" else "%d_%d" % [d.x, d.y]
		_add(
			out,
			r,
			"%s_door_%s" % [id, _slug(tag)],
			Vector3(inside.x, inside.y, lv.floor_under(inside.x, inside.y, .05)),
			look,
			"inside the door %s, looking in" % tag
		)
	for a in lv.districts.size():
		var mid := _district_middle(lv, a)
		if mid == Vector2.INF:
			continue
		_add(
			out,
			r,
			"%s_place_%s" % [id, _slug(lv.districts[a])],
			Vector3(mid.x, mid.y, lv.floor_under(mid.x, mid.y, .05)),
			_open_way(r, mid),
			"the middle of %s" % lv.districts[a]
		)
	var most := L.whole("tour_most")
	if out.size() > most:
		out.resize(most)
	return out


static func _slug(text: String) -> String:
	var s := text.to_lower()
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out.strip_edges().trim_suffix("_")


static func _first(r: MapReview, fight: Dictionary) -> String:
	var members: Array = fight["hands"]
	var m: int = members[0]
	return str(r.hands[m]["id"])


static func _add(
	out: Array[Dictionary],
	r: MapReview,
	tag: String,
	at: Vector3,
	look: Vector2,
	what: String,
	pitch := 0.0
) -> void:
	for v in out:
		if v["tag"] == tag:
			return
	var angle := atan2(look.y - at.y, look.x - at.x)
	if Vector2(at.x, at.y).distance_to(look) < .01:
		angle = r.lv.spawn[2]
	(
		out
		. append(
			{
				"level": r.level_id,
				"tag": tag,
				"x": snappedf(at.x, .01),
				"y": snappedf(at.y, .01),
				"z": snappedf(at.z, .01),
				"angle": snappedf(angle, .001),
				"pitch": pitch,
				"what": what,
			}
		)
	)


## tour_back cells before stop k along the way (the start when it is closer).
static func _back_from(r: MapReview, k: int, at: Vector3) -> Vector3:
	var back := L.num("tour_back")
	var last: int = r.stop_steps[k] if k < r.stop_steps.size() else -1
	var i := last
	while i > 0 and MapReview.centre(r.steps[i]).distance_to(Vector2(at.x, at.y)) < back:
		i -= 1
	if i < 0 or r.steps.is_empty():
		return r.spawn
	var p := MapReview.centre(r.steps[i])
	return Vector3(p.x, p.y, r.lv.floor_under(p.x, p.y, at.z + .05))


## The two highest places a body stands (on a level with geometry).
static func _high(r: MapReview) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var lv := r.lv
	if lv.geo == null:
		return out
	var f := FlowField.new(lv)
	if f.graph == null:
		return out
	var best: Array[int] = []
	for n in range(f.graph.cells, f.graph.count):
		if f.graph.z[n] < 1.0:
			continue
		best.append(n)
	best.sort_custom(func(a: int, b: int) -> bool: return f.graph.z[a] > f.graph.z[b])
	for n in best:
		var c: int = f.graph.cell[n]
		var p := Vector3(c % lv.width + .5, c / lv.width + .5, f.graph.z[n])
		var far := true
		for q in out:
			if Vector2(q.x, q.y).distance_to(Vector2(p.x, p.y)) < 6.0:
				far = false
		if far:
			out.append(p)
		if out.size() >= 2:
			break
	return out


## The open cell beside a door under a roof (inside), or INF.
static func _inside_of(lv: LevelData, d: LevelData.Door) -> Vector2:
	var sides: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0)]
	if not d.vertical:
		sides = [Vector2i(0, -1), Vector2i(0, 1)]
	for s in sides:
		var x := d.x + s.x * 2
		var y := d.y + s.y * 2
		if x < 0 or y < 0 or x >= lv.width or y >= lv.height:
			continue
		var c := y * lv.width + x
		if lv.solid[c] < 0 and lv.roof[c] > 0.0:
			return Vector2(x + .5, y + .5)
	return Vector2.INF


## The open cell nearest a district's middle, or INF.
static func _district_middle(lv: LevelData, a: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for c in lv.area.size():
		if lv.area[c] == a and lv.solid[c] < 0:
			sum += Vector2(c % lv.width + .5, c / lv.width + .5)
			count += 1
	if count < 6:
		return Vector2.INF
	var mid := sum / count
	var best := Vector2.INF
	var best_d := INF
	for c in lv.area.size():
		if lv.area[c] != a or lv.solid[c] >= 0:
			continue
		var p := Vector2(c % lv.width + .5, c / lv.width + .5)
		if lv.blocked(p.x, p.y, .3, lv.floor_under(p.x, p.y, .05)):
			continue  # (a kit building's walls stand in open cells)
		var d := p.distance_to(mid)
		if d < best_d:
			best_d = d
			best = p
	return best


## Where to look from `p`: along the longest open look of eight (what shows
## the most of a place).
static func _open_way(r: MapReview, p: Vector2) -> Vector2:
	var best := MapReview.DIRS[0]
	var far := -1.0
	for d in MapReview.DIRS:
		var f := r._look(p, d, 24.0)
		if f > far:
			far = f
			best = d
	return p + best * maxf(far, 1.0)


## Where to stand for a fight's picture: the first step from where the way
## meets it that sees one of its hands (within 14), else its nearest step.
static func _fight_spot(r: MapReview, fight: Dictionary) -> Vector2:
	var meet: int = fight["meet"]
	var closest: int = fight["closest"]
	for i in range(meet, maxi(meet, closest) + 1):
		var p := MapReview.centre(r.steps[i])
		for m: int in fight["hands"]:
			var at: Vector3 = r.hands[m]["at"]
			if (
				Vector2(at.x, at.y).distance_to(p) <= 14.0
				and r.lv.visible(
					p.x, p.y, at.x, at.y, r.lv.floor_under(p.x, p.y, .05) + .95, at.z + 1.0
				)
			):
				return p
	return MapReview.centre(r.steps[maxi(closest, 0)])
