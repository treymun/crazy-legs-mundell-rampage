## The 5v5 bots measured and held (src/modes/tactical_bot.gd, bot_aim.gd),
## headless:
##
##   godot --headless --path godot --script res://tools/bot_check.gd
##       [-- bench] [skills=0,1,2,3] [ranges=4,8,14,22] [trials=16]
##       [map=grainyard] [hz=60] [gun=rifle] [no_match]
##
## AIM: one bot (TacticalBot, as it plays) against one target on an open
## lane of a 5v5 map, `trials` times at each skill, range and target: a
## STANDING target and a STRAFING one (a person's A-D dance: a run one way
## for a quarter to two thirds of a second, then the other, never more than
## 1.6 cells off its spot), both in a vest. The bot starts turned a little
## away (the target comes into view off the middle of its screen) with the
## gun up. Each trial ends at the kill or after CAP seconds (the target
## lived). Per row: time to the first shot and the first hit, time to kill
## (median; `lived` the share the target outlived CAP), the hit rate (shots
## that took health or vest off / shots fired), head hits (of hits) and head
## kills (of kills: the killing hit on the head).
##
## The check (no `bench`) runs a short set (EASY, NORMAL, HARD at 5, 12 and
## 20 cells) and holds each skill's numbers against a strafer inside BOUNDS
## (an EASY bot slower and wilder than a HARD one, none of them a laser up
## close, heading no more than MOST_HEADS of its hits), checks a bot holds its
## fire with a smoke cloud between and fires
## with the lane clear (SMOKE), and plays ten-bot matches (grainyard and
## salvage search and destroy, holler hostage rescue) so the bots plant, cut a
## fuse and carry hostages out, and the team radio speaks (OBJECTIVES).
## Prints BOT CHECK OK.
extends SceneTree

const CAP := 6.0
## The check's limits per skill (EASY, NORMAL, HARD, HOG WILD), at the check's
## ranges against the strafing target: [least, most] median seconds to the
## first hit; [least, most] hit rate; the least share of kills within CAP.
const BOUNDS := {
	0: {"first_hit": [.9, 3.5], "rate": [.12, .4], "kills": .35},
	1: {"first_hit": [.55, 1.6], "rate": [.2, .45], "kills": .6},
	2: {"first_hit": [.4, 1.1], "rate": [.3, .62], "kills": .8},
}
## Nobody is a laser: the most any skill hits a strafer at the nearest range.
const MOST_CLOSE := .9
## Nobody heads like a machine: the most of any skill's hits on a strafer that
## land on the head (aimed at the belly, a bot heads it only where its hand
## strays high; before 3.3.0 they aimed at the chest and some 60% of their
## pistol kills in a match were head shots).
const MOST_HEADS := .15

var failures: Array = []
var main: Control
var hz := 60.0
var gun_id := "rifle"
var dice := RandomNumberGenerator.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var bench := false
	var skills: Array = [0, 1, 2]
	var ranges: Array = [5.0, 12.0, 20.0]
	var trials := 10
	var map := "grainyard"
	var play_match := true
	for arg: String in OS.get_cmdline_user_args():
		if arg == "bench":
			bench = true
			skills = [0, 1, 2, 3]
			ranges = [4.0, 8.0, 14.0, 22.0]
			trials = 16
			play_match = false
		elif arg.begins_with("skills="):
			skills = Array(arg.substr(7).split(",")).map(func(s: String) -> int: return int(s))
		elif arg.begins_with("ranges="):
			ranges = Array(arg.substr(7).split(",")).map(func(s: String) -> float: return float(s))
		elif arg.begins_with("trials="):
			trials = int(arg.substr(7))
		elif arg.begins_with("map="):
			map = arg.substr(4)
		elif arg.begins_with("hz="):
			hz = float(arg.substr(3))
		elif arg.begins_with("gun="):
			gun_id = arg.substr(4)
		elif arg == "no_match":
			play_match = false
		elif arg == "match":
			play_match = true
	var errors := CrashLog.tally()
	var t0 := Time.get_ticks_msec()
	print(
		(
			"== AIM  %s, %s, %d Hz, %d trials a row, target in a vest, cap %.0f s"
			% [map, gun_id, int(hz), trials, CAP]
		)
	)
	print(
		(
			"  %-9s %5s %-8s %8s %8s %8s %6s %6s %6s %6s"
			% [
				"skill",
				"range",
				"target",
				"1st shot",
				"1st hit",
				"kill",
				"lived",
				"hits",
				"heads",
				"hs kl"
			]
		)
	)
	var by_skill := {}
	for skill: int in skills:
		var totals := {"first_hit": [], "hits": 0, "heads": 0, "shots": 0, "kills": 0, "n": 0}
		for d: float in ranges:
			for moving: bool in [false, true]:
				var row := _aim_row(map, skill, d, moving, trials)
				_print_row(skill, d, moving, row)
				if moving and d == ranges[0]:
					totals["close"] = float(row["hits"]) / maxf(1.0, float(row["shots"]))
				if moving:
					var hit_times: Array = row["first_hit_all"]
					totals["first_hit"].append_array(hit_times)
					totals["hits"] += int(row["hits"])
					totals["heads"] += int(row["heads"])
					totals["shots"] += int(row["shots"])
					totals["kills"] += int(row["kills"])
					totals["n"] += trials
		by_skill[skill] = totals
	print("  (%.0f s to run)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if not bench:
		for skill: int in by_skill:
			if not BOUNDS.has(skill):
				continue
			var t: Dictionary = by_skill[skill]
			var b: Dictionary = BOUNDS[skill]
			var first := _median(t["first_hit"])
			var rate := float(t["hits"]) / maxf(1.0, float(t["shots"]))
			var kills := float(t["kills"]) / maxf(1.0, float(t["n"]))
			var fb: Array = b["first_hit"]
			var rb: Array = b["rate"]
			var name := _skill_name(skill)
			_check(
				first >= float(fb[0]) and first <= float(fb[1]),
				"%s: first hit on a strafer %.2f s (%.2f..%.2f)" % [name, first, fb[0], fb[1]]
			)
			_check(
				rate >= float(rb[0]) and rate <= float(rb[1]),
				(
					"%s: hit rate on a strafer %.0f%% (%.0f..%.0f%%)"
					% [name, rate * 100.0, rb[0] * 100.0, rb[1] * 100.0]
				)
			)
			var close: float = t.get("close", 0.0)
			_check(
				close <= MOST_CLOSE,
				(
					"%s: no laser, %.0f%% hits on a strafer %.0f cells off"
					% [name, close * 100.0, ranges[0]]
				)
			)
			_check(
				kills >= float(b["kills"]),
				(
					"%s: kills a strafer within %.0f s %.0f%% (at least %.0f%%)"
					% [name, CAP, kills * 100.0, float(b["kills"]) * 100.0]
				)
			)
			var heads := float(t["heads"]) / maxf(1.0, float(t["hits"]))
			_check(
				heads <= MOST_HEADS,
				(
					"%s: head hits like a person's, %.0f%% of hits on a strafer (at most %.0f%%)"
					% [name, heads * 100.0, MOST_HEADS * 100.0]
				)
			)
		if by_skill.has(0) and by_skill.has(2):
			var easy := _median(by_skill[0]["first_hit"])
			var hard := _median(by_skill[2]["first_hit"])
			_check(easy > hard, "EASY is slower to hit than HARD (%.2f s > %.2f s)" % [easy, hard])
		_smoke(map)
	if play_match:
		_objectives()
	errors.stop()
	_check(
		errors.errors == 0,
		(
			"no script or engine errors"
			+ ("" if errors.errors == 0 else " (%d: %s)" % [errors.errors, errors.first_errors[0]])
		)
	)
	print("")
	print("BOT CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func _skill_name(skill: int) -> String:
	return ["EASY", "NORMAL", "HARD", "HOG WILD"][clampi(skill, 0, 3)]


static func _median(values: Array) -> float:
	if values.is_empty():
		return INF
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


func _print_row(skill: int, d: float, moving: bool, row: Dictionary) -> void:
	var shot := _median(row["first_shot_all"])
	var hit := _median(row["first_hit_all"])
	var kill := _median(row["kill_all"])
	print(
		(
			"  %-9s %5.0f %-8s %8s %8s %8s %5.0f%% %5.0f%% %5.0f%% %5.0f%%"
			% [
				_skill_name(skill),
				d,
				"strafing" if moving else "standing",
				"-" if shot == INF else "%.2f" % shot,
				"-" if hit == INF else "%.2f" % hit,
				"-" if kill == INF else "%.2f" % kill,
				100.0 * float(row["lived"]) / maxf(1.0, float(row["n"])),
				100.0 * float(row["hits"]) / maxf(1.0, float(row["shots"])),
				100.0 * float(row["heads"]) / maxf(1.0, float(row["hits"])),
				100.0 * float(row["head_kills"]) / maxf(1.0, float(row["kills"])),
			]
		)
	)


# ------------------------------------------------------------------- aim


## A 1v1 game on `map` set to `skill`, its first round live.
func _duel_game(map: String, skill: int) -> Game:
	var g: Game = main.make_game(map)
	g.configure({"difficulty": clampi(skill, 0, 3)})
	Modes.setup(g, Modes.BOMB, 2, {"arena": map, "rounds": 16, "bot_skill": skill})
	g.tick(1.0 / hz, {})
	var st = Modes.feature(g)
	st.phase = "live"
	st.live_from = g.clock
	return g


## A lane `d` long: [bot x, y, target x, y, the strafe's way x, y], both ends
## open and level, the target seen from the bot across its whole strafe.
func _lane(g: Game, d: float, seed_no: int) -> Array:
	var w := g.world
	dice.seed = 1013 * seed_no + int(d * 7.0)
	for attempt in 4000:
		var ax := dice.randf_range(2.0, w.width - 2.0)
		var ay := dice.randf_range(2.0, w.height - 2.0)
		var angle := dice.randf_range(0.0, TAU)
		var bx := ax + cos(angle) * d
		var by := ay + sin(angle) * d
		if not _open(g, ax, ay) or not _open(g, bx, by):
			continue
		if absf(w.elevation(ax, ay) - w.elevation(bx, by)) > .2:
			continue
		var side := Vector2(-sin(angle), cos(angle))
		var ok := true
		for k: float in [-1.8, -.9, 0.0, .9, 1.8]:
			var sx := bx + side.x * k
			var sy := by + side.y * k
			if not _open(g, sx, sy) or absf(w.elevation(sx, sy) - w.elevation(bx, by)) > .2:
				ok = false
				break
			var eye := w.elevation(ax, ay) + .95
			if not w.visible(ax, ay, sx, sy, eye, w.elevation(sx, sy) + .5):
				ok = false
				break
		if ok and not TacticalUtility.smoked(g, ax, ay, bx, by):
			return [ax, ay, bx, by, side.x, side.y]
	return []


func _open(g: Game, x: float, y: float) -> bool:
	return not g.world.blocked(x, y, .45) and not g.world.deep_at(x, y)


func _aim_row(map: String, skill: int, d: float, moving: bool, trials: int) -> Dictionary:
	var row := {
		"first_shot_all": [],
		"first_hit_all": [],
		"kill_all": [],
		"lived": 0,
		"hits": 0,
		"shots": 0,
		"heads": 0,
		"head_kills": 0,
		"kills": 0,
		"n": trials,
	}
	var g := _duel_game(map, skill)
	var st = Modes.feature(g)
	var bot_p: Player = g.players[0]
	var target: Player = g.players[1]
	var shots := [0]
	g.events.shot_fired.connect(
		func(_gun: int) -> void:
			if g.player == bot_p:
				shots[0] += 1
	)
	var gun_row := TacticalShop.item(gun_id)
	for t in trials:
		var lane := _lane(g, d, t + 1)
		if lane.is_empty():
			print("  (no lane %.0f long on %s)" % [d, map])
			return row
		var ax: float = lane[0]
		var ay: float = lane[1]
		var bx: float = lane[2]
		var by: float = lane[3]
		var side := Vector2(lane[4], lane[5])
		dice.seed = 77 + t * 31 + int(d) + (1000 if moving else 0)
		var off := dice.randf_range(.2, .8) * (1.0 if dice.randf() < .5 else -1.0)
		var bearing := atan2(by - ay, bx - ax)
		Modes.place(g, bot_p, ax, ay, bearing + off)
		Modes.place(g, target, bx, by, bearing + PI)
		Modes.stand_up(g, bot_p, 100)
		Modes.stand_up(g, target, 100)
		st.armor[target.slot] = float(TacticalShop.VEST)
		st.helmet[target.slot] = false
		st.armor[bot_p.slot] = float(TacticalShop.VEST)
		TacticalShop.base_kit(bot_p, 0)
		TacticalShop.give(st, bot_p, gun_row)
		TacticalShop.settle(bot_p.armory)
		st.phase = "live"
		st.live_from = g.clock
		st.round_winner = -1
		st.head_hit = {}
		st.clouds = []
		st.fires = []
		st.blind = {}
		g.won = false
		g.shots.clear()
		var bot := TacticalBot.new(bot_p.slot)
		bot.rng.seed = 5003 * (t + 1) + skill * 17 + int(d * 3.0) + (7 if moving else 0)
		var dir := 1.0 if dice.randf() < .5 else -1.0
		var flip_at := g.clock + dice.randf_range(.25, .65)
		var started := g.clock
		var first_shot := -1.0
		var first_hit := -1.0
		var killed := -1.0
		shots[0] = 0
		var hits := 0
		var heads := 0
		var last_head := false
		var was := target.health + int(st.armor[target.slot])
		var ticks := int(CAP * hz)
		for i in ticks:
			var given := {}
			g.focus(bot_p)
			given[bot_p.slot] = bot.steer(g)
			g.focus(target)
			var c := Game.Controls.new()
			if moving:
				var along := Vector2(target.x - bx, target.y - by).dot(side)
				if g.clock >= flip_at or absf(along) > 1.6 and signf(along) == dir:
					dir = -dir
					flip_at = g.clock + dice.randf_range(.25, .65)
				# The strafe is along the lane's side way whichever way it faces.
				var facing := Vector2(cos(target.angle), sin(target.angle))
				var want := side * dir
				c.forward = want.dot(facing)
				c.strafe = want.dot(Vector2(-facing.y, facing.x))
				c.running = true
			given[target.slot] = c
			g.focus(g.local_player)
			var shots_before: int = shots[0]
			g.tick(1.0 / hz, given)
			bot.moved(g)
			if shots[0] > shots_before and first_shot < 0.0:
				first_shot = g.clock - started
			var now := maxi(0, target.health) + int(st.armor[target.slot])
			if now < was:
				hits += 1
				last_head = st.head_hit.get(target.slot, false)
				if last_head:
					heads += 1
					st.head_hit.erase(target.slot)
				if first_hit < 0.0:
					first_hit = g.clock - started
			was = now
			if target.health <= 0:
				killed = g.clock - started
				break
		row["shots"] += shots[0]
		row["hits"] += hits
		row["heads"] += heads
		if first_shot >= 0.0:
			row["first_shot_all"].append(first_shot)
		row["first_hit_all"].append(first_hit if first_hit >= 0.0 else CAP)
		if killed >= 0.0:
			row["kills"] += 1
			row["kill_all"].append(killed)
			if last_head:
				row["head_kills"] += 1
		else:
			row["lived"] += 1
			row["kill_all"].append(CAP)
	return row


# ------------------------------------------------------------------ smoke


## A bot never takes a target behind a smoke cloud for a foe, fires at it or
## hurts it (and, the same lane clear, it does all three: the check means
## something). Shots it fires with no foe (at boarded cover) do not count.
func _smoke(map: String) -> void:
	var fired := []
	var saw := []
	var hurt := []
	for cloud: bool in [true, false]:
		var g := _duel_game(map, 2)
		var st = Modes.feature(g)
		var bot_p: Player = g.players[0]
		var target: Player = g.players[1]
		var lane := _lane(g, 10.0, 3)
		if lane.is_empty():
			_check(false, "a lane for the smoke check")
			return
		var shots := [0]
		var bot := TacticalBot.new(bot_p.slot)
		g.events.shot_fired.connect(
			func(_gun: int) -> void:
				if g.player == bot_p and bot.foe == target:
					shots[0] += 1
		)
		var ax: float = lane[0]
		var ay: float = lane[1]
		var bx: float = lane[2]
		var by: float = lane[3]
		var bearing := atan2(by - ay, bx - ax)
		Modes.place(g, bot_p, ax, ay, bearing)
		Modes.place(g, target, bx, by, bearing + PI)
		TacticalShop.give(st, bot_p, TacticalShop.item(gun_id))
		TacticalShop.settle(bot_p.armory)
		if cloud:
			# A cloud between them, already grown.
			var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
			st.clouds = [[mid.x, mid.y, g.clock + 30.0, g.clock - 3.0]]
		var seen := false
		for i in int(2.0 * hz):
			var given := {}
			g.focus(bot_p)
			given[bot_p.slot] = bot.steer(g)
			seen = seen or bot.foe == target
			g.focus(g.local_player)
			g.tick(1.0 / hz, given)
			bot.moved(g)
			# Both kept on the lane's ends: the line stays through the cloud.
			bot_p.x = ax
			bot_p.y = ay
			target.x = bx
			target.y = by
		fired.append(shots[0])
		saw.append(seen)
		hurt.append(target.health < 100)
	_check(
		not saw[0] and fired[0] == 0 and not hurt[0],
		"through a smoke cloud: not seen, %d shots at it, unhurt" % fired[0]
	)
	_check(
		saw[1] and fired[1] > 0 and hurt[1],
		"the same lane clear: seen, %d shots at it, hurt" % fired[1]
	)


# ------------------------------------------------------------- objectives


## Bots-only matches: the outlaws plant and the deputies cut a fuse in
## search and destroy, the deputies carry hostages out in hostage rescue.
func _objectives() -> void:
	print("== OBJECTIVES (ten bots)")
	var planted := 0
	var defused := 0
	var rescued := 0
	var radio := {}
	var carried := 0
	for job: Array in [
		["grainyard", Modes.BOMB], ["holler", Modes.HOSTAGE], ["salvage", Modes.BOMB]
	]:
		var map := String(job[0])
		var mode := String(job[1])
		var g: Game = main.make_game(map)
		g.configure({"difficulty": 1})
		Modes.setup(g, mode, 10, {"arena": map, "rounds": 3})
		TacticalScreens.human = -1
		var st = Modes.feature(g)
		var pilots := {}
		for p: Player in g.players:
			pilots[p.slot] = TacticalBot.new(p.slot)
		var was_state := ""
		var step := 1.0 / hz
		var rounds := 0
		var t0 := Time.get_ticks_msec()
		for i in int(16.0 * 60.0 * hz):
			var given := {}
			for p: Player in g.players:
				if p.health > 0:
					g.focus(p)
					given[p.slot] = pilots[p.slot].steer(g)
			g.focus(g.local_player)
			g.tick(step, given)
			TacticalRadio.listen(g, st)
			for line: String in TacticalRadio.lines(g):
				radio[line.substr(line.find(":") + 2)] = true
			for p: Player in g.players:
				pilots[p.slot].moved(g)
			if mode == Modes.BOMB:
				var state := String(st.bomb.get("state", ""))
				if state != was_state:
					if state == "planted":
						planted += 1
					elif state == "defused":
						defused += 1
					was_state = state
			else:
				for h: Array in st.hostages:
					if String(h[2]) == "carried" and was_state != "carried":
						carried += 1
						was_state = "carried"
				if String(st.phase) == "freeze":
					was_state = ""
			if st.history.size() > rounds:
				rounds = st.history.size()
				var last: Array = st.history[rounds - 1]
				if String(last[1]) == "RESCUE":
					rescued += 1
			if bool(st.match_over):
				break
		var reasons := {}
		for r: Array in st.history:
			reasons[String(r[1])] = int(reasons.get(String(r[1]), 0)) + 1
		print(
			(
				"  %-10s %-8s %d rounds in %.0f s of play (%.1f s to run): %s"
				% [map, mode, rounds, g.clock, (Time.get_ticks_msec() - t0) / 1000.0, str(reasons)]
			)
		)
	print(
		(
			"  planted %d, defused %d, hostages carried %d, rescues %d"
			% [planted, defused, carried, rescued]
		)
	)
	_check(planted > 0, "the outlaw bots plant the bomb (%d)" % planted)
	var cut := _defuse_scenarios()
	_check(
		defused + cut.size() > 0 and cut.size() == 3,
		"the deputy bots cut a fuse (%d in the matches; with the outlaws down: %s)" % [defused, cut]
	)
	_check(carried > 0, "the deputy bots carry a hostage (%d)" % carried)
	_check(rescued > 0, "the deputy bots get a hostage out (%d)" % rescued)
	print("  radio heard: ", ", ".join(radio.keys().slice(0, 8)))
	_check(radio.size() >= 3, "the team radio speaks (%d kinds of line)" % radio.size())


## A shine bomb planted on site A with every outlaw down (the round goes on
## while it ticks): the deputy bots come off their holds and cut it, on a
## 5v5 map of each kind and a 2v2 one. The maps they did it on.
func _defuse_scenarios() -> Array:
	var done: Array = []
	for map: String in ["grainyard", "salvage", "pineacres"]:
		var g: Game = main.make_game(map)
		g.configure({"difficulty": 1})
		var options := {"arena": map, "rounds": 3}
		var count := 10
		if Modes.TAGTEAM_MAPS.has(map):
			options.merge(Modes.TAGTEAM_OPTIONS)
			count = Modes.TAGTEAM_PLAYERS
		Modes.setup(g, Modes.BOMB, count, options)
		TacticalScreens.human = -1
		var st = Modes.feature(g)
		var pilots := {}
		for p: Player in g.players:
			pilots[p.slot] = TacticalBot.new(p.slot)
		var step := 1.0 / hz
		var planted := false
		for i in int((BombMode.BOMB_TIMER + 30.0) * hz):
			if not planted and String(st.phase) == "live":
				planted = true
				var box: Array = g.world.tactical["sites"]["A"]
				var centre := TacticalMode.box_centre(box)
				var spot := Modes.open_spot_near(g, centre.x, centre.y)
				for p: Player in g.players:
					if TacticalMode.side_of(st, p) == 0:
						p.health = 0
						p.down_at = g.clock
				st.bomb["state"] = "planted"
				st.bomb["site"] = "A"
				st.bomb["x"] = spot.x
				st.bomb["y"] = spot.y
				st.bomb["planted_at"] = g.clock
				st.bomb["beep_at"] = g.clock + 1.0
			var given := {}
			for p: Player in g.players:
				if p.health > 0:
					g.focus(p)
					given[p.slot] = pilots[p.slot].steer(g)
			g.focus(g.local_player)
			g.tick(step, given)
			if planted and String(st.bomb.get("state", "")) != "planted":
				break
		var state := String(st.bomb.get("state", ""))
		print("  %-10s bomb planted on A, outlaws down: %s" % [map, state])
		if state == "defused":
			done.append(map)
	return done
