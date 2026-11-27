## The map kit's one call: a piece's spec (a small dictionary, as a map
## source or a player map says it) built into LevelParts.
##
##   var parts := LevelParts.new()
##   var made := KitPiece.build({"piece": "farmhouse", "id": "home", "x": 10, "y": 6}, parts)
##   if made.has("error"): print(made["error"])
##
## Every key but piece and id has a default (data/tuning/map_kit.json
## "common" and the piece's own "options"), so a one-line placement looks
## right. A spec that names something the piece does not take, a number out of
## its range or the wrong kind of value is refused with one plain line, and
## nothing of it is built. Pieces: catalog().
class_name KitPiece
extends RefCounted

const TUNING := "res://data/tuning/map_kit.json"
## Families whose footprints may not overlap one another.
const BUILDINGS := ["houses", "farm", "town"]

static var _tuning := {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
		_tuning = parsed if parsed is Dictionary else {}
	return _tuning


## A build number (map_kit.json "build").
static func num(key: String) -> float:
	var build: Dictionary = tuning().get("build", {})
	var value: float = build.get(key, 0.0)
	return value


## Every piece's name, sorted.
static func names() -> Array[String]:
	var pieces: Dictionary = tuning().get("pieces", {})
	var out: Array[String] = []
	for key: String in pieces:
		out.append(key)
	out.sort()
	return out


## What a piece takes: {w: [default, min, max], d: [...], style, family,
## options: {name: default or [default, min, max] or [default, choices...]}}.
static func catalog(kind: String) -> Dictionary:
	var pieces: Dictionary = tuning().get("pieces", {})
	var entry: Dictionary = pieces.get(kind, {})
	return entry


## A style's materials (wall, roof, trim, floor, under, found), the variant's
## changes over them.
static func style(name: String, variant: int) -> Dictionary:
	var styles: Dictionary = tuning().get("styles", {})
	var base: Dictionary = styles.get(name, {})
	var out := base.duplicate()
	out.erase("variants")
	var variants: Array = base.get("variants", [])
	if not variants.is_empty():
		var pick: Dictionary = variants[posmod(variant, variants.size())]
		out.merge(pick, true)
	return out


static func style_names() -> Array[String]:
	var styles: Dictionary = tuning().get("styles", {})
	var out: Array[String] = []
	for key: String in styles:
		out.append(key)
	out.sort()
	return out


## Builds the piece `spec` names into `parts`. Returns the piece's record
## (LevelParts.pieces' entry) or {"error": "<one plain line>"}.
static func build(spec: Dictionary, parts: LevelParts) -> Dictionary:
	var o := resolve(spec)
	if o.has("error"):
		return o
	var kind: String = o["piece"]
	var id: String = o["id"]
	var w: float = o["w"]
	var d: float = o["d"]
	var x: float = o["x"]
	var y: float = o["y"]
	var turn: int = o["turn"]
	var mirror: bool = o["mirror"]
	var district: int = o["area"]
	var f := KitFrame.make(Vector2(x, y), Vector2(w, d), turn, mirror)
	var entry := catalog(kind)
	var family: String = entry.get("family", "")
	var problem := _place_problem(id, f.footprint(), family, parts)
	if problem != "":
		return {"error": problem}
	var cost_before := parts.cost()
	var before := parts.mark()
	parts.begin(id, kind, f, district)
	parts.note("building", family in BUILDINGS)
	var variant: int = o["variant"]
	if variant <= 0:
		# Looks dice (the piece's id and the map's seed), never play's.
		variant = parts.dice("variant").randi_range(0, 2)
	else:
		variant -= 1
	var style_name: String = o["style"]
	var look := style(style_name, variant)
	match family:
		"houses":
			KitHouses.build(kind, o, look, parts)
		"farm":
			KitFarm.build(kind, o, look, parts)
		"town":
			KitTown.build(kind, o, look, parts)
		"bits":
			KitBits.build(kind, o, look, parts)
		"roofs":
			KitRoofs.piece(o, look, parts)
	var made := parts.finish()
	var most := num("piece_cost_most")
	if parts.cost() - cost_before > most:
		parts.rollback(before)
		return {
			"error": "%s: %d pieces of building, %d most" % [id, parts.cost() - cost_before, most]
		}
	return made


## Where a piece may not stand: off the map (inside its border), on another
## building, or under an id already used. "" when it may.
static func _place_problem(id: String, r: Rect2, family: String, parts: LevelParts) -> String:
	if parts.width > 0 and parts.height > 0:
		var inside := Rect2(1, 1, parts.width - 2, parts.height - 2)
		if not inside.encloses(r):
			return (
				"%s: runs off the map (%d, %d to %d, %d)"
				% [id, r.position.x, r.position.y, r.end.x, r.end.y]
			)
	for other: Dictionary in parts.pieces:
		var other_id: String = other["id"]
		if other_id == id:
			return "%s: that id is taken" % id
		var building: bool = other.get("building", false)
		if not building or not (family in BUILDINGS):
			continue
		var fp: Array = other["footprint"]
		var fx0: float = fp[0]
		var fy0: float = fp[1]
		var fx1: float = fp[2]
		var fy1: float = fp[3]
		var o_rect := Rect2(fx0, fy0, fx1 - fx0, fy1 - fy0)
		var meet := r.intersection(o_rect)
		if meet.size.x > .001 and meet.size.y > .001:
			return "%s: stands on %s (move one of them)" % [id, other_id]
	return ""


## The spec with every default filled in and checked: {piece, id, x, y, w, d,
## turn, mirror, area, style, variant, <options>} or {"error": line}.
static func resolve(spec: Dictionary) -> Dictionary:
	var kind_v: Variant = spec.get("piece", spec.get("type", ""))
	if not (kind_v is String):
		return {"error": "a kit piece needs a piece name"}
	var kind: String = kind_v
	var entry := catalog(kind)
	if entry.is_empty():
		return {"error": "no kit piece named %s" % kind}
	var id_v: Variant = spec.get("id", "")
	if not (id_v is String) or str(id_v) == "":
		return {"error": "%s: a kit piece needs an id" % kind}
	var id: String = id_v
	if not id.is_valid_ascii_identifier():
		return {"error": "%s: an id is letters, digits and _ (%s)" % [kind, id]}
	var common: Dictionary = tuning().get("common", {})
	var options: Dictionary = entry.get("options", {})
	var rules := {}
	rules.merge(common)
	rules["w"] = entry.get("w", [1, 1, 1])
	rules["d"] = entry.get("d", [1, 1, 1])
	rules.merge(options)
	var out := {"piece": kind, "id": id}
	for key: String in spec:
		if key == "piece" or key == "type" or key == "id":
			continue
		if not rules.has(key):
			return {"error": "%s: %s takes no %s" % [id, kind, key]}
	for key: String in rules:
		if key == "id":
			continue
		var rule: Variant = rules[key]
		var given: Variant = spec.get(key, null)
		var value: Variant = _value(key, rule, given)
		if value is String and str(value).begins_with("!"):
			return {"error": "%s: %s %s" % [id, key, str(value).substr(1)]}
		out[key] = value
	if str(out["style"]) == "":
		out["style"] = entry.get("style", "barn_red")
	if not style_names().has(str(out["style"])):
		return {"error": "%s: no style named %s" % [id, out["style"]]}
	if spec.has("face") and not spec.has("turn"):
		out["turn"] = KitFrame.FACES.get(out["face"], 0)
	return out


## A key's value under its rule, the rule's default when not given, or
## "!<what is wrong>".
static func _value(key: String, rule: Variant, given: Variant) -> Variant:
	if rule is bool:
		if given == null:
			return rule
		if not (given is bool):
			return "!is true or false"
		return given
	if rule is String:
		if given == null:
			return rule
		if not (given is String):
			return "!is a word"
		var word: String = given
		if word.length() > 40:
			return "!is too long"
		return word
	var list: Array = rule
	if list.is_empty():
		return "!has no rule"
	if list[0] is String:
		if given == null:
			return list[0]
		if not (given is String) or not list.slice(1).has(given):
			return "!is one of %s" % ", ".join(PackedStringArray(list.slice(1)))
		return given
	var fallback: float = list[0]
	var low: float = list[1]
	var high: float = list[2]
	var whole := fmod(fallback, 1.0) == 0.0 and fmod(low, 1.0) == 0.0 and fmod(high, 1.0) == 0.0
	var v := fallback
	if given != null:
		if not (given is float or given is int):
			return "!is a number"
		v = given
		if is_nan(v) or v < low or v > high:
			return "!is %s to %s" % [_show(low), _show(high)]
		if whole and fmod(v, 1.0) != 0.0:
			return "!is a whole number"
	if whole:
		var n := int(v)
		if key in ["x", "y", "w", "d"]:
			return float(n)
		return n
	return snappedf(v, .001)


static func _show(v: float) -> String:
	return str(int(v)) if fmod(v, 1.0) == 0.0 else str(v)
