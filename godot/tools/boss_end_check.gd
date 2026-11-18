## The boss endings (src/boss_ending.gd, features/boss_fight.gd stand_down),
## headless, for every boss: felled in its BOSS REMATCH it runs through the
## front end's own frame to the result board within a time band; its camera
## is never inside a wall, a roof or the ground; the arena is stood down
## (no hazard, no enemy shot, the hands near stunned); no HUD is laid while
## it plays; the music is never silent more than half a second; it can be
## skipped; in the campaign with two players it runs and hands back to play;
## and the game under it is the same as with no ending at all (play exact).
##
##   godot --headless --path godot --script res://tools/boss_end_check.gd [-- kinds=boss,maw]
extends SceneTree

const STEP := 1.0 / 60.0
## The longest the music may be silent (seconds) and what counts as silent.
const SILENCE := .5
const QUIET := .02

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	BossRematch.unlock_all = true
	var kinds: Array = BossRematch.BOSSES.duplicate()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
	main.options["kill_cam"] = KillCam.BOSSES
	main.apply_options()
	print("BOSS ENDINGS")
	for kind: String in kinds:
		_rematch(kind)
		_skip(kind)
		_two_players(kind)
	_exact("foreman")
	print("")
	print("BOSS END OK" if failures.is_empty() else "%d BOSS END CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


# ------------------------------------------------------------------ driving


## The front end's play frame as main.gd runs it, then the draw.
func _frame() -> void:
	if main.state != "play" or main.game == null:
		main.render()
		return
	var still := Game.Controls.new()
	if main.boss_end.start(main):
		main.boss_end.frame(main, STEP)
		main.advance(STEP, Game.Controls.new())
	elif main.kill_cam.playing or main.kill_cam.start(main):
		main.kill_cam.frame(main, STEP)
	else:
		main.advance(STEP, still)
	main.watch_rematch()
	main.sound.tick_score(STEP)
	main.render()


## Into the boss's fight (god mode on, the player a few cells off it in its
## room), then the boss one blow from falling. The boss.
func _into_fight(g: Game, kind: String, two := false) -> Enemy:
	var boss := BossFight.of_kind(g, kind)
	if boss == null:
		return null
	for e: Enemy in g.enemies:
		if e != boss and e.hostile and not BossRematch.active(g):
			e.dormant = true
	g.cheats.god = true
	_place(g, boss)
	if two and g.players.size() < 2:
		var one: Player = g.player
		Players.join(g, one.x - cos(one.angle) * .8, one.y - sin(one.angle) * .8, one.angle)
	boss.dormant = false
	boss.alerted = true
	boss.wake(g, g.player.x, g.player.y)
	for i in 240:
		_frame()
		g.player.angle = atan2(boss.y - g.player.y, boss.x - g.player.x)
	_place(g, boss)
	boss.hp = minf(boss.hp, 30.0)
	boss.windup = 0.0
	return boss


func _place(g: Game, boss: Enemy) -> void:
	var p := g.player
	var w: LevelData = g.world
	var toward := atan2(p.y - boss.y, p.x - boss.x)
	for r: float in [5.0, 6.0, 4.0, 7.0, 3.2]:
		for k in 24:
			var turn: int = int((k + 1) / 2.0) * (1 if k % 2 else -1)
			var a := toward + turn * TAU / 24.0
			var at := Vector2(boss.x + cos(a) * r, boss.y + sin(a) * r)
			if w.blocked(at.x, at.y, .4) or w.deep_at(at.x, at.y):
				continue
			if not w.visible(at.x, at.y, boss.x, boss.y):
				continue
			if (
				not BossFight.lock_of(g, boss.kind).is_empty()
				and not BossFight.in_room(g, boss.kind, at.x, at.y)
			):
				continue
			p.x = at.x
			p.y = at.y
			p.eye = w.stand(p) + .95
			p.angle = atan2(boss.y - p.y, boss.x - p.x)
			return


## The killing blow: the player's buckshot.
func _fell(g: Game, boss: Enemy) -> void:
	g.hit_point = Vector3(boss.x, boss.y, g.world.stand(boss) + boss.height * .5)
	boss.hurt(boss.hp + 200.0, g, false, false, null, "shotgun")


## How loud the music is meant to be (a share of MUSIC VOLUME): the score
## asked for, under every hold on it, or the end sting over it for its own
## length from the fall. Worked out, not listened to: headless the players
## run on the wall clock while these frames run faster. No score player (no
## sound at all): 1.
func _heard() -> float:
	var s: Sound = main.sound
	var sp = s.score_player
	if sp == null or not sp.enabled:
		return 1.0
	var heard := 0.0
	if not sp.paused and sp.requested != "":
		heard = s._game_music * (1.0 - s.radio_gain) * s._music_duck * s._opener_hold
	var be: BossEnding = main.boss_end
	if be.playing and be.at < be.sting_left:
		heard = maxf(heard, .84)
	return heard


# ------------------------------------------------------------------ the checks


## Felled in its rematch: the whole ending through to the result board.
func _rematch(kind: String) -> void:
	main.start_rematch(kind, false)
	var g: Game = main.game
	var boss := _into_fight(g, kind)
	if boss == null:
		_check(false, "%s: its rematch has the boss" % kind)
		return
	# Something of the fight still going: a hand awake and winding up near,
	# a hazard on the floor and a shot of the boss's in the air.
	var hand := Enemy.new("coot", boss.x + 1.5, boss.y, 0.0)
	g.enemies.append(hand)
	hand.wake(g, g.player.x, g.player.y)
	hand.windup = .5
	g.add_hazard("steam", boss.x, boss.y + 1.0, .8, 0.0, 3.0, 5)
	var w: LevelData = g.world
	var floor_z: float = w.stand(boss)
	g.launch(boss.x, boss.y, floor_z + 1.0, 0.0, 2.0, "deputy_shot", 0.0, true, 5, 4.0)
	_fell(g, boss)
	var stood_down := g.hazards.is_empty()
	for shot: GameState.Shot in g.shots:
		stood_down = stood_down and not shot.enemy
	_check(
		stood_down and hand.stun > 0.0 and hand.windup == 0.0,
		(
			"%s: the fall stands the arena down (hazards %d, the hand stunned %.1f s)"
			% [kind, g.hazards.size(), hand.stun]
		)
	)
	var started := false
	var played := 0.0
	var inside := ""
	var hud_up := ""
	var quiet := 0.0
	var quietest := 0.0
	var frames := 0
	var aimed_away := 0
	var said := ""
	while frames < int(12.0 / STEP) and main.state == "play":
		_frame()
		frames += 1
		var be: BossEnding = main.boss_end
		if be.playing:
			started = true
			played = frames * STEP
			var eye := be.eye_at(be.at)
			var x: float = eye["x"]
			var y: float = eye["y"]
			var z: float = eye["eye"]
			var why := OpenerCamera.clear_at(w, x, y, z, false)
			if why != "" and inside == "":
				inside = "%s at %.2f s (%.1f, %.1f, %.2f)" % [why, be.at, x, y, z]
			for key: String in ["notice", "callout", "clock", "feed", "boss"]:
				if g.hud.layout.find(key).size.x > 0 and hud_up == "":
					hud_up = key
			if g.caption != "" and g.clock < g.caption_until and said == "":
				said = g.caption
			var look := be.target(be.at)
			var facing: float = eye["view_angle"]
			var off := absf(Enemy.angle_delta(atan2(look.y - y, look.x - x), facing))
			if be.at > BossEnding.HOLD + BossEnding.FLY and off > .35:
				aimed_away += 1
		if started and frames == 45:
			# The boss loop has handed back to the chapter's score by now.
			var s: Sound = main.sound
			var sting: String = s._sting.cue
			_check(
				s._sting.player.playing and sting.ends_with("_end"),
				"%s: its end sting is still playing over the score's hand-back (%s)" % [kind, sting]
			)
		if started:
			var heard := _heard()
			quiet = quiet + STEP if heard < QUIET else 0.0
			quietest = maxf(quietest, quiet)
	var length: float = BossEnding.REMATCH_LENGTH
	_check(started, "%s: the fall starts its ending" % kind)
	_check(
		main.state == "rematch_done" and played > length - .1 and played < length + .6,
		(
			"%s: it runs %.2f s (band %.1f to %.1f) to the result board (%s)"
			% [kind, played, length - .1, length + .6, main.state]
		)
	)
	_check(
		inside == "",
		"%s: its camera is never inside a wall, roof or the ground %s" % [kind, inside]
	)
	_check(
		aimed_away == 0,
		"%s: its camera keeps the boss in the shot (%d frames off)" % [kind, aimed_away]
	)
	_check(said != "", "%s: its last word is captioned under the picture (%s)" % [kind, said])
	_check(hud_up == "", "%s: no HUD is laid while it plays %s" % [kind, hud_up])
	_check(
		quietest <= SILENCE,
		"%s: the music is never silent over %.1f s (longest %.2f s)" % [kind, SILENCE, quietest]
	)
	_check(
		main.rematch_result.get("kind", "") == kind,
		"%s: the board shows its time and ribbon (%s)" % [kind, main.rematch_result]
	)
	main.state = "title"


## A key a second in: on to the fade, done well inside its length.
func _skip(kind: String) -> void:
	main.start_rematch(kind, false)
	var g: Game = main.game
	var boss := _into_fight(g, kind)
	if boss == null:
		return
	_fell(g, boss)
	var frames := 0
	var took_key := false
	while frames < int(10.0 / STEP) and main.state == "play":
		_frame()
		frames += 1
		if frames == 15:
			took_key = main.boss_end.playing and main.boss_end.skip()
			_check(
				main.boss_end.length >= BossEnding.REMATCH_LENGTH,
				"%s: a key at once is held off" % kind
			)
		if frames == 60:
			took_key = main.boss_end.skip()
	var done := frames * STEP
	_check(
		took_key and main.state == "rematch_done" and done < 1.0 + BossEnding.SKIP_FADE + .2,
		"%s: a key a second in skips it (the board after %.2f s)" % [kind, done]
	)
	main.state = "title"


## In its chapter with a second player along: it plays, and hands back to
## play (never stuck), the players still there.
func _two_players(kind: String) -> void:
	main.start(str(BossRematch.LEVEL_OF[kind]))
	main.state = "play"
	var g: Game = main.game
	var boss := _into_fight(g, kind, true)
	if boss == null:
		_check(false, "%s: its chapter has the boss" % kind)
		return
	_fell(g, boss)
	var frames := 0
	var played := 0
	while frames < int(10.0 / STEP):
		_frame()
		frames += 1
		if main.boss_end.playing:
			played += 1
	var expected: float = BossEnding.LENGTH
	if kind == "boss":
		expected = BossEnding.SHORT_LENGTH
	var seconds := played * STEP
	_check(
		(
			main.state == "play"
			and main.game == g
			and g.players.size() == 2
			and not main.boss_end.playing
			and absf(seconds - expected) < .2
		),
		(
			"%s: with two players it plays %.2f s (of %.1f) and hands back to play"
			% [kind, seconds, expected]
		)
	)


## The same fall with and without the ending: the game under it is the same.
func _exact(kind: String) -> void:
	var caught: Array = []
	for mode: int in [KillCam.BOSSES, KillCam.OFF]:
		main.options["kill_cam"] = mode
		main.apply_options()
		main.start(str(BossRematch.LEVEL_OF[kind]))
		main.state = "play"
		var g: Game = main.game
		var boss := _into_fight(g, kind)
		_fell(g, boss)
		var shown := 0
		for i in int(6.0 / STEP):
			_frame()
			if main.boss_end.playing:
				shown += 1
		caught.append([GameSnapshot.capture(g), shown])
	main.options["kill_cam"] = KillCam.BOSSES
	main.apply_options()
	var with_it: Array = caught[0]
	var without: Array = caught[1]
	var with_shown: int = with_it[1]
	var without_shown: int = without[1]
	_check(
		with_shown > 0 and without_shown == 0 and GameSnapshot.same(with_it[0], without[0]),
		"%s: the game under the ending is the same as with KILL CAM off (play exact)" % kind
	)
