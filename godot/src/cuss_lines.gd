## The CUSS PACK's lines (data/tuning/cuss_lines.json, which the voice tools
## read too): the hands' (features/enemy_barks.gd), Mundell's (game_state.gd
## Barks) and the 5v5 bots' (features/chatter.gd). The CHATTER setting is
## OFF (0), CLEAN (1: the same lines with the cuss words under a duck call or a
## horn, captions as #@!%) or CUSSIN' (2). A line's cue is
## cuss_<voice>_<moment>_<n>, its CLEAN copy that plus _clean; a cue not made
## yet is simply not said.
class_name CussLines
extends RefCounted

const PATH := "res://data/tuning/cuss_lines.json"
const OFF := 0
const CLEAN := 1
const CUSSIN := 2
## What a starred word shows as in a CLEAN caption, cut to the word's length.
const GRAWLIX := "#@!%&$#@!%"

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


## The lines of `group` ("enemies", "tactical": by voice; "mundell": `who` "")
## for `moment` ([] when none).
static func lines(group: String, who: String, moment: String) -> Array:
	var part = data().get(group, {})
	if who != "" and part is Dictionary:
		part = (part as Dictionary).get(who, {})
	if not part is Dictionary:
		return []
	var out = (part as Dictionary).get(moment, [])
	return out if out is Array else []


static func cue(who: String, moment: String, n: int, chatter: int) -> String:
	return "cuss_%s_%s_%d%s" % [who, moment, n, "_clean" if chatter == CLEAN else ""]


## A line as its caption shows it: CUSSIN' plain, CLEAN with the starred words
## as grawlix.
static func caption(text: String, chatter: int) -> String:
	if chatter != CLEAN:
		return text.replace("*", "")
	var out := ""
	var parts := text.split("*")
	for i in parts.size():
		if i % 2 == 1:
			out += GRAWLIX.substr(0, clampi(parts[i].length(), 2, GRAWLIX.length()))
		else:
			out += parts[i]
	return out
