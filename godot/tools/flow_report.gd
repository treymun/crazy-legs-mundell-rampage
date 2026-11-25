## How the campaign flows (pass 15): the balance bot (tools/balance_pilot.gd)
## plays the campaign as tools/balance.gd's run does (god mode off, the PLAY
## page's defaults, each chapter carried into the next, a death retried as
## the death screen does), and every attempt's flow is written down
## (tools/flow_probe.gd): fight and walk shares, the fights and the quiet
## between them, how many alerted hands are on the player at once, the damage
## from out of view, melee and dry seconds, the fight music, what a death cost,
## time to kill by kind, and the fight-rhythm director's beats. `report`
## turns the lines into the tables (tools/flow_tables.gd). Every play track
## shows its before and after with it.
##
##   godot --headless --path godot --script res://tools/flow_report.gd -- run
##       [diff=1] [skill=1] [seed=1] [hound=1] [chapters=a,b] [director=0] out=<file.jsonl>
##   godot --headless --path godot --script res://tools/flow_report.gd -- report
##       in=<file, files a,b or a dir> [md=<file>]
##
## run: one campaign, a line of JSON an attempt. `director=0` plays with the
## director off (DirectorData.ON) for a side by side on the same build. Each
## process wants its own APPDATA and LOCALAPPDATA when several run at once
## (the boss checkpoint lives in the cache folder). About two to four minutes
## a campaign on the desktop.
## (Keep _play_chapter in step with balance.gd's: what a death goes back to.)
extends SceneTree

const Pilot := preload("res://tools/balance_pilot.gd")
const Probe := preload("res://tools/flow_probe.gd")
const Tables := preload("res://tools/flow_tables.gd")
const STEP := 1.0 / 60.0
const ATTEMPT_LIMIT := 900.0
const MOST_DEATHS := 6
const DIRECTOR_DATA := "res://src/core/director_data.gd"

var main
var out_path := ""
var args := {}
var lines := 0


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
		var text: String = Tables.tables(str(args.get("in", "")))
		print(text)
		if args.has("md"):
			var f := FileAccess.open(str(args["md"]), FileAccess.WRITE)
			f.store_string(text)
			f.close()
		quit(0)
		return
	if args.get("director", "1") == "0" and ResourceLoader.exists(DIRECTOR_DATA):
		load(DIRECTOR_DATA).set("ON", false)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	out_path = str(args.get("out", ""))
	_campaign()
	main.queue_free()
	await process_frame
	print("FLOW RUN DONE: %d lines" % lines)
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


func _options(diff: int, hound: int) -> Dictionary:
	var options: Dictionary = SessionStore.defaults().duplicate()
	options["difficulty"] = diff
	options["hound"] = hound
	options["bench"] = 1
	options["opener"] = 0
	options["openers"] = 0
	return options


func _campaign() -> void:
	var diff := _int("diff", 1)
	var skill := _int("skill", 1)
	var seed_value := _int("seed", 1)
	var hound := _int("hound", 1)
	var only: Array = []
	if args.has("chapters"):
		only = Array(str(args["chapters"]).split(","))
	var options := _options(diff, hound)
	for key: String in options:
		main.options[key] = options[key]
	var chapters: Array = Campaign.ORDER if only.is_empty() else only
	var kit: Variant = null
	var history: Array = []
	for chapter: String in chapters:
		var base := {
			"diff": diff,
			"skill": skill,
			"seed": seed_value,
			"hound": hound,
			"director_on": args.get("director", "1") != "0",
			"chapter": chapter,
			"order": Campaign.ORDER.find(chapter)
		}
		if kit == null and chapter != "hickston":
			main.start(chapter, null, history, false, null)
			NetCoop.chapter_kit(main.game, chapter)
			main.game.entry = main.game.loadout()
		else:
			main.start(chapter, kit, history, false, null)
		var won := _play_chapter(base, seed_value, skill)
		var g: Game = main.game
		if not won:
			break
		kit = g.loadout()
		history = g.history.duplicate()
		history.append(g.result())


## The bench's mods bought with the scrap in hand, cheapest first.
func _buy(g: Game) -> Array:
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
	return got


## The chapter in main.game to its end, retrying deaths as balance.gd does.
func _play_chapter(base: Dictionary, seed_value: int, skill: int) -> bool:
	var deaths := 0
	var attempt := 0
	var mods := _buy(main.game)
	while true:
		attempt += 1
		var g: Game = main.game
		g.rng = GameState.Rng.new(seed_value * 1009 + int(base["order"]) * 31 + attempt)
		var row := base.duplicate()
		row["attempt"] = attempt
		row["mods_bought"] = mods
		var outcome := _attempt(g, Pilot.new(skill, seed_value * 13 + attempt), row)
		_write(row)
		if outcome == "clear":
			return true
		deaths += 1
		if deaths >= MOST_DEATHS or outcome == "timeout":
			var gone: Game = main.game
			if outcome == "death":
				main.restart_chapter(gone)
			var walk := main.game as Game
			walk.cheats.god = true
			_attempt(walk, Pilot.new(2, 1), {}, true)
			return bool(walk.won)
		if bool(row.get("boss_fight", false)):
			main.retry_fight()
		else:
			main.restart_chapter(g)
	return false


## One go until won, dead or out of time; `quiet`: a god-mode walk, unmeasured.
func _attempt(g: Game, pilot: Pilot, row: Dictionary, quiet := false) -> String:
	var probe: Probe = null if quiet else Probe.new(g, pilot)
	var start := g.clock
	var outcome := "timeout"
	while g.clock - start < ATTEMPT_LIMIT * (2.0 if quiet else 1.0):
		if probe != null:
			probe.before()
		var c := pilot.steer(g)
		g.tick(STEP, c)
		pilot.moved(g)
		if probe != null:
			probe.after()
		if g.won:
			outcome = "clear"
			break
		if g.player.health <= 0:
			outcome = "death"
			break
	if probe != null:
		probe.finish(row, outcome)
	return outcome
