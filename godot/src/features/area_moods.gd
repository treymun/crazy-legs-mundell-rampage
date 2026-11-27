## Moods by area (pass 16, LOOKS), all looks: a map that opts in names a mood
## for the whole level (LevelData.mood) or for a district (LevelData
## .area_moods), each a preset of effects.cfg ([mood.<name>]: fog, grade, fog
## banks, how much rain is drawn, crows and fireflies). The 3D view asks now()
## for the frame's values (world_view.gd _effects) and the view eases from one
## mood to the next over [moods] blend seconds as the player crosses into a
## district with another; a jump of more than [moods] snap cells, or a frame
## with the clock where it was (a picture tour moving the player), takes the
## new one at once. What a mood leaves out is the level's own ([level.<id>]).
##
## A level that names no mood (every chapter) makes this do nothing: now()
## returns {} and the view reads the level's own values as it always did.
## Nothing to save, nothing carried; no tick (it is asked by the view).
class_name AreaMoodsFeature
extends GameFeature

## The keys a mood blends, with what a level that sets none has (the view's
## own defaults, world_view.gd _effects; rain is a share of the weather's).
const KEYS := {
	"fog": Color(0, 0, 0),
	"fog_start": 1000.0,
	"fog_full": 2000.0,
	"fog_most": 0.0,
	"grade": Color(1, 1, 1),
	"fog_banks": 0.0,
	"rain": 1.0,
	"crows": false,
	"fireflies": false,
}

## Whether the level names any mood (else everything here is idle).
var active := false
## The district the view stands in, and the values eased from, to and now.
var _district := -1
var _from := {}
var _to := {}
var current := {}
## When the ease began (game.clock), and the last frame's clock and place.
var _start := 0.0
var _clock := -1.0
var _at := Vector2(-1000, -1000)


func id() -> String:
	return "moods"


func attach() -> void:
	var lv := game.level
	active = (
		(lv.mood != "" and Effects.MOODS.has(lv.mood))
		or lv.area_moods.values().any(func(m: Variant) -> bool: return Effects.MOODS.has(str(m)))
	)


## The mood values for a viewer at (x, y) at `clock`: {} when the level has
## none (the caller keeps the level's own), else every key of KEYS.
func now(x: float, y: float, clock: float) -> Dictionary:
	if not active:
		return {}
	var lv := game.level
	var c := clampi(int(y), 0, lv.height - 1) * lv.width + clampi(int(x), 0, lv.width - 1)
	var district: int = lv.area[c] if c < lv.area.size() else 0
	var here := Vector2(x, y)
	var snap: float = Effects.MOOD_BLEND.get("snap", 3.0)
	var jumped := (
		_clock < 0.0 or clock < _clock or here.distance_to(_at) > snap or (clock == _clock)
	)
	if district != _district:
		_district = district
		_to = values_for(district)
		if jumped:
			_from = _to
			_start = clock - 1000.0
		else:
			_from = current.duplicate() if not current.is_empty() else _to
			_start = clock
	_clock = clock
	_at = here
	var blend: float = Effects.MOOD_BLEND.get("blend", 1.5)
	var t := clampf((clock - _start) / maxf(blend, .001), 0.0, 1.0)
	current = mix(_from, _to, t * t * (3.0 - 2.0 * t))
	return current


## The values a district shows: its own mood over the level's mood over the
## level's own effects.cfg values (every key of KEYS).
func values_for(district: int) -> Dictionary:
	var lv := game.level
	var out := {}
	var named: String = lv.area_moods.get(district, lv.mood)
	for key: String in KEYS:
		var own: Variant = Effects.mood(lv.id, key, KEYS[key])
		var level_wide: Variant = Effects.preset(lv.mood, key, own)
		var v: Variant = Effects.preset(named, key, level_wide)
		if KEYS[key] is float:
			var number: float = v
			out[key] = number
		else:
			out[key] = v
	return out


## The last frame's value of `key` (what other looks read: ambient's crows and
## fireflies, the gun's light), or `fallback` when no mood is showing.
func value(key: String, fallback: Variant) -> Variant:
	if not active or current.is_empty():
		return fallback
	return current.get(key, fallback)


## `a` eased toward `b` by t (0 to 1): colours and numbers in between, a flag
## taking b's past half way.
static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	if t >= 1.0:
		return b
	var out := {}
	for key: String in b:
		var to: Variant = b[key]
		var from: Variant = a.get(key, to)
		if to is Color and from is Color:
			var ca: Color = from
			var cb: Color = to
			out[key] = ca.lerp(cb, t)
		elif to is float and from is float:
			var fa: float = from
			var fb: float = to
			out[key] = lerpf(fa, fb, t)
		else:
			out[key] = to if t >= .5 else from
	return out
