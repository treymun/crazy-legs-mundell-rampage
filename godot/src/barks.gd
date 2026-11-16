## Port of rampage2.Barks: Mundell's one-liners with per-category cooldowns,
## shown and (with CHATTER on) spoken. The game's `barks`; typed as
## GameState.Barks (game_state.gd preloads this file under that name).
extends RefCounted

const LINES := {
	"kill":
	[
		"THAT'S ONE LESS VARMINT.",
		"YEE-HAW!",
		"BACK TO THE DIRT, SON.",
		"DON'T MESS WITH THE LEGS.",
		"SHOULD'VE STAYED HOME.",
		"THAT'LL LEARN YA.",
		"SOMEBODY CALL THE UNDERTAKER.",
		"FIXIN' TO BE FERTILIZER.",
		"BLESS YOUR HEART.",
		"HOLD MY BEER.",
		"NOT IN MY COUNTY.",
		"THAT'S GONNA LEAVE A MARK."
	],
	"streak":
	["WHO'S NEXT?", "I'M JUST GETTIN' WARMED UP.", "IT'S RAMPAGE TIME!", "LINE UP, BOYS."],
	"pickup_weapon":
	[
		"NOW WE'RE TALKIN'.",
		"COME TO PAPPY.",
		"THAT'LL DO NICELY.",
		"HOT DIGGITY.",
		"OH, YOU PURTY THING."
	],
	"pickup_food":
	[
		"GOOD EATIN'.",
		"MMM, SALTY.",
		"THAT HITS THE SPOT.",
		"WASH IT DOWN.",
		"PORK RINDS. NOW WE'RE LIVIN'."
	],
	"hurt":
	["OW! THAT STUNG.", "WHY, I OUGHTA...", "YOU'LL PAY FER THAT.", "RIGHT IN THE OVERALLS!"],
	"low":
	["I'M SEEIN' THE LIGHT...", "NEED ME A SNACK.", "TOO MEAN TO DIE.", "SOMEBODY GET MAMA."],
	"reload":
	["LOCK AND LOAD.", "ANOTHER ROUND.", "COME ON, COME ON...", "FEED THE BEAST.", "FILL 'ER UP."],
	"empty": ["CLICK. WELL, SHUCKS.", "OUT OF SHELLS!", "DANG, PLUMB OUT.", "NEED ME MORE BOOM."],
	"drunk":
	[
		"HIC! WHO MOVED THE BARN?",
		"THE GROUND'S MOVIN'.",
		"I SEE TWO OF YA.",
		"WHOA, THE ROOM'S DANCIN'."
	],
	"secret":
	[
		"WELL, LOOKY HERE.",
		"NOW THAT'S A SECRET.",
		"SECRET STASH! DON'T MIND IF I DO.",
		"CAN'T HIDE NOTHIN' FROM ME."
	],
	"boss":
	[
		"WELL, AIN'T YOU A BIG UGLY ONE.",
		"YOU'RE GONNA NEED A BIGGER PORCH.",
		"LET'S DANCE, BIG'UN.",
		"I'VE WRASSLED HOGS MEANER'N YOU."
	],
	"boss_down":
	[
		"AND STAY DOWN!",
		"WHO'S THE BOSS NOW?",
		"SOMEBODY HOSE THAT OFF THE FLOOR.",
		"BIGGEST VARMINT I EVER BAGGED."
	],
	"station":
	[
		"THAT OUGHTA DO IT.",
		"FIXED IT. SORTA.",
		"DONE AND DONE.",
		"MAMA'D BE PROUD.",
		"GOOD ENOUGH FER THE COUNTY."
	],
	"key":
	[
		"NOW SOMETHIN' ROUND HERE OPENS.",
		"KEYS! NOW WE'RE COOKIN'.",
		"WELL NOW. BET IT FITS SOMETHIN'.",
		"SHINY. MINE NOW."
	],
	"headshot":
	["RIGHT BETWEEN THE EYES.", "DIDN'T NEED THAT HEAD ANYHOW.", "CLEAN OFF!", "BULLSEYE, BUBBA."],
	"start":
	[
		"LET'S GIT 'ER DONE.",
		"SMELLS LIKE TROUBLE. AND PIG.",
		"TIME TO CLEAN HOUSE.",
		"SOMEBODY'S FIXIN' TO GET LEARNED."
	],
	"new_iron":
	[
		"SMELLS LIKE GUN OIL ROUND HERE...",
		"SOMETHIN' SHINY CLOSE BY. NEW IRON.",
		"GUN'S CLOSE. I CAN SMELL IT."
	],
}
const COOLDOWN := {
	"kill": 6.0,
	"streak": 8.0,
	"pickup_weapon": 4.0,
	"pickup_food": 7.0,
	"hurt": 7.5,
	"low": 14.0,
	"reload": 12.0,
	"empty": 6.0,
	"drunk": 20.0,
	"secret": 4.0,
	"boss": 30.0,
	"boss_down": 10.0,
	"station": 6.0,
	"key": 4.0,
	"headshot": 7.0,
	"start": 60.0,
	"new_iron": 4.0
}
## Where his spoken lines are written (the voices'; LINES is the same in
## capitals), and how often CUSSIN' or CLEAN reaches for a cuss line over a
## clean one when both are made.
const SPOKEN := "res://data/tuning/mundell_lines.json"
const CUSS_SHARE := .5
static var _spoken_lines := {}
const GLOBAL_GAP := 2.6
const SHOW_FOR := 2.2

var state := 0
var last_at := {}
var last_line := {}
var next_any := 0.0
var text := ""
var until := 0.0
var recent_kills: Array = []
var enabled := true


func _init() -> void:
	state = (2098 * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF


func _rand() -> float:
	state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
	return float(state >> 10) / 9007199254740992.0


func say(game: Game, category: String, force := false) -> bool:
	# The local player's mouth (another player's kill is not ours to crow).
	if game.player != game.local_player:
		return false
	# With CHATTER on, Mundell says a cuss pack line aloud where one is made.
	var spoken := _spoken(game, category)
	if not spoken.is_empty() and game.sound.talking():
		# Somebody is talking (a boss, a hand, the radio): shown, not said.
		spoken = []
	if not enabled and spoken.is_empty():
		return false
	var now: float = game.clock
	if not force:
		if now < next_any:
			return false
		var last: float = last_at.get(category, -99.0)
		var gap: float = COOLDOWN[category]
		if now - last < gap:
			return false
	if not spoken.is_empty():
		return _speak(game, category, spoken, now)
	var pool: Array = LINES[category]
	var choices: Array = []
	for line: Variant in pool:
		if line != last_line.get(category):
			choices.append(line)
	if choices.is_empty():
		choices = pool
	var line: String = choices[clampi(int(_rand() * choices.size()), 0, choices.size() - 1)]
	last_line[category] = line
	last_at[category] = now
	next_any = now + GLOBAL_GAP
	text = line
	until = now + SHOW_FOR
	if category == "kill" or category == "streak":
		if _rand() < .35:
			game.sound.play("yee_haw_alt" if _rand() < .5 else "yee_haw", .7)
	return true


## Mundell's spoken lines (data/tuning/mundell_lines.json): moment -> lines.
static func spoken_lines() -> Dictionary:
	if _spoken_lines.is_empty() and FileAccess.file_exists(SPOKEN):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPOKEN))
		if parsed is Dictionary:
			var doc: Dictionary = parsed
			_spoken_lines = doc.get("lines", {})
	return _spoken_lines


## What Mundell can say aloud for `category` with CHATTER on, each [cue,
## caption, cuss]: his clean lines and the cuss pack's whose cues are made;
## [] with CHATTER off.
func _spoken(game: Game, category: String) -> Array:
	var chatter := game.chatter
	if chatter == CussLines.OFF or game.sound == null:
		return []
	var out: Array = []
	var clean: Array = spoken_lines().get(category, [])
	for n in clean.size():
		var cue := "mundell_%s_%d" % [category, n]
		if game.sound.has(cue):
			out.append([cue, str(clean[n]), false])
	var cuss := CussLines.lines("mundell", "", category)
	for n in cuss.size():
		var cue := CussLines.cue("mundell", category, n, chatter)
		if game.sound.has(cue):
			out.append([cue, CussLines.caption(str(cuss[n]), chatter), true])
	return out


func _speak(game: Game, category: String, spoken: Array, now: float) -> bool:
	var cussing := spoken.filter(func(s: Array) -> bool: return s[2])
	var plain := spoken.filter(func(s: Array) -> bool: return not s[2])
	var pool: Array = cussing if not cussing.is_empty() and _rand() < CUSS_SHARE else plain
	if pool.is_empty():
		pool = spoken
	var pick: Array = pool[clampi(int(_rand() * pool.size()), 0, pool.size() - 1)]
	if pool.size() > 1 and pick[1] == last_line.get(category):
		pick = pool[(pool.find(pick) + 1) % pool.size()]
	game.sound.play(str(pick[0]), .95)
	last_line[category] = pick[1]
	last_at[category] = now
	next_any = now + GLOBAL_GAP
	text = str(pick[1]).to_upper() if enabled else ""
	until = now + SHOW_FOR if enabled else 0.0
	return true


func kill(game: Game, head := false) -> void:
	var recent: Array = []
	for t: float in recent_kills:
		if game.clock - t < 7.0:
			recent.append(t)
	recent.append(game.clock)
	recent_kills = recent
	if recent_kills.size() >= 3:
		if say(game, "streak"):
			recent_kills.clear()
			return
	if head and say(game, "headshot"):
		return
	say(game, "kill")


func visible(game: Game) -> bool:
	return enabled and until > game.clock
