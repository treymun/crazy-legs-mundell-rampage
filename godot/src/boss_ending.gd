## A boss's fall as a short cinematic, like a 1990s cutscene (PLAY setting
## KILL CAM: BOSSES or BOSSES AND AREAS, on by default; OFF plays none). The
## blow lands, the view leaves the player's eyes (no gun, no HUD, black bars
## sliding in) and flies out on an eased path to a shot that frames the whole
## boss, swinging slowly round it while it falls in the boss fall's slow
## motion and the dust, sparks and debris go up; the boss bar drains and goes,
## a fair ribbon drops with its name, the music sinks under its end sting and
## its last word is captioned; then a fade to black and the iris opens on play
## again, or in a BOSS REMATCH on the result board (the card shows the time
## and the ribbon). Any key, button, click or tap skips to the fade.
##
## Looks only. Play goes on under it as ever (the front end advances the game
## with the controls let go, as when the console is open): it is drawn from
## game.eye_override, set only for the draw, and reads the game, never writes
## it. So it runs alike alone, in co-op and online (each machine shows its
## own when the boss's body shows it fell); what the fall does to play (the
## slow motion, the arena standing down, the hands stunned) is
## features/boss_fight.gd's, the same with or without this.
class_name BossEnding
extends RefCounted

const DATA := "res://data/tuning/camera.cfg"
## The bars over and under the picture (canvas rows), as the openers'.
const BAR_TOP := 14
const BAR_LOW := 142
## Where the card's ribbon hangs: in the bar under the picture.
const CARD_TOP := 145
## How long the bars take to slide in, and a dip's half when the view cuts.
const BARS_IN := .3
const DIP := .16
## Seconds after a body's fall within which it is still shown (a save
## loaded with a boss long down shows nothing).
const FRESH := .75
## How near the player's eye the camera keeps his own body undrawn, and how
## fast the shot follows a moving body (a share a second).
const SELF_CLEAR := 1.1
const FOLLOW := 5.0
## Cells a second the camera comes nearer or goes back out when a wall cuts
## in on its swing.
const REACH_RATE := 2.5
## The bearings tried round the boss: first (off the player's line, either
## side, then nearer it or round behind), and again round the lying body
## (nearest the camera first); and how long the camera takes to get there.
const FIRST_TURNS := [.95, -.95, 1.45, -1.45, .5, -.5, 2.0, -2.0, 0.0, 2.6, -2.6, PI]
const NEAR_TURNS := [0.0, .35, -.35, .7, -.7, 1.1, -1.1, 1.6, -1.6, 2.3, -2.3, PI]
const REFRAME_FLY := .9
## Bosses whose model is a ride as well (the boat's fan, the truck): their
## bones' middle is not the body's, so the shot keeps to their own spot.
const RIDES := ["swamp_king", "derby_champ"]
## The most the camera looks down (horizon pixels; the view draws to about 53).
const PITCH_MOST := 46.0
## How near the camera a blast is never drawn while it plays (cells).
const CLEAR_BLAST := 2.5
static var HOLD: float = _num("hold")
static var FLY: float = _num("fly")
static var FLY_FAR: float = _num("fly_far")
static var LENGTH: float = _num("length")
static var REMATCH_LENGTH: float = _num("rematch_length")
static var SHORT_LENGTH: float = _num("short_length")
static var END_FADE: float = _num("end_fade")
static var SKIP_FADE: float = _num("skip_fade")
static var SKIP_AFTER: float = _num("skip_after")
static var CARD_AT: float = _num("card_at")
static var BAR_TIME: float = _num("bar_time")
static var REACH: float = _num("reach")
static var NEAR: float = _num("near")
static var FAR: float = _num("far")
static var LIFT: float = _num("lift")
static var SWING: float = _num("swing")
static var PUSH: float = _num("push")
static var CRANE: float = _num("crane")
static var AIM_HIGH: float = _num("aim_high")
static var AIM_LOW: float = _num("aim_low")
static var DUCK: float = _num("duck")
static var SIZE: Dictionary = Tuning.file(DATA).get_value("boss_end", "size", {})
static var CLOSE: Dictionary = Tuning.file(DATA).get_value("boss_end", "close", {})

var mode := KillCam.BOSSES
var playing := false
var game: Game
var boss: Enemy
## Seconds into it, how long it runs, and how long its fade to black takes.
var at := 0.0
var length := 0.0
## Its natural length, which the swing is timed to (a skip only shortens length).
var span := 0.0
var fade := 0.0
var skipped := false
## The card: its title, the line under it, and the boss's health share the
## bar drains from.
var title := ""
var under := ""
var bar_from := 0.0
## The shot: the boss's feet (x, y and its floor), its height, how far off
## and how high the camera sits, where round it it starts and which way it
## swings; the eye it leaves from; whether it cuts (walled off) or flies.
var centre := Vector3.ZERO
var tall := 2.0
var reach := 3.0
var lift := 1.2
## How far up it cranes over the swing (CRANE, or 1 under a roof).
var crane := 1.8
var bearing := 0.0
var swing_way := 1.0
var start_eye := {}
var cuts := false
## The game whose ending last ran to its end (main_flow.gd's rematch reads it).
var ended_game: Game = null
var _seen_game: Game = null
var _bosses: Array = []
var _counted := -1
var _shown := {}
var _held := false
## The height of the drawn body's middle (NAN until the 3D view shows it).
var aim_z := NAN
## Where the drawn body's middle last was (-INF until drawn), and the reach
## the shot was planned at (the camera eases back to it once clear).
var body := Vector2(-INF, -INF)
var planned := 3.0
var first_reach := 3.0
var first_lift := 1.2
## The spot the shot was planned round.
var planned_round := Vector2.ZERO
## When the shot was planned again round the lying body (INF: not yet), and
## the eye it eases over from.
var reframed_at := INF
var re_spot := Vector3.ZERO
var re_angle := 0.0
var re_pitch := 0.0
var _last_body := Vector2(-INF, -INF)
## Seconds the end sting runs from the fall (0: none).
var sting_left := 0.0
var _black: Texture2D = null


static func _num(key: String) -> float:
	var v: float = Tuning.file(DATA).get_value("boss_end", key, 0.0)
	return v


## Whether one may run for this front end now: the setting, in play, and not
## a tour, bench, smoke run or demo (those must look the same everywhere).
func allowed(m: MainState) -> bool:
	if mode == KillCam.OFF or m.game == null or m.state != "play" or m.game.in_hub:
		return false
	return (
		m.view_tour == ""
		and m.view_bench == 0
		and m.smoke_frames == 0
		and not m.demo
		and not m.showcase
	)


# ------------------------------------------------------------------ when


## Each play frame before the game advances: a boss whose body shows it just
## fell starts one (a boss is shown once). True when one is playing.
func start(m: MainState) -> bool:
	if playing:
		return true
	var g := m.game
	if g == null:
		return false
	if g != _seen_game:
		_seen_game = g
		_shown.clear()
		_counted = -1
	if g.enemies.size() != _counted:
		# Looked over again when the list changes (backup, a mirror's update).
		_counted = g.enemies.size()
		_bosses.clear()
		for e: Enemy in g.enemies:
			if BossKit.is_boss(e):
				_bosses.append(e)
	for e: Enemy in _bosses:
		if e.alive or e.died_at < 0.0 or _shown.has(e.get_instance_id()):
			continue
		_shown[e.get_instance_id()] = true
		if g.clock - e.died_at > FRESH or not allowed(m) or g.defeated():
			continue
		begin(m, e)
		return true
	return false


func begin(m: MainState, e: Enemy) -> void:
	game = m.game
	boss = e
	playing = true
	skipped = false
	at = 0.0
	fade = END_FADE
	ended_game = null
	var g := game
	title = BossBar.title(e.kind)
	bar_from = clampf(e.struck_sum / maxf(1.0, e.max_hp), .04, 1.0)
	under = _under(g, e)
	length = LENGTH
	if BossRematch.active(g):
		length = REMATCH_LENGTH
	elif e == g.boss and g.jerry != null and g.jerry.hp > 0.0:
		length = SHORT_LENGTH
	start_eye = g.player.as_render_player()
	span = length
	OpenerCamera.prepare(g.world, g.props, m.art)
	_frame_shot(g, e)
	sting_left = _sting_seconds(m, g, e)
	aim_z = NAN
	body = Vector2(-INF, -INF)
	planned = reach
	reframed_at = INF
	_last_body = Vector2(-INF, -INF)
	planned_round = Vector2(centre.x, centre.y)
	_held = false


## The line under the name: a rematch's time and ribbon, Jerry coming, the
## ship coming apart, or how long the fight took.
static func _under(g: Game, e: Enemy) -> String:
	if BossRematch.active(g):
		var fight: GameFeature = g.features.get("boss_rematch")
		var seconds := 0.0
		if fight != null:
			seconds = fight.call("seconds")
		return (
			"TIME %s   %s"
			% [BossRematch.clock_text(seconds), BossRematch.ribbon(e.kind, seconds) + " RIBBON"]
		)
	if e == g.boss and g.jerry != null and g.jerry.hp > 0.0:
		return "HERE COMES JERRY!"
	if e.brain == "maw":
		return "THE SHIP'S COMING APART!"
	var fall: GameFeature = g.features.get("boss_fight")
	if fall != null:
		var down: Dictionary = fall.get("down")
		if down.has(e.kind):
			var took: float = down[e.kind]
			var s := int(took)
			return "PUT DOWN IN %d:%02d" % [int(s / 60.0), s % 60]
	return "AND HE AIN'T GETTIN' UP"


# ------------------------------------------------------------------ the shot


## Where the camera works from: off to one side of the player's line, the
## boss's size away, its whole swing clear of walls and in sight of the boss
## (nearer, or from the player's own side, when nothing else is).
func _frame_shot(g: Game, e: Enemy) -> void:
	var w: LevelData = g.world
	tall = e.height * e.variant
	var size: float = SIZE.get(e.kind, tall)
	centre = Vector3(e.x, e.y, w.stand(e))
	reach = clampf(size * REACH, NEAR, FAR)
	if CLOSE.has(e.kind):
		var close: float = CLOSE[e.kind]
		reach = close
	first_reach = reach
	lift = clampf(size * LIFT, .9, 3.4)
	first_lift = lift
	var p := g.player
	var toward := atan2(p.y - e.y, p.x - e.x)
	var found := _plan(w, toward, FIRST_TURNS, 0.0)
	if not found:
		# Walled in all round: from the player's side, as near as it must be.
		bearing = toward
		swing_way = 1.0
		reach = clampf(Vector2(p.x - e.x, p.y - e.y).length(), 1.2, reach * .5)
		lift = minf(lift, 1.1)
		crane = 1.0
	var to := orbit(HOLD + FLY)
	var from := _start_spot()
	cuts = from.distance_to(to) > FLY_FAR or not _path_clear(w, from, to)


## The first clear swing round `centre` from bearings `toward` + each of
## `turns` (a swing already `share` of the way through), at the planned reach
## or nearer: bearing, swing_way and reach set. False when none is clear.
func _plan(w: LevelData, toward: float, turns: Array, share: float) -> bool:
	var full := reach
	var high := lift
	# Craning up and high first; lower under a roof or a lintel (Maw's
	# throne alcove), then nearer.
	for low: Array in [[1.0, CRANE], [1.0, 1.0], [.6, 1.0], [.45, 1.0]]:
		var lower: float = low[0]
		lift = high * lower
		crane = low[1]
		for scale: float in [1.0, .8, .64, .5]:
			for turn: float in turns:
				var way := 1.0 if turn >= 0.0 else -1.0
				if share > 0.0:
					way = swing_way
				var a: float = toward + turn - SWING * way * _smooth(share)
				if _swing_clear(w, a, way, full * scale):
					bearing = a
					swing_way = way
					reach = full * scale
					return true
	lift = high
	crane = CRANE
	return false


## The body has come to rest away from where it stood (a boss falls the
## length of itself): the shot is planned again round where it lies, as near
## the camera's bearing as is clear, and the camera eased over to it.
func _reframe() -> void:
	var w: LevelData = game.world
	var was := eye_at(at)
	var share := clampf((at - HOLD) / maxf(.1, span - HOLD), 0.0, 1.0)
	var x: float = was["x"]
	var y: float = was["y"]
	var z: float = was["eye"]
	reframed_at = at
	re_spot = Vector3(x, y, z)
	re_angle = was["view_angle"]
	re_pitch = was["pitch"]
	var kept := [bearing, swing_way, reach, lift, crane, centre]
	centre.x = body.x
	centre.y = body.y
	reach = first_reach
	lift = first_lift
	if _plan(w, Vector2(x - body.x, y - body.y).angle(), NEAR_TURNS, share):
		planned = reach
		planned_round = body
	else:
		# Nowhere clear round where it lies: the shot as it was.
		bearing = kept[0]
		swing_way = kept[1]
		reach = kept[2]
		lift = kept[3]
		crane = kept[4]
		centre = kept[5]


## The camera's spot at `a` round the boss, `d` off: clear by the openers'
## own rule (OpenerCamera.clear_at: no wall, roof, deck, door, prop or ground
## near it), clear of the furniture, and in sight of the boss's middle.
func spot_clear(w: LevelData, a: float, d: float, up: float) -> bool:
	var x := centre.x + cos(a) * d
	var y := centre.y + sin(a) * d
	var z := centre.z + up
	if x < 1.0 or y < 1.0 or x > w.width - 1.0 or y > w.height - 1.0:
		return false
	return (
		OpenerCamera.clear_at(w, x, y, z) == ""
		and not w.blocked(x, y, .3, z)
		and w.visible(x, y, centre.x, centre.y, z, centre.z + tall * .5 if is_nan(aim_z) else aim_z)
	)


func _swing_clear(w: LevelData, a: float, way: float, d: float) -> bool:
	for k in 7:
		var share := k / 6.0
		if not spot_clear(w, a + SWING * way * share, d * _out(share), _up(share)):
			return false
	return true


## Nothing solid on the straight way from the player's eye to the shot.
static func _path_clear(w: LevelData, from: Vector3, to: Vector3) -> bool:
	var steps := int(ceilf(from.distance_to(to) / .25))
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		if w.blocked(p.x, p.y, .15, p.z):
			return false
	return true


## The swinging camera's spot at `t`.
func orbit(t: float) -> Vector3:
	var share := _smooth(clampf((t - HOLD) / maxf(.1, span - HOLD), 0.0, 1.0))
	var a := bearing + SWING * swing_way * share
	var d := reach * _out(share)
	return Vector3(centre.x + cos(a) * d, centre.y + sin(a) * d, centre.z + _up(share))


## How far out (a share of reach) and how high over the boss's floor the
## camera is `share` of the way through its swing: easing back and craning
## up as the body comes to lie, so the whole of it shows whichever way it fell.
func _out(share: float) -> float:
	return 1.0 + PUSH * share


func _up(share: float) -> float:
	return lift * lerpf(1.0, crane, share)


## What the camera looks at: the boss's middle as the blow lands, low on
## it once it lies.
func target(t: float) -> Vector3:
	var down := _smooth(clampf((t - .2) / 1.4, 0.0, 1.0))
	var low := AIM_LOW * (.35 if RIDES.has(boss.kind) else 1.0) if boss != null else AIM_LOW
	var z := centre.z + tall * lerpf(AIM_HIGH, low, down)
	if not is_nan(aim_z):
		z = lerpf(aim_z, z, .35)  # the drawn body's middle, a touch toward the floor
	return Vector3(centre.x, centre.y, z)


## The camera's eye at `t`: the player's, then flown out to the swing (or cut
## to it at the dip), looking at the boss.
func eye_at(t: float) -> Dictionary:
	var spot := orbit(t)
	var look := target(t)
	var flat := Vector2(look.x - spot.x, look.y - spot.y)
	var angle := atan2(flat.y, flat.x)
	# Never so high over a near body that the view cannot tilt down to it
	# (the King in his boat at the bottom edge).
	var most := look.z + PITCH_MOST * maxf(.5, flat.length()) / View.base_focal
	if spot.z > most:
		spot.z = maxf(most, centre.z + .6)
	var pitch := -View.base_focal * (spot.z - look.z) / maxf(.5, flat.length())
	var k := _smooth(clampf((t - HOLD) / FLY, 0.0, 1.0))
	if cuts:
		k = 1.0 if t >= HOLD + FLY * .5 else 0.0
	if k < 1.0:
		var from := _start_spot()
		var from_angle: float = start_eye["view_angle"]
		var from_pitch: float = start_eye["pitch"]
		spot = from.lerp(spot, k)
		angle = lerp_angle(from_angle, angle, k)
		pitch = lerpf(from_pitch, pitch, k)
	var over := _smooth(clampf((t - reframed_at) / REFRAME_FLY, 0.0, 1.0))
	if t >= reframed_at and over < 1.0:
		spot = re_spot.lerp(spot, over)
		angle = lerp_angle(re_angle, angle, over)
		pitch = lerpf(re_pitch, pitch, over)
	var eye := {
		"x": spot.x,
		"y": spot.y,
		"eye": spot.z,
		"view_angle": angle,
		"pitch": clampf(pitch, -70.0, 70.0),
		"bob": 0.0,
		"sway": 0.0,
	}
	if Vector2(spot.x - _start_spot().x, spot.y - _start_spot().y).length() < SELF_CLEAR:
		eye["hide_player"] = true  # still in the player's head: not drawn round the camera
	return eye


static func _smooth(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# ------------------------------------------------------------------ playing


## One frame: the clock runs, the music holds under the end sting while it
## plays, and at the end (or once the game is gone) it stops.
func frame(m: MainState, dt: float) -> void:
	if not playing:
		return
	if m.game != game or m.state != "play" or game.defeated():
		stop(m, false)
		return
	at += dt
	_follow(m, dt)
	_music(m)
	if at >= length:
		stop(m, true)


## The music under the boss's end sting: eased down to DUCK while it plays
## (the score and the sting played over each other before), then let go to
## ease back up (Sound's opener hold, which only an opener uses otherwise).
func _music(m: MainState) -> void:
	if m.sound == null:
		return
	if at < sting_left - .15:
		_held = true
		var down := _smooth(clampf(at / .35, 0.0, 1.0))
		m.sound.set_opener_hold(lerpf(1.0, DUCK, down))
	else:
		_let_music_go(m)


func _let_music_go(m: MainState) -> void:
	if _held and m.sound != null:
		m.sound.end_opener(PackedStringArray())
	_held = false


## How long the end sting the fall played lasts (game_world.gd and
## mothership.gd play it: the chapter's last boss its own, Jerry and the
## sheriff alone Hickston's), 0 when there is none (the sheriff with Jerry
## to come keeps the boss loop going).
static func _sting_seconds(m: MainState, g: Game, e: Enemy) -> float:
	var cue := ""
	if e == g.finale:
		cue = e.kind + "_end"
	elif e == g.jerry or (e == g.boss and (g.jerry == null or g.jerry.hp <= 0.0)):
		cue = "shakedown_end"
	var stream := m.art.cue(cue) if cue != "" and m.art != null else null
	return stream.get_length() if stream != null else 0.0


## The shot keeps on the body as it moves (a truck rolling on, a boat
## drifting) and as it falls: eased after the middle of the body as the 3D
## view draws it (its bones), so a boss lying the length of itself away from
## its feet is still framed whole; the camera brought nearer while the spot
## it swings to is walled off.
func _follow(m: MainState, dt: float) -> void:
	var w: LevelData = game.world
	var k := minf(1.0, dt * FOLLOW)
	var want := Vector2(boss.x, boss.y)
	var mid: Variant = null
	if m.world_view != null and m.world_view.actors != null and not RIDES.has(boss.kind):
		mid = m.world_view.actors.body_middle(boss)
	if mid is Vector3:
		var middle: Vector3 = mid
		if Vector2(middle.x - boss.x, middle.y - boss.y).length() < tall:
			body = Vector2(middle.x, middle.y)
			aim_z = middle.z if is_nan(aim_z) else lerpf(aim_z, middle.z, k)
	if body.x > -INF:
		want = body  # the last the view drew (out of sight it is not drawn)
		var still := body.distance_to(_last_body) < .004
		_last_body = body
		var away := body.distance_to(planned_round)
		if still and is_inf(reframed_at) and at > HOLD + FLY * .6 and away > tall * .3:
			_reframe()
			return
	centre.x = lerpf(centre.x, want.x, k)
	centre.y = lerpf(centre.y, want.y, k)
	centre.z = lerpf(centre.z, w.stand(boss), k)
	if at < HOLD:
		return
	# The nearest of the planned reach and a few shorter ones that is clear,
	# eased to (never a jump).
	var share := _smooth(clampf((at - HOLD) / maxf(.1, span - HOLD), 0.0, 1.0))
	var a := bearing + SWING * swing_way * share
	var fit := planned
	for i in 5:
		if spot_clear(w, a, fit * _out(share), _up(share)):
			break
		fit = maxf(NEAR * .5, fit * .85)
	reach = move_toward(reach, fit, dt * REACH_RATE)


## Any key, button, click or tap: on to the fade (after SKIP_AFTER, so the
## trigger held through the killing blow does not skip it). True when taken.
func skip() -> bool:
	if not playing:
		return false
	if at < SKIP_AFTER or skipped:
		return true
	skipped = true
	if at < length - SKIP_FADE:
		length = at + SKIP_FADE
		fade = SKIP_FADE
	return true


## Done (`whole`: ran to its black) or cut short: the music let go, the
## trigger held from the fight ignored, and the iris opens on play.
func stop(m: MainState, whole: bool) -> void:
	if not playing:
		return
	playing = false
	_let_music_go(m)
	m.mouse_rel = Vector2.ZERO
	m.block_fire = true
	if whole:
		ended_game = game
		m.screen_age = 0.0
	game = null
	boss = null


# ------------------------------------------------------------------ drawing


## The frame: the world from the camera (no gun, no HUD; the player stands in
## it), the bars, the drained boss bar, the card, the caption, the fades.
func draw(m: MainState) -> void:
	var g := m.game
	var c := m.canvas
	var eye := eye_at(at)
	g.eye_override = eye
	# The ship's explosions coming apart round Maw (and any blast) between the
	# camera and the body are left out of the picture: they filled the frame.
	var blasts := g.blasts
	g.blasts = _behind(blasts, eye)
	var fx: GameFeature = g.features.get("gun_fx")
	var booms: Array = []
	var bits: Array = []
	if fx != null:
		booms = fx.get("booms")
		bits = fx.get("bits")
		fx.set("booms", _behind(booms, eye))
		fx.set("bits", _behind(bits, eye))
	g.draw(c, 0, true)
	m.show_view()
	g.blasts = blasts
	if fx != null:
		fx.set("booms", booms)
		fx.set("bits", bits)
	g.eye_override = {}
	if c.gpu:
		c.gpu_item(Canvas.ITEM_NORMAL)
	var dark := 0.0
	if cuts:
		dark = maxf(0.0, 1.0 - absf(at - (HOLD + FLY * .5)) / DIP)
	if dark > 0.0:
		_shade(c, 0, 0, View.WIDTH, View.VIEW, dark)
	var bars := _smooth(clampf(at / BARS_IN, 0.0, 1.0))
	var black := Color(0, 0, 0)
	c.fill_rect(0, 0, View.WIDTH, int(roundf(BAR_TOP * bars)), black)
	var low := int(roundf(lerpf(View.VIEW, BAR_LOW, bars)))
	c.fill_rect(0, low, View.WIDTH, View.HEIGHT - low, black)
	_draw_bar(c)
	draw_card(c, at - CARD_AT, title, under)
	_draw_caption(c, g)
	if at > SKIP_AFTER and not skipped:
		var skip_word := "TAP TO SKIP" if m.input_device == "touch" else "ANY KEY SKIPS"
		c.anchor(View.shift)  # ASPECT WIDE: at the picture's right edge
		HUD.text(c, skip_word, 312, 4, "mini", HUD.DIM, false, false, true)
		c.anchor(0)
	var gone := clampf((at - (length - fade)) / maxf(.05, fade), 0.0, 1.0)
	if gone > 0.0:
		_shade(c, 0, 0, View.WIDTH, View.HEIGHT, gone)


## The blasts (game.blasts, and gun_fx's fireballs and their smoke and
## scraps) out of the camera's way: none nearer it than the body is, and none
## within CLEAR_BLAST of it. Looks only: the lists are put back after the draw.
func _behind(things: Array, eye: Dictionary) -> Array:
	if things.is_empty():
		return things
	var x: float = eye["x"]
	var y: float = eye["y"]
	var to_body := Vector2(centre.x - x, centre.y - y).length()
	var out: Array = []
	for thing: Variant in things:
		var at := Vector2.INF
		if thing is Array:
			var row: Array = thing
			var rx: float = row[0]
			var ry: float = row[1]
			at = Vector2(rx, ry)
		elif thing is Object:
			var obj: Object = thing
			var ox: float = obj.get("x")
			var oy: float = obj.get("y")
			at = Vector2(ox, oy)
		var d := at.distance_to(Vector2(x, y))
		if d > CLEAR_BLAST and d > to_body - .5:
			out.append(thing)
	return out


## The boss bar where the fight had it, emptying to nothing and sliding off.
func _draw_bar(c: Canvas) -> void:
	if at > BAR_TIME:
		return
	var drain := clampf(at / (BAR_TIME * .55), 0.0, 1.0)
	var off := _smooth(clampf((at - BAR_TIME * .6) / (BAR_TIME * .4), 0.0, 1.0))
	var x := 193 + int(roundf(off * 130.0))
	var y := BAR_TOP + 4
	HUD.panel(c, x, y, 122, 20, Canvas.rgb(35, 24, 20), Canvas.rgb(126, 85, 57))
	HUD.text(c, title, x + 60, y + 3, "body", HUD.INK, true, false)
	c.fill_rect(x + 6, y + 12, 110, 4, Canvas.rgb(70, 42, 32))
	var share := bar_from * (1.0 - drain)
	if share > 0.0:
		c.fill_rect(
			x + 6, y + 12, maxi(1, int(roundf(110.0 * share))), 4, Canvas.rgb(255, 238, 200)
		)


## The fair ribbon for the fall (BossKit.draw_intro's, turned to the end) in
## the bar under the picture, clear of the body: unrolled from the middle,
## the name slammed on it, the line under it on a dark strip. `t` is seconds
## since it began (nothing before).
static func draw_card(c: Canvas, t: float, name: String, line: String) -> void:
	if t < 0.0:
		return
	var red := Canvas.rgb(150, 30, 24)
	var deep := Canvas.rgb(98, 18, 14)
	var gold := Canvas.rgb(236, 196, 104)
	var shade := Canvas.rgb(20, 12, 9)
	var half := int(lerpf(18.0, 132.0, clampf(t / .2, 0.0, 1.0)))
	var top := CARD_TOP
	for side: int in [-1, 1]:
		# Swallowtails at either end, a shade darker.
		var x0 := 160 + side * half - (10 if side < 0 else 0)
		c.fill_rect(x0, top + 4, 10, 18, deep)
		c.fill_rect(x0 + (0 if side < 0 else 5), top + 10, 5, 6, Color(0, 0, 0))
	c.fill_rect(160 - half, top, half * 2, 26, red)
	c.fill_rect(160 - half + 3, top + 2, half * 2 - 6, 1, gold)
	c.fill_rect(160 - half + 3, top + 23, half * 2 - 6, 1, gold)
	if t < .14:
		return
	var fall := clampf((t - .14) / .12, 0.0, 1.0)
	var y := int(lerpf(float(top - 18), float(top + 6), fall))
	var jolt := 0
	if fall >= 1.0 and t < .55:
		jolt = int(roundf(sin(t * 70.0) * 3.0 * (1.0 - (t - .26) / .29)))
	HUD.text(c, name, 160 + jolt, y, "heading", HUD.AMBER, true)
	if t < .45 or line == "":
		return
	var wide := PixelType.text_width(line, "body") + 16
	c.fill_rect(160 - wide / 2, top + 29, wide, 12, shade)
	c.fill_rect(160 - wide / 2, top + 29, wide, 1, Canvas.rgb(126, 85, 57))
	HUD.text(c, line, 160, top + 32, "body", gold, true)


## The line being said (the boss's last word, Mundell's answer) at the foot,
## under the card: one line, or two small ones when it is long.
static func _draw_caption(c: Canvas, g: Game) -> void:
	if not g.voice_captions or g.caption == "" or g.clock > g.caption_until:
		return
	if PixelType.text_width(g.caption, "body") <= 312:
		HUD.text(c, g.caption, View.WIDTH / 2, 189, "body", HUD.INK, true, false)
		return
	var lines := PixelType.wrap(g.caption, 312, "mini")
	for i in mini(2, lines.size()):
		HUD.text(c, lines[i], View.WIDTH / 2, 187 + i * 6, "mini", HUD.INK, true, false)


## Black laid over at `alpha` (with no window: solid past half).
func _shade(c: Canvas, x: int, y: int, w: int, h: int, alpha: float) -> void:
	if c.gpu:
		if _black == null:
			var one := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			one.fill(Color(0, 0, 0, 1))
			_black = ImageTexture.create_from_image(one)
		c.gpu_texture(_black, x, y, w, h, roundi(clampf(alpha, 0.0, 1.0) * 255.0))
	elif alpha >= .5:
		c.fill_rect(x, y, w, h, Color(0, 0, 0))


## Where the player's eye was as the blow landed.
func _start_spot() -> Vector3:
	var x: float = start_eye["x"]
	var y: float = start_eye["y"]
	var z: float = start_eye["eye"]
	return Vector3(x, y, z)
