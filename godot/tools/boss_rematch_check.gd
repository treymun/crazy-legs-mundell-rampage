## The boss checkpoint and the BOSS REMATCH (tools/check_fixes.gd runs the
## quick part; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/boss_rematch_check.gd
##       [-- bot] [kinds=boss,maw]
##
## Quick: the guns table matches the levels' pickups; every boss's rematch
## loads with that boss alone, present and awake, the player at an entrance a
## body fits that walks to the boss within DOOR_STEPS, armed as the table
## says; the title entry, the board, a rematch's timer, result and best, and
## none of it touching the campaign; and for every boss the checkpoint at its
## door: taken as its fight begins, offered on the death screen, loaded with
## the boss whole and the player at the door with what they had, cleared by a
## win. A felled boss (god mode allowed) ends its rematch with a time.
## bot: also has tools/bot_pilot.gd fight each rematch on its own, god mode
## off, and prints its time to kill (the par times in boss_rematch.gd come from
## these); a bot that goes down is reported and the fight is won again in god
## mode. Takes minutes, so it is not in check_fixes.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0
const BOT_LIMIT := 300.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var kinds: Array = BossRematch.BOSSES.duplicate()
	var bot := false
	for arg in OS.get_cmdline_user_args():
		if arg == "bot":
			bot = true
		elif String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
	run(main, func(ok: bool, text: String) -> void: _check(ok, text), kinds)
	if bot:
		_bot_times(main, kinds)
	print("")
	print(
		(
			"BOSS REMATCH OK"
			if failures.is_empty()
			else "%d BOSS REMATCH CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func run(main, check: Callable, kinds: Array = BossRematch.BOSSES) -> void:
	print("BOSS REMATCH (every boss alone, awake, at a walkable entrance, armed)")
	BossRematch.unlock_all = false
	_guns(check)
	for kind: String in kinds:
		_rematch(main, check, kind)
	_flow(main, check)
	print("BOSS CHECKPOINT (taken at the door, offered, loaded whole, cleared by a win)")
	for kind: String in kinds:
		_checkpoint(main, check, kind)


## GUNS is every chapter's weapon pickups and those before it.
static func _guns(check: Callable) -> void:
	var have := {0: true, 1: true}
	var right := true
	for level_id: String in Campaign.ORDER:
		var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % level_id))
		for row in doc.get("pickups", []):
			var name := String(GameState.ALIAS.get(String(row[0]), String(row[0])))
			if Weapons.NAMES.has(name):
				have[Weapons.NAMES.find(name)] = true
			elif name == "dynamite":
				have[Weapons.DYNAMITE] = true
		var want: Array = have.keys()
		want.sort()
		var table: Array = BossRematch.GUNS[level_id].duplicate()
		table.sort()
		if want != table:
			right = false
			print("    %s: the levels give %s" % [level_id, want])
	check.call(right, "the rematch guns table matches the guns lying about by each chapter")


static func _rematch(main, check: Callable, kind: String) -> void:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	check.call(g != null, "%s: the rematch loads" % kind)
	if g == null:
		return
	g.configure({})
	var boss := BossFight.of_kind(g, kind)
	var alone := true
	for e: Enemy in g.enemies:
		alone = alone and (e == boss or not e.hostile)
	check.call(
		boss != null and boss.alive and boss.alerted and not boss.dormant and alone,
		"%s: present, awake and the only hostile in %s" % [kind, g.level.id]
	)
	if boss == null:
		return
	var p := g.player
	var field := BossRematch.field_from(g, boss)
	var steps := field.distance(p.x, p.y) if field != null else FlowField.FAR
	check.call(
		(
			BossRematch.fits(g, Vector2i(int(p.x), int(p.y)))
			and steps >= 3
			and steps <= BossRematch.DOOR_STEPS
		),
		(
			"%s: the entrance (%.1f, %.1f) is open floor %d steps from the boss"
			% [kind, p.x, p.y, steps]
		)
	)
	var armed := g.armory.owned[Weapons.SHOTGUN] and g.player.health == 100
	for i in Weapons.COUNT:
		var want: bool = BossRematch.GUNS[g.level.id].has(i)
		armed = armed and g.armory.owned[i] == want
		if want:
			armed = armed and g.armory.reserve[i] == Weapons.MAX_RESERVE[i]
	check.call(armed, "%s: the guns of the campaign by then, full" % kind)
	# A few seconds in, god mode on: the fight starts and the boss can be felled.
	g.cheats.god = true
	var fight = g.features["boss_rematch"]
	for i in 240:
		g.tick(STEP, Game.Controls.new())
	check.call(
		g.player.health > 0 and boss.alive, "%s: the fight runs a few seconds in god mode" % kind
	)
	boss.hurt(boss.hp + 99999.0, g)
	# Past the death moment's held world (hitstop stops the clock) and AFTER.
	for i in 400:
		g.tick(STEP, Game.Controls.new())
	check.call(
		fight.fell >= 0.0 and fight.seconds() > 3.0 and fight.finished(),
		"%s: felled, it is timed (%.1f s) and the rematch ends" % [kind, fight.seconds()]
	)


## The title's entry, the board, a rematch in play and out, the result.
static func _flow(main, check: Callable) -> void:
	print("BOSS REMATCH (title entry, board, result, the campaign untouched)")
	main.return_to_title(true)
	main.campaign_run = null
	var files := [
		"user://campaign-entry.json", "user://hickston-quick.json", "user://campaign-unlocks.json"
	]
	var before := {}
	for path: String in files:
		before[path] = _stamp(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BossRematch.profile_path()))
	main.unlocked = {"hickston": true}
	check.call(main.entries().has("BOSS REMATCH"), "the title offers BOSS REMATCH")
	check.call(_pick(main, "BOSS REMATCH") and main.state == "rematch", "and it opens the board")
	# (Maw opens from a campaign entry save that won her chapter, if one is here.)
	var opened: Array = main.rematch_open.keys()
	opened.erase("maw")
	check.call(opened.is_empty(), "with only Hickston reached every boss is locked")
	main.rematch_pick = 0
	main.key(KEY_ENTER)
	check.call(main.state == "rematch" and main.menu_note != "", "a locked boss says what to beat")
	main.unlocked = {"hickston": true, "fair": true}
	main.open_rematch_board()
	check.call(
		main.rematch_open.has("boss") and main.rematch_open.has("jerry"),
		"the sheriff and Jerry open once the fair is"
	)
	check.call(not main.rematch_open.has("rudy"), "and Rudy waits for the fair to be beaten")
	BossRematch.unlock_all = true
	main.open_rematch_board()
	check.call(main.rematch_open.size() == 8, "unlock_all (--rematch-all, console) opens all eight")
	BossRematch.unlock_all = false
	main.start("hickston")
	var chapter: Game = main.game
	main.return_to_title()
	main.open_rematch_board()
	main.rematch_pick = 1
	main.key(KEY_ENTER)
	var fight: Game = main.game
	check.call(
		main.state == "play" and main.in_rematch() and main.campaign_run == chapter,
		"picking Jerry starts his rematch, the chapter paused waits"
	)
	main.save_game()
	check.call(main.slot_source() == null, "a rematch offers nothing to save")
	fight.portal_request = "hub"
	main.travel("hub")
	check.call(main.game == fight, "and has no road out to the Crossroads")
	main.key(KEY_ESCAPE)
	check.call(main.entries().has("LEAVE REMATCH"), "Esc pauses on the title with LEAVE REMATCH")
	_pick(main, "RESUME")
	fight.player.health = 0
	main.key(KEY_ENTER)
	check.call(
		main.game != fight and main.in_rematch() and main.rematch_return == chapter,
		"dead in a rematch, Enter fights it again"
	)
	fight = main.game
	var jerry := BossFight.of_kind(fight, "jerry")
	fight.cheats.god = true
	for i in 60:
		fight.tick(STEP, Game.Controls.new())
	jerry.hurt(99999.0, fight)
	for i in 400:
		fight.tick(STEP, Game.Controls.new())
	main.watch_rematch()
	check.call(
		main.state == "rematch_done" and main.game == chapter,
		"the fall ends it on the result, the chapter back in its place"
	)
	var seconds := float(main.rematch_result.get("seconds", 0.0))
	check.call(
		(
			bool(main.rematch_result.get("fresh", false))
			and absf(BossRematch.best("jerry") - seconds) < .02
		),
		"the first time is the best, kept in %s" % BossRematch.FILE
	)
	var c := Canvas.new()
	main.render()
	BossRematch.draw_result(c, main.menu, main.rematch_result, "", "")
	check.call(
		(
			BossRematch.ribbon("jerry", 1.0) == "BLUE"
			and BossRematch.ribbon("jerry", BossRematch.PAR["jerry"] * 1.3) == "RED"
			and BossRematch.ribbon("jerry", 9999.0) == "WHITE"
		),
		"ribbons by par: blue, red, white"
	)
	main.key(KEY_ENTER)
	check.call(main.state == "rematch", "Enter on the result goes back to the board")
	main.render()
	main.key(KEY_ESCAPE)
	check.call(main.state == "title" and main.game == chapter, "and Esc to the title")
	main.return_to_title(true)
	main.campaign_run = null
	var same := true
	for path: String in files:
		same = same and _stamp(path) == before[path]
	check.call(same, "no campaign entry, quicksave or unlock file was written")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BossRematch.profile_path()))
	main.unlocked = SessionStore.unlocks("")


## One boss's checkpoint: walked into its arena from outside, killed, retried.
static func _checkpoint(main, check: Callable, kind: String) -> void:
	var level_id := String(BossRematch.LEVEL_OF[kind])
	main.return_to_title(true)
	main.start(level_id, null, [], true, null)
	var g: Game = main.game
	var boss := BossFight.of_kind(g, kind)
	if kind == "jerry" and g.boss != null:
		g.boss.hp = 0.0
	boss.dormant = false
	boss.alerted = true
	g.cheats.god = true
	g.spawn_grace = 99.0
	# As by the fight: the doors on the way open.
	for door: LevelData.Door in g.world.doors:
		if not door.secret:
			door.opened = true
			door.progress = 1.0
	# The way in from the start: the last spot outside the arena, the first in.
	var field := BossRematch.field_from(g, boss)
	var path: Array = []
	field.waypoint(g.level.spawn[0], g.level.spawn[1], 100000, path)
	var outside := Vector2.INF
	var inside := Vector2.INF
	for cell: Vector2i in path:
		var at := Vector2(cell.x + .5, cell.y + .5)
		if not BossRematch.fits(g, cell):
			continue
		if BossFight.in_arena_at(g, boss, at.x, at.y):
			inside = at
			break
		if (
			BossFight.clear_of(g, boss, at.x, at.y)
			and at.distance_to(Vector2(boss.x, boss.y)) > BossFight.ARENA + 2.0
		):
			outside = at
	if inside == Vector2.INF and boss != g.finale:
		# The sheriff stands below the pen's top half the boss bar counts.
		var top := Vector2i(int(boss.x), int(BossFight.PEN_Y) - 2)
		if BossRematch.fits(g, top):
			inside = Vector2(top.x + .5, top.y + .5)
	if outside == Vector2.INF or inside == Vector2.INF:
		check.call(false, "%s: a way into the arena from the start" % kind)
		return
	var bx := boss.x
	var by := boss.y
	_stand(g, outside)
	for i in 40:
		_hold(g, boss, bx, by)
	_stand(g, inside)
	g.armory.reserve[Weapons.SHOTGUN] = 11
	for i in 40:
		_hold(g, boss, bx, by)
	var feature = g.features["boss_checkpoint"]
	var file := BossDoor.path(level_id, true)
	check.call(
		feature.taken.has(kind) and FileAccess.file_exists(file),
		"%s: walking into the arena takes the checkpoint" % kind
	)
	var health := g.player.health
	var shells := g.armory.reserve[Weapons.SHOTGUN]
	var door := (
		Vector2(float(feature.door[0]), float(feature.door[1]))
		if feature.door.size() >= 3
		else Vector2.INF
	)
	(
		check
		. call(
			door.distance_to(outside) < .01 and BossFight.clear_of(g, boss, door.x, door.y),
			(
				"%s: its door (%.1f, %.1f) is where the player last stood clear of the arena (%.1f, %.1f)"
				% [kind, door.x, door.y, outside.x, outside.y]
			)
		)
	)
	boss.hurt(boss.max_hp * .3, g)
	g.cheats.god = false
	g.armory.reserve[Weapons.SHOTGUN] = 0
	g.damage(9999.0)
	check.call(
		feature.offered() and feature.death_lines().size() == 2,
		"%s: dead, RETRY THE FIGHT is offered" % kind
	)
	main.state = "play"
	main.key(KEY_ENTER)
	var back: Game = main.game
	var whole := BossFight.of_kind(back, kind)
	(
		check
		. call(
			(
				back != g
				and whole != null
				and is_equal_approx(whole.hp, whole.max_hp)
				and back.player.health == health
				and back.armory.reserve[Weapons.SHOTGUN] == shells
				and Vector2(back.player.x, back.player.y).distance_to(door) < .01
				and back.replay
			),
			(
				"%s: retried with the boss whole, at the door (%.1f, %.1f), health and rounds as they were"
				% [kind, door.x, door.y]
			)
		)
	)
	back.cheats.god = true
	for i in 30:
		back.tick(STEP, Game.Controls.new())
	check.call(
		FileAccess.file_exists(file) and back.features["boss_checkpoint"].taken.has(kind),
		"%s: the retried fight keeps its checkpoint" % kind
	)
	back.finish_level("")
	check.call(not FileAccess.file_exists(file), "%s: a won chapter clears its checkpoint" % kind)
	main.return_to_title(true)


static func _stand(g: Game, at: Vector2) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.vx = 0.0
	p.vy = 0.0
	p.eye = g.world.elevation(at.x, at.y) + .95


## A tick with the boss held where it stood (it would come for the player).
static func _hold(g: Game, boss: Enemy, x: float, y: float) -> void:
	g.tick(STEP, Game.Controls.new())
	boss.x = x
	boss.y = y
	boss.windup = 0.0


static func _pick(main, entry: String) -> bool:
	var rows: PackedStringArray = main.entries()
	var at := rows.find(entry)
	if at < 0:
		return false
	main.selection = at
	main.menu_action()
	return true


static func _stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "none"
	return "%d:%s" % [FileAccess.get_modified_time(path), FileAccess.get_md5(path)]


## The bot fights each rematch alone (god mode off) and its time is printed.
func _bot_times(main, kinds: Array) -> void:
	print("\nBOT TIMES (tools/bot_pilot.gd, god mode off; par = BLUE in boss_rematch.gd)")
	for kind: String in kinds:
		var first := _bot_fight(main, kind, false)
		var line := "  %-12s " % kind
		if first[0] == "won":
			line += "%6.1f s  health left %d" % [float(first[1]), int(first[2])]
		else:
			var again := _bot_fight(main, kind, true)
			line += (
				"bot went down after %.1f s (boss at %d%%); god mode: %s %.1f s"
				% [float(first[1]), int(first[3]), again[0], float(again[1])]
			)
			if again[0] != "won":
				failures.append("%s cannot be won by the bot even in god mode" % kind)
		line += "   par %.0f s" % float(BossRematch.PAR[kind])
		print(line)


## [outcome ("won", "died", "timeout"), seconds, health, boss health %].
func _bot_fight(main, kind: String, god: bool) -> Array:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	g.configure(SessionStore.defaults())
	g.cheats.god = god
	var boss := BossFight.of_kind(g, kind)
	var fight = g.features["boss_rematch"]
	var pilot := Pilot.new()
	var field: FlowField = null
	var field_at := -9.0
	var ticks := 0
	while g.clock < BOT_LIMIT and ticks < int(BOT_LIMIT / STEP) * 2:
		ticks += 1
		if g.clock - field_at > 1.0 and boss.alive:
			field = BossRematch.field_from(g, boss)
			field_at = g.clock
		var controls := pilot.steer(g)
		if pilot.foe == null and field != null and boss.alive:
			# Nothing in sight: walk to the boss, a cell at a time.
			var p := g.player
			var aim := field.heading(p.x, p.y)
			if is_nan(aim):
				aim = atan2(boss.y - p.y, boss.x - p.x)
			var turn := fposmod(aim - p.angle + PI, TAU) - PI
			controls.turn = clampf(turn, -.12, .12)
			controls.forward = 1.0 if absf(turn) < .9 else .2
			controls.running = true
		g.tick(STEP, controls)
		pilot.moved(g)
		if OS.get_cmdline_user_args().has("trace") and ticks % 30 == 0:
			print(
				(
					"    %.1f hp %.0f boss %.1f,%.1f me %.1f,%.1f foe %s fire %s gun %d"
					% [
						g.clock,
						boss.hp,
						boss.x,
						boss.y,
						g.player.x,
						g.player.y,
						pilot.foe != null,
						controls.fire,
						g.armory.active
					]
				)
			)
		if fight.fell >= 0.0:
			return ["won", fight.seconds(), g.player.health, 0]
		if g.player.health <= 0:
			return ["died", g.clock, 0, int(100.0 * boss.hp / boss.max_hp)]
	return ["timeout", g.clock, g.player.health, int(100.0 * boss.hp / boss.max_hp)]
