## COUNTY RUN's numbers and words (data/tuning/county.json, CLAUDE.md "County
## Run"): the three maps and their enemy mix, the XP curve, the spawner, the
## starting kit, each weapon's card, every upgrade, perk and milestone. Read
## once and kept; a run started from the project folder after the file
## changed reads it again (Tuning.watch's clock is the file's own time).
class_name CountyData
extends RefCounted

const PATH := "res://data/tuning/county.json"
## The levels COUNTY RUN plays on (tools/levels/county_*_plan.gd).
const MAP_IDS := ["county_hickston", "county_quarry", "county_bayou"]
## The weapon kinds a milestone can need (county.json "needs").
const EXPLOSIVE := "explosive"
const MELEE := "melee"

static var _data := {}
static var _stamp := -1
static var _asked := 0


static func all() -> Dictionary:
	# The file's time is asked at most once a second (it is read on every
	# tick of a run, many times).
	var now := Time.get_ticks_msec()
	if not _data.is_empty() and now - _asked < 1000:
		return _data
	_asked = now
	var stamp := FileAccess.get_modified_time(PATH)
	if _data.is_empty() or stamp != _stamp:
		_stamp = stamp
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func section(name: String) -> Dictionary:
	var out = all().get(name, {})
	return out if out is Dictionary else {}


static func maps() -> Array:
	var out = all().get("maps", [])
	return out if out is Array else []


## A map's entry ({} when the id is not one of them).
static func map(level_id: String) -> Dictionary:
	for m in maps():
		if m is Dictionary and String(m.get("id", "")) == level_id:
			return m
	return {}


static func number(group: String, key: String, fallback := 0.0) -> float:
	return float(section(group).get(key, fallback))


## A weapon's entry by its index in weapons.cfg ({} when the run never offers it).
static func weapon(gun: int) -> Dictionary:
	if gun < 0 or gun >= Weapons.COUNT:
		return {}
	var out = section("weapons").get(String(Weapons.NAMES[gun]), {})
	return out if out is Dictionary else {}


## The weapons a run can hand out, by index, in the file's order.
static func roster() -> Array:
	var out: Array = []
	for name: String in section("weapons"):
		var gun := Weapons.NAMES.find(name)
		if gun >= 0:
			out.append(gun)
	return out


static func kind_of(gun: int) -> String:
	return String(weapon(gun).get("kind", ""))


static func upgrade(id: String) -> Dictionary:
	var out = section("upgrades").get(id, {})
	return out if out is Dictionary else {}


static func perk(id: String) -> Dictionary:
	var out = section("perks").get(id, {})
	return out if out is Dictionary else {}


static func milestone(id: String) -> Dictionary:
	var out = section("milestones").get(id, {})
	return out if out is Dictionary else {}


## The upgrades a weapon can take (county.json), those whose `kinds` allow it.
static func upgrades_for(gun: int) -> Array:
	var out: Array = []
	var kind := kind_of(gun)
	for id in weapon(gun).get("upgrades", []):
		var spec := upgrade(String(id))
		if spec.is_empty():
			continue
		var kinds = spec.get("kinds", [])
		if kinds is Array and not kinds.is_empty() and not kinds.has(kind):
			continue
		out.append(String(id))
	return out


## The XP from level `level` to the next.
static func xp_to_next(level: int) -> int:
	var x := section("xp")
	var n := float(maxi(0, level - 1))
	return maxi(
		1,
		roundi(
			(
				float(x.get("first", 5))
				+ float(x.get("step", 3)) * n
				+ float(x.get("curve", .1)) * n * n
			)
		)
	)


## A gun's name for a card, short enough for the HUD's slot boxes too.
static func gun_name(gun: int) -> String:
	if gun < 0 or gun >= Weapons.COUNT:
		return "EMPTY"
	var label := String(Weapons.LABELS[gun])
	var cut := label.find(" [")
	return label.substr(0, cut) if cut > 0 else label


## The HUD slot's name (county.json "short", else the label cut short).
static func short_name(gun: int) -> String:
	var short := String(weapon(gun).get("short", ""))
	return short if short != "" else gun_name(gun).substr(0, 9)


## A card's words with its numbers filled in: {v} the value at `rank`, {b}
## and {e} a spec's bonus and edge, {gun} the weapon's name.
static func fill(text: String, spec: Dictionary, rank: int, gun := -1) -> String:
	var per := float(spec.get("per", 0.0))
	var v := per * maxf(1.0, float(rank))
	# "unit": "dec" a number with one place (seconds, steps), else a share
	# below 1 is a percentage and a whole number is itself.
	var shown := ""
	if String(spec.get("unit", "")) == "dec":
		shown = "%.1f" % v
	elif absf(per) < 1.0 and per != 0.0:
		shown = "%d" % roundi(absf(v) * 100.0)
	else:
		shown = "%d" % roundi(v)
	var out := text.replace("{v}", shown)
	out = out.replace("{b}", "%d" % roundi(float(spec.get("bonus", 0.0)) * rank * 100.0))
	out = out.replace("{e}", "%d" % roundi(float(spec.get("edge", 0.0)) * rank * 100.0))
	out = out.replace("{gun}", gun_name(gun))
	return out


## The ammo a weapon comes with on a card: "6 + 36 ROUNDS", "NO AMMO".
static func ammo_text(gun: int) -> String:
	var kind := kind_of(gun)
	if kind == MELEE:
		return "NO AMMO NEEDED"
	var reserve := int(weapon(gun).get("reserve", Weapons.PICKUP_RESERVE[gun]))
	var loaded := int(Weapons.CAPACITY[gun])
	var unit := "ROUNDS"
	match gun:
		Weapons.SHOTGUN:
			unit = "SHELLS"
		Weapons.CROSSBOW:
			unit = "STICKS"
		Weapons.ROCKET:
			unit = "ROCKETS"
		Weapons.KEG:
			unit = "KEGS"
		Weapons.COW:
			unit = "COWS"
		Weapons.BOWLING:
			unit = "BALLS"
		Weapons.RIPSAW:
			unit = "BLADES"
		Weapons.TEAT:
			unit = "SQUIRTS"
	if loaded > 0:
		return "COMES WITH %d + %d %s" % [loaded, reserve, unit]
	return "COMES WITH %d %s" % [reserve, unit]


## The campaign chapter a COUNTY RUN map is built on ("county_quarry" ->
## "quarry"), whose music and enemy pictures it uses; any other level itself.
static func base_of(level_id: String) -> String:
	return level_id.substr(7) if level_id.begins_with("county_") else level_id
