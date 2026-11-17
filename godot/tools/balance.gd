## Difficulty and pacing as numbers (polish pass 9): the campaign bot
## (tools/balance_pilot.gd, a player's skill on tools/bot_pilot.gd) plays
## the campaign for real, god mode off, each chapter carried into the next
## as continue_campaign does, dying and retrying as the death screen does
## (RETRY THE FIGHT in a boss fight), and every attempt is written down: how
## it ended and where, the time, health, rounds, scrap, finishers, hazard
## kills, the hound, the vehicles, the bosses' times and the bench's buys.
## COUNTY RUN likewise (tools/county_bot.gd): survival, the XP curve, the
## cards picked.
##
##   godot --headless --path godot --script res://tools/balance.gd -- check [part=1..5]
##   godot ... -- run [diff=1] [skill=1] [seed=1] [hound=1] [chapters=a,b] out=<file.jsonl>
##   godot ... -- county [diff=1] [seed=1] [maps=county_hickston] [cap=900] out=<file.jsonl>
##   godot ... -- report in=<dir or file> [md=<file>]
##
## run: one campaign, a line of JSON per chapter attempt (and per boss).
## Each process wants its own APPDATA and LOCALAPPDATA (the boss checkpoint
## lives in the cache folder); tools/balance_runs.sh spreads many over the PC.
## report: the tables (tools/balance_report.gd) from those lines.
## check (check_all): the short guard, BALANCE OK. Every boss fought in its
## rematch by a REGULAR bot at NORMAL (seeds BOSS_SEEDS) must fall inside
## its BOSS_BANDS seconds; every chapter played from its chapter kit by a
## SHARP bot at NORMAL must be cleared within CHAPTER_DEATHS deaths and its
## CHAPTER_BANDS seconds; a retried fight brings [boss_retry]'s floor. Play
## is exact, so the numbers are the same each run.
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const CountyBot := preload("res://tools/county_bot.gd")
const Report := preload("res://tools/balance_report.gd")
const STEP := 1.0 / 60.0
## Game seconds an attempt may take before it counts as stuck.
const ATTEMPT_LIMIT := 900.0
## Deaths in a chapter before the run gives up on it (and walks it in god mode).
const MOST_DEATHS := 6
## The guard's bands: seconds the REGULAR bot takes to bring each boss down
## in its rematch at NORMAL, seeds BOSS_SEEDS (measured after the pass 9
## tuning: boss 6.2/8.2, jerry 10.2, rudy 10.9/13.4, foreman 14.1, baron 17.7,
## swamp_king 12.6/13.0, derby_champ 13.7/15.3, revenue_man 12.0/12.5, maw
## 24.3/24.1; each band about 45 % either side).
const BOSS_SEEDS := [1, 2]
const BOSS_BANDS := {
	"boss": [4.0, 12.0],
	"jerry": [6.0, 15.0],
	"rudy": [7.0, 18.0],
	"foreman": [8.0, 21.0],
	"baron": [10.0, 26.0],
	"swamp_king": [7.0, 19.0],
	"derby_champ": [8.0, 22.0],
	"revenue_man": [7.0, 18.0],
	"maw": [14.0, 36.0],
}
## The guard's chapters: the SHARP bot at NORMAL from the chapter kit, seed 1,
## cleared within CHAPTER_DEATHS deaths and inside its band of seconds (after
## the pass 9 tuning, as each check_all row plays them: hickston 247, fair
## 275, sawmill 205, quarry 212, bayou 561 (one death), speedway 196,
## moonshine 482, mothership 513 (one death); about 35 % either side). Before
## the tuning it could not clear Hickston at all within two deaths. A part
## plays the same every time; the whole check in one process differs a
## little (ids and caches are carried over from the chapters before it).
const CHAPTER_DEATHS := 1
const CHAPTER_BANDS := {
	"hickston": [160.0, 335.0],
	"fair": [180.0, 370.0],
	"sawmill": [135.0, 275.0],
	"quarry": [140.0, 285.0],
	"bayou": [365.0, 760.0],
	"speedway": [125.0, 265.0],
	"moonshine": [310.0, 645.0],
	"mothership": [335.0, 700.0],
}
## check_all's rows: the bosses, then two chapters a row.
const CHECK_PARTS := 5

var main
var out_path := ""
var lines := 0
var failures: Array = []
var args := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var at := arg.find("=")
		if at < 0:
			args[arg] = "1"
		else:
			args[arg.substr(0, at)] = arg.substr(at + 1)
	if args.has("report"):
		var text := Report.tables(str(args.get("in", "")))
		print(text)
		if args.has("md"):
			var f := FileAccess.open(str(args["md"]), FileAccess.WRITE)
			f.store_string(text)
			f.close()
		quit(0)
		return
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	out_path = str(args.get("out", ""))
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-balance-county")
	if args.has("check"):
		_check()
	elif args.has("county"):
		_county()
	else:
		_campaign()
	main.queue_free()
	await process_frame
	if args.has("check"):
		print("BALANCE OK" if failures.is_empty() else "BALANCE FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
		quit(0 if failures.is_empty() else 1)
		return
	print("BALANCE RUN DONE: %d lines" % lines)
	quit(0)


func _int(key: String, fallback: int) -> int:
	return int(args.get(key, str(fallback)))


func _write(row: Dictionary) -> void:
	lines += 1
	if out_path == "":
		print(JSON.stringify(row))
		return
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(out_path, FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(row))
	f.close()


## The options a player starts with (the PLAY page's defaults), at `diff`.
func _options(diff: int, hound: int) -> Dictionary:
	var options: Dictionary = SessionStore.defaults().duplicate()
	options["difficulty"] = diff
	options["hound"] = hound
	options["bench"] = 1
	options["opener"] = 0
	options["openers"] = 0
	return options


# ------------------------------------------------------------------ campaign


## One campaign by one bot: every chapter in order (or `chapters=`).
func _campaign() -> void:
	var diff := _int("diff", 1)
	var skill := _int("skill", 1)
	var seed_value := _int("seed", 1)
	var hound := _int("hound", 1)
	var only: Array = []
	if args.has("chapters"):
		only = Array(str(args["chapters"]).split(","))
	for key: String in _options(diff, hound):
		main.options[key] = _options(diff, hound)[key]
	var chapters: Array = Campaign.ORDER if only.is_empty() else only
	var kit: Variant = null
	var history: Array = []
	var bought: Array = []
	for index in chapters.size():
		var chapter: String = chapters[index]
		var base := {
			"diff": diff,
			"skill": skill,
			"seed": seed_value,
			"hound": hound,
			"chapter": chapter,
			"order": Campaign.ORDER.find(chapter)
		}
		if kit == null and chapter != "hickston":
			main.start(chapter, null, history, false, null)
			NetCoop.chapter_kit(main.game, chapter)
			main.game.entry = main.game.loadout()
		else:
			main.start(chapter, kit, history, false, null)
		var won := _play_chapter(base, seed_value, skill, bought)
		var g: Game = main.game
		if not won:
			break
		kit = g.loadout()
		history = g.history.duplicate()
		history.append(g.result())


## The bench's mods bought with the scrap in hand, cheapest first (the bot
## takes them at the chapter's start: its bench stands a few steps away).
func _buy(g: Game, base: Dictionary, bought: Array) -> Array:
	var got: Array = []
	if not BenchMods.on(g):
		return got
	var order: Array = []
	for i in BenchMods.ids().size():
		order.append([int(BenchMods.mod(BenchMods.ids()[i])["price"]), i])
	order.sort()
	for pair: Array in order:
		var i: int = pair[1]
		if BenchMods.buy(g.player, i):
			got.append(BenchMods.ids()[i])
			bought.append([BenchMods.ids()[i], base["chapter"]])
	return got


## Plays the chapter in main.game to its end, retrying deaths; true when won.
func _play_chapter(base: Dictionary, seed_value: int, skill: int, bought: Array) -> bool:
	var deaths := 0
	var attempt := 0
	var scrap_start: int = main.game.armory.scrap
	var mods := _buy(main.game, base, bought)
	while true:
		attempt += 1
		var g: Game = main.game
		g.rng = GameState.Rng.new(seed_value * 1009 + int(base["order"]) * 31 + attempt)
		var row := base.duplicate()
		row["attempt"] = attempt
		row["mods_bought"] = mods
		row["mods_owned"] = g.armory.mods.duplicate()
		row["scrap_carried"] = scrap_start
		var outcome := _attempt(g, Pilot.new(skill, seed_value * 13 + attempt), row, deaths)
		_write(row)
		if outcome == "clear":
			return true
		deaths += 1
		if deaths >= MOST_DEATHS or outcome == "timeout":
			# Given up: walked through in god mode so the campaign goes on.
			var gone: Game = main.game
			if outcome == "death":
				main.restart_chapter(gone)
			var walk := main.game as Game
			walk.cheats.god = true
			var rest := {"chapter": base["chapter"], "walked": true}
			_attempt(walk, Pilot.new(2, 1), rest, deaths, true)
			return bool(walk.won)
		if bool(row.get("boss_fight", false)):
			main.retry_fight()
		else:
			main.restart_chapter(g)
	return false


## One go at the chapter in `g` until it is won, the player dies or time is
## up; fills `row` and returns "clear", "death" or "timeout".
func _attempt(g: Game, pilot: Pilot, row: Dictionary, _deaths: int, quiet := false) -> String:
	var stats := {
		"shots": {},
		"kills_by": {},
		"taken": 0.0,
		"cause": "",
		"bosses": [],
		"fighting": "",
		"pickups": 0,
		"scrap_found": 0,
		"dry": 0,
		"ride": 0
	}
	var on_shot := func(gun: int) -> void:
		var name := str(Weapons.NAMES[gun])
		stats["shots"][name] = int(stats["shots"].get(name, 0)) + 1
	var on_kill := func(_e: Enemy) -> void:
		var name := str(Weapons.NAMES[g.armory.active])
		stats["kills_by"][name] = int(stats["kills_by"].get(name, 0)) + 1
	var on_hurt := func(amount: float, cause: String) -> void:
		stats["taken"] = float(stats["taken"]) + amount
		stats["cause"] = cause
	var on_intro := func(e: Enemy) -> void: stats["fighting"] = e.kind
	# A boss's fight is timed from the first hit it takes to its fall (the
	# game's own clock starts at its intro, which not every boss has).
	var hit_at := {}
	var on_down := func(e: Enemy, _secs: float) -> void:
		var since: float = hit_at.get(e.kind, g.clock)
		stats["bosses"].append([e.kind, snappedf(g.clock - since, .1)])
		stats["fighting"] = ""
	var on_pick := func(name: String) -> void:
		stats["pickups"] = int(stats["pickups"]) + 1
		if name.begins_with("scrap_"):
			stats["scrap_found"] = int(stats["scrap_found"]) + BenchMods.worth(name)
	g.events.shot_fired.connect(on_shot)
	g.events.enemy_killed.connect(on_kill)
	g.events.player_hurt.connect(on_hurt)
	g.events.boss_intro.connect(on_intro)
	g.events.boss_down.connect(on_down)
	g.events.pickup_taken.connect(on_pick)
	var start := g.clock
	var kills_was := g.kills
	var rides: Object = g.features.get("vehicles")
	var outcome := "timeout"
	var ticks := 0
	while g.clock - start < ATTEMPT_LIMIT * (2.0 if quiet else 1.0):
		ticks += 1
		if ticks % 15 == 0:
			for e: Enemy in g.enemies:
				if e.alive and not hit_at.has(e.kind) and BossKit.is_boss(e) and e.hp < e.max_hp:
					hit_at[e.kind] = g.clock
					stats["fighting"] = e.kind
		var c := pilot.steer(g)
		if c.cycle != 0:
			stats["dry"] = int(stats["dry"]) + 1
		g.tick(STEP, c)
		pilot.moved(g)
		if rides != null and bool(rides.call("seated", g.player)):
			stats["ride"] = int(stats["ride"]) + 1
		if g.won:
			outcome = "clear"
			break
		if g.player.health <= 0:
			outcome = "death"
			break
	for sig: Array in [
		[g.events.shot_fired, on_shot],
		[g.events.enemy_killed, on_kill],
		[g.events.player_hurt, on_hurt],
		[g.events.boss_intro, on_intro],
		[g.events.boss_down, on_down],
		[g.events.pickup_taken, on_pick]
	]:
		var s: Signal = sig[0]
		if s.is_connected(sig[1]):
			s.disconnect(sig[1])
	if quiet:
		return outcome
	var p := g.player
	row["outcome"] = outcome
	row["secs"] = snappedf(g.clock - start, .1)
	row["x"] = snappedf(p.x, .1)
	row["y"] = snappedf(p.y, .1)
	var names: PackedStringArray = g.level.districts
	row["district"] = names[g.district] if g.district >= 0 and g.district < names.size() else ""
	row["cause"] = stats["cause"]
	row["boss_fight"] = str(stats["fighting"]) != ""
	row["fighting"] = stats["fighting"]
	row["near"] = _near(g)
	row["health"] = p.health
	row["ammo"] = snappedf(_ammo_share(g), .01)
	row["dry"] = snappedf(int(stats["dry"]) * STEP, .1)
	row["kills"] = g.kills - kills_was
	row["taken"] = roundi(float(stats["taken"]))
	row["eaten"] = pilot.eaten
	row["scrap_found"] = stats["scrap_found"]
	row["scrap_end"] = g.armory.scrap
	row["shots"] = stats["shots"]
	row["kills_by"] = stats["kills_by"]
	row["bosses"] = stats["bosses"]
	row["ride_s"] = snappedf(int(stats["ride"]) * STEP, .1)
	var brawl: Object = g.features.get("brawl")
	if brawl != null:
		var finished: Dictionary = brawl.get("finished")
		var n := 0
		for k: Variant in finished:
			n += int(finished[k])
		row["finishers"] = n
		row["boots"] = brawl.get("kicks")
		var hz: Dictionary = brawl.get("hazard_kills")
		var h := 0
		for k: Variant in hz:
			h += int(hz[k])
		row["hazards"] = h
	var dog: Object = g.features.get("hound")
	if dog != null and bool(dog.get("on")):
		row["dog"] = {
			"bites": dog.get("bites"),
			"pins": dog.get("pins"),
			"finished": dog.get("finished"),
			"downs": dog.get("downs"),
			"points": dog.get("points")
		}
	return outcome


## The kinds of hostile within 10 cells (where a death came from).
static func _near(g: Game) -> Array:
	var kinds: Array = []
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and Vector2(e.x - g.player.x, e.y - g.player.y).length() < 10.0:
			if not kinds.has(e.kind):
				kinds.append(e.kind)
	return kinds


## The rounds in hand for the guns owned that take them, as a share of what
## each can carry (melee and endless guns left out).
static func _ammo_share(g: Game) -> float:
	var a := g.armory
	var sum := 0.0
	var n := 0
	for slot in Weapons.COUNT:
		if not a.owned[slot] or slot >= Weapons.MAX_RESERVE.size():
			continue
		var most: int = Weapons.MAX_RESERVE[slot]
		if most <= 0:
			continue
		sum += minf(1.0, float(a.reserve[slot]) / most)
		n += 1
	return sum / maxf(1.0, n)


# ------------------------------------------------------------------- county


func _county() -> void:
	var diff := _int("diff", 1)
	var seed_value := _int("seed", 1)
	var cap := float(_int("cap", 900))
	var maps: Array = CountyData.MAP_IDS.duplicate()
	if args.has("maps"):
		maps = Array(str(args["maps"]).split(","))
	for map_id: String in maps:
		var g: Game = main.make_game(map_id)
		g.configure(_options(diff, 0))
		Modes.setup(g, Modes.COUNTY, 1)
		g.rng = GameState.Rng.new(seed_value * 7907 + diff)
		var f = g.features["county"]
		var bot = CountyBot.new()
		var curve: Array = []
		var picks: Array = []
		var next_mark := 60.0
		var ticks := 0
		while not g.defeated() and f.run_time < cap and ticks < int(cap * 60.0) + 60000:
			if f.on and not f.pending.is_empty():
				var at: int = CountyBot.pick(g, f)
				var offered: Array = []
				for card: Dictionary in f.offer:
					var named: String = card.get("id", "")
					if named == "":
						named = "%s:%s" % [card.get("type", ""), card.get("gun", "")]
					offered.append(named)
				picks.append([offered, offered[at] if at < offered.size() else ""])
				CountyMode.choose(g, at, 0)
				continue
			g.tick(STEP, bot.steer(g))
			bot.moved(g)
			ticks += 1
			if f.run_time >= next_mark:
				curve.append([int(next_mark), f.level, g.kills, g.player.health])
				next_mark += 60.0
		_write(
			{
				"mode": "county",
				"map": map_id,
				"diff": diff,
				"seed": seed_value,
				"survived": snappedf(f.run_time, .1),
				"alive": not g.defeated(),
				"level": f.level,
				"kills": g.kills,
				"curve": curve,
				"picks": picks
			}
		)
		g.dispose()


# -------------------------------------------------------------------- check


## part=1: the bosses; part=2..CHECK_PARTS: two chapters each (check_all
## runs each part as its own row); no part: all of it.
func _check() -> void:
	var part := _int("part", 0)
	if part <= 1:
		_check_retry()
		_check_bosses()
	if part == 1:
		return
	var chapters: Array = Campaign.ORDER
	if part >= 2:
		chapters = Campaign.ORDER.slice((part - 2) * 2, (part - 1) * 2)
	_check_chapters(chapters)


## RETRY THE FIGHT with guns run dry (BossDoor.retry_floor): the guns
## carried come back with bosses.cfg [boss_retry] rounds, more kept, a gun not
## carried none.
func _check_retry() -> void:
	print("RETRY ROUNDS")
	var least: Dictionary = BossData.get_value("boss_retry", "rounds")
	var g: Game = main.make_game("hickston")
	var a := g.armory
	a.owned[Weapons.SHOTGUN] = true
	a.reserve[Weapons.REVOLVER] = 0
	a.reserve[Weapons.SHOTGUN] = 99
	a.owned[Weapons.RIFLE] = false
	a.reserve[Weapons.RIFLE] = 0
	BossDoor.retry_floor(g)
	var ok := (
		a.reserve[Weapons.REVOLVER] == int(least["revolver"])
		and a.reserve[Weapons.SHOTGUN] == 99
		and a.reserve[Weapons.RIFLE] == 0
	)
	print(
		(
			"  revolver %d, shotgun %d, rifle (not carried) %d"
			% [a.reserve[1], a.reserve[2], a.reserve[4]]
		)
	)
	if not ok:
		failures.append("a retried fight's rounds: %s" % str(a.reserve.slice(0, 5)))
	g.dispose()


func _check_bosses() -> void:
	print("BOSSES (rematch, REGULAR bot, NORMAL)")
	for kind: String in BOSS_BANDS:
		var band: Array = BOSS_BANDS[kind]
		var times: Array = []
		for s: int in BOSS_SEEDS:
			times.append(_boss_fight(kind, s))
		var line := "  %-14s" % kind
		for t: float in times:
			line += " %6.1f" % t
		line += "   band %.0f..%.0f" % [band[0], band[1]]
		print(line)
		for t: float in times:
			if t < float(band[0]) or t > float(band[1]):
				failures.append(
					"%s fell in %.1f s, outside %.0f..%.0f" % [kind, t, band[0], band[1]]
				)


func _check_chapters(chapters: Array) -> void:
	print("CHAPTERS (chapter kit, SHARP bot, NORMAL, seed 1)")
	for key: String in _options(1, 0):
		main.options[key] = _options(1, 0)[key]
	main.options["bench"] = 0
	for chapter: String in chapters:
		main.start(chapter, null, [], false, null)
		NetCoop.chapter_kit(main.game, chapter)
		main.game.entry = main.game.loadout()
		var deaths := 0
		var secs := 0.0
		var won := false
		while deaths <= CHAPTER_DEATHS:
			var g: Game = main.game
			g.rng = GameState.Rng.new(1009 + deaths)
			var row := {}
			var outcome := _attempt(g, Pilot.new(2, 1 + deaths), row, deaths)
			secs += float(row["secs"])
			if outcome == "clear":
				won = true
				break
			deaths += 1
			if bool(row.get("boss_fight", false)):
				main.retry_fight()
			else:
				main.restart_chapter(g)
		print("  %-11s deaths %d  %6.1f s  %s" % [chapter, deaths, secs, "clear" if won else "NOT"])
		if not won:
			failures.append("%s: not cleared within %d deaths" % [chapter, CHAPTER_DEATHS])
		else:
			var band: Array = CHAPTER_BANDS[chapter]
			if secs < float(band[0]) or secs > float(band[1]):
				failures.append(
					"%s: %.0f s, outside %.0f..%.0f" % [chapter, secs, band[0], band[1]]
				)


## Seconds a REGULAR bot takes to bring `kind` down in its rematch (god mode
## off; a death counts as the limit, which fails the band).
func _boss_fight(kind: String, seed_value: int) -> float:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	g.configure(_options(1, 0))
	g.rng = GameState.Rng.new(seed_value * 101)
	var boss := BossFight.of_kind(g, kind)
	var fight = g.features["boss_rematch"]
	var pilot := Pilot.new(1, seed_value)
	var field: FlowField = null
	var field_at := -9.0
	while g.clock < 400.0:
		if g.clock - field_at > 1.0 and boss.alive:
			field = BossRematch.field_from(g, boss)
			field_at = g.clock
		var c := pilot.steer(g)
		if pilot.foe == null and field != null and boss.alive:
			var p := g.player
			var aim := field.heading(p.x, p.y)
			if is_nan(aim):
				aim = atan2(boss.y - p.y, boss.x - p.x)
			var turn := fposmod(aim - p.angle + PI, TAU) - PI
			c.turn = clampf(turn, -.12, .12)
			c.forward = 1.0 if absf(turn) < .9 else .2
			c.running = true
		g.tick(STEP, c)
		pilot.moved(g)
		if fight.fell >= 0.0:
			var took: float = fight.seconds()
			g.dispose()
			return took
		if g.player.health <= 0:
			break
	g.dispose()
	return 999.0
