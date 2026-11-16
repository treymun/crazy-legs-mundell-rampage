## Set pieces built round the vehicles (feature pass 7): a run against the
## clock through gates in order, started by driving the right vehicle through
## its start (a level's "vehicle_runs", from its plan's meta). Gator Bayou's
## CHANNEL RUN takes the airboat from the dock out round both forks of the
## Big Channel and up into the king's lagoon with his boys after it; Buzzard
## Bend's HEAT RACE is three laps of the oval in the stock car, to beat the
## Boggs boys still lapping in their race cars (their time for three laps, or
## the run's own `time` once they have run dry) with the pit crew coming out
## onto the track. The hands a run wakes are held back by a level trigger
## whose "when" is {"run": id} (src/triggers.gd): they come when it starts.
## Optional and once: made in time, everyone in the vehicle takes its
## `reward` (game.collect) and the chapter's tally shows the time; run out
## of time, get out or wreck it and it can be started again once the vehicle
## has left the start.
##
## Play: plain numbers in parallel lists (a simulation feature, carried in
## snapshots and saved), no dice. Its flares on the next gate, the plate with
## the clock and the pin's goal are looks.
##
## A run in the level's list:
##   {"id", "title", "kind" (the vehicle), "start": [x, y, r, name],
##    "way": [x, y] (the start counts only heading that way; optional),
##    "gates": [[x, y, r, name], ...] in order (one lap's; the last is the goal),
##    "laps", "time" (seconds), "pace" (true: the lap cars' time for the laps
##    while they still run), "reward": [pickup names],
##    "intro", "won" (%s: the time), "lost" lines}
extends GameFeature

const READY := 0
const RUNNING := 1
const DONE := 2
## The clock turns red with this little left (seconds).
const LATE := 10.0
## The plate's size, and its corner: the view's top right, across from the
## driving plate (src/vehicle_hud.gd), clear of the touch buttons.
const W := 84
const H := 27
const PLATE := Vector2i(View.WIDTH - W - 4, 36)
## A flare's glow and the smoke off it.
const FLARE := "fx_flare"
const PUFFS := 4

## The runs (the level's list, the same everywhere).
var defs: Array[Dictionary] = []
## For each run: READY, RUNNING or DONE; the next gate (counting on round the
## laps); when it started; its time limit; the ride it is run in and the
## slot at its wheel; whether it may start (the vehicle has left the start
## since it was last tried); how long the winning run took; how many tries.
var status := PackedInt32Array()
var gate := PackedInt32Array()
var began := PackedFloat64Array()
var limit := PackedFloat64Array()
var ride := PackedInt32Array()
var driver := PackedInt32Array()
var armed := PackedInt32Array()
var best := PackedFloat64Array()
var tries := PackedInt32Array()


func id() -> String:
	return "vehicle_runs"


func attach() -> void:
	if game.in_hub:
		return
	for row: Variant in game.level.vehicle_runs:
		if not row is Dictionary:
			continue
		var run: Dictionary = row
		defs.append(run)
		status.append(READY)
		gate.append(0)
		began.append(0.0)
		limit.append(0.0)
		ride.append(-1)
		driver.append(-1)
		armed.append(1)
		best.append(0.0)
		tries.append(0)
	if defs.is_empty():
		return
	tick_with(_tick)


func _rides() -> Array:
	var cars: GameFeature = game.features.get("vehicles")
	if cars == null or not cars.call("active"):
		return []
	return cars.get("rides")


## The first ride of `kind` (-1 when the level has none).
func _ride_of(kind: String) -> int:
	var list := _rides()
	for k in list.size():
		var v: VehicleDrive.Ride = list[k]
		if v.kind == kind:
			return k
	return -1


func _tick(_dt: float) -> void:
	var list := _rides()
	if list.is_empty() or game.revisiting:
		return
	for i in defs.size():
		var d: Dictionary = defs[i]
		var state: int = status[i]
		if state == DONE:
			continue
		if state == READY:
			var k := _ride_of(str(d.get("kind", "")))
			if k < 0:
				continue
			var v: VehicleDrive.Ride = list[k]
			var start: Array = d["start"]
			var inside := _near(v, start)
			if not inside:
				armed[i] = 1
			elif armed[i] == 1 and v.wreck < 0.0 and v.seats[0] >= 0 and _going(v, d):
				_start(i, k, v)
			continue
		var at: int = ride[i]
		var run_ride: VehicleDrive.Ride = list[at]
		if run_ride.wreck >= 0.0:
			_lose(i, run_ride, "THE RIG'S DONE FOR. SO'S THE RUN.")
		elif run_ride.seats[0] != driver[i]:
			_lose(i, run_ride, "NOBODY AT THE WHEEL. RUN'S OFF.")
		elif game.clock - began[i] > limit[i]:
			_lose(i, run_ride, str(d.get("lost", "TOO SLOW. RUN'S OFF.")))
		else:
			_gates(i, d, run_ride)


## Where a [x, y, ...] spot is.
static func _at(spot: Array) -> Vector2:
	var x: float = spot[0]
	var y: float = spot[1]
	return Vector2(x, y)


## Whether `v` is inside a [x, y, r, ...] circle.
static func _near(v: VehicleDrive.Ride, spot: Array) -> bool:
	var x: float = spot[0]
	var y: float = spot[1]
	var r: float = spot[2]
	return Vector2(v.x - x, v.y - y).length() < r


## Whether `v` comes through the start on the move, the way the run goes.
static func _going(v: VehicleDrive.Ride, d: Dictionary) -> bool:
	if VehicleDrive.speed(v) < 1.0:
		return false
	var way: Array = d.get("way", [])
	if way.is_empty():
		return true
	var wx: float = way[0]
	var wy: float = way[1]
	return Vector2(v.vx, v.vy).normalized().dot(Vector2(wx, wy).normalized()) > .3


func _start(i: int, k: int, v: VehicleDrive.Ride) -> void:
	var d: Dictionary = defs[i]
	status[i] = RUNNING
	gate[i] = 0
	began[i] = game.clock
	ride[i] = k
	driver[i] = v.seats[0]
	armed[i] = 0
	tries[i] = tries[i] + 1
	limit[i] = _limit(d)
	game.sound_at("honk", v.x, v.y, 1.0)
	_say(v, str(d.get("intro", "GO!")), 3.5)


## The time a run is given: its own `time`, or the lap cars' for its laps
## while they still run (`pace`).
func _limit(d: Dictionary) -> float:
	var own: float = d.get("time", 60.0)
	if not d.get("pace", false):
		return own
	var laps_feature: GameFeature = game.features.get("race_laps")
	if laps_feature == null or laps_feature.get("dry"):
		return own
	var total: float = laps_feature.get("total")
	var spec: Dictionary = laps_feature.get("spec")
	var speed: float = spec.get("speed", 8.0)
	var laps: int = d.get("laps", 1)
	return snappedf(total * laps / maxf(1.0, speed), .1) if total > 0.0 else own


func _gates(i: int, d: Dictionary, v: VehicleDrive.Ride) -> void:
	var gates: Array = d["gates"]
	var laps: int = d.get("laps", 1)
	var next: int = gate[i]
	var spot: Array = gates[next % gates.size()]
	if not _near(v, spot):
		return
	next += 1
	gate[i] = next
	if next >= gates.size() * laps:
		_win(i, d, v)
		return
	game.sound_at("fair_bell", v.x, v.y, .8)
	if laps > 1 and next % gates.size() == 0:
		_say(v, "LAP %d OF %d" % [next / gates.size() + 1, laps], 1.6)


func _win(i: int, d: Dictionary, v: VehicleDrive.Ride) -> void:
	status[i] = DONE
	var took := game.clock - began[i]
	best[i] = took
	game.sound_at("yee_haw", v.x, v.y, 1.0)
	var reward: Array = d.get("reward", [])
	for slot: int in v.seats:
		var q := _player(slot)
		if q == null:
			continue
		game.focus(q)
		for item: Variant in reward:
			game.collect(str(item))
		game.focus(game.local_player)
	var line := str(d.get("won", "MADE IT IN %s."))
	_say(v, line % _clock(took) if line.contains("%s") else line, 4.5)


func _lose(i: int, v: VehicleDrive.Ride, line: String) -> void:
	status[i] = READY
	armed[i] = 0
	game.sound_at("empty", v.x, v.y, .8)
	_say(v, line + " BACK TO THE START TO GO AGAIN.", 3.5)


## A line for the local player when they ride in `v`.
func _say(v: VehicleDrive.Ride, text: String, length: float) -> void:
	if v.seats.has(game.local_player.slot):
		game.message(text, length)


func _player(slot: int) -> Player:
	if slot < 0:
		return null
	for q: Player in game.players:
		if q.slot == slot:
			return q
	return null


## The run `p` is in the middle of (riding in its vehicle), or -1.
func _running_for(p: Player) -> int:
	var list := _rides()
	for i in defs.size():
		if status[i] != RUNNING:
			continue
		var at: int = ride[i]
		if at >= 0 and at < list.size():
			var v: VehicleDrive.Ride = list[at]
			if v.seats.has(p.slot):
				return i
	return -1


## The run `p` could start: at the wheel of its vehicle, ready (-1 if none).
func _open_for(p: Player) -> int:
	var list := _rides()
	for i in defs.size():
		if status[i] != READY:
			continue
		var d: Dictionary = defs[i]
		var k := _ride_of(str(d.get("kind", "")))
		if k >= 0:
			var v: VehicleDrive.Ride = list[k]
			if v.seats[0] == p.slot and v.wreck < 0.0:
				return i
	return -1


## Whether the local player is in a run now (the car's own lap timer gives
## way to its plate: features/vehicles.gd).
func live() -> bool:
	return not defs.is_empty() and _running_for(game.local_player) >= 0


## Where the objective pin points for `p`: the next gate of their run, or the
## start of the one their vehicle can run; null when neither.
func goal(p: Player) -> Variant:
	if defs.is_empty():
		return null
	var i := _running_for(p)
	if i >= 0:
		var gates: Array = defs[i]["gates"]
		var spot: Array = gates[gate[i] % gates.size()]
		return _at(spot)
	i = _open_for(p)
	if i >= 0:
		var start: Array = defs[i]["start"]
		return _at(start)
	return null


## What the objective says for `p` in the same cases ("" when neither).
func objective(p: Player) -> String:
	if defs.is_empty():
		return ""
	var i := _running_for(p)
	if i >= 0:
		var gates: Array = defs[i]["gates"]
		var spot: Array = gates[gate[i] % gates.size()]
		return "%s / %s" % [defs[i].get("title", "RUN"), str(spot[3])]
	i = _open_for(p)
	if i >= 0:
		var start: Array = defs[i]["start"]
		return "%s / START AT %s" % [defs[i].get("title", "RUN"), str(start[3])]
	return ""


## Whether run `run_id` has been started (src/triggers.gd's {"run": id}).
func started(run_id: String) -> bool:
	for i in defs.size():
		if str(defs[i].get("id", "")) == run_id and tries[i] > 0:
			return true
	return false


## Run `run_id`'s state (for the checks): READY, RUNNING, DONE, or -1.
func state_of(run_id: String) -> int:
	for i in defs.size():
		if str(defs[i].get("id", "")) == run_id:
			return status[i]
	return -1


func save() -> Dictionary:
	var any := 0
	for count: int in tries:
		any += count
	if any == 0:
		return {}
	var rows: Array = []
	for i in defs.size():
		# A run in the middle is saved as ready again: it starts over.
		var state: int = status[i]
		rows.append(
			[str(defs[i].get("id", "")), DONE if state == DONE else READY, best[i], tries[i]]
		)
	return {"runs": rows}


func restore(state: Dictionary) -> void:
	var rows: Array = state.get("runs", [])
	for row: Variant in rows:
		var r: Array = row
		for i in defs.size():
			if str(defs[i].get("id", "")) == str(r[0]):
				var was: int = r[1]
				var took: float = r[2]
				var count: int = r[3]
				status[i] = was
				best[i] = took
				tries[i] = count
				gate[i] = 0
				armed[i] = 0


func tally_rows() -> Array:
	var rows: Array = []
	for i in defs.size():
		if status[i] == DONE:
			rows.append([str(defs[i].get("title", "RUN")), _clock(best[i])])
	return rows


## A time as 1:05.3.
static func _clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d.%d" % [whole / 60, whole % 60, int((seconds - whole) * 10.0)]


## A time left as 0:41.
static func _short(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]


# ------------------------------------------------------------------- looks


## The next gate's flare (and the start's, while the local player has the
## wheel of a vehicle that can run it): a burning flare on a stake with its
## smoke going up.
func sprites() -> Array:
	var out: Array = []
	for spot: Array in _flares():
		_flare(out, spot)
	return out


## [where, light] for each flare burning now (the local player's).
func _flares() -> Array:
	var out: Array = []
	if defs.is_empty():
		return out
	var p := game.local_player
	var i := _running_for(p)
	if i >= 0:
		var gates: Array = defs[i]["gates"]
		var spot: Array = gates[gate[i] % gates.size()]
		out.append([_at(spot), "run_flare"])
		return out
	i = _open_for(p)
	if i >= 0:
		var start: Array = defs[i]["start"]
		out.append([_at(start), "run_start"])
	return out


func _flare(out: Array, spot: Array) -> void:
	var at: Vector2 = spot[0]
	var x := at.x
	var y := at.y
	if not game.in_view(x, y, 1.0):
		return
	var z := game.world.floor_under(x, y, 9.0)
	var beat := .85 + .15 * sin(game.clock * 13.0 + x)
	var glow := game.pooled(x, y, FLARE, .6 * beat, z + .7)
	glow.glow = true
	out.append(glow)
	var core := game.pooled(x, y, "fx_flame_%d" % (int(game.clock * 12.0) % 4), .4, z + .55)
	core.glow = true
	out.append(core)
	for k in PUFFS:
		var phase := fposmod(game.clock * .5 + float(k) / PUFFS, 1.0)
		var puff := game.pooled(
			x + sin(k * 2.1 + phase * 3.0) * .15 + phase * .35,
			y + cos(k * 1.3) * .15,
			"fx_smoke_%d" % mini(3, int(phase * 4.0)),
			.35 + phase * .7,
			z + .8 + phase * 2.0
		)
		puff.translucent = true
		out.append(puff)


## The flares' light (view_lights.gd).
func lights(_p: Player) -> Array:
	var out: Array = []
	for spot: Array in _flares():
		var at: Vector2 = spot[0]
		var z := game.world.floor_under(at.x, at.y, 9.0) + .6
		var l: Variant = Effects.light(str(spot[1]), at.x, at.y, z, 1.0, game.clock)
		if l != null:
			out.append(l)
	return out


## The run's plate across from the driving plate: its name, the time left
## (red at the end), the gate or the lap, and where to next.
func draw_view(c: Canvas) -> void:
	if defs.is_empty():
		return
	var i := _running_for(game.local_player)
	if i < 0:
		return
	var d: Dictionary = defs[i]
	var gates: Array = d["gates"]
	var laps: int = d.get("laps", 1)
	var left := maxf(0.0, limit[i] - (game.clock - began[i]))
	var late := left < LATE and int(game.clock * 4.0) % 2 == 0
	var next: int = gate[i]
	var count := (
		"LAP %d/%d" % [mini(laps, next / gates.size() + 1), laps]
		if laps > 1
		else "GATE %d/%d" % [mini(gates.size(), next + 1), gates.size()]
	)
	var spot: Array = gates[next % gates.size()]
	if game.hud.minimal:
		var line := "%s  %s" % [_short(left), count]
		HUD.text(c, line, View.WIDTH - 6, VehicleHud.AT.y, "mini", HUD.INK, false, true, true)
		return
	var x := PLATE.x
	var y := PLATE.y
	c.panel(x, y, W, H, VehicleHud.FACE, VehicleHud.EDGE)
	HUD.text(c, str(d.get("title", "RUN")), x + 4, y + 3, "mini", HUD.AMBER, false, false)
	HUD.text(c, count, x + W - 4, y + 3, "mini", HUD.INK, false, false, true)
	HUD.text(
		c, _short(left), x + W / 2, y + 10, "body", HUD.LOW_HOT if late else HUD.INK, true, false
	)
	HUD.text(c, str(spot[3]), x + W / 2, y + 19, "mini", HUD.DIM, true, false)
