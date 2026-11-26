## The pass 15 LOOKS (effects.cfg [rim], [pickup_glint], [hurt_looks],
## [enemy_muzzle], [gun_smoke], [casings]; all looks only):
##
## - an awake hostile hand wears the warm rim, stronger far off; asleep,
##   held, dead or a stand-in none; the listed critters a cool one; a rim
##   coming up in sight fades in, one first seen awake is whole; it is its
##   own pass round the outline (actor_rim.gdshader), off under a hit's wash
##   and the wind-up's amber, only with LIGHTS AND GLOW;
## - ammo, food and scrap glint (both frames of the star, a short share of
##   the time), keys, guns and task items do not; EASY ON THE EYES makes the
##   glints rarer and stills the bob;
## - a blow draws the vignette and it fades; low health drains the colour and
##   holds the vignette; under heart_from the heart thumps, quicker lower;
##   SCREEN FLASHES OFF none of it; PHOTO MODE's eye none;
## - a gunman's shot lights the yard a moment (a scattergun brighter), a
##   melee hand's swing does not, and the lights stay within MAX_LIGHTS;
## - each gun's shells are its effects.cfg picture, the newer guns' their
##   own, every picture packed;
## - smoke curls off the muzzle after a burst or a big gun's shot, not after
##   a lone pistol round, and goes when he fires again or puts the gun down;
## - none of it touches game.rng.
##
##   godot --headless --path godot --script res://tools/looks_check.gd
##
## Prints LOOKS CHECK OK (check_all runs it).
extends SceneTree

const STEP := 1.0 / 60.0

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	_tuning()
	_rims()
	_shader()
	_glints()
	_hurt()
	_muzzles()
	_casings()
	_smoke()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("LOOKS CHECK OK")
	else:
		print("LOOKS CHECK FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


func _made(id := "hickston") -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": 0})
	g.lessons = false
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	_ticks(g, 2)
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


func _hand(g: Game, kind: String, ahead := 3.0, side := 0.0) -> Enemy:
	var p := g.player
	var e := Enemy.new(kind, p.x + ahead, p.y + side, PI)
	e.uid = g.take_uid()
	e.dormant = false
	e.alerted = true
	e.cooldown = 99.0
	e.floor_z = g.world.elevation(e.x, e.y)
	g.enemies.append(e)
	return e


func _tuning() -> void:
	print("\nTHE NUMBERS")
	for section: String in [
		"rim", "pickup_glint", "hurt_looks", "enemy_muzzle", "gun_smoke", "casings"
	]:
		check(Effects.SECTIONS.has(section), "effects.cfg has [%s]" % section)
	for source: String in ["enemy_muzzle", "enemy_muzzle_scatter"]:
		check(Effects.LIGHTS.has(source), "effects.cfg has [light.%s]" % source)
	check(Effects.MAX_LIGHTS == 16, "the shader still takes MAX_LIGHTS 16 lights")


func _rims() -> void:
	print("\nTHE RIM")
	var g := _made()
	var awake := _hand(g, "billy")
	var rim := ActorRim.wanted(awake)
	var near: float = Effects.num("rim", "near", 0.0)
	check(rim.a > 0.0 and absf(rim.a - near) < .001, "an awake hand wears the rim (%.2f)" % rim.a)
	check(rim.r > rim.g and rim.g > rim.b, "the hand's rim is warm (%s)" % rim)
	var reach := ActorRim.reach(awake)
	check(reach.x > rim.a and reach.z > reach.y, "it is stronger far off (%.2f)" % reach.x)
	awake.alerted = false
	check(ActorRim.wanted(awake).a == 0.0, "asleep: none")
	awake.alerted = true
	awake.dormant = true
	check(ActorRim.wanted(awake).a == 0.0, "held (dormant): none")
	awake.dormant = false
	awake.hp = 0.0
	check(ActorRim.wanted(awake).a == 0.0, "dead: none")
	var cow := _hand(g, "cow")
	cow.alerted = false
	var cool := ActorRim.wanted(cow)
	check(cool.a > 0.0 and cool.b > cool.r, "a cow wears a cool rim (%s)" % cool)
	check(ActorRim.reach(cow).x == cool.a, "an animal's rim does not grow far off")
	var stand_in := ModeBodies.stand_in(g, "looks-check", "coot")
	check(ActorRim.wanted(stand_in).a == 0.0, "a stand-in (a player's body) wears none")
	# The fade, on a model: first seen awake, whole; waking in sight, from 0.
	var view := ActorView.new()
	var hand := _hand(g, "coot")
	view.shown_at = 10.0
	check(absf(ActorRim.of(view, hand).a - near) < .001, "a hand first seen awake has it whole")
	var fade: float = Effects.num("rim", "fade", .3)
	hand.alerted = false
	view.shown_at = 11.0
	ActorRim.of(view, hand)
	hand.alerted = true
	view.shown_at = 12.0
	var woke := ActorRim.of(view, hand).a
	view.shown_at = 12.0 + fade * .5
	var half := ActorRim.of(view, hand).a
	view.shown_at = 12.0 + fade + .01
	var whole := ActorRim.of(view, hand).a
	check(
		woke == 0.0 and half > 0.0 and half < near and absf(whole - near) < .001,
		"waking in sight it fades in (%.2f, %.2f, %.2f)" % [woke, half, whole]
	)
	view.free()


func _shader() -> void:
	print("\nTHE SHADERS")
	var shell := FileAccess.get_file_as_string("res://src/view3d/actor_rim.gdshader")
	check(
		shell.contains("cull_front") and shell.contains("uniform vec4 rim"),
		"the rim is its own pass: the parts' back faces swollen out (actor_rim.gdshader)"
	)
	check(shell.contains("!effects_on"), "with LIGHTS AND GLOW only")
	var actor := FileAccess.get_file_as_string("res://src/view3d/actor.gdshader")
	check(not actor.contains("own_rim"), "the body's own shader is as it was (no specks in it)")
	var rim := Color(1, .5, .2, .45)
	check(ActorRim.quieted(rim, .2, 0.0).a == 0.0, "a hit's wash takes it off")
	var half := ActorRim.quieted(rim, 0.0, .19).a
	check(
		half > 0.0 and half < rim.a and ActorRim.quieted(rim, 0.0, .38).a == 0.0,
		"it gives way as the wind-up's amber rises (%.2f at half)" % half
	)
	# Hung on a part as its material's next pass, and taken off.
	var part := MeshInstance3D.new()
	part.mesh = BoxMesh.new()
	var own := ShaderMaterial.new()
	own.shader = load("res://src/view3d/actor.gdshader")
	part.material_override = own
	ActorRim.dress(part, rim, Vector4(1, 3, 15, .6))
	var hung := own.next_pass as ShaderMaterial
	check(hung != null and hung.shader == ActorRim.SHADER, "a part with a rim wears the pass")
	check(ActorRim.normal_out(part.mesh) != 0.0, "its normals' way is worked out per mesh")
	ActorRim.dress(part, Color(0, 0, 0, 0), Vector4(1, 3, 15, .6))
	check(own.next_pass == null, "and none without one")
	part.free()
	var display := FileAccess.get_file_as_string("res://src/display.gdshader")
	check(
		display.contains("uniform float pain") and display.contains("uniform float drain"),
		"the display shader takes pain and drain"
	)
	var was := Effects.enabled
	Effects.enabled = false
	var g := _made()
	check(ActorRim.wanted(_hand(g, "billy")).a == 0.0, "LIGHTS AND GLOW off: no rim")
	Effects.enabled = was
	# ENEMY RIM: SOFT by default, reaching the game; OFF none; SOFT a dull edge
	# of a pixel or so, BOLD brighter and a little wider; neither a fill.
	var options := SessionStore.defaults().duplicate()
	check(int(options.get("enemy_rim", -1)) == ActorRim.SOFT, "ENEMY RIM is SOFT by default")
	options["enemy_rim"] = ActorRim.OFF
	g.configure(options)
	check(ActorRim.mode == ActorRim.OFF, "the setting reaches the view")
	check(ActorRim.wanted(_hand(g, "billy")).a == 0.0, "ENEMY RIM OFF: no rim")
	options["enemy_rim"] = ActorRim.SOFT
	g.configure(options)
	var soft := ActorRim.look_of(ActorRim.SOFT)
	var bold := ActorRim.look_of(ActorRim.BOLD)
	check(
		soft.x <= .601 and soft.z < 1.0 and soft.y < soft.z,
		"SOFT: at most a pixel out at 320 wide, dull (%s)" % soft
	)
	check(bold.x > soft.x and bold.z > soft.z, "BOLD: wider and brighter (%s)" % bold)
	check(soft.w > 0.0 and bold.w > 0.0, "both thin out far off (a far figure keeps its pixels)")
	check(shell.contains("DEPTH ="), "the edge is tested behind the body (no lines over it)")


func _glints() -> void:
	print("\nTHE GLINT")
	for item: String in ["shells", "rinds", "beer", "scrap_bolts", "rifle_ammo"]:
		check(PickupLooks.glints(item), "%s glints" % item)
	for item: String in ["key_brass", "pa_patch", "revolver", "hunter"]:
		check(not PickupLooks.glints(item), "%s does not (its own shine)" % item)
	var every: float = Effects.num("pickup_glint", "every", 2.6)
	var shares: Array[float] = []
	for motion in 3:
		var seen := {}
		var shown := 0
		var n := 0
		var t := 0.0
		while t < every * 6.0:
			var f := PickupLooks.frame_at(12.3, 40.7, t, motion)
			if f >= 0:
				shown += 1
				seen[f] = true
			n += 1
			t += 1.0 / 240.0
		shares.append(float(shown) / n)
		check(seen.has(0) and seen.has(1), "EASY ON THE EYES %d: both frames show" % motion)
	check(
		shares[0] > .02 and shares[0] < .2, "it glints a short share of the time (%.3f)" % shares[0]
	)
	check(shares[1] < shares[0] and shares[2] < shares[1], "EASY ON THE EYES makes it rarer")
	check(
		absf(_first_glint(12.3, 40.7, every) - _first_glint(30.1, 9.2, every)) > .05,
		"each pickup its own beat"
	)
	check(PickupLooks.bob(0) > .035, "the bob is a little bigger (%.3f)" % PickupLooks.bob(0))
	check(PickupLooks.bob(2) == 0.0, "STILL: no bob")
	var g := _made()
	var p := g.player
	var before: Variant = g.rng.state
	var stars := 0
	var keys := 0
	var t := 0.0
	while t < every * 2.0:
		g.clock = t
		var out: Array = []
		PickupLooks.glint(g, ["shells", p.x + 2.0, p.y, 1], p.x + 2.0, p.y, .3, p, out)
		for s: View.Sprite in out:
			stars += 1 if s.image.begins_with("fx_twinkle_") and s.glow else 0
		out.clear()
		PickupLooks.glint(g, ["key_brass", p.x + 2.0, p.y, 2], p.x + 2.0, p.y, .3, p, out)
		keys += out.size()
		t += STEP
	check(stars > 0, "the shells glint in the list the view draws (%d frames)" % stars)
	check(keys == 0, "the key does not")
	for name: String in PickupLooks.STARS:
		check(g.art.has_art(name), "%s is packed" % name)
	check(g.rng.state == before, "the glint never draws on game.rng")


## When a pickup at x, y first glints, from clock 0.
func _first_glint(x: float, y: float, every: float) -> float:
	var t := 0.0
	while t < every * 3.0:
		if PickupLooks.frame_at(x, y, t, 0) >= 0:
			return t
		t += 1.0 / 240.0
	return -1.0


func _hurt() -> void:
	print("\nHURT")
	var g := _made()
	var looks: HurtLooks = g.features.get("hurt_looks")
	check(looks != null, "hurt_looks runs")
	check(GameSnapshot.LOOKS_FEATURES.has("hurt_looks"), "it is a LOOKS feature")
	if looks == null:
		return
	var p := g.player
	var before: Variant = g.rng.state
	check(looks.vignette() == 0.0 and looks.drained() == 0.0, "at full health: nothing")
	g.cheats.god = false
	g.damage(15.0, [p.x + 3.0, p.y], "BUCKSHOT")
	var hit := looks.vignette()
	var floor_k: float = Effects.num("hurt_looks", "pain_floor", .3)
	check(hit >= floor_k, "a blow draws the vignette (%.2f)" % hit)
	var fade: float = Effects.num("hurt_looks", "pain_fade", 1.1)
	g.clock += fade * .5
	var later := looks.vignette()
	g.clock += fade
	check(later < hit and later > 0.0, "it fades (%.2f)" % later)
	p.health = 80
	check(looks.vignette() == 0.0, "and is gone")
	p.health = 60
	check(looks.drained() == 0.0, "60 health: no drain")
	p.health = 22
	var some := looks.drained()
	p.health = 4
	var most: float = Effects.num("hurt_looks", "drain_most", .72)
	check(
		some > 0.0 and absf(looks.drained() - most) < .001,
		"low health drains the colour (%.2f at 22, %.2f at 4)" % [some, looks.drained()]
	)
	check(looks.vignette() > 0.0, "and holds the vignette (%.2f)" % looks.vignette())
	# The heart: counted as the view draws.
	var thumps := [0, 0]
	for k in 2:
		p.health = 18 if k == 0 else 3
		looks.beat_clock = -1.0
		var last := looks.thump_at
		for i in 600:
			g.clock += STEP
			looks.draw_view(null)
			if looks.thump_at != last:
				thumps[k] += 1
				last = looks.thump_at
	check(thumps[0] >= 6 and thumps[1] > thumps[0], "the heart thumps, quicker lower %s" % [thumps])
	p.health = 40
	var last_thump := looks.thump_at
	for i in 300:
		g.clock += STEP
		looks.draw_view(null)
	check(looks.thump_at == last_thump, "not at 40 health")
	# The display shader's numbers.
	var material := ShaderMaterial.new()
	material.shader = load("res://src/display.gdshader")
	p.health = 10
	HurtLooks.uniforms(material, g, true)
	var pain: float = material.get_shader_parameter("pain")
	var drain: float = material.get_shader_parameter("drain")
	check(pain > 0.0 and drain > 0.0, "the shader gets them (%.2f, %.2f)" % [pain, drain])
	HurtLooks.uniforms(material, g, false)
	pain = material.get_shader_parameter("pain")
	check(pain == 0.0, "none in the menus")
	g.flash_scale = 0.0
	HurtLooks.uniforms(material, g, true)
	pain = material.get_shader_parameter("pain")
	drain = material.get_shader_parameter("drain")
	check(pain == 0.0 and drain == 0.0, "SCREEN FLASHES OFF: none")
	g.flash_scale = 1.0
	g.eye_override = {"x": 0.0}
	HurtLooks.uniforms(material, g, true)
	pain = material.get_shader_parameter("pain")
	check(pain == 0.0, "PHOTO MODE's eye: none")
	g.eye_override = {}
	check(g.rng.state == before, "the hurt looks never draw on game.rng")


func _muzzles() -> void:
	print("\nTHE HANDS' SHOTS")
	var g := _made()
	var fx: GameFeature = g.features.get("gun_fx")
	var muzzles: MuzzleLooks = fx.get("muzzles")
	var before: Variant = g.rng.state
	var billy := _hand(g, "billy", 5.0)
	var coot := _hand(g, "coot", 6.0, 2.0)
	var swinger := _hand(g, "millhand", 4.0, -2.0)
	muzzles.tick_hands()
	check(muzzles.flashes.is_empty(), "nothing before a shot")
	for e: Enemy in [billy, coot, swinger]:
		e.recovery = e.recovery_time()
	muzzles.tick_hands()
	check(muzzles.flashes.size() == 2, "two gunmen fire: two flashes (%d)" % muzzles.flashes.size())
	var out: Array = []
	muzzles.lights(out)
	check(out.size() == 2, "each lights the yard")
	var spec_s: Dictionary = Effects.LIGHTS["enemy_muzzle_scatter"]
	var spec_p: Dictionary = Effects.LIGHTS["enemy_muzzle"]
	var s_strength: float = spec_s["strength"]
	var p_strength: float = spec_p["strength"]
	check(s_strength > p_strength, "the scattergun's is the brighter")
	var lit: Array = fx.call("lights")
	check(lit.size() >= 2, "gun_fx hands them to the view")
	g.clock += .3
	muzzles.tick_hands()
	out.clear()
	muzzles.lights(out)
	check(muzzles.flashes.is_empty() and out.is_empty(), "a moment later they are out")
	# Many at once: the view still takes the nearest MAX_LIGHTS.
	for k in 24:
		var e := _hand(g, "coot", 3.0 + k * .4, -3.0 + (k % 5) * 1.5)
		e.recovery = 0.0
	muzzles.tick_hands()
	for e: Enemy in g.enemies:
		if e.alive and e.kind == "coot":
			e.recovery = e.recovery_time()
	muzzles.tick_hands()
	check(muzzles.flashes.size() > Effects.MAX_LIGHTS, "a volley of %d" % muzzles.flashes.size())
	check(
		ViewLights.effect_lights(g).size() <= Effects.MAX_LIGHTS,
		"the view still takes at most MAX_LIGHTS"
	)
	check(g.rng.state == before, "the flashes never draw on game.rng")


func _casings() -> void:
	print("\nTHE BRASS")
	var g := _made()
	var debris: GameFeature = g.features.get("debris")
	var bits: Array = debris.get("bits")
	var newer := [
		"county45", "star357", "hogleg", "riot_pump", "tommy", "grease_gun", "marksman", "hunter"
	]
	var rows: Dictionary = Effects.SECTIONS.get("casings", {})
	for name: String in newer:
		check(rows.has(name), "[casings] has %s" % name)
	for name: String in rows:
		var row: Array = rows[name]
		var gun := Weapons.NAMES.find(name)
		check(gun >= 0, "%s is a gun" % name)
		if gun < 0:
			continue
		var picture := str(row[0])
		check(g.art.has_art(picture), "%s is packed" % picture)
		bits.clear()
		if str(row[2]) == "reload":
			debris.call("own_reload", gun)
		else:
			debris.call("own_shot", gun)
		var made := 0
		for b: Variant in bits:
			made += 1 if str(b.get("picture")) == picture else 0
		var count: int = row[1]
		check(made == count, "%s throws %d of %s (%d)" % [name, count, picture, made])
		# Out ahead, where the view draws them (not at the lens).
		var p := g.player
		for b: Variant in bits:
			b.set("x", p.x + cos(p.angle) * 3.0)
			b.set("y", p.y + sin(p.angle) * 3.0)
		var sprites: Array = debris.call("sprites")
		for s: View.Sprite in sprites:
			check(s.image == picture, "%s's shell is drawn as %s (%s)" % [name, picture, s.image])
			break
	var own := {}
	for name: String in newer:
		var row: Array = rows.get(name, [""])
		own[str(row[0])] = true
	check(own.size() >= 4 and not own.has("fx_casing"), "the newer guns throw brass of their own")


func _smoke() -> void:
	print("\nSMOKE OFF THE MUZZLE")
	var g := _made()
	var fx: GameFeature = g.features.get("gun_fx")
	var muzzles: MuzzleLooks = fx.get("muzzles")
	var before: Variant = g.rng.state
	var wait: float = Effects.num("gun_smoke", "wait", .12)
	var life: float = Effects.num("gun_smoke", "life", 2.4)
	for row: Array in [["tommy", 3, true], ["tommy", 1, false], ["revolver", 1, false]]:
		var gun := Weapons.NAMES.find(str(row[0]))
		_hold(g, gun)
		muzzles.wisp_at = -1.0
		var shots: int = row[1]
		for k in shots:
			muzzles.shot(gun)
			g.clock += .1
		muzzles.tick_wisp()
		check(muzzles.wisp_at < 0.0, "%s: none while shooting" % row[0])
		g.clock += wait + .01
		muzzles.tick_wisp()
		var want: bool = row[2]
		check(
			(muzzles.wisp_at >= 0.0) == want,
			"%s, %d shot(s): %s" % [row[0], shots, "a wisp" if want else "no wisp"]
		)
	for name: String in ["shotgun", "hogleg"]:
		var gun := Weapons.NAMES.find(name)
		_hold(g, gun)
		muzzles.shot(gun)
		g.clock += wait + .01
		muzzles.tick_wisp()
		check(muzzles.wisp_at >= 0.0, "one shot of the %s: a wisp" % name)
	muzzles.shot(Weapons.NAMES.find("hogleg"))
	check(muzzles.wisp_at < 0.0, "firing again ends it")
	g.clock += wait + .01
	muzzles.tick_wisp()
	g.armory.lower = 1.0
	muzzles.tick_wisp()
	check(muzzles.wisp_at < 0.0, "putting the gun down ends it")
	g.armory.lower = 0.0
	muzzles.shot(Weapons.NAMES.find("hogleg"))
	g.clock += wait + .01
	muzzles.tick_wisp()
	g.clock += life + .01
	muzzles.tick_wisp()
	check(muzzles.wisp_at < 0.0, "it is gone after its life")
	var whole := _pixels(MuzzleLooks.wisp(0, MuzzleLooks.RISE_STEPS - 1, 0))
	var low := _pixels(MuzzleLooks.wisp(0, 0, 0))
	var thin := _pixels(MuzzleLooks.wisp(0, MuzzleLooks.RISE_STEPS - 1, MuzzleLooks.THIN_STEPS - 1))
	check(whole > 40, "the wisp has body (%d pixels)" % whole)
	check(low < whole and thin < whole, "it rises and thins (%d, %d)" % [low, thin])
	check(not MuzzleLooks.smokes(Weapons.NAMES.find("teat_gun")), "the teat gun does not smoke")
	check(g.rng.state == before, "the smoke never draws on game.rng")


func _hold(g: Game, gun: int) -> void:
	var arms := g.armory
	arms.owned[gun] = true
	arms.reserve[gun] = maxi(Weapons.MAX_RESERVE[gun], 1)
	arms.loaded[gun] = Weapons.CAPACITY[gun]
	arms.active = gun
	arms.switch = 0.0
	arms.reload = 0.0
	arms.holstered = false
	arms.lower = 0.0
	arms._note_drawn()


func _pixels(data: PackedByteArray) -> int:
	var n := 0
	for i in range(3, data.size(), 4):
		n += 1 if data[i] > 0 else 0
	return n
