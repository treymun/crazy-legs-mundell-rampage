## Checks of the game modes (src/modes/, CLAUDE.md "Modes"; tools/check_fixes.gd
## runs the quick part, this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/mode_check.gd
##       [-- seconds=<co-op bot play>] [level=<chapter>]
##
## The campaign stays the default and saves nothing new. Co-op: two players
## join, the county scales by the table, two bots play a chapter's opening,
## a partner down is revived by USE held beside them or comes back on their
## own, the game is lost only with everyone down, gun and ammo pickups go to
## both, bodies block each other, a co-op save loads as co-op with its
## partner, and the area attacks (steam, a burning slick, a race car, Maw's
## rolling pin and stomp ring) hit both players standing in them. Versus:
## spawn points in the range, the Crossroads and four boss arenas, enemies
## off, a frag for a kill and one off for a fall, a respawn with the kit, the
## frag and time limits ending the match with its results, team deathmatch's
## teammates out of each other's fire.
extends SceneTree

const Bot := preload("res://tools/mode_bot.gd")
const STEP := 1.0 / 60.0
const QUICK_SECONDS := 30.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var seconds := 90.0
	var level := "hickston"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg.begins_with("level="):
			level = arg.substr(6)
	var report := func(ok: bool, text: String) -> void:
		print("  ok   " if ok else "  FAIL ", text)
		if not ok:
			failures.append(text)
	run(main, report, seconds, level)
	print("")
	print("MODE CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The checks; `check` is check_fixes' (condition, text).
static func run(main, check: Callable, seconds := QUICK_SECONDS, level := "hickston") -> void:
	_campaign(main, check)
	_scaling(main, check)
	_coop_play(main, check, level, seconds)
	_revive(main, check)
	_respawn(main, check)
	_game_over(main, check)
	_pickups_and_bodies(main, check)
	_coop_save(main, check)
	_hazards(main, check)
	_rematch(main, check)
	_spawns(main, check)
	_deathmatch(main, check)
	_team(main, check)
	if seconds > QUICK_SECONDS:
		_versus_bots(main, check, Modes.ARENAS, seconds)
	else:
		_versus_bots(main, check, ["range"], seconds)


static func _made(main, id: String, mode := "", count := 1, options := {}) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	if mode != "":
		Modes.setup(g, mode, count, options)
	return g


static func _ticks(g: Game, n: int, given = null) -> void:
	for i in n:
		g.tick(STEP, given if given != null else Game.Controls.new())


## Down `p` (the mode notices on its own: player_hurt).
static func _down(g: Game, p: Player) -> void:
	g.cheats.god = false
	g.damage(500.0, null, "TEST", p)


static func _campaign(main, check: Callable) -> void:
	var g := _made(main, "hickston")
	check.call(Modes.mode_of(g) == Modes.CAMPAIGN, "a game is the campaign unless a mode is set")
	check.call(
		g.features["mode"].save().is_empty(), "the campaign saves nothing of the modes' (old saves)"
	)
	var hp: Array = []
	for e: Enemy in g.enemies:
		hp.append([e.kind, e.max_hp])
	_ticks(g, 2)
	var same := g.enemies.size() >= hp.size()
	for i in hp.size():
		# (A variant swapped in on the first tick has its own health.)
		if g.enemies[i].kind == String(hp[i][0]):
			same = same and is_equal_approx(g.enemies[i].max_hp, float(hp[i][1]))
	check.call(same, "the campaign's enemies keep their health (no scaling)")
	_down(g, g.player)
	check.call(g.defeated(), "the campaign: the one player down is the death screen")


static func _scaling(main, check: Callable) -> void:
	for count in [2, 4]:
		var g := _made(main, "hickston", Modes.COOP, count)
		var hand: Enemy = null
		var boss: Enemy = null
		var level_n: int = g.enemies.size()
		for e: Enemy in g.enemies:
			if e.hostile and Enemy.BOSS_TITLES.has(e.kind) and boss == null:
				boss = e
			elif e.hostile and hand == null and e.tactical():
				hand = e
		var hand_hp := hand.max_hp
		var boss_hp := boss.max_hp if boss != null else 0.0
		_ticks(g, 1)
		var table := CoopMode.scale_for(count)
		check.call(
			(
				g.players.size() == count
				and is_equal_approx(hand.max_hp, hand_hp * float(table[0]))
				and is_equal_approx(hand.hp, hand.max_hp)
				and boss != null
				and is_equal_approx(boss.max_hp, boss_hp * float(table[1]))
			),
			(
				"co-op %d players: hands' health x%.2f (%d -> %d), bosses' x%.2f (%d -> %d)"
				% [
					count,
					float(table[0]),
					hand_hp,
					hand.max_hp,
					float(table[1]),
					boss_hp,
					boss.max_hp if boss != null else 0.0
				]
			)
		)
		var posse: int = g.enemies.size() - level_n
		var hostile := 0
		for e: Enemy in g.enemies:
			if e.hostile:
				hostile += 1
		check.call(
			posse > 0 and g.total_kills == hostile,
			"co-op %d players: %d extra hands join beside the level's own" % [count, posse]
		)


## Two bots play a chapter's opening together.
static func _coop_play(main, check: Callable, level: String, seconds: float) -> void:
	var g := _made(main, level, Modes.COOP, 2)
	var bots := [Bot.new(), Bot.new()]
	var hurt := {0: 0.0, 1: 0.0}
	var downs: Array = []
	g.player_hurt.connect(
		func(amount: float, cause: String) -> void:
			hurt[g.player.slot] = float(hurt[g.player.slot]) + amount
			if g.player.health <= 0:
				downs.append("%s %.0f s %s" % [Modes.tag(g.player), g.clock, cause])
	)
	var played := 0
	var start_kills := g.kills
	for t in int(seconds * 60.0):
		if g.defeated() or g.won:
			break
		var given := {}
		for p: Player in g.players:
			if p.health > 0:
				g.focus(p)
				given[p.slot] = bots[p.slot].steer(g)
		g.focus(g.local_player)
		g.tick(STEP, given)
		for p: Player in g.players:
			g.focus(p)
			bots[p.slot].moved(g)
		g.focus(g.local_player)
		played += 1
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	print(
		(
			"    co-op %s %.0f s: kills %d, hurt %d/%d, downs %s, revives %d, health %d/%d, apart %.1f"
			% [
				level,
				played / 60.0,
				g.kills - start_kills,
				hurt[0],
				hurt[1],
				downs,
				g.features["mode"].revives,
				a.health,
				b.health,
				Vector2(a.x - b.x, a.y - b.y).length()
			]
		)
	)
	check.call(
		g.kills - start_kills >= 2 and played > 0,
		"two bots play %s's opening in co-op (%d kills in %.0f s)" % [level, g.kills, played / 60.0]
	)
	check.call(
		Vector2(a.x - b.x, a.y - b.y).length() < 30.0 or a.health <= 0 or b.health <= 0,
		"the partner keeps up with player one"
	)


static func _revive(main, check: Callable) -> void:
	var g := _made(main, "hickston", Modes.COOP, 2)
	_ticks(g, 1)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	_down(g, b)
	g.cheats.god = true
	check.call(b.health == 0 and b.down_at >= 0.0 and not g.defeated(), "a partner at 0 is down")
	var holding := Game.Controls.new()
	holding.hold = true
	Modes.place(g, b, a.x + .7, a.y, 0.0)
	_ticks(g, int(CoopMode.REVIVE_TIME * 60.0 * .5), {0: holding})
	var halfway := b.revive
	_ticks(g, 30, {0: Game.Controls.new()})
	var eased := b.revive < halfway
	_ticks(g, int(CoopMode.REVIVE_TIME * 60.0) + 40, {0: holding})
	check.call(
		halfway > 1.0 and eased and b.health == CoopMode.REVIVE_HEALTH and b.down_at < 0.0,
		(
			"USE held beside a downed partner for %.0f s stands them up with %d (halfway %.1f s)"
			% [CoopMode.REVIVE_TIME, CoopMode.REVIVE_HEALTH, halfway]
		)
	)


static func _respawn(main, check: Callable) -> void:
	var g := _made(main, "hickston", Modes.COOP, 2)
	_ticks(g, 1)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	Modes.place(g, b, a.x + 1.2, a.y, 0.0)
	_down(g, b)
	g.cheats.god = true
	Modes.place(g, a, a.x - 3.0, a.y, 0.0)
	if g.world.blocked(a.x, a.y, .25):
		Modes.place(g, a, a.x + 3.0, a.y, 0.0)
	_ticks(g, int((CoopMode.RESPAWN_AFTER - 1.0) * 60.0))
	var still := b.health == 0
	_ticks(g, 120)
	check.call(
		(
			still
			and b.health == CoopMode.RESPAWN_HEALTH
			and Vector2(a.x - b.x, a.y - b.y).length() < 3.2
		),
		(
			"left alone %.0f s a partner comes back beside the other with %d"
			% [CoopMode.RESPAWN_AFTER, CoopMode.RESPAWN_HEALTH]
		)
	)


static func _game_over(main, check: Callable) -> void:
	var g := _made(main, "hickston", Modes.COOP, 2)
	_ticks(g, 1)
	_down(g, g.players[1])
	var one := g.defeated()
	var clock := g.clock
	_ticks(g, 10)
	var going := g.clock > clock
	_down(g, g.players[0])
	var both := g.defeated()
	clock = g.clock
	_ticks(g, 10)
	check.call(
		not one and going and both and g.clock == clock,
		"co-op is lost only with everyone down (one down: play goes on)"
	)


static func _pickups_and_bodies(main, check: Callable) -> void:
	var g := _made(main, "hickston", Modes.COOP, 2)
	_ticks(g, 1)
	g.cheats.god = true
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var before: int = b.armory.reserve[Weapons.REVOLVER]
	var b_rinds := int(b.inventory["rinds"])
	g.add_pickup("bullets", a.x, a.y)
	g.add_pickup("rinds", a.x, a.y)
	Modes.place(g, b, a.x + 2.0, a.y, 0.0)
	if g.world.blocked(b.x, b.y, .25):
		Modes.place(g, b, a.x - 2.0, a.y, 0.0)
	_ticks(g, 1)
	check.call(
		b.armory.reserve[Weapons.REVOLVER] > before and int(b.inventory["rinds"]) == b_rinds,
		"co-op: an ammo pickup is the partner's too, a pocket item only the taker's"
	)
	# Bodies block: two walks into one standing still.
	var spot := Modes.open_spot_near(g, a.x, a.y)
	Modes.place(g, b, spot.x, spot.y, 0.0)
	var toward := atan2(b.y - a.y, b.x - a.x)
	a.angle = toward
	var walk := Game.Controls.new()
	walk.forward = 1.0
	var nearest := 99.0
	for i in 60:
		g.tick(STEP, {0: walk})
		nearest = minf(nearest, Vector2(a.x - b.x, a.y - b.y).length())
	check.call(
		nearest >= GameState.PLAYER_RADIUS * 2.0 - .02,
		"players block each other (walked into: %.2f apart at the nearest)" % nearest
	)


static func _coop_save(main, check: Callable) -> void:
	var g := _made(main, "hickston", Modes.COOP, 2)
	_ticks(g, 30)
	var b: Player = g.players[1]
	b.health = 61
	b.armory.owned[Weapons.SHOTGUN] = true
	b.armory.reserve[Weapons.SHOTGUN] = 7
	var doc: Dictionary = JSON.parse_string(JSON.stringify(SessionStore.snapshot(g)))
	var back: Game = SessionStore.restore(doc, main.make_game)
	var ok := back != null and Modes.mode_of(back) == Modes.COOP and back.players.size() == 2
	if ok:
		var c: Player = back.players[1]
		ok = (
			c.health == 61
			and c.armory.owned[Weapons.SHOTGUN]
			and c.armory.reserve[Weapons.SHOTGUN] == 7
			and Vector2(c.x - b.x, c.y - b.y).length() < .01
		)
		var hand := -1
		for i in g.enemies.size():
			if g.enemies[i].hostile and g.enemies[i].alive:
				hand = i
				break
		ok = ok and hand >= 0 and is_equal_approx(back.enemies[hand].max_hp, g.enemies[hand].max_hp)
	check.call(ok, "a co-op save loads as co-op: the partner's place, health and guns, the scaling")


## The area attacks bite everyone standing in them.
static func _hazards(main, check: Callable) -> void:
	# Steam (game_combat.gd update_hazards).
	var g := _made(main, "quarry", Modes.COOP, 2)
	_ticks(g, 1)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	Modes.place(g, b, a.x + .5, a.y, 0.0)
	g.hazards.clear()
	g.add_hazard("steam", a.x + .25, a.y, 1.0, 0.0, 1.0, 10)
	_ticks(g, 2)
	check.call(a.health < 100 and b.health < 100, "steam scalds both players standing in it")
	# A burning slick (features/boss_arenas.gd).
	g = _made(main, "bayou", Modes.COOP, 2)
	_ticks(g, 1)
	a = g.players[0]
	b = g.players[1]
	var arenas = g.features["boss_arenas"]
	Modes.place(g, b, a.x + .3, a.y, 0.0)
	if arenas.boss != null:
		arenas.slicks = [[a.x + .15, a.y, g.clock - arenas.SLICK_CATCH - .1, -10.0, -10.0]]
		arenas._burning()
	check.call(
		arenas.boss != null and a.health < 100 and b.health < 100,
		"a burning slick bites both players in it"
	)
	# A race car (features/race_laps.gd).
	g = _made(main, "speedway", Modes.COOP, 2)
	_ticks(g, 1)
	a = g.players[0]
	b = g.players[1]
	var laps = g.features["race_laps"]
	var hit_both := false
	if not laps.cars.is_empty():
		var car: Array = laps.cars[0]
		var ahead: Vector2 = laps._at(float(car[0]) + float(car[1]) * STEP)[0]
		Modes.place(g, a, ahead.x, ahead.y, 0.0)
		Modes.place(g, b, ahead.x + .25, ahead.y + .1, 0.0)
		_ticks(g, 1)
		hit_both = a.health < 100 and b.health < 100
	check.call(hit_both, "a race car runs down both players on the track")
	# Maw's rolling pin and stomp ring (features/mothership.gd).
	g = _made(main, "mothership", Modes.COOP, 2)
	_ticks(g, 1)
	a = g.players[0]
	b = g.players[1]
	var ship = g.features["mothership"]
	var pinned := false
	var ringed := false
	if ship.maw != null:
		Modes.place(g, b, a.x + .5, a.y, 0.0)
		ship.maw.aim_mark = [a.x + .25, a.y, a.eye]
		ship._slam()
		pinned = a.health < 100 and b.health < 100
		var ha := a.health
		var hb := b.health
		# A ring from a spot both stand the same distance from, as wide as that.
		var from := Vector2(a.x + .25, a.y - 2.0)
		var r := from.distance_to(Vector2(a.x, a.y))
		ship.rings = [[from.x, from.y, g.clock - (r - .6) / ship.RING_SPEED, false]]
		ship._rings(0.0)
		ringed = a.health < ha and b.health < hb
	check.call(pinned, "Maw's rolling pin comes down on both players under it")
	check.call(ringed, "Maw's stomp ring throws both players it rolls under")


static func _spawns(main, check: Callable) -> void:
	for name: String in Modes.ARENAS:
		var at := Modes.arena_of(name)
		var g: Game = main.make_game(String(at[0]))
		var box := Modes.arena_box(g, String(at[1]))
		var spots := Modes.spawn_points(g, box, 12)
		var inside := true
		for s: Array in spots:
			if box.size != Vector2i.ZERO and not box.has_point(Vector2i(int(s[0]), int(s[1]))):
				inside = false
			if g.world.blocked(float(s[0]), float(s[1]), .3):
				inside = false
		check.call(
			spots.size() >= 4 and inside,
			"versus arena %s: %d spawn points, open and inside it" % [name, spots.size()]
		)


## A versus game with p1 facing p2 a few steps away.
static func _facing(g: Game) -> void:
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var spot := Modes.open_spot_near(g, a.x, a.y)
	var dir := (spot - Vector2(a.x, a.y)).normalized()
	var far := Vector2(a.x, a.y) + dir * 2.5
	if g.world.blocked(far.x, far.y, .3) or not g.world.visible(a.x, a.y, far.x, far.y):
		far = spot
	Modes.place(g, b, far.x, far.y, 0.0)
	a.angle = atan2(b.y - a.y, b.x - a.x)
	a.pitch = (b.eye - .35 - a.eye) / maxf(.5, Vector2(b.x - a.x, b.y - a.y).length())
	a.pitch *= Renderer.base_focal


## p1 fires on p2 until p2 is down (or `limit` ticks).
static func _shoot_down(g: Game, limit := 900) -> void:
	var fire := Game.Controls.new()
	fire.fire = true
	var still := Game.Controls.new()
	for i in limit:
		if g.players[1].health <= 0:
			return
		var a: Player = g.players[0]
		var b: Player = g.players[1]
		a.angle = atan2(b.y - a.y, b.x - a.x)
		g.tick(STEP, {0: fire if i % 2 == 0 else still, 1: still})


static func _deathmatch(main, check: Callable) -> void:
	var g := _made(main, "range", Modes.DEATHMATCH, 2)
	_ticks(g, 1)
	var st = g.features["mode"]
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	check.call(
		(
			g.enemies.is_empty()
			and st.spawns.size() >= 4
			and Vector2(a.x - b.x, a.y - b.y).length() > 3.0
			and a.armory.owned[Weapons.SHOTGUN]
			and b.armory.owned[Weapons.SHOTGUN]
		),
		(
			"deathmatch: no enemies, %d spawn points, players start %.1f apart with the kit"
			% [st.spawns.size(), Vector2(a.x - b.x, a.y - b.y).length()]
		)
	)
	_facing(g)
	_shoot_down(g)
	check.call(
		b.health <= 0 and a.frags == 1 and b.deaths == 1 and b.downed_by == 0,
		"a kill by another player is their frag (p1 %d frags, p2 %d deaths)" % [a.frags, b.deaths]
	)
	_ticks(g, int(DeathmatchMode.RESPAWN_DELAY * 60.0) + 2)
	check.call(
		(
			b.health == 100
			and b.armory.owned[Weapons.SHOTGUN]
			and b.armory.loaded[Weapons.SHOTGUN] == Weapons.CAPACITY[Weapons.SHOTGUN]
		),
		(
			"a fragged player comes back %.0f s later with full health and the kit"
			% [DeathmatchMode.RESPAWN_DELAY]
		)
	)
	_down(g, b)
	check.call(b.frags == -1, "a fall to the world takes a frag off (%d)" % b.frags)
	_ticks(g, int(DeathmatchMode.RESPAWN_DELAY * 60.0) + 2)
	st.frag_limit = 2
	_facing(g)
	_shoot_down(g)
	_ticks(g, 1)
	var rows: Array = Modes.rules(g).scores(g, st)
	check.call(
		(
			st.match_over
			and g.showing_tally
			and rows.size() == 2
			and String(rows[0][0]) == "P1"
			and int(rows[0][1]) == 2
		),
		"the frag limit ends the match; the results put P1 first with 2 frags"
	)
	check.call(not g.defeated(), "versus is never the death screen")
	var timed := _made(main, "hub", Modes.DEATHMATCH, 2, {"time_limit": 2.0})
	_ticks(timed, 130)
	check.call(
		timed.features["mode"].match_over and timed.enemies.is_empty(),
		"the time limit ends a match (the Crossroads as the arena)"
	)
	var boss := _made(main, "hickston", Modes.DEATHMATCH, 2, {"arena": "hickston:boss"})
	_ticks(boss, 1)
	var box := Modes.arena_box(boss, "boss")
	var p: Player = boss.players[1]
	check.call(
		box.has_point(Vector2i(int(p.x), int(p.y))) and boss.enemies.is_empty(),
		"a boss arena as the arena: players start inside the sheriff's rodeo, nobody else"
	)


## Two bots fight a deathmatch in each arena (`arenas`) for `seconds`.
static func _versus_bots(main, check: Callable, arenas: Array, seconds: float) -> void:
	var total := 0
	for name: String in arenas:
		var at := Modes.arena_of(name)
		var g := _made(main, String(at[0]), Modes.DEATHMATCH, 2, {"arena": name})
		var bots := [Bot.new(), Bot.new()]
		for t in int(seconds * 60.0):
			if g.won:
				break
			var given := {}
			for p: Player in g.players:
				if p.health > 0:
					g.focus(p)
					given[p.slot] = bots[p.slot].steer(g)
			g.focus(g.local_player)
			g.tick(STEP, given)
			for p: Player in g.players:
				g.focus(p)
				bots[p.slot].moved(g)
			g.focus(g.local_player)
		var a: Player = g.players[0]
		var b: Player = g.players[1]
		print(
			(
				"    deathmatch %s %.0f s: frags %d/%d, deaths %d/%d"
				% [name, g.clock, a.frags, b.frags, a.deaths, b.deaths]
			)
		)
		total += a.deaths + b.deaths
	check.call(
		total > 0, "two bots fight deathmatches in %s (%d deaths)" % [", ".join(arenas), total]
	)


## A boss rematch in co-op: the partner beside player one at the door, the
## boss's health scaled for two, the fight begun by whichever walks in.
static func _rematch(main, check: Callable) -> void:
	var g := BossRematch.build(main.make_game, "boss")
	if g == null:
		check.call(false, "a rematch can be built for co-op")
		return
	g.configure({"difficulty": 1})
	var boss: Enemy = BossFight.of_kind(g, "boss")
	var whole := boss.max_hp
	Modes.setup(g, Modes.COOP, 2)
	Modes.gather(g)
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var beside := Vector2(a.x - b.x, a.y - b.y).length() < 3.0
	_ticks(g, 1)
	check.call(
		beside and is_equal_approx(boss.max_hp, whole * float(CoopMode.scale_for(2)[1])),
		"a co-op rematch: the partner at the door beside player one, the boss scaled for two"
	)
	# Player two alone walks into the arena (player one back at the chapter's
	# start): the fight begins for the party.
	var start: Array = g.level.spawn
	Modes.place(g, a, float(start[0]), float(start[1]), 0.0)
	Modes.place(g, b, boss.x - 3.0, boss.y, 0.0)
	if g.world.blocked(b.x, b.y, .25):
		Modes.place(g, b, boss.x + 3.0, boss.y, PI)
	boss.alerted = true
	g.focus(a)
	check.call(
		not BossKit.in_arena(g, boss) and BossKit.party_in_arena(g, boss),
		"a boss's fight begins when any player walks into its arena"
	)


static func _team(main, check: Callable) -> void:
	var g := _made(main, "range", Modes.TEAM, 4)
	_ticks(g, 1)
	var r := Modes.rules(g)
	var p: Array = g.players
	check.call(
		(
			p[0].team == 0
			and p[2].team == 0
			and p[1].team == 1
			and r.hurt_scale(g, p[0], p[2], false) == 0.0
			and r.hurt_scale(g, p[0], p[2], true) == 0.0
			and r.hurt_scale(g, p[0], p[1], false) == 1.0
			and r.hurt_scale(g, p[0], p[0], true) == 1.0
		),
		"team deathmatch: RED and BLUE by slot, teammates out of each other's fire"
	)
	p[0].frags = 3
	p[2].frags = 2
	p[1].frags = 4
	check.call(
		r.leader_score(g) == 5 and r.winner(g) == "RED", "a team's score is its players' frags"
	)
