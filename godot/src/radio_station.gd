## The county radio (content pass 8): KPSM, fourteen-ninety AM, the Possum.
## Dub Tillery talks between the songs (station IDs, weather, the county's
## businesses, and what the player has been up to), says a line when a truck's
## radio is tuned in, and the county's police scanner calls in Mundell's
## trouble, faint, louder by a radio set or in a vehicle.
##
## One per machine, kept by Sound (`sound.station`) so it remembers the night
## across chapters and retries. It only decides what is said and when, with its
## own dice (never game.rng): `player` plays a cue on a channel and says how
## long it lasts, `stopper` stops one. features/radio.gd tells it the news and
## where the sets are; Sound holds the next song while a break is on
## (ScorePlayer `take_break`), ducks it under talk over music, and ducks the
## radio under anyone talking. The lines are data/tuning/radio_lines.json.
## Looks and sound only: play never reads it.
class_name RadioStation
extends RefCounted

const PATH := "res://data/tuning/radio_lines.json"
## The RADIO setting.
const DJ_AND_MUSIC := 0
const MUSIC_ONLY := 1
const OFF := 2
## Its two channels.
const DJ := 0
const SCANNER := 1
## The share of gaps between songs with no news that Dub lets go by.
const QUIET_SHARE := .3
## Seconds: a beat after the song before he talks, between his lines, and
## after his last line before the band.
const LEAD_IN := .8
const LINE_GAP := .35
const TAIL := .6
## News older than this is stale; a topic told is not told again for TOLD_HOLDS.
const NEWS_KEEPS := 600.0
const TOLD_HOLDS := 420.0
## The order news is told in (a boss's fall first).
const PRIORITY := ["boss", "boom", "wreck", "rampage", "deaths", "drunk", "secret"]
## Deaths this close together make a rough night.
const DEATHS := 3
const DEATH_WINDOW := 900.0
## The share of reactions told with a crude line (CUSSIN'; CLEAN its copy).
const CUSS_SHARE := .35
## The scanner: seconds between calls of one kind and between any two, the
## pause between a call's pieces, and how long a call waits for quiet.
const SCAN_TOPIC_GAP := 45.0
const SCAN_GAP := 16.0
const SCAN_PIECE_GAP := .18
const SCAN_WAITS := 8.0
## What sets the scanner off.
const SCAN_CALLS := ["shots", "boom", "wreck", "rampage", "officer"]
## A drive line when a vehicle is taken, at most this often.
const TUNE_GAP := 90.0
## How many cues the log keeps (the checks read it).
const LOG_SIZE := 64

static var _data := {}

var mode := DJ_AND_MUSIC
var chatter := CussLines.CUSSIN
## Off where the radio has no place (the 5v5 rounds).
var enabled := true
## Nothing new starts (a boss fight): a break or a call waiting is dropped.
var hold := false
## Someone else is talking (Sound.talking): a scanner call waits.
var others_talking := false
## The chapter the scanner sends units to (its place_<id> lines).
var place := ""
## The nearest set (0 none, 1 right by it), its pan and muffle, and whether
## the local player is in a vehicle (features/radio.gd, every look).
var near := 0.0
var near_pan := 0.0
var near_cutoff := Sound.OPEN_CUTOFF
var driving := false
var player := Callable()
var stopper := Callable()
var has_cue := Callable()
## Seconds of radio (real time, not the game's clock).
var now := 0.0
var in_break := false
## The last line said, for its caption: channel, words, until when, and a
## count that moves with each line.
var said_channel := -1
var said := ""
var said_until := 0.0
var said_count := 0
## The cues played, last LOG_SIZE (the checks read it).
var log: Array[String] = []

var _dice := Sound.ShuffleRng.new(1490)
var _bags := {}
var _last := {}
var _fresh: Array = []
var _told := {}
var _deaths: Array[float] = []
var _talk: Array = []
var _talk_next := 0.0
var _talk_until := 0.0
var _scan: Array = []
var _scan_next := 0.0
var _scan_asked := 0.0
var _scan_last := -1000.0
var _scan_told := {}
var _tuned_at := -1000.0


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


## The lines of `section` ("dj", "cuss", "scanner") for `group` ([] when none).
static func lines(section: String, group: String) -> Array:
	var part: Variant = data().get(section, {})
	if not part is Dictionary:
		return []
	var by_group: Dictionary = part
	var out: Variant = by_group.get(group, [])
	return out if out is Array else []


## Whether Dub talks (DJ + MUSIC, where the radio has a place).
func talks() -> bool:
	return mode == DJ_AND_MUSIC and enabled


## Something happened: "boom", "wreck", "rampage", "drunk", "secret",
## "boss_<speaker>", "death" (one; DEATHS of them make news), and for the
## scanner "shots" and "officer".
func news(topic: String) -> void:
	if topic == "death":
		_deaths.append(now)
		while not _deaths.is_empty() and now - _deaths[0] > DEATH_WINDOW:
			_deaths.pop_front()
		if _deaths.size() >= DEATHS:
			_deaths.clear()
			_freshen("deaths")
		return
	if SCAN_CALLS.has(topic):
		_call(topic)
	if topic == "shots" or topic == "officer":
		return
	_freshen(topic)


func _freshen(topic: String) -> void:
	var told_at: float = _told.get(topic, -1000.0)
	if not topic.begins_with("boss_") and now - told_at < TOLD_HOLDS:
		return
	for i in range(_fresh.size() - 1, -1, -1):
		var row: Array = _fresh[i]
		if str(row[0]) == topic:
			_fresh.remove_at(i)
	_fresh.append([topic, now])


## The news still to tell, freshest last (the checks read it).
func fresh_topics() -> Array[String]:
	var out: Array[String] = []
	for row: Array in _fresh:
		out.append(str(row[0]))
	return out


## A chapter's song just ended: whether Dub takes the gap (then the next
## song waits until `in_break` is over).
func take_break() -> bool:
	if not talks() or hold or not _talk.is_empty():
		return false
	var topic := _pop_news()
	if topic == "" and _dice.next() < QUIET_SHARE:
		return false
	var segment: Array = [_line("id")]
	if topic != "":
		segment.append(_reaction(topic))
		var more := _pop_news()
		if more != "":
			segment.append(_reaction(more))
	else:
		var body: String = ["weather", "ad", "bit", "ad"][int(_dice.next() * 4.0) % 4]
		segment.append(_line(body))
		if body != "ad" and _dice.next() < .4:
			segment.append(_line("ad"))
	segment.append(_line("outro"))
	var made: Array = []
	for row: Array in segment:
		if _made(str(row[0])):
			made.append(row)
	if made.size() < 2:
		return false
	_talk = made
	_talk_next = now + LEAD_IN
	in_break = true
	return true


## A vehicle was taken: the set clicks on and, now and then, Dub says a line
## for the road over the music.
func tune_in() -> void:
	if mode == OFF or not enabled or in_break or not _talk.is_empty():
		return
	_talk = [["radio_tune", ""]]
	if talks() and not hold and now - _tuned_at >= TUNE_GAP:
		_tuned_at = now
		_talk.append(_line("drive"))
	_talk_next = now


## The break is over early (a fight, another score): the line playing ends,
## nothing more is said, and the band comes back.
func end_break() -> void:
	if in_break:
		_talk.clear()
		in_break = false


## Everything stops at once (a boss's line cuts in, the game paused).
func hush() -> void:
	_talk.clear()
	_scan.clear()
	in_break = false
	_talk_until = 0.0
	said_until = 0.0
	if stopper.is_valid():
		stopper.call(DJ)
		stopper.call(SCANNER)


## Whether Dub's line is still playing.
func on_air() -> bool:
	return now < _talk_until


func update(dt: float) -> void:
	now += dt
	if mode == OFF or not enabled:
		if in_break or not _talk.is_empty() or not _scan.is_empty():
			hush()
		return
	if not _talk.is_empty() and now >= _talk_next:
		if hold:
			_talk.clear()
		else:
			var row: Array = _talk.pop_front()
			var cue := str(row[0])
			if cue != "radio_tune" and not talks():
				_talk.clear()
			else:
				var length := _play(DJ, cue, str(row[1]))
				_talk_until = now + length
				_talk_next = now + length + (TAIL if _talk.is_empty() else LINE_GAP)
	if in_break and _talk.is_empty() and now >= _talk_next:
		in_break = false
	if not talks():
		_scan.clear()
	elif not _scan.is_empty() and now >= _scan_next:
		var head: Array = _scan[0]
		var first := str(head[0]) == "scan_squelch"
		if hold or now - _scan_asked > SCAN_WAITS:
			_scan.clear()
		elif not first or not (others_talking or on_air()):
			var row: Array = _scan.pop_front()
			var length := _play(SCANNER, str(row[0]), str(row[1]))
			_scan_next = now + length + SCAN_PIECE_GAP
			_scan_last = now


func _play(channel: int, cue: String, caption: String) -> float:
	var length: float = player.call(channel, cue) if player.is_valid() else 0.0
	log.append(cue)
	if log.size() > LOG_SIZE:
		log.pop_front()
	if caption != "" and length > 0.0:
		said_channel = channel
		said = caption
		said_until = now + length + .2
		said_count += 1
	return length


func _made(cue: String) -> bool:
	if not has_cue.is_valid():
		return true
	var made: bool = has_cue.call(cue)
	return made


## A scanner call: the key-up, now and then "all units", the call, where to,
## and now and then a word on the suspect.
func _call(kind: String) -> void:
	if not talks() or hold or not _scan.is_empty():
		return
	var called_at: float = _scan_told.get(kind, -1000.0)
	if now - called_at < SCAN_TOPIC_GAP or now - _scan_last < SCAN_GAP:
		return
	var pieces: Array = [["scan_squelch", ""]]
	if _dice.next() < .6:
		pieces.append(_line("open", "scanner", "scan_"))
	pieces.append(_line(kind, "scanner", "scan_"))
	if kind != "officer" or _dice.next() < .5:
		var where := "place_" + place
		if lines("scanner", where).is_empty():
			where = "place_hickston"
		pieces.append(_line(where, "scanner", "scan_"))
	if _dice.next() < .55:
		pieces.append(_line("tag", "scanner", "scan_"))
	pieces.append(["scan_squelch", ""])
	var made: Array = []
	for row: Array in pieces:
		if _made(str(row[0])):
			made.append(row)
	if made.size() < 4:
		return
	_scan_told[kind] = now
	_scan_last = now
	_scan_asked = now
	_scan_next = now
	_scan = made


func _pop_news() -> String:
	while not _fresh.is_empty():
		var oldest: Array = _fresh[0]
		var at: float = oldest[1]
		if now - at <= NEWS_KEEPS:
			break
		_fresh.pop_front()
	var best := -1
	var rank := PRIORITY.size()
	for i in _fresh.size():
		var row: Array = _fresh[i]
		var topic := str(row[0])
		var r := PRIORITY.find("boss" if topic.begins_with("boss_") else topic)
		if r >= 0 and r <= rank:
			best = i
			rank = r
	if best < 0:
		return ""
	var picked: Array = _fresh[best]
	var topic := str(picked[0])
	_fresh.remove_at(best)
	_told[topic] = now
	return topic


## [cue, caption] for news `topic`: its own lines, or now and then a crude
## one (CUSSIN'; CLEAN plays the copy with the words covered; none with
## CHATTER OFF).
func _reaction(topic: String) -> Array:
	var crude := lines("cuss", topic)
	if not crude.is_empty() and chatter != CussLines.OFF and _dice.next() < CUSS_SHARE:
		var n := _deal("cuss_" + topic, crude.size())
		var cue := CussLines.cue("dj", topic, n, chatter)
		if _made(cue):
			return [cue, "KPSM: " + CussLines.caption(str(crude[n]), chatter)]
	return _line(topic)


## The next of `group`'s lines, dealt so none comes round again before the
## rest have: [cue, caption].
func _line(group: String, section := "dj", prefix := "dj_") -> Array:
	var all := lines(section, group)
	if all.is_empty():
		return ["", ""]
	var n := _deal(section + group, all.size())
	var label := "KPSM: " if section == "dj" else "SCANNER: "
	return ["%s%s_%d" % [prefix, group, n], label + str(all[n])]


func _deal(key: String, size: int) -> int:
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		for i in size:
			bag.append(i)
		var i := bag.size() - 1
		while i > 0:
			var j := int(_dice.next() * float(i + 1))
			var swap: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = swap
			i -= 1
		# Never the line just said again across a new deal.
		var top: int = bag[bag.size() - 1]
		var said_last: int = _last.get(key, -1)
		if bag.size() > 1 and top == said_last:
			var swap2: Variant = bag[0]
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = swap2
	var n: int = bag.pop_back()
	_bags[key] = bag
	_last[key] = n
	return n
