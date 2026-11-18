## What a wreck piece is made of, with its form's share: data/tuning/wreck.cfg
## [stuff.<name>] (breakables.cfg's `stuff` names; one not there is wood;
## `like` starts from another's numbers) and [form.<name>] (board, stave,
## ring, disc, can, shard, chunk, sheet, clump: shares of those). Its
## weight, bounce, grip, the spin and slide it loses on the floor, a flat
## face's air drag, its sounds and how hard a knock cracks it; and the
## knocks' push on any point by [impact.<kind>] (push_for: a wreck piece's
## or a ragdoll's ball alike). Read once, kept. Looks only.
class_name WreckStuff
extends RefCounted

const PATH := "res://data/tuning/wreck.cfg"

var name := "wood"
var dense := 500.0
var bounce := WreckPhysics.E_FLOOR
var grip := WreckPhysics.MU
var roll := WreckPhysics.GROUND_SPIN
var slide := WreckPhysics.GROUND_SLIDE
var drag := 0.0
var cue := "debris_settle"
var cue_hard := ""
var spin_cue := ""
## Other takes of `cue` (dealt at random with it, for `cue_hard` too when
## it is the same).
var alts: Array = []
var loud := 5.0
var crack := 0.0
var burst := 1.0
var sinks := false

## The tuning, read once, and the stuffs made for each "stuff|form" asked.
static var _cfg: ConfigFile
static var _made := {}
## Each [impact.<kind>]'s numbers, read once: reach, along, out, lift,
## spread, spin, most, hidden (REACH ... HIDDEN).
static var _kinds := {}
const REACH := 0
const ALONG := 1
const OUT := 2
const LIFT := 3
const SPREAD := 4
const SPIN := 5
const MOST := 6
const HIDDEN := 7


## The stuff `stuff` with the form `form`'s shares (wreck.cfg; a stuff not
## there is wood, a form not there a plain box). Made once each.
static func of(stuff: String, form := "") -> WreckStuff:
	var key := stuff + "|" + form
	var kept: WreckStuff = _made.get(key)
	if kept != null:
		return kept
	if _cfg == null:
		_cfg = Tuning.file(PATH)
	var made := WreckStuff.new()
	var section := "stuff." + stuff
	if not _cfg.has_section(section):
		section = "stuff.wood"
	made.name = stuff if _cfg.has_section("stuff." + stuff) else "wood"
	var chain: Array[String] = [section]
	while chain.size() < 4 and _cfg.has_section_key(chain[-1], "like"):
		chain.append("stuff." + str(_cfg.get_value(chain[-1], "like")))
	chain.reverse()
	for sec: String in chain:
		made.dense = _cfg.get_value(sec, "dense", made.dense)
		made.bounce = _cfg.get_value(sec, "bounce", made.bounce)
		made.grip = _cfg.get_value(sec, "grip", made.grip)
		made.roll = _cfg.get_value(sec, "roll", made.roll)
		made.slide = _cfg.get_value(sec, "slide", made.slide)
		made.cue = _cfg.get_value(sec, "cue", made.cue)
		made.cue_hard = _cfg.get_value(sec, "cue_hard", made.cue_hard)
		made.spin_cue = _cfg.get_value(sec, "spin_cue", made.spin_cue)
		made.alts = _cfg.get_value(sec, "alts", made.alts)
		made.loud = _cfg.get_value(sec, "loud", made.loud)
		made.crack = _cfg.get_value(sec, "crack", made.crack)
		made.burst = _cfg.get_value(sec, "burst", made.burst)
		made.sinks = _cfg.get_value(sec, "sinks", made.sinks)
	var shares := "form." + form
	if form != "" and _cfg.has_section(shares):
		var bounce: float = _cfg.get_value(shares, "bounce", 1.0)
		var grip: float = _cfg.get_value(shares, "grip", 1.0)
		var roll: float = _cfg.get_value(shares, "roll", 1.0)
		var slide: float = _cfg.get_value(shares, "slide", 1.0)
		made.bounce *= bounce
		made.grip *= grip
		made.roll *= roll
		made.slide *= slide
		made.drag = _cfg.get_value(shares, "drag", 0.0)
	if made.cue_hard == "":
		made.cue_hard = made.cue
	_made[key] = made
	return made


## One of wreck.cfg's [impact.<kind>] or [knock] numbers.
static func tuned(section: String, key: String, fallback: float) -> float:
	if _cfg == null:
		_cfg = Tuning.file(PATH)
	return _cfg.get_value(section, key, fallback)


## A knock's push on a point `point` (of something whose middle is `middle`)
## from a hit at `at` going `way` (a unit vector; ZERO for a blast, which
## pushes straight out) of `strength`, by wreck.cfg's [impact.<kind>]: "shot"
## (strength an impulse), "break" (a thing's pieces as it comes apart),
## "blast", "kick" (a boot, a hand, the hound walking through), "ram" (a
## vehicle). Its way is along the hit, out from the hit point and up by the
## kind's shares, turned at random by `spread` (`dice`: the caller's own,
## looks; null none); its size the strength by how near the point is (half
## at the kind's `reach`), times `hidden` when `seen` is false. Returns the
## push as a velocity (an impulse for a shot: divide by the weight), ZERO
## when too faint. General: a wreck piece's point (impact()) or a ragdoll's
## ball alike.
## [impact.<kind>]'s numbers (REACH, ALONG... HIDDEN), read once.
static func kind_of(kind: String) -> PackedFloat64Array:
	var kept: Variant = _kinds.get(kind)
	if kept != null:
		var numbers: PackedFloat64Array = kept
		return numbers
	var sec := "impact." + kind
	var made := PackedFloat64Array(
		[
			tuned(sec, "reach", .3),
			tuned(sec, "along", 1.0),
			tuned(sec, "out", .5),
			tuned(sec, "lift", .5),
			tuned(sec, "spread", .3),
			tuned(sec, "spin", 4.0),
			tuned(sec, "most", 8.0),
			tuned(sec, "hidden", 1.0)
		]
	)
	_kinds[kind] = made
	return made


static func push_for(
	kind: String,
	at: Vector3,
	way: Vector3,
	strength: float,
	point: Vector3,
	middle: Vector3,
	seen := true,
	dice: RandomNumberGenerator = null
) -> Vector3:
	var k := kind_of(kind)
	var reach := k[REACH]
	var d := point.distance_to(at)
	if d > reach * 6.0:
		return Vector3.ZERO
	var share := 1.0 / (1.0 + (d / reach) * (d / reach))
	if not seen:
		share *= k[HIDDEN]
	if share < .02:
		return Vector3.ZERO
	var from := middle - at
	from = from / maxf(from.length(), .001)
	var push := way * k[ALONG] + from * k[OUT] + Vector3(0.0, 0.0, k[LIFT])
	if dice != null:
		push += (
			Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), dice.randf() * .5)
			* k[SPREAD]
		)
	if push.length_squared() < 1e-6:
		push = Vector3(0.0, 0.0, 1.0)
	return push.normalized() * strength * share
