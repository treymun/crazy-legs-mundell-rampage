## Checks of the boss fights (src/boss_kit.gd, src/features/boss_fight.gd,
## src/bosses/; tools/check_fixes.gd runs them; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/boss_check.gd
##
## Every boss has its moves file; the phases change under half and under a
## fifth of a boss's health (Maw's by her own) and are worked out again after
## a load; a big enough hit staggers a boss, cancels its wind-up and cannot
## again until its rest is over; a weak spot multiplies the player's damage
## and only where the hit struck; the backup at a phase change comes in the
## numbers DIFFICULTY gives, out of the player's sight, and is still there
## after a save and a load; the entrance never holds the world in a tool or a
## tour (game.lessons off), holds it in play, ends, and never comes twice; the
## slow motion as a boss falls ends, and its fall leaves loot and a tally row.
extends SceneTree


## A boss whose every hit is a weak spot at twice the damage.
class DoubleWeak:
	extends BossMoves

	func weak_spot(_e: Enemy, _game, _hit: Vector3, _from: Vector2, _how: String) -> float:
		return 2.0


var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("BOSS CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## A level's game with its last boss awake and the player `gap` cells from it
## (on open floor it can see), the posse feature having had its first look.
static func _fight(main, level_id: String, difficulty := 1, gap := 6.0) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({"difficulty": difficulty})
	g.spawn_grace = 0.0
	g.ticked.emit(1.0 / 60.0)
	var foe := boss_of(g)
	if foe == null:
		return g
	foe.dormant = false
	foe.alerted = true
	var p := g.player
	for ring: float in [gap, gap - 1.0, gap + 1.0, gap - 2.0, gap + 2.0, 3.0]:
		for k in 24:
			var a := k * TAU / 24.0
			var x := foe.x + cos(a) * ring
			var y := foe.y + sin(a) * ring
			if (
				not g.world.blocked(x, y, .3)
				and not g.world.deep_at(x, y)
				and g.world.visible(foe.x, foe.y, x, y)
			):
				p.x = x
				p.y = y
				p.eye = g.world.elevation(x, y) + .95
				p.angle = atan2(foe.y - y, foe.x - x)
				g.flow.update(p.x, p.y, g.clock + 99.0)
				return g
	return g


static func boss_of(g: Game) -> Enemy:
	if g.finale != null:
		return g.finale
	return g.boss


static func _ticks(g: Game, seconds: float, controls: Game.Controls = null) -> void:
	var held := controls if controls != null else Game.Controls.new()
	for _k in int(seconds * 60.0):
		g.tick(1.0 / 60.0, held)


static func run(main, check: Callable) -> void:
	print("BOSS FIGHTS")
	_moves(check)
	_phases(main, check)
	_stagger(main, check)
	_weak_spot(main, check)
	_backup(main, check)
	_entrance(main, check)
	_fall(main, check)


static func _moves(check: Callable) -> void:
	var missing: Array = []
	for kind: String in Enemy.BOSS_TITLES:
		if not BossKit.MOVES.has(kind) or not BossKit.moves(kind) is BossMoves:
			missing.append(kind)
	check.call(
		missing.is_empty() and Enemy.BOSS_TITLES.size() >= 8,
		"every boss has its moves file (%d)%s" % [Enemy.BOSS_TITLES.size(), " " + str(missing)]
	)


static func _phases(main, check: Callable) -> void:
	# Hickston: a save of a later chapter needs the chapters before in its history.
	var g := _fight(main, "hickston")
	var e := boss_of(g)
	var heard: Array = []
	g.boss_phase.connect(func(_who: Enemy, phase: int) -> void: heard.append(phase))
	e.hp = e.max_hp * .51
	e.hurt(1.0, g)
	var first := e.boss_phase
	e.hp = e.max_hp * .5 + .5
	e.hurt(1.0, g)
	var second := e.boss_phase
	e.hp = e.max_hp * .2 + .5
	e.hurt(1.0, g)
	check.call(
		first == 1 and second == 2 and e.boss_phase == 3 and heard == [2, 3],
		(
			"a boss goes to phase 2 under half its health and 3 under a fifth (%d %d %d, %s)"
			% [first, second, e.boss_phase, heard]
		)
	)
	check.call(e.enraged and e.desperate_at >= 0.0, "fightin' mad at 2, plum desperate at 3")
	var path := OS.get_cache_dir().path_join("clmr-boss-phase.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var again: Enemy = boss_of(back) if back != null else null
	check.call(
		again != null and again.boss_phase == 3 and again.enraged,
		"a load works the phase out again from health (no save field)"
	)
	var ship: Game = main.make_game("mothership")
	ship.configure({})
	var maw := boss_of(ship)
	var lines: Array = []
	for left: float in [.9, .6, .3]:
		maw.hp = maw.max_hp * left
		lines.append(BossKit.phase_of(maw))
	check.call(lines == [1, 2, 3], "Maw's phases follow her own lines (%s)" % [lines])


static func _stagger(main, check: Callable) -> void:
	var g := _fight(main, "hickston", 1, 4.0)
	var e: Enemy = g.boss
	var heard: Array = []
	g.boss_staggered.connect(func(who: Enemy) -> void: heard.append(who))
	var hit := BossKit.moves(e.kind).stagger_hit(e)
	var rest := BossKit.moves(e.kind).stagger_rest(e)
	e.windup = .5
	e.aim_mark = [g.player.x, g.player.y, g.player.eye]
	e.hurt(hit * .6, g)
	var small := e.windup > 0.0 and heard.is_empty()
	g.clock += .2
	var before := Vector2(e.x, e.y)
	e.hurt(hit + 1.0, g)
	var big := (
		heard.size() == 1
		and e.windup == 0.0
		and e.aim_mark == null
		and Vector2(e.x, e.y).distance_to(before) > .1
	)
	g.clock += .2
	e.windup = .5
	e.aim_mark = [g.player.x, g.player.y, g.player.eye]
	e.hurt(hit + 1.0, g)
	var resting := heard.size() == 1 and e.windup > 0.0
	g.clock += rest
	e.hurt(hit + 1.0, g)
	check.call(small, "a hit under %d does not stagger the sheriff" % int(hit))
	check.call(big, "a hit over it staggers him back and cancels his wind-up")
	check.call(resting, "not again within his rest (%.1f s)" % rest)
	check.call(heard.size() == 2, "and again once it is over")
	var track: Game = _fight(main, "speedway", 1, 5.0)
	var car := boss_of(track)
	var at := Vector2(car.x, car.y)
	car.hurt(BossKit.moves(car.kind).stagger_hit(car) + 1.0, track)
	check.call(
		car.staggered_at == track.clock and Vector2(car.x, car.y).distance_to(at) > .1,
		"Boggs's car skids instead"
	)


static func _weak_spot(main, check: Callable) -> void:
	var g := _fight(main, "quarry")
	var e := boss_of(g)
	var weak: Array = []
	g.boss_weak_hit.connect(func(who: Enemy) -> void: weak.append(who))
	var hp := e.hp
	g.hit_point = Vector3(e.x, e.y, 1.0)
	e.hurt(10.0, g)
	var plain := hp - e.hp
	BossKit.set_moves(e.kind, DoubleWeak.new())
	hp = e.hp
	g.hit_point = Vector3(e.x, e.y, 1.0)
	g.hit_from = Vector2(g.player.x, g.player.y)
	e.hurt(10.0, g)
	var doubled := hp - e.hp
	hp = e.hp
	e.hurt(10.0, g)
	var unknown := hp - e.hp
	BossKit.set_moves(e.kind, null)
	check.call(is_equal_approx(plain, 10.0), "no weak spot: the damage as dealt (%.1f)" % plain)
	check.call(
		is_equal_approx(doubled, 20.0) and weak.size() == 1,
		"a weak spot's multiplier is applied, and announced (%.1f)" % doubled
	)
	check.call(
		is_equal_approx(unknown, 10.0) and g.hit_point == Vector3.INF,
		"only where a hit was seen to strike; hurt() forgets the point"
	)


static func _backup(main, check: Callable) -> void:
	var counts: Array = []
	var saved := false
	var full := true
	for level_id: String in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway"]:
		for difficulty: int in [0, 3]:
			var g := _fight(main, level_id, difficulty)
			var e := boss_of(g)
			var fight = g.features["boss_fight"]
			var before := g.enemies.size()
			# As many as DIFFICULTY says, where the arena has room for them unseen.
			var room: int = fight.hidden_spots(e, 99).size()
			e.hp = e.max_hp * .5 - 1.0
			e.hurt(1.0, g)
			var made := g.enemies.size() - before
			var want: int = fight.BACKUP[difficulty]
			counts.append("%s/%d: %d of %d (room %d)" % [level_id, difficulty, made, want, room])
			check.call(
				made == mini(want, room) and made >= 2,
				"%s on %s calls %d backup (%d)" % [e.kind, difficulty, want, made]
			)
			if level_id != "quarry":
				full = full and made == want
			var hidden := true
			for i in range(before, g.enemies.size()):
				var add: Enemy = g.enemies[i]
				var head: float = g.world.elevation(add.x, add.y) + .9
				var p := g.player
				var off := absf(Enemy.angle_delta(atan2(add.y - p.y, add.x - p.x), p.view_angle()))
				hidden = (
					hidden
					and add.alerted
					and (
						off >= fight.BEHIND
						or not g.world.visible(p.x, p.y, add.x, add.y, p.eye, head)
					)
				)
			check.call(hidden, "out of the player's sight (behind something or them), after them")
			if not saved and made > 0 and level_id == "hickston":
				saved = true
				var path := OS.get_cache_dir().path_join("clmr-boss-backup.json")
				SessionStore.save(g, path)
				var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
				check.call(
					back != null and back.enemies.size() == g.enemies.size(),
					(
						"the backup is still there after a save and a load"
						+ ("" if back != null else " (%s)" % SessionStore.last_error)
					)
				)
				# Every hand down, the backup too: more kills than the level's own.
				for foe: Enemy in g.enemies.duplicate():
					if foe.alive and foe.hostile:
						foe.hurt(9999.0, g)
				# As if the dormant ones had fallen too: every kill there is.
				g.kills = g.total_kills
				SessionStore.save(g, path)
				back = SessionStore.read(path, Callable(main, "make_game"), false)
				check.call(
					back != null and back.kills == g.kills and back.total_kills == g.total_kills,
					(
						"a save after the backup is killed too still loads (%d of %d)"
						% [g.kills, g.total_kills]
					)
				)
	print("    ", ", ".join(counts))
	check.call(full, "every arena but the quarry's cramped one has room for them all")
	var off := _fight(main, "fair")
	off.boss_backup = false
	var foe := boss_of(off)
	var count := off.enemies.size()
	foe.hp = foe.max_hp * .5 - 1.0
	foe.hurt(1.0, off)
	check.call(off.enemies.size() == count, "no backup when game.boss_backup is off")
	var ship := _fight(main, "mothership")
	var maw := boss_of(ship)
	var crew := ship.enemies.size()
	ship.features["boss_fight"].backup(maw, 2)
	check.call(ship.enemies.size() == crew, "Maw calls her own, not the shared backup")


static func _entrance(main, check: Callable) -> void:
	var tool := _fight(main, "fair")
	var intros: Array = []
	tool.boss_intro.connect(func(who: Enemy) -> void: intros.append(who))
	_ticks(tool, .1)
	check.call(
		tool.boss_hold == 0.0 and intros.size() == 1,
		"a tour or bench (lessons off): the fight begins without holding the world"
	)
	var bot := _fight(main, "fair")
	bot.lessons = true
	_ticks(bot, .1)
	check.call(
		bot.boss_hold == 0.0 and bot.features["boss_fight"].met.has(boss_of(bot).kind),
		"a tool driving real play (the walkthrough): no entrance either"
	)
	# Real play, as far as the entrance knows.
	BossKit.tool_intros = true
	var play := _fight(main, "hickston")
	play.lessons = true
	var met: Array = []
	play.boss_intro.connect(func(who: Enemy) -> void: met.append(who))
	_ticks(play, 1.0 / 60.0)
	var held := play.boss_hold > 0.0
	var clock := play.clock
	var fire := Game.Controls.new()
	fire.fire = true
	_ticks(play, .5, fire)
	var holding := play.boss_hold > 0.0 and play.clock == clock
	check.call(held and holding, "in play the entrance holds the world (fire held from before)")
	_ticks(play, 1.0 / 60.0)
	_ticks(play, 1.0 / 60.0, fire)
	check.call(play.boss_hold == 0.0, "a fresh press of fire cuts it short")
	var again := _fight(main, "fair")
	again.lessons = true
	_ticks(again, 1.0 / 60.0)
	var began := again.boss_hold > 0.0
	_ticks(again, BossKit.INTRO + .2)
	check.call(
		began and again.boss_hold == 0.0 and again.clock > 0.0, "left alone, it ends by itself"
	)
	var path := OS.get_cache_dir().path_join("clmr-boss-intro.json")
	SessionStore.save(play, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var twice: Array = []
	if back != null:
		back.lessons = true
		back.boss_intro.connect(func(who: Enemy) -> void: twice.append(who))
		var boss := boss_of(back)
		boss.dormant = false
		boss.alerted = true
		_ticks(back, .1)
	check.call(
		back != null and back.boss_hold == 0.0 and twice.is_empty() and met.size() == 1,
		"never twice for the same boss, a load between"
	)
	BossKit.tool_intros = false


static func _fall(main, check: Callable) -> void:
	var g := _fight(main, "sawmill")
	var e := boss_of(g)
	var downs: Array = []
	g.boss_down.connect(func(_who: Enemy, seconds: float) -> void: downs.append(seconds))
	_ticks(g, .5)
	var loot := g.pickups.size()
	e.hurt(e.hp + 1.0, g)
	var slow := g.slowmo
	var start := g.clock
	_ticks(g, .3 + 1.0 / 60.0)
	var after_hitstop := g.clock
	_ticks(g, .5)
	var slowed := g.clock - after_hitstop
	_ticks(g, 1.5)
	check.call(
		is_equal_approx(slow, g.features["boss_fight"].SLOWMO) and g.slowmo == 0.0,
		"the slow motion as a boss falls ends (%.2f s left)" % g.slowmo
	)
	check.call(
		slowed > .1 and slowed < .3,
		"the world runs at about a third meanwhile (%.2f of .5 s)" % slowed
	)
	check.call(g.clock - start > 1.0, "and at full speed after it")
	check.call(
		downs.size() == 1 and downs[0] >= .4,
		"its fall is announced with the fight's time (%s)" % [downs]
	)
	var rows: Array = g.features["boss_fight"].tally_rows()
	check.call(
		rows.size() == 1 and String(rows[0][0]) == "BOSS DOWN IN", "and a tally row: %s" % [rows]
	)
	# The finale drop plus the shower.
	check.call(
		g.pickups.size() - loot >= 5,
		"a shower of the chapter's ammo and food (%d)" % (g.pickups.size() - loot)
	)
	var lift := _fight(main, "quarry")
	var foe := boss_of(lift)
	foe.boss_phase = 3
	lift.ticked.emit(.2)
	check.call(
		is_equal_approx(lift.sound.score_lift, 1.06), "the boss loop lifts in the last phase"
	)
	foe.hp = 0.0
	lift.ticked.emit(.2)
	check.call(is_equal_approx(lift.sound.score_lift, 1.0), "and settles when it falls")
