## Trail markers (pass 15; docs/dev/gameplay.md "Trail markers"): the
## chapter picked up from the last marker after a death, BACK TO THE MARKER
## on the death screen, instead of from its start. Before them a death
## outside a boss fight cost the ROOKIE bot 107 to 140 s of play each, three
## times in one Fair, every one at the end of a single unbroken fight.
##
## A marker is a whole save (SessionStore's format, chapter_marks.gd keeps
## the file: marker-<chapter>[-replay|-party].json), so the world comes back
## as it was: every hand, door, pickup, key, station, set piece and every
## feature's save() (a director's beat, say) with it, by itself. It is taken:
##   - on an objective: a station done, a key or a task item taken, a
##     vehicle run over, a boss down;
##   - on first standing in a district the player had not been in;
##   - on the clock, `gap_most` seconds after the last, fight or no fight
##     (modes.cfg [marker]); the first two only once `gap_least` have gone;
## and only when it is safe enough (_safe: everyone up, on the ground, not
## hurt this second, no hand on top of them, no boss fight near...). A
## clock's marker that has waited `press_after` for that is taken on a
## looser test (_safe(true): not hurt for `press_calm`, hands about or not):
## the fights that killed the ROOKIE had a crawler within a step and a half
## the whole last minute. Back at one each player gets the [marker] floor
## (health, rounds), as RETRY THE FIGHT does, so a fight lost at 10 health
## is not lost again at once; and dead again within `bad_within` of coming
## back to it, the marker before it is used instead (it was a bad spot:
## chapter_marks.gd keeps the one before beside it), so nobody is stuck
## dying at the same marker.
##
## Campaign chapters (and co-op, the host's game) only, while CHECKPOINTS is
## TRAIL MARKERS: never the hub, the range, a revisit, a rematch, County Run
## or a versus match. Taking one only reads the game (the file is written on
## a worker thread): play goes on exactly as without it. Looks only
## (LOOKS_FEATURES); its own state, kept in the features block, says when the
## next is due and which marker this run took (a token the file must hold).
extends GameFeature

const BossCheckpointFeature := preload("res://src/features/boss_checkpoint.gd")

const SCAN := .25
## How long the stamp stays on the HUD.
const STAMP_FOR := 2.2
const STAMP := "TRAIL MARKER SET"

static var GAP_LEAST: float = ModeData.get_value("marker", "gap_least", 20.0)
static var GAP_MOST: float = ModeData.get_value("marker", "gap_most", 45.0)
static var PRESS_AFTER: float = ModeData.get_value("marker", "press_after", 10.0)
static var PRESS_CALM: float = ModeData.get_value("marker", "press_calm", .5)
static var BAD_WITHIN: float = ModeData.get_value("marker", "bad_within", 30.0)
static var CALM_FOR: float = ModeData.get_value("marker", "calm_for", 1.0)
static var CLEAR_REACH: float = ModeData.get_value("marker", "clear_reach", 3.0)
static var SHOT_REACH: float = ModeData.get_value("marker", "shot_reach", 5.0)
static var SETTLE_MOST: float = ModeData.get_value("marker", "settle_most", 10.0)
static var HEALTH: int = ModeData.get_value("marker", "health", 50)
static var GRACE: float = ModeData.get_value("marker", "grace", 1.5)
static var DISTRICTS: bool = ModeData.get_value("marker", "district", true)
## Cells from an awake boss within which no marker is taken (the boss
## checkpoint's own reach on the way in).
static var BOSS_REACH: float = BossData.get_value("boss_retry", "approach")

## The clock the last marker was taken at (the chapter's start until one is;
## -1 before the first tick).
var last_at := -1.0
## The districts (the level's areas) a player has stood in.
var seen: Array[int] = []
## Why a marker is wanted now ("objective", "district", "clock"; "" none),
## and since when.
var want := ""
var want_since := 0.0
## The marker this run took: the token its file holds, the clock it was
## taken at, and how many this chapter.
var token := ""
var taken_at := -1.0
var count := 0
## The marker before it (its token and clock), and the clock this game was
## last brought back to a marker at (-1 never) and that marker's token.
var before_token := ""
var before_at := -1.0
var back_at := -1.0
var back_token := ""
## Not kept: the last clock a player was hurt, the next look round, the vehicle
## runs going when last looked, the stamp, the death screen's answer (-1 not
## worked out yet).
var hurt_at := -INF
var scan_left := 0.0
var _running := 0
var stamp_until := -1.0
var offer := -1


func id() -> String:
	return "trail_marker"


func attach() -> void:
	tick_with(_tick)
	game.events.station_done.connect(func(_id: String) -> void: _objective())
	game.events.pickup_taken.connect(_picked)
	game.events.boss_down.connect(func(_e: Enemy, _s: float) -> void: _objective())
	game.events.player_hurt.connect(func(_a: float, _c: String) -> void: hurt_at = game.clock)
	game.events.level_won.connect(_won)


func save() -> Dictionary:
	if last_at < 0.0:
		return {}
	return {
		"last_at": last_at,
		"seen": Array(seen),
		"want": want,
		"want_since": want_since,
		"token": token,
		"taken_at": taken_at,
		"count": count,
		"before_token": before_token,
		"before_at": before_at,
		"back_at": back_at,
		"back_token": back_token,
	}


func restore(state: Dictionary) -> void:
	last_at = SessionStore._float(state.get("last_at", -1.0))
	seen = []
	var areas: Variant = state.get("seen", [])
	if areas is Array:
		var area_list: Array = areas
		for value: Variant in area_list:
			seen.append(SessionStore._int(value))
	want = str(state.get("want", ""))
	want_since = SessionStore._float(state.get("want_since", 0.0))
	token = str(state.get("token", ""))
	taken_at = SessionStore._float(state.get("taken_at", -1.0))
	count = SessionStore._int(state.get("count", 0))
	before_token = str(state.get("before_token", ""))
	before_at = SessionStore._float(state.get("before_at", -1.0))
	back_at = SessionStore._float(state.get("back_at", -1.0))
	back_token = str(state.get("back_token", ""))
	hurt_at = -INF
	offer = -1


## A campaign chapter or co-op's, this machine deciding, markers on.
func eligible() -> bool:
	var mode := Modes.mode_of(game)
	return (
		game.trail_markers
		and not game.in_hub
		and game.net_role != "copy"
		and not game.revisiting
		and Campaign.ORDER.has(game.level.id)
		and (mode == Modes.CAMPAIGN or mode == Modes.COOP)
		and not BossRematch.active(game)
	)


func _tick(dt: float) -> void:
	scan_left -= dt
	if scan_left > 0.0:
		return
	scan_left = SCAN
	if not eligible() or game.won or game.showing_tally:
		return
	if last_at < 0.0:
		last_at = game.clock  # the chapter's start: its kit is the first marker
	_look_round()
	if want == "" and game.clock - last_at >= GAP_MOST:
		_wish("clock")
	if want == "":
		return
	if want != "clock" and game.clock - want_since > SETTLE_MOST:
		want = ""  # no safe moment came: the clock takes it from here
		return
	if _safe(want == "clock" and game.clock - want_since >= PRESS_AFTER):
		take()


## A new district stood in, a vehicle run just over.
func _look_round() -> void:
	var w := game.world
	for p: Player in game.players:
		if p.health <= 0 or p.away:
			continue
		var area := int(w.area[w.cell(p.x, p.y)])
		if not seen.has(area):
			seen.append(area)
			if DISTRICTS and seen.size() > 1:
				_wish("district")
	var runs: Object = game.features.get("vehicle_runs")
	var going := 0
	if runs != null:
		var status: PackedInt32Array = runs.get("status")
		for s: int in status:
			if s == 1:
				going += 1
	if going < _running:
		_objective()
	_running = going


func _picked(name: String) -> void:
	if name.begins_with("key_") or Game.TASK_ITEMS.has(name):
		_objective()


func _objective() -> void:
	_wish("objective")


func _wish(why: String) -> void:
	if want != "" or last_at < 0.0:
		return
	if why != "clock" and game.clock - last_at < GAP_LEAST:
		return
	want = why
	want_since = game.clock


## Safe enough to come back to: everyone up and on their feet in the open,
## not hurt this second, no hand on top of them and no hostile shot near
## (`pressed`, a clock's marker long due: not hurt for press_calm, and hands
## and shots about or not), no fire at their feet, no boss fight on or near,
## no set piece coming down, no vehicle run on, no feature holding it back.
func _safe(pressed := false) -> bool:
	if game.player != game.players[0] or game.armory.fuse > 0.0:
		return false  # (a save is player one's: nothing is refocused for it)
	if game.clock - hurt_at < (PRESS_CALM if pressed else CALM_FOR) or _running > 0:
		return false
	var rides: Object = game.features.get("vehicles")
	var w := game.world
	for p: Player in game.players:
		if p.away:
			continue
		if p.health <= 0 or p.air != 0.0 or p.vertical_speed != 0.0 or p.ladder >= 0:
			return false
		if w.deep_at(p.x, p.y):
			return false
		if rides != null:
			var seated: bool = rides.call("seated", p)
			if seated:
				return false
		if _danger_near(p, pressed) or _boss_near(p):
			return false
	var lock: Object = game.features.get("boss_lock")
	if lock != null:
		var shut: bool = lock.call("shut_now")
		if shut:
			return false
	if _set_piece_going():
		return false
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		if not feature.marker_ready():
			return false
	return true


func _danger_near(p: Player, pressed: bool) -> bool:
	for hazard: Game.Hazard in game.hazards:
		if Vector2(hazard.x - p.x, hazard.y - p.y).length() < hazard.radius + 1.0:
			return true
	if pressed:
		return false
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile or e.dormant or not e.alerted:
			continue
		if absf(e.x - p.x) < CLEAR_REACH and absf(e.y - p.y) < CLEAR_REACH:
			if Vector2(e.x - p.x, e.y - p.y).length() < CLEAR_REACH:
				return true
	for shot: Game.Shot in game.shots:
		if shot.enemy and Vector2(shot.x - p.x, shot.y - p.y).length() < SHOT_REACH:
			return true
	return false


## A boss awake and the player in its arena or on the way to it, or its
## fight's checkpoint taken (RETRY THE FIGHT is the way back then).
func _boss_near(p: Player) -> bool:
	var foe := BossFight.awake(game)
	if foe == null:
		return false
	if BossFight.in_arena_at(game, foe, p.x, p.y):
		return true
	if Vector2(foe.x - p.x, foe.y - p.y).length() < BOSS_REACH:
		return true
	var checkpoint: Object = game.features.get("boss_checkpoint")
	if checkpoint != null:
		var taken: Dictionary = checkpoint.get("taken")
		return taken.has(foe.kind)
	return false


## A barn or a tower creaking or coming down, or a flood running.
func _set_piece_going() -> bool:
	var pieces: Object = game.features.get("set_pieces")
	if pieces == null:
		return false
	var floods: Array = pieces.get("floods")
	if not floods.is_empty():
		return true
	var states: Array = pieces.get("pieces")
	for piece: Variant in states:
		if piece is Dictionary:
			var state: Dictionary = piece
			var stage: int = state.get("stage", 0)
			if stage == 1 or stage == 2:  # WARN, FALLING
				return true
	return false


## The marker taken now (tools call it straight).
func take() -> void:
	count += 1
	before_token = token
	before_at = taken_at
	token = "%s-m%d-%d" % [game.level.id, count, Time.get_ticks_usec()]
	taken_at = game.clock
	last_at = game.clock
	want = ""
	offer = -1
	ChapterMarks.write_soon(ChapterMarks.MARKER, game, ChapterMarks.BEFORE)
	stamp_until = game.clock + STAMP_FOR
	if not game.host:
		game.sound.play("marker_tie", .7)


func _won() -> void:
	if eligible() and Modes.mode_of(game) == Modes.CAMPAIGN:
		ChapterMarks.clear(ChapterMarks.MARKER, game.level.id, game.replay)
		ChapterMarks.clear(ChapterMarks.BEFORE, game.level.id, game.replay)


## BACK TO THE MARKER is on offer: this run took one, and the file on hand is
## that one.
func offered() -> bool:
	if game.player.health > 0:
		offer = -1
		return false
	if offer < 0:
		var yes := eligible() and token != ""
		if yes:
			var file := ChapterMarks.path_of(ChapterMarks.MARKER, game)
			var state := ChapterMarks.state_on_file(file, game.level.id, id())
			yes = str(state.get("token", "")) == token
		offer = 1 if yes else 0
	return offer == 1


## Dead again within bad_within of being brought back to the newest marker
## (and none taken since): the one before it is gone back to, while its file
## is the one this run took.
func falls_back() -> bool:
	if back_at < 0.0 or back_token != token or before_token == "":
		return false
	if game.clock - back_at >= BAD_WITHIN:
		return false
	var file := ChapterMarks.path_of(ChapterMarks.BEFORE, game)
	var state := ChapterMarks.state_on_file(file, game.level.id, id())
	return str(state.get("token", "")) == before_token


## The death screen's lines when a marker can be gone back to ([] otherwise),
## in the words of the device last used.
func death_lines() -> Array:
	if not offered():
		return []
	if game.use_key == "Y":
		return ["A  BACK TO THE MARKER", "X  CHAPTER START  /  B  TITLE"]
	if game.use_key == "USE":
		return ["TAP  BACK TO THE MARKER", "TAP HERE  CHAPTER START"]
	return [
		"ENTER  BACK TO THE MARKER",
		"%s  CHAPTER START  /  F9 LOAD  /  ESC TITLE" % BossCheckpointFeature.reload_key(),
	]


## The stamp under the top's notices for a moment after one is taken.
func hud_late(layout: HudLayout) -> void:
	if stamp_until > game.clock and not game.map and game.player.health > 0:
		layout.banner("marker", STAMP, 5)


func draw_view(c: Canvas) -> void:
	if stamp_until <= game.clock or game.map or game.player.health <= 0:
		return
	var at := game.hud.layout.find("marker")
	if at.size.x <= 0:
		return
	HudLayout.begin(c, "marker")
	HUD.banner(c, STAMP, at.position.y, game.hud.layout.limit, Lessons.INK)
	HudLayout.end(c)


# ------------------------------------------------------------- back to one


## The game in the marker's file, made ready to play on (null when it is gone
## or no longer loads).
static func restore_from(make_game: Callable, current: Game) -> Game:
	var mine: Object = current.features.get("trail_marker")
	var back_one := false
	if mine != null:
		var falling: bool = mine.call("falls_back")
		# The one before becomes the newest again (its file holds its token).
		back_one = (
			falling and ChapterMarks.promote(ChapterMarks.BEFORE, ChapterMarks.MARKER, current)
		)
	var loaded := ChapterMarks.read(ChapterMarks.MARKER, make_game, current)
	if loaded == null:
		return null
	return at_marker(loaded, back_one)


## A marker's game, just loaded: each player's floor, a moment's grace, every
## feature told. `back_one`: the marker before the newest.
static func at_marker(loaded: Game, back_one := false) -> Game:
	floor_of(loaded)
	loaded.spawn_grace = maxf(loaded.spawn_grace, GRACE)
	var mine: Object = loaded.features.get("trail_marker")
	if mine != null:
		mine.set("back_at", loaded.clock)
		mine.set("back_token", mine.get("token"))
	for key: String in loaded.features:
		var feature: GameFeature = loaded.features[key]
		feature.marker_back()
	loaded.message(
		(
			"THAT SPOT WAS A DEATH TRAP. BACK ONE MORE MARKER."
			if back_one
			else "BACK AT THE TRAIL MARKER. PATCHED UP. GIT ON."
		),
		3.0
	)
	return loaded


## Each player back with at least [marker] health, and each gun carried with
## at least its [marker] rounds in reserve. Play, the same on every machine.
static func floor_of(loaded: Game) -> void:
	var least_of: Dictionary = ModeData.get_value("marker", "rounds", {})
	for pl: Player in loaded.players:
		if pl.away:
			continue
		pl.health = maxi(pl.health, HEALTH)
		for gun: String in least_of:
			var slot := Weapons.NAMES.find(gun)
			if slot < 0 or not pl.armory.owned[slot]:
				continue
			var least: int = least_of[gun]
			pl.armory.reserve[slot] = maxi(pl.armory.reserve[slot], least)
