## A body's own rim (pass 15, effects.cfg [rim]): a hostile hand awake wears a
## warm edge along his silhouette, stronger far off so a far hand reads; the
## animals a cool one. The actor shader draws it (`own_rim`, `own_rim_reach`) with
## LIGHTS AND GLOW only (QUALITY LOW drops it), under a hit's wash and a
## wind-up's amber, and in place of the moon's rim by night. Looks only: it
## reads the hand, never play's dice; nothing is kept but when each model's
## rim came up (ActorView.rim_since), for its fade.
class_name ActorRim
extends RefCounted

static var _version := -1
static var _awake := Color(1, .5, .18, .3)
static var _critter := Color(.62, .78, 1, .24)
static var _reach := Vector4(.75, 3.0, 15.0, .6)
static var _fade := .3
static var _critters := {}


static func _read() -> void:
	if _version == Effects.version:
		return
	_version = Effects.version
	var awake: Color = Effects.num("rim", "awake", Color(1, .5, .18))
	var near: float = Effects.num("rim", "near", .3)
	_awake = Color(awake.r, awake.g, awake.b, near)
	var cool: Color = Effects.num("rim", "critter", Color(.62, .78, 1))
	var cool_k: float = Effects.num("rim", "critter_strength", .24)
	_critter = Color(cool.r, cool.g, cool.b, cool_k)
	var far: float = Effects.num("rim", "far", .75)
	var near_at: float = Effects.num("rim", "near_at", 3.0)
	var far_at: float = Effects.num("rim", "far_at", 15.0)
	var fog_cut: float = Effects.num("rim", "fog_cut", .6)
	_reach = Vector4(far, near_at, far_at, fog_cut)
	_fade = Effects.num("rim", "fade", .3)
	_critters = {}
	var kinds: Array = Effects.num("rim", "critters", [])
	for kind: Variant in kinds:
		_critters[str(kind)] = true


## The rim `who` wears (rgb, a how much up close; a 0: none), without the fade.
static func wanted(who: Object) -> Color:
	_read()
	var e: Enemy = who as Enemy
	if e == null or not e.alive or e.dormant:
		return Color(0, 0, 0, 0)
	if e.hostile:
		return _awake if e.alerted else Color(0, 0, 0, 0)
	if _critters.has(e.kind):
		# The far reach is a hand's: an animal's rim stays as it is up close.
		return _critter
	return Color(0, 0, 0, 0)


## The rim for model `view` showing `who` now. One that comes up while the
## model is in sight (a hand waking) fades in over `fade` seconds; a body
## first seen with one has it whole.
static func of(view: ActorView, who: Object) -> Color:
	var want := wanted(who)
	if want.a <= 0.0:
		view.rim_since = -1.0
		view.rim_off_seen = true
		return want
	if view.rim_since < 0.0 or view.rim_since > view.shown_at:
		view.rim_since = view.shown_at if view.rim_off_seen else view.shown_at - _fade
	var up := clampf((view.shown_at - view.rim_since) / maxf(_fade, .001), 0.0, 1.0)
	return Color(want.r, want.g, want.b, want.a * up)


## How the rim of `who` reaches far off (the shader's `own_rim_reach`): a hand's
## grows with distance, an animal's does not.
static func reach(who: Object) -> Vector4:
	_read()
	var e: Enemy = who as Enemy
	if e != null and e.hostile:
		return _reach
	return Vector4(_critter.a, _reach.y, _reach.z, _reach.w)
