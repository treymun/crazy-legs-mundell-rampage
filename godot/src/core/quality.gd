## QUALITY: the tiers a machine plays at (LOW, MEDIUM, HIGH) and what each
## picks: VIEW DETAIL, DRAW DISTANCE, LIGHTS AND GLOW and the physics detail.
## AUTO measures the frame's own work during the first seconds of play
## (Meter) and picks the tier once, with a phone or tablet capped
## (camera.cfg [quality]); a tier picked by hand sets the three settings at
## once, and the player may still change each afterwards.
##
## `physics` is the one number other systems read (the bowling pins' steps,
## anything heavy that can do with less on a slow phone): 0 LOW, 1 MEDIUM, 2
## HIGH. With more than one player (`shared`) everyone steps at HIGH, so every
## copy of a networked game works alike; a host or a tool that never sets it
## keeps HIGH.
class_name Quality
extends RefCounted

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const NAMES: Array[String] = ["LOW", "MEDIUM", "HIGH"]
const DATA := "res://data/tuning/camera.cfg"
## Where AUTO keeps the tier it measured (the settings file holds only
## settings): {"tier": n}.
const MEASURED_FILE := "user://quality.json"

static var physics := HIGH
static var shared := false
static var SETTLE: float = _num("settle")
static var MEASURE: float = _num("measure")
static var HIGH_MS: float = _num("high_ms")
static var MEDIUM_MS: float = _num("medium_ms")
static var PHONE_TOP: int = int(_num("phone_top"))


static func _num(key: String) -> float:
	var v: float = Tuning.file(DATA).get_value("quality", key, 0.0)
	return v


## The physics detail to step play at now (HIGH whenever several play).
static func level() -> int:
	return HIGH if shared else physics


## `full` steps of a solver cut to the physics detail (at least two): HIGH
## all of them, MEDIUM two thirds, LOW half.
static func steps(full: int) -> int:
	var k: float = [.5, .67, 1.0][clampi(level(), 0, 2)]
	return maxi(2, mini(full, ceili(full * k)))


## The settings a tier sets: VIEW DETAIL (0 HIGH, 1 LOW, 2 AUTO), DRAW
## DISTANCE (0 AUTO, 1 FAR, 2 NEAR), LIGHTS AND GLOW and SHADOWS (off on LOW).
static func preset(tier: int) -> Dictionary:
	match clampi(tier, LOW, HIGH):
		LOW:
			return {"detail": 1, "draw_distance": 2, "lights": 0, "shadows": 0}
		MEDIUM:
			return {"detail": 2, "draw_distance": 2, "lights": 1, "shadows": 1}
	return {"detail": 2, "draw_distance": 1, "lights": 1, "shadows": 1}


## The tier the device alone suggests before anything is measured.
static func device_tier(phone: bool) -> int:
	return mini(PHONE_TOP, HIGH) if phone else HIGH


## The tier from a measured average of the frame's own work (ms), never
## above what the device allows.
static func pick(phone: bool, work_ms: float) -> int:
	var tier := LOW
	if work_ms < HIGH_MS:
		tier = HIGH
	elif work_ms < MEDIUM_MS:
		tier = MEDIUM
	return mini(tier, device_tier(phone))


## The QUALITY setting (0 AUTO, 1 LOW, 2 MEDIUM, 3 HIGH) as the tier in
## force: AUTO is what was measured (-1: not yet, the device's guess).
static func tier_of(setting: int, measured: int, phone: bool) -> int:
	if setting > 0:
		return clampi(setting - 1, LOW, HIGH)
	return measured if measured >= 0 else device_tier(phone)


## The tier AUTO measured on this machine, or -1.
static func load_measured(path := MEASURED_FILE) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return -1
	var found: Dictionary = parsed
	var tier: Variant = found.get("tier", -1)
	if typeof(tier) != TYPE_INT and typeof(tier) != TYPE_FLOAT:
		return -1
	var whole: int = tier
	return clampi(whole, -1, HIGH)


## Keep (or forget, -1) the tier AUTO measured. Tools never write the
## player's profile.
static func save_measured(tier: int, path := MEASURED_FILE) -> void:
	if (
		path == MEASURED_FILE
		and Engine.get_main_loop() != null
		and Engine.get_main_loop().get_script() != null
	):
		return
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if handle != null:
		handle.store_string(JSON.stringify({"tier": tier}))
		handle.close()


## AUTO's measurement: fed each frame of play (its length and the frame's
## own work), it says the tier once it has seen enough (-1 until then).
class Meter:
	var phone := false
	var seen := 0.0
	var work := 0.0
	var frames := 0

	func _init(on_phone := false) -> void:
		phone = on_phone

	## One frame of play: `dt` seconds long, `work_ms` of it the game's own.
	func add(dt: float, work_ms: float) -> int:
		seen += dt
		if seen < Quality.SETTLE:
			return -1
		work += work_ms
		frames += 1
		if seen < Quality.SETTLE + Quality.MEASURE or frames < 10:
			return -1
		return Quality.pick(phone, work / frames)
