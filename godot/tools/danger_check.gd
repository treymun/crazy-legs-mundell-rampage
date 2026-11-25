## Reading danger (pass 15, src/danger_marks.gd, features/danger_looks.gd,
## EnemyLooks.tell), headless:
##
## - DANGER ARROWS: a blow from off the view (damage() with a source) draws one
##   red chevron on its side of the view and no other; a heavy one doubles; at
##   most `arrows_most` at once; each gone after `arrow_for`; ASPECT WIDE puts
##   them on the picture's edges; one slides clear of a touch button; the hurt
##   banner names only what hit (the side is the arrow's); off, no arrows and
##   the words and arc as before.
## - Wind-ups: a hand winding up behind the player gets an amber chevron at the
##   foot of the view, one in the view none; the model's amber (the sprite's
##   tell) shows over the right share of the wind-up only, never on a boss;
##   a big wind-up marks the floor where it is aimed, a short one does not; a
##   ranged hand's gun glints over the same share.
## - Hazards: the skull under the crosshair shows only when the boot's slide
##   line meets a hazard (a saw ahead, not one off to the side, not with no one
##   to kick); the brackets round a hazard near an awake hand in the sights,
##   not a sleeping one.
##
##   godot --headless --path godot --script res://tools/danger_check.gd
extends SceneTree

const Brawly := preload("res://tools/brawl_check.gd")
const DangerLooks := preload("res://src/features/danger_looks.gd")
const STEP := 1.0 / 60.0

var failures: Array = []
var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	_arrows()
	_windups()
	_hazards()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print(
		"DANGER CHECK OK" if failures.is_empty() else "%d DANGER CHECK(S) FAILED" % failures.size()
	)
	main.game = null
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=danger_check.gd::%s" % text)


## A quiet game on the range with the player on an open lane, facing east.
func _game() -> Game:
	var g: Game = Brawly.game(main)
	g.configure(SessionStore.defaults().duplicate())
	g.cheats.god = false
	g.spawn_grace = 0.0
	g.barks.enabled = false
	g.lessons = false
	var at := Brawly.lane(g, 8, Vector2i(4, 4))
	Brawly.stand(g, at, 0.0)
	g.player.health = 100
	main.game = g
	main.state = "play"
	return g


func _render() -> void:
	main.game.hurt_flash = 0.0  # the red wash over the whole view, not a mark
	main.render()


## The red pixels in the view's columns [x0, x1) (rows 20 to 140).
func _red(x0: int, x1: int) -> int:
	var pix: PackedByteArray = main.canvas.pixels
	var n := 0
	for y in range(20, 140):
		for x in range(x0, x1):
			var i := (y * 320 + x) * 3
			if pix[i] > 180 and pix[i + 1] < 90 and pix[i + 2] < 70:
				n += 1
	return n


# ------------------------------------------------------------------ arrows


func _arrows() -> void:
	print("\nDANGER ARROWS")
	var g := _game()
	var p := g.player
	_render()
	var calm := _red(0, 24) + _red(296, 320)
	# A blow from the player's left (north of him, facing east).
	g.damage(8.0, [p.x, p.y - 3.0], "BUCKSHOT")
	_check(g.danger_blows.size() == 1, "a blow with a source is kept for its arrow")
	_render()
	var fresh: Color = DangerMarks.arrows(g)[0][3]
	_check(fresh == DangerMarks.WHITE, "white the moment it lands")
	g.clock += .1
	_render()
	var marks := DangerMarks.arrows(g)
	_check(marks.size() == 1, "one arrow for one blow (%d)" % marks.size())
	if marks.size() == 1:
		var x: int = marks[0][0]
		var y: int = marks[0][1]
		var way: int = marks[0][2]
		_check(
			x < 24 and absi(y - 78) < 20 and way == 3,
			"on the view's left, pointing left (%d, %d, way %d)" % [x, y, way]
		)
		_check(not bool(marks[0][4]), "a light blow is a single chevron")
	var left := _red(0, 24)
	var right := _red(296, 320)
	_check(
		left > 8 and right <= calm,
		"drawn red at the left edge only (left %d, right %d)" % [left, right]
	)
	# From behind and to the right, heavy.
	g.damage(30.0, [p.x - 2.0, p.y + 2.0], "PITCHFORK")
	_render()
	marks = DangerMarks.arrows(g)
	_check(marks.size() == 2, "a second blow, a second arrow")
	if marks.size() == 2:
		var x2: int = marks[1][0]
		var y2: int = marks[1][1]
		var way2: int = marks[1][2]
		_check(
			y2 > 120 and x2 > 160 and way2 == 2,
			(
				"behind on the right: the foot of the view, pointing down (%d, %d, way %d)"
				% [x2, y2, way2]
			)
		)
		_check(bool(marks[1][4]), "a heavy blow doubles its chevron")
	for k in 5:
		g.damage(2.0, [p.x - k, p.y + 3.0], "HIT")
	_check(
		(
			g.danger_blows.size() == DangerMarks.ARROWS_MOST
			and DangerMarks.arrows(g).size() == DangerMarks.ARROWS_MOST
		),
		"at most %d arrows at once, the newest" % DangerMarks.ARROWS_MOST
	)
	g.clock += DangerMarks.ARROW_FOR + .01
	_render()
	_check(DangerMarks.arrows(g).is_empty(), "each gone after arrow_for")
	# No source (a fall), his own blast, a cloud right on him: no arrow.
	g.damage(3.0, null, "FALL")
	g.damage(3.0, [p.x + 2.0, p.y], "LIT DYNAMITE")
	g.damage(3.0, [p.x, p.y], "CHALK")
	_check(DangerMarks.arrows(g).is_empty(), "no source, his own blast or a cloud on him: none")
	# A cloud's middle off to his left, a boilerback's steam behind: arrows.
	g.damage(3.0, [p.x, p.y - 1.4], "CHALK")
	g.damage(3.0, [p.x - 3.0, p.y], "STEAM")
	_check(DangerMarks.arrows(g).size() == 2, "the chalk cloud's middle and the steam: two arrows")
	g.clock += DangerMarks.ARROW_FOR + .01
	# ASPECT WIDE: the picture's own edge.
	var was_shift := View.shift
	View.shift = 56
	g.danger_blows = [[p.view_angle() - PI / 2.0, g.clock, g.clock + .5, 5.0]]
	marks = DangerMarks.arrows(g)
	var wx: int = marks[0][0] if marks.size() == 1 else 999
	_check(wx < 0 and wx > -56, "WIDE: on the picture's left edge (x %d)" % wx)
	View.shift = was_shift
	# A touch button at the left edge: the arrow slides in clear of it.
	_render()
	var button := Rect2i(2, 64, 30, 30)
	g.hud.layout.take("touch_test", button)
	marks = DangerMarks.arrows(g)
	var box := (
		Rect2i(int(marks[0][0]) - 7, int(marks[0][1]) - 7, 15, 15) if marks.size() == 1 else button
	)
	_check(not box.intersects(button), "slid clear of a touch button over the view (%s)" % str(box))
	# The words: with arrows only what hit; without them the side as before.
	g.clock += 1.0
	g.damage(8.0, [p.x, p.y - 3.0], "BUCKSHOT")
	_render()
	var short: int = main.hud.layout.find("hurt").size.x
	g.danger_arrows = false
	_render()
	var wide: int = main.hud.layout.find("hurt").size.x
	_check(
		short > 0 and wide > short,
		"with arrows the banner names only what hit (%d px, %d with the side)" % [short, wide]
	)
	_check(DangerMarks.arrows(g).is_empty(), "DANGER ARROWS off: no arrows")
	_check(_red(24, 36) > 8, "and the hurt arc shows the side as before")
	g.danger_arrows = true
	var options := SessionStore.defaults().duplicate()
	_check(int(options.get("danger_arrows", -1)) == 1, "DANGER ARROWS is on by default")
	options["danger_arrows"] = 0
	g.configure(options)
	_check(not g.danger_arrows, "the setting reaches the game")


# ----------------------------------------------------------------- wind-ups


func _windups() -> void:
	print("\nWIND-UPS")
	var g := _game()
	var p := g.player
	var e := Brawly.hand(g, "billy", p.x - 4.0, p.y)
	e.player_seen = true
	var whole: float = Enemy.WINDUP["billy"][0]
	e.windup = whole * .8
	e.aim_mark = [p.x, p.y, p.eye]
	_render()
	var marks := DangerMarks.arrows(g)
	_check(marks.size() == 1, "a hand winding up behind: one arrow (%d)" % marks.size())
	if marks.size() == 1:
		var y: int = marks[0][1]
		var way: int = marks[0][2]
		var ink: Color = marks[0][3]
		_check(
			y > 120 and way == 2 and ink.g > ink.b + .2,
			"amber, at the foot of the view, pointing down (y %d, way %d)" % [y, way]
		)
	e.x = p.x + 4.0
	_render()
	_check(
		DangerMarks.arrows(g).is_empty(),
		"one winding up in the view: no arrow (his model shows it)"
	)
	# The amber over the last tell_share only.
	var share := EnemyLooks.TELL_SHARE
	e.windup = whole * (share + .1)
	var early := e.sprite([p.x, p.y], false, g.clock).tell
	e.windup = whole * (share - .1)
	var beat := floorf(g.clock * EnemyLooks.TELL_BEAT) / EnemyLooks.TELL_BEAT
	var late := e.sprite([p.x, p.y], false, beat + .1 / EnemyLooks.TELL_BEAT).tell
	var late2 := e.sprite([p.x, p.y], false, beat + .8 / EnemyLooks.TELL_BEAT).tell
	e.windup = 0.0
	var after := e.sprite([p.x, p.y], false, g.clock).tell
	_check(
		early == 0.0 and late > 0.0 and late2 > 0.0 and after == 0.0,
		(
			"the model's amber over the last %.0f%% of the wind-up only (%.2f, %.2f, %.2f, %.2f)"
			% [share * 100.0, early, late, late2, after]
		)
	)
	_check(late != late2, "and it flickers")
	e.windup = whole * (share - .1)
	e.hit_flash = .1
	var hit := e.sprite([p.x, p.y], false, g.clock)
	_check(hit.hurt > 0.0, "a hit's wash still shows over it (the 3D view puts the hit first)")
	e.hit_flash = 0.0
	var boss := Brawly.hand(g, "boss", p.x + 6.0, p.y + 2.0)
	boss.windup = .2
	_check(EnemyLooks.tell(boss, g.clock) == 0.0, "never on a boss (his own glow)")
	g.enemies.erase(boss)
	# The floor mark of a big wind-up.
	var looks: GameFeature = g.features["danger_looks"]
	var chain := Brawly.hand(g, "chain_hand", p.x + 5.0, p.y + 1.0)
	chain.player_seen = true
	chain.windup = float(Enemy.WINDUP["chain_hand"][0]) * .5
	chain.aim_mark = [p.x, p.y, p.eye]
	var slam := 0
	var dots := 0
	for m: View.GroundMark in looks.ground_marks():
		if m.image == "mark_slam" and absf(m.x - p.x) < .01 and absf(m.y - p.y) < .01:
			slam += 1
		elif m.image == "mark_warning":
			dots += 1
	_check(
		slam == 1 and dots >= 6,
		"a big wind-up marks the floor where it is aimed (%d, %d dots)" % [slam, dots]
	)
	_check(not DangerLooks.ringed(e), "a short one (billy) does not")
	g.enemies.erase(chain)
	# The glint at a ranged hand's gun.
	var tosser := Brawly.hand(g, "yard_deputy", p.x + 5.0, p.y - 1.0)
	tosser.player_seen = true
	tosser.aim_mark = [p.x, p.y, p.eye]
	var whole_t: float = Enemy.WINDUP["yard_deputy"][0]
	tosser.windup = whole_t * .9
	_render()
	var glints_early := _glints(looks)
	tosser.windup = whole_t * .3
	var glints_late := _glints(looks)
	_check(
		Enemy.RANGED.has("yard_deputy") and glints_early == 0 and glints_late >= 1,
		"a ranged hand's gun glints over the same share (%d, %d)" % [glints_early, glints_late]
	)


func _glints(looks: GameFeature) -> int:
	var n := 0
	for s: View.Sprite in looks.sprites():
		if s.image.begins_with("fx_glint"):
			n += 1
	return n


# ------------------------------------------------------------------ hazards


func _hazards() -> void:
	print("\nHAZARDS")
	var g := _game()
	var p := g.player
	var b = g.features["brawl"]
	b.spots()
	b._spots = [["saw", p.x + 3.6, p.y]]
	_check(not DangerMarks.skull(g), "no skull with no one to kick")
	var e := Brawly.hand(g, "billy", p.x + 1.2, p.y)
	_check(DangerMarks.skull(g), "a hand in front, a saw down the slide line: the skull")
	_render()
	var bone := 0
	var pix: PackedByteArray = main.canvas.pixels
	for y in range(84, 92):
		for x in range(155, 166):
			var i := (y * 320 + x) * 3
			if pix[i] > 200 and pix[i + 1] > 190 and pix[i + 2] > 150:
				bone += 1
	_check(bone >= 15, "drawn under the crosshair (%d bone pixels)" % bone)
	b._spots = [["saw", p.x + 3.0, p.y + 2.2]]
	_check(not DangerMarks.skull(g), "the saw off to the side of the line: no skull")
	b._spots = [["saw", p.x + 9.0, p.y]]
	_check(not DangerMarks.skull(g), "the saw past where the slide stops: no skull")
	# Brackets round a hazard near the awake hand in the sights.
	b._spots = [["saw", p.x + 3.6, p.y + 1.5]]
	e.x = p.x + 4.0
	e.alerted = true
	_check(DangerMarks.glowing(g).size() == 1, "a hazard near an awake hand in the sights glows")
	e.alerted = false
	_check(DangerMarks.glowing(g).is_empty(), "not near a sleeping one")
	e.alerted = true
	e.y = p.y + 3.0
	_check(DangerMarks.glowing(g).is_empty(), "nor one out of the sights")
	# The real boot agrees with the skull: kicked, he goes in.
	e.x = p.x + 1.2
	e.y = p.y
	b._spots = [["saw", p.x + 3.6, p.y]]
	var said := DangerMarks.skull(g)
	Brawly.press_use(g)
	Brawly.ticks(g, 1.5)
	_check(
		said and not e.alive and int(b.hazard_kills.get("saw", 0)) == 1,
		"booted where the skull said, he dies in the saw"
	)
