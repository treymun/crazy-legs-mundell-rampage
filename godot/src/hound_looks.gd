## How BLUE looks (features/hound.gd), all of it drawn from what play
## carries and the clock (looks only: nothing here touches play or
## game.rng):
##
## - His body in the view: his model (scenes/actors/hound.tscn, made by
##   scripts/blender/actors_hound.py) stood in by an Enemy only the view reads
##   (ModeBodies.stand_in), posed by `pose`: the walk, trot and gallop on his
##   gait (a limp when he is sore, his nose down when he tracks), idle with
##   the tail going and now and then a scratch or a sniff, sat or lying at
##   STAY, the point, the howl, the lunge and bite, the hold with its head
##   shake, the yelp, going down onto his side, whining there, got up by a
##   hand on him, getting up and shaking it off. ActorView blends one pose
##   into the next (fit.json "blend") and plays a motion's five keys on the
##   stand-in's gait. What he carries is drawn in his jaws.
## - His badge in the view's bottom left corner (ui/hud/hud_layout.gd): his
##   head (hound_face_*), his mood, what he is up to, his health.
## - A tin marker over him when he is out of sight behind something, or at
##   the view's edge pointing his way when he is off it (red, blinking, when
##   he is down); brackets on what he points or bays at; GETTIN' BLUE UP and
##   its bar while a hand is on him.
class_name HoundLooks
extends RefCounted

## The badge's plate: its top left on the 320x200 canvas, its size.
const BADGE_X := HudLayout.EDGE
const BADGE_W := 74
const BADGE_H := 33
## The head's box in it.
const FACE := 28
## The plate's wood and trim, as the status bar's (hud.gd meter()).
const PLATE := Color(57 / 255.0, 46 / 255.0, 38 / 255.0)
const TRIM := Color(172 / 255.0, 159 / 255.0, 132 / 255.0)
const TRIM_LOW := Color(125 / 255.0, 111 / 255.0, 92 / 255.0)
const TRIM_SIDE := Color(100 / 255.0, 92 / 255.0, 76 / 255.0)
const WELL := Color(29 / 255.0, 23 / 255.0, 19 / 255.0)
const RIVET := Color(140 / 255.0, 124 / 255.0, 98 / 255.0)
## Health: eight ticks, red, amber, then a field green by how many are lit.
const TICKS := 8
const TICK_INK := [
	Color(238 / 255.0, 89 / 255.0, 52 / 255.0),
	Color(251 / 255.0, 183 / 255.0, 98 / 255.0),
	Color(160 / 255.0, 210 / 255.0, 92 / 255.0)
]
## The marker's cool tin (the night rim's blue) and the down marker's red.
const MARK := Color(150 / 255.0, 190 / 255.0, 240 / 255.0)
const MARK_DARK := Color(22 / 255.0, 28 / 255.0, 40 / 255.0)
const MARK_DOWN := Color(255 / 255.0, 96 / 255.0, 64 / 255.0)
const POINT_INK := Color(251 / 255.0, 207 / 255.0, 142 / 255.0)
const REVIVE_INK := Color(160 / 255.0, 210 / 255.0, 92 / 255.0)
## His size in the world: his model is built in metres (a bluetick about
## .66 at the shoulder and .82 to the top of his head), and the world draws
## a man (a co-op partner's Mundell, ModeScreens.PARTNER_HEIGHT) about .97
## tall, so a metre of him is SIZE of the world's: his shoulder about .37
## and his head about .46 of Mundell's height, as a real hound's against a
## man's (tools/actor_check.gd holds it). Before pass 10's size fix he was
## drawn a metre to the world unit, nearly as tall as the man.
const SIZE := .54
## His gaits (pass 12), by how fast his legs go (Dog.stride_v, cells a
## second): the walk, into the trot over TROT_FROM (back under TROT_TO), into
## the lope (his gallop's keys) over LOPE_FROM (back under LOPE_TO), held
## between so a gait never flickers. GALLOP_FROM is kept for the old cels.
const TROT_FROM := 1.5
const TROT_TO := 1.0
const LOPE_FROM := 2.6
const LOPE_TO := 1.9
const GALLOP_FROM := LOPE_FROM
## How far a planted foot goes back a beat in each gait's keys (metres of
## his model: walk, trot, lope; tools/hound_pace.gd measures them off the
## model), the share of the ground his feet keep to (1 they hold it), and
## the most strides a second each gait goes (past it they slip a little
## rather than scurry). Play's Dog.gait gains beats_per_cell a cell.
const STRIDE: Array[float] = [.15, .21, .277]
const HOLD := .9
const CADENCE: Array[float] = [3.6, 4.2, 4.8]
## Seconds: going down onto his side, his breathing on it, getting up, the
## shake after; the idle wag's loops a second; the lunge's gather before
## a bite and its follow-through after.
const FALL_TIME := .9
const DOWN_LOOP := 2.8
const UP_TIME := .75
const SHAKE_TIME := .8
const WAG := 1.6
const GATHER := .22
const FOLLOW_THROUGH := .36
## Each hound's idle round (seconds) and its scratch and sniff in it; his
## tracking round at heel.
const IDLE_ROUND := 21.0
const SCRATCH_FOR := 1.8
const SNIFF_AT := 9.0
const SNIFF_FOR := 2.0
const TRACK_ROUND := 26.0
const TRACK_FOR := 6.0
## Sat at STAY this long he lies down.
const LIE_AFTER := 9.0
## His legs going faster than this (cells a second) he walks, and under
## STAND_TO he stands again (pass 12).
const MOVING := .3
const STAND_TO := .12
## Still beside his player standing this long he sits, and this long lies
## down (pass 12).
const SIT_AFTER := 4.0
## Stood this long, his idle round's scratch and sniff come round.
const IDLE_AFTER := 1.5
const LIE_DOWN_AFTER := 14.0
## Under this share of his health he is sore: he limps and stops wagging.
const SORE := .35
## His job words on the badge, by his state (features/hound.gd), and while
## he goes with his player by what he is up to (Dog.job, Hound.JOBS).
const JOBS := [
	"HEELIN'",
	"STAYIN'",
	"SIC 'EM",
	"HOLDIN'",
	"FETCHIN'",
	"BRINGIN'",
	"BAYIN'",
	"POINTIN'",
	"DOWN!",
	"HOWLIN'",
	"HIDIN'",
	"GLAD",
	"WAGGIN'",
	"GROWLIN'",
	"RIDIN'"
]
const FOLLOW_JOBS := [
	"HEELIN'",
	"RANGIN'",
	"SNIFFIN'",
	"CIRCLIN'",
	"HUSTLIN'",
	"DODGIN'",
	"TRAILIN'",
	"WAITIN'",
	"LEADIN'"
]
## His mood words on the badge for Dog.mood (Hound.MOODS: calm, happy,
## alert, scared, sulking, hurt), with their inks.
const MOOD_WORDS := ["EASY", "HAPPY", "RILED", "SKEERED", "SULKIN'", "SORE"]
## The old cels (2D pictures) a motion stands in for when no model draws him.
const CELS := {
	"i": "0",
	"w": "w",
	"t": "w",
	"l": "w",
	"n": "w",
	"r": "r",
	"c": "sit",
	"k": "0",
	"f": "pain",
	"o": "down",
	"v": "down",
	"u": "sit",
	"j": "bite",
	"p": "pin",
	"rest": "whine"
}
## Head picture -> its scaled pixels.
static var _faces: Dictionary = {}

# ------------------------------------------------------------------ his body


## His gait (-1 standing, 0 walk, 1 trot, 2 lope) for legs going `v` cells a
## second, from the one he was in (`was`): held between the thresholds.
static func gait_of(was: int, v: float) -> int:
	if v > LOPE_FROM or (was == 2 and v > LOPE_TO):
		return 2
	if v > TROT_FROM or (was >= 1 and v > TROT_TO):
		return 1
	if v > MOVING or (was >= 0 and v > STAND_TO):
		return 0
	return -1


## His legs' beats a cell in gait `kind` going `v` cells a second: his feet
## held to the ground (HOLD of it), no more than CADENCE strides a second.
static func beats_per_cell(kind: int, v: float) -> float:
	var k := maxi(kind, 0)
	var hold := HOLD / (STRIDE[k] * SIZE)
	if v > .05:
		hold = minf(hold, CADENCE[k] * 4.0 / v)
	return hold


## [frame, gait]: the frame his model shows (actors.json "hound"; a motion's
## first beat, x0, for a motion) and the gait it is played at (ActorView: a
## motion's beat is gait / (PI / 2), 0..4).
static func pose(h: Game.HoundScript, d: Game.HoundScript.Dog) -> Array:
	var g := h.game
	var now := g.clock
	if d.state == Game.HoundScript.DOWN:
		if d.revive > 0.0:
			# A hand on him: up onto his chest and his forelegs as it goes.
			return _run("v", _once(d.revive / h.n("revive_time")))
		var lying := now - d.down_at
		if lying < FALL_TIME:
			return _run("f", _once(lying / FALL_TIME))
		return _run("o", _loop((lying - FALL_TIME) / DOWN_LOOP))
	var up := now - d.up_at
	if up >= 0.0 and up < UP_TIME:
		return _run("u", _once(up / UP_TIME))
	if up >= UP_TIME and up < UP_TIME + SHAKE_TIME:
		return _run("k", _loop((up - UP_TIME) / SHAKE_TIME * 2.0))
	if now - d.hurt_at < .35:
		return ["pain", 0.0]
	var sore := d.health < h.n("health") * SORE
	var p: Player = g.players[d.slot] if d.slot < g.players.size() else null
	var calm := p != null and d.calm
	var tracking := (
		(d.state == Game.HoundScript.BAY or d.state == Game.HoundScript.POINT)
		and d.bark_at < d.since
	)
	if d.state == Game.HoundScript.FOLLOW and calm and d.item == "":
		tracking = fmod(now + d.slot * 7.3, TRACK_ROUND) < TRACK_FOR
	if d.gait_kind >= 0:
		if d.gait_kind == 2:
			return ["r0", d.gait]
		if d.gait_kind == 1:
			return ["l0" if sore else "t0", d.gait]
		# Sulking behind, his nose down too.
		var low := tracking or d.mood == Game.HoundScript.SULK
		var walk := "l0" if sore else "n0" if low else "w0"
		return [walk, d.gait]
	match d.state:
		Game.HoundScript.STAY:
			var lie := p != null and p.health <= 0
			return ["rest" if lie or now - d.since > LIE_AFTER else "sit", 0.0]
		Game.HoundScript.PIN:
			return _run("p", _loop(now * 2.2))
		Game.HoundScript.SIC:
			var gather := d.bite_at - now
			if gather >= 0.0 and gather < GATHER:
				return _run("j", (1.0 - gather / GATHER) * 2.0)
			var after := now - (d.bite_at - h.n("bite_every"))
			if after >= 0.0 and after < FOLLOW_THROUGH:
				return _run("j", 2.0 + after / FOLLOW_THROUGH * 1.999)
			if d.bite_at - h.n("bite_every") > d.since:
				# Between bites, braced to go again (the lunge's last key; pass
				# 12: a bark flashed up between bites).
				return _run("j", 3.999)
			return ["bark", 0.0]
		Game.HoundScript.BAY:
			return ["bay" if d.bark_at >= d.since else "sniff", 0.0]
		Game.HoundScript.POINT:
			return ["point" if d.bark_at >= d.since else "sniff", 0.0]
		Game.HoundScript.CARRY, Game.HoundScript.TREAT:
			return ["fetch", 0.0]
		Game.HoundScript.RIDE:
			return ["sit", 0.0]
		Game.HoundScript.HOWL:
			return ["bay", 0.0]
		Game.HoundScript.GROWL:
			return ["bark", 0.0]
		Game.HoundScript.COWER:
			return ["rest", 0.0]
		Game.HoundScript.GREET:
			return _run("i", _loop(now * WAG * 2.2))
	if d.item != "":
		return ["fetch", 0.0]
	if now - d.bark_at < .3:
		return ["bark", 0.0]
	if d.state == Game.HoundScript.FOLLOW and d.job == Game.HoundScript.LEAD and d.until > 0.0:
		return ["point", 0.0]  # pass 15: at a stop down the way, showing it
	if p != null and p.health <= 0:
		return ["rest", 0.0]
	if sore:
		# standing, the sore leg held off the ground (the limp's first beat)
		return ["l0", 0.0]
	if tracking or (d.state == Game.HoundScript.FOLLOW and d.job == Game.HoundScript.NOSING):
		return ["sniff", 0.0]
	# Settled by his player standing (pass 12): he sits, then lies down.
	var settled := now - d.still_at
	if (
		calm
		and d.state == Game.HoundScript.FOLLOW
		and (d.job == Game.HoundScript.HEEL or d.job == Game.HoundScript.WAIT)
		and d.p_v.length() < .3
		and settled > SIT_AFTER
	):
		return ["rest" if settled > LIE_DOWN_AFTER else "sit", 0.0]
	var round := fmod(now + d.slot * 5.1, IDLE_ROUND)
	# (Only once he has stood a moment: a scratch flashed up as he stopped.)
	var stood := settled > IDLE_AFTER
	if calm and stood and round < SCRATCH_FOR:
		return _run("c", _loop(round / .36))
	if stood and round >= SNIFF_AT and round < SNIFF_AT + SNIFF_FOR:
		return ["sniff", 0.0]
	return _run("i", _loop(now * WAG + d.slot * .3))


## A motion's first beat and the gait that plays `beat` (0..4) of it.
static func _run(motion: String, beat: float) -> Array:
	return [motion + "0", beat * PI * .5]


## A motion played through once: `k` of the way (0..1) -> its beat, short of
## its last key (a whole 4 would wrap round to the first).
static func _once(k: float) -> float:
	return clampf(k, 0.0, 1.0) * 3.999


## A motion looped: `k` loops -> its beat.
static func _loop(k: float) -> float:
	return fposmod(k, 1.0) * 4.0


## The old cel (assets/art/hound_<cel>) standing for a model frame.
static func cel(frame: String, gait: float) -> String:
	var motion := frame[0] if ActorView.is_run(frame) else frame
	var beat := int(fposmod(gait / (PI * .5), 4.0))
	var named: String = CELS.get(motion, motion)
	if named == "w" or named == "r":
		return named + str(beat)
	if motion == "i":
		return "wag" if beat % 2 == 1 else "0"
	if motion == "p":
		return "pin2" if beat >= 2 else "pin"
	if motion == "f" and beat >= 2:
		return "down"
	return named


## His bodies in the view this frame (each hound in sight) and what each
## carries.
static func sprites(h: Game.HoundScript) -> Array:
	var out: Array = []
	var g := h.game
	for d: Game.HoundScript.Dog in h.dogs:
		if d.slot >= g.players.size() or g.players[d.slot].away:
			continue
		if not g.in_view(d.x, d.y, 1.2):
			continue
		var now := pose(h, d)
		var frame: String = now[0]
		var gait: float = now[1]
		# Holding a hand he is drawn where play has him: at his size his jaws
		# reach from the hold's gap (the two bodies' radii) to its legs. (Drawn
		# a metre to the unit before pass 10, his head stood in its chest and
		# he was set back .3.)
		var bx := d.x
		var by := d.y
		var e := ModeBodies.stand_in(g, "hound%d" % d.slot, "hound")
		e.x = bx
		e.y = by
		e.angle = d.angle
		e.gait = gait
		e.height = SIZE
		e.variant = 1.0
		e.died_at = -1.0
		# A kick or a blast rocks him as a hit rocks a hand (ActorView.flinch).
		e.struck_at = d.hurt_at
		e.struck_sum = 18.0
		e.last_zone = "body"
		var s := g.pooled(bx, by, "hound_" + cel(frame, gait), SIZE, d.floor_z)
		s.pose = "hound_" + frame
		s.who = e
		s.body = true
		s.hurt = d.flash
		out.append(s)
		if d.item != "":
			out.append(carried(g, d.item, d.x, d.y, d.floor_z, d.angle))
	return out


## What he carries, in his jaws: the pickup's own picture, small.
static func carried(
	g: Game, item: String, x: float, y: float, z: float, angle: float
) -> View.Sprite:
	var reach := .86 * SIZE
	return g.pooled(
		x + cos(angle) * reach, y + sin(angle) * reach, "item_" + item, .2 * SIZE, z + .72 * SIZE
	)


# ------------------------------------------------------------------ the badge


## The badge's rect on the view: the bottom left corner.
static func rect() -> Rect2i:
	return Rect2i(BADGE_X, View.VIEW - BADGE_H - 3, BADGE_W, BADGE_H)


## His job on the badge: what he is up to ("SNIFFIN'" when he tracks,
## "LIMPIN'" when he is sore at heel).
static func job(h: Game.HoundScript, d: Game.HoundScript.Dog) -> String:
	var frame: String = pose(h, d)[0]
	if d.state == Game.HoundScript.FOLLOW:
		if frame == "u0" or frame == "k0":
			return "UP AGIN"
		if frame == "n0" or frame == "sniff":
			return "SNIFFIN'"
		if d.health < h.n("health") * SORE:
			return "LIMPIN'"
	if d.state == Game.HoundScript.STAY and frame == "rest":
		return "LAYIN' UP"
	if d.state == Game.HoundScript.FOLLOW:
		return FOLLOW_JOBS[clampi(d.job, 0, FOLLOW_JOBS.size() - 1)]
	return JOBS[clampi(d.state, 0, JOBS.size() - 1)]


## His mood on the badge: [word, colour]. Down he is WHIPPED; sore (low
## or just hurt) SORE; in a fight RILED; on point KEEN; his player low
## FRETTIN'; at STAY PATIENT; else play's own mood (Dog.mood, MOOD_WORDS).
static func mood(h: Game.HoundScript, d: Game.HoundScript.Dog) -> Array:
	var g := h.game
	var share := d.health / maxf(1.0, h.n("health"))
	var p: Player = g.players[d.slot] if d.slot < g.players.size() else null
	if d.state == Game.HoundScript.DOWN:
		return ["WHIPPED", HUD.LOW]
	if share < SORE or g.clock - d.hurt_at < 1.0 or d.mood == Game.HoundScript.HURT:
		return ["SORE", HUD.LOW]
	if d.state == Game.HoundScript.SIC or d.state == Game.HoundScript.PIN:
		return ["RILED", Color(1.0, .55, .3)]
	if d.state == Game.HoundScript.BAY or d.state == Game.HoundScript.POINT:
		return ["KEEN", HUD.AMBER]
	match d.mood:
		Game.HoundScript.ALERT:
			return ["RILED", Color(1.0, .55, .3)]
		Game.HoundScript.SCARED:
			return ["SKEERED", HUD.DIM]
		Game.HoundScript.SULK:
			return ["SULKIN'", HUD.DIM]
		Game.HoundScript.HAPPY:
			return ["HAPPY", TICK_INK[2]]
	if p != null and p.health > 0 and p.health < 30:
		return ["FRETTIN'", HUD.DIM]
	if d.state == Game.HoundScript.STAY:
		return ["PATIENT", HUD.DIM]
	return [MOOD_WORDS[Game.HoundScript.CALM], TICK_INK[2]]


## The badge for player p's hound: the tin plate, his head in its well,
## his mood, what he is up to, eight health ticks. Kept narrow: the prompt
## and the caption rise beside it.
static func badge(h: Game.HoundScript, c: Canvas, d: Game.HoundScript.Dog) -> void:
	var g := h.game
	var x := BADGE_X
	var y := View.VIEW - BADGE_H - 3
	c.round_rect(x, y, BADGE_W, BADGE_H, 2, PLATE)
	c.line(x + 2, y, x + BADGE_W - 3, y, TRIM)
	c.line(x + 1, y + 1, x + 1, y + BADGE_H - 3, TRIM_SIDE)
	c.line(x + 2, y + BADGE_H - 2, x + BADGE_W - 3, y + BADGE_H - 2, TRIM_LOW)
	for rx: int in [x + BADGE_W - 4]:
		c.fill_rect(rx, y + 2, 1, 1, RIVET)
		c.fill_rect(rx, y + BADGE_H - 4, 1, 1, RIVET)
	var face := "0"
	var share := d.health / maxf(1.0, h.n("health"))
	if d.state == Game.HoundScript.DOWN:
		face = "down"
	elif g.clock - d.hurt_at < 1.0 or share < SORE or d.mood == Game.HoundScript.HURT:
		face = "2"
	elif d.state in [Game.HoundScript.SIC, Game.HoundScript.PIN, Game.HoundScript.BAY]:
		face = "1"
	elif d.state in [Game.HoundScript.GROWL, Game.HoundScript.HOWL]:
		face = "1"
	elif d.state == Game.HoundScript.POINT:
		face = "1"
	# the head in its dark well
	c.fill_rect(x + 3, y + 2, FACE, FACE, WELL)
	_face(g, c, "hound_face_" + face, x + 3, y + 2)
	var right := x + 3 + FACE + 3
	# his mood
	var feel: Array = mood(h, d)
	var feel_word: String = feel[0]
	var feel_ink: Color = feel[1]
	HUD.text(c, feel_word, right, y + 3, "mini", feel_ink, false, true)
	# what he is up to; DOWN blinks
	var down := d.state == Game.HoundScript.DOWN
	if not down or fmod(g.clock, .8) < .5:
		HUD.text(c, job(h, d), right, y + 12, "mini", HUD.LOW if down else HUD.AMBER, false, true)
	# health: eight ticks in a well
	var lit := clampi(ceili(share * TICKS - .001), 0, TICKS)
	var ink: Color = TICK_INK[0 if lit <= 2 else 1 if lit <= 5 else 2]
	c.fill_rect(right - 1, y + 21, TICKS * 4 + 1, 9, WELL)
	for i in TICKS:
		var on := i < lit
		var shade := ink if on else Color(ink.r * .22, ink.g * .22, ink.b * .22)
		c.fill_rect(right + i * 4, y + 22, 3, 7, shade)
		if on:
			c.line(right + i * 4, y + 22, right + i * 4 + 2, y + 22, ink.lightened(.25))


## Whether `at` (the 320x200 picture) is on the badge, shown in game `g`
## (a tap there whistles: main_input.gd).
static func on_badge(g: Game, at: Vector2i) -> bool:
	var hound: Game.HoundScript = g.features.get("hound")
	if hound == null or not hound.on:
		return false
	return rect().grow(3).has_point(at)


## A head picture scaled into the FACE box (kept), at (x, y).
static func _face(g: Game, c: Canvas, name: String, x: int, y: int) -> void:
	var scaled: Dictionary = _faces.get(name, {})
	if scaled.is_empty():
		var art := g.art.art(name)
		var w: int = art["w"]
		var h: int = art["h"]
		var data: PackedByteArray = art["data"]
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for py in h:
			for px in w:
				if data[(py * w + px) * 4 + 3] >= 128:
					x0 = mini(x0, px)
					x1 = maxi(x1, px)
					y0 = mini(y0, py)
					y1 = maxi(y1, py)
		scaled = {"w": 0, "h": 0, "data": PackedByteArray()}
		if x1 >= x0 and y1 >= y0:
			var cw := x1 - x0 + 1
			var ch := y1 - y0 + 1
			var k := minf(float(FACE) / cw, float(FACE) / ch)
			var tw := maxi(1, roundi(cw * k))
			var th := maxi(1, roundi(ch * k))
			var sub := PackedByteArray()
			sub.resize(cw * ch * 4)
			for py in ch:
				for px in cw:
					var from := ((y0 + py) * w + x0 + px) * 4
					var to := (py * cw + px) * 4
					for b in 4:
						sub[to + b] = data[from + b]
			scaled = {"w": tw, "h": th, "data": SmoothScale.rgba(sub, cw, ch, tw, th)}
		_faces[name] = scaled
	var sw: int = scaled["w"]
	if sw == 0:
		return
	var sh: int = scaled["h"]
	var pix: PackedByteArray = scaled["data"]
	c.blit_rgba(pix, sw, sh, x + (FACE - sw) / 2, y + FACE - sh, "hound|" + name)


# ------------------------------------------------------------------ the HUD


## The badge keeps the view's bottom left corner (ui/hud/hud_layout.gd).
static func lay_fixed(h: Game.HoundScript, layout: HudLayout) -> void:
	if _mine(h) != null:
		layout.take("badge", rect())


## GETTIN' BLUE UP and its bar, while this machine's player has a hand on
## a hound down beside them: over the view's foot, under the prompt.
static func lay_flow(h: Game.HoundScript, layout: HudLayout) -> void:
	if _reviving(h) != null:
		layout.up("hound_revive", Vector2i(70, 14), 125)


## Everything of his over the view: the markers, the brackets on what he
## points at, the revive bar, the badge.
static func draw(h: Game.HoundScript, c: Canvas) -> void:
	var d := _mine(h)
	if d == null:
		return
	var g := h.game
	if g.player.health > 0 and not g.map and g.eye_override.is_empty():
		_point_mark(h, c, d)
		_marker(h, c, d)
	var helped := _reviving(h)
	var at := g.hud.layout.find("hound_revive")
	if helped != null and at.size.x > 0:
		HudLayout.begin(c, "hound_revive")
		HUD.text(c, "GETTIN' BLUE UP", at.position.x + 1, at.position.y + 1, "mini", REVIVE_INK)
		var share := clampf(helped.revive / maxf(.01, h.n("revive_time")), 0.0, 1.0)
		c.fill_rect(at.position.x + 1, at.position.y + 8, 66, 5, WELL)
		c.fill_rect(at.position.x + 2, at.position.y + 9, roundi(64 * share), 3, REVIVE_INK)
		HudLayout.end(c)
	HudLayout.begin(c, "badge")
	badge(h, c, d)
	HudLayout.end(c)


## This machine's player's hound, or null.
static func _mine(h: Game.HoundScript) -> Game.HoundScript.Dog:
	var g := h.game
	if not h.on or g.local_player == null:
		return null
	return h.dog_of(g.local_player)


## A hound down that this machine's player has a hand on (holding USE by
## him, the revive under way), or null.
static func _reviving(h: Game.HoundScript) -> Game.HoundScript.Dog:
	var g := h.game
	var me: Player = g.local_player
	if not h.on or me == null or me.health <= 0:
		return null
	for d: Game.HoundScript.Dog in h.dogs:
		if (
			d.state == Game.HoundScript.DOWN
			and d.revive > 0.0
			and Vector2(me.x - d.x, me.y - d.y).length() < h.n("revive_reach")
		):
			return d
	return null


## Whether the view's eye sees him (his back over whatever is between).
static func in_sight(g: Game, d: Game.HoundScript.Dog) -> bool:
	if g.view_eye.is_empty():
		return true
	var ex: float = g.view_eye["x"]
	var ey: float = g.view_eye["y"]
	var ez: float = g.view_eye["eye"]
	return g.world.visible(ex, ey, d.x, d.y, ez, d.floor_z + .9 * SIZE)


## Where his marker goes this frame: [x, y (the 320x200 view), the way
## the arrow points (radians, 0 down the view)], or [] for none. Over him
## when he is in the view but out of sight; at the edge of the view his
## way when he is off it; none when he is in plain sight or right by.
static func marker_at(g: Game, d: Game.HoundScript.Dog, near := 2.5) -> Array:
	if g.view_eye.is_empty():
		return []
	var ex: float = g.view_eye["x"]
	var ey: float = g.view_eye["y"]
	var gap := Vector2(d.x - ex, d.y - ey).length()
	if gap < near:
		return []
	var top := d.floor_z + (.5 if d.state == Game.HoundScript.DOWN else 1.05) * SIZE
	var at := g.to_canvas(d.x, d.y, top)
	var margin := 10.0
	var side := float(View.shift)  # ASPECT WIDE: the picture's own edges
	var on_view := (
		at.z > 0.0
		and at.x > margin - side
		and at.x < View.WIDTH + side - margin
		and at.y > margin
		and at.y < View.VIEW - margin
	)
	if on_view:
		if in_sight(g, d):
			return []
		return [at.x, at.y - 5.0, 0.0]
	if at.z > 0.0:
		# Ahead but past the view's edge (under its foot, off a side): on
		# the edge nearest him, pointing at him.
		var edge := Vector2(
			clampf(at.x, 12.0 - side, View.WIDTH + side - 12.0),
			clampf(at.y, 14.0, View.VIEW - 46.0)
		)
		var toward := Vector2(at.x, at.y) - edge
		if toward.length() < .5:
			return [edge.x, edge.y, 0.0]
		toward = toward.normalized()
		return [edge.x, edge.y, atan2(-toward.x, toward.y)]
	# Behind the eye: round the view's middle toward him, on its edge.
	var angle: float = g.view_eye["view_angle"]
	var dx := d.x - ex
	var dy := d.y - ey
	var ahead := dx * cos(angle) + dy * sin(angle)
	var across := dy * cos(angle) - dx * sin(angle)
	var way := atan2(across, ahead)
	var cx := View.WIDTH / 2.0 + sin(way) * (View.WIDTH / 2.0 + side - 14.0)
	var cy := View.VIEW / 2.0 - cos(way) * (View.VIEW / 2.0 - 16.0)
	cx = clampf(cx, 12.0 - side, View.WIDTH + side - 12.0)
	cy = clampf(cy, 14.0, View.VIEW - 46.0)
	return [cx, cy, way + PI]


## The marker: a little tin tag with BLUE on it and an arrow under it
## pointing at him (down when he is behind something in the view).
static func _marker(h: Game.HoundScript, c: Canvas, d: Game.HoundScript.Dog) -> void:
	var g := h.game
	var down := d.state == Game.HoundScript.DOWN
	# Down and right by him, the prompt says it; on his way, from further.
	var where := marker_at(g, d, h.n("revive_reach") + .3 if down else 2.5)
	if where.is_empty():
		return
	if down and fmod(g.clock, .7) >= .45:
		return
	var ink := MARK_DOWN if down else MARK
	var mx: float = where[0]
	var my: float = where[1]
	var cx := roundi(mx)
	var cy := roundi(my)
	var way: float = where[2]
	var word := "BLUE!" if down else "BLUE"
	var w := PixelType.text_width(word, "mini") + 4
	# Clear of the HUD's pieces: slid in toward the view's middle, or not
	# drawn at all.
	var clear := false
	for _try in 8:
		var box := Rect2i(cx - w / 2 - 1, cy - 14, w + 2, 15)
		clear = true
		for r: Rect2i in g.hud.layout.taken:
			if r.intersects(box):
				clear = false
		if clear:
			break
		cx += signi(160 - cx) * 8
		cy += signi(View.VIEW / 2 - cy) * 6
	if not clear:
		return
	var x := cx - w / 2
	var y := cy - 13
	c.fill_rect(x, y, w, 8, MARK_DARK)
	c.line(x, y, x + w - 1, y, ink.darkened(.3))
	HUD.text(c, word, x + 2, y + 2, "mini", ink, false, false)
	# the arrow: three rows narrowing toward him
	var dir := Vector2(-sin(way), cos(way))
	if absf(way) < .01:
		dir = Vector2(0, 1)
	var tip := Vector2(cx, cy - 5) + dir * 5.0
	var side := Vector2(-dir.y, dir.x)
	for k in 4:
		var row := tip - dir * k
		var half := k
		for s in range(-half, half + 1):
			var px := row + side * s
			c.fill_rect(roundi(px.x), roundi(px.y), 1, 1, ink if k < 3 else ink.darkened(.4))


## Brackets on what he points or bays at, while he does, breathing as
## USE's mark does.
static func _point_mark(h: Game.HoundScript, c: Canvas, d: Game.HoundScript.Dog) -> void:
	var g := h.game
	if d.state != Game.HoundScript.POINT and d.state != Game.HoundScript.BAY:
		return
	if d.bark_at < d.since or d.look == Vector2.INF:
		return
	var floor := g.world.floor_under(d.look.x, d.look.y, d.floor_z + 1.0)
	var at := g.to_canvas(d.look.x, d.look.y, floor + .3)
	if at.z <= 0.0:
		return
	var half := int(clampf(.3 / at.z * View.base_focal, 5, 14))
	var cx := int(at.x)
	var cy := int(at.y)
	if (
		cx < half - View.shift
		or cx > View.WIDTH + View.shift - half
		or cy < half + 8
		or cy > View.VIEW - half
	):
		return
	var glow := .72 + .28 * sin(g.clock * 5.0)
	var ink := Color(POINT_INK.r * glow, POINT_INK.g * glow, POINT_INK.b * glow)
	var arm := maxi(2, half / 3)
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var x := cx + sx * half
			var y := cy + sy * half
			c.fill_rect(mini(x, x - sx * arm), y, arm + 1, 1, ink)
			c.fill_rect(x, mini(y, y - sy * arm), 1, arm + 1, ink)
	# a little paw-print pip over the brackets: BLUE's find
	var bob := roundi(sin(g.clock * 4.0) * 1.5)
	var px := cx
	var py := cy - half - 6 + bob
	c.fill_rect(px - 1, py, 3, 2, ink)
	for t: int in [-2, 0, 2]:
		c.fill_rect(px + t, py - 2, 1, 1, ink)
