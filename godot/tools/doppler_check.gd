## Doppler on fast movers (pass 14; src/doppler.gd, src/mover_sounds.gd,
## data/tuning/doppler.cfg):
##
##   Godot --headless --path <project> --script res://tools/doppler_check.gd
##
## - The tuning: the file read, every family a [fly] row names listed, every
##   loop it names in the bank.
## - The physics: a source passing the listener at a car's top speed comes
##   in high and goes away low (rising, then falling through the pass),
##   near the plain Doppler ratio far off, never past the clamp, and smooth
##   frame to frame (never more than `slew` a second); a source and a
##   listener standing still give exactly 1.
## - The voices: an engine's note tied to a mover keeps exactly its own
##   pitch (Sound's per-play spread times its rate) while the mover stands
##   and is that times the Doppler while it moves; the same note heard
##   through a wall (cutoff 1300) bends by the same factor.
## - A teleport (a respawn, a seat taken) gives no spike; OFF and a family's
##   scale 0 give none at all.
## - In a game: a bottle rocket fired past the player carries its loop
##   (fly_rocket on a flight bed), up then down; driving the car, its own
##   engine barely bends (the listener rides along at its speed).
## - Play exact: a run with the movers' sounds every frame and one with
##   neither leave the same state, rng and snapshot.
##
## Nobody listens here: this says the pitch moves as the numbers say, not
## how it sounds.
extends SceneTree

const STEP := 1.0 / 60.0
const VehiclesScript := preload("res://src/features/vehicles.gd")
const BrawlCheck := preload("res://tools/brawl_check.gd")

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
	print("A PASS")
	_pass()
	print("STANDING STILL, SPREAD AND WALLS")
	_voices()
	print("TELEPORTS, OFF AND SCALE 0")
	_snaps()
	print("IN A GAME")
	_in_game()
	print("PLAY EXACT")
	_exact()
	print(
		(
			"\n%d passed, %d failed in %.1f s"
			% [passes, failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("DOPPLER CHECK FAILED" if not failures.is_empty() else "DOPPLER CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


static func semis(f: float) -> float:
	return 12.0 * log(f) / log(2.0)


func _fresh() -> Doppler:
	var d := Doppler.new()
	d.tune()
	return d


# ------------------------------------------------------------------ tuning


func _tuning() -> void:
	var d := _fresh()
	_check(
		d.on and d.sound_speed > 50.0 and d.most_up > 0.0 and d.most_up <= 4.0,
		(
			"doppler.cfg read: on, c %.0f cells a second, at most +%.1f / -%.1f semitones"
			% [d.sound_speed, d.most_up, d.most_down]
		)
	)
	var cfg := Tuning.file(Doppler.DATA)
	var rows: Array = []
	for kind: String in cfg.get_section_keys("fly"):
		rows.append(cfg.get_value("fly", kind))
	rows.append(cfg.get_value("carried", "loop"))
	rows.append(cfg.get_value("saucer", "loop"))
	var missing: Array = []
	var unlisted: Array = []
	for row: Array in rows:
		if row.size() < 5 or not main.sound.has(str(row[0])):
			missing.append(row)
		elif not d.families.has(str(row[3])):
			unlisted.append(row[3])
	_check(missing.is_empty(), "every flight loop doppler.cfg names is made %s" % str(missing))
	_check(unlisted.is_empty(), "and every family it names has a [family.*] %s" % str(unlisted))
	for kind: String in ["car", "airboat", "mower", "race"]:
		_check(d.families.has(kind), "the %s family is tuned" % kind)


# ------------------------------------------------------------------ a pass


## A source running along x at `speed` past a listener 2 cells off its
## line: the factor each frame.
func _drive_by(d: Doppler, speed: float, key := 7, family := "car") -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var x := -40.0
	d.listen(Vector3(0.0, 2.0, .9), STEP)
	while x < 40.0:
		d.listen(Vector3(0.0, 2.0, .9), STEP)
		d.feed(key, family, Vector3(x, 0.0, .9), STEP)
		d.frame(STEP)
		out.append(d.factor_of(key))
		x += speed * STEP
	return out


func _pass() -> void:
	var d := _fresh()
	var top := VehicleDrive.spec("car").top
	var f := _drive_by(d, top)
	var high := 0
	var low := 0
	for i in f.size():
		if f[i] > f[high]:
			high = i
		if f[i] < f[low]:
			low = i
	var want_far := Doppler.ratio(
		d.sound_speed,
		Vector3(-30.0, 0, .9),
		Vector3(top, 0, 0),
		Vector3(0, 2, .9),
		Vector3.ZERO,
		1.0
	)
	var at_far := f[int(10.0 / top / STEP)]
	_check(
		f[0] == 1.0 and f[high] > 1.0 and f[low] < 1.0 and high < low,
		(
			"a car at its top %.1f passing 2 cells off: up %.2f then down %.2f semitones"
			% [top, semis(f[high]), semis(f[low])]
		)
	)
	_check(
		absf(semis(at_far) - semis(want_far)) < .03,
		"far off it is the plain ratio (%.3f against %.3f)" % [at_far, want_far]
	)
	var falls := true
	for i in range(high + 1, low + 1):
		falls = falls and f[i] <= f[i - 1] + 1e-6
	_check(falls, "and it only falls from the highest to the lowest")
	var steepest := 0.0
	for i in range(1, f.size()):
		steepest = maxf(steepest, absf(semis(f[i]) - semis(f[i - 1])))
	_check(
		steepest <= d.slew * STEP + 1e-4,
		"smooth: at most %.3f semitones a frame (slew %.0f a second)" % [steepest, d.slew]
	)
	# Faster than anything in the county: held at the clamp.
	var fast := _drive_by(_fresh(), 40.0)
	var up := -INF
	var down := INF
	for v in fast:
		up = maxf(up, semis(v))
		down = minf(down, semis(v))
	_check(
		up <= d.most_up + 1e-4 and down >= -d.most_down - 1e-4 and up > d.most_up - .2,
		"at 40 cells a second it is clamped (+%.2f / %.2f)" % [up, down]
	)
	var still := _fresh()
	for i in 60:
		still.listen(Vector3(1.0, 1.0, .9), STEP)
		still.feed(3, "car", Vector3(5.0, 4.0, .5), STEP)
		still.frame(STEP)
	_check(still.factor_of(3) == 1.0, "standing still, exactly 1 (%.9f)" % still.factor_of(3))
	# The listener running at a standing source: up while closing, nothing
	# once level with it and the gap opening at the same rate down.
	var ear := _fresh()
	var y := -20.0
	var closing := 1.0
	while y < 20.0:
		ear.listen(Vector3(0.0, y, .9), STEP)
		ear.feed(4, "car", Vector3(1.0, 0.0, .9), STEP)
		ear.frame(STEP)
		if y < -10.0:
			closing = ear.factor_of(4)
		y += 6.0 * STEP
	_check(
		closing > 1.0 and ear.factor_of(4) < 1.0,
		(
			"the listener running past a standing one: up %.2f, then down %.2f"
			% [semis(closing), semis(ear.factor_of(4))]
		)
	)


# ------------------------------------------------------------------ voices


func _effects_quiet(sound: Sound) -> void:
	for v: Sound.Voice in sound._effects:
		v.player.stop()


## The effect voice playing `cue`, started last.
func _voice_of(sound: Sound, cue: String) -> AudioStreamPlayer:
	for v: Sound.Voice in sound._effects:
		if v.player.playing and v.cue == cue:
			return v.player
	return null


func _voices() -> void:
	var sound: Sound = main.sound
	var d := sound.doppler
	d.reset()
	d.tune()
	var cue := "lap_car_pass"
	_check(
		sound.has(cue) and sound.assets.cue(cue).get_length() >= d.shortest,
		"%s is long enough to bend" % cue
	)
	# Its own pitch, unbent: the dice put back to play it again tied.
	_effects_quiet(sound)
	var dice := sound._dice.state
	sound.play_at_rate(cue, .5, 0.0, Sound.OPEN_CUTOFF, 1.12)
	var plain := _voice_of(sound, cue)
	var own := plain.pitch_scale if plain != null else 0.0
	_effects_quiet(sound)
	sound._dice.state = dice
	var key := Doppler.RIDE + 90
	for i in 10:
		d.listen(Vector3(0, 0, .9), STEP)
		d.feed(key, "car", Vector3(6, 3, .9), STEP)
		d.frame(STEP)
	d.next_from = key
	sound.play_at_rate(cue, .5, 0.0, Sound.OPEN_CUTOFF, 1.12)
	d.next_from = 0
	var tied := _voice_of(sound, cue)
	_check(
		tied != null and d.holds(tied) and tied.pitch_scale == own and own != 1.12,
		(
			"standing, a tied note keeps exactly its own pitch: spread x rate %.6f (%.6f)"
			% [own, tied.pitch_scale if tied != null else 0.0]
		)
	)
	# The same note again, through a wall: both tied to one mover coming on.
	sound._dice.state = dice
	d.next_from = key
	sound.play_at_rate(cue, .5, 0.0, 1300.0, 1.12)
	d.next_from = 0
	var muffled: AudioStreamPlayer = null
	for v: Sound.Voice in sound._effects:
		if v.player.playing and v.cue == cue and v.player != tied:
			muffled = v.player
			var filter := AudioServer.get_bus_effect(v.bus, 1) as AudioEffectLowPassFilter
			_check(filter != null and filter.cutoff_hz == 1300.0, "the second is muffled (1300 Hz)")
	var x := -30.0
	var sweep: Array = []
	while x < 30.0:
		d.listen(Vector3(0, 2, .9), STEP)
		d.feed(key, "car", Vector3(x, 0, .9), STEP)
		d.frame(STEP)
		if muffled != null and tied != null and tied.playing and muffled.playing:
			sweep.append([tied.pitch_scale / own, muffled.pitch_scale / own, d.factor_of(key)])
		x += 13.0 * STEP
		if x > -24.0:
			break
	var same := not sweep.is_empty()
	var bent := false
	for row: Array in sweep:
		var a: float = row[0]
		var b: float = row[1]
		var f: float = row[2]
		same = same and absf(a - f) < 1e-5 and absf(b - f) < 1e-5
		bent = bent or f > 1.01
	_check(
		same and bent,
		(
			"moving, open and through the wall both play spread x rate x the same Doppler (%d frames)"
			% sweep.size()
		)
	)
	# A cue too short to hear a sweep keeps its pitch.
	_effects_quiet(sound)
	d.next_from = key
	sound.play("rocket_whistle", .5)
	d.next_from = 0
	var short := _voice_of(sound, "rocket_whistle")
	_check(short != null and not d.holds(short), "a 0.3 s whistle is not tied (too short to bend)")
	_effects_quiet(sound)
	d.reset()


# ------------------------------------------------------------------ snaps


func _snaps() -> void:
	# Steady at 10 cells a second, then 20 cells on in one frame.
	var d := _fresh()
	var x := -40.0
	var worst := 0.0
	var before := 0.0
	var after := 0.0
	for i in 400:
		d.listen(Vector3(0, 30, .9), STEP)
		if i == 200:
			x += 20.0
		d.feed(5, "car", Vector3(x, 0, .9), STEP)
		var was := d.factor_of(5)
		d.frame(STEP)
		if i >= 200:
			# What its true speed gives there (the jump aside), and what is heard.
			var true_ratio := Doppler.ratio(
				d.sound_speed, Vector3(x, 0, .9), Vector3(10, 0, 0), d.ear, Vector3.ZERO, 1.0
			)
			before = maxf(before, absf(semis(true_ratio)))
			after = maxf(after, absf(semis(d.factor_of(5))))
		if i >= 200 and i < 210:
			worst = maxf(worst, absf(semis(d.factor_of(5)) - semis(was)))
		x += 10.0 * STEP
	_check(
		worst <= d.slew * STEP + 1e-4 and after <= before + 1e-3,
		(
			"a 20-cell jump: no spike (at most %.3f semitones a frame; at most %.2f, its true speed %.2f)"
			% [worst, after, before]
		)
	)
	# The listener teleported (a respawn) beside a mover going by.
	var e := _fresh()
	var spike := 0.0
	for i in 120:
		e.listen(Vector3(0, 5, .9) if i < 60 else Vector3(60, 5, .9), STEP)
		e.feed(6, "car", Vector3(-20.0 + i * .1, 0, .9), STEP)
		var was := e.factor_of(6)
		e.frame(STEP)
		spike = maxf(spike, absf(semis(e.factor_of(6)) - semis(was)))
	_check(spike <= e.slew * STEP + 1e-4, "the listener teleported: no spike (%.3f)" % spike)
	var off := _fresh()
	off.on = false
	var off_pass := _drive_by(off, 13.0)
	var scaled := _fresh()
	scaled.families["car"] = 0.0
	var zero_pass := _drive_by(scaled, 13.0)
	var flat := true
	for i in off_pass.size():
		flat = flat and off_pass[i] == 1.0 and zero_pass[i] == 1.0
	_check(flat, "OFF, and a family's scale 0: exactly 1 all through a pass")
	# And a tied voice then plays exactly its own pitch.
	var sound: Sound = main.sound
	sound.doppler.reset()
	sound.doppler.on = false
	_effects_quiet(sound)
	var dice := sound._dice.state
	sound.play("lap_car_pass", .5)
	var plain := _voice_of(sound, "lap_car_pass").pitch_scale
	_effects_quiet(sound)
	sound._dice.state = dice
	sound.doppler.next_from = Doppler.RIDE + 91
	sound.play("lap_car_pass", .5)
	sound.doppler.next_from = 0
	for i in 30:
		sound.doppler.listen(Vector3(0, 2, .9), STEP)
		sound.doppler.feed(Doppler.RIDE + 91, "car", Vector3(-10.0 + i * .3, 0, .9), STEP)
		sound.doppler.frame(STEP)
	var heard := _voice_of(sound, "lap_car_pass").pitch_scale
	_check(heard == plain, "OFF, a tied note plays its own pitch (%.6f, %.6f)" % [heard, plain])
	_effects_quiet(sound)
	sound.doppler.on = true
	sound.doppler.reset()


# ------------------------------------------------------------------ a game


func _bed(sound: Sound, cue: String) -> AudioStreamPlayer:
	for v: Sound.Voice in sound._beds:
		if v.player.playing and v.cue == cue:
			return v.player
	return null


func _in_game() -> void:
	var g := BrawlCheck.game(main)
	var sound: Sound = main.sound
	var movers := MoverSounds.new()
	var at := BrawlCheck.lane(g, 16)
	var p := BrawlCheck.stand(g, at + Vector2(8.0, .35))
	for i in 4:
		g.tick(STEP, Game.Controls.new())
		movers.frame(g, STEP)
	var shot := Game.Shot.new(
		at.x + .2, at.y - .35, p.eye + .3, 9.6, 0.0, 0.0, "bottle_rocket", 4.0
	)
	shot.uid = g.take_uid()
	shot.travelled = 1.0
	g.shots.append(shot)
	var base: float = (Tuning.file(Doppler.DATA).get_value("fly", "bottle_rocket") as Array)[2]
	var pitches := PackedFloat32Array()
	for i in 150:
		g.tick(STEP, Game.Controls.new())
		movers.frame(g, STEP)
		var bed := _bed(sound, "fly_rocket")
		if bed != null and g.shots.has(shot):
			pitches.append(bed.pitch_scale / base)
		if not g.shots.has(shot):
			break
	var high := 0
	var low := 0
	for i in pitches.size():
		if pitches[i] > pitches[high]:
			high = i
		if pitches[i] < pitches[low]:
			low = i
	_check(
		pitches.size() > 40 and pitches[high] > 1.005 and pitches[low] < .995 and high < low,
		(
			"a bottle rocket past the player: fly_rocket for %d frames, up %.2f then down %.2f semitones"
			% [
				pitches.size(),
				semis(pitches[high]) if pitches.size() > 0 else 0.0,
				semis(pitches[low]) if pitches.size() > 0 else 0.0
			]
		)
	)
	g.shots.erase(shot)
	for i in 20:
		g.tick(STEP, Game.Controls.new())
		movers.frame(g, STEP)
	_check(_bed(sound, "fly_rocket") == null, "gone, its loop fades out and stops")
	movers.hush(sound)
	# In the car: its own engine rides along with the listener.
	var cg := BrawlCheck.game(main, "speedway")
	var rides: VehiclesScript = cg.features["vehicles"]
	var car := -1
	for i in rides.rides.size():
		if (rides.rides[i] as VehicleDrive.Ride).kind == "car":
			car = i
	var seated := car >= 0 and rides.seat_in(cg.player, car)
	var engine := VehicleDrive.spec("car").engine
	for i in 12:
		cg.tick(STEP, Game.Controls.new())
		movers.frame(cg, STEP)
	var idle := _bed(sound, engine)
	var idle_pitch := idle.pitch_scale if idle != null else 0.0
	_check(idle != null and Assets.loops(idle.stream), "the seated car starts its own engine loop")
	var go := Game.Controls.new()
	go.forward = 1.0
	var most := 0.0
	var fastest := 0.0
	var engine_pitch := idle_pitch
	var d := sound.doppler
	for i in 150:
		cg.tick(STEP, go)
		movers.frame(cg, STEP)
		if idle != null and idle.playing:
			engine_pitch = maxf(engine_pitch, idle.pitch_scale)
		if i > 60:
			most = maxf(most, absf(semis(d.factor_of(Doppler.RIDE + car))))
			fastest = maxf(fastest, d.speed_of(Doppler.RIDE + car))
	_check(
		seated and fastest > 4.0 and most < .15,
		(
			"driving the car at %.1f cells a second, its own engine bends at most %.3f semitones"
			% [fastest, most]
		)
	)
	_check(
		_bed(sound, engine) == idle and engine_pitch > idle_pitch + .15,
		(
			"the same car engine voice rises from %.2f to %.2f as it drives"
			% [idle_pitch, engine_pitch]
		)
	)
	movers.hush(sound)
	_check(_bed(sound, engine) == null, "the engine stops when the view holds")
	d.reset()


# ------------------------------------------------------------------ exact


func _exact() -> void:
	var ends: Array = []
	for on: bool in [true, false]:
		var g := BrawlCheck.game(main, "speedway")
		g.cheats.god = false
		g.adaptive = false
		var sound: Sound = main.sound
		sound.doppler.reset()
		sound.doppler.on = on
		var movers := MoverSounds.new()
		var rides: VehiclesScript = g.features["vehicles"]
		var car := 0
		for i in rides.rides.size():
			if (rides.rides[i] as VehicleDrive.Ride).kind == "car":
				car = i
		rides.seat_in(g.player, car)
		var go := Game.Controls.new()
		go.forward = 1.0
		var p := g.player
		for t in 240:
			if t == 30 or t == 90:
				var kind := "bottle_rocket" if t == 30 else "tnt"
				var shot := Game.Shot.new(p.x + 1.0, p.y, p.eye, 6.0, 1.0, 1.0, kind, 3.0)
				shot.uid = g.take_uid()
				g.shots.append(shot)
			g.tick(STEP, go if t < 180 else Game.Controls.new())
			if on:
				movers.frame(g, STEP)
		var snap := GameSnapshot.capture(g)
		ends.append([Replay.state_hash(g), g.rng.state, var_to_str(snap).hash()])
		movers.hush(sound)
	sound_back()
	_check(
		ends[0] == ends[1],
		(
			"play is the same with the Doppler and the loops on and off: state, rng, snapshot (%s / %s)"
			% [str(ends[0]), str(ends[1])]
		)
	)


func sound_back() -> void:
	var sound: Sound = main.sound
	sound.doppler.on = true
	sound.doppler.reset()
