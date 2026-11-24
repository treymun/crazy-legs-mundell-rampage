## Controller rumble and phone buzz (features/rumble.gd, src/rumble_out.gd,
## data/tuning/rumble.cfg). tools/check_all.gd runs it, quick too; this also
## runs on its own:
##
##   godot --headless --path godot --script res://tools/rumble_check.gd
##
## A recorder stands in for Input's vibration calls. Every gun fires its own
## pulse and the pad gets its weak, strong and length (a crack is weak-heavy,
## a thump strong-heavy and longer, a rattle shorter than its gun's fire
## time, the rip saw's grind one held buzz); a melee blow, the dynamite's
## match and throw; a hurt by how much, leaning to the side it came from; the
## boot on a man, into the air; a blast near more than far and nothing past
## its reach; a hard landing by the drop and none for a hop; each vehicle's
## engine, faster louder, a wall struck, a wreck; the bosses' moments and a
## quake (mixed by the bigger). OFF gives nothing, LOW scales; the phone
## buzzes the strongest new pulse and never a weak one; only the local
## player's doings and hurts count; out of live play (a menu, the focus
## lost, the down screen) the pad stops and the pulses go. And play stays
## exact: a short run with RUMBLE FULL and with OFF ends in the same state,
## rng and snapshot.
extends SceneTree

const STEP := 1.0 / 60.0
const Rumble := preload("res://src/features/rumble.gd")
const BrawlCheck := preload("res://tools/brawl_check.gd")
const VehiclesScript := preload("res://src/features/vehicles.gd")


## Input's vibration calls, written down.
class Recorder:
	extends RumbleOut.Sink
	var calls: Array = []
	var pad_list: Array[int] = [0]
	var can_phone := true

	func pads() -> Array[int]:
		return pad_list

	func pad_moved(_device: int) -> bool:
		return false

	func pad(device: int, weak: float, strong: float, seconds: float) -> void:
		calls.append(["pad", device, weak, strong, seconds])

	func pad_stop(device: int) -> void:
		calls.append(["stop", device])

	func phone_can() -> bool:
		return can_phone

	func phone(ms: int, amplitude: float) -> void:
		calls.append(["phone", ms, amplitude])

	func phone_stop() -> void:
		calls.append(["phone_stop"])


var failures: Array = []
var passes := 0
var main: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	print("TUNING")
	_tuning()
	print("GUNS")
	_guns()
	print("MELEE AND DYNAMITE")
	_melee()
	print("HURT")
	_hurt()
	print("BOOT")
	_boot()
	print("BLASTS")
	_blasts()
	print("LANDING")
	_landing()
	print("VEHICLES")
	_vehicles()
	print("BOSSES AND QUAKES")
	_bosses()
	print("LEVELS AND THE PHONE")
	_levels()
	print("ONLY THE LOCAL PLAYER")
	_local_only()
	print("LIVE PLAY ONLY")
	_live()
	print("PLAY EXACT")
	_exact()
	print(
		(
			"\n%d passed, %d failed in %.1f s"
			% [passes, failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("RUMBLE CHECK FAILED" if not failures.is_empty() else "RUMBLE CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
	else:
		print("  FAIL ", text)
		failures.append(text)


func _game(level := "range") -> Game:
	var g := BrawlCheck.game(main, level)
	var r := _rumble(g)
	r.keep_made = true
	return g


func _rumble(g: Game) -> Rumble:
	return g.features["rumble"]


func _out() -> RumbleOut:
	var out := RumbleOut.new()
	out.sink = Recorder.new()
	return out


func _calls(out: RumbleOut) -> Array:
	return (out.sink as Recorder).calls


## The last pulse made, or null.
func _last(g: Game) -> Rumble.Pulse:
	var made := _rumble(g).made
	return made[-1] if not made.is_empty() else null


## The pulses made named `what` (or starting with it and ":").
func _named(g: Game, what: String) -> Array:
	var out: Array = []
	for pulse: Rumble.Pulse in _rumble(g).made:
		if pulse.what == what or pulse.what.begins_with(what + ":"):
			out.append(pulse)
	return out


func _clear(g: Game) -> void:
	var r := _rumble(g)
	r.hush()
	r.made.clear()


func _ticks(g: Game, n: int, c: Game.Controls = null) -> void:
	for i in n:
		g.tick(STEP, c if c != null else Game.Controls.new())


func _near(a: float, b: float, by := 1e-4) -> bool:
	return absf(a - b) <= by


## The pad driven at `level` from now until it is stopped (at most `most`
## seconds): [the first pad call, the seconds until the stop (-1: none)].
func _until_stop(r: Rumble, level: int, most := 3.0) -> Array:
	var out := _out()
	var first: Array = []
	var t := 0.0
	while t < most:
		out.drive(r, STEP, level, 0, "pad")
		t += STEP
		for call: Array in _calls(out):
			if call[0] == "pad" and first.is_empty():
				first = call
			if call[0] == "stop":
				return [first, t]
	return [first, -1.0]


# ------------------------------------------------------------------ tuning


func _tuning() -> void:
	var lined := true
	var missing := ""
	for i in Weapons.NAMES.size():
		var p := RumbleData.gun(i)
		if p.z <= 0.0 or maxf(p.x, p.y) <= 0.0:
			lined = false
			missing = str(Weapons.NAMES[i])
	_check(lined, "every gun in weapons.cfg has its own [guns] line %s" % missing)
	var seen := {}
	for i in Weapons.NAMES.size():
		var line := RumbleData.gun(i)
		if seen.has(line):
			missing = "%s and %s" % [seen[line], Weapons.NAMES[i]]
		seen[line] = Weapons.NAMES[i]
	_check(seen.size() == Weapons.NAMES.size(), "and no two guns feel alike %s" % missing)
	var cfg := ConfigFile.new()
	cfg.load("res://data/tuning/vehicles.cfg")
	var kinds := true
	for kind in cfg.get_sections():
		if kind != "all" and RumbleData.vehicle_section(kind) != "vehicle." + kind:
			kinds = false
			missing = kind
	_check(kinds, "every vehicle kind has its own [vehicle.<kind>] %s" % missing)
	_check(
		RumbleData.level_scale(0) == 0.0 and RumbleData.level_scale(2) == 1.0,
		"OFF scales by none, FULL by all"
	)
	_check(
		Features.LOOKS.has("rumble") and GameSnapshot.LOOKS_FEATURES.has("rumble"),
		"rumble is a looks feature (a host leaves it off)"
	)


# -------------------------------------------------------------------- guns


func _guns() -> void:
	var g := _game()
	var arms := g.armory
	var right := true
	var pads := true
	var lengths := true
	var said := ""
	for i in Weapons.NAMES.size():
		_clear(g)
		arms.active = i
		arms.last_spent = 1
		arms.grinding = false
		g.events.shot_fired.emit(i)
		var want := RumbleData.gun(i)
		var made := _last(g)
		var name := str(Weapons.NAMES[i])
		if (
			made == null
			or made.what != "gun:" + name
			or not _near(made.weak, want.x)
			or not _near(made.strong, want.y)
			or not _near(made.length, want.z)
		):
			right = false
			said = name
			continue
		var felt := _until_stop(_rumble(g), 2)
		var first: Array = felt[0]
		if first.is_empty() or not _near(first[2], want.x) or not _near(first[3], want.y):
			pads = false
			said = name
		# Fading out, it goes quiet a little before the end.
		var hold := RumbleData.num("all", "hold")
		var quiet := RumbleData.num("all", "quiet")
		var early := want.z * (1.0 - quiet * (1.0 - hold) / maxf(want.x, want.y))
		var stopped: float = felt[1]
		if stopped < early - STEP * 1.5 or stopped > want.z + STEP * 2.5:
			lengths = false
			said = "%s %.3f of %.3f" % [name, stopped, want.z]
	_check(right, "each gun's shot makes its own pulse, as rumble.cfg says %s" % said)
	_check(pads, "and the pad gets that weak and strong %s" % said)
	_check(lengths, "and is stopped as it runs out %s" % said)
	var revolver := RumbleData.gun(Weapons.REVOLVER)
	var shotgun := RumbleData.gun(Weapons.SHOTGUN)
	_check(
		revolver.x > revolver.y and shotgun.y > shotgun.x and shotgun.z > revolver.z,
		"the .38 cracks (weak motor), the sawed-off thumps (strong, longer)"
	)
	var rattles := true
	for i in [Weapons.TOMMY, Weapons.GREASE_GUN, Weapons.MOWER, Weapons.RIVETER, Weapons.RIFLE]:
		if RumbleData.gun(i).z >= Weapons.FIRE_TIME[i]:
			rattles = false
			said = str(Weapons.NAMES[i])
	_check(rattles, "a fast gun's pulse is shorter than its fire time: a rattle %s" % said)
	# Both barrels: the pair's share more.
	_clear(g)
	arms.active = Weapons.SHOTGUN
	arms.last_spent = 2
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	var both := _last(g)
	_check(both != null and both.strong > shotgun.y * 1.2, "both barrels kick harder than one")
	# The rip saw held on both triggers: one buzz, bite after bite.
	_clear(g)
	arms.active = Weapons.RIPSAW
	arms.grinding = true
	var out := _out()
	var buzzing := 0
	for k in 60:
		if k % 8 == 0:
			g.events.shot_fired.emit(Weapons.RIPSAW)
		out.drive(_rumble(g), STEP, 2, 0, "pad")
		if out.sent.x > .15:
			buzzing += 1
	var stops := 0
	for call: Array in _calls(out):
		if call[0] == "stop":
			stops += 1
	_check(
		_named(g, "grind").size() >= 7 and stops == 0 and buzzing >= 55,
		"the rip saw's grind is one held buzz (%d frames of 60, %d stops)" % [buzzing, stops]
	)
	arms.grinding = false


func _melee() -> void:
	var g := _game()
	var arms := g.armory
	arms.active = Weapons.CROWBAR
	_clear(g)
	g.events.traced.emit(Vector3.ZERO, "enemy")
	var on_man := _last(g)
	var want := RumbleData.pulse("melee", "crowbar")
	_check(
		on_man != null and on_man.what == "melee:crowbar" and _near(on_man.strong, want.y),
		"the crowbar landing on a man"
	)
	_clear(g)
	g.events.traced.emit(Vector3.ZERO, "wall:wood")
	var on_wall := _last(g)
	_check(on_wall != null and on_wall.strong < want.y and on_wall.strong > 0.0, "on a wall, less")
	_clear(g)
	g.events.traced.emit(Vector3.ZERO, "air")
	arms.active = Weapons.REVOLVER
	g.events.traced.emit(Vector3.ZERO, "enemy")
	_check(_rumble(g).made.is_empty(), "a swing at the air, and a bullet's end, make none")
	arms.active = Weapons.RIPSAW
	arms.grinding = true
	g.events.traced.emit(Vector3.ZERO, "enemy")
	_check(_named(g, "bite").size() == 1, "the rip saw's teeth in a man bite")
	arms.grinding = false
	# The dynamite: the match, then the throw.
	g = _game()
	var p := g.player
	p.armory.owned[Weapons.DYNAMITE] = true
	p.armory.reserve[Weapons.CROSSBOW] = 5
	p.armory.select(Weapons.DYNAMITE, g)
	_ticks(g, 40)
	_clear(g)
	var hold := Game.Controls.new()
	hold.fire = true
	_ticks(g, 20, hold)
	var lit := _named(g, "tnt:light").size()
	p.armory.release_dynamite(g)
	_ticks(g, 2)
	_check(
		lit == 1 and _named(g, "tnt:throw").size() == 1,
		(
			"the dynamite: the match struck, the stick thrown (%d, %d)"
			% [lit, _named(g, "tnt:throw").size()]
		)
	)


# -------------------------------------------------------------------- hurt


func _hurt() -> void:
	var g := _game()
	g.cheats.god = false
	var at := BrawlCheck.lane(g, 6)
	var p := BrawlCheck.stand(g, at, 0.0)
	var right := Vector2(-sin(p.angle), cos(p.angle))
	var felt := {}
	for side: String in ["right", "left", "none"]:
		_clear(g)
		p.health = 100
		var from := Vector2(p.x, p.y) + right * (2.0 if side == "right" else -2.0)
		g.damage(20.0, [from.x, from.y] if side != "none" else null, "HIT")
		_rumble(g).mix(0.0)
		felt[side] = _last(g)
	var r: Rumble.Pulse = felt["right"]
	var l: Rumble.Pulse = felt["left"]
	var n: Rumble.Pulse = felt["none"]
	_check(r != null and l != null and n != null, "a hurt makes a pulse")
	if r == null or l == null or n == null:
		return
	_check(r.weak > n.weak and r.strong < n.strong, "a blow from the right leans to the weak motor")
	_check(l.strong > n.strong and l.weak < n.weak, "a blow from the left to the strong motor")
	_clear(g)
	p.health = 100
	g.damage(4.0, null, "HIT")
	_rumble(g).mix(0.0)
	var light := _last(g)
	_clear(g)
	p.health = 100
	g.damage(40.0, null, "HIT")
	_rumble(g).mix(0.0)
	var heavy := _last(g)
	_check(
		light != null and heavy != null and heavy.strong > light.strong * 2.0,
		"a heavy blow more than a light one"
	)
	p.health = 100


# -------------------------------------------------------------------- boot


func _boot() -> void:
	var g := _game()
	var at := BrawlCheck.lane(g, 8)
	BrawlCheck.stand(g, at)
	BrawlCheck.hand(g, "billy", at.x + 1.2, at.y)
	_ticks(g, 2)
	_clear(g)
	BrawlCheck.press_use(g)
	_ticks(g, 40)
	_check(
		_named(g, "boot:hit").size() == 1 and _named(g, "boot:miss").is_empty(),
		"the boot landing on a man"
	)
	var want := RumbleData.pulse("boot", "hit")
	var hit := _named(g, "boot:hit")
	_check(not hit.is_empty() and _near(hit[0].strong, want.y), "with the boot's own pulse")
	var b := BrawlCheck.brawl(g)
	var e := BrawlCheck.hand(g, "billy", at.x + 6.0, at.y)
	e.dormant = true
	_ticks(g, 60)
	_clear(g)
	b.kick(g.player, e.uid)
	_ticks(g, 40)
	_check(
		_named(g, "boot:miss").size() == 1 and _named(g, "boot:hit").is_empty(),
		"a boot into the air, a light one"
	)


# ------------------------------------------------------------------ blasts


func _blasts() -> void:
	var g := _game()
	var at := BrawlCheck.lane(g, 6)
	var p := BrawlCheck.stand(g, at)
	var felt := []
	for d: float in [1.0, 6.0, 40.0]:
		_clear(g)
		var shot := Game.Shot.new(
			p.x + d, p.y, p.floor_z + .15, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0
		)
		shot.owner = -1
		g.explode(shot)
		var blasts := _named(g, "blast")
		felt.append(blasts[0] if not blasts.is_empty() else null)
	var near: Rumble.Pulse = felt[0]
	var far: Rumble.Pulse = felt[1]
	_check(near != null and far != null, "a blast near and one further off are felt")
	if near != null and far != null:
		_check(
			near.strong > far.strong * 1.5 and near.length > far.length,
			"near harder and longer than far (%.2f %.2f)" % [near.strong, far.strong]
		)
	_check(felt[2] == null, "one past its reach is not")
	_clear(g)
	g.blast_quiet = true
	g.events.exploded.emit(p.x + 1.0, p.y, p.floor_z, false)
	g.blast_quiet = false
	_check(_named(g, "blast").is_empty(), "a blast an online client showed already, not twice")


# ----------------------------------------------------------------- landing


func _landing() -> void:
	var g := _game()
	var at := BrawlCheck.lane(g, 6)
	var p := BrawlCheck.stand(g, at)
	var felt := {}
	for drop: float in [0.3, 1.5, 4.0]:
		_ticks(g, 10)
		_clear(g)
		p.air = drop
		p.vertical_speed = -.01
		_ticks(g, 120)
		var lands := _named(g, "land")
		felt[drop] = lands[0] if not lands.is_empty() else null
	_check(felt[0.3] == null, "a hop is not a hard landing")
	var mid: Rumble.Pulse = felt[1.5]
	var big: Rumble.Pulse = felt[4.0]
	_check(mid != null and big != null, "a fall of 1.5 and of 4 cells land hard")
	if mid != null and big != null:
		var want := RumbleData.pulse("land", "pulse")
		_check(
			big.strong > mid.strong and _near(big.strong, want.y),
			"by the drop, the whole pulse from rumble.cfg's full up"
		)


# ---------------------------------------------------------------- vehicles


func _vehicles() -> void:
	var hums := {}
	for level: String in ["bayou", "speedway", "hickston"]:
		var g := _game(level)
		var rides: VehiclesScript = g.features["vehicles"]
		var v: VehicleDrive.Ride = rides.rides[0]
		rides.seat_in(g.player, 0)
		_ticks(g, 6)
		var idle := _rumble(g).bed
		var go := Game.Controls.new()
		go.forward = 1.0
		var top := Vector2.ZERO
		for k in 120:
			g.tick(STEP, go)
			top = top.max(_rumble(g).bed)
		hums[v.kind] = [idle, top]
		var want := RumbleData.pair(RumbleData.vehicle_section(v.kind), "idle")
		_check(
			idle.x >= want.x * .99 and idle.y >= want.y * .99 and idle.length() > 0.0,
			"the %s's engine hums standing (%s)" % [v.kind, str(idle)]
		)
		_check(
			top.x > idle.x and top.length() > idle.length(),
			"the %s hums harder on the move (%s)" % [v.kind, str(top)]
		)
		if v.kind == "car":
			# Held on, it strikes something.
			var bumped := false
			for k in 900:
				g.tick(STEP, go)
				if (
					not _named(g, "vehicle:bump").is_empty()
					or not _named(g, "vehicle:crash").is_empty()
				):
					bumped = true
					break
			_check(bumped, "the car striking a wall bumps (or crashes)")
			_clear(g)
			rides.call("_hurt", v, 9999.0)
			_ticks(g, 2)
			var wrecked := _named(g, "vehicle:wreck").size()
			# (Let the wreck's pieces settle: a game let go with them flying
			# leaks at exit, whatever this feature does.)
			_ticks(g, 60)
			_check(
				wrecked == 1 and _rumble(g).bed == Vector2.ZERO,
				"its tank going up with the driver in it; out of it, no hum"
			)
		if v.kind == "mower":
			var thumps := 0
			var last := 0.0
			for k in 60:
				g.tick(STEP, Game.Controls.new())
				var now := _rumble(g).bed.y
				if now > last + .1:
					thumps += 1
				last = now
			_check(thumps >= 4, "the mower's one cylinder thumps (%d a second)" % thumps)


# ------------------------------------------------------------------ bosses


func _bosses() -> void:
	var g := _game()
	var e := BrawlCheck.hand(g, "billy", 3.0, 3.0)
	for moment: String in ["intro", "enraged", "phase", "staggered", "weak_hit", "down"]:
		_clear(g)
		match moment:
			"intro":
				g.events.boss_intro.emit(e)
			"enraged":
				g.events.boss_enraged.emit(e)
			"phase":
				g.events.boss_phase.emit(e, 2)
			"staggered":
				g.events.boss_staggered.emit(e)
			"weak_hit":
				g.events.boss_weak_hit.emit(e)
			"down":
				g.events.boss_down.emit(e, 30.0)
		var want := RumbleData.pulse("boss", moment)
		var made := _last(g)
		_check(
			made != null and made.what == "boss:" + moment and _near(made.length, want.z),
			"a boss's %s" % moment
		)
	var down := RumbleData.pulse("boss", "down")
	var intro := RumbleData.pulse("boss", "intro")
	_check(
		down.y >= intro.y and down.z > RumbleData.pulse("boss", "staggered").z,
		"the fall is the biggest"
	)
	# A quake: the screen shaken by something with no pulse of its own (a slam).
	_ticks(g, 30)
	_clear(g)
	g.shake = minf(1.0, g.shake + .5)
	_ticks(g, 1)
	var quakes := _named(g, "quake")
	_check(quakes.size() == 1 and quakes[0].quake, "a slam's shake of the screen is a quake")
	_ticks(g, 30)
	_clear(g)
	g.shake = minf(1.0, g.shake + .04)
	_ticks(g, 1)
	_check(_named(g, "quake").is_empty(), "a little shake is not")
	# A quake is mixed with the rest by the bigger, not added.
	var r := _rumble(g)
	_clear(g)
	r.add("a", Vector3(.3, .4, 1.0))
	r.add("q", Vector3(.2, .5, 1.0), 1.0, true)
	var m := r.mix(0.0)
	_check(_near(m.x, .3) and _near(m.y, .5), "a quake goes by the bigger (%s)" % str(m))
	_clear(g)
	for k in 8:
		r.add("a", Vector3(.5, .5, 1.0))
	m = r.mix(0.0)
	_check(
		(
			_near(m.x, RumbleData.num("all", "cap_weak"))
			and _near(m.y, RumbleData.num("all", "cap_strong"))
		),
		"pulses together add up to the caps"
	)


# ------------------------------------------------------ levels, the phone


func _levels() -> void:
	var g := _game()
	var r := _rumble(g)
	var want := RumbleData.gun(Weapons.REVOLVER)
	g.armory.active = Weapons.REVOLVER
	g.armory.last_spent = 1
	_clear(g)
	g.events.shot_fired.emit(Weapons.REVOLVER)
	var off := _out()
	for k in 20:
		off.drive(r, STEP, 0, 0, "pad")
	_check(_calls(off).is_empty(), "RUMBLE OFF: the pad is never told")
	_clear(g)
	g.events.shot_fired.emit(Weapons.REVOLVER)
	var low := _until_stop(r, 1)
	var first: Array = low[0]
	var k := RumbleData.num("all", "low")
	_check(
		not first.is_empty() and _near(first[2], want.x * k) and _near(first[3], want.y * k),
		"RUMBLE LOW: every pulse times %.2f" % k
	)
	# Keys in hand and the pad idle: it stays still.
	_clear(g)
	g.events.shot_fired.emit(Weapons.REVOLVER)
	var idle := _out()
	idle.pad_used_at = -999.0
	idle.drive(r, STEP, 2, 0, "keys")
	_check(_calls(idle).is_empty(), "a pad lying idle while the keys play is left still")
	# The phone: the strongest new pulse, at its level; none for a weak one.
	_clear(g)
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	g.events.shot_fired.emit(Weapons.REVOLVER)
	var phone := _out()
	phone.drive(r, STEP, 2, 2, "touch")
	var buzz: Array = []
	var pads := 0
	for call: Array in _calls(phone):
		if call[0] == "phone":
			buzz = call
		if call[0] == "pad":
			pads += 1
	var shotgun := RumbleData.gun(Weapons.SHOTGUN)
	_check(
		(
			not buzz.is_empty()
			and buzz[1] == roundi(shotgun.z * 1000.0)
			and _near(buzz[2], maxf(shotgun.x, shotgun.y))
		),
		"played by touch, the phone buzzes the strongest new pulse %s" % str(buzz)
	)
	_check(pads == 0, "and the pad lying about is left still")
	_clear(g)
	g.events.shot_fired.emit(Weapons.TEAT)
	phone = _out()
	phone.drive(r, STEP, 1, 1, "touch")
	_check(_calls(phone).is_empty(), "PHONE RUMBLE LOW: the teat gun's squirt is too weak to buzz")
	_clear(g)
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	phone = _out()
	(phone.sink as Recorder).can_phone = false
	phone.drive(r, STEP, 2, 2, "touch")
	_check(_calls(phone).is_empty(), "a phone that cannot buzz (an iPhone's browser) is left alone")
	var none := _out()
	(none.sink as Recorder).pad_list = []
	_check(none.taste("rumble", 2) != "", "the setting says so when no pad is hooked up")
	var tasted := _out()
	_check(
		tasted.taste("rumble", 2) == "" and str(_calls(tasted)[0][0]) == "pad",
		"changing RUMBLE gives a taste of it"
	)


# --------------------------------------------------------------- local only


func _local_only() -> void:
	var g := _game()
	var one := g.player
	var two := Players.join(g, one.x + 1.0, one.y, 0.0)
	_clear(g)
	g.focus(two)
	g.armory.last_spent = 1
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	g.events.traced.emit(Vector3.ZERO, "enemy")
	g.focus(g.local_player)
	g.cheats.god = false
	g.damage(20.0, [one.x + 2.0, one.y], "HIT", two)
	_rumble(g).mix(0.0)
	_check(_rumble(g).made.is_empty(), "the other player's shots, blows and hurts make none here")
	g.armory.last_spent = 1
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	_check(_named(g, "gun").size() == 1, "the local player's do")
	g.cheats.god = true


# ------------------------------------------------------------------- live


func _live() -> void:
	var g: Game = main.make_game("range")
	g.configure({})
	g.cheats.god = true
	main.game = g
	main.state = "play"
	main.focused = true
	_check(RumbleOut.live_of(main), "in play: live")
	var out := _out()
	var r := _rumble(g)
	g.armory.active = Weapons.SHOTGUN
	g.armory.last_spent = 1
	g.events.shot_fired.emit(Weapons.SHOTGUN)
	out.drive(r, STEP, 2, 0, "pad")
	var stops := {}
	for case: String in ["menu", "focus", "down"]:
		match case:
			"menu":
				main.state = "title"
			"focus":
				main.focused = false
			"down":
				g.local_player.health = 0
		r.add("x", Vector3(.5, .5, 1.0))
		out.drive(r, STEP, 2, 0, "pad")
		out.frame(main, STEP)
		var stopped := false
		for call: Array in _calls(out):
			stopped = stopped or call[0] == "stop"
		stops[case] = stopped and r.pulses.is_empty() and not RumbleOut.live_of(main)
		(out.sink as Recorder).calls.clear()
		main.state = "play"
		main.focused = true
		g.local_player.health = 100
	_check(stops["menu"], "a menu (pause) stops the pad and drops the pulses")
	_check(stops["focus"], "the window losing the focus does")
	_check(stops["down"], "the down screen does")
	r.add("x", Vector3(.5, .5, 1.0))
	out.drive(r, STEP, 2, 0, "pad")
	out.stop()
	var quit := false
	for call: Array in _calls(out):
		quit = quit or call[0] == "stop"
	_check(quit, "and stop() (the program closing) stops it")
	main.state = "title"


# ------------------------------------------------------------------ exact


## The same few seconds of play (guns, a blast, a hurt, a landing) with RUMBLE
## FULL driven every frame and with it OFF: the same state, rng and snapshot.
func _exact() -> void:
	var ends: Array = []
	for level: int in [2, 0]:
		var g := _game()
		g.cheats.god = false
		g.adaptive = false
		var at := BrawlCheck.lane(g, 8)
		var p := BrawlCheck.stand(g, at)
		BrawlCheck.hand(g, "billy", at.x + 5.0, at.y)
		var arms := p.armory
		arms.owned[Weapons.SHOTGUN] = true
		arms.loaded[Weapons.SHOTGUN] = 2
		arms.reserve[Weapons.SHOTGUN] = 20
		arms.select(Weapons.SHOTGUN, g)
		var out := _out()
		var r := _rumble(g)
		var fire := Game.Controls.new()
		fire.fire = true
		for t in 240:
			if t == 60:
				var shot := Game.Shot.new(
					p.x + 3.0, p.y, p.floor_z + .15, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0
				)
				shot.owner = -1
				g.explode(shot)
			if t == 120:
				p.air = 2.0
				p.vertical_speed = -.01
			g.tick(STEP, fire if t % 40 < 20 else Game.Controls.new())
			out.drive(r, STEP, level, level, "pad")
		var snap := GameSnapshot.capture(g)
		ends.append(
			[
				Replay.state_hash(g),
				g.rng.state,
				var_to_str(snap).hash(),
				r.made.size(),
				_calls(out).size()
			]
		)
	var full: Array = ends[0]
	var off: Array = ends[1]
	_check(
		full[3] > 5 and full[4] > 0,
		"the run rumbles at FULL (%d pulses, %d calls)" % [full[3], full[4]]
	)
	_check(off[4] == 0, "and not at all at OFF")
	_check(
		full[0] == off[0] and full[1] == off[1] and full[2] == off[2],
		(
			"play is the same with RUMBLE FULL and OFF: state, rng, snapshot (%s / %s)"
			% [str(full.slice(0, 3)), str(off.slice(0, 3))]
		)
	)
