## Mundell's junk bench (src/bench_mods.gd, data/tuning/bench.cfg): where
## the benches stand, the scrap that turns up to spend at them, and USE.
##
## - The Crossroads' bench stands in the Road Department's yard, its back to
##   the depot's wall (`hub_at`); each chapter's near where the chapter
##   starts, out of the way it starts you looking, its back to a wall on clear
##   floor where there is one, found as the chapter starts (_spot: the same on
##   every machine). It has no box of its own: a player walking into one is
##   put back out (no hand comes near the Crossroads; one in a chapter can
##   walk through it).
## - USE at a bench (within `reach`, looking at it) opens BenchScreen for this
##   machine's player; a buy comes back as Controls.buy (game.gd: every copy
##   of a networked game, and a replay, buys alike) and is taken only at a
##   bench (BenchMods.buy).
## - Scrap: a hand killed drops a piece now and then (`[drops]`, game.rng),
##   a breakable broken, a vehicle wrecked and a set piece come down drop
##   theirs, and a few pieces lie about each chapter from its start
##   (`[placed]`). A piece is a pickup (item_scrap_<piece>), taken as any
##   pickup is (game_world.gd collect: the scrap on the taker's Armory).
##
## Play, carried (a SIM feature): asleep for good where the bench is not
## live (BenchMods.on), so a game without it plays as before.
extends GameFeature

const VehiclesScript := preload("res://src/features/vehicles.gd")
const SetPieces := preload("res://src/features/set_pieces.gd")

## Live in this game (worked out on the first tick: the options and the
## mode are set after the features attach).
var live := false
var decided := false
## The chapter's loose scrap is laid out (saved: a save has it in its pickups).
var placed := false
## The benches: [x, y, facing (radians: the front looks along (sin, cos)),
## spare (false)].
var benches: Array = []
## The vehicles wrecked and set pieces down that have dropped their scrap
## (their places in their lists).
var wrecks_done: Array = []
var sets_done: Array = []
## The tick count, for the slow look at the wrecks.
var ticks := 0
## How far round a chapter's bench a body is kept (a player's radius and a hair).
const PLAYER_PAD := .2


func id() -> String:
	return "bench"


func attach() -> void:
	tick_with(_tick)
	game.events.enemy_killed.connect(_killed)
	game.events.prop_broken.connect(_broken)


func num(section: String, key: String, fallback := 0.0) -> float:
	var v: float = BenchMods.value(section, key, fallback)
	return v


func _decide() -> void:
	decided = true
	live = BenchMods.on(game)
	game.bench_live = live
	benches = []
	if not live:
		return
	if game.in_hub:
		var at: Vector2 = BenchMods.value("bench", "hub_at", Vector2.ZERO)
		benches.append([at.x, at.y, num("bench", "hub_facing"), false])
		return
	var spot := _spot()
	if not spot.is_empty():
		benches.append(spot)
	if not placed:
		placed = true
		_lay_out()


## The Crossroads' tick (game.gd: the hub runs no hands and no features):
## the bench made ready, each player's buy, the mods shown on the guns.
func hub_tick(by_slot: Array) -> void:
	if not decided:
		_decide()
	if not live:
		return
	for q: Player in game.players:
		q.armory.mods_on = true
		var c: Game.Controls = by_slot[q.slot] if q.slot < by_slot.size() else null
		if c != null and c.buy >= 0:
			buy(q, c.buy)


func _tick(_dt: float) -> void:
	if not decided:
		_decide()
	if not live:
		sleep()
		return
	ticks += 1
	_keep_out()
	if ticks % 15 == 0:
		_look_at_wrecks()


# ------------------------------------------------------------------ where


## A chapter's bench: near its start, back to a wall, on clear level floor,
## clear of pickups and quest pieces ([] when there is none).
func _spot() -> Array:
	var w := game.world
	var sx := float(game.level.spawn[0])
	var sy := float(game.level.spawn[1])
	var wide := num("bench", "width", 1.3)
	var deep := num("bench", "depth", .55)
	var near := num("bench", "near", 1.4)
	var far := num("bench", "far", 4.5)
	var ground := w.elevation(sx, sy)
	# Never in front of where the chapter starts you looking.
	var looking := float(game.level.spawn[2]) if game.level.spawn.size() > 2 else 0.0
	var clear_of := num("bench", "clear_of_view", 1.2)
	# Its back to a wall if there is one near, else standing free.
	for walled: bool in [true, false]:
		var r := near
		while r <= far + .001:
			for k in 16:
				var a := k * TAU / 16.0
				var cx := sx + sin(a) * r
				var cy := sy + cos(a) * r
				if absf(angle_difference(looking, atan2(cy - sy, cx - sx))) < clear_of:
					continue
				# Its front faces the start, its back the other way.
				var facing := atan2(sx - cx, sy - cy)
				if _fits(cx, cy, facing, wide, deep, ground, walled):
					return [cx, cy, facing, false]
			r += .25
	return []


func _fits(
	cx: float, cy: float, facing: float, wide: float, deep: float, ground: float, walled: bool
) -> bool:
	var w := game.world
	var fx := sin(facing)
	var fy := cos(facing)
	# Along its width (the right hand of its front) and its depth.
	var ax := fy
	var ay := -fx
	for i in 5:
		for j in 3:
			var u := (i / 4.0 - .5) * wide
			var v := (j / 2.0 - .5) * deep
			var px := cx + ax * u + fx * v
			var py := cy + ay * u + fy * v
			if px < 1.0 or py < 1.0 or px >= w.width - 1 or py >= w.height - 1:
				return false
			if w.blocked(px, py, .12) or absf(w.elevation(px, py) - ground) > .04:
				return false
	# A wall right behind it, all along.
	for i in 3 if walled else 0:
		var u := (i / 2.0 - .5) * wide * .8
		var bx := cx + ax * u - fx * (deep * .5 + .3)
		var by := cy + ay * u - fy * (deep * .5 + .3)
		if not w.blocked(bx, by, .05):
			return false
	# Nothing else stands or lies there.
	for entry: Array in game.pickups:
		var ex: float = entry[1]
		var ey: float = entry[2]
		if Vector2(ex - cx, ey - cy).length() < wide:
			return false
	for station: LevelData.Station in w.stations:
		if Vector2(station.x - cx, station.y - cy).length() < 2.0:
			return false
	for door: LevelData.Door in w.doors:
		if Vector2(door.x + .5 - cx, door.y + .5 - cy).length() < 1.6:
			return false
	return true


## A player walking into a chapter's bench is put back out of it.
func _keep_out() -> void:
	var wide := num("bench", "width", 1.3)
	var deep := num("bench", "depth", .55)
	for b: Array in benches:
		var cx: float = b[0]
		var cy: float = b[1]
		var facing: float = b[2]
		var fx := sin(facing)
		var fy := cos(facing)
		for p: Player in game.players:
			var dx := p.x - cx
			var dy := p.y - cy
			var u := dx * fy - dy * fx
			var v := dx * fx + dy * fy
			var hu := wide * .5 + PLAYER_PAD
			var hv := deep * .5 + PLAYER_PAD
			if absf(u) >= hu or absf(v) >= hv:
				continue
			# Out by the nearest side.
			if hu - absf(u) < hv - absf(v):
				u = hu * signf(u if u != 0.0 else 1.0)
			else:
				v = hv * signf(v if v != 0.0 else 1.0)
			p.x = cx + u * fy + v * fx
			p.y = cy - u * fx + v * fy


## The bench player `p` is at and looking at (its place in `benches`), or -1.
func at_bench(p: Player, facing_too := true) -> int:
	if not live or p.health <= 0:
		return -1
	var reach := num("bench", "reach", 1.7)
	var cone := num("bench", "facing", .9)
	var best := -1
	var best_d := INF
	for i in benches.size():
		var b: Array = benches[i]
		var bx: float = b[0]
		var by: float = b[1]
		var d := Vector2(bx - p.x, by - p.y)
		if d.length() > reach:
			continue
		if facing_too and absf(angle_difference(p.view_angle(), d.angle())) > cone:
			continue
		if d.length() < best_d:
			best_d = d.length()
			best = i
	return best


## Within `leave` of a bench (the screen stays open that far).
func near_bench(p: Player) -> bool:
	if not live or p.health <= 0:
		return false
	var leave := num("bench", "leave", 2.4)
	for b: Array in benches:
		var bx: float = b[0]
		var by: float = b[1]
		if Vector2(bx - p.x, by - p.y).length() <= leave:
			return true
	return false


## USE's prompt at a bench ("" none).
func prompt(p: Player) -> String:
	if at_bench(p) < 0:
		return ""
	return "%s: JUNK BENCH  /  SCRAP %d" % [game.use_key, p.armory.scrap]


## USE at a bench: this machine's player gets the bench screen. True when
## USE was the bench's.
func use(p: Player) -> bool:
	if at_bench(p) < 0:
		return false
	if p == game.local_player and not game.host:
		game.bench_asked = true
	return true


## A buy (Controls.buy) from player `p`: only at a bench. True when bought.
func buy(p: Player, index: int) -> bool:
	if at_bench(p, false) < 0 and not near_bench(p):
		return false
	if not BenchMods.buy(p, index):
		return false
	var m: Dictionary = BenchMods.mod(BenchMods.ids()[index])
	game.sound_at("bench_tape", p.x, p.y, .9)
	if p == game.local_player:
		game.notice = "%s TAPED ON." % str(m["label"])
		game.message_until = game.clock + 2.4
	var acting := game.player
	if acting == p:
		game.barks.say(game, "bench_buy", true)
	return true


# ------------------------------------------------------------------ scrap


## A few pieces beside the chapter's own pickups, from the far end of its list.
func _lay_out() -> void:
	var count := roundi(num("placed", "count", 3))
	var stride := maxi(1, roundi(num("placed", "stride", 5)))
	var pieces: Array = BenchMods.value("placed", "pieces", ["bolts"])
	var spots: Array = game.level.pickups
	var laid := 0
	var i := spots.size() - 1
	while laid < count and i >= 0:
		var spec: Array = spots[i]
		var x: float = spec[1]
		var y: float = spec[2]
		var lift := NAN
		if spec.size() > 3:
			lift = spec[3]
		for k in 4:
			var a := k * PI * .5 + .6
			var px := x + cos(a) * .38
			var py := y + sin(a) * .38
			if not game.world.blocked(px, py, .1):
				game.add_pickup("scrap_" + str(pieces[laid % pieces.size()]), px, py, lift)
				laid += 1
				break
		i -= stride


## Pieces dropped round (x, y), a little apart (their places from game.rng).
func drop(pieces: Array, x: float, y: float, z := NAN) -> void:
	var spread := num("scrap", "spread", .45)
	for piece: Variant in pieces:
		var a := game.rng.random() * TAU
		var r := game.rng.randf_range(.15, spread)
		var px := x + cos(a) * r
		var py := y + sin(a) * r
		if game.world.blocked(px, py, .1):
			px = x
			py = y
		game.add_pickup("scrap_" + str(piece), px, py, z)


func _killed(e: Enemy) -> void:
	if not live or not e.hostile:
		return
	if BossKit.is_boss(e):
		var loot: Array = BenchMods.value("drops", "boss", [])
		drop(loot, e.x, e.y, e.floor_z)
		return
	var kinds: Dictionary = BenchMods.value("drops", "enemy_kinds", {})
	var chance: float = kinds.get(e.kind, num("drops", "enemy_chance", .06))
	if game.rng.random() >= chance:
		return
	var pieces: Array = BenchMods.value("drops", "enemy_pieces", ["bolts"])
	var pick: Variant = game.rng.choice(pieces)
	drop([pick], e.x, e.y, e.floor_z)


func _broken(image: String, x: float, y: float, z: float) -> void:
	if not live:
		return
	var table: Dictionary = BenchMods.value("drops", "props", {})
	if not table.has(image):
		return
	var row: Array = table[image]
	var chance: float = row[0]
	if game.rng.random() < chance:
		drop([row[1]], x, y, z)


## The wrecks and the set pieces come down since last looked, each once.
func _look_at_wrecks() -> void:
	var rides: VehiclesScript = game.features.get("vehicles")
	if rides != null:
		for i in rides.rides.size():
			var v: VehicleDrive.Ride = rides.rides[i]
			if v.wreck >= 0.0 and not wrecks_done.has(i):
				wrecks_done.append(i)
				var loot: Array = BenchMods.value("drops", "vehicle", [])
				drop(loot, v.x, v.y, v.z)
	var sets: SetPieces = game.features.get("set_pieces")
	if sets != null:
		var table: Dictionary = BenchMods.value("drops", "set_pieces", {})
		for i in sets.pieces.size():
			var st: Dictionary = sets.pieces[i]
			var stage: int = st.get("stage", 0)
			if stage < SetPieces.FALLING or sets_done.has(i):
				continue
			sets_done.append(i)
			var spec := sets.spec_of(i)
			var box: Rect2 = sets._boxes[i]
			var mid := box.get_center()
			var loot: Array = table.get(str(spec.get("kind", "")), [])
			drop(loot, mid.x, mid.y)


# ------------------------------------------------------------------ looks


func sprites() -> Array:
	var out: Array = []
	if not live:
		return out
	var model := str(BenchMods.value("bench", "model", "town_junk_bench"))
	var tall := num("bench", "height", 1.75)
	for b: Array in benches:
		var x: float = b[0]
		var y: float = b[1]
		var facing: float = b[2]
		if not game.in_view(x, y, 2.0):
			continue
		var s := game.pooled(x, y, model, tall, game.world.elevation(x, y))
		s.face = facing + PropModels.PICTURE_TURN
		out.append(s)
	return out


func save() -> Dictionary:
	return {"placed": placed, "wrecks": wrecks_done.duplicate(), "sets": sets_done.duplicate()}


func restore(state: Dictionary) -> void:
	placed = state.get("placed", placed)
	var wrecks: Array = state.get("wrecks", [])
	var sets: Array = state.get("sets", [])
	wrecks_done = []
	for i: Variant in wrecks:
		var n: int = i
		wrecks_done.append(n)
	sets_done = []
	for i: Variant in sets:
		var n: int = i
		sets_done.append(n)
