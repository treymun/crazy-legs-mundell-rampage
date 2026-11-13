## The arenas of the last four bosses: what in them fights both ways, and how
## each turns on everybody in its boss's third phase (the bosses' own attacks
## are src/bosses/; the plans mark the arena in the level's boss_arena):
##   quarry      the baron's still house. His steam outlets scald him too when
##               he stands in one as it blows; in phase 3 the copper pipes burst
##               along the walls (`jets`: each a lane that warns, then roars
##               with steam, then rests) and the house's alarm lamps go red.
##   bayou       the king's lagoon. In phase 3 his holed tank trails fuel that
##               catches a breath after it hits the water: burning slicks that
##               hurt the player and the boat alike.
##   speedway    the derby bowl. In phase 3 the bowl's floodlights blow one
##               after another (`floods`) and the wrecks round the wall burn
##               (`fires`); his headlights are the light he comes by.
##   mothership  the core. In her last phase the core goes critical: the beam
##               column throbs red and every few seconds a pulse rolls out from
##               it across the deck, to be jumped, that burns Maw as well.
## Drops (drop()): what a boss throws onto marked spots (the baron's copper
## rain, the king's dynamite, Maw's hot curlers), each ring closing in until it
## lands; they hurt whoever is there, the boss too.
## The arena's own coloured lights (`lights`: a boiler's fire, the throne's
## glow) burn the whole chapter, and its valves (`steam`) curl steam.
## Nothing to save: each phase follows the boss's health; drops, slicks and
## pulses are a moment's. Looks spark off boss_fight's dice, never the game's rng.
extends GameFeature

const BOSSES := {
	"quarry": "baron", "bayou": "swamp_king", "speedway": "derby_champ", "mothership": "maw"
}
## Burst pipes: seconds a cycle, then how long each part of it lasts.
const JET_CYCLE := 4.6
const JET_WARN := .95
const JET_LIVE := 1.35
const JET_HURT := 12
const JET_SCALD := 26.0
## The baron's own outlets on him: how much one blowing under him takes off.
const OUTLET_SCALD := 30.0
## Burning slicks: how often one drops behind the boat, how long it takes to
## catch, how long it burns, how wide, what it does a touch.
const SLICK_EVERY := .55
const SLICK_CATCH := .6
const SLICK_LIFE := 6.5
const SLICK_R := .85
const SLICK_HURT := 7
const SLICK_BURN := 12.0
const SLICKS_MAX := 16
## The core's pulses: seconds between, the warning before, how fast it rolls.
const PULSE_EVERY := [4.2, 3.6, 3.2, 2.7]
const PULSE_WARN := .85
const PULSE_SPEED := 4.6
const PULSE_HURT := 13
const PULSE_BURN := 40.0
## Floodlights: seconds between one blowing and the next.
const FLOOD_GAP := .45

var level_id := ""
var boss: Enemy = null
var arena := {}
## [kind, x, y, lands_at, fuse, radius, damage, cause] still coming down.
var drops: Array = []
## How many hazards have scalded the boss since the count last started over
## (each marks itself: GameState.Hazard.scalded, carried with the hazard).
var scald_count := 0
## Burning slicks: [x, y, dropped_at].
var slicks: Array = []
var slick_next := 0.0
## Core pulses rolling out: [born, struck player, struck boss].
var pulses: Array = []
var pulse_next := -1.0
## When the third phase's change came (-1: not yet), and the floodlights blown.
var turned_at := -1.0
var floods_out := 0
var flood_boards: Array = []
## Lights the arena keeps in game.trigger_lights (changed in place).
var alarm_lights: Array = []
var head_light: Array = []
var jet_hit := {}


func id() -> String:
	return "boss_arenas"


func attach() -> void:
	level_id = String(game.level.id)
	if not BOSSES.has(level_id):
		return
	arena = game.world.boss_arena
	for e: Enemy in game.enemies:
		if e.kind == BOSSES[level_id]:
			boss = e
	if boss == null:
		return
	for spot in arena.get("floods", []):
		for board: LevelData.Billboard in game.world.billboards:
			if (
				board.image == "town_floodlight_tower"
				and absf(board.x - float(spot[0])) < .6
				and absf(board.y - float(spot[1])) < .6
			):
				flood_boards.append(board)
	for l in arena.get("lights", []):
		var c: Array = l[4]
		game.trigger_lights.append(
			[
				float(l[0]),
				float(l[1]),
				float(l[2]),
				float(l[3]),
				Color(float(c[0]), float(c[1]), float(c[2])),
				float(l[5]),
				INF
			]
		)
	game.ticked.connect(_tick)


func restore(_state: Dictionary) -> void:
	# Loaded in the third phase already: the arena as it was left, no fanfare.
	if boss != null and boss.alive and BossKit.phase_of(boss) >= 3:
		turned_at = game.clock - 30.0
		while floods_out < flood_boards.size():
			_blow_flood(floods_out, true)
			floods_out += 1


## The third phase began for `e` (BossMoves.phase_changed calls this).
func turn(e: Enemy) -> void:
	if e != boss or turned_at >= 0.0:
		return
	turned_at = game.clock
	pulse_next = game.clock + 1.2
	match level_id:
		"quarry":
			game.message("THE PIPES ARE BURSTING! WATCH THE WALLS!", 2.8)
			game.sound_at("pressure_vent", e.x, e.y, 1.0)
		"bayou":
			game.message("HIS TANK'S HOLED! THE LAGOON'S CATCHING FIRE!", 2.8)
		"speedway":
			game.message("THE FLOODLIGHTS ARE BLOWING!", 2.6)
		"mothership":
			game.message("THE CORE'S GOING CRITICAL! JUMP THE PULSES!", 3.0)
			game.sound_at(ShipAliens.cue(game, "ship_quake", "distant_quarry_blast"), e.x, e.y, 1.0)


func third() -> bool:
	return turned_at >= 0.0 and boss != null and boss.alive


## Something the boss throws, landing at (x, y) in `fuse` seconds.
func drop(
	kind: String, x: float, y: float, fuse: float, radius: float, damage: int, cause: String
) -> void:
	drops.append([kind, x, y, game.clock + fuse, fuse, radius, damage, cause])


func _tick(_dt: float) -> void:
	if boss == null:
		return
	_drops()
	_outlets()
	if not slicks.is_empty():
		_burning()
	if not third():
		_lights_off()
		return
	match level_id:
		"quarry":
			_jets()
			_alarm(Color(1.0, .25, .12), .9)
		"bayou":
			_spill()
		"speedway":
			_floods()
		"mothership":
			_pulses()
			_alarm(Color(1.0, .2, .25), 1.3)


# ------------------------------------------------------------------ drops


func _drops() -> void:
	var going: Array = []
	for d: Array in drops:
		if game.clock >= float(d[3]):
			going.append(d)
	for d: Array in going:
		drops.erase(d)
		_land(d)


func _land(d: Array) -> void:
	var kind := String(d[0])
	var x := float(d[1])
	var y := float(d[2])
	var r := float(d[5])
	var z: float = game.world.elevation(x, y)
	match kind:
		"steam":
			game.add_hazard("steam", x, y, r, 0.0, 1.1, int(d[6]))
			_sparks(x, y, z + .3, "spark", 8, 2.2)
			_sparks(x, y, z + .2, "dust", 6, 1.2)
			game.sound_at("pressure_vent", x, y, .7)
			if Vector2(boss.x - x, boss.y - y).length() < r + boss.radius:
				_burn(OUTLET_SCALD * .6, "steam")
		"curler":
			_blast(x, y, z + .3, "maw_curler")
		_:
			_blast(x, y, z + .3, "king_dynamite")


func _blast(x: float, y: float, z: float, kind: String) -> void:
	var shot := GameState.Shot.new(x, y, z, 0.0, 0.0, 0.0, kind, 0.0, true, 0)
	shot.owner = boss.get_instance_id()
	game.explode(shot)


## The boss hurt by its own arena (no weak spot: nobody aimed it).
func _burn(amount: float, how: String) -> void:
	if not boss.alive:
		return
	game.hit_point = Vector3.INF
	boss.hurt(amount, game, false, false, null, how)
	boss.hit_flash = .18


# ------------------------------------------------------------------ the quarry


## A steam hazard live on the baron's own outlet, under him: it scalds him once.
func _outlets() -> void:
	if level_id != "quarry" or not boss.alive:
		return
	for h: GameState.Hazard in game.hazards:
		if h.kind != "steam" or h.age < h.warning or h.scalded:
			continue
		if Vector2(boss.x - h.x, boss.y - h.y).length() < h.radius + boss.radius * .5:
			h.scalded = true
			scald_count += 1
			_burn(OUTLET_SCALD, "steam")
			_sparks(boss.x, boss.y, game.world.elevation(boss.x, boss.y) + 1.0, "dust", 10, 1.4)
			game.sound_at("boiler_release", boss.x, boss.y, .8)
	if scald_count > 40:
		scald_count = 0
		for h: GameState.Hazard in game.hazards:
			h.scalded = false


## Where a burst pipe is in its cycle: 0 resting, 1 warning, 2 roaring.
func jet_state(k: int) -> int:
	var t := fposmod(game.clock - turned_at - 1.0 - k * JET_CYCLE / 4.0, JET_CYCLE)
	if game.clock - turned_at < 1.0:
		return 0
	if t < JET_WARN:
		return 1
	return 2 if t < JET_WARN + JET_LIVE else 0


func _jets() -> void:
	var jets: Array = arena.get("jets", [])
	for k in jets.size():
		var j: Array = jets[k]
		var state := jet_state(k)
		var cycle := int((game.clock - turned_at - 1.0 - k * JET_CYCLE / 4.0) / JET_CYCLE)
		if state != 2:
			continue
		var key := "%d:%d" % [k, cycle]
		for p: Player in game.players:
			var mine := key + ("p" if p.slot == 0 else "p%d" % p.slot)
			if not jet_hit.has(mine) and _in_lane(j, p.x, p.y, .45) and p.air < .4:
				jet_hit[mine] = true
				game.damage(JET_HURT, [float(j[0]), float(j[1])], "STEAM", p)
		if not jet_hit.has(key + "b") and _in_lane(j, boss.x, boss.y, boss.radius):
			jet_hit[key + "b"] = true
			_burn(JET_SCALD, "steam")
		if fmod(game.clock, .3) < .02:
			game.sound_at("pressure_vent", float(j[0]), float(j[1]), .45)
	if jet_hit.size() > 64:
		jet_hit.clear()


func _in_lane(j: Array, x: float, y: float, reach: float) -> bool:
	var a := float(j[2])
	var dx := x - float(j[0])
	var dy := y - float(j[1])
	var along := dx * cos(a) + dy * sin(a)
	return along > -.2 and along < float(j[3]) and absf(dx * sin(a) - dy * cos(a)) < .55 + reach


# ------------------------------------------------------------------ the bayou


## The king's holed tank: fuel on the water behind the boat, catching.
func _spill() -> void:
	var w: LevelData = game.world
	if boss.alive and game.clock >= slick_next and BayouBrains.wet_at(w, boss.x, boss.y):
		slick_next = game.clock + SLICK_EVERY
		var behind := Vector2(boss.x - cos(boss.angle) * 1.2, boss.y - sin(boss.angle) * 1.2)
		if BayouBrains.wet_at(w, behind.x, behind.y):
			burn(behind.x, behind.y)


## Fuel or oil spilled at (x, y): it catches a breath later and burns a while
## (the king's slicks, Boggs's oil on HOG WILD).
func burn(x: float, y: float) -> void:
	if game.world.blocked(x, y, .1):
		return
	slicks.append([x, y, game.clock, -10.0, -10.0])
	if slicks.size() > SLICKS_MAX:
		slicks.pop_front()


func _burning() -> void:
	var kept: Array = []
	for s: Array in slicks:
		var age: float = game.clock - float(s[2])
		if age > SLICK_LIFE:
			continue
		kept.append(s)
		if age < SLICK_CATCH:
			continue
		var at := Vector2(float(s[0]), float(s[1]))
		# (One bite a slick at a time, whoever stands in it.)
		for p: Player in game.players:
			if (
				at.distance_to(Vector2(p.x, p.y)) < SLICK_R
				and p.air < .3
				and game.clock - float(s[3]) > .7
			):
				s[3] = game.clock
				game.damage(SLICK_HURT, [at.x, at.y], "BURNED", p)
		if (
			boss.alive
			and age > SLICK_CATCH + .5
			and at.distance_to(Vector2(boss.x, boss.y)) < SLICK_R + boss.radius * .6
			and game.clock - float(s[4]) > 1.0
		):
			s[4] = game.clock
			_burn(SLICK_BURN, "fire")
	slicks = kept


# ------------------------------------------------------------------ the speedway


func _floods() -> void:
	var since: float = game.clock - turned_at
	while floods_out < flood_boards.size() and since >= .3 + floods_out * FLOOD_GAP:
		_blow_flood(floods_out, false)
		floods_out += 1
	# His headlights: the light he comes by in the dark.
	if head_light.is_empty():
		head_light = [boss.x, boss.y, 1.0, 5.5, Color(1.0, .92, .7), 1.25, INF]
		game.trigger_lights.append(head_light)
	head_light[0] = boss.x + cos(boss.angle) * 1.4
	head_light[1] = boss.y + sin(boss.angle) * 1.4
	head_light[2] = game.world.elevation(boss.x, boss.y) + .8
	head_light[6] = INF if boss.alive else 0.0


func _blow_flood(k: int, quiet: bool) -> void:
	var board: LevelData.Billboard = flood_boards[k]
	board.glow = false
	if "lamp_boards" in game:
		game.lamp_boards.erase(board)
	if quiet:
		return
	var top: float = game.world.elevation(board.x, board.y) + board.z + board.height * .92
	_sparks(board.x, board.y, top, "spark", 26, 3.0)
	_sparks(board.x, board.y, top, "glass", 10, 2.0)
	game.sound_at("break_window", board.x, board.y, 1.0)
	game.sound_at(ShipAliens.cue(game, "arc_snap", "metal_down"), board.x, board.y, .8)
	game.blast_flash = maxf(game.blast_flash, .25)
	game.shake = minf(1.0, game.shake + .2)


# ------------------------------------------------------------------ the core


func _pulses() -> void:
	var c := _core()
	if boss.alive and pulse_next > 0.0 and game.clock >= pulse_next:
		pulse_next = game.clock + float(PULSE_EVERY[clampi(game.difficulty, 0, 3)])
		pulses.append([game.clock, false, false])
		game.shake = minf(1.0, game.shake + .35)
		game.blast_flash = maxf(game.blast_flash, .2)
		game.sound_at(ShipAliens.cue(game, "ship_quake", "distant_quarry_blast"), c.x, c.y, .9)
	var reach := float(arena.get("core_reach", 11.0))
	var kept: Array = []
	for pulse: Array in pulses:
		var r: float = (game.clock - float(pulse[0])) * PULSE_SPEED + 1.0
		if r > reach + 1.0:
			continue
		kept.append(pulse)
		# pulse[1]: the players it has struck, a bit each by slot (true: player one).
		for p: Player in game.players:
			var bit := 1 << p.slot
			var dp := Vector2(p.x, p.y).distance_to(c)
			if not (int(pulse[1]) & bit) and absf(dp - r) < .45 and p.air < .22:
				var struck: int = int(pulse[1]) | bit
				pulse[1] = true if struck == 1 else struck
				game.damage(PULSE_HURT, [c.x, c.y], "CORE PULSE", p)
		var db := Vector2(boss.x, boss.y).distance_to(c)
		if not bool(pulse[2]) and absf(db - r) < boss.radius:
			pulse[2] = true
			_burn(PULSE_BURN, "energy")
	pulses = kept


func _core() -> Vector2:
	var at = arena.get("core", null)
	if at is Array and at.size() >= 2:
		return Vector2(float(at[0]), float(at[1]))
	return Vector2(boss.x, boss.y)


func pulse_warning() -> float:
	if not third() or pulse_next < 0.0:
		return 0.0
	return clampf(1.0 - (pulse_next - game.clock) / PULSE_WARN, 0.0, 1.0)


# ------------------------------------------------------------------ lights


## The arena's alarm lamps, beating red.
func _alarm(colour: Color, strength: float) -> void:
	if alarm_lights.is_empty():
		for spot in arena.get("alarms", []):
			var l := [
				float(spot[0]), float(spot[1]), float(spot[2]), float(spot[3]), colour, 0.0, INF
			]
			alarm_lights.append(l)
			game.trigger_lights.append(l)
	var beat := .5 + .5 * sin(game.clock * 6.0)
	for l: Array in alarm_lights:
		l[5] = strength * (.25 + .75 * beat)
		l[6] = INF


func _lights_off() -> void:
	for l: Array in alarm_lights:
		l[6] = 0.0
	alarm_lights.clear()
	if not head_light.is_empty():
		head_light[6] = 0.0
		head_light = []


# ------------------------------------------------------------------ the picture


func _sparks(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	var fight = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(x, y, z, kind, count, speed)


func ground_marks() -> Array:
	var out: Array = []
	if boss == null:
		return out
	for d: Array in drops:
		out.append_array(_closing(d))
	for s: Array in slicks:
		if game.in_view(float(s[0]), float(s[1]), 1.0):
			out.append(_spot(float(s[0]), float(s[1]), SLICK_R, "mark_scorch_1"))
	if not third():
		return out
	match level_id:
		"quarry":
			var jets: Array = arena.get("jets", [])
			for k in jets.size():
				var state := jet_state(k)
				if state == 0:
					continue
				var j: Array = jets[k]
				var a := float(j[2])
				var half := float(j[3]) * .5
				var mx := float(j[0]) + cos(a) * half
				var my := float(j[1]) + sin(a) * half
				out.append(
					Renderer.GroundMark.new(
						mx,
						my,
						game.world.elevation(mx, my) + .004,
						a,
						half,
						.55 if state == 2 else .3,
						"mark_steam" if state == 2 else "mark_lane"
					)
				)
		"mothership":
			var c := _core()
			var warn := pulse_warning()
			if warn > 0.0:
				for k in 16:
					var a := k * TAU / 16.0 + warn
					var r := 2.4 - warn * .9
					out.append(_spot(c.x + cos(a) * r, c.y + sin(a) * r, .24, "mark_warning"))
			for pulse: Array in pulses:
				var r: float = (game.clock - float(pulse[0])) * PULSE_SPEED + 1.0
				var dots := int(clampf(r * 4.0, 12.0, 48.0))
				for k in dots:
					var a := k * TAU / dots
					var x := c.x + cos(a) * r
					var y := c.y + sin(a) * r
					if not game.world.blocked(x, y, .05) and game.in_view(x, y, .5):
						out.append(_spot(x, y, .3, "mark_beam"))
	return out


## A drop's warning: marks closing in on the spot, its middle filling.
func _closing(d: Array) -> Array:
	var out: Array = []
	var x := float(d[1])
	var y := float(d[2])
	if not game.in_view(x, y, 2.0):
		return out
	var t := clampf(1.0 - (float(d[3]) - game.clock) / maxf(.05, float(d[4])), 0.0, 1.0)
	var r := lerpf(float(d[5]) + .7, float(d[5]) * .6, t)
	for k in 10:
		var a := k * TAU / 10.0 + t * 1.3
		var px := x + cos(a) * r
		var py := y + sin(a) * r
		if not game.world.blocked(px, py, .05):
			out.append(_spot(px, py, .15 + .05 * t, "mark_warning"))
	out.append(_spot(x, y, .15 + float(d[5]) * .6 * t, "mark_slam"))
	return out


func _spot(x: float, y: float, r: float, image: String) -> Renderer.GroundMark:
	return Renderer.GroundMark.new(x, y, game.world.elevation(x, y) + .005, 0.0, r, r, image)


func sprites() -> Array:
	var out: Array = []
	if boss == null:
		return out
	var frame := int(game.clock * 10.0)
	for d: Array in drops:
		out.append_array(_falling(d, frame))
	out.append_array(_valves())
	for s: Array in slicks:
		var age: float = game.clock - float(s[2])
		if age < SLICK_CATCH or not game.in_view(float(s[0]), float(s[1]), 1.0):
			continue
		var fade := clampf((SLICK_LIFE - age) / 1.5, .3, 1.0)
		var fire := Renderer.Sprite.new(
			float(s[0]),
			float(s[1]),
			"fx_fire_%d" % ((frame + int(float(s[0]) * 3.0)) % 4),
			.75 * fade,
			game.world.elevation(float(s[0]), float(s[1])) - .05
		)
		fire.glow = true
		out.append(fire)
	if not third():
		return out
	match level_id:
		"quarry":
			var jets: Array = arena.get("jets", [])
			for k in jets.size():
				if jet_state(k) != 2:
					continue
				var j: Array = jets[k]
				var a := float(j[2])
				var length := float(j[3])
				var n := int(length / .9)
				for i in n:
					var along := (i + .5) * length / n
					var x := float(j[0]) + cos(a) * along
					var y := float(j[1]) + sin(a) * along
					if not game.in_view(x, y, 1.0):
						continue
					var s := Renderer.Sprite.new(
						x,
						y,
						"fx_steam_%d" % ((frame + i + k) % 4),
						.7 + along / length * .5,
						game.world.elevation(x, y) + float(j[4]) * (1.0 - along / length) + .1
					)
					s.translucent = true
					out.append(s)
		"speedway":
			for spot in arena.get("fires", []):
				var x := float(spot[0])
				var y := float(spot[1])
				if game.in_view(x, y, 1.0):
					for k in 2:
						var fire := Renderer.Sprite.new(
							x + (k - .5) * .5,
							y,
							"fx_fire_%d" % ((frame + k * 2) % 4),
							1.0 + k * .3,
							game.world.elevation(x, y) + .4
						)
						fire.glow = true
						out.append(fire)
		"mothership":
			var c := _core()
			if game.in_view(c.x, c.y, 2.0):
				var beat := .5 + .5 * sin(game.clock * (6.0 + 8.0 * pulse_warning()))
				for k in 3:
					var a: float = game.clock * 2.0 + k * TAU / 3.0
					var spark := Renderer.Sprite.new(
						c.x + cos(a) * .75,
						c.y + sin(a) * .75,
						"fx_energy_%d" % ((frame + k) % 4),
						.9 + beat * .5,
						game.world.elevation(c.x, c.y) + 1.0 + k * 1.6
					)
					spark.glow = true
					out.append(spark)
	return out


## Steam curling off the arena's valves (boss_arena: steam), always: looks only.
func _valves() -> Array:
	var out: Array = []
	var spots: Array = arena.get("steam", [])
	for k in spots.size():
		var v: Array = spots[k]
		var x := float(v[0])
		var y := float(v[1])
		if not game.in_view(x, y, 1.2):
			continue
		var floor_z: float = game.world.elevation(x, y)
		for n in 2:
			var age := fposmod(game.clock * .7 + k * .37 + n * .5, 1.0)
			var s := Renderer.Sprite.new(
				x + sin(game.clock * 1.3 + k + n) * .15 * age,
				y + cos(game.clock * 1.1 + k) * .15 * age,
				"fx_steam_%d" % mini(3, int(age * 4.0)),
				.5 + age * .9,
				floor_z + float(v[2]) + age * 1.1
			)
			s.translucent = true
			out.append(s)
	return out


## What is coming down on a drop's spot: a lit stick, a red-hot curler, a
## copper slug, falling the last part of its way.
func _falling(d: Array, frame: int) -> Array:
	var x := float(d[1])
	var y := float(d[2])
	var left: float = float(d[3]) - game.clock
	if left > .45 or not game.in_view(x, y, 1.0):
		return []
	var image := "fx_tnt_%d" % (frame % 3)
	if String(d[0]) == "curler":
		image = "fx_energy_%d" % (frame % 4)
	elif String(d[0]) == "steam":
		image = "fx_valve_slug"
	var s := Renderer.Sprite.new(x, y, image, .35, game.world.elevation(x, y) + left * 6.0)
	s.glow = String(d[0]) != "tnt"
	return [s]
