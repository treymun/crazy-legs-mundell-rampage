## Teaching by doing (pass 12, ONBOARD). The first time something comes up
## (the first step, the first hand after you, one reeling in reach, a locked
## door, a thing you can tote, a rig you can drive, the junk bench, scrap,
## BLUE and his badge, the dynamite, a full gut, the drink) one short tip says
## what to do, naming the key, pad button or touch button the player last
## used (game.input_device, `glyph()`); then never again on this profile
## (user://lessons.json, not part of a save). One tip at a time, in its own
## banner under the notice (game.tip, game_view.gd), never over a boss's
## entrance, the map or the tally; the ones that can wait (BLUE, the map,
## changing guns) wait out a fight. Shown only in real play (main_flow.gd
## turns Game.lessons on) with NEW PLAYER TIPS on (setting `tips`). A few
## say a line of Mundell's too (barks.gd `tip_*`). tools/onboard_check.gd
## holds every tip to its moment, once, off with the setting, by device.
class_name Lessons
extends RefCounted

const FILE := "user://lessons.json"
## Seconds a tip stays up at the least, and the clear seconds after one.
const SHOW := 5.0
const GAP := 1.5
## Seconds between looks round for the costlier moments (a thing to tote,
## a rig, the bench, a locked door).
const SCAN := .2
## The tip banner's ink: the palette's chalk green (BLUE's badge's), apart
## from the notices' cream (the display maps every colour to the palette).
const INK := Color(169 / 255.0, 221 / 255.0, 75 / 255.0)

## Pad buttons by play action (main_state.gd _pad_bindings, read_pad).
const PAD := {
	"fire": "RT",
	"alt": "LT",
	"use": "Y",
	"reload": "X",
	"jump": "A",
	"crouch": "B",
	"prev_weapon": "D-PAD DOWN",
	"next_weapon": "RB",
	"kick": "R3",
	"throw": "LB",
	"run": "L3",
	"map": "BACK",
	"whistle": "HOLD BACK",
	"flashlight": "R3",
}
## Touch buttons by play action (touch_controls.gd).
const TOUCH := {
	"fire": "FIRE",
	"alt": "ALT",
	"use": "USE",
	"jump": "JUMP",
	"crouch": "DUCK",
	"next_weapon": "NEXT",
	"map": "MAP",
	"whistle": "WHISTLE",
	"flashlight": "LIGHT",
	"kick": "KICK",
	"throw": "THROW",
}
## Mouse buttons for the actions the mouse does on a keyboard.
const MOUSE := {"fire": "LEFT CLICK", "alt": "RIGHT CLICK"}

## Every tip: id -> {device or "all": words}. {action} is that action's
## glyph for the device in use. The order of ORDER is who goes first.
const TIPS := {
	"fire":
	{
		"keys": "{fire} SHOOTS, {reload} RELOADS. {alt} IS THE GUN'S OTHER FIRE.",
		"pad": "{fire} SHOOTS, {reload} RELOADS. {alt} IS THE GUN'S OTHER FIRE.",
		"touch": "FIRE SHOOTS. STRAIGHT GUNS FIRE BY THEMSELVES AT A FOE IN THE SIGHTS.",
	},
	"move":
	{
		"keys": "{forward} {strafe_left} {back} {strafe_right} WALK, THE MOUSE AIMS, {run} RUNS.",
		"pad": "LEFT STICK WALKS, RIGHT STICK AIMS, L3 RUNS.",
		"touch": "LEFT THUMB WALKS, RIGHT THUMB AIMS.",
	},
	"map":
	{
		"keys": "THE ARROW UP TOP POINTS THE WAY, THE NUMBER'S STEPS LEFT. {map} SHOWS THE MAP.",
		"pad": "THE ARROW UP TOP POINTS THE WAY, THE NUMBER'S STEPS LEFT. BACK SHOWS THE MAP.",
		"touch": "THE ARROW UP TOP POINTS THE WAY, THE NUMBER'S STEPS LEFT. TAP MAP FOR THE MAP.",
	},
	"finish": {"all": "HE'S REELIN'! GET UP CLOSE AND {use} FINISHES HIM."},
	"kick":
	{
		"all": "UP CLOSE, {kick} (OR {use}) PUTS THE BOOT TO HIM. KICK HIM INTO SOMETHIN' MEAN.",
	},
	"locked":
	{
		"all": "LOCKED TIGHT. THE ARROW LEADS TO ITS KEY; KEYS YOU CARRY SHOW UNDER KEYS.",
	},
	"heal":
	{
		"keys": "{use_item} EATS OR DRINKS WHAT IS PICKED, {next_item} PICKS ANOTHER.",
		"pad": "D-PAD UP, LEFT AND RIGHT: A RIND, A BEER, A SWIG OF SHINE.",
		"touch": "RIND, BEER AND SHINE PATCH YOU UP. TAP ONE.",
	},
	"ride":
	{
		"keys":
		"A RIG! {use} GETS YOU IN. {forward} GAS, {back} BRAKE, THE MOUSE STEERS, {jump} SKIDS.",
		"pad":
		"A RIG! {use} GETS YOU IN. LEFT STICK GAS AND BRAKE, RIGHT STICK STEERS, {jump} SKIDS.",
		"touch": "A RIG! USE GETS YOU IN. THE STICK IS GAS AND BRAKE, DRAG TO STEER.",
	},
	"carry":
	{
		"all": "LOOSE JUNK CAN BE TOTED: {use} PICKS IT UP, {fire} CHUCKS IT, {alt} SETS IT DOWN.",
	},
	"bench": {"all": "MUNDELL'S JUNK BENCH: {use} TRADES SCRAP FOR DUCT-TAPE MODS ON YER GUNS."},
	"tnt":
	{
		"all":
		"HOLD {fire} TO LIGHT A STICK, LET GO TO CHUCK IT. HANG ON TOO LONG AND IT'S AT YER FEET.",
	},
	"hound":
	{
		"keys":
		"THAT'S BLUE, YER HOUND. {whistle} WHISTLES: AT A VARMINT HE SICS IT, AT A PICKUP HE FETCHES.",
		"pad":
		"THAT'S BLUE, YER HOUND. HOLD BACK TO WHISTLE: AT A VARMINT HE SICS IT, AT A PICKUP HE FETCHES.",
		"touch": "THAT'S BLUE, YER HOUND. TAP HIS BADGE TO WHISTLE: AT A VARMINT HE SICS IT.",
	},
	"guns":
	{
		"keys":
		"NUMBER KEYS OR THE MOUSE WHEEL CHANGE GUNS. SO DO {prev_weapon} AND {next_weapon}.",
		"pad": "{prev_weapon} AND {next_weapon} CHANGE GUNS.",
		"touch": "NEXT CHANGES GUNS.",
	},
	"pockets":
	{
		"keys":
		"FOOD AND DRINK GO IN YER STUFF, BOTTOM RIGHT. {next_item} PICKS ONE, {use_item} HAS IT.",
		"pad": "FOOD AND DRINK GO IN YER STUFF, BOTTOM RIGHT. THE D-PAD HAS ONE.",
		"touch": "FOOD AND DRINK GO IN YER STUFF, BOTTOM RIGHT. TAP ONE TO HAVE IT.",
	},
	"scrap": {"all": "SCRAP! THE JUNK BENCH NEAR EVERY CHAPTER'S START TRADES IT FOR GUN MODS."},
	"hound_hurt":
	{
		"all":
		"BLUE'S HURTIN'. HIS HIDE'S THE BAR ON HIS BADGE. DOWN, HOLD {use} BY HIM OR FEED HIM A RIND.",
	},
	"badge": {"all": "BLUE'S BADGE, BOTTOM LEFT: HOW HE FEELS AND WHAT HE'S UP TO."},
	"gut":
	{
		"all":
		"YER GUT'S FULL: A BIT SLOWER, AND THE COUNTY SPOTS YA SOONER. IT EMPTIES AS YOU GO.",
	},
	"drunk":
	{
		"all":
		"A LITTLE DRINK TAKES THE EDGE OFF HITS. TOO MUCH AND THE WORLD WOBBLES. IT WEARS OFF.",
	},
}
const ORDER := [
	"fire",
	"move",
	"finish",
	"kick",
	"locked",
	"heal",
	"ride",
	"carry",
	"bench",
	"tnt",
	"map",
	"hound",
	"guns",
	"pockets",
	"scrap",
	"hound_hurt",
	"badge",
	"gut",
	"drunk",
]
## Tips that wait out a fight (no hand after the player in sight).
const QUIET := ["hound", "guns", "pockets", "scrap", "badge", "bench", "carry"]
## Tips that can wait: they keep CALM_GAP clear after the last tip.
const CALM := ["hound", "guns", "scrap", "badge", "hound_hurt", "gut", "drunk"]
## Tips that cut short any other tip (up a second already).
const URGENT := ["fire", "finish", "kick"]
## Clear seconds after a tip before one that can wait.
const CALM_GAP := 9.0
## Tips Mundell says a line with (barks.gd `tip_<id>`).
const SPOKEN := ["hound", "carry", "ride", "bench", "locked"]

static var taught := {}
static var _loaded := false
## Where the taught tips are kept: "" for the run's own (path()); tools may
## point it at a scratch file of their own.
static var file := ""
## The last tip shown and its id (tools/onboard_walk.gd reads them).
static var last_shown := ""
static var last_id := ""
## What the costlier moments looked like at the last scan, and when.
static var _scan_at := -1.0
static var _seen := {}


## The file in use: `file`, else FILE, but a tool run (a SceneTree script)
## keeps its tips under the cache folder, never in a player's profile.
static func path() -> String:
	if file != "":
		return file
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-lessons.json")
	return FILE


## A brand-new profile's slate (tools): nothing taught, nothing read from disk.
static func forget() -> void:
	taught = {}
	_loaded = true
	last_shown = ""
	last_id = ""
	_scan_at = -1.0
	_seen = {}


## Every tip shown again from the next one (nothing kept on disk).
static func reset() -> void:
	forget()
	if FileAccess.file_exists(path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path()))


static func tick(game: Game) -> void:
	if not game.lessons or game.tips == 0 or game.in_hub or game.showing_tally:
		return
	if game.player != game.local_player or game.player.health <= 0:
		return
	if game.map or game.boss_hold > 0.0:
		return
	# One at a time: a tip is cut short (after a second) only by an urgent
	# one (a fight starting, a hand to finish or to boot).
	var up := game.tip_until > game.clock
	var cut := up and not URGENT.has(last_id)
	cut = cut and game.tip_until - game.clock < _shown_for(game) - 1.0
	var resting := game.tip != "" and game.tip_until + GAP > game.clock
	if (up and not cut) or (not up and resting):
		return
	var noticed := game.message_until > game.clock
	if not _loaded:
		_loaded = true
		# A new profile has no file: parsing "" would print an error.
		var text := FileAccess.get_file_as_string(path()) if FileAccess.file_exists(path()) else ""
		var parsed: Variant = JSON.parse_string(text) if text != "" else null
		taught = parsed if parsed is Dictionary else {}
	if game.clock < _scan_at or game.clock - _scan_at >= SCAN:
		_scan_at = game.clock
		_seen = _scan(game)
	var fighting: bool = _seen.get("fight", false)
	# The ones that can wait keep CALM_GAP clear after the last tip.
	var calm_ok := not up and (game.tip == "" or game.tip_until + CALM_GAP <= game.clock)
	for id: String in ORDER:
		if taught.has(id):
			continue
		if (QUIET.has(id) and fighting) or (CALM.has(id) and not calm_ok):
			continue
		if (cut or noticed) and not URGENT.has(id):
			continue  # only an urgent tip cuts one short or shows with a notice
		if _due(game, id):
			_teach(game, id)
			return


## How long the tip up now was given.
static func _shown_for(game: Game) -> float:
	return maxf(SHOW, 1.2 + .3 * game.tip.split(" ", false).size())


## Whether tip `id` has come up now.
static func _due(game: Game, id: String) -> bool:
	var p: Player = game.player
	match id:
		"fire":
			return _seen.get("fight", false)
		"move":
			return game.clock > 1.5
		"map":
			return taught.has("move") and game.clock > 7.0 and game.objective_target() != null
		"finish":
			return _seen.get("finish", false)
		"kick":
			return _seen.get("kick", false)
		"locked":
			return _seen.get("locked", false)
		"heal":
			return p.health < 55 and _has_food(game)
		"ride":
			return _seen.get("ride", false)
		"carry":
			return _seen.get("carry", false)
		"bench":
			return _seen.get("bench", false)
		"tnt":
			return game.armory.active == Weapons.DYNAMITE
		"hound":
			return game.clock > 14.0 and _dog_health(game) >= 0.0
		"guns":
			return _guns(game) >= 3
		"pockets":
			return _has_food(game)
		"scrap":
			return game.armory.scrap > 0 and BenchMods.on(game)
		"hound_hurt":
			return _dog_health(game) >= 0.0 and _dog_health(game) < 65.0
		"badge":
			return taught.has("hound") and game.clock > 75.0 and _dog_health(game) >= 0.0
		"gut":
			return p.gut >= 66.0
		"drunk":
			return p.drunk >= 38.0
	return false


## The costlier moments, looked for every SCAN seconds.
static func _scan(game: Game) -> Dictionary:
	var seen := {"fight": _threat_in_view(game)}
	var p: Player = game.player
	var brawl: Game.BrawlScript = game.features.get("brawl")
	var facing := Vector2.from_angle(p.view_angle())
	for e: Enemy in game.enemies:
		if not (e.alive and e.hostile) or BossKit.is_boss(e):
			continue
		var gap := Vector2(e.x - p.x, e.y - p.y)
		var d := gap.length()
		if d > 4.0 or not game.world.visible(p.x, p.y, e.x, e.y):
			continue
		if brawl != null and brawl.finishable(e):
			seen["finish"] = true
		if d < 1.6 + e.radius and gap.normalized().dot(facing) > cos(.62) and e.alerted:
			seen["kick"] = true
	var prompt := game.use_prompt()
	seen["locked"] = prompt.ends_with("KEY NEEDED")
	var held := prompt.begins_with("FIRE  THROW")
	seen["carry"] = held or prompt.find("PICK UP ") >= 0
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	seen["ride"] = rides != null and rides.prompt(p).find("DRIVE THE ") >= 0
	var bench: Game.BenchScript = game.features.get("bench")
	seen["bench"] = bench != null and bench.prompt(p) != ""
	return seen


## The words of tip `id` for the device in use.
static func words(game: Game, id: String) -> String:
	var table: Dictionary = TIPS[id]
	var device := game.input_device
	var text: String = table.get(device, table.get("all", table.get("keys", "")))
	var at := text.find("{")
	while at >= 0:
		var end := text.find("}", at)
		var action := text.substr(at + 1, end - at - 1)
		text = text.substr(0, at) + glyph(device, action) + text.substr(end + 1)
		at = text.find("{")
	return text


## What to press for a play action on a device: the bound key (or mouse
## button) on a keyboard, the button on a pad or a touch screen.
static func glyph(device: String, action: String) -> String:
	if device == "pad":
		return str(PAD.get(action, key(action)))
	if device == "touch":
		return str(TOUCH.get(action, action.to_upper()))
	if MOUSE.has(action):
		return str(MOUSE[action])
	return key(action)


## The key bound to a play action, by name.
static func key(action: String) -> String:
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return KeyBindings.key_name((event as InputEventKey).keycode)
	var code: int = KeyBindings.default_key(action)
	return KeyBindings.key_name(code) if code != KEY_NONE else "?"


static func _teach(game: Game, id: String) -> void:
	taught[id] = true
	var text := words(game, id)
	last_shown = text
	last_id = id
	game.tip = text
	game.tip_until = game.clock + _shown_for(game)
	if SPOKEN.has(id):
		game.barks.say(game, "tip_" + id, true)
	var out := FileAccess.open(path(), FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(taught))


## A hand after the player (or that has seen them) within 16 and in sight.
static func _threat_in_view(game: Game) -> bool:
	var p: Player = game.player
	for e: Enemy in game.enemies:
		if not (e.alive and e.hostile and (e.alerted or e.player_seen)):
			continue
		if absf(e.x - p.x) > 16.0 or absf(e.y - p.y) > 16.0:
			continue
		if game.world.visible(p.x, p.y, e.x, e.y):
			return true
	return false


## BLUE's health beside the player, -1 when he is not along.
static func _dog_health(game: Game) -> float:
	var hound: Game.HoundScript = game.features.get("hound")
	if hound == null:
		return -1.0
	var d: Game.HoundScript.Dog = hound.dog_of(game.player)
	return d.health if d != null else -1.0


static func _has_food(game: Game) -> bool:
	for name: String in HUD.ITEMS:
		var have: int = game.inventory.get(name, 0)
		if have > 0:
			return true
	return false


static func _guns(game: Game) -> int:
	var count := 0
	for owned: bool in game.armory.owned:
		if owned:
			count += 1
	return count
