## The regular hands' looks as a fight wears on them (tools/art/build_enemy_actors.gd
## makes the cels): the first beat of a wind-up shows `<kind>_wind` (drawn back,
## racking, revving, rearing; the rest of it is the usual `_aim`), and below half
## health every living cel gives way to its hurt copy, `<kind>_hurt_<cel>`
## (bloodied, torn, limping; tin dented and sparking). A cel without a variant
## keeps its name, so a kind drawn before the hurt pass looks as it did. Bosses
## have their own (BossLooks). Looks only: nothing here changes play.
class_name EnemyLooks
extends RefCounted

## Share of health left at or under which the hurt set shows.
const HURT_AT := .5
## The wind-up cel holds while more than this share of the wind-up is left.
const WIND_SHARE := .5

## Each winding-up hand's wind-up as it started (by instance id).
static var _wound := {}
## By kind and cel name, what cel() needs (_row()), for an index of this size.
static var _rows := {}
static var _index_size := -1


## The cel a regular enemy shows instead of `name` (one of its own `<kind>_...` cels).
static func cel(e: Enemy, name: String) -> String:
	if Assets.shared_index.size() != _index_size:
		# The pictures known changed (a chapter's pack came in): look again.
		_index_size = Assets.shared_index.size()
		_rows = {}
	if _index_size == 0:
		return name
	if not _rows.has(e.kind):
		_rows[e.kind] = {}
	var by_kind: Dictionary = _rows[e.kind]
	if not by_kind.has(name):
		by_kind[name] = _row(e.kind, name)
	var row: Array = by_kind[name]
	if row.is_empty():
		return name
	var id := e.get_instance_id()
	var wind := false
	if row[0]:
		var was: float = _wound.get(id, 0.0)
		var full := maxf(was, e.windup)
		_wound[id] = full
		wind = e.windup > full * WIND_SHARE and row[3] != ""
	elif e.windup <= 0.0 and not _wound.is_empty():
		_wound.erase(id)
	var hurt := e.hp <= e.max_hp * HURT_AT
	if wind:
		return row[4] if hurt and row[4] != "" else row[3]
	return row[2] if hurt and row[2] != "" else row[1]


## What cel() needs to know of `name` for `kind`, worked out once: [the cel is
## the aim, its own name, its hurt copy, the wind-up cel, the wind-up's hurt
## copy] ("" where there is no such picture), or [] when it is not the kind's.
static func _row(kind: String, name: String) -> Array:
	if not name.begins_with(kind + "_"):
		return []
	var rest := name.substr(kind.length() + 1)
	var wind := kind + "_wind"
	var hurt := "%s_hurt_%s" % [kind, rest]
	var hurt_wind := "%s_hurt_wind" % kind
	var has: Dictionary = Assets.shared_index
	return [
		rest == "aim",
		kind + "_" + rest,
		hurt if has.has(hurt) else "",
		wind if has.has(wind) else "",
		hurt_wind if has.has(hurt_wind) else "",
	]


## What it looks like this frame. `into` (a sprite fresh from Game.pooled(),
## every field at its default) is filled in and handed back instead of a new one.
static func sprite(
	e: Enemy, observer: Variant = null, relieved := false, now := -1.0, into: View.Sprite = null
) -> View.Sprite:
	if e.dormant:
		return null
	var out := into if into != null else View.Sprite.new()
	out.x = e.x
	out.y = e.y
	out.flip = e.face_left
	if not e.alive:
		if e.explosive or e.brain == "saucer" or e.brain == "skeeter":
			return null
		var fallen := now - e.died_at
		var cels := 5 if Enemy.TURNS.has(e.kind) else 2 if Enemy.FALLS.has(e.kind) else 0
		var span := Enemy.DEATH_TIME if cels == 5 else Enemy.DEATH_TIME * .5
		var worn := Variants.stem(e.kind)
		if cels > 0 and e.died_at >= 0.0 and now >= e.died_at and fallen < span:
			var cel := Enemy.cel_name(worn + "_die", mini(cels - 1, int(fallen / span * cels)))
			out.image = Variants.look(e, cel)
			out.height = e.height * e.variant
			out.z = e.z + e.toss
			return out
		out.image = Variants.look(e, Enemy.cel_name(worn, "down"))
		out.height = e.height * Enemy.DOWN_SHARE.get(e.brain, .25)
		out.z = e.toss - .07
		return out
	var turns := Enemy.TURNS.has(e.kind)
	var recover := e.recovery_time(relieved) if e.recovery > 0.0 else 0.0
	var release := minf(.14, recover * .53)
	var frame: Variant = 0
	if e.hostile and (e.stun > 0.0 or (e.flinch > 0.0 and e.windup <= 0.0)):
		frame = "pain"
	elif recover > 0.0 and e.recovery > recover - release:
		frame = "fire"
	elif e.windup > 0.0:
		frame = "aim"
	elif recover > 0.0 and turns:
		frame = "recover"
	elif e.brain == "saucer" or e.brain == "skeeter" or e.brain == "lantern":
		frame = int(e.pose * (16 if e.brain == "skeeter" else 5)) % 3 - 1
	elif e.stun > 0.0 or e.brain == "bessie" or e.pose - e.last_stride > .18:
		frame = 0
	elif turns:
		# Four-beat walk: contact, passing, contact, passing.
		frame = Enemy.WALK_CELS[posmod(int(floorf(e.gait / (PI * .5))), 4)]
	else:
		frame = int(roundf(sin(e.gait)))
	if e.mind != null and not e.alerted and frame is int and frame == 0:
		frame = IdleLife.frame(e, observer)
	var worn := Variants.stem(e.kind)
	var stem: String = worn if e.kind != "maw" else worn + ShipAliens.skin(e)
	var walking: bool = frame is String and str(frame).begins_with("w")
	var plain: bool = frame is int and frame >= -1 and frame <= 1
	if observer != null and (plain or walking) and turns:
		var seen_x: float = observer[0]
		var seen_y: float = observer[1]
		var bearing := atan2(seen_y - e.y, seen_x - e.x)
		var relative := Enemy.angle_delta(bearing, e.angle)
		var direction := mini(4, int(absf(relative) / (PI / 4.0) + .5))
		if direction:
			stem += Enemy.HEADINGS[direction]
		out.flip = relative < 0.0 and direction < 4
	if (
		frame is int
		and frame == 0
		and stem == worn
		and Enemy.FIDGETS.has(e.kind)
		and not e.alerted
		and fmod(e.pose + e.x * .37 + e.y * .13, 5.2) > 4.68
	):
		frame = "fidget"
	var look := Enemy.cel_name(stem, frame) if e.held_cel == "" else e.held_cel
	var boss := Enemy.BOSS_TITLES.has(e.kind)
	if boss:
		look = BossLooks.cel(e, look)
	elif e.hostile:
		look = cel(e, look)
	out.image = Variants.look(e, look)
	# A cow going over: her picture squashed by the lean, never below .3.
	out.height = e.height * e.variant * maxf(.3, e.squash)
	out.z = e.z
	out.body = e.hostile
	out.hurt = e.hit_flash
	if e.windup > 0.0 and boss:
		# A boss winding up glows in a quickening beat (boss_kit.gd).
		out.hurt = maxf(e.hit_flash, BossKit.pulse(e))
	return out
