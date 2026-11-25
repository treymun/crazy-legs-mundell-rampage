## The chapter end card's numbers (pass 15): each chapter's PAR (modes.cfg
## [par]) and the player's bests, kept in chapter_bests.json beside the boss
## rematch bests (BossRematch.folder(): the profile, or the cache folder in a
## tool run, so a check never touches a player's): for each chapter and
## difficulty the best time, the most varmints and the most secrets, each its
## own best. Never in a save; a missing or broken file is no bests at all.
class_name ChapterBests
extends RefCounted

const FILE := "chapter_bests.json"
## The difficulties as the file names them (the PLAY page's words).
const DIFFICULTIES := ["EASY", "NORMAL", "HARD", "HOG WILD"]
## A file bigger than this is not ours: read as none.
const MOST_BYTES := 65536

static var PARS: Dictionary = ModeData.get_value("par", "chapters", {})
static var PACE_SHARE: float = ModeData.get_value("par", "pace_share", .2)
static var SLACK: float = ModeData.get_value("par", "slack", 2.0)


## Seconds for the chapter's PAR, or 0 when it has none (a player's map).
static func par(level_id: String) -> float:
	var seconds: float = PARS.get(level_id, 0.0)
	return seconds


## How well a time kept to par, out of one: 1 at par or under, 0 at SLACK
## times par (and with no par: -1, the ribbon leaves pace out).
static func pace(level_id: String, seconds: float) -> float:
	var target := par(level_id)
	if target <= 0.0:
		return -1.0
	if seconds <= target:
		return 1.0
	return clampf((target * SLACK - seconds) / (target * (SLACK - 1.0)), 0.0, 1.0)


static func difficulty_name(difficulty: int) -> String:
	return str(DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)])


static func path() -> String:
	return BossRematch.folder().path_join(FILE)


## {chapter: {difficulty name: {"time": s, "kills": n, "secrets": n}}}, only
## the well-formed entries of the campaign's chapters.
static func sheet() -> Dictionary:
	var out := {}
	var file := path()
	if not FileAccess.file_exists(file):
		return out
	var raw := FileAccess.get_file_as_bytes(file)
	if raw.size() > MOST_BYTES:
		return out
	var doc: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (doc is Dictionary):
		return out
	var kept: Dictionary = doc
	var bests: Variant = kept.get("bests", {})
	if not (bests is Dictionary):
		return out
	var chapters: Dictionary = bests
	for level_id: Variant in chapters:
		var by_difficulty: Variant = chapters[level_id]
		if not Campaign.ORDER.has(str(level_id)) or not (by_difficulty is Dictionary):
			continue
		var rows: Dictionary = by_difficulty
		var clean := {}
		for word: Variant in rows:
			var row: Variant = rows[word]
			if DIFFICULTIES.has(str(word)) and row is Dictionary:
				var sheet_row: Dictionary = row
				var entry := _clean(sheet_row)
				if not entry.is_empty():
					clean[str(word)] = entry
		if not clean.is_empty():
			out[str(level_id)] = clean
	return out


static func _clean(row: Dictionary) -> Dictionary:
	var time: Variant = row.get("time", 0.0)
	var kills: Variant = row.get("kills", 0)
	var secrets: Variant = row.get("secrets", 0)
	if not (time is float or time is int) or not (kills is float or kills is int):
		return {}
	if not (secrets is float or secrets is int):
		return {}
	var seconds: float = time
	if seconds <= 0.0:
		return {}
	var most_kills: int = kills
	var most_secrets: int = secrets
	return {"time": seconds, "kills": maxi(0, most_kills), "secrets": maxi(0, most_secrets)}


## The bests for a chapter at a difficulty ({} when none yet).
static func best(level_id: String, difficulty: int) -> Dictionary:
	var rows: Dictionary = sheet().get(level_id, {})
	var row: Dictionary = rows.get(difficulty_name(difficulty), {})
	return row


## A won run's numbers kept where they beat the bests. Returns {"old": the
## bests before ({} on a first run), "time"/"kills"/"secrets": true where
## this run set a new one (all false on a first run), "kept": written}.
static func record(
	level_id: String, difficulty: int, seconds: float, kills: int, secrets: int
) -> Dictionary:
	var all := sheet()
	var rows: Dictionary = all.get(level_id, {})
	var word := difficulty_name(difficulty)
	var old: Dictionary = rows.get(word, {})
	var out := {"old": old, "time": false, "kills": false, "secrets": false, "kept": false}
	if not Campaign.ORDER.has(level_id) or seconds <= 0.0:
		return out
	var row := {"time": snappedf(seconds, .1), "kills": kills, "secrets": secrets}
	if not old.is_empty():
		var old_time: float = old["time"]
		var old_kills: int = old["kills"]
		var old_secrets: int = old["secrets"]
		var faster := seconds < old_time - .05
		out["time"] = faster
		out["kills"] = kills > old_kills
		out["secrets"] = secrets > old_secrets
		row["time"] = snappedf(seconds, .1) if faster else old_time
		row["kills"] = maxi(kills, old_kills)
		row["secrets"] = maxi(secrets, old_secrets)
		if row == old:
			return out  # nothing beaten: the file stays as it was
	rows[word] = row
	all[level_id] = rows
	out["kept"] = SessionStore._write_atomic(path(), JSON.stringify({"bests": all}, "", false))
	return out


## Any of the three beaten (a first run beats nothing).
static func fresh(result: Dictionary) -> bool:
	var time: bool = result.get("time", false)
	var kills: bool = result.get("kills", false)
	var secrets: bool = result.get("secrets", false)
	return time or kills or secrets


## A time as the card writes it, as its TIME row does: 04:21.
static func clock_text(seconds: float) -> String:
	var whole := int(maxf(0.0, seconds))
	return "%02d:%02d" % [whole / 60, whole % 60]
