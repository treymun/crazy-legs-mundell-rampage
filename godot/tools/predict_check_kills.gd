## predict_check.gd's pass 13 cases (NETLAST): what a client's shot or USE
## kills, finishes or breaks, drawn at the press (src/net/net_kill_looks.gd,
## net_finish_looks.gd, net_break_looks.gd), on the same rig (predict_check's
## Rig: the copy, its link, the host LAG ticks on).
##
## - a sure kill (a hand held still by a stun, low on health, our .38 well
##   on it): drawn dead from the press frame, never on its feet again, its
##   fall's moment the same every frame through the copy's own kill (one
##   doll, never begun again); off, when the copy kills it, LAG frames on;
## - a kill that is not sure (the hand free to move): never drawn dead
##   before the copy kills it, its flinch held every frame till then;
## - a sure kill the host refuses (the trigger never reached it): taken back,
##   counted (the only way a body stands up again);
## - a finisher (USE on a dazed hand): its move the same on the copy as drawn
##   at the press (picked from what both know with more than one player),
##   the gun's path from the press, the blow's sound heard once in all, the
##   hand drawn falling at the blow, the copy's own blow kept quiet;
## - a breakable our .38 is sure to break: drawn broken from the press, its
##   real pieces thrown once in all, its sound heard once, never whole again;
##   off, when the copy breaks it.
extends RefCounted

const STEP := NetSync.STEP


## Hickston co-op, a hand of `hp` health two steps ahead of player one (a
## .38 in hand, aimed at its middle), stunned for `stun` seconds.
static func _scene(check: Object, main: Object, hp: float, stun: float) -> Array:
	var g: Game = main.call("make_game", "hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var man: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and e.hp > 60.0 and not Game.BrawlScript.FLYING.has(e.brain):
			if Enemy.BOSS_TITLES.has(e.kind) or HitZones.metal(e) or e.kind == "tin_guard":
				continue
			if Variants.DOORS.has(e.kind):
				continue
			man = e
			break
	if man == null:
		check.call("_check", false, "a hand to shoot in Hickston")
		return []
	var spot := Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * 2.2
	if g.world.blocked(spot.x, spot.y, .4):
		a.angle += PI
		spot = Vector2(a.x, a.y) + Vector2(cos(a.angle), sin(a.angle)) * 2.2
	# Nobody else about to take the shot.
	for e: Enemy in g.enemies:
		if e != man and e.alive and Vector2(e.x - a.x, e.y - a.y).length() < 8.0:
			e.dormant = true
	a.armory.select(Weapons.REVOLVER, g)
	a.armory.loaded[Weapons.REVOLVER] = 6
	var place := func() -> void:
		man.x = spot.x
		man.y = spot.y
		man.dormant = false
		man.alerted = false
		man.windup = 0.0
		man.hp = hp
		man.stun = stun
		a.angle = atan2(man.y - a.y, man.x - a.x)
		a.pitch = (g.world.stand(man) + man.height * .55 - a.eye) / 2.2 * View.base_focal
	return [g, a, man, place]


## A sure kill drawn from the press (on) or when the copy plays it (off).
static func sure_kill(check: Object, main: Object, rig_class: Script, lag: int, on: bool) -> void:
	NetKillLooks.enabled = on
	var made := _scene(check, main, 5.0, 3.0)
	if made.is_empty():
		NetKillLooks.enabled = true
		return
	var g: Game = made[0]
	var man: Enemy = made[2]
	var place: Callable = made[3]
	var r: Object = rig_class.new(g)
	place.call()
	r.call("idle", lag + 4)
	place.call()
	r.set("frame_probe", func() -> Array: return [man.alive, man.died_at])
	var probes: Array = r.get("probes")
	var from := probes.size()
	r.call("step", check.call("_fire"))
	for i in lag + 30:
		r.call("step", Game.Controls.new())
	var drawn: Array = probes.slice(from)
	var first := -1
	var up_again := false
	var moments := {}
	for i in drawn.size():
		var row: Array = drawn[i]
		if not row[0]:
			if first < 0:
				first = i
			moments[row[1]] = true
		elif first >= 0:
			up_again = true
	var pred: NetShotPredict = r.get("pred")
	NetKillLooks.enabled = true
	var dead_copy := not man.alive
	check.call(
		"_check",
		(
			dead_copy
			and first >= 0
			and not up_again
			and moments.size() == 1
			and (first == 0) == on
			and (first >= lag) == (not on)
		),
		(
			(
				"a sure kill (%s): drawn dead %d frames after the press, never up again (%s), one"
				+ " fall moment (%d), the copy's own kill (%s); drawn %d, given %d"
			)
			% [
				"led" if on else "the copy's",
				first,
				not up_again,
				moments.size(),
				dead_copy,
				pred.kills.stats["sure"],
				pred.kills.stats["given"]
			]
		)
	)


## A killing shot on a hand free to move: its flinch held, never drawn dead
## before the copy kills it.
static func reel(check: Object, main: Object, rig_class: Script, lag: int) -> void:
	var made := _scene(check, main, 5.0, 0.0)
	if made.is_empty():
		return
	var g: Game = made[0]
	var man: Enemy = made[2]
	var place: Callable = made[3]
	var r: Object = rig_class.new(g)
	place.call()
	r.call("idle", lag + 4)
	place.call()
	r.set("frame_probe", func() -> Array: return [man.alive, man.flinch])
	var probes: Array = r.get("probes")
	var from := probes.size()
	r.call("step", check.call("_fire"))
	for i in lag + 20:
		r.call("step", Game.Controls.new())
	var drawn: Array = probes.slice(from)
	var died := -1
	var held := true
	for i in drawn.size():
		var row: Array = drawn[i]
		if not row[0]:
			died = i
			break
		var flinch: float = row[1]
		held = held and flinch > 0.0
	var pred: NetShotPredict = r.get("pred")
	check.call(
		"_check",
		died >= lag and held and pred.kills.stats["sure"] == 0 and pred.kills.stats["reels"] == 1,
		(
			(
				"a killing hit on a hand free to move: its flinch held every frame (%s), drawn dead"
				+ " only when the copy kills it (%d frames on), no kill drawn early (%d)"
			)
			% [held, died, pred.kills.stats["sure"]]
		)
	)


## A sure kill the host never plays (the shot refused): taken back, counted.
static func refused(check: Object, main: Object, rig_class: Script, lag: int) -> void:
	var made := _scene(check, main, 5.0, 3.0)
	if made.is_empty():
		return
	var g: Game = made[0]
	var man: Enemy = made[2]
	var place: Callable = made[3]
	var r: Object = rig_class.new(g)
	place.call()
	r.call("idle", lag + 4)
	place.call()
	r.set("refuse", func(c: Game.Controls) -> Game.Controls: return Game.Controls.new())
	r.set("frame_probe", func() -> bool: return man.alive)
	var probes: Array = r.get("probes")
	var from := probes.size()
	r.call("step", check.call("_fire"))
	for i in lag + NetKillLooks.GIVE_UP + 8:
		r.call("step", Game.Controls.new())
	var drawn: Array = probes.slice(from)
	var pred: NetShotPredict = r.get("pred")
	(
		check
		. call(
			"_check",
			not drawn[0] and drawn[-1] and man.alive and pred.kills.stats["withdrawn"] == 1,
			(
				"a sure kill the host refuses: drawn dead at the press, taken back (%d), alive on the copy"
				% pred.kills.stats["withdrawn"]
			)
		)
	)


## A finisher from USE on a man down to his last (pass 13): its move picked
## from what both know, the gun's path drawn from the press, the man falling
## at the blow, its sound heard once in all; off (`on` false), all of it
## when the copy plays it.
static func finisher(check: Object, main: Object, rig_class: Script, lag: int, on: bool) -> void:
	NetFinishLooks.enabled = on
	var made := _scene(check, main, 8.0, 3.0)
	if made.is_empty():
		NetFinishLooks.enabled = true
		return
	var g: Game = made[0]
	var a: Player = made[1]
	var man: Enemy = made[2]
	var place: Callable = made[3]
	var r: Object = rig_class.new(g)
	var near := func() -> void:
		place.call()
		var gap := Vector2(man.x - a.x, man.y - a.y).normalized()
		man.x = a.x + gap.x * .9
		man.y = a.y + gap.y * .9
	near.call()
	r.call("idle", lag + 4)
	near.call()
	var brawl: Game.BrawlScript = g.features.get("brawl")
	var picks := brawl.picks_for(a)
	var move := Game.BrawlScript.party_move(picks, man, a)
	var row: Dictionary = Game.BrawlScript.MOVE[move]
	var cue := str(row.get("cue", "brawl_punch"))
	if row.get("round", false):
		cue = str(Weapons.NAMES[a.armory.active])
	r.set("frame_probe", func() -> Array: return [absf(a.weapon_turn) > .01, man.alive])
	var probes: Array = r.get("probes")
	var from := probes.size()
	var ears: Object = r.get("ears")
	var before: int = ears.call("count", cue)
	var use := Game.Controls.new()
	use.use = true
	r.call("step", use)
	for i in lag + 40:
		r.call("step", Game.Controls.new())
	var drawn: Array = probes.slice(from)
	var swung := -1
	var fell := -1
	var up_again := false
	for i in drawn.size():
		var p: Array = drawn[i]
		if p[0] and swung < 0:
			swung = i
		if not p[1] and fell < 0:
			fell = i
		elif p[1] and fell >= 0:
			up_again = true
	var heard: int = ears.call("count", cue) - before
	var last: Array = brawl.last_moves.get(a.slot, [])
	var copy_move := str(last[0]) if not last.is_empty() else ""
	var pred: NetShotPredict = r.get("pred")
	NetFinishLooks.enabled = true
	var wind := int(ceilf(float(Game.BrawlScript.FINISH["wind"]) / STEP))
	var timed := (swung < 3 and fell <= wind + 1) if on else (swung >= lag and fell >= lag + wind)
	(
		check
		. call(
			"_check",
			(
				timed
				and not up_again
				and not man.alive
				and copy_move == move
				and heard == 1
				and pred.finishes.stats["matched"] == (1 if on else 0)
			),
			(
				(
					"a finisher (%s): the move %s the copy's (%s), the gun swung %d frames after USE, the"
					+ " man down %d frames on and never up again (%s), its sound heard once in all (%d)"
				)
				% ["led" if on else "the copy's", move, copy_move, swung, fell, not up_again, heard]
			)
		)
	)


## Something our .38 is sure to break (pass 13): drawn broken from the press
## (on) with its real pieces thrown and its sound heard then, once in all,
## never whole again; off, when the copy breaks it.
static func sure_break(check: Object, main: Object, rig_class: Script, lag: int, on: bool) -> void:
	NetBreakLooks.enabled = on
	var g: Game = main.call("make_game", "hickston")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.tick(STEP, Game.Controls.new())
	var a: Player = g.players[0]
	var pieces: Object = g.features.get("breakables")
	var wreck: Object = g.features.get("wreckage")
	var found: Object = null
	var spot := Vector2.ZERO
	for p: Object in pieces.get("pieces"):
		var spec: Dictionary = p.get("spec")
		var base: PackedFloat32Array = p.get("base")
		if p.get("broken") or not base.is_empty() or spec.get("sign", false) or spec.has("blast"):
			continue
		if str(spec.get("broken", "")) == "" or p.get("board") == null:
			continue
		var px: float = p.get("x")
		var py: float = p.get("y")
		for k in 16:
			var dir := Vector2(cos(k * TAU / 16.0), sin(k * TAU / 16.0))
			var at := Vector2(px, py) + dir * 2.5
			if g.world.blocked(at.x, at.y, .3) or not g.world.visible(at.x, at.y, px, py):
				continue
			found = p
			spot = at
			break
		if found != null:
			break
	if found == null:
		check.call("_check", false, "a crate to break in Hickston")
		NetBreakLooks.enabled = true
		return
	for e: Enemy in g.enemies:
		if e.alive and Vector2(e.x - spot.x, e.y - spot.y).length() < 10.0:
			e.dormant = true
	a.armory.select(Weapons.REVOLVER, g)
	a.armory.loaded[Weapons.REVOLVER] = 6
	var px2: float = found.get("x")
	var py2: float = found.get("y")
	var aim := func() -> void:
		a.x = spot.x
		a.y = spot.y
		a.vx = 0.0
		a.vy = 0.0
		a.angle = atan2(py2 - a.y, px2 - a.x)
		var foot: float = g.world.stand(found) + float(found.get("z"))
		var tall: float = found.get("height")
		a.pitch = (foot + tall * .5 - a.eye) / 2.5 * View.base_focal
		found.set("hp", 1.0)
	var r: Object = rig_class.new(g)
	aim.call()
	r.call("idle", lag + 4)
	aim.call()
	var spec2: Dictionary = found.get("spec")
	var broken := str(spec2["broken"])
	var cue := str(spec2.get("cue", "impact_wood"))
	var board: Object = found.get("board")
	r.set(
		"frame_probe",
		func() -> Array: return [str(board.get("image")) == broken, wreck.get("wrecks").size()]
	)
	var probes: Array = r.get("probes")
	var from := probes.size()
	var ears: Object = r.get("ears")
	var before: int = ears.call("count", cue)
	var wrecks_before: int = wreck.get("wrecks").size()
	r.call("step", check.call("_fire"))
	for i in lag + 20:
		r.call("step", Game.Controls.new())
	var drawn: Array = probes.slice(from)
	var first := -1
	var whole_again := false
	var thrown_at := -1
	for i in drawn.size():
		var row: Array = drawn[i]
		if row[0] and first < 0:
			first = i
		elif not row[0] and first >= 0:
			whole_again = true
		var count: int = row[1]
		if count > wrecks_before and thrown_at < 0:
			thrown_at = i
	var heard: int = ears.call("count", cue) - before
	var pred: NetShotPredict = r.get("pred")
	NetBreakLooks.enabled = true
	var timed := (first == 0 and thrown_at == 0) if on else (first >= lag and thrown_at >= lag)
	(
		check
		. call(
			"_check",
			timed and not whole_again and found.get("broken") and heard == 1,
			(
				(
					"a sure break (%s): drawn broken %d frames after the press, its pieces thrown %d on,"
					+ " never whole again (%s), its sound heard once in all (%d); drawn %d, given %d"
				)
				% [
					"led" if on else "the copy's",
					first,
					thrown_at,
					not whole_again,
					heard,
					pred.breaks.stats["shown"],
					pred.breaks.stats["given"]
				]
			)
		)
	)
