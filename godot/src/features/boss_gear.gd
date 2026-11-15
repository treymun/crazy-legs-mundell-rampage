## A boss's gear can be shot off (bosses.cfg [boss_gear]): the sheriff's hat
## and tin star, Jerry's helmet, Rudy's PA horns and top hat, the foreman's
## hard hat, the Baron's top hat and monocle, the Swamp King's crown and bow
## shield, Boggs's hood, trunk lid and push-bar ram, Maw's curlers and cat-eye
## glasses. Each is a part of the boss's 3D model with bones of its own
## (actors.json "gear", tagged in the Blender builds with gear()).
##
## A player's hit that lands where a piece sits (a band of the boss's height,
## from the front, the back or any side, near enough its middle across) wears
## it down by the hit's damage; worn, it soaks a hit there by its `armour`.
## Worn out it flies off as a loose piece (Tumble: it tumbles, bounces and
## lies on the floor where it lands, drawn as that part of the model) and the
## model leaves it off (ActorView.lose_gear); a hit there then counts `bare`.
## Some come off by themselves at a share of the boss's health (`falls`: the
## derby truck sheds its panels as it is beaten). A boss's own moves ask
## lost() for what changes when a piece is gone (Jerry's helmet stops
## guarding his head, Rudy's horns stop blowing their volley, Boggs's ram
## stops biting as hard).
##
## Play: the hits it soaks change the fight, so it is a simulation feature
## (carried online, saved; the boss checkpoint and BOSS REMATCH start with
## every piece on, reset()). No dice: where a piece flies is worked out from
## where the shot came from. BOSS ARENAS WRECK off (game.boss_wrecks): no
## piece comes off and none soaks anything.
class_name BossGearFeature
extends GameFeature

static var GEAR: Dictionary = BossData.get_value("boss_gear", "gear")
## How a piece flies off: its run away from the shot, its lift, how fast it
## turns over in the air.
static var FLING: float = BossData.get_value("boss_gear", "fling")
static var LIFT: float = BossData.get_value("boss_gear", "lift")
static var SPIN: float = BossData.get_value("boss_gear", "spin")
## What Boggs's rams do with the push-bar ram shot off (derby_champ.gd, boggs.gd).
static var RAMLESS: float = BossData.get_value("boss_gear", "ramless")

## Each piece of every boss in the level: {"e": boss, "kind", "name", "hp",
## "off": bool}.
var gear: Array = []
## Pieces shot off, loose in the world: {"e", "name", "x", "y", "z", "vx",
## "vy", "vz", "rest", "born", "turn" (heading), "axis" (tumble axis's
## heading), "rest_turn" (the tumble it lies at)}.
var loose: Array = []
## "kind:name" -> Tumble.Feel (each piece rests on its own half height).
var _feels: Dictionary = {}


func id() -> String:
	return "boss_gear"


func attach() -> void:
	for e: Enemy in game.enemies:
		_fit(e)
	game.events.ticked.connect(_tick)


func save() -> Dictionary:
	var lost: Array = []
	for g: Dictionary in gear:
		var off: bool = g["off"]
		var e: Enemy = g["e"]
		lost.append([game.enemies.find(e), g["name"], g["hp"], off])
	var pieces: Array = []
	for p: Dictionary in loose:
		var e: Enemy = p["e"]
		(
			pieces
			. append(
				[
					game.enemies.find(e),
					p["name"],
					p["x"],
					p["y"],
					p["z"],
					p["turn"],
					p["axis"],
					p["rest_turn"],
				]
			)
		)
	return {"gear": lost, "loose": pieces}


func restore(state: Dictionary) -> void:
	var lost: Array = state.get("gear", [])
	for row: Array in lost:
		var i: int = row[0]
		if i < 0 or i >= game.enemies.size():
			continue
		for g: Dictionary in gear:
			if g["e"] == game.enemies[i] and g["name"] == str(row[1]):
				g["hp"] = row[2]
				g["off"] = row[3]
	loose.clear()
	var pieces: Array = state.get("loose", [])
	for row: Array in pieces:
		var i: int = row[0]
		if i < 0 or i >= game.enemies.size():
			continue
		var e: Enemy = game.enemies[i]
		var x: float = row[2]
		var y: float = row[3]
		var z: float = row[4]
		var p := _piece(e, str(row[1]), x, y, z, 0.0, 0.0)
		p["rest"] = true
		p["turn"] = row[5]
		p["axis"] = row[6]
		p["rest_turn"] = row[7]
		loose.append(p)


## Every piece back on and none lying about (the boss checkpoint's retry).
func reset() -> void:
	loose.clear()
	for g: Dictionary in gear:
		g["off"] = false
		g["hp"] = _spec(g)["hp"]


## Pieces enemies joined later (a rematch's boss, a stand-in) have from now on.
func _fit(e: Enemy) -> void:
	if not GEAR.has(e.kind):
		return
	for g: Dictionary in gear:
		if g["e"] == e:
			return
	var table: Dictionary = GEAR[e.kind]
	var names: Array = table.keys()
	names.sort()
	for name: String in names:
		var spec: Dictionary = table[name]
		var hp: float = spec["hp"]
		gear.append({"e": e, "kind": e.kind, "name": name, "hp": hp, "off": false})


func _spec(g: Dictionary) -> Dictionary:
	var table: Dictionary = GEAR[str(g["kind"])]
	var spec: Dictionary = table[str(g["name"])]
	return spec


## Whether boss `e` has lost piece `name` (its moves ask: Jerry's helmet...).
static func lost(game: Game, e: Enemy, name: String) -> bool:
	var me: BossGearFeature = game.features.get("boss_gear")
	if me == null:
		return false
	for g: Dictionary in me.gear:
		if g["e"] == e and g["name"] == name:
			var off: bool = g["off"]
			return off
	return false


## Enemy -> the names of the pieces it has lost (game_view hands it to the 3D
## view, which leaves them off the model).
static func lost_of(game: Game) -> Dictionary:
	var out := {}
	var me: BossGearFeature = game.features.get("boss_gear")
	if me == null:
		return out
	for g: Dictionary in me.gear:
		var off: bool = g["off"]
		if off:
			var e: Enemy = g["e"]
			if not out.has(e):
				out[e] = []
			var names: Array = out[e]
			names.append(g["name"])
	return out


## A player's hit of `amount` on boss `e` at `hit` from `from` (BossKit.weak):
## what the piece it struck makes of it (armour while on, `bare` once off),
## and the piece worn by it, flying off when worn out. 1.0 when it struck no
## piece.
func struck(e: Enemy, hit: Vector3, from: Vector2, amount: float) -> float:
	if not game.boss_wrecks or hit == Vector3.INF or not e.alive:
		return 1.0
	for g: Dictionary in gear:
		if g["e"] != e or not _on(e, _spec(g), hit, from):
			continue
		var spec := _spec(g)
		var off: bool = g["off"]
		if off:
			var bare: float = spec.get("bare", 1.0)
			return bare
		var armour: float = spec.get("armour", 1.0)
		var hp: float = g["hp"]
		g["hp"] = hp - amount
		if hp - amount <= 0.0:
			knock(g, from)
		return armour
	return 1.0


## Whether a hit at `hit` from `from` lands where a piece sits on `e`.
func _on(e: Enemy, spec: Dictionary, hit: Vector3, from: Vector2) -> bool:
	var tall := e.height * e.variant
	var feet: float = e.z + game.world.stand(e)
	var up := (hit.z - feet) / maxf(.1, tall)
	var band: Array = spec["z"]
	var lo: float = band[0]
	var hi: float = band[1]
	if up < lo or up > hi:
		return false
	var dx := from.x - e.x
	var dy := from.y - e.y
	var ahead := cos(e.angle) * dx + sin(e.angle) * dy
	var side := str(spec.get("side", "any"))
	if (side == "front" and ahead <= 0.0) or (side == "back" and ahead >= 0.0):
		return false
	var reach: float = spec.get("reach", 1.0)
	return Vector2(hit.x - e.x, hit.y - e.y).length() <= reach * tall + e.radius * .5


## Piece `g` comes off, flung away from (fx, fy).
func knock(g: Dictionary, from: Vector2) -> void:
	var off: bool = g["off"]
	if off:
		return
	g["off"] = true
	g["hp"] = 0.0
	var e: Enemy = g["e"]
	var spec := _spec(g)
	var at: Array = spec["at"]
	var tall := e.height * e.variant
	var ahead: float = at[0]
	var right: float = at[1]
	var up: float = at[2]
	var fx := cos(e.angle)
	var fy := sin(e.angle)
	# The boss's right is its heading turned a quarter clockwise on the map.
	var x := e.x + (fx * ahead - fy * right) * tall
	var y := e.y + (fy * ahead + fx * right) * tall
	var z: float = e.z + game.world.stand(e) + up * tall
	var away := atan2(y - from.y, x - from.x)
	if from.distance_to(Vector2(x, y)) < .05:
		away = e.angle + PI
	var weight: float = spec.get("weight", 1.0)
	var run := FLING / sqrt(maxf(.5, weight))
	var p := _piece(e, str(g["name"]), x, y, z, cos(away) * run, sin(away) * run)
	p["vz"] = LIFT / maxf(.3, sqrt(weight))
	# It leaves facing as the boss faced (the model's turn), tumbling over
	# about the line across its flight.
	p["turn"] = e.angle - PI * .5
	p["axis"] = away + PI * .5
	loose.append(p)
	game.sound_at(str(spec.get("cue", "ricochet_tin")), x, y, 1.0)
	game.burst(x, y, z, "spark", 8, 2.4)
	var call := str(spec.get("call", ""))
	if call != "":
		game.message(call, 1.8)


## How piece `p` moves: its size against walls and the half height its
## middle rests at over the floor (bosses.cfg "half", of the boss's height).
func _feel_of(p: Dictionary) -> Tumble.Feel:
	var e: Enemy = p["e"]
	var key := "%s:%s" % [e.kind, p["name"]]
	var feel: Tumble.Feel = _feels.get(key)
	if feel != null:
		return feel
	var table: Dictionary = GEAR.get(e.kind, {})
	var spec: Dictionary = table.get(str(p["name"]), {})
	var tall := e.height * e.variant
	var half: float = spec.get("half", .05)
	var wide: float = spec.get("wide", .1)
	feel = Tumble.Feel.new(clampf(wide * tall, .06, .5), .35, .28, 3.2)
	feel.lift = half * tall
	feel.climb = .1
	feel.hard = 1.6
	_feels[key] = feel
	return feel


func _piece(
	e: Enemy, name: String, x: float, y: float, z: float, vx: float, vy: float
) -> Dictionary:
	return {
		"e": e,
		"name": name,
		"x": x,
		"y": y,
		"z": z,
		"vx": vx,
		"vy": vy,
		"vz": 0.0,
		"rest": false,
		"born": game.clock,
		"turn": 0.0,
		"axis": 0.0,
		"rest_turn": 0.0,
	}


func _tick(dt: float) -> void:
	if gear.is_empty():
		for e: Enemy in game.enemies:
			_fit(e)
		if gear.is_empty():
			return
	if game.boss_wrecks:
		_falls()
	for p: Dictionary in loose:
		var resting: bool = p["rest"]
		if resting:
			continue
		var feel := _feel_of(p)
		var hit := Tumble.step(game.world, p, feel, dt)
		if hit & Tumble.FLOOR:
			var px: float = p["x"]
			var py: float = p["y"]
			game.sound_at("tnt_bounce", px, py, .6)
		var born: float = p["born"]
		if hit & Tumble.RESTED or game.clock - born > 6.0:
			p["rest"] = true
			p["vx"] = 0.0
			p["vy"] = 0.0
			p["vz"] = 0.0
			var rx: float = p["x"]
			var ry: float = p["y"]
			var rz: float = p["z"]
			p["z"] = Tumble.floor_at(game.world, rx, ry, rz - feel.lift, feel.radius) + feel.lift
			# It lies the right way up or upside down, as it fell.
			var age := game.clock - born
			p["rest_turn"] = snappedf(age * SPIN, PI)


## Pieces that come off by themselves as the boss is beaten.
func _falls() -> void:
	for g: Dictionary in gear:
		var off: bool = g["off"]
		if off:
			continue
		var spec := _spec(g)
		var falls: float = spec.get("falls", 0.0)
		var e: Enemy = g["e"]
		if falls <= 0.0 or not e.alive or e.max_hp <= 0.0 or e.hp / e.max_hp > falls:
			continue
		# Thrown off behind it as it goes.
		knock(g, Vector2(e.x + cos(e.angle) * 2.0, e.y + sin(e.angle) * 2.0))


func sprites() -> Array:
	var out: Array = []
	for p: Dictionary in loose:
		var px: float = p["x"]
		var py: float = p["y"]
		if not game.in_view(px, py, 1.0):
			continue
		var pz: float = p["z"]
		var s := View.Sprite.new(px, py, "fx_chips", .2, pz)
		s.who = p["e"]
		s.gear = str(p["name"])
		var heading: float = p["turn"]
		var axis_at: float = p["axis"]
		var axis := Vector3(cos(axis_at), sin(axis_at), 0.0)
		var resting: bool = p["rest"]
		var over: float = p["rest_turn"]
		if not resting:
			var born: float = p["born"]
			over = (game.clock - born) * SPIN
		# Map axes, z up: turned to its heading, then over about its axis.
		s.turn = Basis(axis, over) * Basis(Vector3(0, 0, 1), heading)
		out.append(s)
	return out
