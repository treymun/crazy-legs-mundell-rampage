## The first minutes of a brand-new profile, played by a new player
## (tools/newbie_pilot.gd: a ROOKIE that only does what the game has shown
## it), from NEW GAME into Hickston with the PLAY page's defaults (BLUE, the
## junk bench, county events, the tips). It writes down every notice, tip and
## USE prompt as they come, each objective and how long it took, the places
## it got lost (the way to the objective no shorter for LOST_AFTER seconds
## with nothing to fight), its deaths (retried as the death screen does) and
## what it wanted to do but was never told how. With a window and out=<dir>
## it also takes a picture at each of those moments (onboard_*.png).
##
##   godot --headless --path godot --script res://tools/onboard_walk.gd -- [secs=900]
##       [diff=1] [skill=0] [seed=1] [tips=0] [pad] [touch]
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/onboard_walk.gd -- out=<dir> [menus]
##
## Point APPDATA at a scratch folder: it plays with the profile there.
## tools/onboard_check.gd uses run() for its time budget.
extends SceneTree

const Newbie := preload("res://tools/newbie_pilot.gd")
const STEP := 1.0 / 60.0
## Seconds without getting nearer the objective (and nothing to fight) that
## count as lost.
const LOST_AFTER := 20.0

var main
var out := ""
var shots := 0
var args := {}
## What happened, in order: [game second, kind, text].
var log_rows: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var at := arg.find("=")
		args[arg if at < 0 else arg.substr(0, at)] = "1" if at < 0 else arg.substr(at + 1)
	out = str(args.get("out", ""))
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	if out != "":
		main.touring = true
		Effects.enabled = true
	if out != "" and args.has("menus"):
		await _menus()
	var device := "touch" if args.has("touch") else ("pad" if args.has("pad") else "keys")
	var result: Dictionary = await run(
		main,
		{
			"secs": float(args.get("secs", "900")),
			"diff": int(args.get("diff", "1")),
			"skill": int(args.get("skill", "0")),
			"seed": int(args.get("seed", "1")),
			"tips": int(args.get("tips", "1")),
			"device": device,
			"through": args.has("through"),
		},
		self
	)
	for row: Array in log_rows:
		print("%6.1f  %-8s %s" % [float(row[0]), str(row[1]), str(row[2])])
	print("ONBOARD WALK: ", JSON.stringify(result))
	main.queue_free()
	await process_frame
	quit()


## Title, CONTROLS (each page) and the SETTINGS page with the tips.
func _menus() -> void:
	main.game = null
	main.state = "title"
	await snap("title")
	main.state = "controls"
	for page in MainState.CONTROL_PAGES.size():
		main.controls_page = page
		await snap("controls_%d" % page)
	main.controls_page = 0
	main.state = "setup"
	var pages := SessionStore.setup_pages()
	for page in pages.size():
		if str(pages[page][0]) == "PLAY":
			main.option_page = page
			main.option_slot = (pages[page][1] as Array).size() - 1
			main.option_scroll = 0
			await snap("setup_play")
	main.state = "title"


## A picture of the window as it is now (only with out=<dir>).
func snap(name: String) -> void:
	if out == "":
		return
	shots += 1
	for i in 3:
		main.render()
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("onboard_%02d_%s.png" % [shots, name]))


func note(t: float, kind: String, text: String) -> void:
	log_rows.append([snappedf(t, .1), kind, text])


## Plays a new profile's first `secs` seconds of Hickston on main (a Main
## with its processing off) and returns what came of it. `walker` (this
## tool, for its pictures and log) may be null.
static func run(m: Variant, setup: Dictionary, walker: Variant = null) -> Dictionary:
	var options: Dictionary = SessionStore.defaults().duplicate()
	options["difficulty"] = int(setup.get("diff", 1))
	options["tips"] = int(setup.get("tips", 1))
	options["openers"] = 2
	for key: String in options:
		m.options[key] = options[key]
	m.input_device = str(setup.get("device", "keys"))
	if m.input_device == "touch":
		m.touch.showing = true  # the buttons over the view, as on a phone
		m.touch.layout(m.viewport_rect(), true)
	Lessons.forget()
	var skill: int = setup.get("skill", 0)
	var seed_value: int = setup.get("seed", 1)
	var limit: float = setup.get("secs", 900.0)
	# through: on past the sheriff's first sight until he falls.
	var through: bool = setup.get("through", false)
	m.start()
	var result := {
		"deaths": 0,
		"boss_at": -1.0,
		"lost": [],
		"objectives": [],
		"tips": [],
		"held_back": {},
		"clock": 0.0,
		"boss_down": -1.0,
		"boss_deaths": 0,
		"taken": {},
		"hurt_by": {},
	}
	var total := 0.0
	var attempt := 0
	var said := ""
	var tip_was := ""
	var tip_snap: Array = []
	var prompt := ""
	var objective := ""
	var objective_at := 0.0
	var prompts_seen := {}
	var seen_foe := false
	var hurt_once := false
	var next_mark := 60.0
	var pilot := Newbie.new(skill, seed_value)
	while total < limit:
		attempt += 1
		var g: Game = m.game
		g.rng = GameState.Rng.new(seed_value * 1009 + attempt)
		pilot = Newbie.new(skill, seed_value * 13 + attempt)
		var least := FlowField.FAR
		var least_at := g.clock
		var lost_logged := false
		var start := g.clock
		var cause := [""]
		var fight := [false]
		var taken: Dictionary = result["taken"]
		var base_t := total
		g.events.player_hurt.connect(
			func(amount: float, why: String) -> void:
				cause[0] = why
				var bucket := "%03d" % (int((base_t + g.clock - start) / 30.0) * 30)
				taken[bucket] = int(taken.get(bucket, 0)) + roundi(amount)
				var by: Dictionary = result["hurt_by"]
				var who := _shooter(g)
				by[who] = int(by.get(who, 0)) + roundi(amount)
		)
		g.events.boss_intro.connect(func(_e: Enemy) -> void: fight[0] = true)
		if walker != null:
			await walker.snap("start_%d" % attempt)
		while total + (g.clock - start) < limit:
			g.use_key = m.use_button()
			g.torch_key = m.torch_button()
			g.input_device = m.input_device
			var c: Game.Controls = pilot.steer(g)
			g.tick(STEP, c)
			pilot.moved(g)
			var now := total + (g.clock - start)
			if g.message_until > g.clock and g.notice != said:
				said = g.notice
				if walker != null:
					walker.note(now, "notice", said)
				if walker != null and now < 12.0:
					await walker.snap("notice")
			elif g.message_until <= g.clock:
				said = ""
			if g.tip_until > g.clock and g.tip != tip_was:
				tip_was = g.tip
				(result["tips"] as Array).append([snappedf(now, .1), Lessons.last_id])
				if walker != null:
					walker.note(now, "tip", g.tip)
					tip_snap = [now + .35, Lessons.last_id]  # a moment on: drawn in full
			if not tip_snap.is_empty() and now >= float(tip_snap[0]):
				if walker != null:
					await walker.snap("tip_" + str(tip_snap[1]))
				tip_snap = []
			var shown := g.use_prompt()
			if shown != prompt:
				prompt = shown
				if shown != "" and not prompts_seen.has(shown):
					prompts_seen[shown] = true
					if walker != null:
						walker.note(now, "prompt", shown)
						await walker.snap("prompt")
			var words := g.objective()
			if words != objective:
				if objective != "":
					(result["objectives"] as Array).append(
						[objective, snappedf(now - objective_at, .1)]
					)
				objective = words
				objective_at = now
				if walker != null:
					walker.note(now, "goal", words)
			if pilot.foe != null and not seen_foe:
				seen_foe = true
				if walker != null:
					walker.note(now, "fight", "first hand after it: " + pilot.foe.kind)
					await walker.snap("first_fight")
			if g.player.health < 100 and not hurt_once:
				hurt_once = true
				if walker != null:
					walker.note(now, "hurt", "first hit taken")
			if float(result["boss_at"]) < 0.0 and g.boss != null and g.boss.alive:
				var boss_d := Vector2(g.boss.x - g.player.x, g.boss.y - g.player.y).length()
				if boss_d < 12.0 and g.world.visible(g.player.x, g.player.y, g.boss.x, g.boss.y):
					result["boss_at"] = snappedf(now, .1)
					result["boss_health"] = g.player.health
					result["boss_rounds"] = _rounds(g)
					if walker != null:
						walker.note(now, "boss", "the sheriff in sight")
						await walker.snap("boss")
			var goal: Variant = g.objective_target()
			if goal != null and pilot.foe == null:
				var d := g.route.distance(g.player.x, g.player.y, g.world.stand(g.player))
				if d < least - .5:
					least = d
					least_at = g.clock
					lost_logged = false
				elif g.clock - least_at > LOST_AFTER and not lost_logged:
					lost_logged = true
					var area: String = g.level.districts[g.district] if g.district >= 0 else "?"
					var row := [snappedf(now, .1), area, words, snappedf(d, .1)]
					(result["lost"] as Array).append(row)
					if walker != null:
						walker.note(now, "lost", "%s, %s, %.0f steps" % [area, words, d])
						await walker.snap("lost")
			elif pilot.foe != null:
				least_at = g.clock
			if now >= next_mark:
				next_mark += 60.0
				if walker != null:
					walker.note(
						now,
						"minute",
						(
							"health %d, kills %d, %s"
							% [g.player.health, g.kills, g.level.districts[maxi(g.district, 0)]]
						)
					)
					await walker.snap("minute_%d" % int(now / 60.0))
			if through and float(result["boss_down"]) < 0.0 and g.boss != null and not g.boss.alive:
				result["boss_down"] = snappedf(now, .1)
				if walker != null:
					walker.note(now, "boss", "the sheriff down")
			var done := float(result["boss_at"]) >= 0.0 and not through
			done = done or float(result["boss_down"]) >= 0.0
			if g.won or g.player.health <= 0 or done:
				break
		total += g.clock - start
		for id: String in pilot.held_back:
			result["held_back"][id] = pilot.held_back[id]
		if (float(result["boss_at"]) >= 0.0 and not through) or g.won:
			break
		if float(result["boss_down"]) >= 0.0:
			break
		if g.player.health <= 0:
			result["deaths"] = int(result["deaths"]) + 1
			if walker != null:
				var area: String = g.level.districts[maxi(g.district, 0)]
				walker.note(total, "death", "%s (%s)" % [area, cause[0]])
				await walker.snap("death")
			if fight[0] or float(result["boss_at"]) >= 0.0:
				result["boss_deaths"] = int(result["boss_deaths"]) + 1
			# As the death screen's ENTER: RETRY THE FIGHT, BACK TO THE MARKER
			# (pass 15) or the chapter's start.
			m.retry_death(g)
			continue
		break
	result["clock"] = snappedf(total, .1)
	result["eaten"] = pilot.eaten
	return result


## The kind of the nearest hostile after the player that can see them
## (who a hit most likely came from).
static func _shooter(g: Game) -> String:
	var best := "?"
	var near := 30.0
	for e: Enemy in g.enemies:
		if not (e.alive and e.hostile and e.alerted):
			continue
		var d := Vector2(e.x - g.player.x, e.y - g.player.y).length()
		if d < near and g.world.visible(g.player.x, g.player.y, e.x, e.y):
			near = d
			best = e.kind
	return best


## Rounds carried for every gun owned (loaded and in reserve), by gun.
static func _rounds(g: Game) -> Dictionary:
	var out := {}
	var a := g.armory
	for slot in Weapons.COUNT:
		if a.owned[slot] and not Weapons.MELEE.has(slot):
			out[str(Weapons.NAMES[slot])] = a.loaded[slot] + a.reserve[slot]
	return out
