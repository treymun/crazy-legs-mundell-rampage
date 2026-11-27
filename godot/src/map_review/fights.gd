## The fights along a level's way (MapReview): hands bunched by fight_link
## cells on about one floor make a fight; the way meets it at the first step
## within fight_near of one of them. Then, fight by fight in the order the way
## meets them:
## - ammo: the damage the player carries in (the kit, rounds and guns picked
##   up within ammo_reach of the way, hit_share of it landing, drops from the
##   fights before at drop_share) against the hands' health. A boss's arena
##   is its own design and left out;
## - cover: the walk in from where the hands first see it (within
##   cover_look) to the way's nearest step, and how long it runs in their
##   sight with nothing solid within cover_reach cells (a wall, a fixture, a
##   piece).
class_name MapFights
extends RefCounted

const L := preload("res://src/map_review/review_lines.gd")
const NUMBERS: Array[String] = [
	"NO",
	"ONE",
	"TWO",
	"THREE",
	"FOUR",
	"FIVE",
	"SIX",
	"SEVEN",
	"EIGHT",
	"NINE",
	"TEN",
	"ELEVEN",
	"TWELVE"
]


static func words(count: int) -> String:
	return NUMBERS[count] if count < NUMBERS.size() else str(count)


## The fights: {hands: [index into r.hands], centre: Vector3, hp, boss,
## meet: the step the way meets it (-1: never), closest: the way's nearest
## step}, in the order the way meets them (those it never meets last).
static func find(r: MapReview) -> Array[Dictionary]:
	var link := L.num("fight_link")
	var floor_gap := L.num("fight_floor")
	var group := PackedInt32Array()
	group.resize(r.hands.size())
	group.fill(-1)
	var count := 0
	for i in r.hands.size():
		if group[i] >= 0:
			continue
		group[i] = count
		var queue: Array[int] = [i]
		while not queue.is_empty():
			var a: int = queue.pop_back()
			var pa: Vector3 = r.hands[a]["at"]
			for b in r.hands.size():
				if group[b] >= 0:
					continue
				var pb: Vector3 = r.hands[b]["at"]
				if (
					Vector2(pa.x, pa.y).distance_to(Vector2(pb.x, pb.y)) <= link
					and absf(pa.z - pb.z) <= floor_gap
				):
					group[b] = count
					queue.append(b)
		count += 1
	var out: Array[Dictionary] = []
	for k in count:
		var members: Array[int] = []
		var sum := Vector3.ZERO
		var hp := 0.0
		var boss := false
		for i in r.hands.size():
			if group[i] == k:
				members.append(i)
				var at: Vector3 = r.hands[i]["at"]
				sum += at
				var h: float = r.hands[i]["hp"]
				hp += h
				var is_boss: bool = r.hands[i]["boss"]
				boss = boss or is_boss
		var fight := {
			"hands": members,
			"centre": sum / members.size(),
			"hp": hp,
			"boss": boss,
			"meet": -1,
			"closest": -1,
		}
		_meet(r, fight)
		out.append(fight)
	out.sort_custom(_sooner)
	return out


static func _sooner(a: Dictionary, b: Dictionary) -> bool:
	var ma: int = a["meet"]
	var mb: int = b["meet"]
	if ma < 0:
		return false
	if mb < 0:
		return true
	return ma < mb


static func _meet(r: MapReview, fight: Dictionary) -> void:
	var near := L.num("fight_near")
	var c: Vector3 = fight["centre"]
	var best := INF
	for i in r.steps.size():
		var p := MapReview.centre(r.steps[i])
		var d := p.distance_to(Vector2(c.x, c.y))
		if d < best:
			best = d
			fight["closest"] = i
		var met: int = fight["meet"]
		if met < 0:
			for m: int in fight["hands"]:
				var at: Vector3 = r.hands[m]["at"]
				if p.distance_to(Vector2(at.x, at.y)) <= near:
					fight["meet"] = i
					break


## Weapon name -> damage a round (a pellet gun's every pellet).
static func _damage(gun: String) -> float:
	var c := Tuning.file(Tuning.WEAPONS)
	if str(c.get_value(gun, "fire", "")) == "pellets":
		var each: float = c.get_value(gun, "damage", c.get_value("all", "shotgun_damage", 12))
		var pellets: float = c.get_value(gun, "pellets", c.get_value("all", "shotgun_pellets", 10))
		return each * pellets
	var d: float = c.get_value(gun, "damage", 0.0)
	return d


## What the player holds going in: gun name -> rounds.
class Pockets:
	var rounds := {}
	var owned := {}


static func _ammo_names() -> Dictionary:
	var guns := Tuning.sections(Tuning.WEAPONS)
	var out := {}
	var table := HitData.ammo()
	for key: String in table:
		var row: Array = table[key]
		var gun: int = row[0]
		var amount: int = row[1]
		if gun >= 0 and gun < guns.size():
			out[key] = [guns[gun], amount]
	return out


static func _take(held: Pockets, name: String, ammo: Dictionary) -> void:
	if ammo.has(name):
		var row: Array = ammo[name]
		var gun: String = row[0]
		var amount: int = row[1]
		var was: int = held.rounds.get(gun, 0)
		held.rounds[gun] = was + amount
	elif Tuning.file(Tuning.WEAPONS).has_section(name):
		held.owned[name] = true
		var more: int = Tuning.file(Tuning.WEAPONS).get_value(name, "pickup_reserve", 0)
		var had: int = held.rounds.get(name, 0)
		held.rounds[name] = had + more


## The damage the rounds held for owned guns would do, hit_share landing.
static func _worth(held: Pockets) -> float:
	var sum := 0.0
	for gun: String in held.rounds:
		if held.owned.has(gun):
			var rounds: int = held.rounds[gun]
			sum += rounds * _damage(gun) * L.num("hit_share")
	return sum


## Spend `damage` from the rounds held, the strongest gun's first.
static func _spend(held: Pockets, damage: float) -> void:
	var guns: Array = held.rounds.keys()
	guns.sort_custom(func(a: String, b: String) -> bool: return _damage(a) > _damage(b))
	var left := damage
	for gun: String in guns:
		if not held.owned.has(gun) or left <= 0.0:
			continue
		var each := _damage(gun) * L.num("hit_share")
		if each <= 0.0:
			continue
		var have: int = held.rounds[gun]
		var use := mini(have, ceili(left / each))
		held.rounds[gun] = have - use
		left -= use * each


## The gun owned with the most damage a round, and its ammo's name.
static func _main_gun(held: Pockets, ammo: Dictionary) -> Array:
	var best := ""
	for gun: String in held.owned:
		if best == "" or _damage(gun) > _damage(best):
			best = gun
	var word := "rounds"
	for key: String in ammo:
		var row: Array = ammo[key]
		if row[0] == best:
			word = key.replace("_", " ")
			break
	return [best, word]


static func ammo(r: MapReview) -> void:
	var names := _ammo_names()
	var held := Pockets.new()
	for key: String in r.kit:
		var amount: int = r.kit[key]
		if Tuning.file(Tuning.WEAPONS).has_section(key):
			held.owned[key] = true
			var kept: int = held.rounds.get(key, 0)
			held.rounds[key] = kept + amount
	var taken := {}
	var reach := L.num("ammo_reach")
	var step := 0
	var short := 0
	for fight in r.fights:
		var meet: int = fight["meet"]
		if meet < 0:
			continue
		while step <= meet and step < r.steps.size():
			var c := MapReview.centre(r.steps[step])
			for i in r.lv.pickups.size():
				var p: Array = r.lv.pickups[i]
				if taken.has(i):
					continue
				var px: float = p[1]
				var py: float = p[2]
				if Vector2(px, py).distance_to(c) <= reach:
					taken[i] = true
					_take(held, str(p[0]), names)
			step += 1
		var need: float = fight["hp"]
		var have := _worth(held)
		var boss_fight: bool = fight["boss"]
		if not boss_fight and have < need:
			short += 1
			var main := _main_gun(held, names)
			var each := maxf(1.0, _damage(str(main[0])) * L.num("hit_share"))
			var at: Vector3 = fight["centre"]
			var members: Array = fight["hands"]
			var count: int = members.size()
			(
				r
				. _add(
					"ammo",
					"ammo_short",
					[at.x, at.y, at.z],
					{
						"hands": words(count).to_lower() if count <= 12 else str(count),
						"need": ceili(need / each),
						"have": floori(have / each),
						"rounds": main[1],
						"object": _first_id(r, fight),
					}
				)
			)
		_spend(held, need)
		for m: int in fight["hands"]:
			var drop: String = r.hands[m]["drop"]
			var chance: float = r.hands[m]["drop_chance"]
			if names.has(drop):
				var row: Array = names[drop]
				var gun: String = row[0]
				var amount: int = row[1]
				var before: int = held.rounds.get(gun, 0)
				held.rounds[gun] = before + roundi(amount * chance * L.num("drop_share"))
	r.numbers["fights_short"] = short


static func _first_id(r: MapReview, fight: Dictionary) -> String:
	var members: Array = fight["hands"]
	if members.is_empty():
		return ""
	var m: int = members[0]
	return str(r.hands[m]["id"])


## Whether anything solid stands within `reach` of (x, y).
static func _covered(lv: LevelData, x: float, y: float, reach: float) -> bool:
	var k := ceili(reach)
	for dy in range(-k, k + 1):
		for dx in range(-k, k + 1):
			if Vector2(dx, dy).length() > reach + .01:
				continue
			var px := x + dx
			var py := y + dy
			if px < 0 or py < 0 or px >= lv.width or py >= lv.height:
				return true
			if lv.solid[int(py) * lv.width + int(px)] >= 0:
				return true
			if (dx != 0 or dy != 0) and lv.blocked(px, py, .3, .5):
				return true
	return false


static func cover(r: MapReview) -> void:
	var reach := L.num("cover_reach")
	var look := L.num("cover_look")
	var most := L.whole("open_most")
	var worst := 0
	for fight in r.fights:
		var meet: int = fight["meet"]
		var closest: int = fight["closest"]
		var boss_here: bool = fight["boss"]
		if meet < 0 or boss_here:
			continue
		var centre: Vector3 = fight["centre"]
		var run := 0
		var best := 0
		var best_at := Vector2.ZERO
		for i in range(_first_seen(r, fight, look), maxi(meet, closest) + 1):
			var p := MapReview.centre(r.steps[i])
			var seen := false
			for m: int in fight["hands"]:
				var at: Vector3 = r.hands[m]["at"]
				var d := Vector2(at.x, at.y).distance_to(p)
				if d <= look and r.lv.visible(at.x, at.y, p.x, p.y):
					seen = true
					break
			if seen and not _covered(r.lv, p.x, p.y, reach):
				run += 1
				if run > best:
					best = run
					best_at = p
			else:
				run = 0
		worst = maxi(worst, best)
		if best > most:
			(
				r
				. _add(
					"cover",
					"no_cover",
					[best_at.x, best_at.y],
					{
						"steps": best,
						"reach": reach,
						"object": _first_id(r, fight),
						"at": L.place([centre.x, centre.y, centre.z]),
					}
				)
			)
	r.numbers["open_approach_most"] = worst


## The first step (at or before the way meets the fight) a hand of it sees.
static func _first_seen(r: MapReview, fight: Dictionary, look: float) -> int:
	var meet: int = fight["meet"]
	var i := meet
	while i > 0:
		var p := MapReview.centre(r.steps[i - 1])
		var seen := false
		for m: int in fight["hands"]:
			var at: Vector3 = r.hands[m]["at"]
			if Vector2(at.x, at.y).distance_to(p) <= look and r.lv.visible(at.x, at.y, p.x, p.y):
				seen = true
				break
		if not seen:
			break
		i -= 1
	return i
