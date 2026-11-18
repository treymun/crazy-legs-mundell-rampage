## The blast and vehicle wreck looks (features/gun_fx.gd, src/blast_looks.gd,
## src/vehicle_wreck_looks.gd; destruction pass 11). tools/check_all.gd runs
## it, quick too; this also runs on its own:
##
##   godot --headless --path godot --script res://tools/blast_check.gd
##
## Every look in blast_looks.cfg goes off in Hickston's yard and throws what
## it should (its fireball's fire, lobes, a column, scraps of its kind, dirt
## puffs, a crater); what blew picks the look (a propane tank, a hazard drum,
## a vehicle) over the blast's kind; two blasts of one kind never look alike;
## a blast in water throws a column of water and leaves no crater, one on the
## hay loft no crater, one against a wall throws its fire off it; six in a
## chain each have their whole fireball and stay under the bits' cap. The
## stock car wrecked by a stick at its side throws its own parts (cut from its
## model) away from the blast, leaves its hulk without them and burns; badly
## hurt it smokes from the engine. And play stays exact: the same blasts with
## the looks' dice seeded otherwise play to the same state.
extends SceneTree

const DT := 1.0 / 60.0
const BlastLooksScript := preload("res://src/blast_looks.gd")
const BreakablesFeature := preload("res://src/features/breakables.gd")

var failures: Array = []
var passes := 0
var main: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	print("LOOKS")
	_looks()
	print("WHAT BLEW")
	_what_blew()
	print("NO TWO ALIKE")
	_alike()
	print("WHERE")
	_where()
	print("CHAIN")
	_chain()
	print("COCKTAIL")
	_cocktail()
	print("WRECK")
	_wreck()
	print("PLAY EXACT")
	_exact()
	print(
		(
			"\n%d passed, %d failed in %.1f s"
			% [passes, failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("BLAST CHECK FAILED" if not failures.is_empty() else "BLAST CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
	else:
		print("  FAIL ", text)
		failures.append(text)


func _game(id: String) -> Game:
	var game: Game = main.make_game(id)
	game.configure({})
	game.cheats.god = true
	for e: Enemy in game.enemies:
		e.dormant = true
	return game


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(DT, Game.Controls.new())


## A clear spot of Hickston's yard: open ground three cells round, no roof.
func _yard(g: Game) -> Vector2:
	var w := g.world
	for cy in range(4, w.height - 4, 2):
		for cx in range(4, w.width - 4, 2):
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var i := (cy + dy) * w.width + cx + dx
					if w.solid[i] >= 0 or w.roof[i] > 0.0:
						ok = false
					elif absf(w.ground[i] - w.ground[cy * w.width + cx]) > .02:
						ok = false
			if ok and not _wet(g, cx + .5, cy + .5):
				return Vector2(cx + .5, cy + .5)
	return Vector2.INF


func _wet(g: Game, x: float, y: float) -> bool:
	var fx: GameFeature = g.features["gun_fx"]
	var looks: BlastLooks = fx.get("blast_looks")
	var where := looks.place(x, y, g.world.elevation(x, y) + .2)
	return where["water"]


func _boom(g: Game, at: Vector2, kind: String, z := NAN) -> void:
	var fz := g.world.elevation(at.x, at.y) + .15 if is_nan(z) else z
	var shot := Game.Shot.new(at.x, at.y, fz, 0.0, 0.0, 0.0, kind, 0.0, false, 0)
	shot.owner = -1
	g.explode(shot)


## What the layer holds now: main fireballs, lobes, bits by kind/look, craters.
func _census(g: Game) -> Dictionary:
	var fx: GameFeature = g.features["gun_fx"]
	var booms: Array = fx.get("booms")
	var bits: Array = fx.get("bits")
	var looks: BlastLooks = fx.get("blast_looks")
	var out := {
		"main": 0,
		"lobes": 0,
		"fire": "",
		"shape": -1,
		"bits": bits.size(),
		"craters": looks.craters.size()
	}
	for boom: Array in booms:
		var side: bool = boom[5]
		if side:
			out["lobes"] = int(out["lobes"]) + 1
		else:
			out["main"] = int(out["main"]) + 1
			out["fire"] = str(boom[6])
			out["shape"] = int(boom[7])
	for bit: FxBit in bits:
		var key := bit.kind + ":" + bit.look
		out[key] = int(out.get(key, 0)) + 1
	var geysers: Array = fx.get("geysers")
	out["geysers"] = geysers.size()
	return out


func _looks() -> void:
	var cfg := Tuning.file(BlastLooksScript.PATH)
	for kind: String in ["tnt", "keg", "fuel", "gas_can", "cow", "bottle_rocket"]:
		var g := _game("hickston")
		var at := _yard(g)
		if at == Vector2.INF:
			_check(false, "hickston has a clear yard")
			return
		_boom(g, at, kind)
		_ticks(g, 2)
		var c := _census(g)
		var name := str(cfg.get_value("kinds", kind, "blast"))
		var fire := str(cfg.get_value("look." + name, "fire", "d"))
		_check(int(c["main"]) == 1, "%s: one fireball (%d)" % [kind, int(c["main"])])
		_check(str(c["fire"]) == fire, "%s: its fire is %s (%s)" % [kind, fire, str(c["fire"])])
		_check(int(c["lobes"]) >= 1, "%s: lobes beside it" % kind)
		_check(int(c["craters"]) == 1, "%s: a crater in the yard" % kind)
		_check(int(c.get("dust:dirtpuff", 0)) >= 1, "%s: dirt puffs rolling out" % kind)
		var smoke := str(cfg.get_value("look." + name, "smoke", "soot"))
		var column := int(
			c.get("soot:" + ("billowpowder" if smoke == "powder" else "billowhot"), 0)
		)
		_check(column >= 1, "%s: a column of %s" % [kind, smoke])
		var scrap := str(cfg.get_value("look." + name, "scrap", ""))
		var scraps: float = cfg.get_value("look." + name, "scraps", 0)
		if scraps >= 3.0:
			_check(
				int(c.get("chunk:" + scrap, 0)) >= 1,
				"%s: scraps of %s" % [kind, scrap if scrap != "" else "char"]
			)
		print("  %s: %s" % [kind, str(c)])


## A propane tank and a hazard drum both set off a "fuel" blast; each has its
## own look (propane's yellow-white ball, the drum's fuel fire and tin).
func _what_blew() -> void:
	var g := _game("hickston")
	var fx: GameFeature = g.features["gun_fx"]
	var looks: BlastLooks = fx.get("blast_looks")
	var pieces: BreakablesFeature = g.features["breakables"]
	var seen := {}
	for i in pieces.pieces.size():
		var p: BreakablesFeature.Piece = pieces.pieces[i]
		if seen.has(p.image) or not p.image in ["town_propane_tank", "town_warning_barrel"]:
			continue
		seen[p.image] = true
		pieces.strike(i, 9999.0, 1.0, 0.0)
		var look := looks.look_of("fuel", p.x, p.y)
		var want := "propane" if p.image == "town_propane_tank" else "drum"
		_check(
			str(look["name"]) == want, "%s goes up as %s (%s)" % [p.image, want, str(look["name"])]
		)
	_check(seen.size() == 2, "hickston has a propane tank and a hazard drum")


func _alike() -> void:
	var g := _game("hickston")
	var at := _yard(g)
	var marks: Array = []
	for k in 4:
		var fx: GameFeature = g.features["gun_fx"]
		var booms: Array = fx.get("booms")
		var bits: Array = fx.get("bits")
		booms.clear()
		bits.clear()
		_boom(g, at + Vector2(k % 2, k / 2) * .5, "tnt")
		var c := _census(g)
		var looks: BlastLooks = fx.get("blast_looks")
		var crater: Array = looks.craters[looks.craters.size() - 1]
		var sign := (
			"%d/%d/%d/%d/%.2f/%.2f"
			% [
				int(c["shape"]),
				int(c["lobes"]),
				int(c["bits"]),
				int(c.get("chunk:", 0)),
				float(crater[3]),
				float(crater[4])
			]
		)
		marks.append(sign)
		_ticks(g, 120)
	var unique := {}
	for m: String in marks:
		unique[m] = true
	_check(unique.size() == marks.size(), "four sticks in a row look four ways %s" % str(marks))


func _where() -> void:
	# In water: a column of water, no crater.
	var g := _game("bayou")
	var w := g.world
	var found := false
	for cy in range(4, w.height - 4):
		for cx in range(4, w.width - 4):
			if found or not _wet(g, cx + .5, cy + .5):
				continue
			found = true
			_boom(g, Vector2(cx + .5, cy + .5), "tnt")
			var c := _census(g)
			_check(int(c["geysers"]) == 1, "a blast in water throws up a column of water")
			_check(int(c["craters"]) == 0, "a blast in water leaves no crater")
	_check(found, "the bayou has water")
	# On the hay loft: no crater in the planks.
	g = _game("hickston")
	for s: LevelGeometry.Slab in g.world.geo.slabs:
		if s.id != "hay_loft":
			continue
		var mark := Vector2(s.x0 + 2.4, s.y0 + 3.4)
		_boom(g, mark, "tnt", s.top + .15)
		var c := _census(g)
		_check(int(c["craters"]) == 0, "a blast on the hay loft leaves no crater")
		_check(int(c.get("splinter:", 0)) >= 1, "a blast on the hay loft throws splinters")
	# Against a wall: the fire is thrown off it.
	g = _game("hickston")
	w = g.world
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			if w.solid[cy * w.width + cx] >= 0 or w.solid[cy * w.width + cx + 1] < 0:
				continue
			var at := Vector2(cx + .8, cy + .5)
			var fx: GameFeature = g.features["gun_fx"]
			var looks: BlastLooks = fx.get("blast_looks")
			var where := looks.place(at.x, at.y, w.elevation(at.x, at.y) + .2)
			var off: Vector2 = where["wall"]
			_check(off.x < 0.0, "a blast by a wall to its east is thrown west (%s)" % str(off))
			return


func _chain() -> void:
	var g := _game("hickston")
	var at := _yard(g)
	var fx: GameFeature = g.features["gun_fx"]
	var looks: BlastLooks = fx.get("blast_looks")
	var most := 0
	var started := Time.get_ticks_usec()
	for k in 6:
		_boom(g, at + Vector2((k % 3) - 1, k / 3) * 1.1, "fuel" if k % 2 else "tnt")
		_ticks(g, 9)
		var bits: Array = fx.get("bits")
		most = maxi(most, bits.size())
	var spent := (Time.get_ticks_usec() - started) / 1000.0
	var c := _census(g)
	_check(
		int(c["main"]) >= 4, "a chain's booms each keep their fireball (%d live)" % int(c["main"])
	)
	_check(
		most <= looks.most_bits,
		"a chain stays under the bits' cap (%d of %d)" % [most, looks.most_bits]
	)
	print("  six blasts and 54 ticks: %.1f ms, most bits %d" % [spent, most])


func _wreck() -> void:
	var g := _game("speedway")
	var rides: GameFeature = g.features["vehicles"]
	var list: Array = rides.get("rides")
	if list.is_empty():
		_check(false, "the speedway has its stock car")
		return
	var v: VehicleDrive.Ride = list[0]
	var s := VehicleDrive.spec("car")
	var wreck: GameFeature = g.features["wreckage"]
	var before: Array = wreck.get("wrecks")
	var had := before.size()
	# Its parts are cut on a worker as the level starts: done before a wreck.
	var waited := 0
	while not VehicleWreckLooks._cells.has("car") and waited < 300:
		_ticks(g, 1)
		OS.delay_msec(5)
		waited += 1
	_check(VehicleWreckLooks._cells.has("car"), "the car's parts are cut on a worker at the start")
	print("  the car's cut: %.1f ms on a worker" % VehicleWreckLooks.cut_ms)
	v.hp = 40.0
	var side := Vector2.from_angle(v.h + PI / 2.0)
	var blast_at := Vector2(v.x, v.y) + side * (s.width * .5 + .5)
	var t0 := Time.get_ticks_usec()
	_boom(g, blast_at, "tnt")
	_ticks(g, 1)
	print("  the wreck's blast and its tick: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_check(v.wreck >= 0.0, "the stick wrecks the car")
	var fx: GameFeature = g.features["gun_fx"]
	_ticks(g, 1)
	var parts := WreckCuts.parts(g.art, "m:stock_car|vw")
	_check(
		parts.size() == 8, "the car's model is cut into its eight loose parts (%d)" % parts.size()
	)
	var after: Array = wreck.get("wrecks")
	var thrown := after.size() - had
	_check(thrown >= 1, "parts come off the car (%d)" % thrown)
	var away := 0
	for k in range(had, after.size()):
		var piece: Object = after[k]
		var body: WreckPhysics.Body = piece.get("body")
		if Vector2(body.v.x, body.v.y).dot(-side) > 0.0:
			away += 1
	_check(away * 2 >= thrown, "they fly away from the blast (%d of %d)" % [away, thrown])
	var hulk: Variant = null
	for _k in 200:
		# The hulk is built on a worker: its model shows until it is done.
		hulk = fx.call("hulk", 0)
		if hulk != null:
			break
		OS.delay_msec(5)
		_ticks(g, 1)
	_check(hulk != null, "a hulk stands where the car was")
	if hulk != null:
		var spr: View.Sprite = hulk
		_check(spr.solid.contains("|vh"), "the hulk is the car's own cut model (%s)" % spr.solid)
		_ticks(g, 300)
		spr = fx.call("hulk", 0)
		_check(spr.hurt > .7, "the hulk chars as it burns (%.2f)" % spr.hurt)
	var c := _census(g)
	_check(
		int(c.get("soot:billowhot", 0)) + int(c.get("soot:billow", 0)) >= 3,
		"the wreck burns under a column of smoke"
	)
	# Badly hurt: smoke off the engine.
	g = _game("speedway")
	list = g.features["vehicles"].get("rides")
	v = list[0]
	v.hp = s.hp * .2
	_ticks(g, 60)
	c = _census(g)
	_check(int(c.get("soot:soot", 0)) >= 2, "a badly hurt car smokes from its engine")


## A shine cocktail bursting (the 5v5 throwable): fuel fire, glass, burning
## drops, no crater.
func _cocktail() -> void:
	var g := _game("hickston")
	var at := _yard(g)
	var fx: GameFeature = g.features["gun_fx"]
	fx.call("firebomb", at.x, at.y, g.world.elevation(at.x, at.y) + .1)
	var c := _census(g)
	_check(str(c["fire"]) == "f" and int(c["main"]) == 1, "a cocktail bursts in a fuel fireball")
	_check(int(c.get("glint:", 0)) >= 3, "a cocktail's glass flies")
	_check(int(c.get("burning:", 0)) >= 3, "a cocktail splashes burning shine")
	_check(int(c["craters"]) == 0, "a cocktail leaves no crater")


## Play does not hear the looks: the same blasts and a wreck with the looks'
## dice seeded otherwise play to the same hash.
func _exact() -> void:
	var hashes: Array = []
	for seed in [1997, 4242]:
		var g := _game("hickston")
		var fx: GameFeature = g.features["gun_fx"]
		var dice: RandomNumberGenerator = fx.get("dice")
		dice.seed = seed
		var at := _yard(g)
		for k in 4:
			_boom(g, at + Vector2(k, 0) * .7, ["tnt", "keg", "fuel", "cow"][k])
			_ticks(g, 20)
		_ticks(g, 120)
		hashes.append(Replay.state_hash(g))
	_check(hashes[0] == hashes[1], "play is the same whatever the looks' dice (%s)" % str(hashes))
