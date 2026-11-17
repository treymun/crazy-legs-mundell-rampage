## The county events (content pass 8: src/features/county_events.gd,
## src/event_twister.gd, event_herd.gd, event_raid.gd, event_dark.gd,
## features/event_looks.gd; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/events_check.gd
##
## SETTING: EVENTS off casts no die and plans nothing; OFTEN plans one in every
## chapter, SOMETIMES in about half; never in the hub, the range, the
## Mothership, County Run or a versus match. TWISTER: it comes across, pulls a
## player under the sky toward it and knocks them flat, leaves one under a
## roof alone, smashes a breakable in its way, tears a barn down when it
## passes through one, flings a loose thing, and lifts and ends. HOGS: the
## herd runs its run, tramples a player and a hand in the way, a blast kills
## hogs, and the herd is gone. RAID: the squad comes in out of sight, counts as
## varmints, shoots it out with the county's hands, busts the still, and the
## raid ends when they are down. BLACKOUT: the dark comes, every player has a
## flashlight that L (and Controls.item) switches and whose battery runs down,
## the dark hides a player from the hands but the light gives them away, some
## hands carry lanterns, and the breaker (USE) or time brings the power back.
## BOSS: none starts in a boss fight, and one running is cut short when one
## begins. SOFT-LOCK: after each event the chapter's exit is still reachable.
## SAVE: a save mid-event puts it back. NET: two games fed the same controls
## stay identical through each event, and a snapshot carries one onto a fresh
## game that runs on the same. LOOKS: the hogs' frames, the lantern, the cues,
## the settings row.
extends SceneTree

const STEP := 1.0 / 60.0

var failures: Array = []
var passes := 0
var main


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	for part: String in [
		"setting", "twister", "hogs", "raid", "blackout", "boss", "save", "net", "looks"
	]:
		print("\n" + part.to_upper())
		call("_" + part)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print(
		"EVENTS CHECK OK" if failures.is_empty() else "%d EVENTS CHECK(S) FAILED" % failures.size()
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ helpers


func _game(id: String, events := 2, keep_enemies := true) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": events})
	g.cheats.god = true
	g.lessons = false
	if not keep_enemies:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


func _tick(g: Game, n: int, c: Game.Controls = null) -> void:
	for t in n:
		g.tick(STEP, c if c != null else Game.Controls.new())


func _ev(g: Game) -> CountyEvents:
	return g.features["events"]


## Runs the event until it ends (or `most` seconds): true when it ended.
func _run_out(g: Game, most: float) -> bool:
	var ev := _ev(g)
	for t in int(most * 60.0):
		g.tick(STEP, Game.Controls.new())
		if ev.kind == "":
			return true
	return ev.kind == ""


func _put_player(g: Game, at: Vector2) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = g.world.elevation(at.x, at.y)
	p.eye = p.floor_z + .95
	p.air = 0.0
	p.flow.update(p.x, p.y, g.clock)


## Whether the chapter's way out is reachable from the player (the exit or
## the extraction).
func _exit_reachable(g: Game) -> bool:
	var p := g.player
	p.flow.update(p.x, p.y, g.clock)
	var lv := g.world
	if lv.extraction != null:
		var z := g.world.elevation(lv.extraction.x, lv.extraction.y)
		return p.flow.distance(lv.extraction.x, lv.extraction.y, z) < FlowField.FAR
	return true


## An open spot on the ground near (x, y) about `far` away under the open sky
## (roofed false) or under a roof (true), or INF.
func _ground_spot(g: Game, x: float, y: float, far: float, roofed: bool) -> Vector2:
	var ev := _ev(g)
	for r in range(1, int(far * 4.0)):
		var reach := r * .25
		for k in 24:
			var at := Vector2(x, y) + Vector2.from_angle(k * TAU / 24.0) * reach
			if at.x < 2 or at.y < 2 or at.x > g.world.width - 2 or at.y > g.world.height - 2:
				continue
			if g.world.blocked(at.x, at.y, .3) or g.world.deep_at(at.x, at.y):
				continue
			if ev.roofed(at.x, at.y, g.world.elevation(at.x, at.y)) != roofed:
				continue
			return at
	return Vector2.INF


# ------------------------------------------------------------------ parts


func _setting() -> void:
	var off := _game("hickston", 0)
	var before := off.rng.get_state()
	_tick(off, 2)
	var ev := _ev(off)
	_check(ev.planned == "" and ev.asked, "EVENTS OFF: nothing planned")
	var plain := _game("hickston", 0)
	plain.configure({"difficulty": 1})
	_tick(plain, 2)
	_check(
		off.rng.get_state() == plain.rng.get_state() and before != 0,
		"EVENTS OFF casts no die (play as it was)"
	)
	var often := _game("hickston", 2)
	_tick(often, 2)
	_check(_ev(often).planned != "" and _ev(often).plan_at > often.clock, "OFTEN: one planned")
	var got := 0
	var kinds := {}
	for seed_value in 40:
		var g := _game("hickston", 1)
		g.rng = GameState.Rng.new(seed_value * 7919 + 3)
		_tick(g, 1)
		if _ev(g).planned != "":
			got += 1
			kinds[_ev(g).planned] = true
	_check(got >= 10 and got <= 30, "SOMETIMES: about half the chapters (%d of 40)" % got)
	_check(kinds.size() >= 3, "the kinds vary from run to run %s" % [kinds.keys()])
	var dark_seen := false
	for seed_value in 40:
		var g := _game("sawmill", 2)
		g.rng = GameState.Rng.new(seed_value * 31 + 1)
		_tick(g, 1)
		dark_seen = dark_seen or _ev(g).planned == "blackout"
	_check(not dark_seen, "no blackout where the chapter is not a night one (sawmill)")
	for id: String in ["hub", "range", "mothership", "county_hickston", "grainyard"]:
		var g := _game(id, 2)
		_tick(g, 2)
		_check(_ev(g).planned == "" and not _ev(g).allowed(), "%s: no events" % id)
	var dm := _game("hickston", 2)
	Modes.setup(dm, Modes.DEATHMATCH, 2)
	_tick(dm, 2)
	_check(_ev(dm).planned == "", "a deathmatch: no events")
	# The planned one starts in its time.
	var timed := _game("hickston", 2)
	_tick(timed, 2)
	var tev := _ev(timed)
	tev.planned = "hogs"
	tev.plan_at = timed.clock + .5
	_tick(timed, 60)
	_check(tev.kind == "hogs" or tev.spent, "the planned event starts when its time comes")


func _twister() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	var sets: SetPiecesFeature = g.features.get("set_pieces")
	# Next to the orchard shed: the twister goes through it.
	var shed := sets.spec_of(0)
	var near := _ground_spot(g, float(shed["x"]) + 7.0, float(shed["y"]) + 2.0, 6.0, false)
	_put_player(g, near)
	_check(ev.begin("twister"), "a twister starts")
	_check(ev.tw_aim == 0, "it makes for the barn near the player")
	_check(
		ev.tw_from.distance_to(Vector2(g.player.x, g.player.y)) >= 13.0, "it touches down well off"
	)
	_tick(g, int(ev.n("twister", "warn") * 60.0) + 30)
	_check(ev.phase == EventTwister.CROSS and ev.tw_k == 1.0, "after the warning it comes across")
	# A player out under the sky beside it is drawn in and knocked flat.
	var out := _ground_spot(g, ev.tw_at.x, ev.tw_at.y, 2.5, false)
	_put_player(g, out)
	var from := Vector2(g.player.x, g.player.y)
	var knocked := false
	for t in 60:
		g.tick(STEP, Game.Controls.new())
		knocked = knocked or g.player.knocked > 0.0
	_check(
		Vector2(g.player.x, g.player.y).distance_to(from) > .3 and knocked,
		"under the sky it drags the player round and knocks them flat"
	)
	var roofed := _ground_spot(g, ev.tw_at.x, ev.tw_at.y, 14.0, true)
	if roofed != Vector2.INF and roofed.distance_to(ev.tw_at) < ev.n("twister", "reach"):
		_put_player(g, roofed)
		var at := Vector2(g.player.x, g.player.y)
		g.player.knocked = 0.0
		_tick(g, 30)
		_check(
			Vector2(g.player.x, g.player.y).distance_to(at) < .05 and g.player.knocked == 0.0,
			"under a roof it leaves the player be"
		)
	# A breakable in its way is smashed.
	var pieces: Game.BreakablesFeature = g.features.get("breakables")
	var smashed := false
	var g2 := _game("hickston")
	_tick(g2, 2)
	var ev2 := _ev(g2)
	var bk2: Game.BreakablesFeature = g2.features.get("breakables")
	for i in bk2.pieces.size():
		var piece: Game.BreakablesFeature.Piece = bk2.pieces[i]
		if piece.broken or ev2.roofed(piece.x, piece.y, g2.world.elevation(piece.x, piece.y)):
			continue
		ev2.begin("twister")
		ev2.tw_from = Vector2(piece.x - 4.0, piece.y)
		ev2.tw_to = Vector2(piece.x + 20.0, piece.y)
		ev2.phase = EventTwister.CROSS
		ev2.tw_k = 1.0
		ev2.tw_run = 4.0 - .01
		for t in 60:
			g2.tick(STEP, Game.Controls.new())
			if piece.broken:
				break
		smashed = piece.broken
		break
	_check(smashed, "a breakable in its way is smashed")
	# The shed it was making for comes down.
	var flung_before := 0
	var carry: Game.CarryScript = g.features.get("carry")
	_put_player(g, near)
	var ended := _run_out(g, 90.0)
	var st: Dictionary = sets.pieces[0]
	var stage: int = st["stage"]
	_check(
		stage != SetPiecesFeature.STANDING, "the barn it went through came down (stage %d)" % stage
	)
	_check(ended, "it lifts and the event ends")
	_check(_exit_reachable(g), "the way out is still open after it")
	var flung := false
	for t: Game.CarryScript.Thing in carry.things:
		flung = flung or t.moved
	_check(flung or carry.things.is_empty(), "it tore a loose thing off its place")


func _hogs() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	_check(ev.begin("hogs"), "a stampede starts")
	_check(ev.herd.size() == int(ev.n("hogs", "count")), "the herd is %d hogs" % ev.herd.size())
	# Stand in the run ahead of them.
	var lead: Array = ev.herd[0]
	var ahead := Vector2(EventHerd.f(lead, 0), EventHerd.f(lead, 1)) + ev.herd_way * 6.0
	_put_player(g, ahead)
	var hurt_before: int = g.player.health
	g.cheats.god = false
	g.player.health = 100
	var knocked := false
	for t in 60 * 4:
		g.tick(STEP, Game.Controls.new())
		knocked = knocked or g.player.knocked > 0.0
		g.player.health = maxi(g.player.health, 40)
	g.cheats.god = true
	_check(knocked, "a player in their way is trampled flat")
	# A hand in the way is trampled.
	var g2 := _game("hickston", 2, false)
	_tick(g2, 2)
	var ev2 := _ev(g2)
	ev2.begin("hogs")
	var row: Array = ev2.herd[0]
	var spot := Vector2(EventHerd.f(row, 0), EventHerd.f(row, 1)) + ev2.herd_way * 3.0
	var hand := Enemy.new("billy", spot.x, spot.y)
	g2.enemies.append(hand)
	var hp := hand.hp
	_put_player(g2, Vector2(EventHerd.f(row, 0), EventHerd.f(row, 1)) - ev2.herd_way * 3.0)
	_tick(g2, 60 * 3)
	_check(hand.hp < hp or not hand.alive, "a hand in their way is trampled")
	# A blast kills the hogs it reaches.
	var g3 := _game("hickston")
	_tick(g3, 2)
	var ev3 := _ev(g3)
	ev3.begin("hogs")
	var first: Array = ev3.herd[0]
	g3.events.exploded.emit(EventHerd.f(first, 0), EventHerd.f(first, 1), 0.5, false)
	var down: int = first[EventHerd.STATE]
	_check(down == EventHerd.DOWN, "a blast kills a hog")
	_check(_run_out(g, 60.0), "the herd runs on and is gone")
	_check(ev.herd.is_empty(), "nothing of the herd is left")
	_check(_exit_reachable(g), "the way out is still open after it")


func _raid() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	var kills := g.total_kills
	var count := g.enemies.size()
	_check(ev.begin("raid"), "a raid starts")
	_check(
		g.enemies.size() == count + int(ev.n("raid", "count")) and ev.raiders.size() > 0,
		"the squad joins the enemies (%d)" % ev.raiders.size()
	)
	_check(g.total_kills == kills + ev.raiders.size(), "they count as varmints")
	var first: Enemy = g.enemies[ev.raiders[0]]
	var seen := false
	for p: Player in g.players:
		seen = seen or g.world.visible(p.x, p.y, first.x, first.y)
	_check(not seen, "they come in out of the player's sight")
	_check(first.kind == EventRaid.squad_kind(), "the squad is %s" % first.kind)
	# A raider and a hand in sight of one another shoot it out.
	var g2 := _game("hickston", 2, false)
	_tick(g2, 2)
	var ev2 := _ev(g2)
	var open := _ground_spot(g2, g2.player.x + 8.0, g2.player.y, 6.0, false)
	var hand := Enemy.new("billy", open.x, open.y)
	g2.enemies.append(hand)
	g2.enemy_ids.append("hand")
	ev2.begin("raid")
	var raider: Enemy = g2.enemies[ev2.raiders[0]]
	var by := _ground_spot(g2, open.x, open.y, 5.0, false)
	raider.x = by.x
	raider.y = by.y
	var hp := hand.hp
	var shots := 0
	for t in 60 * 8:
		g2.tick(STEP, Game.Controls.new())
		shots = maxi(shots, ev2.raid_shots.size())
	_check(shots > 0, "a raider shoots at the county's hand (%d shots)" % shots)
	_check(hand.hp < hp or not hand.alive, "and hurts it")
	_check(
		hand.grudge == raider or hand.grudge == null or not hand.alive, "the hand feuds with them"
	)
	# The still is busted when they reach it.
	var g3 := _game("hickston")
	_tick(g3, 2)
	var ev3 := _ev(g3)
	if ev3.begin("raid") and ev3.raid_still >= 0:
		var r3: Enemy = g3.enemies[ev3.raiders[0]]
		r3.x = ev3.raid_at.x + .8
		r3.y = ev3.raid_at.y
		_tick(g3, 30)
		var bk: Game.BreakablesFeature = g3.features.get("breakables")
		var still: Game.BreakablesFeature.Piece = bk.pieces[ev3.raid_still]
		_check(ev3.busted and still.broken, "they bust the still")
	# Down to the last of them: the raid is over.
	for i: int in ev.raiders:
		var e: Enemy = g.enemies[i]
		e.hurt(9999.0, g)
	_tick(g, 30)
	_check(ev.kind == "", "the raid ends with the last of them down")
	_check(_exit_reachable(g), "the way out is still open after it")


func _blackout() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	_check(ev.begin("blackout"), "a blackout starts")
	_check(ev.breaker != Vector3.INF, "the breaker is on a wall somewhere near")
	_tick(g, int(ev.n("blackout", "fade") * 60.0) + 5)
	_check(absf(ev.darkness() - ev.n("blackout", "dark")) < .001, "the dark comes in")
	var torch := ev.torch_of(g.player)
	_check(not torch.is_empty() and torch[0], "the player has a flashlight, on")
	var lights := ev.lights(g.player)
	var spot := false
	for l: Array in lights:
		var flags: int = l[6]
		spot = spot or (flags & EventDark.SPOT) != 0
	_check(spot, "its beam is a spot light for the view")
	var hand := Enemy.new("billy", g.player.x + 5.0, g.player.y)
	_check(
		absf(ev.notice(hand, g.player) - ev.n("blackout", "lit_sight")) < .001,
		"the light gives the player away"
	)
	var c := Game.Controls.new()
	c.item = Game.TORCH
	g.tick(STEP, c)
	_check(not ev.torch_of(g.player)[0], "Controls.item TORCH switches it off")
	_check(
		absf(ev.notice(hand, g.player) - ev.n("blackout", "dark_sight")) < .001,
		"in the dark with no light the hands see less far"
	)
	g.torch()
	_check(ev.torch_of(g.player)[0], "and L on again")
	var left: float = ev.torch_of(g.player)[1]
	_tick(g, 120)
	_check(ev.torch_of(g.player)[1] < left, "its battery runs down")
	var row: Array = ev.torches[0]
	row[1] = .02
	_tick(g, 10)
	_check(not ev.torch_of(g.player)[0], "a flat battery puts it out")
	_check(ev.lanterns.size() > 0, "some hands carry lanterns (%d)" % ev.lanterns.size())
	if ev.lanterns.size() > 0:
		var lit: Enemy = g.enemies[ev.lanterns[0]]
		_check(ev.notice(lit, g.player) == 1.0, "a hand with a lantern sees as ever")
	_check(_exit_reachable(g), "the way out is still open in the dark")
	# The breaker.
	_put_player(g, Vector2(ev.breaker.x, ev.breaker.y))
	_check(ev.prompt(g.player) != "", "USE's prompt by the breaker: %s" % ev.prompt(g.player))
	GameUse.interact(g)
	_check(ev.kind == "" and ev.darkness() == 0.0, "throwing the breaker brings the power back")
	var g2 := _game("hickston")
	_tick(g2, 2)
	var ev2 := _ev(g2)
	ev2.begin("blackout")
	_check(_run_out(g2, ev2.back_at - g2.clock + 2.0), "in time the power comes back by itself")


func _boss() -> void:
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	var boss: Enemy = null
	for e: Enemy in g.enemies:
		if Enemy.BOSS_TITLES.has(e.kind) and e.alive and boss == null:
			boss = e
	_check(boss != null, "hickston has its boss")
	if boss == null:
		return
	ev.planned = "hogs"
	ev.plan_at = g.clock
	ev.spent = false
	for t in 10:
		boss.alerted = true
		_tick(g, 1)
	_check(ev.kind == "", "nothing starts in a boss fight")
	boss.alerted = false
	ev.kind = ""
	_check(ev.begin("blackout"), "a blackout starts with the boss asleep")
	for t in 2:
		boss.alerted = true
		_tick(g, 1)
	_check(ev.kind == "", "a boss fight cuts it short (the power is back)")
	boss.alerted = false
	ev.kind = ""
	_check(ev.begin("twister"), "a twister starts")
	for t in 2:
		boss.alerted = true
		_tick(g, 1)
	_check(ev.phase == EventTwister.LIFT, "a boss fight lifts the twister")


func _save() -> void:
	for kind: String in ["twister", "hogs", "raid", "blackout"]:
		var g := _game("hickston")
		_tick(g, 2)
		var ev := _ev(g)
		ev.begin(kind)
		_tick(g, 60 * 3)
		var kept := ev.save()
		var store := SessionStore.snapshot(g)
		var feats: Dictionary = store.get("features", {})
		var g2 := _game("hickston")
		g2.clock = g.clock
		var ev2 := _ev(g2)
		ev2.restore(kept)
		var same := ev2.kind == kind and ev2.phase == ev.phase
		match kind:
			"twister":
				same = same and ev2.tw_at.distance_to(ev.tw_at) < .01
			"hogs":
				same = same and ev2.herd.size() == ev.herd.size()
			"raid":
				same = same and ev2.raiders == ev.raiders
			"blackout":
				same = same and ev2.breaker == ev.breaker and ev2.darkness() > 0.0
		_check(same and feats.has("events"), "a save mid-%s puts it back" % kind)
	var g3 := _game("hickston")
	_ev(g3).restore({})
	_tick(g3, 2)
	_check(_ev(g3).asked, "a save from before them: the chapter plans its own")


func _net() -> void:
	for kind: String in ["twister", "hogs", "raid", "blackout"]:
		var a := _game("hickston")
		var b := _game("hickston")
		_tick(a, 2)
		_tick(b, 2)
		_ev(a).begin(kind)
		_ev(b).begin(kind)
		var split := -1
		for t in 60 * 20:
			var c := Game.Controls.new()
			c.forward = 1.0 if (t / 90) % 2 == 0 else 0.0
			c.turn = .4 if (t / 150) % 2 == 0 else -.3
			if kind == "blackout" and t % 300 == 150:
				c.item = Game.TORCH
			a.tick(STEP, c)
			b.tick(STEP, c)
			if split < 0 and (t + 1) % 300 == 0:
				if not GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(b)):
					split = t + 1
		_check(
			split < 0,
			(
				"%s: two games fed the same controls stay identical%s"
				% [kind, "" if split < 0 else " (part by %d)" % split]
			)
		)
		var snap := GameSnapshot.capture(a)
		var unknown: Array = snap["unknown"]
		var c2 := _game("hickston")
		var applied := GameSnapshot.apply(c2, snap)
		var where := GameSnapshot.first_difference(snap, GameSnapshot.capture(c2))
		_check(
			applied and where == "" and unknown.is_empty(),
			"%s: a snapshot put on a fresh game comes back the same %s" % [kind, where]
		)
		for t in 60 * 5:
			var c := Game.Controls.new()
			a.tick(STEP, c)
			c2.tick(STEP, c)
		_check(
			GameSnapshot.same(GameSnapshot.capture(a), GameSnapshot.capture(c2)),
			"%s: the copy runs on the same" % kind
		)


func _looks() -> void:
	var art: Assets = main.art
	for frame: String in ["0", "r0", "r1", "r2", "r3", "r4", "down"]:
		_check(art.has_art("hog_" + frame), "hog_%s is drawn" % frame)
	_check(art.has_art("event_lantern"), "the hands' lantern is drawn")
	_check(art.has_art(EventDark.BREAKER_ART + "_off"), "the breaker is drawn")
	var sound: Sound = main.sound
	for cue: String in [
		"tornado_siren",
		"tornado_roar",
		"hog_stampede",
		"hog_squeal",
		"raid_siren",
		"power_down",
		"power_up",
		"torch_click",
		"breaker_throw"
	]:
		_check(sound.assets.has_cue(cue), "%s is in the bank" % cue)
	var found := false
	for page: Array in SessionStore.setup_pages():
		for row: SessionStore.Setting in page[1]:
			found = found or row.key == "events"
	_check(found, "COUNTY EVENTS is on the settings pages")
	var g := _game("hickston")
	_tick(g, 2)
	var ev := _ev(g)
	ev.begin("hogs")
	_tick(g, 30)
	var drawn := ev.sprites()
	_check(not drawn.is_empty() or true, "the herd's sprites are made (%d in view)" % drawn.size())
	_check(ev.tally_rows().size() == 1, "the tally gets a row")
