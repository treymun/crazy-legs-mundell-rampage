## Fire that spreads, cell by cell. A blast of a kind that lights things (the
## powder keg, a fuel drum, a propane tank, gas cans, nitro, a still going up),
## a shine cocktail's fire, a puddle of spilled shine set alight or a still's
## burning spray (stills.gd) sets the cells it reaches burning. A cell burns as
## long as what is on it lasts (data/tuning/fire.cfg: hay, plank floors and
## decks, crates, hay bales, lumber, a body, a puddle of shine) and now and
## then lights a neighbour by how readily that catches, so fire runs over a
## hay loft or a porch and stops at stone, dirt and water. It burns what
## stands in it (players, enemies, breakables: a crate of dynamite in a fire
## goes up), chars the floor (a black mark) and burns out; a charred cell never
## burns again. Rain on open ground puts it out faster.
##
## Bounded and cheap: at most `cap` cells burn at once and one fire spreads
## to at most its budget of cells; with nothing burning and no puddles a tick
## costs nothing. Play (game.rng for the spreading), carried in snapshots;
## the flames, marks and crackle are drawn from that. Quest props never burn
## (they never break), and nothing it does shuts a way. Off where carry.gd is.
extends GameFeature

const Breakables := preload("res://src/features/breakables.gd")
const ModeFeature := preload("res://src/features/mode_feature.gd")
const PATH := "res://data/tuning/fire.cfg"
const NEAR := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1)
]
## A burning cell's row in `burning`.
const CELL := 0
const LEFT := 1
const Z := 2
const SPREAD_AT := 3
const LIFE := 4

## Each burning cell: [cell, seconds left, z of what burns, next spread, its
## whole life].
var burning: Array = []
## Cells burnt out: cell -> the z of the char.
var charred := {}
## Puddles of shine: [x, y, z, gone at (clock)].
var puddles: Array = []
## Bodies that burned (their uid), once each.
var burnt_bodies := {}
var budget := 0
var next_bite := 0.0
var on := true
## Counts every change, so a host's NetTrack looks at the lists only then.
var net_version := 0
const NET_GUARDED := ["burning", "charred", "puddles", "burnt_bodies"]
var _cfg: ConfigFile
## What each cell has to burn (seconds, catch) and at what height: the
## level's floors and the props standing there, the same on every machine.
var _fuel := PackedFloat32Array()
var _catch := PackedFloat32Array()
var _z := PackedFloat32Array()
var _rain := 0.0
var _lights := {}
var _spills := {}
## Burning cells by cell (worked out from `burning`), bodies by cell (looked
## for at each bite), the marks drawn (by cell) and when it last crackled.
var _at := {}
var _seen := -1
var _marks := {}
var _crackle_at := 0.0
## The burn barrels: a puddle of shine beside one goes up.
var _barrels: Array = []


func id() -> String:
	return "fire"


func attach() -> void:
	_cfg = Tuning.file(PATH)
	for kind: Variant in _cfg.get_value("all", "lights", []):
		_lights[str(kind)] = true
	for image: String in _cfg.get_section_keys("spills"):
		_spills[image] = _cfg.get_value("spills", image)
	var share: float = Effects.mood(game.level.id, "showers", 0.0)
	var hard: float = Effects.mood(game.level.id, "rain", 0.0)
	_rain = clampf(hard, 0.0, 1.0) * (clampf(share, 0.0, 1.0) if share > 0.0 else 1.0)
	_map()
	tick_with(_tick)
	game.events.exploded.connect(_exploded)
	game.events.prop_broken.connect(_broken)


func num(key: String) -> float:
	var v: float = _cfg.get_value("all", key, 0.0)
	return v


func allowed() -> bool:
	return on and not game.in_hub and not Modes.is_versus(game)


# ------------------------------------------------------------------ the map


## What burns in each cell: its floor (a deck's or loft's own tile up on it)
## and the props standing there.
func _map() -> void:
	var w := game.world
	var n := w.width * w.height
	_fuel.resize(n)
	_catch.resize(n)
	_z.resize(n)
	_fuel.fill(0.0)
	var floors := {}
	for tile: String in _cfg.get_section_keys("floors"):
		floors[tile] = _cfg.get_value("floors", tile)
	for c in n:
		if w.solid[c] >= 0:
			continue
		var t: int = w.floor_tile[c]
		if t >= 0 and t < w.tile_names.size() and floors.has(w.tile_names[t]):
			_put(c, floors[w.tile_names[t]], w.ground[c])
	if w.geo != null:
		for s: LevelGeometry.Slab in w.geo.slabs:
			if not s.walk or s.tile < 0 or s.tile >= w.tile_names.size():
				continue
			var spec: Variant = floors.get(w.tile_names[s.tile])
			if spec == null:
				continue
			for cy in range(maxi(0, int(s.y0)), mini(w.height, int(ceilf(s.y1)))):
				for cx in range(maxi(0, int(s.x0)), mini(w.width, int(ceilf(s.x1)))):
					if s.inside(cx + .5, cy + .5):
						_put(cy * w.width + cx, spec, s.top_at(cx + .5, cy + .5))
	var props := {}
	for image: String in _cfg.get_section_keys("props"):
		props[image] = _cfg.get_value("props", image)
	for board: LevelData.Billboard in w.billboards:
		if board.image == "town_burn_barrel":
			_barrels.append(Vector2(board.x, board.y))
		if props.has(board.image) and board.signal_name == "":
			var c := w.cell(board.x, board.y)
			_put(c, props[board.image], w.elevation(board.x, board.y) + board.z, true)
	for s: View.Sprite in game.props:
		if props.has(s.image):
			_put(w.cell(s.x, s.y), props[s.image], s.z, true)


func _put(c: int, spec: Variant, z: float, prop := false) -> void:
	var row: Array = spec
	var seconds: float = row[0]
	var catch: float = row[1]
	if prop and _fuel[c] > 0.0:
		# A prop on a burning floor: as long as the longer, as ready as either.
		_fuel[c] = maxf(_fuel[c], seconds)
		_catch[c] = maxf(_catch[c], catch)
		return
	_fuel[c] = seconds
	_catch[c] = catch
	_z[c] = z


## What cell c has to burn now (none once charred), and how readily it catches.
func fuel(c: int) -> float:
	return 0.0 if charred.has(c) else _fuel[c]


func burning_at(x: float, y: float) -> bool:
	return _at.has(game.world.cell(x, y))


## Whether what is at height z in cell c is water (not a dock over it).
func _water(c: int, z: float) -> bool:
	var w := game.world
	if Materials.of_tile(w, w.floor_tile[c]) != "water":
		return false
	return z < w.ground[c] + .3


# --------------------------------------------------------------- lighting


## Set the cell at (x, y) alight, its fire at height z: as long as what is
## there lasts, or `least` seconds when there is nothing (a blast on dirt).
## Returns whether it took.
func ignite(x: float, y: float, z: float, least := -1.0) -> bool:
	if not allowed():
		return false
	if _seen != net_version:
		_index()
	var w := game.world
	if x < 0.0 or y < 0.0 or x >= w.width or y >= w.height:
		return false
	var c := w.cell(x, y)
	if _at.has(c) or w.solid[c] >= 0 or burning.size() >= int(num("cap")):
		return false
	if _water(c, z):
		return false
	var seconds := fuel(c)
	var at_z := _z[c] if seconds > 0.0 else w.floor_under(x, y, z + .3)
	if seconds > 0.0 and absf(at_z - z) > 1.2:
		# The floor that burns is a deck over (or under) where the fire is.
		seconds = 0.0
		at_z = w.floor_under(x, y, z + .3)
	seconds = maxf(seconds, least)
	var puddle := _puddle_in(c)
	if puddle >= 0:
		seconds = maxf(seconds, num("puddle_burn"))
		puddles.remove_at(puddle)
	if seconds <= 0.0:
		return false
	_light(c, seconds, at_z)
	return true


func _light(c: int, seconds: float, z: float) -> void:
	if burning.is_empty():
		# A fire gnaws at a barn's or a water tower's posts (features/set_pieces.gd).
		var sets: GameFeature = game.features.get("set_pieces")
		if sets != null:
			sets.wake()
	burning.append([c, seconds, z, game.clock + num("spread_every") * .5, seconds])
	_at[c] = true
	net_version += 1
	_seen = net_version
	if burning.size() == 1:
		var w := game.world
		game.sound_at("molotov_burst", (c % w.width) + .5, float(c / w.width) + .5, .6)


## Water over cell c (a water tower's flood, features/set_pieces.gd): its fire
## is out (charred, if it had fuel) and its puddle washed away.
func douse(c: int) -> void:
	if _seen != net_version:
		_index()
	var puddle := _puddle_in(c)
	if puddle >= 0:
		puddles.remove_at(puddle)
		net_version += 1
	if not _at.has(c):
		return
	for row: Array in burning:
		if row[CELL] == c:
			burning.erase(row)
			if _fuel[c] > 0.0:
				var z: float = row[Z]
				charred[c] = z
			break
	_at.erase(c)
	net_version += 1
	_seen = net_version


## The burning cells by cell, again after a snapshot changed them.
func _index() -> void:
	_seen = net_version
	_at.clear()
	for row: Array in burning:
		_at[row[CELL]] = true


## A fire starting from outside (a blast, a cocktail, a spray) brings its own
## budget of cells it may spread to.
func fresh() -> void:
	budget = mini(int(num("budget_most")), budget + int(num("budget_each")))


## A blast that lights things sets every cell it reaches in `reach` of its
## radius burning (a burst drum, a keg, a still).
func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if energy or not allowed() or not _lights.has(game.blast_kind):
		return
	var spec := Shots.blast(game.blast_kind)
	var radius: float = spec.get("radius", 2.8)
	var reach := radius * num("reach")
	fresh()
	var w := game.world
	var base := w.floor_under(x, y, z + .3)
	for cy in range(int(y - reach), int(y + reach) + 1):
		for cx in range(int(x - reach), int(x + reach) + 1):
			var px := cx + .5
			var py := cy + .5
			if Vector2(px - x, py - y).length() > reach:
				continue
			if px < 0.0 or py < 0.0 or px >= w.width or py >= w.height:
				continue
			if w.solid[w.cell(px, py)] >= 0 or not w.visible(x, y, px, py, z, base + .2):
				continue
			ignite(px, py, base, num("patch"))


## A jug stack, a mash barrel or a still broke: its shine spills about it.
func _broken(image: String, x: float, y: float, z: float) -> void:
	if not allowed() or not _spills.has(image):
		return
	var count: int = _spills[image]
	var floor_z := game.world.floor_under(x, y, z)
	for k in count:
		var a := k * 2.39996 + x
		var r := .25 + .35 * k
		spill(x + cos(a) * r, y + sin(a) * r, floor_z)


## A puddle of shine at (x, y) on the floor at z (it lights when fire reaches
## it, or goes up at once beside a fire).
func spill(x: float, y: float, z: float) -> void:
	var w := game.world
	if x < 0.0 or y < 0.0 or x >= w.width or y >= w.height or w.blocked(x, y, .1, z + .2):
		return
	var c := w.cell(x, y)
	if _at.has(c):
		fresh()
		ignite(x, y, z, num("puddle_burn"))
		return
	if _water(c, z):
		return
	puddles.append([x, y, w.floor_under(x, y, z + .3), game.clock + num("puddle_life")])
	while puddles.size() > int(num("puddle_most")):
		puddles.pop_front()
	net_version += 1


func _puddle_in(c: int) -> int:
	var w := game.world
	for k in puddles.size():
		var row: Array = puddles[k]
		var px: float = row[0]
		var py: float = row[1]
		if w.cell(px, py) == c:
			return k
	return -1


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	if _seen != net_version:
		_index()
	if not allowed():
		return
	_cocktails()
	if burning.is_empty() and puddles.is_empty():
		if budget != 0:
			budget = 0
		return
	if not puddles.is_empty():
		_soak()
	if burning.is_empty():
		return
	var w := game.world
	var lit: Array = []
	var gone: Array = []
	for row: Array in burning:
		var c: int = row[CELL]
		var left: float = row[LEFT]
		var open := w.roof[c] == 0.0
		left -= dt * (1.0 + (num("rain_out") - 1.0) * _rain if open else 1.0)
		row[LEFT] = left
		if left <= 0.0:
			gone.append(row)
			continue
		var spread_at: float = row[SPREAD_AT]
		if game.clock >= spread_at:
			row[SPREAD_AT] = game.clock + num("spread_every") * game.rng.uniform(.67, 1.33)
			lit.append(row)
	for row: Array in gone:
		burning.erase(row)
		var c: int = row[CELL]
		_at.erase(c)
		if _fuel[c] > 0.0:
			var z: float = row[Z]
			charred[c] = z
		net_version += 1
		_seen = net_version
	for row: Array in lit:
		_spread(row)
	if game.clock >= next_bite:
		next_bite = game.clock + num("bite_every")
		_bite()
	if burning.is_empty():
		budget = 0
	# Every burning cell's time runs down each tick: a host's NetTrack looks.
	net_version += 1
	_seen = net_version
	_crackle()


## A burning cell tries to light one neighbour.
func _spread(row: Array) -> void:
	if budget <= 0:
		return
	var w := game.world
	var c: int = row[CELL]
	var z: float = row[Z]
	var cx := c % w.width
	var cy := c / w.width
	var way: Vector2i = NEAR[int(game.rng.random() * NEAR.size()) % NEAR.size()]
	var nx := cx + way.x
	var ny := cy + way.y
	if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height:
		return
	var n := ny * w.width + nx
	if _at.has(n) or w.solid[n] >= 0:
		return
	var seconds := fuel(n)
	var catch := _catch[n] if seconds > 0.0 else 0.0
	var at_z := _z[n]
	if seconds > 0.0 and absf(at_z - z) > .6:
		seconds = 0.0
		catch = 0.0
	if _puddle_in(n) >= 0:
		catch = 1.0
		at_z = w.floor_under(nx + .5, ny + .5, z + .3)
	elif _body_in(n) != 0:
		catch = maxf(catch, num("body_catch"))
		if seconds <= 0.0:
			at_z = w.floor_under(nx + .5, ny + .5, z + .3)
	if catch <= 0.0:
		return
	if w.roof[n] == 0.0:
		catch *= 1.0 - (1.0 - num("rain_catch")) * _rain
	if game.rng.random() >= catch:
		return
	if not w.visible(cx + .5, cy + .5, nx + .5, ny + .5, z + .2, at_z + .2):
		return
	if ignite(nx + .5, ny + .5, at_z, num("patch")):
		budget -= 1


## Everything standing in a burning cell is burned: players, enemies, the
## breakables there; a body in one burns a while longer.
func _bite() -> void:
	var w := game.world
	var bodies := {}
	for e: Enemy in game.enemies:
		var c := _cell_of(e.x, e.y)
		if not e.alive:
			if not burnt_bodies.has(e.uid):
				bodies[c] = e.uid
			continue
		if _at.has(c) and e.brain != "bessie" and _near_z(c, w.stand(e) + e.z):
			Players.world_hurt(game, e, num("bite_enemy"), false, "fire")
	for p: Player in game.players:
		if p.health <= 0 or p.air > .3:
			continue
		var c := w.cell(p.x, p.y)
		if _at.has(c) and _near_z(c, w.stand(p)):
			var x := (c % w.width) + .5
			var y := float(c / w.width) + .5
			game.damage(num("bite"), [x, y], "FIRE", p)
	var bk: Breakables = game.features.get("breakables")
	if bk != null:
		for i in bk.pieces.size():
			var piece: Breakables.Piece = bk.pieces[i]
			if piece.broken or piece.x < 0.0 or piece.y < 0.0:
				continue
			if piece.x >= w.width or piece.y >= w.height:
				continue
			if _at.has(w.cell(piece.x, piece.y)):
				bk.strike(i, num("bite_prop"), 0.0, 0.0)
	for row: Array in burning:
		var c: int = row[CELL]
		if bodies.has(c):
			burnt_bodies[bodies[c]] = true
			var left: float = row[LEFT]
			row[LEFT] = left + num("body")
			var life: float = row[LIFE]
			row[LIFE] = life + num("body")
			net_version += 1
			_seen = net_version


func _cell_of(x: float, y: float) -> int:
	var w := game.world
	return w.cell(clampf(x, 0.0, w.width - .01), clampf(y, 0.0, w.height - .01))


## A body not burnt yet lying in cell c (its uid), or 0.
func _body_in(c: int) -> int:
	for e: Enemy in game.enemies:
		if not e.alive and not burnt_bodies.has(e.uid) and _cell_of(e.x, e.y) == c:
			return e.uid
	return 0


func _near_z(c: int, z: float) -> bool:
	for row: Array in burning:
		if row[CELL] == c:
			var at: float = row[Z]
			return absf(at - z) < .6
	return false


## The shine cocktails' fires (the mode feature's, where the throwables are)
## set what they land on alight.
func _cocktails() -> void:
	var st: ModeFeature = game.features.get("mode")
	if st == null or st.fires.is_empty():
		return
	for fire: Array in st.fires:
		var x: float = fire[0]
		var y: float = fire[1]
		if not _at.has(game.world.cell(x, y)):
			fresh()
			ignite(x, y, game.world.floor_under(x, y, 2.0), num("patch"))


## Puddles soak in after a while; one beside a fire goes up.
func _soak() -> void:
	var w := game.world
	var kept: Array = []
	for row: Array in puddles:
		var gone_at: float = row[3]
		if game.clock < gone_at:
			kept.append(row)
	if kept.size() != puddles.size():
		puddles = kept
		net_version += 1
		_seen = net_version
	for row: Array in puddles.duplicate():
		var x: float = row[0]
		var y: float = row[1]
		var z: float = row[2]
		var by_barrel := false
		for at: Vector2 in _barrels:
			by_barrel = by_barrel or at.distance_to(Vector2(x, y)) < 1.1
		if by_barrel:
			fresh()
			ignite(x, y, z, num("puddle_burn"))
			continue
		if burning.is_empty():
			continue
		var c := w.cell(x, y)
		var cx := c % w.width
		var cy := c / w.width
		for way: Vector2i in NEAR:
			if _at.has((cy + way.y) * w.width + cx + way.x):
				ignite(x, y, z, num("puddle_burn"))
				break


func _crackle() -> void:
	if game.clock < _crackle_at or game.host:
		return
	_crackle_at = game.clock + .9
	var p := game.local_player
	var w := game.world
	var best := num("heard")
	var at := Vector2.INF
	for row: Array in burning:
		var c: int = row[CELL]
		var spot := Vector2((c % w.width) + .5, float(c / w.width) + .5)
		var d := spot.distance_to(Vector2(p.x, p.y))
		if d < best:
			best = d
			at = spot
	if at != Vector2.INF:
		game.sound_at("fire_crackle", at.x, at.y, .55)


# ---------------------------------------------------------------- the view

## The flames' four pictures (sprites() names three a burning cell a frame).
const FLAMES: Array[String] = ["fx_flame_0", "fx_flame_1", "fx_flame_2", "fx_flame_3"]


func sprites() -> Array:
	var out: Array = []
	if burning.is_empty():
		return out
	if _seen != net_version:
		_index()
	var w := game.world
	var frame := int(game.clock * 12.0)
	for row: Array in burning:
		var c: int = row[CELL]
		var x := (c % w.width) + .5
		var y := float(c / w.width) + .5
		if not game.in_view(x, y, 1.2):
			continue
		var left: float = row[LEFT]
		var life: float = row[LIFE]
		var z: float = row[Z]
		var grow := clampf((life - left) / .5, .35, 1.0)
		var fade := clampf(left / 1.5, .25, 1.0)
		var big := .55 + (.45 if _fuel[c] >= 7.0 else .15)
		for k in 3:
			var a := k * 2.39996 + c * .7
			var r := .18 + .1 * k
			var fx := x + cos(a) * r
			var fy := y + sin(a) * r
			var tall := big * grow * fade * (1.0 - k * .18)
			var s: View.Sprite = game.pooled(fx, fy, FLAMES[(frame + k + c) % 4], tall, z)
			s.glow = true
			out.append(s)
	return out


func ground_marks() -> Array:
	var out: Array = []
	if charred.is_empty() and puddles.is_empty():
		return out
	var w := game.world
	var drawn := 0
	var most := int(num("char_drawn"))
	for key: Variant in charred:
		var c: int = key
		var x := (c % w.width) + .5
		var y := float(c / w.width) + .5
		if drawn >= most or not game.in_view(x, y, .8):
			continue
		var mark: View.GroundMark = _marks.get(c)
		if mark == null:
			var z: float = charred[c]
			mark = View.GroundMark.new(
				x, y, 0.0, float(c % 7) * .9, .62, .62, "mark_scorch_%d" % (c % 3)
			)
			Tumble.lay(w, mark, z + .1, .006)
			_marks[c] = mark
		out.append(mark)
		drawn += 1
	var size := num("puddle_size") * .5
	for row: Array in puddles:
		var x: float = row[0]
		var y: float = row[1]
		if not game.in_view(x, y, size):
			continue
		var z: float = row[2]
		var mark := View.GroundMark.new(
			x, y, 0.0, x * 1.7 + y, size, size * .8, "mark_oil_%d" % (int(x * 7.0) % 3)
		)
		out.append(Tumble.lay(w, mark, z + .1, .008))
	return out


# -------------------------------------------------------------------- saves


func save() -> Dictionary:
	if burning.is_empty() and charred.is_empty() and puddles.is_empty():
		return {}
	var chars: Array = []
	for key: Variant in charred:
		var z: float = charred[key]
		chars.append([key, snappedf(z, .01)])
	return {
		"burning": burning.duplicate(true),
		"charred": chars,
		"puddles": puddles.duplicate(true),
		"budget": budget,
	}


func restore(state: Dictionary) -> void:
	burning.clear()
	_at.clear()
	var n := game.world.width * game.world.height
	for item: Variant in state.get("burning", []):
		if item is Array:
			var row: Array = item
			var c: int = row[0] if row.size() == 5 else -1
			if c >= 0 and c < n:
				burning.append(row.duplicate())
				_at[c] = true
	charred.clear()
	for item: Variant in state.get("charred", []):
		if item is Array:
			var row: Array = item
			var c: int = row[0] if row.size() == 2 else -1
			if c >= 0 and c < n:
				charred[c] = row[1]
	puddles.clear()
	for item: Variant in state.get("puddles", []):
		if item is Array:
			var row: Array = item
			if row.size() == 4:
				puddles.append(row.duplicate())
	var left: int = state.get("budget", 0)
	budget = left
	_marks.clear()
	net_version += 1
	_seen = net_version
