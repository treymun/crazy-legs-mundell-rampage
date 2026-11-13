## Checks of the multiplayer foundation (src/players.gd, src/game_snapshot.gd;
## tools/check_fixes.gd runs the quick part; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/net_check.gd
##       [-- levels=hickston,fair] [ticks=6000] [after=1200] [quick]
##
## Every field of Game and every feature is put down as simulation or
## presentation (GameSnapshot's lists). Two games fed the same controls (the
## bot's, recorded) stay identical, snapshot for snapshot. A snapshot put onto
## a fresh game gives the same snapshot back, as bytes and as a delta too, and
## the fresh game then runs on beside the first for `after` ticks, still
## identical (the snapshot carries all the play there is). Two players: both
## are hunted, the second is hurt by enemies and blasts, takes pickups, opens a
## door with USE; two bots play a chapter for three minutes, and two such
## games stay identical and a snapshot of one round-trips. The host
## (game_host.gd): its game has no looks-only feature and no sound; it and an
## ordinary game fed the same controls stay identical; a mirror (game_mirror.gd)
## over a fresh client game kept up by deltas alone (and once by a whole
## snapshot onto its running game) matches the host every time it is compared,
## with one, two and four players; deltas merge.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0
const QUICK_TICKS := 1500
const QUICK_AFTER := 600
## The host's tick, and how often a host check compares whole snapshots.
const HOST_STEP := GameHost.STEP
const COMPARE_EVERY := 240
const QUICK_HOST := 1200

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var args := OS.get_cmdline_user_args()
	var levels: Array = ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
	var ticks := 6000
	var after := 1200
	for arg: String in args:
		if arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(","))
		elif arg.begins_with("ticks="):
			ticks = int(arg.substr(6))
		elif arg.begins_with("after="):
			after = int(arg.substr(6))
	if args.has("quick"):
		levels = ["hickston"]
		ticks = QUICK_TICKS
		after = QUICK_AFTER
	var report := func(ok: bool, text: String) -> void:
		print("  ok   " if ok else "  FAIL ", text)
		if not ok:
			failures.append(text)
	run(main, report, levels, ticks, after)
	print("")
	print("NET CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The checks; `check` is check_fixes' (condition, text).
static func run(
	main, check: Callable, levels := ["hickston"], ticks := QUICK_TICKS, after := QUICK_AFTER
) -> void:
	var first: Game = _made(main, String(levels[0]))
	var loose := GameSnapshot.unclassified(first)
	check.call(
		loose.is_empty(),
		(
			"every Game field and feature is simulation or presentation (GameSnapshot)"
			+ ("" if loose.is_empty() else ": " + ", ".join(loose))
		)
	)
	for id: String in levels:
		_lockstep(main, check, id, ticks, after)
	# Two players for three minutes (the quick part: as long as the rest).
	_two_players(main, check, String(levels[0]), ticks if ticks <= QUICK_TICKS else 10800)
	# The host and its mirrors (game_host.gd, game_mirror.gd).
	_merge_rules(check)
	_host_game(main, check, String(levels[0]))
	var host_ticks := QUICK_HOST if ticks <= QUICK_TICKS else ticks
	for id: String in levels:
		_host_and_mirror(main, check, id, host_ticks, 1)
	for players: int in [2, 4]:
		_host_and_mirror(main, check, String(levels[0]), host_ticks, players)


static func _made(main, id: String, players := 1) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	# The chapters before it played (a save checks the campaign's history).
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	for i in players - 1:
		# A step off player one, where the floor is open (as a host places them).
		GameHost.join_near(g)
	return g


## Two games, the bot's controls recorded and fed to both; then a snapshot of
## the first onto a fresh third, which runs on beside it.
static func _lockstep(main, check: Callable, id: String, ticks: int, after: int) -> void:
	var a := _made(main, id)
	var b := _made(main, id)
	for g: Game in [a, b]:
		g.cheats.god = true
	var pilot := Pilot.new()
	pilot.as_controls = true
	var started := Time.get_ticks_msec()
	var split := -1
	var base := {}
	for t in ticks:
		var c := pilot.steer(a)
		a.tick(STEP, c)
		b.tick(STEP, c)
		pilot.moved(a)
		if t == 599:
			base = GameSnapshot.capture(a)
		if split < 0 and (t + 1) % 600 == 0:
			var sa := GameSnapshot.capture(a)
			var sb := GameSnapshot.capture(b)
			if not GameSnapshot.same(sa, sb):
				split = t + 1
				print("    first difference: ", GameSnapshot.first_difference(sa, sb))
	var sim_ms := Time.get_ticks_msec() - started
	check.call(
		split < 0,
		(
			"%s: two games fed the same controls are identical over %d ticks%s"
			% [id, ticks, "" if split < 0 else " (they part by tick %d)" % split]
		)
	)
	var t0 := Time.get_ticks_usec()
	var snap := GameSnapshot.capture(a)
	var capture_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var unknown: Array = snap["unknown"]
	check.call(
		unknown.is_empty(),
		(
			"%s: the snapshot knows every class it meets %s"
			% [id, "" if unknown.is_empty() else str(unknown)]
		)
	)
	var bytes := GameSnapshot.to_bytes(snap)
	check.call(
		GameSnapshot.same(GameSnapshot.from_bytes(bytes), snap),
		(
			"%s: a snapshot comes back from its bytes (%d bytes, %.1f ms to take)"
			% [id, bytes.size(), capture_ms]
		)
	)
	if not base.is_empty():
		var change = GameSnapshot.delta(base, snap)
		var back = GameSnapshot.patch(base, change)
		check.call(
			GameSnapshot.same(back, snap),
			(
				"%s: a delta from tick 600 patches back to the snapshot (%d bytes)"
				% [id, GameSnapshot.to_bytes(change).size()]
			)
		)
	var c2 := _made(main, id)
	c2.cheats.god = true
	t0 = Time.get_ticks_usec()
	var applied := GameSnapshot.apply(c2, snap)
	var apply_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var again := GameSnapshot.capture(c2)
	var where := GameSnapshot.first_difference(snap, again)
	check.call(
		applied and where == "",
		(
			"%s: capture, apply to a fresh game, capture is the same (%.1f ms to apply)%s"
			% [id, apply_ms, "" if where == "" else ": " + where]
		)
	)
	var parted := -1
	var parted_at := ""
	for t in after:
		var c := pilot.steer(a)
		a.tick(STEP, c)
		c2.tick(STEP, c)
		pilot.moved(a)
		if parted < 0 and ((t + 1) % 60 == 0 or t == after - 1):
			var sa := GameSnapshot.capture(a)
			var sc := GameSnapshot.capture(c2)
			if not GameSnapshot.same(sa, sc):
				parted = t + 1
				parted_at = GameSnapshot.first_difference(sa, sc)
	check.call(
		parted < 0,
		(
			"%s: the game made from the snapshot runs on identical for %d ticks%s"
			% [id, after, "" if parted < 0 else " (parts by tick %d: %s)" % [parted, parted_at]]
		)
	)
	print("    %s: %d ticks of two games in %d ms" % [id, ticks, sim_ms])


## Two players on one chapter: both bots play, the enemies go after either,
## the second is hurt, takes pickups and opens a door; two such games stay
## identical and a snapshot of one round-trips.
static func _two_players(main, check: Callable, id: String, ticks: int) -> void:
	var a := _made(main, id, 2)
	var b := _made(main, id, 2)
	var p2: Player = a.players[1]
	check.call(
		a.players.size() == 2 and p2.slot == 1 and a.local_player == a.players[0],
		"%s: a second player joins in slot 1; player one stays local" % id
	)
	check.call(
		(
			not is_same(p2.armory, a.players[0].armory)
			and not is_same(p2.inventory, a.players[0].inventory)
		),
		"a second player has guns and pockets of their own"
	)
	check.call(
		is_same(p2.keys, a.players[0].keys) == bool(Players.SHARED["keys"]),
		"the party's keys are shared as Players.SHARED says"
	)
	_door_for_two(main, check, id)
	_blast_for_two(main, check, id)
	_pickups_for_two(main, check, id)
	_enemy_for_two(main, check, id)
	var hurt := [0.0]
	var took := [0]
	a.player_hurt.connect(
		func(amount: float, _cause: String) -> void:
			if a.player == p2:
				hurt[0] += amount
	)
	a.pickup_taken.connect(
		func(_name: String) -> void:
			if a.player == p2:
				took[0] += 1
	)
	var pilots := [Pilot.new(), Pilot.new()]
	for pilot in pilots:
		pilot.as_controls = true
	var hunted := {}
	var split := -1
	var played := 0
	for t in ticks:
		if not Players.anyone_alive(a):
			break
		var given := {}
		for p: Player in a.players:
			if p.health <= 0:
				continue
			a.focus(p)
			given[p.slot] = pilots[p.slot].steer(a)
		a.focus(a.local_player)
		a.tick(STEP, given)
		b.tick(STEP, given)
		for p: Player in a.players:
			a.focus(p)
			pilots[p.slot].moved(a)
		a.focus(a.local_player)
		played += 1
		for e: Enemy in a.enemies:
			if e.hunted != null and e.alive and e.hostile:
				hunted[e.hunted.slot] = int(hunted.get(e.hunted.slot, 0)) + 1
		if split < 0 and (t + 1) % 600 == 0:
			if not GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)):
				split = t + 1
	print(
		(
			"    two players %d ticks: hunted by slot %s, player two hurt %d, took %d, health %d/%d"
			% [played, hunted, hurt[0], took[0], a.players[0].health, p2.health]
		)
	)
	check.call(hunted.has(0) and hunted.has(1), "%s: the enemies go after both players" % id)
	check.call(
		split < 0, "two two-player games fed the same controls stay identical (%d ticks)" % played
	)
	var snap := GameSnapshot.capture(a)
	var c2 := _made(main, id)
	var applied := GameSnapshot.apply(c2, snap)
	var where := GameSnapshot.first_difference(snap, GameSnapshot.capture(c2))
	check.call(
		applied and c2.players.size() == 2 and where == "",
		(
			"a two-player snapshot round-trips onto a fresh game%s"
			% ("" if where == "" else ": " + where)
		)
	)


## Shells, a beer and a key at player two's feet: two takes them, the shells
## and the beer are two's own, the key the party's (Players.SHARED).
static func _pickups_for_two(main, check: Callable, id: String) -> void:
	var g := _made(main, id, 2)
	var p1: Player = g.players[0]
	var p2: Player = g.players[1]
	var shells := [p1.armory.reserve[Weapons.SHOTGUN], p2.armory.reserve[Weapons.SHOTGUN]]
	for name: String in ["shells", "beer", "key_brass"]:
		g.add_pickup(name, p2.x, p2.y)
	g.tick(STEP, {})
	check.call(
		(
			p2.armory.reserve[Weapons.SHOTGUN] > int(shells[1])
			and p1.armory.reserve[Weapons.SHOTGUN] == int(shells[0])
			and int(p2.inventory["beer"]) == 1
			and int(p1.inventory["beer"]) == 0
		),
		"%s: player two takes shells and a beer for themselves" % id
	)
	check.call(
		p2.keys.has("key_brass") and p1.keys.has("key_brass") == bool(Players.SHARED["keys"]),
		"%s: a key player two takes is the party's" % id
	)


## A hand woken a step from player two, player one far off: it goes after
## two and hurts two, not one.
static func _enemy_for_two(main, check: Callable, id: String) -> void:
	var g := _made(main, id, 2)
	var p1: Player = g.players[0]
	var p2: Player = g.players[1]
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		if not e.hostile or not e.alive or Enemy.BOSS_TITLES.has(e.kind):
			continue
		if Vector2(e.x - p1.x, e.y - p1.y).length() < 20.0:
			continue
		for k in 8:
			var at := Vector2(e.x, e.y) + Vector2.from_angle(k * TAU / 8.0) * 1.6
			if not g.world.blocked(at.x, at.y, .25) and g.world.visible(e.x, e.y, at.x, at.y):
				p2.x = at.x
				p2.y = at.y
				foe = e
				break
		if foe != null:
			break
	if foe == null:
		check.call(true, "%s: no hand to try against player two" % id)
		return
	g.spawn_grace = 0.0
	var one := p1.health
	var after_two := false
	for t in 900:
		g.tick(STEP, {})
		after_two = after_two or foe.hunted == p2
		if p2.health < 100:
			break
	check.call(
		after_two and p2.health < 100 and p1.health == one,
		(
			"%s: a %s next to player two goes after two and hurts two (%d), not one"
			% [id, foe.kind, p2.health]
		)
	)


## Player two stands at a plain door and presses USE (by controls): it opens.
static func _door_for_two(main, check: Callable, id: String) -> void:
	var g := _made(main, id, 2)
	var door: LevelData.Door = null
	for d: LevelData.Door in g.world.doors:
		if not d.opened and d.key == "" and not d.secret and not d.blast_only:
			if not g.world.controlled_doors.has(Vector2i(d.x, d.y)):
				door = d
				break
	if door == null:
		check.call(true, "%s: no plain door to try player two on" % id)
		return
	var p2: Player = g.players[1]
	var centre := door.center()
	# Stand off the door on whichever side is open floor, facing it.
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var at := centre + side * .9
		if not g.world.blocked(at.x, at.y, .2):
			p2.x = at.x
			p2.y = at.y
			p2.angle = (-side).angle()
			break
	var c := Game.Controls.new()
	c.use = true
	g.tick(STEP, {1: c})
	check.call(door.opened, "%s: player two opens a door with USE" % id)


## A stick of dynamite goes off by player two, far from player one: two is
## hurt (a backblast), one is not.
static func _blast_for_two(main, check: Callable, id: String) -> void:
	var g := _made(main, id, 2)
	var p1: Player = g.players[0]
	var p2: Player = g.players[1]
	p2.x += 0.0
	p1.x = p2.x + 30.0 if not g.world.blocked(p2.x + 30.0, p2.y, .2) else p1.x
	var far := Vector2(p1.x - p2.x, p1.y - p2.y).length() > 8.0
	var one := p1.health
	var two := p2.health
	g.focus(p2, true)
	g.explode(GameState.Shot.new(p2.x + .3, p2.y, p2.eye - .3, 0, 0, 0, "tnt", 0.0, false, 0))
	g.focus(g.local_player)
	check.call(
		p2.health < two and (p1.health == one or not far),
		(
			"%s: a blast by player two hurts player two (%d -> %d), not player one far off"
			% [id, two, p2.health]
		)
	)


# ------------------------------------------------------------ host and mirror


## A host's game: the simulation's features and none of the looks-only ones,
## no sound but a QuietSound, no voices.
static func _host_game(main, check: Callable, id: String) -> void:
	var host := GameHost.new(id, 2, {"difficulty": 1})
	var plain: Game = main.make_game(id)
	var g := host.game
	var looks: Array = []
	for key: String in plain.features:
		var file: String = plain.features[key].get_script().resource_path.get_file()
		if Features.LOOKS.has(file.get_basename()):
			looks.append(key)
	looks.sort()
	var listed: Array = GameSnapshot.LOOKS_FEATURES.duplicate()
	listed.sort()
	check.call(
		looks == listed,
		"Features.LOOKS are GameSnapshot.LOOKS_FEATURES (%d features)" % looks.size()
	)
	var extra: Array = []
	for key: String in g.features:
		if not GameSnapshot.SIM_FEATURES.has(key):
			extra.append(key)
	var missing: Array = []
	for key: String in plain.features:
		if GameSnapshot.SIM_FEATURES.has(key) and not g.features.has(key):
			missing.append(key)
	check.call(
		g.host and extra.is_empty() and missing.is_empty(),
		(
			"%s: a host's game has the simulation's features and no looks-only ones%s"
			% [id, "" if extra.is_empty() and missing.is_empty() else ": %s %s" % [extra, missing]]
		)
	)
	check.call(
		g.sound is QuietSound and g.speaker is QuietSound and g.players[1].voice == null,
		"%s: a host's game makes no sound (QuietSound) and gives players no voice" % id
	)


## A host's game and an ordinary one fed the same controls (bots playing every
## player, god mode) stay identical; a mirror over a fresh client game takes
## one whole snapshot, then only deltas every DELTA_EVERY ticks, and after
## each matches the host (its patched snapshot is a fresh capture of the host,
## and a capture of its game is too); halfway a whole snapshot is put onto the
## mirror's running game and it carries on.
static func _host_and_mirror(main, check: Callable, id: String, ticks: int, players: int) -> void:
	var host := GameHost.new(id, players, {"difficulty": 1})
	var plain := _made(main, id, players)
	for g: Game in [host.game, plain]:
		g.cheats.god = true
	var mirror := GameHost.mirror_for(main.make_game(id))
	var took := mirror.take(host.snapshot())
	var pilots: Array = []
	for i in players:
		var pilot := Pilot.new()
		pilot.as_controls = true
		pilots.append(pilot)
	var parted := ""
	var tracked := ""
	var mirrored := ""
	var refused := 0
	var sizes: Array = []
	var delta_ms: Array = []
	var take_ms: Array = []
	var resynced := false
	var compared := 0
	for t in ticks:
		var given := {}
		for p: Player in plain.players:
			if p.health > 0:
				plain.focus(p)
				given[p.slot] = pilots[p.slot].steer(plain)
		plain.focus(plain.local_player)
		plain.tick(HOST_STEP, given)
		host.step(given)
		for p: Player in plain.players:
			plain.focus(p)
			pilots[p.slot].moved(plain)
		plain.focus(plain.local_player)
		if host.tick % GameHost.DELTA_EVERY == 0:
			if not resynced and t >= ticks / 2:
				# A client that lost its way: a whole snapshot onto its running game.
				resynced = true
				took = mirror.take(host.snapshot()) and took
			else:
				var d := host.delta_since(mirror.acked)
				delta_ms.append(host.delta_ms)
				sizes.append(d.size())
				if not mirror.take(d):
					refused += 1
				take_ms.append(mirror.take_ms)
		if (t + 1) % COMPARE_EVERY == 0 or t == ticks - 1:
			if host.tick != mirror.acked:
				mirror.take(host.delta_since(mirror.acked))
			compared += 1
			var sh := GameSnapshot.capture(host.game)
			if parted == "":
				var sp := GameSnapshot.capture(plain)
				if not GameSnapshot.same(sh, sp):
					parted = "tick %d: %s" % [t + 1, GameSnapshot.first_difference(sp, sh)]
			if tracked == "" and not GameSnapshot.same(mirror.full, sh):
				tracked = "tick %d: %s" % [t + 1, GameSnapshot.first_difference(sh, mirror.full)]
			if mirrored == "":
				var sm := GameSnapshot.capture(mirror.game)
				if not GameSnapshot.same(sm, sh):
					mirrored = "tick %d: %s" % [t + 1, GameSnapshot.first_difference(sh, sm)]
	var who := "%s, %d player%s" % [id, players, "" if players == 1 else "s"]
	(
		check
		. call(
			parted == "",
			(
				"%s: a host's game and an ordinary one fed the same controls are identical over %d ticks%s"
				% [who, ticks, "" if parted == "" else " (%s)" % parted]
			)
		)
	)
	check.call(
		tracked == "",
		(
			"%s: the host's deltas patch a client's snapshot to the host's exactly (%d looks)%s"
			% [who, compared, "" if tracked == "" else " (%s)" % tracked]
		)
	)
	check.call(
		took and refused == 0 and mirrored == "",
		(
			(
				"%s: a mirror kept up by deltas alone (and one whole snapshot onto its running"
				+ " game) matches the host%s"
			)
			% [
				who,
				"" if mirrored == "" and refused == 0 else " (%s; %d refused)" % [mirrored, refused]
			]
		)
	)
	print(
		(
			"    %s: %d deltas, median %d bytes (largest %d), %.2f ms to make, %.2f ms to put on"
			% [
				who,
				sizes.size(),
				_median(sizes),
				0 if sizes.is_empty() else sizes.max(),
				_median(delta_ms),
				_median(take_ms)
			]
		)
	)


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


## Merged deltas and patches agree: two deltas one after the other are their
## merge, with keys going and coming back.
static func _merge_rules(check: Callable) -> void:
	var a := {"x": 1, "d": {"k": 1, "j": [1]}, "gone": 3}
	var b := {"x": 2, "d": {"k": 1, "j": [2], "n": {"z": 1}}, "new": 4}
	var c := {"x": 2, "d": {"j": [2], "n": {"z": 2}}, "new": 5, "gone": 6}
	var ab = GameSnapshot.delta(a, b)
	var bc = GameSnapshot.delta(b, c)
	var merged = GameSnapshot.merge(ab, bc)
	check.call(
		(
			merged != null
			and GameSnapshot.same(GameSnapshot.patch(a, merged), c)
			and GameSnapshot.same(GameSnapshot.patch(a, ab), b)
		),
		"deltas merge: patch(a, merge(delta(a, b), delta(b, c))) == c"
	)
