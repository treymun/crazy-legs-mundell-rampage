## Locked in with the boss (bosses.cfg [boss_lock]; docs/dev/bosses.md
## "Locked in"). A boss fight begins only once someone stands
## BossFight.DEPTH past every way into the boss's room with the boss awake
## (features/boss_fight.gd); that moment every way in shuts:
##   the level's doors on the sheet swing shut and hold: USE says why, and
##     nothing opens them while the boss lives (a kick, a station, a trigger,
##     a blast: each is shut again the next tick);
##   a gap with no door in it (the rodeo's chute gate) gets a gate, wall rows
##     in LevelData.lock_walls drawn with the doors;
##   every cell a door or a gate stands in is solid while it lives: to bodies,
##     shots, sight, thrown things, ragdolls, wrecks, fire and vehicles alike;
##   a fence on the room's edge shot through stands shut as a gate too.
## Anyone up outside the shut-in ground (the room; the bayou's whole bank, its
## bridges up) is brought in to the sheet's spot, off a vehicle first: the
## fair choice in co-op (nobody is left outside, nobody holds the fight up),
## and a partner who comes back to life outside is brought in the same way.
## The boss down, the doors that stood open swing open again and the gates
## go (a door that stood shut, the escape hatch say, is left to what opens
## it). The boss checkpoint's retry opens it all (reset(): the player back at
## the door, the arena as before the fight); it shuts again as they walk in.
##
## Play: no dice. Carried (SIM_FEATURES) and a fact (FACT_FEATURES):
## restore() puts this machine's world in step (the solid cells, the gates,
## the held doors) on a copy or a loaded save; what it put there is its own
## (the underscored fields, SnapCodec.SKIP_FIELDS).
extends GameFeature

const BossFightFeature := preload("res://src/features/boss_fight.gd")
const WallBreaksFeature := preload("res://src/features/wall_breaks.gd")
const VehiclesFeature := preload("res://src/features/vehicles.gd")

## The boss kind whose arena is shut ("" none).
var kind := ""
## The level's doors in its way, by their place in the level's list ->
## whether each stood open as it shut (those swing open again).
var before := {}

## This machine's world: the kind shut on it; each cell made solid -> what it
## was; the clear-sight bytes cleared -> what they were; the doors held ->
## whether they were remote doors already; the gates standing; the fence
## cells on the room's edge; the shut-in ground (a byte a cell).
var _applied := ""
var _solid := {}
var _clear := {}
var _held := {}
var _gates: Array[Vector2i] = []
var _edge: Array[Vector2i] = []
var _ground := PackedByteArray()
## The lockable bosses' kinds on this level.
var _kinds: Array[String] = []


func id() -> String:
	return "boss_lock"


func attach() -> void:
	for title: String in Enemy.BOSS_TITLES:
		if not BossFight.lock_of(game, title).is_empty():
			_kinds.append(title)
	if not _kinds.is_empty():
		game.events.ticked.connect(_tick)


func save() -> Dictionary:
	if kind == "":
		return {}
	var doors := {}
	for i: int in before:
		doors[str(i)] = before[i]
	return {"kind": kind, "before": doors}


func restore(state: Dictionary) -> void:
	kind = str(state.get("kind", ""))
	if BossFight.lock_of(game, kind).is_empty():
		kind = ""
	before = {}
	var rows: Variant = state.get("before", {})
	if kind != "" and rows is Dictionary:
		var by_door: Dictionary = rows
		for key: Variant in by_door:
			var stood_open: bool = by_door[key] == true
			before[int(str(key))] = stood_open
	_sync()


## Whether `kind`'s arena is shut now.
func shut_now() -> bool:
	return kind != ""


## Whether (x, y) is on the shut-in ground (false when nothing is shut).
func inside(x: float, y: float) -> bool:
	var w := game.world
	if _applied == "" or x < 0.0 or y < 0.0 or x >= w.width or y >= w.height:
		return false
	return _ground.size() == w.width * w.height and _ground[int(y) * w.width + int(x)] != 0


## The fight again from the boss checkpoint's door (BossDoor.at_door): the
## doors as they stood before it shut, the gates gone; it shuts again as the
## player walks in.
func reset() -> void:
	var doors := game.world.doors
	for i: int in before:
		var stood_open: bool = before[i]
		if stood_open and i < doors.size():
			var door: LevelData.Door = doors[i]
			door.opened = true
			door.progress = 1.0
	kind = ""
	before = {}
	_sync()


# ------------------------------------------------------------------ the tick


func _tick(_dt: float) -> void:
	if game.in_hub:
		return
	for title: String in _kinds:
		_keep_in(BossFight.of_kind(game, title))
	if kind != "":
		_hold()
		return
	for title: String in _kinds:
		var e := BossFight.of_kind(game, title)
		if e == null or not e.alive or e.dormant or not BossKit.party_started(game, e):
			continue
		if not e.alerted:
			# Walked well in on it: it knows.
			var q := _starter(e)
			e.wake(game, q.x, q.y)
			continue
		var fight: BossFightFeature = game.features.get("boss_fight")
		if fight == null or fight.met.has(title):
			_shut(e)
			return


## A boss keeps to its room, shut or not: one that has stepped out of it (into
## a doorway after the player, a charge through a gate, a shove) is set back on
## the nearest floor of it. No fight is ever had outside its arena.
func _keep_in(e: Enemy) -> void:
	if e == null or not e.alive or BossFight.in_room(game, e.kind, e.x, e.y):
		return
	var w := game.world
	var inset := minf(e.radius, .45)
	var best := Vector2.INF
	for cy in range(int(e.y) - 3, int(e.y) + 4):
		for cx in range(int(e.x) - 3, int(e.x) + 4):
			if not BossFight.in_room(game, e.kind, cx + .5, cy + .5):
				continue
			var at := Vector2(
				clampf(e.x, cx + inset, cx + 1.0 - inset), clampf(e.y, cy + inset, cy + 1.0 - inset)
			)
			if w.blocked(at.x, at.y, e.radius):
				continue
			if (
				best == Vector2.INF
				or at.distance_to(Vector2(e.x, e.y)) < best.distance_to(Vector2(e.x, e.y))
			):
				best = at
	if best != Vector2.INF:
		e.x = best.x
		e.y = best.y


## The first one up standing where `e`'s fight starts.
func _starter(e: Enemy) -> Player:
	for q: Player in game.players:
		if q.health > 0 and BossFight.started_at(game, e, q.x, q.y):
			return q
	return game.player


## Its fight began: every way in shuts and anyone outside is brought in.
func _shut(e: Enemy) -> void:
	kind = e.kind
	before = {}
	var w := game.world
	var held := BossFight.lock_doors(game, kind)
	for i in w.doors.size():
		var door: LevelData.Door = w.doors[i]
		if held.has(door):
			before[i] = door.opened
	_sync()
	for door: LevelData.Door in held:
		if door.opened:
			game.toggle_door(door, false)
	for cell: Vector2i in _gates:
		game.sound_at("gate", cell.x + .5, cell.y + .5, .9)
	game.shake = minf(1.0, game.shake + .15)
	game.message("SLAM! THE WAY OUT'S SHUT TILL THE BOSS IS DOWN.", 3.0)
	_pull_in()


## While it lives: the doors held shut, a fence shot through on the edge
## gated, anyone outside brought in. Once it is down, all of it opens.
func _hold() -> void:
	var e := BossFight.of_kind(game, kind)
	if e == null or not e.alive:
		_open()
		return
	for door: LevelData.Door in BossFight.lock_doors(game, kind):
		if door.opened:
			door.opened = false
	var w := game.world
	var more := false
	for cell: Vector2i in _edge:
		var c := cell.y * w.width + cell.x
		if w.solid[c] < 0 and not _solid.has(c):
			_gate(cell)
			more = true
	if more:
		_draw()
		_shut_paths()
		_clear_bodies()
	_pull_in()


## The boss is down: the doors that stood open swing open, the gates go.
func _open() -> void:
	var doors := game.world.doors
	for i: int in before:
		var stood_open: bool = before[i]
		if stood_open and i < doors.size():
			game.toggle_door(doors[i], true)
	for cell: Vector2i in _gates:
		game.sound_at("gate", cell.x + .5, cell.y + .5, .9)
	kind = ""
	before = {}
	_sync()


# ------------------------------------------------------------------ the world


## This machine's world put in step with `kind`.
func _sync() -> void:
	if _applied == kind:
		return
	if _applied != "":
		_unapply()
	if kind != "":
		_apply()


func _apply() -> void:
	var w := game.world
	var tile := w.tile_id(str(BossData.get_value("boss_lock", "gate_tile")))
	for door: LevelData.Door in BossFight.lock_doors(game, kind):
		var at := Vector2i(door.x, door.y)
		_make_solid(at, door.material if door.material >= 0 else tile)
		if not _held.has(at):
			_held[at] = w.controlled_doors.has(at)
		w.controlled_doors[at] = "boss"
	for cell: Vector2i in BossFight.gate_cells(game, kind):
		_gate(cell)
	_applied = kind
	_ground = _shut_in()
	_edge = _edge_fences()
	for cell: Vector2i in _edge:
		if w.solid[cell.y * w.width + cell.x] < 0:
			_gate(cell)
	_draw()
	w.solid_version += 1
	_shut_paths()
	_clear_bodies()


func _unapply() -> void:
	var w := game.world
	for c: int in _solid:
		var was: int = _solid[c]
		w.solid[c] = was
	for c: int in _clear:
		var clear: int = _clear[c]
		w.clear_cells[c] = clear
	for at: Vector2i in _held:
		var remote: bool = _held[at]
		if remote:
			w.controlled_doors[at] = true
		else:
			w.controlled_doors.erase(at)
	w.lock_walls = PackedFloat32Array()
	w.solid_version += 1
	_solid = {}
	_clear = {}
	_held = {}
	_gates = []
	_edge = []
	_ground = PackedByteArray()
	_applied = ""
	for f: FlowField in _fields():
		f.origin = Vector2i(-1, -1)
		f.next_at = 0.0
	game.route_sig = []


## A cell made solid with `tile` (what it was kept), and the clear-sight
## shortcut off round it (LevelSight takes it as open floor).
func _make_solid(at: Vector2i, tile: int) -> void:
	var w := game.world
	if at.x < 0 or at.y < 0 or at.x >= w.width or at.y >= w.height:
		return
	var c := at.y * w.width + at.x
	if not _solid.has(c):
		_solid[c] = w.solid[c]
	if w.solid[c] < 0:
		w.solid[c] = maxi(0, tile)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := at.x + dx
			var ny := at.y + dy
			if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height:
				continue
			var n := ny * w.width + nx
			if not _clear.has(n):
				_clear[n] = w.clear_cells[n]
			w.clear_cells[n] = 0


## A gate stands in an open cell.
func _gate(at: Vector2i) -> void:
	if _gates.has(at):
		return
	var w := game.world
	_make_solid(at, w.tile_id(str(BossData.get_value("boss_lock", "gate_tile"))))
	_gates.append(at)


## The gates' faces, toward every open cell beside them (LevelEdit.EDGES: a
## face shows on its left), a gate high over the ground.
func _draw() -> void:
	var w := game.world
	var tile := float(w.tile_id(str(BossData.get_value("boss_lock", "gate_tile"))))
	var top: float = BossData.get_value("boss_lock", "gate_top")
	var rows := PackedFloat32Array()
	for at: Vector2i in _gates:
		var c := at.y * w.width + at.x
		for e: Array in LevelEdit.EDGES:
			var ex: int = e[0]
			var ey: int = e[1]
			var nx := at.x + ex
			var ny := at.y + ey
			if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height:
				continue
			var n := ny * w.width + nx
			var wall: int = _solid.get(n, w.solid[n])
			if _gates.has(Vector2i(nx, ny)) or wall >= 0:
				continue
			var ax: int = e[2]
			var ay: int = e[3]
			var bx: int = e[4]
			var by: int = e[5]
			(
				rows
				. append_array(
					PackedFloat32Array(
						[
							at.x + ax,
							at.y + ay,
							at.x + bx,
							at.y + by,
							tile,
							snappedf(w.light[n] * (1.0 if ex == 0 else .83), .0001),
							minf(w.ground[n], w.ground[c]),
							w.ground[c] + top,
							float(w.area[n]),
						]
					)
				)
			)
	w.lock_walls = rows


## The ground the shut arena keeps: its room, or (`flood`) every open cell the
## room reaches with the doors and gates shut (deep water only in the room).
func _shut_in() -> PackedByteArray:
	var w := game.world
	var ground := BossFight.room_of(game, kind).duplicate()
	var size := w.width * w.height
	if ground.size() != size or not BossFight.lock_of(game, kind).get("flood", false):
		return ground
	var todo := PackedInt32Array()
	for c in size:
		if ground[c] != 0:
			todo.append(c)
	while not todo.is_empty():
		var c := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		if w.deep_at(c % w.width + .5, c / w.width + .5):
			# Nobody wades out of the deep: the king's water joins no shore.
			continue
		for step: int in [1, -1, w.width, -w.width]:
			var n := c + step
			if n < 0 or n >= size or ground[n] != 0 or absi(n % w.width - c % w.width) > 1:
				continue
			if w.solid[n] >= 0 and not w.door_cells.has(n):
				continue
			if _solid.has(n):
				continue
			var nx := n % w.width + .5
			var ny := n / w.width + .5
			if w.deep_at(nx, ny) and not w.over_deep(nx, ny):
				continue
			ground[n] = 1
			todo.append(n)
	return ground


## The breakable fence cells on the shut-in ground's edge (an open cell of it
## on one side, open floor outside it on another).
func _edge_fences() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var breaks: WallBreaksFeature = game.features.get("wall_breaks")
	if breaks == null:
		return out
	var w := game.world
	for key: Variant in breaks.fences:
		var cell: Vector2i = key
		var keeps := false
		var leaves := false
		for e: Array in LevelEdit.EDGES:
			var ex: int = e[0]
			var ey: int = e[1]
			var nx := cell.x + ex
			var ny := cell.y + ey
			if nx < 0 or ny < 0 or nx >= w.width or ny >= w.height:
				continue
			var n := ny * w.width + nx
			var wall: int = _solid.get(n, w.solid[n])
			if _ground[n] != 0:
				keeps = true
			elif wall < 0:
				leaves = true
		if keeps and leaves:
			out.append(cell)
	return out


## Every flow field asks again at the shut cells (a door's cell already does).
func _shut_paths() -> void:
	for f: FlowField in _fields():
		for c: int in _solid:
			if c < f.open.size() and f.open[c] == 1:
				f.open[c] = 2
		f.origin = Vector2i(-1, -1)
		f.next_at = 0.0
	game.route_sig = []


func _fields() -> Array[FlowField]:
	var out: Array[FlowField] = []
	for p: Player in game.players:
		if p.flow != null and not out.has(p.flow):
			out.append(p.flow)
	if game.route != null and not out.has(game.route):
		out.append(game.route)
	return out


## Nobody left standing in a cell that just went solid: each body is put
## beside it, on the side it stood.
func _clear_bodies() -> void:
	for e: Enemy in game.enemies:
		if e.alive and _caught(e.x, e.y, e.radius):
			var spot := _beside(e.x, e.y, e.radius)
			e.x = spot.x
			e.y = spot.y
	for q: Player in game.players:
		if q.health > 0 and _caught(q.x, q.y, GameState.PLAYER_RADIUS):
			var spot := _beside(q.x, q.y, GameState.PLAYER_RADIUS)
			q.x = spot.x
			q.y = spot.y


## Whether a body of `radius` at (x, y) overlaps a cell the lock made solid.
func _caught(x: float, y: float, radius: float) -> bool:
	var w := game.world
	for c: int in _solid:
		var was: int = _solid[c]
		if was >= 0:
			continue
		var cx := float(c % w.width)
		var cy := float(c / w.width)
		if x + radius > cx and x - radius < cx + 1.0 and y + radius > cy and y - radius < cy + 1.0:
			return true
	return false


## The nearest point to (x, y), out a step at most, where a body of `radius`
## clears the shut cells; (x, y) itself when nothing near does.
func _beside(x: float, y: float, radius: float) -> Vector2:
	var w := game.world
	for reach: float in [.15, .3, .45, .6, .8, 1.0, 1.25]:
		for k in 8:
			var a := k * TAU / 8.0
			var at := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if not w.blocked(at.x, at.y, radius):
				return at
	return Vector2(x, y)


# ------------------------------------------------------------------ bringing in


## Anyone up outside the shut-in ground is brought in.
func _pull_in() -> void:
	for q: Player in game.players:
		if q.health > 0 and not inside(q.x, q.y):
			_bring(q)


## Off any vehicle, then to the sheet's spot (the nearest open floor of the
## room to it), facing the boss.
func _bring(q: Player) -> void:
	var rides: VehiclesFeature = game.features.get("vehicles")
	if rides != null and rides.seated(q):
		var seat := rides.seat_of(q)
		var ride: VehicleDrive.Ride = rides.rides[seat.x]
		ride.seats[seat.y] = -1
		if seat.y == 0:
			q.armory.holstered = false
	var spot := _spot(q)
	var boss := BossFight.of_kind(game, kind)
	var face := q.angle
	if boss != null:
		face = atan2(boss.y - spot.y, boss.x - spot.x)
	Modes.place(game, q, spot.x, spot.y, face)
	q.floor_z = game.world.elevation(spot.x, spot.y)
	q.ladder = -1
	q.climb_time = 0.0
	if q == game.local_player:
		game.message("HAULED IN. THE ARENA'S SHUT TILL THE BOSS IS DOWN.", 2.5)


## Open floor in the room near the sheet's spot that no one else stands on.
func _spot(q: Player) -> Vector2:
	var w := game.world
	var sheet := BossFight.lock_of(game, kind)
	var spot: Array = sheet.get("spot", [0.0, 0.0])
	var sx: float = spot[0]
	var sy: float = spot[1]
	for reach: float in [0.0, .8, 1.6, 2.4, 3.2, 4.0, 5.0]:
		for k in 12 if reach > 0.0 else 1:
			var a := k * TAU / 12.0
			var at := Vector2(sx + cos(a) * reach, sy + sin(a) * reach)
			if not BossFight.in_room(game, kind, at.x, at.y):
				continue
			if w.blocked(at.x, at.y, GameState.PLAYER_RADIUS + .05) or w.deep_at(at.x, at.y):
				continue
			var taken := false
			for other: Player in game.players:
				if other != q and Vector2(other.x, other.y).distance_to(at) < .8:
					taken = true
			if not taken:
				return at
	return Vector2(sx, sy)
