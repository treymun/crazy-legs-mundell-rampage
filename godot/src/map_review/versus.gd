## The design review of a versus map (pass 16, T7): the starts and sites a
## map gives its modes (LevelData.tactical, from a map source's dm_spawn,
## team_spawn, bomb_site, hostage and rescue_zone objects, or a plan's
## meta.tactical), checked for what makes a fair fight. Run by MapReview on
## any level whose tactical block is not empty; its findings go with the
## rest. Numbers and lines: data/tuning/map_review.json.
##
## - deathmatch starts: enough of them, all walked to from one another, none
##   standing in sight of another close by (spawn_open), none overlooked by
##   most of the rest (spawn_watched);
## - the 5v5 starts: the two sides walked to each other (spawn_cut), neither
##   side's start seen from the other's (team_spawn_seen), far enough apart
##   (teams_close);
## - balance: the defenders reach each site before the attackers, but not
##   so long before that the attack is hopeless (site_rush, site_far); the
##   attackers' walks to A and to B within a ratio (sites_uneven); hostages
##   and the rescue ground walked to (hostage_cut).
class_name MapVersus
extends RefCounted

const L := preload("res://src/map_review/review_lines.gd")
const EYE := .95


static func review(r: MapReview) -> void:
	var tac: Dictionary = r.lv.tactical
	var modes: Array = tac.get("modes", []) if tac.get("modes") is Array else []
	r.numbers["modes"] = ", ".join(PackedStringArray(modes))
	var dm := _spots(tac, "deathmatch")
	if not dm.is_empty():
		_deathmatch(r, dm)
	elif modes.has("deathmatch") or modes.has("team_deathmatch"):
		r._add("versus", "dm_auto", [r.spawn.x, r.spawn.y], {})
	var attack := _spots(tac, "attack_spawns")
	var defend := _spots(tac, "defend_spawns")
	if not attack.is_empty() and not defend.is_empty():
		_teams(r, attack, defend)
		_balance(r, tac, attack, defend)


## [x, y] places of a tactical list (each [x, y, facing]) on their floors.
static func _spots(tac: Dictionary, key: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rows: Variant = tac.get(key, [])
	if not (rows is Array):
		return out
	var list: Array = rows
	for row: Variant in list:
		if not (row is Array):
			continue
		var pair: Array = row
		if pair.size() >= 2:
			var x: float = pair[0]
			var y: float = pair[1]
			out.append(Vector2(x, y))
	return out


static func _field(r: MapReview, at: Vector2) -> FlowField:
	var f := FlowField.new(r.lv)
	f.reach = 1 << 20
	f.doors_open = true
	f.every_door = true
	MapReview.measure(f, Vector3(at.x, at.y, r.lv.floor_under(at.x, at.y, .05)))
	return f


static func _steps(r: MapReview, f: FlowField, at: Vector2) -> int:
	return f.distance(at.x, at.y, r.lv.floor_under(at.x, at.y, .05))


static func _sees(r: MapReview, a: Vector2, b: Vector2) -> bool:
	var za := r.lv.floor_under(a.x, a.y, .05) + EYE
	var zb := r.lv.floor_under(b.x, b.y, .05) + EYE
	return r.lv.visible(a.x, a.y, b.x, b.y, za, zb)


static func _deathmatch(r: MapReview, dm: Array[Vector2]) -> void:
	r.numbers["dm_spawns"] = dm.size()
	if dm.size() < L.whole("dm_spawns_least"):
		r._add(
			"versus",
			"dm_spawns_few",
			[dm[0].x, dm[0].y],
			{"count": dm.size(), "least": L.whole("dm_spawns_least")}
		)
	var f := _field(r, dm[0])
	var near := L.num("spawn_open_near")
	var watch := L.num("spawn_watch_near")
	var flagged := {}
	for i in dm.size():
		var a := dm[i]
		if i > 0 and _steps(r, f, a) >= FlowField.FAR:
			r._add("versus", "spawn_cut", [a.x, a.y], {"name": "deathmatch start %d" % (i + 1)})
			continue
		var watched := 0
		for j in dm.size():
			if i == j:
				continue
			var b := dm[j]
			var d := a.distance_to(b)
			if d <= watch and _sees(r, a, b):
				watched += 1
				if d < near and j > i and not flagged.has(j):
					flagged[j] = true
					r._add(
						"versus",
						"spawn_open",
						[b.x, b.y],
						{"a": i + 1, "b": j + 1, "far": snappedf(d, .1)}
					)
		if dm.size() >= 4 and watched * 2 > dm.size() - 1:
			r._add(
				"versus",
				"spawn_watched",
				[a.x, a.y],
				{"n": i + 1, "watched": watched, "of": dm.size() - 1}
			)


static func _middle(list: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for p: Vector2 in list:
		sum += p
	return sum / maxf(list.size(), 1)


static func _teams(r: MapReview, attack: Array[Vector2], defend: Array[Vector2]) -> void:
	var fa := _field(r, attack[0])
	var apart := _steps(r, fa, defend[0])
	r.numbers["teams_apart_steps"] = apart
	if apart >= FlowField.FAR:
		r._add("versus", "spawn_cut", [defend[0].x, defend[0].y], {"name": "the defenders' start"})
		return
	if apart < L.whole("teams_apart_least"):
		r._add(
			"versus",
			"teams_close",
			[defend[0].x, defend[0].y],
			{"steps": apart, "least": L.whole("teams_apart_least")}
		)
	# The closest pair of starts in sight of each other: MUST FIX within
	# team_seen_near, SHOULD past it (a long lane the fog thins out).
	var best := INF
	var pair: Array[Vector2] = []
	for a: Vector2 in attack:
		for d: Vector2 in defend:
			var far := a.distance_to(d)
			if far < best and _sees(r, a, d):
				best = far
				pair = [a, d]
	if pair.is_empty():
		return
	var fields := {
		"a": L.place([pair[0].x, pair[0].y]),
		"d": L.place([pair[1].x, pair[1].y]),
		"far": snappedf(best, .1),
	}
	if best > L.num("team_seen_near"):
		fields["level"] = "SHOULD"
	r._add("versus", "team_spawn_seen", [pair[1].x, pair[1].y], fields)


## The walk each side has to each site (and the hostages): who gets there first.
static func _balance(
	r: MapReview, tac: Dictionary, attack: Array[Vector2], defend: Array[Vector2]
) -> void:
	var fa := _field(r, _near_open(r, _middle(attack), attack[0]))
	var fd := _field(r, _near_open(r, _middle(defend), defend[0]))
	var sites: Dictionary = tac.get("sites", {}) if tac.get("sites") is Dictionary else {}
	var walks := {}
	for name: Variant in sites:
		var box: Array = sites[name]
		if box.size() < 4:
			continue
		var x0: float = box[0]
		var y0: float = box[1]
		var x1: float = box[2]
		var y1: float = box[3]
		var centre := _near_open(r, Vector2((x0 + x1 + 1.0) * .5, (y0 + y1 + 1.0) * .5), Vector2(x0 + .5, y0 + .5))
		var sa := _steps(r, fa, centre)
		var sd := _steps(r, fd, centre)
		var site := str(name)
		r.numbers["site_%s_attack_steps" % site] = sa
		r.numbers["site_%s_defend_steps" % site] = sd
		if sa >= FlowField.FAR or sd >= FlowField.FAR:
			r._add("versus", "spawn_cut", [centre.x, centre.y], {"name": "site " + site})
			continue
		walks[site] = sa
		var ratio := float(sa) / maxf(sd, 1.0)
		var fields := {"site": site, "attack": sa, "defend": sd, "ratio": snappedf(ratio, .01)}
		if ratio < L.num("site_ratio_least"):
			r._add("versus", "site_rush", [centre.x, centre.y], fields)
		elif ratio > L.num("site_ratio_most"):
			r._add("versus", "site_far", [centre.x, centre.y], fields)
	if walks.has("A") and walks.has("B"):
		var a: int = walks["A"]
		var b: int = walks["B"]
		var uneven := float(maxi(a, b)) / maxf(mini(a, b), 1.0)
		r.numbers["sites_uneven"] = snappedf(uneven, .01)
		if uneven > L.num("sites_uneven_most"):
			r._add(
				"versus",
				"sites_uneven",
				[attack[0].x, attack[0].y],
				{"a": a, "b": b, "ratio": snappedf(uneven, .01)}
			)
	for h: Vector2 in _spots(tac, "hostages"):
		if _steps(r, fa, h) >= FlowField.FAR:
			r._add("versus", "hostage_cut", [h.x, h.y], {"what": "a hostage"})
	var rescue: Variant = tac.get("rescue", [])
	var box: Array = rescue if rescue is Array else []
	if box.size() == 4 and not _spots(tac, "hostages").is_empty():
		var rx: float = box[0]
		var ry: float = box[1]
		var rx1: float = box[2]
		var ry1: float = box[3]
		var mid := _near_open(r, Vector2((rx + rx1 + 1.0) * .5, (ry + ry1 + 1.0) * .5), attack[0])
		if _steps(r, fa, mid) >= FlowField.FAR:
			r._add("versus", "hostage_cut", [mid.x, mid.y], {"what": "the rescue ground"})


## `at` when a body stands there, else the nearest open cell middle within 3
## (a site's middle may be a crate), else `fallback`.
static func _near_open(r: MapReview, at: Vector2, fallback: Vector2) -> Vector2:
	if not r.lv.blocked(at.x, at.y, .2):
		return at
	for k in range(1, 4):
		for dy in range(-k, k + 1):
			for dx in range(-k, k + 1):
				var p := Vector2(floorf(at.x) + dx + .5, floorf(at.y) + dy + .5)
				if p.x > 0 and p.y > 0 and p.x < r.lv.width and p.y < r.lv.height:
					if not r.lv.blocked(p.x, p.y, .2):
						return p
	return fallback
