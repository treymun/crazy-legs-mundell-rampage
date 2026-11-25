## Dirty fighting (features/brawl.gd, content pass 8), headless:
##
##   Godot --headless --path <project> --script res://tools/brawl_check.gd
##
## The boot slides a hand back, dazes him and slams him into a wall harder
## than open ground; it knocks a second man down the line; a running USE at
## a shut door kicks it in. A finisher of each class (pistol, long gun,
## blade, the boot) drops a low hand with its own move, in slow motion when
## alone and not with two players; a swing of the crowbar finishes too; a
## healthy hand is kicked, not finished. Every hazard kind kills a man booted
## into it (the saw, chipper, crusher, zapper, hot fence, burn barrel, well,
## cattle guard, the water and the hogs); a hand walking past one is not
## caught. A boss is kicked, never finished, and a hazard only takes his
## share. Two runs of the same boot end the same, and a snapshot taken mid
## slide plays on the same on a copy, tick for tick (net sync).
extends SceneTree

const STEP := 1.0 / 60.0
const Brawl := preload("res://src/features/brawl.gd")

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(main, func(ok: bool, text: String) -> void: _check(ok, text))
	print("")
	print("BRAWL OK" if failures.is_empty() else "%d BRAWL CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func run(main, check: Callable) -> void:
	print("BRAWL (the boot, finishers, hazards, bosses, net sync)")
	_boot(main, check)
	_finishers(main, check)
	_hazards(main, check)
	_bonus(main, check)
	_bosses(main, check)
	_door(main, check)
	_smash(main, check)
	_sync(main, check)
	_looks(main, check)


# ------------------------------------------------------------------ helpers


static func game(main, level := "range") -> Game:
	var g: Game = main.make_game(level)
	g.configure({})
	g.cheats.god = true
	Modes.clear_enemies(g)
	return g


static func hand(g: Game, kind: String, x: float, y: float) -> Enemy:
	var e := Enemy.new(kind, x, y)
	e.dormant = false
	e.uid = g.take_uid()
	e.alerted = true
	g.enemies.append(e)
	e.floor_z = g.world.elevation(x, y)
	return e


## A run of open, level floor `length` cells east of a cell, on `g`'s level:
## [x, y] of its west end (the player stands there).
static func lane(g: Game, length: int, from := Vector2i(2, 2)) -> Vector2:
	var w := g.world
	for y in range(from.y, w.height - 2):
		for x in range(from.x, w.width - length - 2):
			var ok := true
			var z := w.elevation(x + .5, y + .5)
			for k in length + 1:
				for dy in [-1, 0, 1]:
					var cx: float = x + k + .5
					var cy: float = y + dy + .5
					if (
						w.blocked(cx, cy, .45)
						or absf(w.elevation(cx, cy) - z) > .01
						or BayouBrains.wet_at(w, cx, cy)
						or w.roof[w.cell(cx, cy)] > 0.0
					):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2(x + .5, y + .5)
	return Vector2(-1, -1)


static func stand(g: Game, at: Vector2, angle := 0.0) -> Player:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = angle
	p.floor_z = g.world.elevation(at.x, at.y)
	p.air = 0.0
	p.vx = 0.0
	p.vy = 0.0
	return p


static func ticks(g: Game, seconds: float, c: Game.Controls = null) -> void:
	for i in int(seconds * 60.0):
		g.tick(STEP, c if c != null else Game.Controls.new())


static func press_use(g: Game) -> void:
	var c := Game.Controls.new()
	c.use = true
	g.tick(STEP, c)
	g.tick(STEP, Game.Controls.new())


static func brawl(g: Game) -> Brawl:
	return g.features["brawl"]


# --------------------------------------------------------------------- boot


static func _boot(main, check: Callable) -> void:
	var g := game(main)
	var at := lane(g, 8)
	stand(g, at)
	var e := hand(g, "billy", at.x + 1.2, at.y)
	var hp := e.hp
	press_use(g)
	ticks(g, .7)
	var b := brawl(g)
	var went := e.x - (at.x + 1.2)
	check.call(
		b.kicks == 1 and went > 1.5 and e.hp < hp and e.alive,
		"the boot slides a hand back %.2f cells, hurt (%.0f of %.0f)" % [went, hp - e.hp, hp]
	)
	check.call(b.finishable(e), "and leaves him dazed: open to a finisher")
	# Into a wall: a slam, harder than the open floor.
	var wall := game(main)
	var spot := Vector2(-1, -1)
	for y in range(2, wall.world.height - 2):
		for x in range(4, wall.world.width - 2):
			if (
				wall.world.blocked(x + 2.5, y + .5, .2)
				and not wall.world.blocked(x + 1.5, y + .5, .45)
				and not wall.world.blocked(x - .5, y + .5, .45)
				and not wall.world.blocked(x + .5, y + .5, .45)
				and (
					absf(
						wall.world.elevation(x - .5, y + .5) - wall.world.elevation(x + 1.5, y + .5)
					)
					< .01
				)
			):
				spot = Vector2(x - .5, y + .5)
				break
		if spot.x >= 0.0:
			break
	stand(wall, spot)
	var w := hand(wall, "billy", spot.x + 1.2, spot.y)
	var whp := w.hp
	press_use(wall)
	ticks(wall, .7)
	check.call(
		whp - w.hp > hp - e.hp + 5.0,
		"into a wall he slams: %.0f against %.0f in the open" % [whp - w.hp, hp - e.hp]
	)
	# Down the line: a second man is knocked on.
	var d := game(main)
	var lane2 := lane(d, 9)
	stand(d, lane2)
	var a := hand(d, "coot", lane2.x + 1.2, lane2.y)
	var z := hand(d, "coot", lane2.x + 2.3, lane2.y)
	var zx := z.x
	press_use(d)
	ticks(d, .8)
	check.call(
		z.x - zx > .4 and a.alive, "a man booted into another knocks him on (%.2f)" % [z.x - zx]
	)
	# A healthy hand at USE is kicked, never finished; nothing in reach: USE as ever.
	check.call(brawl(d).finished.is_empty(), "a healthy hand gets the boot, not a finisher")


# --------------------------------------------------------------- finishers


static func _finishers(main, check: Callable) -> void:
	var guns := {
		"pistol": Weapons.NAMES.find("revolver"),
		"long": Weapons.NAMES.find("shotgun"),
		"blade": Weapons.NAMES.find("crowbar"),
		"boot": Weapons.NAMES.find("tnt"),
	}
	for cls: String in guns:
		var g := game(main)
		var at := lane(g, 6)
		var p := stand(g, at)
		var gun: int = guns[cls]
		p.armory.owned[gun] = true
		p.armory.loaded[gun] = maxi(p.armory.loaded[gun], 2)
		p.armory.reserve[gun] = maxi(p.armory.reserve[gun], 6)
		p.armory.active = gun
		p.armory.switch = 0.0
		var e := hand(g, "billy", at.x + 1.1, at.y)
		e.hp = e.max_hp * .2
		press_use(g)
		var crisp := g.slowmo == 0.0
		ticks(g, .2)
		var slow := g.slowmo > 0.0 and crisp
		ticks(g, 1.0)
		var b := brawl(g)
		var move := ""
		for k: String in b.finished:
			move = k
		var row: Dictionary = Brawl.MOVE.get(move, {})
		check.call(
			not e.alive and move != "" and str(row.get("class", "")) == cls and slow,
			(
				"%s: a low hand is finished (%s), the wind at full speed, the blow in slow motion"
				% [cls, row.get("name", "-")]
			)
		)
	# Each move of each class lands (picked by game.rng: try seeds until seen).
	var seen := {}
	for seed in 40:
		var g := game(main)
		g.rng.set_state(seed * 7919 + 1)
		var at := lane(g, 6)
		var p := stand(g, at)
		var cls: String = ["pistol", "long", "blade", "boot"][seed % 4]
		var gun: int = guns[cls]
		p.armory.owned[gun] = true
		p.armory.loaded[gun] = maxi(p.armory.loaded[gun], 2)
		p.armory.active = gun
		p.armory.switch = 0.0
		var e := hand(g, "coot", at.x + 1.1, at.y)
		e.hp = 1.0
		press_use(g)
		ticks(g, .8)
		for k: String in brawl(g).finished:
			seen[k] = true
	check.call(
		seen.size() == Brawl.MOVE.size(),
		"every move lands (%s)" % ", ".join(PackedStringArray(seen.keys()))
	)
	# A crowbar's swing finishes a man too.
	var s := game(main)
	var sat := lane(s, 6)
	var sp := stand(s, sat)
	var bar := Weapons.NAMES.find("crowbar")
	sp.armory.owned[bar] = true
	sp.armory.active = bar
	sp.armory.switch = 0.0
	sp.armory.cooldown = 0.0
	var se := hand(s, "billy", sat.x + 1.1, sat.y)
	se.hp = se.max_hp * .25
	var fire := Game.Controls.new()
	fire.fire = true
	s.tick(STEP, fire)
	ticks(s, 1.0)
	check.call(not se.alive and not brawl(s).finished.is_empty(), "a swing of the crowbar finishes")
	# SLOW-MO FINISHERS off: none.
	var two := game(main)
	var tat := lane(two, 6)
	stand(two, tat)
	var te := hand(two, "billy", tat.x + 1.1, tat.y)
	te.hp = 1.0
	two.finish_slowmo = false
	press_use(two)
	ticks(two, .3)
	check.call(two.slowmo == 0.0, "SLOW-MO FINISHERS off: the finisher plays at full speed")
	# Co-op: the second player finishes a man; no slow motion with two.
	var co := game(main)
	var cat := lane(co, 6)
	stand(co, cat + Vector2(0.0, 0.0))
	co.player.x = cat.x + 5.0
	var p2 := Players.join(co, cat.x, cat.y, 0.0)
	p2.floor_z = co.world.elevation(cat.x, cat.y)
	var ce := hand(co, "billy", cat.x + 1.1, cat.y)
	ce.hp = 1.0
	var use := Game.Controls.new()
	use.use = true
	co.tick(STEP, {p2.slot: use})
	var co_slow := co.slowmo
	for i in 60:
		co.tick(STEP, {})
	check.call(
		not ce.alive and co_slow == 0.0 and not brawl(co).finished.is_empty(),
		"co-op: player two finishes a man, no slow motion with two players"
	)


# ------------------------------------------------------------------ hazards


static func _hazards(main, check: Callable) -> void:
	for kind: String in ["saw", "chipper", "crusher", "zapper", "fence", "barrel", "well", "guard"]:
		var g := game(main)
		var at := lane(g, 8)
		stand(g, at)
		var b := brawl(g)
		b.spots()
		b._spots = [[kind, at.x + 3.6, at.y]]
		var e := hand(g, "billy", at.x + 1.2, at.y)
		press_use(g)
		ticks(g, 1.5)
		check.call(
			not e.alive and int(b.hazard_kills.get(kind, 0)) == 1,
			"%s: booted in, he dies by it" % kind
		)
		# A hand walking past it is not caught.
		var w := game(main)
		var wat := lane(w, 8)
		stand(w, wat, PI)
		var wb := brawl(w)
		wb.spots()
		wb._spots = [[kind, wat.x + 3.6, wat.y]]
		var walker := hand(w, "billy", wat.x + 3.6, wat.y + .9)
		walker.alerted = false
		ticks(w, 1.0)
		if kind == "saw":
			check.call(
				walker.alive and wb.hazard_kills.is_empty(),
				"a hand walking by a hazard is never caught"
			)
	# The water: hickston's creek.
	var h := game(main, "hickston")
	var edge := _water_edge(h)
	if edge.x < 0.0:
		check.call(false, "a creek bank found on hickston")
	else:
		stand(h, edge)
		var e := hand(h, "billy", edge.x + 1.1, edge.y)
		press_use(h)
		ticks(h, 1.5)
		check.call(
			not e.alive and int(brawl(h).hazard_kills.get("water", 0)) == 1,
			"water: booted into the creek, he drowns"
		)
	# The hogs: a man booted among them is their slop.
	var f := game(main)
	var fat := lane(f, 8)
	stand(f, fat)
	var victim := hand(f, "billy", fat.x + 1.2, fat.y)
	var hog := Enemy.new("pig", fat.x + 4.4, fat.y + .6)
	hog.dormant = false
	hog.uid = f.take_uid()
	f.enemies.append(hog)
	press_use(f)
	ticks(f, 3.0)
	check.call(
		not victim.alive and int(brawl(f).hazard_kills.get("hogs", 0)) == 1,
		"hogs: booted into the pen, the hogs finish him"
	)


## A hazard kill's bonus (pass 15): COUNTY JUSTICE!, the scrap with the bench
## live (none without it), a drop at the body (his kind's own: billy's
## shells; none with NO DROPS), the hazard_killed event, the same on two runs.
static func _bonus(main, check: Callable) -> void:
	var runs: Array = []
	for k in 2:
		var g := game(main, "hickston")
		g.bench_on = true  # a chapter with WORKBENCH on: the bench is live
		var at := lane(g, 8)
		var p := stand(g, at)
		p.armory.scrap = 0
		var heard: Array = []
		g.events.hazard_killed.connect(
			func(e: Enemy, kind: String, slot: int) -> void: heard.append([e.kind, kind, slot])
		)
		var b := brawl(g)
		b.spots()
		b._spots = [["saw", at.x + 3.6, at.y]]
		var e := hand(g, "billy", at.x + 1.2, at.y)
		var before := g.pickups.size()
		press_use(g)
		ticks(g, 1.5)
		var near := 0
		for item: Array in g.pickups.slice(before):
			if str(item[0]) == "shells" and Vector2(item[1] - e.x, item[2] - e.y).length() < 1.0:
				near += 1
		if k == 0:
			var paid: int = Brawl.BONUS_SCRAP
			check.call(
				not e.alive and p.armory.scrap == paid,
				"a saw kill pays %d scrap with the bench live (%d)" % [paid, p.armory.scrap]
			)
			check.call(near >= 1, "and drops his own drop at the body (%d shells)" % near)
			var called: bool = g.callout == Brawl.Callouts.JUSTICE
			var named: bool = g.notice.begins_with("SAWED IN HALF!")
			check.call(
				called and named, "COUNTY JUSTICE!, the saw's name and the pay (%s)" % g.notice
			)
			check.call(
				heard == [["billy", "saw", p.slot]],
				"the hazard_killed event for a RAMPAGE meter (%s)" % str(heard)
			)
		runs.append(var_to_str([g.pickups, p.armory.scrap, g.rng.state]))
	check.call(runs[0] == runs[1], "two runs of the same hazard kill pay the same")
	# The bench off: no scrap. NO DROPS: no drop.
	var h := game(main)
	h.supply_rule = 2
	var hat := lane(h, 8)
	var q := stand(h, hat)
	q.armory.scrap = 0
	brawl(h).spots()
	brawl(h)._spots = [["saw", hat.x + 3.6, hat.y]]
	var v := hand(h, "billy", hat.x + 1.2, hat.y)
	var had := h.pickups.size()
	press_use(h)
	ticks(h, 1.5)
	check.call(
		not v.alive and q.armory.scrap == 0 and h.pickups.size() == had,
		"the bench off pays no scrap; NO DROPS drops nothing"
	)


static func _water_edge(g: Game) -> Vector2:
	var w := g.world
	for y in range(2, w.height - 2):
		for x in range(3, w.width - 4):
			var dry := true
			for k in 3:
				var cx: float = x + k + .5
				if w.blocked(cx, y + .5, .45) or BayouBrains.wet_at(w, cx, y + .5):
					dry = false
			if not dry:
				continue
			var wet := true
			for k in [3, 4]:
				if (
					not BayouBrains.wet_at(w, x + k + .5, y + .5)
					or w.blocked(x + k + .5, y + .5, .3)
				):
					wet = false
			if wet and absf(w.elevation(x + .5, y + .5) - w.elevation(x + 3.5, y + .5)) < .3:
				return Vector2(x + .5, y + .5)
	return Vector2(-1, -1)


# ------------------------------------------------------------------- bosses


static func _bosses(main, check: Callable) -> void:
	var g := game(main)
	var at := lane(g, 8)
	stand(g, at)
	var boss := hand(g, "foreman", at.x + 1.4, at.y)
	boss.hp = boss.max_hp * .2
	var hp := boss.hp
	press_use(g)
	ticks(g, .6)
	var b := brawl(g)
	check.call(
		b.finished.is_empty() and boss.alive and b.kicks == 1,
		"a low boss gets the boot, never a finisher"
	)
	var h := game(main)
	var hat := lane(h, 8)
	stand(h, hat)
	var hb := brawl(h)
	hb.spots()
	hb._spots = [["saw", hat.x + 2.2, hat.y]]
	var big := hand(h, "foreman", hat.x + 1.4, hat.y)
	var full := big.hp
	press_use(h)
	ticks(h, 1.2)
	check.call(
		(
			big.alive
			and full - big.hp <= big.max_hp * Brawl.BOSS_SHARE + 30.0
			and full - big.hp > 10.0
		),
		(
			"a boss in a saw takes his share (%.0f of %.0f), never killed outright"
			% [full - big.hp, full]
		)
	)


# --------------------------------------------------------------------- door


static func _door(main, check: Callable) -> void:
	var g := game(main, "hickston")
	var b := brawl(g)
	var done := false
	for door: LevelData.Door in g.world.doors:
		if door.opened or door.key != "" or door.secret or door.blast_only:
			continue
		var c := door.center()
		for side in [-1.0, 1.0]:
			var off := Vector2(side, 0.0) if not door.vertical else Vector2(0.0, side)
			off = Vector2(off.y, off.x) if door.vertical else Vector2(0.0, side)
			var at := c + off * 1.1
			if g.world.blocked(at.x, at.y, .3):
				continue
			var p := stand(g, at, atan2(-off.y, -off.x))
			p.floor_z = g.world.elevation(at.x, at.y)
			p.vx = -off.x * 3.0
			p.vy = -off.y * 3.0
			if b._door_ahead(p) < 0:
				continue
			var behind := c - off * 1.0
			var e: Enemy = null
			if not g.world.blocked(behind.x, behind.y, .3):
				e = hand(g, "billy", behind.x, behind.y)
			var c2 := Game.Controls.new()
			c2.use = true
			c2.forward = 1.0
			g.tick(STEP, c2)
			ticks(g, .4)
			check.call(
				door.opened and door.progress >= 1.0 and b.doors == 1,
				"a running USE kicks a shut door in, open at once"
			)
			if e != null:
				check.call(
					Vector2(e.x, e.y).distance_to(behind) > .5,
					"and the man behind it is thrown back"
				)
			done = true
			break
		if done:
			break
	if not done:
		check.call(false, "a plain door on hickston to kick in")


# -------------------------------------------------------------------- smash


## A thing held broken over a man's head: a breakable one breaks, a board
## drops; he reels, open to a finisher.
static func _smash(main, check: Callable) -> void:
	for want_piece in [true, false]:
		var g := game(main, "hickston")
		var carry = g.features["carry"]
		var pick := -1
		for i in carry.things.size():
			var t = carry.things[i]
			if carry.takeable(t) and (t.piece >= 0) == want_piece:
				pick = i
				break
		if pick < 0:
			check.call(false, "a thing to take up on hickston")
			continue
		var at := lane(g, 5)
		var p := stand(g, at)
		carry._take(pick, p)
		ticks(g, .4)
		var e := hand(g, "billy", at.x + 1.0, at.y)
		var hp := e.hp
		var fire := Game.Controls.new()
		fire.fire = true
		g.tick(STEP, fire)
		ticks(g, .1)
		var t = carry.things[pick]
		var done: bool = t.state == 3 if want_piece else t.state != 1
		check.call(
			e.hp < hp and brawl(g).finishable(e) and done and carry.held_by(p) < 0,
			(
				"%s broken over a man's head: hurt %.0f, reeling%s"
				% [t.image, hp - e.hp, ", it breaks" if want_piece else ", it drops"]
			)
		)


# ----------------------------------------------------------------- net sync


static func _sync(main, check: Callable) -> void:
	var ends: Array = []
	for k in 2:
		var g := game(main)
		var at := lane(g, 9)
		stand(g, at)
		var a := hand(g, "billy", at.x + 1.2, at.y)
		var o := hand(g, "coot", at.x + 2.6, at.y + .2)
		press_use(g)
		ticks(g, .2)
		if k == 0:
			var data := GameSnapshot.capture(g)
			var g2 := game(main)
			var same := GameSnapshot.apply(g2, data)
			for i in 50:
				g.tick(STEP, Game.Controls.new())
				g2.tick(STEP, Game.Controls.new())
				var x: String = var_to_str(GameSnapshot.capture(g)["features"]["brawl"])
				var y: String = var_to_str(GameSnapshot.capture(g2)["features"]["brawl"])
				if x != y or absf(g.enemies[0].x - g2.enemies[0].x) > 1e-6:
					same = false
					break
			check.call(same, "a snapshot mid-slide plays on the same on a copy, tick for tick")
		else:
			ticks(g, .83)
		ends.append(var_to_str([a.x, a.y, a.hp, o.x, o.y, o.hp]))
	check.call(ends[0] == ends[1], "two runs of the same boot end the same")


# -------------------------------------------------------------------- looks


## The boot's cels are packed and placed where the art tool put them; the
## boot shows for a kick, the gun ducks, and the view jolts as it lands.
static func _looks(main, check: Callable) -> void:
	const Looks := preload("res://src/features/brawl_looks.gd")
	var path := ProjectSettings.globalize_path("res://").path_join("../assets/art/boot_views.json")
	var written = JSON.parse_string(FileAccess.get_file_as_string(path.simplify_path()))
	var same: bool = written is Dictionary and written.size() == Looks.PLACES.size()
	if same:
		for pose: String in Looks.PLACES:
			var a: Array = Looks.PLACES[pose]
			var b: Array = written.get(pose, [-1, -1])
			same = same and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])
	check.call(same, "the boot cels sit where build_boot_views.gd put them (brawl_looks.gd PLACES)")
	var g := game(main)
	var art_ok := true
	for pose: String in Looks.PLACES:
		art_ok = art_ok and g.art.has_art("fx_boot_" + pose)
	check.call(art_ok, "the boot cels are packed")
	var at := lane(g, 6)
	stand(g, at)
	hand(g, "billy", at.x + 1.2, at.y)
	var looks = g.features["brawl_looks"]
	press_use(g)
	var seen: bool = not looks.boot().is_empty()
	var ducked := g.player.weapon_lag.y > 5.0
	var jolted := false
	for i in 12:
		g.tick(STEP, Game.Controls.new())
		jolted = jolted or g.view_kick.length() > .001
	check.call(seen and ducked and jolted, "a kick shows the boot, the gun ducks, the view jolts")
