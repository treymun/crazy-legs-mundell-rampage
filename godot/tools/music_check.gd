## The fight music in four levels (pass 15: features/fight_music.gd,
## src/score_layers.gd, the layers of scripts/audio_layers.py):
##
## - every chapter's fight loop has its two layers in the packs, as long as
##   it, and the fight player gets the three as one synchronized stream;
## - the layers' gains move at their own pace toward what each level wants,
##   and start at it while the fight player is silent;
## - one hand on the player is BUILD, two a FIGHT, a hand and a blow a FIGHT;
##   the FIGHT holds once they are gone; with the director in a BREATHER and
##   nobody on him it is out of FIGHT within BREATHER_LIMIT; a director's peak
##   with a hand on him, or his RAMPAGE, is the PEAK; the Crossroads is CALM;
## - the balance bot plays Hickston and the Fair (REGULAR, seed 1) with the
##   whole loop on under LOOP_MOST of the time (it was 80 to 97 %).
##
##   godot --headless --path godot --script res://tools/music_check.gd
##
## Prints MUSIC CHECK OK (check_all runs it).
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const FightMusic := preload("res://src/features/fight_music.gd")
const STEP := 1.0 / 60.0
const BREATHER_LIMIT := 4.0
const LOOP_MOST := .6

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	_layers()
	_gains()
	_levels()
	_shares()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("MUSIC CHECK OK")
	else:
		print("MUSIC CHECK FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


func _layers() -> void:
	print("\nTHE LAYERS")
	var assets: Assets = main.art
	for score: String in Sound.FIGHTS:
		var track: String = Sound.FIGHTS[score]
		check(ScoreLayers.layered(assets, track), "%s has its pulse and peak layers" % track)
		var made: AudioStream = ScoreLayers.stream_of(assets, track)
		var synced := made as AudioStreamSynchronized
		if synced == null:
			check(false, "%s plays as one synchronized stream" % track)
			continue
		var lengths: Array = []
		for i in synced.stream_count:
			lengths.append(snappedf(synced.get_sync_stream(i).get_length(), .001))
		var same: bool = lengths.size() == 3 and lengths.min() == lengths.max()
		check(same, "%s: loop, drums and riff the same length %s" % [track, str(lengths)])
	check(not ScoreLayers.layered(assets, ""), "no layers without a fight loop")


func _gains() -> void:
	print("\nTHE LAYERS' GAINS")
	ScoreLayers.step(STEP, ScoreLayers.BUILD, 0.0)
	check(_gains_are([0.0, 1.0, 0.0]), "silent: at BUILD at once (the drums alone)")
	var t := 0.0
	while ScoreLayers.gains[ScoreLayers.LOOP] < 1.0 and t < 5.0:
		ScoreLayers.step(STEP, ScoreLayers.FIGHT, 1.0)
		t += STEP
	var rise: float = ScoreLayers.RISE[ScoreLayers.LOOP]
	check(absf(t - rise) < .05, "the loop comes in over %.2f s (%.2f)" % [rise, t])
	check(
		ScoreLayers.gains[ScoreLayers.PULSE] > 0.0,
		"the drums still going as the loop is in (they leave slower)"
	)
	for i in 120:
		ScoreLayers.step(STEP, ScoreLayers.PEAK, 1.0)
	check(_gains_are([1.0, 0.0, 1.0]), "PEAK: the loop and its riff, no drums alone")
	for i in 30:
		ScoreLayers.step(STEP, ScoreLayers.CALM, 1.0)
	check(_gains_are([1.0, 0.0, 1.0]), "CALM leaves them be while the track comes back")


func _gains_are(want: Array) -> bool:
	for i in 3:
		if absf(ScoreLayers.gains[i] - float(want[i])) > .0001:
			return false
	return true


func _made(id := "hickston") -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": 0})
	g.lessons = false
	g.cheats.god = true
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	return g


func _ticks(g: Game, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		g.tick(STEP, Game.Controls.new())


## A hand by the player that sees him (stunned for good: it stands there).
func _on_him(g: Game, ahead: float) -> Enemy:
	var p := g.player
	var e := Enemy.new("billy", p.x + ahead, p.y, PI)
	e.uid = g.take_uid()
	e.dormant = false
	e.stun = 1e6
	e.cooldown = 1e6
	e.alerted = true
	e.player_seen = true
	e.floor_z = g.world.elevation(e.x, e.y)
	g.enemies.append(e)
	return e


func _fm(g: Game) -> FightMusic:
	return g.features.get("fight_music")


func _levels() -> void:
	print("\nTHE LEVELS")
	var g := _made()
	_ticks(g, .5)
	var fm := _fm(g)
	var d: Director = g.features.get("director")
	check(fm.level == ScoreLayers.CALM, "nobody about: CALM")
	var one := _on_him(g, 4.0)
	_ticks(g, .3)
	check(
		fm.level == ScoreLayers.BUILD, "one hand on him: BUILD (%s)" % ScoreLayers.NAMES[fm.level]
	)
	g.events.player_hurt.emit(5.0, "billy")
	_ticks(g, .3)
	check(fm.level == ScoreLayers.FIGHT, "and a blow: the FIGHT (%s)" % ScoreLayers.NAMES[fm.level])
	var two := _on_him(g, 5.0)
	_ticks(g, FightMusic.HURT_HOT + .5)
	check(fm.level == ScoreLayers.FIGHT, "two on him: the FIGHT")
	# One still hunting him out of sight, farther off: the FIGHT holds HOLD.
	var lurker := _on_him(g, 14.0)
	lurker.player_seen = false
	lurker.hunt_until = 1e9
	one.hp = 0.0
	two.hp = 0.0
	_ticks(g, FightMusic.HOLD - 2.0)
	check(fm.level == ScoreLayers.FIGHT, "it holds while a hand still hunts him")
	_ticks(g, 3.0)
	check(fm.level < ScoreLayers.FIGHT, "and gives way after %.0f s" % FightMusic.HOLD)
	lurker.hp = 0.0
	var six := _on_him(g, 4.0)
	var seven := _on_him(g, 5.0)
	_ticks(g, 1.0)
	six.hp = 0.0
	seven.hp = 0.0
	var quiet := 0.0
	while fm.level >= ScoreLayers.FIGHT and quiet < 15.0:
		_ticks(g, STEP)
		quiet += STEP
	check(
		quiet <= FightMusic.QUIET_HOLD + .3,
		"nobody left awake about: out of the FIGHT in %.1f s" % quiet
	)
	# A breather from the director: out of the FIGHT soon.
	var three := _on_him(g, 4.0)
	var four := _on_him(g, 5.0)
	_ticks(g, 1.0)
	check(fm.level == ScoreLayers.FIGHT, "two on him again: the FIGHT")
	three.hp = 0.0
	four.hp = 0.0
	d.on = true
	d.started = true
	d.phase = Director.BREATHER
	d.breather_until = g.clock + 30.0
	var t := 0.0
	while fm.level >= ScoreLayers.FIGHT and t < 10.0:
		_ticks(g, STEP)
		t += STEP
	check(t <= BREATHER_LIMIT, "a breather: out of the FIGHT in %.1f s" % t)
	# A peak with a hand on him; then a RAMPAGE.
	var five := _on_him(g, 4.0)
	d.phase = Director.PEAK
	d.peak = [g.enemies.find(five)]
	d.peak_began = g.clock
	d.peak_hot = g.clock
	_ticks(g, .3)
	check(fm.level == ScoreLayers.PEAK, "a peak with a hand on him: PEAK")
	five.hp = 0.0
	d.peak = []
	d.phase = Director.BREATHER
	d.breather_until = g.clock + 60.0
	_ticks(g, FightMusic.HOLD + 1.0)
	var r := Rampage.of(g)
	r._grow(0)
	r.until[0] = g.clock + 5.0
	r.began[0] = g.clock
	_ticks(g, .3)
	check(fm.level == ScoreLayers.PEAK, "his RAMPAGE: PEAK")
	var hub := _made("hub")
	hub.in_hub = true
	_on_him(hub, 4.0)
	_ticks(hub, .5)
	check(_fm(hub).level == ScoreLayers.CALM, "the Crossroads: CALM")


## The bot plays a chapter; the share of it with the whole loop on.
func _shares() -> void:
	print("\nTHE WHOLE LOOP NO LONGER ALL CHAPTER (the REGULAR bot)")
	for id: String in ["hickston", "fair"]:
		var g := _made(id)
		g.cheats.god = false
		g.rng = GameState.Rng.new(1009 + 31 * Campaign.ORDER.find(id))
		var pilot := Pilot.new(1, 1)
		var at := [0.0, 0.0, 0.0, 0.0]
		var swaps := 0
		var was := false
		while g.clock < 300.0 and not g.won and g.player.health > 0:
			var c := pilot.steer(g)
			g.tick(STEP, c)
			pilot.moved(g)
			var fm := _fm(g)
			at[fm.level] += STEP
			if fm.fighting != was:
				swaps += 1
				was = fm.fighting
		var whole: float = (at[2] + at[3]) / maxf(1.0, g.clock)
		check(
			whole < LOOP_MOST,
			(
				(
					"%s: the whole loop %.0f %% of %.0f s"
					+ " (CALM %.0f, BUILD %.0f, FIGHT %.0f, PEAK %.0f s; %d swaps)"
				)
				% [id, 100.0 * whole, g.clock, at[0], at[1], at[2], at[3], swaps]
			)
		)
		check(at[1] > 0.0 and at[3] > 0.0, "%s: BUILD and PEAK both heard" % id)
