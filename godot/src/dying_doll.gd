## A man dying, not dead at once (pass 15, T11 ACTIVE BODIES; looks only):
## the dead body's ragdoll (Ragdoll: the level's real shape, the other
## bodies, the wreck pieces, sleep) with muscles still in it for a second or
## more. Play says he is dead and where the body goes (features/corpses.gd);
## this is only how the last of him looks. Each muscle pulls a limb ball
## toward a place from its chain parent in the torso's frame (pulling the
## parent back by as much, as LiveBody's do), its stiffness the tone
## (`env`) times the group's share, and the tone fades: nothing is played
## back.
##
## - **Going slack** (every one): the muscles hold what he had when he was
##   hit, fading over `dying_slack` seconds (a head shot `dying_head`), the
##   legs going first (`dying_legs` of the tone).
## - **Bracing** on the way down: the torso tipping, the arms swing toward
##   where the chest will land and the head is held off it, as strong as the
##   tone left (a dying man half catches himself).
## - **On the ground** (by its own dice, `dying_styles`, only for a hit
##   below the head and not a blast): he may *writhe* (knees drawn up and
##   let go, a hand on the wound, the head up, rocking from side to side),
##   *try to get up* (face down: hands under the shoulders, gripping the
##   floor, the arms pushing him up, then the tone goes and he falls back) or
##   *crawl* (face down: a hand reaches ahead, grips, the arm pulls him on to
##   it, the other next), for `dying_writhe` seconds, then go slack over
##   `dying_slack_end`.
## - **Run down** (killed_by "roadkill"): the vehicle's front is a moving
##   box for a moment (`dying_hood`: [height, length, width, seconds] in
##   shares of the body): the legs swept along by its face, the rest falling
##   back onto its top and carried, so he rolls up over the hood or is
##   knocked flat.
##
## `muscles` false: a plain ragdoll (the checks). Its own dice.
class_name DyingDoll
extends Ragdoll

const LIMP := 0
const WRITHE := 1
const GET_UP := 2
const CRAWL := 3

## Numbers (effects.cfg [ragdoll] dying_*: looks).
static var TONE: float = Effects.RAGDOLL.get("dying_tone", .3)
static var LEGS: float = Effects.RAGDOLL.get("dying_legs", .12)
static var SLACK_FOR: Array = Effects.RAGDOLL.get("dying_slack", [1.0, 2.0])
static var HEAD_FOR: Array = Effects.RAGDOLL.get("dying_head", [.3, .5])
static var STYLES: Array = Effects.RAGDOLL.get("dying_styles", [.5, .22, .14, .14])
static var WRITHE_FOR: Array = Effects.RAGDOLL.get("dying_writhe", [1.8, 3.2])
static var SLACK_END: float = Effects.RAGDOLL.get("dying_slack_end", 1.0)
static var CRAWL_CYCLE: float = Effects.RAGDOLL.get("dying_crawl", .9)
static var HOOD: Array = Effects.RAGDOLL.get("dying_hood", [.36, 1.1, .75, .45])
## A style every dying body takes (-1: its own dice; the motion strips).
static var force_style := -1
static var MUSCLE_MOST: float = Effects.RAGDOLL.get("dying_muscle_most", .02)
## Seconds the arms take the fall once a hand is down before they give.
static var BRACE_GIVE: float = Effects.RAGDOLL.get("dying_brace_give", .2)
## How hard a crawling arm pulls (times the tone) and how far ahead the
## hand reaches for the floor (a share of the arm).
static var CRAWL_PULL: float = Effects.RAGDOLL.get("dying_crawl_pull", 2.6)
static var CRAWL_REACH: float = Effects.RAGDOLL.get("dying_crawl_reach", .85)
## The share of a writhing (or rising) body's drift across the floor taken
## back each step: the muscles move its balls straight, past the floor's
## friction (which holds speeds), so without it the thrashing swims him along.
static var WRITHE_ANCHOR: float = Effects.RAGDOLL.get("dying_writhe_anchor", 1.0)

var style := LIMP
var slack_for := 1.5
var behave_for := 0.0
## When it came to lie (age; -1 still going down) and its tone now.
var lay_at := -1.0
var env := 1.0
var muscles := true
var dice := RandomNumberGenerator.new()
## Each ball's place from its chain parent (torso frame) as it was hit, and
## this step's wanted places.
var held := PackedVector3Array()
var _want := PackedVector3Array()
var _k := PackedFloat32Array()
## The wound (torso frame from the hips' middle) and the hand on it.
var wound := Vector3.ZERO
var clutch_hand := -1
## A hand on the floor first and the head or chest on it first (age; -1 not).
var hand_down_at := -1.0
var torso_down_at := -1.0
var brace_at := Vector3.INF
## Hands gripping the floor (index -> point).
var grips := {}
## The vehicle's front: since (a point at age 0), way, speed, top over the
## floor, the floor, length, width, until (age).
var hood_from := Vector2.ZERO
var hood_dir := Vector2.ZERO
var hood_speed := 0.0
var hood_top := 0.0
var hood_floor := 0.0
var hood_len := 0.0
var hood_w := 0.0
var hood_until := -1.0
## The muscles' travel this step (map units; the checks).
var work := 0.0
var _rest := PackedVector3Array()
## The middle where the writhing left it last step (INF: not writhing).
var _anchor := Vector3.INF


## A dying body for a body hung on `rig`, posed as `model` under `xf`.
static func made_dying(rig: RagdollRig, xf: Transform3D, model: PackedVector3Array) -> DyingDoll:
	var doll := DyingDoll.new()
	Ragdoll.made(rig, xf, model, doll)
	return doll


## How he dies, from how play killed `e` (seeded by `seed`): the style, how
## long the tone lasts, the wound, the vehicle. After fit() and knock().
func begin(e: Enemy, seed: int) -> void:
	dice.seed = seed
	held.resize(R.POINTS)
	_want.resize(R.POINTS)
	_k.resize(R.POINTS)
	_rest.resize(R.POINTS)
	var fr := LiveBody._torso_frame(pos)
	var frt := LiveBody._torso_frame(_rig_points())
	var rest := _rig_points()
	for i in R.POINTS:
		var par: int = LiveBody.PARENT_OF[i]
		if par == -1:
			continue
		held[i] = fr.transposed() * (pos[i] - _from(pos, par))
		_rest[i] = frt.transposed() * (rest[i] - _from(rest, par))
	var lo: float = SLACK_FOR[0]
	var hi: float = SLACK_FOR[1]
	slack_for = dice.randf_range(lo, hi)
	var zone := e.last_zone
	var how := e.killed_by
	var flung := how == "blast" or how == "energy" or how == "roadkill"
	style = LIMP
	if zone == "head":
		var hlo: float = HEAD_FOR[0]
		var hhi: float = HEAD_FOR[1]
		slack_for = dice.randf_range(hlo, hhi)
	elif not flung:
		var roll := dice.randf()
		var total := 0.0
		for k in STYLES.size():
			var share: float = STYLES[k]
			total += share
			if roll < total:
				style = k
				break
	if force_style >= 0:
		style = force_style
	var wlo: float = WRITHE_FOR[0]
	var whi: float = WRITHE_FOR[1]
	behave_for = dice.randf_range(wlo, whi)
	if style == CRAWL:
		# (Room to drag himself a little way off play's body.)
		slack = .65
	# The wound: where the hit landed on the torso (front or back), the hand
	# on the other side.
	wound = Vector3(dice.randf_range(-.6, .6) * radius[R.BELLY], dice.randf_range(.2, .55), 0.0)
	wound.y *= (rest[R.SH_L].distance_to(rest[R.HIP_L])) * size
	wound.z = radius[R.BELLY] * (1.0 if e.last_side != "back" else -1.0)
	clutch_hand = 1 if wound.x < 0.0 else 0
	if _stiff(R.SH_L if clutch_hand == 0 else R.SH_R):
		clutch_hand = 1 - clutch_hand
	if _stiff(R.SH_L if clutch_hand == 0 else R.SH_R):
		clutch_hand = -1
	if how == "roadkill" and e.blast_at != Vector2.INF:
		_hood(e)


## The rig's standing points (map units, as start() took them).
func _rig_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in R.POINTS:
		var p := rig.points[i] * size
		out.append(Vector3(p.x, p.z, p.y))
	return out


static func _from(at: PackedVector3Array, par: int) -> Vector3:
	return (at[R.SH_L] + at[R.SH_R]) * .5 if par == -2 else at[par]


func _hood(e: Enemy) -> void:
	var way := Vector2(e.x, e.y) - e.blast_at
	if way.length() < 1e-4:
		return
	hood_dir = way.normalized()
	var tall := (pos[R.HEAD].z - (pos[R.FOOT_L].z + pos[R.FOOT_R].z) * .5) / .9
	var top: float = HOOD[0]
	var length: float = HOOD[1]
	var width: float = HOOD[2]
	var secs: float = HOOD[3]
	hood_floor = minf(pos[R.FOOT_L].z - radius[R.FOOT_L], pos[R.FOOT_R].z - radius[R.FOOT_R])
	hood_top = top * tall
	hood_len = length * tall
	hood_w = width * tall
	hood_until = secs
	var per: float = Corpses.PER_POINT["blast"]
	var corpse_run := Corpses.BLAST_RUN + per * e.struck_sum
	hood_speed = corpse_run * 1.25
	var mid := middle()
	hood_from = Vector2(mid.x, mid.y) - hood_dir * (radius[R.HIP_L] + .04)


## Whether it still moves of itself.
func active() -> bool:
	return muscles and env > .01


## Ragdoll's, and no muscle travel reported once it has gone to sleep (the
## last step's would otherwise stand for every frame after).
func advance(world: LevelData, dt: float) -> int:
	var n := super.advance(world, dt)
	if not awake:
		work = 0.0
	return n


## Once a step: where each muscle wants its ball now (and how hard).
func _before_passes(_world: LevelData) -> void:
	work = 0.0
	if held.size() != R.POINTS:
		return
	_mark_down()
	env = _envelope()
	if active():
		# (Not asleep while the muscles still move him: lying still a moment
		# between two pulls of a crawl is not rest.)
		still = 0.0
	var fr := LiveBody._torso_frame(pos)
	for i in R.POINTS:
		_want[i] = held[i]
		var g: int = LiveBody.GROUP_OF[i]
		_k[i] = TONE * env * (LEGS if g == LiveBody.LEGS else 1.0)
	if lay_at < 0.0:
		_brace(fr)
		return
	var t := age - lay_at
	if t > behave_for or style == LIMP:
		# (The behaviour over, no hand stays gripping the floor; while the
		# last of the tone fades the floor still holds him where he is.)
		grips.clear()
		if style != LIMP and active():
			_hold_in_place(WRITHE, fr)
		else:
			_anchor = Vector3.INF
		return
	var face_down := fr.z.z < -.3
	var now := style
	if (now == GET_UP or now == CRAWL) and not face_down:
		now = WRITHE
	_hold_in_place(now, fr)
	match now:
		WRITHE:
			_writhe(fr, t)
		GET_UP:
			_get_up(fr, t)
		CRAWL:
			_crawl(fr, t)


## The tone now: held a moment and fading over slack_for (LIMP), or kept
## up through the style on the ground and fading after.
func _envelope() -> float:
	if not muscles:
		return 0.0
	if style == LIMP or lay_at < 0.0:
		var k := _fade(age, .06, slack_for)
		if style != LIMP:
			# (A man who will writhe keeps some on the way down.)
			k = maxf(k, .45)
		return k
	var t := age - lay_at
	if t < behave_for:
		var swell := .75 + .25 * sin(t * 2.3)
		if style == GET_UP:
			# His last push and then nothing.
			var phase := fmod(t, 1.7)
			swell = 1.0 if phase < 1.35 else .08
		return swell
	return _fade(t - behave_for, 0.0, SLACK_END) * .7


static func _fade(t: float, hold: float, over: float) -> float:
	if t <= hold:
		return 1.0
	var k := clampf((t - hold) / maxf(.05, over - hold), 0.0, 1.0)
	return 1.0 - k * k * (3.0 - 2.0 * k)


## Down yet: a hand first, the head or chest; lying once the torso is.
func _mark_down() -> void:
	if _touch.size() < R.POINTS:
		return
	if hand_down_at < 0.0 and (_touch[R.HAND_L] or _touch[R.HAND_R]):
		hand_down_at = age
	var torso := 0
	for i: int in [R.HEAD, R.SH_L, R.SH_R, R.BELLY, R.BACK, R.HIP_L, R.HIP_R]:
		torso += _touch[i]
	if torso_down_at < 0.0 and (_touch[R.HEAD] or _touch[R.SH_L] or _touch[R.SH_R]):
		torso_down_at = age
	# (Lying: the torso down on the floor, or flat and come to rest on
	# whatever is under it, a gun, an arm.)
	var fr := LiveBody._torso_frame(pos)
	var mid := middle()
	var sinking := (
		(mid.z - (old[R.HIP_L].z + old[R.HIP_R].z + old[R.SH_L].z + old[R.SH_R].z) * .25) / STEP
	)
	var flat := absf(fr.y.z) < .55 and absf(sinking) < .25 and age > .25
	if lay_at < 0.0 and (torso >= 3 or flat):
		lay_at = age
		grips.clear()


## The floor holding a body on the ground that the muscles would shove about
## (they move its balls straight, past the floor's friction, which only holds
## speeds): writhing or trying to rise, its drift across the floor since last
## step is mostly taken back (WRITHE_ANCHOR), the whole body moved, the limbs
## still thrashing; crawling (`now` CRAWL), all of a drift back against the
## way his head points and none of the rest (the gripping hand and his knees
## hold him; the reaching arm and the drawn knees would push him back), so
## each pull gains ground.
func _hold_in_place(now: int, fr: Basis) -> void:
	var mid := middle()
	if _anchor != Vector3.INF:
		var drift := Vector3(mid.x - _anchor.x, mid.y - _anchor.y, 0.0)
		var back := drift * WRITHE_ANCHOR
		if now == CRAWL:
			var head_way := Vector3(fr.y.x, fr.y.y, 0.0).normalized()
			back = head_way * minf(drift.dot(head_way), 0.0)
		for i in R.POINTS:
			pos[i] -= back
			old[i] -= back
		mid -= back
	_anchor = mid


## Going down: the arms toward where the chest will land, the head off it.
func _brace(fr: Basis) -> void:
	# (Once a hand is down the fall lands on it and the arms give.)
	var give := 1.0
	if hand_down_at >= 0.0:
		give = 1.0 - (age - hand_down_at) / BRACE_GIVE
		if give <= 0.0:
			return
	var up := fr.y
	var sh := (pos[R.SH_L] + pos[R.SH_R]) * .5
	var fall := (sh - old[R.SH_L].lerp(old[R.SH_R], .5)) / STEP
	if up.z > .9 or fall.z > -.2:
		return
	var feet := (pos[R.FOOT_L] + pos[R.FOOT_R]) * .5
	var lean := Vector3(sh.x - feet.x, sh.y - feet.y, 0.0)
	if lean.length() < 1e-3:
		lean = Vector3(fall.x, fall.y, 0.0)
	if lean.length() < 1e-4:
		return
	lean = lean.normalized()
	var floor_at := minf(feet.z, pos[R.HIP_L].z) - radius[R.FOOT_L]
	var tall := maxf(.2, sh.z - floor_at)
	var at := Vector3(sh.x, sh.y, floor_at) + lean * tall * .45
	brace_at = Vector3(at.x, at.y, floor_at)
	for arm in 2:
		var side := fr.x * radius[R.SH_L] * (-1.0 if arm == 0 else 1.0)
		_hand_to(fr, arm, brace_at + side, .97)
		var hand := R.HAND_L if arm == 0 else R.HAND_R
		_k[hand] *= give
		_k[hand - 1] *= give
	# The head off the fall.
	var away := fr.transposed() * -lean
	var h := held[R.HEAD]
	_want[R.HEAD] = (h.normalized() * .8 + away * .6).normalized() * h.length()
	_k[R.HEAD] *= 1.5


## Hand `arm` (0 left) toward world point `at`, as far as `reach` of the arm.
func _hand_to(fr: Basis, arm: int, at: Vector3, reach: float) -> void:
	var sh := R.SH_L if arm == 0 else R.SH_R
	var el := sh + 3 if arm == 0 else sh + 4
	var hand := el + 1
	if _stiff(sh):
		return
	var upper := rig.points[sh].distance_to(rig.points[el]) * size
	var fore := rig.points[el].distance_to(rig.points[hand]) * size
	var to := at - pos[sh]
	var far := minf(to.length(), (upper + fore) * reach)
	var d := to.normalized() if to.length() > 1e-5 else -fr.y
	var out := fr.x * (-1.0 if arm == 0 else 1.0)
	# The elbow where the arm folds to reach no further (out and back).
	var bend := sqrt(maxf(0.0, upper * upper - (far * .5) * (far * .5)))
	var bow := (out * .7 - fr.z * .3 - d * (out * .7 - fr.z * .3).dot(d)).normalized()
	var elbow := pos[sh] + d * far * .5 + bow * bend
	var tip := pos[sh] + d * far
	_want[el] = fr.transposed() * (elbow - pos[sh])
	_want[hand] = fr.transposed() * (tip - elbow)


## The thigh of leg `leg` drawn up toward the chest by `curl` (radians from
## standing) and the shin folded back under it.
func _curl(leg: int, curl: float) -> void:
	var knee := R.KNEE_L if leg == 0 else R.KNEE_R
	var foot := knee + 1
	if _stiff(R.HIP_L if leg == 0 else R.HIP_R):
		return
	# (Torso frame: the thigh swung ahead of straight down by `curl`, the
	# shin back behind it by as much again and more: the knee folded, the
	# foot back near the floor he lies on.)
	var thigh := Vector3(0.0, -cos(curl), sin(curl))
	var shin := Vector3(0.0, -cos(curl * .9), -sin(curl * .9))
	_want[knee] = thigh * _rest[knee].length()
	_want[foot] = shin * _rest[foot].length()
	_k[knee] = TONE * env * .7
	_k[foot] = TONE * env * .7


## Writhing: knees drawn up and let go, a hand on the wound, the head up,
## rocking side to side.
func _writhe(fr: Basis, t: float) -> void:
	for leg in 2:
		_curl(leg, .6 + .3 * sin(t * (2.1 + leg * .6) + leg * 1.9))
	if clutch_hand >= 0:
		var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
		_hand_to(fr, clutch_hand, hips + fr * wound, .95)
	var other := 1 - clutch_hand if clutch_hand >= 0 else 1
	var sh := pos[R.SH_L if other == 0 else R.SH_R]
	var sweep := fr.y * cos(t * 1.4) * .5 + fr.x * (-1.0 if other == 0 else 1.0) * .6 + fr.z * .4
	_hand_to(fr, other, sh + sweep.normalized() * .5 * size, .9)
	_want[R.HEAD] = Basis(Vector3(1.0, 0.0, 0.0), .35 + .25 * sin(t * 1.7)) * _rest[R.HEAD]
	_k[R.HEAD] = TONE * env
	_roll(fr, .005 * sin(t * 2.6))


## The torso turned about its own length by `by` (radians) on the floor:
## a shoulder and a hip shoving off it.
func _roll(fr: Basis, by: float) -> void:
	var down := 0
	for i: int in [R.SH_L, R.SH_R, R.HIP_L, R.HIP_R, R.BACK, R.BELLY]:
		down += _touch[i] if _touch.size() > i else 0
	if down < 2 or absf(by) < 1e-5:
		return
	var turn := Basis(fr.y, by * env)
	var mid := middle()
	for i: int in [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R, R.BELLY, R.BACK, R.HEAD]:
		pos[i] = mid + turn * (pos[i] - mid)


## Trying to get up (face down): hands under the shoulders gripping the
## floor, the arms pushing him up, knees drawn; then the tone goes.
func _get_up(fr: Basis, t: float) -> void:
	var phase := fmod(t, 1.7)
	var down_way := Vector3(0.0, 0.0, -1.0)
	var head_way := Vector3(fr.y.x, fr.y.y, 0.0).normalized()
	for arm in 2:
		var sh := R.SH_L if arm == 0 else R.SH_R
		var hand := R.HAND_L if arm == 0 else R.HAND_R
		var arm_len := (
			(
				rig.points[sh].distance_to(rig.points[hand - 1])
				+ rig.points[hand - 1].distance_to(rig.points[hand])
			)
			* size
		)
		if phase < .5:
			_hand_to(fr, arm, pos[sh] + down_way * arm_len * .7 + head_way * .05, .8)
		elif phase < 1.35:
			if _touch.size() > hand and _touch[hand] and not grips.has(hand):
				grips[hand] = pos[hand]
			var reach := lerpf(.75, 1.0, clampf((phase - .5) / .6, 0.0, 1.0))
			_hand_to(fr, arm, pos[sh] + down_way * arm_len * 1.2, reach)
			_k[hand] = TONE * env * 2.2
			_k[hand - 1] = TONE * env * 2.2
		else:
			grips.erase(hand)
	for leg in 2:
		_curl(leg, 1.0 if phase > .4 and phase < 1.35 else .45)


## Crawling (face down): a hand reaches ahead, grips, the arm pulls him on
## to it; then the other.
func _crawl(fr: Basis, t: float) -> void:
	var n := floori(t / CRAWL_CYCLE)
	var u := fmod(t, CRAWL_CYCLE) / CRAWL_CYCLE
	var arm := n % 2
	var head_way := Vector3(fr.y.x, fr.y.y, 0.0).normalized()
	var sh := R.SH_L if arm == 0 else R.SH_R
	var hand := R.HAND_L if arm == 0 else R.HAND_R
	var other := R.HAND_R if arm == 0 else R.HAND_L
	var arm_len := (
		(
			rig.points[sh].distance_to(rig.points[hand - 1])
			+ rig.points[hand - 1].distance_to(rig.points[hand])
		)
		* size
	)
	# The floor he lies on (under the torso's lowest ball): the reach is for
	# it, however high his chest lies off it (a long torso, a belly, gear
	# under him), not a set drop from the shoulder.
	var floor_at := INF
	for i: int in [R.SH_L, R.SH_R, R.BELLY, R.BACK, R.HIP_L, R.HIP_R]:
		floor_at = minf(floor_at, pos[i].z - radius[i])
	var on_floor := Vector3(0.0, 0.0, floor_at + radius[hand] * .5 - pos[sh].z)
	if u < .45:
		grips.erase(hand)
		_hand_to(fr, arm, pos[sh] + head_way * arm_len * CRAWL_REACH + on_floor, 1.0)
		_k[hand] = TONE * env * 1.5
	else:
		if _touch.size() > hand and _touch[hand] and not grips.has(hand):
			grips[hand] = pos[hand]
		if grips.has(hand):
			# Gripping: the arm pulls him on to the hand (the other lets go
			# only now: it held him while this one reached, so he does not
			# slide back between pulls).
			grips.erase(other)
			_hand_to(fr, arm, pos[sh] + head_way * arm_len * .25 + Vector3(0.0, 0.0, -.1), .45)
			_k[hand] = TONE * env * CRAWL_PULL
			_k[hand - 1] = TONE * env * CRAWL_PULL
		else:
			# Not down yet: the hand comes down where it is, ahead.
			var at := Vector3(pos[hand].x, pos[hand].y, pos[sh].z) + on_floor
			_hand_to(fr, arm, at, 1.0)
			_k[hand] = TONE * env * 1.5
	for leg in 2:
		_curl(leg, .15 + .15 * sin(t * TAU / CRAWL_CYCLE + leg * PI))
	_want[R.HEAD] = Basis(Vector3(1.0, 0.0, 0.0), .4) * _rest[R.HEAD]
	_k[R.HEAD] = TONE * env


## The muscles: the dead body's own (Ragdoll's, the pose it died in going
## slack), then the living ones toward this step's places.
func _muscles(tone: float, ease: float) -> void:
	super._muscles(tone, ease)
	if not muscles or held.size() != R.POINTS or env < .005:
		return
	var fr := LiveBody._torso_frame(pos)
	var neck := (pos[R.SH_L] + pos[R.SH_R]) * .5
	for i in R.POINTS:
		var par: int = LiveBody.PARENT_OF[i]
		var k := _k[i]
		if par == -1 or k <= 0.0:
			continue
		var from := neck if par == -2 else pos[par]
		var want := from + fr * _want[i]
		var d := (want - pos[i]).limit_length(MUSCLE_MOST * size / maxf(k, .05))
		var wi := inv_mass[i]
		if par == -2:
			var wp := (inv_mass[R.SH_L] + inv_mass[R.SH_R]) * .5
			var fix := d * (minf(k, .9) / (wi + wp))
			pos[i] += fix * wi
			pos[R.SH_L] -= fix * wp * .5
			pos[R.SH_R] -= fix * wp * .5
			work += fix.length() * (wi + wp)
		else:
			var wp := inv_mass[par]
			var fix := d * (minf(k, .9) / (wi + wp))
			pos[i] += fix * wi
			pos[par] -= fix * wp
			work += fix.length() * (wi + wp)


## Knees forward only (Ragdoll's); then the gripping hands held where they
## grip.
func _hinges() -> void:
	super._hinges()
	for i: int in grips:
		var at: Vector3 = grips[i]
		pos[i] = at


## The wreck pieces (Ragdoll's), then the vehicle's front while it is there.
func _on_boxes(world: LevelData, touching: PackedByteArray) -> void:
	super._on_boxes(world, touching)
	if age > hood_until or hood_until < 0.0:
		return
	var front := hood_from + hood_dir * hood_speed * age
	var across := Vector2(-hood_dir.y, hood_dir.x)
	var step := hood_dir * hood_speed * STEP
	for i in mini(pos.size(), R.POINTS):
		var p := pos[i]
		var r := radius[i]
		var rel := Vector2(p.x - front.x, p.y - front.y)
		var u := rel.dot(hood_dir)
		var s := rel.dot(across)
		if absf(s) > hood_w * .5 + r or u > r or u < -hood_len - r:
			continue
		var h := p.z - hood_floor
		if h - r > hood_top:
			continue
		var was := old[i].z - hood_floor
		if was - r >= hood_top - .05 or u < -r * 2.0:
			# On its top: held up by it and carried along a share (it rolls
			# up the hood rather than skates).
			pos[i] = Vector3(p.x, p.y, hood_floor + hood_top + r)
			var run := Vector2(p.x - old[i].x, p.y - old[i].y)
			var keep := run.lerp(step, .35)
			old[i] = Vector3(p.x - keep.x, p.y - keep.y, minf(old[i].z, pos[i].z))
			touching[i] = 1
		else:
			# In front of its face: swept along with it.
			var out := r - u
			p += Vector3(hood_dir.x, hood_dir.y, 0.0) * out
			pos[i] = p
			var run := Vector2(p.x - old[i].x, p.y - old[i].y)
			if run.dot(hood_dir) < step.length():
				var fix := hood_dir * (step.length() - run.dot(hood_dir))
				old[i] -= Vector3(fix.x, fix.y, 0.0)
