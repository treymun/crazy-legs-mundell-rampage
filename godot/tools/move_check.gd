## The walk and the quick hands (pass 15, MOVES), headless:
##
##   godot --headless --path godot --script res://tools/move_check.gd [-- numbers]
##
## FEEL: on an open lane of the range, scripted keys measure the walk (time
## to full speed, how far a stop slides on, how much the air steers, how
## far a slide goes) and hold each to its band; a walk does not slide, a
## slide waits out its rest, letting go of CROUCH or a jump ends it (a hop
## keeps its speed), a wall stops it; an online client's prediction
## (NetPredict.step) walks the same keys to the same place, slide and all.
## HANDS: KICK boots a man in front, and at a shut door stood still it is
## the boot, never USE's door; THROW tosses a stick from the .38 and the .38
## comes back up; no sticks, nothing thrown; a swap takes switch_time; FIRE
## pulled stops a reload with rounds in the gun, not one from empty nor one
## begun with the trigger held.
## WIRE: KICK and THROW through the net codec (PROTOCOL 6), dropped from a
## held input and kept by a merged one; a replay with them plays back
## exactly, and a version-1 recording (buttons as a byte) still plays.
## `numbers` prints the feel numbers only. Prints MOVE CHECK OK.
extends SceneTree

const STEP := 1.0 / 60.0
const Brawl := preload("res://tools/brawl_check.gd")

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var only_numbers := OS.get_cmdline_user_args().has("numbers")
	_feel(main, only_numbers)
	if not only_numbers:
		_hands(main)
		_wire(main)
	print("")
	print("MOVE CHECK OK" if failures.is_empty() else "%d MOVE CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


# ------------------------------------------------------------------ helpers


func _lane(main, length := 22) -> Game:
	var g: Game = Brawl.game(main)
	var at: Vector2 = Brawl.lane(g, length)
	Brawl.stand(g, at)
	return g


func _keys(
	forward := 0.0, run := true, crouch := false, jump := false, strafe := 0.0
) -> Game.Controls:
	var c := Game.Controls.new()
	c.forward = forward
	c.strafe = strafe
	c.running = run
	c.crouch = crouch
	c.jump = jump
	return c


func _speed(p: Player) -> float:
	return Vector2(p.vx, p.vy).length()


## Ticks with `c` until `done` says so or `most` seconds; the seconds taken.
func _until(g: Game, c: Game.Controls, done: Callable, most := 3.0) -> float:
	var t := 0.0
	while t < most and not done.call():
		g.tick(STEP, c)
		t += STEP
	return t


# --------------------------------------------------------------------- feel


func _feel(main, only_numbers: bool) -> void:
	print("FEEL (modes.cfg [move])")
	var g := _lane(main)
	var p := g.player
	var full := Moves.RUN
	var to_full := _until(g, _keys(1.0), func() -> bool: return _speed(p) >= full * .9)
	_until(g, _keys(1.0), func() -> bool: return false, .4)
	var x0 := p.x
	var to_stop := _until(g, _keys(0.0), func() -> bool: return _speed(p) < .05)
	var stop_dist := p.x - x0
	# The air: a jump from standing with a strafe held, side speed at the top.
	g = _lane(main)
	p = g.player
	g.tick(STEP, _keys(0.0, true, false, true))
	_until(g, _keys(0.0, true, false, true, 1.0), func() -> bool: return false, .25)
	var air_side := _speed(p)
	_until(g, _keys(), func() -> bool: return p.air == 0.0)
	# The slide: full speed, then CROUCH held.
	g = _lane(main)
	p = g.player
	_until(g, _keys(1.0), func() -> bool: return false, .6)
	x0 = p.x
	g.tick(STEP, _keys(1.0, true, true))
	var top := _speed(p)
	var slid := p.slide > 0.0
	var slide_t := STEP + _until(g, _keys(1.0, true, true), func() -> bool: return p.slide <= 0.0)
	var slide_dist := p.x - x0
	# The same half second crouch-walked from the same run, for comparison.
	var g2 := _lane(main)
	var p2 := g2.player
	_until(g2, _keys(1.0), func() -> bool: return false, .6)
	p2.slide_rest = 9.0
	var x2 := p2.x
	_until(g2, _keys(1.0, true, true), func() -> bool: return false, slide_t)
	var crouch_dist := p2.x - x2
	print(
		(
			"  run %.2f cells/s: 90 %% of it in %.0f ms; a stop in %.0f ms over %.2f cells;"
			% [full, to_full * 1000.0, to_stop * 1000.0, stop_dist]
		)
	)
	print(
		(
			(
				"  the air steers to %.2f cells/s sideways in .25 s; a slide %.2f cells in %.2f s"
				% [air_side, slide_dist, slide_t]
			)
			+ " from %.2f cells/s (crouch-walking: %.2f cells)" % [top, crouch_dist]
		)
	)
	if only_numbers:
		return
	# Before pass 15 (run 3.85, ease_stop 30, ease_air 7): 90 % of the run in
	# 117 ms, a stop in 150 ms over .13 cells, the air 3.2 cells/s sideways in
	# .25 s, no slide. Snappy, never floaty or slippery:
	check(to_full <= .14, "full speed in %.0f ms (at most 140)" % (to_full * 1000.0))
	check(
		stop_dist < .1 and to_stop <= .12,
		(
			"a stop is short: %.2f cells, %.0f ms (.13 cells, 147 ms before)"
			% [stop_dist, to_stop * 1000.0]
		)
	)
	check(
		air_side > 3.4 and air_side < Moves.RUN,
		"the air steers to %.2f cells/s (3.2 before)" % air_side
	)
	check(slid and top >= Moves.SLIDE_SPEED - .01, "CROUCH on the run slides at %.2f" % top)
	check(
		slide_dist > crouch_dist * 1.6 and slide_dist < 3.2,
		"a slide goes %.2f cells, %.1fx a crouch-walk" % [slide_dist, slide_dist / crouch_dist]
	)
	check(absf(slide_t - Moves.SLIDE_FOR) < .05, "and lasts slide_for (%.2f s)" % slide_t)
	_slide_rules(main)
	_predicted(main)


func _slide_rules(main) -> void:
	# A walk does not slide.
	var g := _lane(main)
	var p := g.player
	_until(g, _keys(1.0, false), func() -> bool: return false, .6)
	g.tick(STEP, _keys(1.0, false, true))
	check(p.slide == 0.0, "a walk (%.2f) crouches, no slide" % Moves.WALK)
	# Its rest: a second CROUCH at once does not slide; after the rest it does.
	g = _lane(main, 26)
	p = g.player
	_until(g, _keys(1.0), func() -> bool: return false, .5)
	g.tick(STEP, _keys(1.0, true, true))
	_until(g, _keys(1.0, true, false), func() -> bool: return false, .1)
	check(p.slide == 0.0, "letting go of CROUCH ends the slide")
	g.tick(STEP, _keys(1.0, true, true))
	check(p.slide == 0.0, "and another waits its rest")
	_until(g, _keys(1.0), func() -> bool: return false, Moves.SLIDE_REST + .1)
	g.tick(STEP, _keys(1.0, true, true))
	check(p.slide > 0.0, "after slide_rest a slide again")
	# A hop out of it.
	g = _lane(main)
	p = g.player
	_until(g, _keys(1.0), func() -> bool: return false, .5)
	g.tick(STEP, _keys(1.0, true, true))
	_until(g, _keys(1.0, true, true), func() -> bool: return false, .1)
	g.tick(STEP, _keys(1.0, true, true, true))
	g.tick(STEP, _keys(1.0, true, true, true))
	var hop := _speed(p)
	check(
		p.slide == 0.0 and p.air > 0.0 and hop > Moves.RUN,
		"JUMP in a slide hops out of it at %.2f cells/s" % hop
	)
	# Into a wall: over.
	g = Brawl.game(main)
	var wall := _wall_ahead(g)
	if wall.x < 0.0:
		check(false, "a wall on the range to slide into")
		return
	Brawl.stand(g, wall)
	p = g.player
	p.vx = Moves.RUN
	_until(g, _keys(1.0), func() -> bool: return false, .05)
	g.tick(STEP, _keys(1.0, true, true))
	var began := p.slide > 0.0
	var t := _until(g, _keys(1.0, true, true), func() -> bool: return p.slide <= 0.0, .6)
	check(
		began and p.slide == 0.0 and t < Moves.SLIDE_FOR - .03,
		"a slide into a wall stops there (%.2f s in)" % t
	)


## A spot with open floor east of it and a wall about two cells on.
func _wall_ahead(g: Game) -> Vector2:
	var w := g.world
	for y in range(3, w.height - 3):
		for x in range(3, w.width - 5):
			var z := w.elevation(x + .5, y + .5)
			var open := true
			for k in 3:
				if (
					w.blocked(x + k + .5, y + .5, .45)
					or absf(w.elevation(x + k + .5, y + .5) - z) > .01
				):
					open = false
			if open and w.blocked(x + 3.5, y + .5, .1) and w.roof[w.cell(x + .5, y + .5)] == 0.0:
				return Vector2(x + .5, y + .5)
	return Vector2(-1, -1)


## The keys walked by the game and by an online client's prediction end in
## the same place (a run, a slide, a hop, a stop).
func _predicted(main) -> void:
	var trace: Array = []
	for i in 30:
		trace.append(_keys(1.0))
	for i in 20:
		trace.append(_keys(1.0, true, true, false, .4 if i > 8 else 0.0))
	trace.append(_keys(1.0, true, true, true))
	for i in 40:
		trace.append(_keys(1.0, true, false, false, -.5))
	for i in 20:
		trace.append(_keys())
	var g := _lane(main)
	for c: Game.Controls in trace:
		g.tick(STEP, c)
	var a := g.player
	var h := _lane(main)
	var b := h.player
	for c: Game.Controls in trace:
		NetPredict.step(h, b, c, STEP)
	var off := Vector2(a.x - b.x, a.y - b.y).length()
	check(off < 1e-6, "an online client's prediction walks it to the same place (%.6f off)" % off)


# -------------------------------------------------------------------- hands


func _hands(main) -> void:
	print("HANDS (KICK, THROW, the swap, a reload stopped)")
	var g: Game = Brawl.game(main)
	var at: Vector2 = Brawl.lane(g, 8)
	Brawl.stand(g, at)
	var e: Enemy = Brawl.hand(g, "billy", at.x + 1.2, at.y)
	var c := Game.Controls.new()
	c.kick = true
	g.tick(STEP, c)
	Brawl.ticks(g, .7)
	var b = Brawl.brawl(g)
	check(b.kicks == 1 and e.x > at.x + 2.0, "KICK boots the man in front")
	# At a shut door, standing: KICK is the boot (into the air), USE opens it.
	g = Brawl.game(main, "hickston")
	b = Brawl.brawl(g)
	var door := _door_spot(g)
	if door.is_empty():
		check(false, "a plain shut door on hickston")
	else:
		var d: LevelData.Door = door[0]
		var spot: Vector2 = door[1]
		Brawl.stand(g, spot, door[2])
		Brawl.ticks(g, .8)
		c = Game.Controls.new()
		c.kick = true
		g.tick(STEP, c)
		Brawl.ticks(g, .5)
		check(
			d.progress == 0.0 and not d.opened and b.kicked_at.has(g.player.slot),
			"KICK at a shut door, stood still: the boot, the door left be"
		)
		Brawl.ticks(g, .8)
		Brawl.press_use(g)
		Brawl.ticks(g, .2)
		check(d.progress > 0.0 or d.opened, "where USE opens it")
	# THROW from the .38 (on hickston: the range tops its sticks up).
	g = Brawl.game(main, "hickston")
	Brawl.stand(g, Brawl.lane(g, 8))
	var arms := g.armory
	arms.owned[Weapons.DYNAMITE] = true
	arms.reserve[Weapons.CROSSBOW] = 3
	arms.select(Weapons.REVOLVER, g)
	Brawl.ticks(g, .5)
	var shots := g.shots.size()
	var sticks: int = arms.reserve[Weapons.CROSSBOW]
	c = Game.Controls.new()
	c.throw = true
	g.tick(STEP, c)
	var thrown := g.shots.size() == shots + 1 and str(g.shots[g.shots.size() - 1].kind) == "tnt"
	check(
		thrown and arms.reserve[Weapons.CROSSBOW] == sticks - 1 and arms.active == Weapons.DYNAMITE,
		"THROW lights and tosses a stick from the .38"
	)
	Brawl.ticks(g, Weapons.THROW_BACK + Weapons.SWITCH_TIME)
	check(arms.active == Weapons.REVOLVER and arms.switch == 0.0, "and the .38 comes back up")
	arms.reserve[Weapons.CROSSBOW] = 0
	shots = g.shots.size()
	g.tick(STEP, c)
	check(g.shots.size() == shots and arms.active == Weapons.REVOLVER, "no sticks: nothing thrown")
	# The swap.
	arms.owned[Weapons.SHOTGUN] = true
	arms.loaded[Weapons.SHOTGUN] = 2
	arms.select(Weapons.SHOTGUN, g)
	var swap := _until(g, Game.Controls.new(), func() -> bool: return arms.switch <= 0.0)
	check(
		absf(swap - Weapons.SWITCH_TIME) < .02 and Weapons.SWITCH_TIME <= .17,
		"a swap takes %.0f ms (230 before pass 15)" % (swap * 1000.0)
	)
	# A reload stopped by FIRE with rounds in, not from empty.
	arms.select(Weapons.REVOLVER, g)
	Brawl.ticks(g, .4)
	arms.loaded[Weapons.REVOLVER] = 3
	arms.reserve[Weapons.REVOLVER] = 30
	arms.start_reload(g)
	g.tick(STEP, Game.Controls.new())
	var fire := Game.Controls.new()
	fire.fire = true
	g.tick(STEP, fire)
	check(
		arms.reload == 0.0 and arms.loaded[Weapons.REVOLVER] == 2,
		"FIRE stops a reload and shoots what is loaded"
	)
	Brawl.ticks(g, .6)
	g.tick(STEP, fire)
	arms.start_reload(g)
	g.tick(STEP, fire)
	check(arms.reload > 0.0, "a reload begun with the trigger held goes on (a fresh pull stops it)")
	Brawl.ticks(g, 2.0)
	arms.loaded[Weapons.REVOLVER] = 0
	arms.start_reload(g)
	g.tick(STEP, Game.Controls.new())
	g.tick(STEP, fire)
	check(arms.reload > 0.0, "a reload from empty goes on")


## [door, where to stand, facing] at a plain shut door of `g`.
func _door_spot(g: Game) -> Array:
	for d: LevelData.Door in g.world.doors:
		if d.opened or d.key != "" or d.secret or d.blast_only or d.progress > 0.0:
			continue
		if g.world.controlled_doors.has(Vector2i(d.x, d.y)):
			continue
		var center := d.center()
		for side in [-1.0, 1.0]:
			var off := Vector2(side, 0.0) if d.vertical else Vector2(0.0, side)
			var at := center + off * 1.1
			if g.world.blocked(at.x, at.y, .3):
				continue
			var face := atan2(-off.y, -off.x)
			Brawl.stand(g, at, face)
			var found: Variant = GameUse.use_target(g)
			if found != null and found[0] == d:
				return [d, at, face]
	return []


# --------------------------------------------------------------------- wire


func _wire(main) -> void:
	print("WIRE (net codec, replays)")
	var c := Game.Controls.new()
	c.kick = true
	c.throw = true
	c.forward = 1.0
	var bytes := NetWire.pack_controls(c)
	var back := NetWire.unpack_controls(bytes)
	check(
		(
			NetWire.PROTOCOL == 6
			and bytes.size() == NetWire.CONTROL_BYTES
			and back.kick
			and back.throw
		),
		"KICK and THROW go over the wire (protocol %d, %d bytes)" % [NetWire.PROTOCOL, bytes.size()]
	)
	var held := NetWire.unpack_controls(NetWire.held_only(bytes))
	check(
		not held.kick and not held.throw and held.forward == 1.0, "a late input's repeat drops them"
	)
	var merged := NetWire.unpack_controls(
		NetWire.merged(bytes, NetWire.pack_controls(Game.Controls.new()))
	)
	check(merged.kick and merged.throw, "a skipped input's presses are kept")
	for version in [Replay.VERSION, 1]:
		var g: Game = Brawl.game(main)
		Brawl.stand(g, Brawl.lane(g, 20))
		g.cheats.god = false
		g.armory.owned[Weapons.DYNAMITE] = true
		g.armory.reserve[Weapons.CROSSBOW] = 4
		Brawl.hand(g, "billy", g.player.x + 6.0, g.player.y)
		var rec := Replay.record(g, {})
		rec.write_version = version
		for i in 300:
			var k := _keys(1.0 if i < 120 else 0.0, true, i >= 40 and i < 70, i == 80)
			if version >= 2:
				k.kick = i == 100
				k.throw = i == 140 or i == 200
			k.turn = .01 if i % 50 < 10 else 0.0
			rec.tick(STEP, k)
			g.tick(STEP, k)
			rec.ticked()
			if i == 160:
				rec.act(["throw"])
				rec.act(["kick"])
		var pb := Replay.Playback.new(Replay.from_bytes(rec.to_bytes()))
		pb.start(Callable(main, "make_game"))
		pb.run()
		check(
			pb.diverged < 0 and pb.hashes >= 2 and pb.game.player.x == g.player.x,
			"a version-%d replay plays back exactly (%d hashes)" % [version, pb.hashes]
		)
