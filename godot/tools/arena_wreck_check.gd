## Checks that the boss arenas wreck and the bosses' gear comes off
## (features/arena_wreck.gd, features/boss_gear.gd; tools/check_fixes.gd runs
## it, this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/arena_wreck_check.gd
##
## For each of the eight bosses, in its rematch's game: every step's props are
## where bosses.cfg says and a toppled one's lane is open floor; with its
## health brought down past each step, the step fires, its pieces come down,
## hurt the player in their way and lie as cover; nothing fires before then,
## nor with BOSS ARENAS WRECK off. The wreck travels in a snapshot onto a
## fresh game, and the boss checkpoint's retry (and a rematch, a fresh game)
## puts the arena back as the level made it. Each piece of gear is shot off
## where bosses.cfg puts it, flies, lands on the floor and stays off the
## model; the piece's mesh is cut from the model.
extends SceneTree

const WreckLanes := preload("res://tools/wreck_lanes.gd")
const STEP := 1.0 / 60.0
const KINDS := ["boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "maw"]

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
	print("ARENA WRECK CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable) -> void:
	print("BOSS ARENAS WRECK (steps at their phases, cover, reset) AND GEAR SHOT OFF")
	var models := ActorModels.new(main.art)
	for kind: String in KINDS:
		_steps(main, check, kind)
		_reset(main, check, kind)
		_gear(main, check, kind, models)
	_off(main, check)
	_wave(main, check)


static func _game(main, kind: String) -> Game:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.spawn_grace = 0.0
	return g


static func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


## The boss held still where it stands (its own moves would walk it into
## the lanes and fire at the player): only its health matters here.
static func _hold(e: Enemy) -> void:
	e.stun = 10.0
	e.cooldown = 10.0


static func _hidden(g: Game) -> int:
	var n := 0
	for board: LevelData.Billboard in g.world.billboards:
		if board.hidden:
			n += 1
	return n


static func _steps(main, check: Callable, kind: String) -> void:
	var g := _game(main, kind)
	var e := BossFight.of_kind(g, kind)
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	var mine: Array = []
	for i in f.steps.size():
		if f.foes[i] == e:
			mine.append(i)
	check.call(not mine.is_empty(), "%s: its arena has wreck steps (%d)" % [kind, mine.size()])
	# Every step's props stand where it says; a lane is open floor.
	for i: int in mine:
		var step: Dictionary = f.steps[i]
		var what := str(step["do"])
		if what == "topple":
			for spot: Array in step["spots"]:
				var board := f._find_board(str(step["image"]), spot[0], spot[1])
				check.call(board != null, "%s: a %s stands at %s" % [kind, step["image"], spot])
				if board == null:
					continue
				var dir: float = spot[2]
				var clear := WreckLanes.lane(g.world, board, dir) < 0.0
				check.call(
					clear, "%s: the %s at %s falls on open floor" % [kind, step["image"], spot]
				)
		elif what == "fall":
			for spot: Array in step["spots"]:
				check.call(
					f._find_lamp(str(step["image"]), spot[0], spot[1]) != null,
					"%s: a lamp hangs at %s" % [kind, spot]
				)
	var volumes := f.added.size()
	_hold(e)
	_ticks(g, 30)
	check.call(f.pieces.is_empty(), "%s: nothing comes down at full health" % kind)
	# Down past each step in turn: it fires, its pieces land and lie as cover.
	var p := g.player
	for i: int in mine:
		var step: Dictionary = f.steps[i]
		var at: float = step["at"]
		var had := f.pieces.size()
		var hid := _hidden(g)
		if str(step["do"]) == "scatter":
			var names: Array = step["images"]
			for board: LevelData.Billboard in g.world.billboards:
				if names.has(board.image) and not board.hidden:
					e.x = board.x - 2.0
					e.y = board.y
					break
		e.hp = e.max_hp * (at - .01)
		BossKit.phase_check(e, g)
		_hold(e)
		g.tick(STEP, Game.Controls.new())
		var fired: int = f.fired[i]
		check.call(fired >= 0, "%s: step %d (%s) fires at %.2f" % [kind, i, step["do"], at])
		var what := str(step["do"])
		if what == "wave" or what == "blowout":
			_ticks(g, 30)
			continue
		var fresh := f.pieces.slice(had)
		check.call(
			not fresh.is_empty(), "%s: step %d sets %d piece(s) going" % [kind, i, fresh.size()]
		)
		if what != "scatter":
			check.call(
				_hidden(g) > hid or what == "fall", "%s: step %d takes its props over" % [kind, i]
			)
		# Stand the player where the first piece comes down, god mode off.
		var first: Dictionary = fresh[0] if not fresh.is_empty() else {}
		var health := p.health
		if what != "scatter" and not first.is_empty():
			var fx: float = first["x"]
			var fy: float = first["y"]
			var dir: float = first["dir"]
			var reach: float = .35 if what == "topple" else 0.0
			p.x = fx + cos(dir) * reach
			p.y = fy + sin(dir) * reach
			if what == "fall":
				p.x = fx + .65
			p.eye = g.world.stand(p) + .95
			g.cheats.god = false
		_hold(e)
		_ticks(g, 60 * 5)
		g.cheats.god = true
		var down := true
		for piece: Dictionary in fresh:
			var stage: int = piece["stage"]
			down = down and stage == ArenaWreckFeature.DOWN
		check.call(down, "%s: step %d's pieces come down and lie" % [kind, i])
		if what != "scatter" and not first.is_empty():
			check.call(
				p.health < health,
				"%s: step %d hurts the player it lands on (%d -> %d)" % [kind, i, health, p.health]
			)
			p.health = 100
		check.call(
			f.added.size() > volumes,
			"%s: step %d leaves cover (%d boxes, %d before)" % [kind, i, f.added.size(), volumes]
		)
		volumes = f.added.size()
		# A piece lying is in the way of bodies and shots.
		if what == "topple" and not first.is_empty():
			var fx: float = first["x"]
			var fy: float = first["y"]
			var dir: float = first["dir"]
			var mx := fx + cos(dir) * 1.0
			var my := fy + sin(dir) * 1.0
			var foot: float = first["z"]
			var floor_z: float = g.world.floor_under(mx, my, foot + .4)
			(
				check
				. call(
					g.world.blocked(mx, my, .1, floor_z + .2),
					(
						"%s: step %d's piece lies across its lane as cover (%.1f, %.1f at %.2f; player %.1f, %.1f)"
						% [kind, i, mx, my, floor_z, p.x, p.y]
					)
				)
			)
	# The wreck travels: a snapshot onto a fresh game puts the same arena down.
	var copy := _game(main, kind)
	GameSnapshot.apply(copy, GameSnapshot.capture(g))
	(
		check
		. call(
			(
				copy.world.collision_volumes.size() == g.world.collision_volumes.size()
				and _hidden(copy) == _hidden(g)
			),
			(
				"%s: a snapshot carries the wreck (%d/%d volumes, %d/%d hidden)"
				% [
					kind,
					copy.world.collision_volumes.size(),
					g.world.collision_volumes.size(),
					_hidden(copy),
					_hidden(g),
				]
			)
		)
	)


## The checkpoint's retry and a rematch start with the arena whole.
static func _reset(main, check: Callable, kind: String) -> void:
	# The chapter itself (a replay run, its checkpoint under the cache folder).
	var level_id := String(BossRematch.LEVEL_OF[kind])
	main.return_to_title(true)
	main.start(level_id, null, [], true, null)
	var g: Game = main.game
	g.cheats.god = true
	g.spawn_grace = 99.0
	var e := BossFight.of_kind(g, kind)
	e.dormant = false
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	var volumes := g.world.collision_volumes.size()
	var props := g.props.size()
	e.hp = e.max_hp * .05
	BossKit.phase_check(e, g)
	_hold(e)
	_ticks(g, 60 * 6)
	var wrecked := g.world.collision_volumes.size() != volumes or _hidden(g) > 0
	print(
		"DEBUG ",
		kind,
		" fired ",
		f.fired,
		" pieces ",
		f.pieces.size(),
		" alive ",
		e.alive,
		" hp ",
		e.hp,
		" clock ",
		g.clock,
		" wrecks ",
		g.boss_wrecks,
		" steps ",
		f.steps.size()
	)
	check.call(wrecked, "%s: brought low, the arena is wrecked" % kind)
	# The checkpoint's way back: its save (kept in memory, not the shared
	# cache folder), loaded, then BossDoor's retry.
	var point = g.features["boss_checkpoint"]
	point.door = [g.player.x, g.player.y, 0.0]
	point.fight_kind = kind
	point.taken[kind] = "check"
	var doc := SessionStore.snapshot(g)
	check.call(not doc.is_empty(), "%s: the boss checkpoint saves mid-wreck" % kind)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(doc))
	var loaded := SessionStore.restore(parsed, Callable(main, "make_game"), g.replay)
	var back: Game = BossDoor.at_door(loaded) if loaded != null else null
	check.call(back != null, "%s: the boss checkpoint loads (%s)" % [kind, SessionStore.last_error])
	if back != null:
		var wf: ArenaWreckFeature = back.features["arena_wreck"]
		var whole := true
		for fired: int in wf.fired:
			whole = whole and fired < 0
		var level_volumes: int = main.make_game(level_id).world.collision_volumes.size()
		check.call(
			(
				whole
				and wf.pieces.is_empty()
				and _hidden(back) == 0
				and back.world.collision_volumes.size() == level_volumes
			),
			(
				"%s: the retry's arena is whole again (%d volumes, level %d, %d hidden)"
				% [kind, back.world.collision_volumes.size(), level_volumes, _hidden(back)]
			)
		)
		var gear: BossGearFeature = back.features["boss_gear"]
		check.call(
			BossGearFeature.lost_of(back).is_empty(), "%s: the retry's boss has all his gear" % kind
		)
		check.call(gear != null, "%s: the retry has its gear" % kind)
	main.return_to_title(true)
	# In place (as a retry on a running game would): reset() puts it all back.
	f.reset()
	check.call(
		g.world.collision_volumes.size() == volumes and _hidden(g) == 0 and g.props.size() == props,
		"%s: reset() puts the arena back as the level made it" % kind
	)
	# A rematch is a fresh game: its arena is whole.
	var again := _game(main, kind)
	check.call(
		(
			_hidden(again) == 0
			and (again.features["arena_wreck"] as ArenaWreckFeature).pieces.is_empty()
		),
		"%s: a rematch starts with the arena whole" % kind
	)


## Each piece of gear: shot where it sits, it flies off and lands on the floor.
static func _gear(main, check: Callable, kind: String, models: ActorModels) -> void:
	var table: Dictionary = BossGearFeature.GEAR.get(kind, {})
	check.call(not table.is_empty(), "%s: has gear to shoot off (%d)" % [kind, table.size()])
	for name: String in table:
		var made := models.gear_mesh(kind, name)
		check.call(
			not made.is_empty(), "%s: the %s is a part of the model of its own" % [kind, name]
		)
		var g := _game(main, kind)
		var e := BossFight.of_kind(g, kind)
		var f: BossGearFeature = g.features["boss_gear"]
		var spec: Dictionary = table[name]
		var band: Array = spec["z"]
		var lo: float = band[0]
		var hi: float = band[1]
		var tall := e.height * e.variant
		var feet: float = e.z + g.world.stand(e)
		e.angle = 0.0
		var side := str(spec.get("side", "any"))
		var from := Vector2(e.x - 5.0, e.y) if side == "back" else Vector2(e.x + 5.0, e.y)
		var hit := Vector3(e.x, e.y, feet + tall * (lo + hi) * .5)
		var hp: float = spec["hp"]
		var shots := 0
		e.hp = e.max_hp
		while not BossGearFeature.lost(g, e, name) and shots < 40:
			g.hit_point = hit
			g.hit_from = from
			e.hurt(hp * .3 + 5.0, g, false, false, null, "shotgun")
			e.hp = e.max_hp
			shots += 1
		check.call(
			BossGearFeature.lost(g, e, name),
			"%s: the %s comes off after %d hits where it sits" % [kind, name, shots]
		)
		check.call(
			(BossGearFeature.lost_of(g).get(e, []) as Array).has(name),
			"%s: the model leaves the %s off" % [kind, name]
		)
		_hold(e)
		_ticks(g, 60 * 5)
		var piece: Dictionary = {}
		for p: Dictionary in f.loose:
			if p["name"] == name:
				piece = p
		check.call(not piece.is_empty(), "%s: the %s flies as a piece of its own" % [kind, name])
		if piece.is_empty():
			continue
		var px: float = piece["x"]
		var py: float = piece["y"]
		var pz: float = piece["z"]
		var half: float = spec.get("half", .05)
		var floor_z := Tumble.floor_at(g.world, px, py, pz - half * tall, .05)
		var resting: bool = piece["rest"]
		check.call(
			resting and absf(pz - half * tall - floor_z) < .08 and not g.world.blocked(px, py, .02),
			(
				"%s: the %s lands on the floor (%.2f over %.2f, %.1f from him)"
				% [kind, name, pz - half * tall, floor_z, Vector2(px - e.x, py - e.y).length()]
			)
		)
		# Its armour gives way: a hit there counts `bare` now.
		g.hit_point = hit
		var bare: float = spec.get("bare", 1.0)
		var counts := f.struck(e, hit, from, 10.0)
		check.call(
			is_equal_approx(counts, bare),
			"%s: off, a hit where the %s was counts %.2f" % [kind, name, counts]
		)
		# It shows: the view gets a sprite of the piece.
		var shown := false
		for s: View.Sprite in f.sprites():
			shown = shown or (s.gear == name and s.who == e)
		check.call(shown, "%s: the %s lying is drawn" % [kind, name])


## BOSS ARENAS WRECK off: nothing comes down and nothing comes off.
static func _off(main, check: Callable) -> void:
	var g := _game(main, "baron")
	g.configure({"difficulty": 1, "boss_wrecks": 0})
	var e := BossFight.of_kind(g, "baron")
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	e.hp = e.max_hp * .05
	_hold(e)
	_ticks(g, 60 * 3)
	var gear: BossGearFeature = g.features["boss_gear"]
	var feet: float = e.z + g.world.stand(e)
	var counts := gear.struck(
		e, Vector3(e.x, e.y, feet + e.height * e.variant * .9), Vector2(e.x + 4.0, e.y), 999.0
	)
	check.call(
		(
			f.pieces.is_empty()
			and _hidden(g) == 0
			and BossGearFeature.lost_of(g).is_empty()
			and counts == 1.0
		),
		"BOSS ARENAS WRECK off: the arena and the boss stay whole"
	)


## The Swamp King's wave shoves the player it meets out of its way.
static func _wave(main, check: Callable) -> void:
	var g := _game(main, "swamp_king")
	var e := BossFight.of_kind(g, "swamp_king")
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	var p := g.player
	var w := g.world
	var spot := Vector2.INF
	for k in 16:
		var a := k * TAU / 16.0
		var at := Vector2(e.x + cos(a) * 3.0, e.y + sin(a) * 3.0)
		if not w.blocked(at.x, at.y, .5) and not w.blocked(at.x + cos(a), at.y + sin(a), .5):
			spot = at
			break
	check.call(spot != Vector2.INF, "swamp_king: open water round him for the wave")
	if spot == Vector2.INF:
		return
	p.x = spot.x
	p.y = spot.y
	p.eye = w.stand(p) + .95
	var before := Vector2(p.x - e.x, p.y - e.y).length()
	for i in f.steps.size():
		if str(f.steps[i]["do"]) == "wave":
			f.fired[i] = -1
	e.hp = e.max_hp * .55
	_hold(e)
	_ticks(g, 2)
	check.call(not f.waves.is_empty(), "swamp_king: past %.2f his wave rolls out" % .6)
	_hold(e)
	_ticks(g, 60)
	var after := Vector2(p.x - e.x, p.y - e.y).length()
	check.call(
		after > before + .5,
		"swamp_king: the wave shoves the player away (%.1f -> %.1f)" % [before, after]
	)
