## The design review's numbers and lines (data/tuning/map_review.json): what
## each check measures against, and what a finding says. A finding is a
## Dictionary (so it goes straight into report.json):
##   {level: "MUST FIX" | "SHOULD" | "NICE", check, code, at: [x, y, z],
##    object (an id, or ""), what (the plain line: what is wrong and where),
##    fix (how to fix it), say (the same in the game's voice, upper case)}.
## A line's {word} is filled from the finding's fields, {WORD} the same upper
## case (for the say lines).
class_name MapReviewLines
extends RefCounted

const DATA := "res://data/tuning/map_review.json"
const LEVELS: Array[String] = ["MUST FIX", "SHOULD", "NICE"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary:
			_data = parsed
		else:
			push_error("%s does not read as JSON" % DATA)
			_data = {"numbers": {}, "lines": {}, "kit": {}}
	return _data


static func num(key: String) -> float:
	var numbers: Dictionary = data().get("numbers", {})
	if not numbers.has(key):
		push_error("%s: no number %s" % [DATA, key])
		return 0.0
	var v: float = numbers[key]
	return v


static func whole(key: String) -> int:
	return roundi(num(key))


## The starting kit a review and a bot run assume: gun or item name -> rounds
## or count (a map's meta.kit is merged over it).
static func kit() -> Dictionary:
	var k: Dictionary = data().get("kit", {})
	return k.duplicate()


static func verdict_line(verdict: String) -> String:
	var v: Dictionary = data().get("verdicts", {})
	return str(v.get(verdict, verdict))


static func verdict_say(verdict: String) -> String:
	var v: Dictionary = data().get("says", {})
	return str(v.get(verdict, ""))


## A place as the lines write it: (x, y) or (x, y, z) when off the ground.
static func place(at: Array) -> String:
	if at.size() < 2:
		return "(?)"
	var x: float = at[0]
	var y: float = at[1]
	var z: float = at[2] if at.size() > 2 else 0.0
	if absf(z) > .05:
		return "(%s, %s, z %s)" % [_n(x), _n(y), _n(z)]
	return "(%s, %s)" % [_n(x), _n(y)]


static func _n(v: float) -> String:
	return str(snappedf(v, .1))


## The finding for line `code`, its words filled from `fields`.
static func finding(check: String, code: String, at: Array, fields: Dictionary) -> Dictionary:
	var lines: Dictionary = data().get("lines", {})
	var line: Dictionary = lines.get(code, {})
	if line.is_empty():
		push_error("%s: no line %s" % [DATA, code])
	var words := {}
	for key: Variant in fields:
		var text := str(fields[key])
		words[str(key)] = text
		words[str(key).to_upper()] = text.to_upper()
	if not words.has("at"):
		words["at"] = place(at)
		words["AT"] = place(at)
	var spot: Array = []
	for v: Variant in at:
		var f: float = v
		spot.append(snappedf(f, .01))
	var level: String = str(fields.get("level", line.get("level", "SHOULD")))
	return {
		"level": level,
		"check": check,
		"code": code,
		"at": spot,
		"object": str(fields.get("object", "")),
		"what": str(line.get("what", "")).format(words),
		"fix": str(line.get("fix", "")).format(words),
		"say": str(line.get("say", "")).format(words),
	}


## FAIL with any MUST FIX, WORK with SHOULD items only, else PASS.
static func verdict(findings: Array) -> String:
	var should := false
	for f: Dictionary in findings:
		if f["level"] == "MUST FIX":
			return "FAIL"
		if f["level"] == "SHOULD":
			should = true
	return "WORK" if should else "PASS"


## How many findings at each level.
static func counts(findings: Array) -> Dictionary:
	var out := {"MUST FIX": 0, "SHOULD": 0, "NICE": 0}
	for f: Dictionary in findings:
		var lv: String = f["level"]
		var was: int = out.get(lv, 0)
		out[lv] = was + 1
	return out
