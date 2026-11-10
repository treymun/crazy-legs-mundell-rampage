## Port of game.py: shared player, combat, interaction and objective state.
##
## Everything the reference calls `world` is LevelData in the port (the JSON
## already carries the generated level), so `level` and `world` are the same
## object here.
class_name Game
extends RefCounted

const VIEW := 156
const WIDTH := 320
const HEIGHT := 200
const FOCAL := 230.0
const HUB_WIDTH := 50.0
const PLAYER_RADIUS := .19
const HUB_BOARD := Vector2(30.36, 44.13)
const GALLERY_STAND := Vector2(25.96, 33.42)
const GALLERY_TARGETS := [
	Vector3(29.54, 32.99, .68),
	Vector3(29.54, 33.56, 1.14),
	Vector3(29.54, 33.79, .65),
	Vector3(29.54, 33.15, 1.32)
]

const PROP_HEIGHTS := {
	"barrel": 1.04,
	"hay": .91,
	"pump": 1.43,
	"pump_b": 1.43,
	"sink": .89,
	"crate": .75,
	"jukebox": 1.45,
	"lamp": .24,
	"tree": 3.65,
	"tree_b": 3.65,
	"utilitypole": 3.85,
	"pickup_truck": 1.31,
	"pickup_truck_b": 1.20,
	"roadsign": 1.67,
	"bleacher_sign": 1.58,
	"mailbox": 1.18,
	"tire": .40,
	"windmill": 4.65,
	"silo": 3.78,
	"reeds": .58,
	"water_tower": 5.1,
}

const PICKUP_NAMES := {
	"key_brass": "BRASS BARN KEY",
	"key_steel": "STEEL PASTURE KEY",
	"bullets": ".38 ROUNDS",
	"shells": "BUCKSHOT",
	"dynamite": "DYNAMITE STICKS",
	"rinds": "PORK RINDS",
	"moonshine": "MOONSHINE",
	"beer": "BEER",
	"rifle_ammo": "RIFLE CARTRIDGES",
	"saw_ammo": "SAW BLADES",
	"arm_ammo": "ALIEN CELLS",
	"rocket_ammo": "BOTTLE ROCKETS",
	"rivet_ammo": "MILL RIVETS",
	"pressure_ammo": "SEALED PRESSURE CHARGES",
	"pa_patch": "PA PATCH LEAD",
	"whiskey": "WHISKEY",
	"cowpie": "COW PIE",
	"milk_ammo": "FRESH MILK",
	"bowling_ammo": "BOWLING BALLS",
	"keg_ammo": "POWDER KEGS",
	"cow_ammo": "SPARE COWS",
}

const ALIAS := {"riveter": "bowling_ball", "pressure_gun": "cow_launcher"}
const TASK_ITEMS := ["pa_patch"]

const AMMO := {
	"bullets": [Weapons.REVOLVER, 11],
	"shells": [Weapons.SHOTGUN, 10],
	"dynamite": [Weapons.CROSSBOW, 6],
	"rifle_ammo": [Weapons.RIFLE, 24],
	"saw_ammo": [Weapons.RIPSAW, 5],
	"arm_ammo": [Weapons.ARMGUN, 9],
	"rocket_ammo": [Weapons.ROCKET, 4],
	"rivet_ammo": [Weapons.BOWLING, 2],
	"pressure_ammo": [Weapons.COW, 2],
	"milk_ammo": [Weapons.TEAT, 40],
	"bowling_ammo": [Weapons.BOWLING, 2],
	"keg_ammo": [Weapons.KEG, 1],
	"cow_ammo": [Weapons.COW, 1],
}

const HUB_DISPATCH := [
	[
		"MISSING HOG",
		"COUNTY DISPATCH / MISSING HOG. LAST SEEN NEAR STANKY'S.",
		"RADIO: LOOK FOR THE HOG."
	],
	["HOG HOME", "HOG HOME. THE FAIR STILL HAS BESSIE'S PRIZE TAG.", "RADIO: THE HOG IS HOME."],
	[
		"BLUE TRUNK",
		"FAIR CLOSED. BLUE TRUNK SHIPPED TO BLACKWATER.",
		"RADIO: CHECK THE BLUE TRUNK."
	],
	[
		"LAST LOAD",
		"MILL QUIET. THE LAST LOAD WENT TO STILLWATER CUT.",
		"RADIO: KEEP THE LAST LOAD."
	],
	[
		"ALL CLEAR",
		"BESSIE'S TAG IS BACK. MUNDELL STILL OWES FOR THE JUGS.",
		"RADIO: THE TAG IS HOME."
	],
]

## scenery.REACTIONS: kind -> [cue, particle, count]
const REACTIONS := {
	"bottles": ["glass_break", "glass", 8],
	"cans": ["scenery_cans", "spark", 5],
	"prize": ["scenery_prize", "dust", 7],
	"scrap": ["scenery_scrap", "dust", 9],
	"pipe": ["scenery_pipe", "splash", 8],
	"belt": ["scenery_belt", "spark", 6],
	"tv": ["tv_pop", "spark", 9],
	"toilet": ["toilet_burst", "splash", 14],
	"vending": ["vending_clunk", "dust", 8],
	"window": ["window_smash", "glass", 14],
	"cancan": ["can_kick", "spark", 5],
	"jukebox": ["jukebox_hit", "spark", 7],
}

const WASH := {
	"hickston": [255, 226, 190, .10],
	"fair": [255, 200, 230, .12],
	"sawmill": [255, 214, 160, .13],
	"quarry": [178, 214, 255, .12]
}
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

const GRAVITY_SHOT := {
	"bolt": 2.2,
	"football": 2.4,
	"tnt": 6.9,
	"chalk_lob": 4.2,
	"fair_bottle": 5.5,
	"keg": 5.0,
	"cow": 1.8
}
const SHOT_SIZES := {
	"keg": .26,
	"cow": .30,
	"bowling": .18,
	"milk": .08,
	"football": .20,
	"blade": .15,
	"arm_bolt": .18,
	"tnt": .19,
	"barker_bolt": .24,
	"lantern_bolt": .18,
	"fair_bottle": .25,
	"chain_hook": .17,
	"valve_slug": .16,
	"deputy_slug": .10,
	"bottle_rocket": .22
}
const GLOW_SHOTS := ["plasma", "arm_bolt", "barker_bolt", "lantern_bolt"]
const NO_MARK_SURFACE := ["BACKBLAST", "LIT DYNAMITE", "STEAM", "CHALK"]

# ------------------------------------------------------------------ helpers


## Python's round(): a value exactly halfway goes to the even neighbour, where
## GDScript's round() goes away from zero (22.5 -> 22, not 23).
static func round_even(value: float) -> float:
	var low := floorf(value)
	var rest := value - low
	if rest > 0.5:
		return low + 1.0
	if rest < 0.5:
		return low
	return low if fmod(low, 2.0) == 0.0 else low + 1.0


## Deterministic, serialisable RNG (Python's Mersenne stream cannot be matched
## bit-for-bit; only its determinism is preserved). The state is 63 bits, so the
## top 53 of them (>> 10) give a float in [0, 1).
class Rng:
	var state := 0

	func _init(seed_value := 1997) -> void:
		state = ((seed_value + 1) * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF

	func next() -> float:
		state = (state * 6364136223846793005 + 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
		return float(state >> 10) / 9007199254740992.0

	func random() -> float:
		return next()

	func uniform(a: float, b: float) -> float:
		return a + (b - a) * next()

	func randf_range(a: float, b: float) -> float:
		return a + (b - a) * next()

	func choice(values: Array):
		return values[clampi(int(next() * values.size()), 0, values.size() - 1)]

	func get_state() -> int:
		return state

	func set_state(value: int) -> void:
		state = value


class Shot:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var kind := ""
	var life := 0.0
	var enemy := false
	var damage := 0
	var bounces := 0
	var travelled := 0.0
	var resting := false

	func _init(
		px := 0.0,
		py := 0.0,
		pz := 0.0,
		dx := 0.0,
		dy := 0.0,
		dz := 0.0,
		k := "",
		l := 0.0,
		e := false,
		dmg := 0,
		b := 0
	) -> void:
		x = px
		y = py
		z = pz
		vx = dx
		vy = dy
		vz = dz
		kind = k
		life = l
		enemy = e
		damage = dmg
		bounces = b


class Speck:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var life := 0.0
	var kind := ""

	func _init(
		px := 0.0, py := 0.0, pz := 0.0, dx := 0.0, dy := 0.0, dz := 0.0, l := 0.0, k := ""
	) -> void:
		x = px
		y = py
		z = pz
		vx = dx
		vy = dy
		vz = dz
		life = l
		kind = k


class Blast:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var age := 0.0
	var kind := "fire"

	func _init(px := 0.0, py := 0.0, pz := 0.0, k := "fire") -> void:
		x = px
		y = py
		z = pz
		kind = k


class Hazard:
	var kind := ""
	var x := 0.0
	var y := 0.0
	var radius := 0.0
	var warning := 0.0
	var life := 0.0
	var damage := 0
	var age := 0.0
	var next_hit := 0.0

	func _init(k := "", px := 0.0, py := 0.0, r := 0.0, w := 0.0, l := 0.0, dmg := 0) -> void:
		kind = k
		x = px
		y = py
		radius = r
		warning = w
		life = l
		damage = dmg


## Port of rampage2.Barks: one-liners with per-category cooldowns.
class Barks:
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
		"streak": ["WHO'S NEXT?", "I'M JUST GETTIN' WARMED UP.", "RAMPAGE TIME!", "LINE UP, BOYS."],
		"pickup_weapon":
		[
			"NOW WE'RE TALKIN'.",
			"COME TO PAPPY.",
			"THAT'LL DO NICELY.",
			"HOT DIGGITY.",
			"OH, YOU PURTY THING."
		],
		"pickup_food": ["GOOD EATIN'.", "MMM, SALTY.", "THAT HITS THE SPOT.", "WASH IT DOWN."],
		"hurt":
		["OW! THAT STUNG.", "WHY, I OUGHTA...", "YOU'LL PAY FER THAT.", "RIGHT IN THE OVERALLS!"],
		"low":
		["I'M SEEIN' THE LIGHT...", "NEED ME A SNACK.", "TOO MEAN TO DIE.", "SOMEBODY GET MAMA."],
		"reload": ["LOCK AND LOAD.", "ANOTHER ROUND.", "COME ON, COME ON...", "FEED THE BEAST."],
		"empty": ["CLICK. WELL, SHUCKS.", "OUT OF SHELLS!"],
		"drunk": ["HIC! WHO MOVED THE BARN?", "THE GROUND'S MOVIN'.", "I SEE TWO OF YA."],
		"secret": ["WELL, LOOKY HERE.", "NOW THAT'S A SECRET."],
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
		"secret": 4.0
	}
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

	func say(game, category: String, force := false) -> bool:
		if not enabled:
			return false
		var now: float = game.clock
		if (
			not force
			and (
				now < next_any
				or now - float(last_at.get(category, -99.0)) < float(COOLDOWN[category])
			)
		):
			return false
		var pool: Array = LINES[category]
		var choices: Array = []
		for line in pool:
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

	func kill(game) -> void:
		var recent: Array = []
		for t in recent_kills:
			if game.clock - float(t) < 7.0:
				recent.append(t)
		recent.append(game.clock)
		recent_kills = recent
		if recent_kills.size() >= 3:
			if say(game, "streak"):
				recent_kills.clear()
				return
		say(game, "kill")

	func visible(game) -> bool:
		return enabled and until > game.clock


## Port of rampage2.Cheats.
class Cheats:
	const CODES := {
		"hickgod": "HICK MODE: TOO MEAN TO DIE",
		"hickguns": "HICK MODE: ALL THE GUNS",
		"hickhp": "HICK MODE: FULL TANK",
		"hickbooze": "HICK MODE: STOCKED CELLAR",
		"hickbarks": "HICK MODE: BIG MOUTH",
	}
	var buffer := ""
	var god := false
	var used := false

	func feed(char: String, game) -> String:
		if char.length() != 1 or not char.to_lower() in "abcdefghijklmnopqrstuvwxyz":
			return ""
		buffer = (buffer + char.to_lower()).right(10)
		for code in CODES:
			if buffer.ends_with(code):
				buffer = ""
				apply(code, game)
				used = true
				var text: String = CODES[code]
				if code == "hickgod":
					text += " (ON)" if god else " (OFF)"
				return text
		return ""

	func apply(code: String, game) -> void:
		var p = game.player
		if code == "hickgod":
			god = not god
		elif code == "hickhp":
			p.health = 100
		elif code == "hickguns":
			var a = game.armory
			for i in Weapons.COUNT:
				a.owned[i] = true
				a.reserve[i] = Weapons.MAX_RESERVE[i]
		elif code == "hickbooze":
			for key in game.inventory:
				game.inventory[key] = 5
		elif code == "hickbarks":
			game.barks_off_by_code = game.barks.enabled
			game.barks.enabled = not game.barks.enabled


## Port of county_events.Gallery (the tin rooster shooting booth).
class Gallery:
	const GOAL := 4
	const LIMIT := 16.0
	const ROUNDS := 6
	const RADIUS := .135
	const TARGETS := [
		Vector3(29.54, 32.99, .68),
		Vector3(29.54, 33.56, 1.14),
		Vector3(29.54, 33.79, .65),
		Vector3(29.54, 33.15, 1.32)
	]

	var rewarded := false
	var active := false
	var clock := 0.0
	var next_target := 2.35
	var hits := 0
	var spent := 0
	var index := 0
	var held := true
	var pistol: Weapons.Armory = null

	func _init() -> void:
		pistol = Weapons.Armory.new(Weapons.REVOLVER)

	func toggle(game) -> void:
		if active:
			finish(game, "GALLERY CLOSED. E TO TRY AGAIN.")
			return
		if game.armory.fuse > 0.0:
			game.message("THROW THE LIT STICK FIRST.")
			return
		active = true
		clock = 0.0
		next_target = 2.35
		hits = 0
		spent = 0
		index = 0
		held = true
		pistol = Weapons.Armory.new(Weapons.REVOLVER)
		game.message("TIN ROOSTER / 4 HITS, 6 BORROWED ROUNDS.", 2.1)
		game.sound.play("menu_accept")

	func prompt() -> String:
		return "E  CLOSE GALLERY" if active else "E  PLAY TIN ROOSTER"

	func hud() -> String:
		return (
			"TIN ROOSTER  %d/4  ROUNDS %d  TIME %02d"
			% [hits, ROUNDS - spent, int(ceil(LIMIT - clock))]
		)

	func sprite(game):
		var t: Vector3 = TARGETS[index]
		var out := Renderer.Sprite.new(
			t.x,
			t.y,
			"county_gallery_target",
			RADIUS * 2.0,
			game.world.elevation(t.x, t.y) + t.z - RADIUS
		)
		out.plane = PI * .5
		return out

	func finish(game, message: String) -> void:
		active = false
		game.message(message, 2.6)

	func advance_target() -> void:
		index = (index + 1) % TARGETS.size()
		next_target = clock + 2.35

	func tick(dt: float, game, fire: bool) -> void:
		var p = game.player
		clock += dt
		pistol.tick(dt, game)
		if not (25.10 <= p.x and p.x <= 28.66 and 32.77 <= p.y and p.y <= 33.94):
			finish(game, "LEFT THE GALLERY. E AT THE TICKET BOOTH TO RETRY.")
			return
		if clock >= LIMIT:
			finish(game, "TIME. E AT THE TICKET BOOTH TO RETRY.")
			return
		if clock >= next_target:
			advance_target()
		var tap := fire and not held
		held = fire
		if not tap or pistol.cooldown > 0.0:
			return
		spent += 1
		pistol.loaded[Weapons.REVOLVER] = ROUNDS - spent
		pistol.recoil = .54
		pistol.flash = .034
		pistol.cooldown = .18
		pistol.shot_age = 0.0
		game.sound.play("revolver", .56)
		var t: Vector3 = TARGETS[index]
		var z: float = t.z + game.world.elevation(t.x, t.y)
		var dx: float = t.x - p.x
		var dy: float = t.y - p.y
		var ax := cos(p.view_angle())
		var ay := sin(p.view_angle())
		var reach: float = dx * ax + dy * ay
		var hit_z: float = p.eye + reach * (p.pitch + p.sway) / FOCAL
		if (
			reach > 0.0
			and absf(dx * ay - dy * ax) < RADIUS
			and absf(z - hit_z) < RADIUS
			and game.world.visible(p.x, p.y, t.x, t.y, p.eye, z)
		):
			hits += 1
			game.sound_at("ricochet", t.x, t.y, .55)
			advance_target()
		if hits == GOAL:
			if rewarded:
				finish(game, "NICE SHOOTING. PRIZE ALREADY CLAIMED.")
			else:
				rewarded = true
				if not game.collect("rinds"):
					game.add_pickup("rinds", 26.47, 33.64)
				finish(game, "TIN ROOSTER WINNER. ONE BAG OF RINDS.")
			game.sound.play("menu_accept")
		elif spent == ROUNDS:
			finish(game, "OUT OF BORROWED ROUNDS. E TO TRY AGAIN.")


# ------------------------------------------------------------------- state

var art: Assets
var hud: HUD
var sound = null

var level: LevelData
var world: LevelData
var renderer: Renderer
var player: Player
var armory: Weapons.Armory

var enemy_ids: Array = []
var enemies: Array = []
var partners := {}
var wave: Array = []
var boss = null
var jerry = null
var bessie = null
var finale = null

var props: Array = []
var pickups: Array = []
var drums := {}
var inventory := {}
var inventory_slot := 0
var keys := {}
var stations_done := {}
var total_secrets := 0
var history: Array = []
var replay := false
var revisiting := false
var retained := {}
var music_bookmark = null
var in_hub := false
var gallery: Gallery = null
var supply_rule := 0
var gate_modes := {}
var hub_findings := {}
var hub_milestone := 0
var hub_dispatch_until := 0.0
var portal_request := ""
var entry := {}

var kills := 0
var secrets := 0
var total_kills := 0
var rng: Rng
var barks: Barks
var duck := 0.0
var cheats: Cheats
var barks_off_by_code := false
var last_low_bark := 0.0
var clock := 0.0
var spawn_grace := 3.2
var face_until := 0.0
var message_until := 0.0
var face := ""
var notice := ""
var hurt_flash := 0.0
var blast_flash := 0.0
var sprint := 0.0
var damage_feedback = null
var item_feedback = null
var step_number := 0
var next_belch := 0.0

var shots: Array = []
var specks: Array = []
## Gibs, blood pools and wall splats (gore.gd).
var gore_fx: Gore = Gore.new(self)
var blasts: Array = []
var hazards: Array = []
var wall_marks: Array = []
var wall_sound := 0.0
var map := false
var won := false
var legacy_completed := false
var legacy_key_route := false
var task_items := {}
var valve_turns := {}
var next_valve_turn := 0.0
var scenery_spent := {}
var bowled := {}
var exchanges: Array = []
var heard_exchanges := {}
var exchange_next := 0.0
var exchange_pending = null
var caption := ""
var caption_until := 0.0
var visited := {}
var district := 0
var district_until := 3.0
var amb_clock := 3.0
var jukebox_on := false
var flush_until := 0.0
var map_panel = null
var map_signature = null
var radio_check := 0.0

# Options (configure()).
var incoming := 1.0
var bob_scale := 1.0
## 0 = automatic (one band per core, capped at 16). Set by the options screen.
var look_bands := 0
## With gpu_look the grain, vignette, wash and brightness table are applied by
## palette.gdshader instead of in draw(); main.gd turns it on when there is a
## window. look_live / tone_live say which of them this frame wants.
var gpu_look := false
## The red hurt wash (0-255) the display shader lays over the view this frame.
var hurt_alpha := 0
var look_live := false
var tone_live := false
var flash_scale := 1.0
var gore := true
var aim_assist := 0
var district_labels := true
var hints := true
var hud_style := 0
var weapon_view := 0
var voice_captions := true
var bullet_marks := true
var retro_look := true
var flicker := true

## Final VGA brightness tone table (set by the front end when brightness != 100).
var tone = null


func _init(p_art: Assets, p_hud: HUD, p_sound, level_id := "hickston") -> void:
	art = p_art
	hud = p_hud
	sound = p_sound
	level = LevelData.load_level(level_id, art)
	world = level
	renderer = Renderer.new(art, level)
	player = Player.new(float(level.spawn[0]), float(level.spawn[1]), float(level.spawn[2]))
	player.eye += world.elevation(player.x, player.y)
	armory = Weapons.Armory.new()

	for i in level.enemies.size():
		var spec: Dictionary = level.enemies[i]
		enemy_ids.append(String(spec["id"]))
		enemies.append(
			Enemy.new(String(spec["kind"]), float(spec["x"]), float(spec["y"]), fmod(i * 2.3, TAU))
		)
	var by_id := {}
	for i in enemy_ids.size():
		by_id[enemy_ids[i]] = enemies[i]
	for pair in level.partners:
		if by_id.has(String(pair[0])) and by_id.has(String(pair[1])):
			partners[by_id[pair[0]].get_instance_id()] = [by_id[pair[1]], int(pair[2])]
	for key in level.patrols:
		var index := int(key)
		if index < 0 or index >= enemies.size():
			continue
		var enemy: Enemy = enemies[index]
		var route: Array = level.patrols[key]
		enemy.route = route
		enemy.patrol_pause = .32 + fmod(index * .73, 1.85)
		if not route.is_empty():
			enemy.angle = atan2(float(route[0][1]) - enemy.y, float(route[0][0]) - enemy.x)
	for index in level.reinforcements:
		if int(index) >= 0 and int(index) < enemies.size():
			wave.append(enemies[int(index)])
	for enemy: Enemy in wave:
		enemy.dormant = true
	for enemy: Enemy in wave:
		if Enemies_TELLS().has(enemy.kind):
			finale = enemy
			break
	if level.rescue:
		enemies[0].angle = PI * .58
		for enemy: Enemy in enemies:
			if enemy.kind == "boss" and boss == null:
				boss = enemy
			elif enemy.kind == "jerry" and jerry == null:
				jerry = enemy
			elif enemy.kind == "bessie" and bessie == null:
				bessie = enemy
		if boss != null:
			boss.angle = PI * .49
		if jerry != null:
			jerry.dormant = true

	for spec in level.props:
		var name := String(spec[0])
		var x := float(spec[1])
		var y := float(spec[2])
		var idx := int(y) * level.width + int(x)
		var z := world.elevation(x, y)
		if name == "lamp":
			z = level.roof[idx] - .25
		var spr := Renderer.Sprite.new(
			x,
			y,
			"prop_" + name + ("_0" if name == "windmill" else ""),
			float(PROP_HEIGHTS[name]),
			z
		)
		spr.glow = name == "lamp"
		if name == "roadsign" or name == "bleacher_sign":
			spr.plane = 0.0
		props.append(spr)

	for spec in level.pickups:
		var name := String(spec[0])
		pickups.append([String(ALIAS.get(name, name)), float(spec[1]), float(spec[2])])

	for point in level.fuel_drums:
		drums[Vector2(float(point[0]), float(point[1]))] = 18

	for name in HUD.ITEMS:
		inventory[name] = 0
	inventory["rinds"] = 1
	inventory_slot = 0

	for door: LevelData.Door in level.doors:
		if door.secret:
			total_secrets += 1
	for station: LevelData.Station in level.stations:
		if station.reveals_secret:
			total_secrets += 1

	gallery = Gallery.new() if level_id == "fair" else null
	exchanges = [] if in_hub else level.exchanges

	entry = loadout()
	rng = Rng.new(1997)
	barks = Barks.new()
	cheats = Cheats.new()
	total_kills = 0
	for enemy: Enemy in enemies:
		if enemy.hostile:
			total_kills += 1
	district = int(level.area[int(player.y) * level.width + int(player.x)])
	configure({})
	_build_grit()
	message(level.introduction, 5.0)


## TELLS keys (enemies.gd owns the table; keep the lookup without a type cycle).
func Enemies_TELLS() -> Dictionary:
	return {"rudy": "HORN SWEEP", "foreman": "CLEAR THE SAW LANES", "baron": "PIPE OUTLETS"}


# --------------------------------------------------------------- loadout


func loadout() -> Dictionary:
	return {
		"health": player.health,
		"owned": armory.owned.duplicate(),
		"loaded": armory.loaded.duplicate(),
		"reserve": armory.reserve.duplicate(),
		"active": armory.active,
		"inventory": inventory.duplicate(),
		"slot": inventory_slot
	}


func apply_loadout(kit: Dictionary) -> void:
	player.health = int(kit["health"])
	var owned: Array = kit["owned"]
	var loaded: Array = kit["loaded"]
	var reserve: Array = kit["reserve"]
	for i in mini(Weapons.COUNT, owned.size()):
		armory.owned[i] = bool(owned[i])
		armory.loaded[i] = int(loaded[i])
		armory.reserve[i] = int(reserve[i])
	armory.active = int(kit["active"])
	inventory = kit["inventory"].duplicate()
	inventory_slot = int(kit["slot"])


func result() -> Array:
	return [level.id, kills, total_kills, secrets, total_secrets, int(clock)]


var showing_tally: bool:
	get:
		return won and not revisiting

# -------------------------------------------------------------- configure


func configure(options: Dictionary) -> void:
	incoming = [0.66, 1.0, 1.34][clampi(int(options.get("difficulty", 1)), 0, 2)]
	bob_scale = float(options.get("bob", 100)) / 100.0
	flash_scale = [1.0, .32, 0.0][clampi(int(options.get("flashes", 0)), 0, 2)]
	gore = bool(options.get("gore", 1))
	aim_assist = int(options.get("aim_assist", 0))
	district_labels = bool(options.get("district_labels", 1))
	hints = bool(options.get("hints", 1))
	hud_style = int(options.get("hud_style", 0))
	renderer.world_motion = int(options.get("world_motion", 0))
	weapon_view = int(options.get("weapon_view", 0))
	voice_captions = bool(options.get("voice_captions", 1))
	bullet_marks = bool(options.get("bullet_marks", 1))
	retro_look = bool(options.get("retro_look", 1))
	flicker = bool(options.get("flicker", 1))
	armory.auto_switch = bool(options.get("auto_switch", 1))
	armory.auto_reload = bool(options.get("auto_reload", 1))
	var enabled := bool(options.get("barks", 1)) and not barks_off_by_code
	barks.enabled = enabled


func message(text: String, length := 1.9) -> void:
	notice = text
	message_until = clock + maxf(length, .70 + .16 * text.split(" ", false).size())


# ----------------------------------------------------------------- sound


func sound_position(x: float, y: float, strength := 1.0, muffle := true) -> Vector2:
	var p := player
	var dx := x - p.x
	var dy := y - p.y
	var distance := sqrt(dx * dx + dy * dy)
	var volume := strength / (1.0 + distance * .22)
	if muffle and distance > 1.0 and not world.visible(p.x, p.y, x, y):
		volume *= .43
	var pan := (-sin(p.view_angle()) * dx + cos(p.view_angle()) * dy) / maxf(1.0, distance)
	return Vector2(volume, pan)


func sound_at(name: String, x: float, y: float, strength := 1.0) -> void:
	var place := sound_position(x, y, strength)
	sound.play(name, place.x, place.y)
	var p := player
	if name != "bessie" and world.roof[int(p.y) * level.width + int(p.x)] != 0.0:
		if sound.has("room_" + name):
			sound.play("room_" + name, place.x * .55, place.y)


func report(name: String) -> void:
	sound.play(name)
	var p := player
	if world.roof[int(p.y) * level.width + int(p.x)] != 0.0:
		sound.play("room_" + name, .78)


func player_sheltered() -> bool:
	for enemy: Enemy in enemies:
		if enemy.alerted and enemy.hostile:
			return false
	var p := player
	var sx := float(level.spawn[0])
	var sy := float(level.spawn[1])
	return sqrt((p.x - sx) * (p.x - sx) + (p.y - sy) * (p.y - sy)) < 9.0


func wake_nearby(radius: float, x: float, y: float) -> void:
	for enemy: Enemy in enemies:
		var distance := sqrt((enemy.x - x) * (enemy.x - x) + (enemy.y - y) * (enemy.y - y))
		if (
			enemy.alive
			and enemy.hostile
			and not enemy.alerted
			and distance < radius
			and (distance < 1.45 or world.visible(x, y, enemy.x, enemy.y))
		):
			enemy.wake(self, x, y)


func disturb(x: float, y: float, radius: float, z = null) -> void:
	var source: float = world.elevation(x, y) + .78 if z == null else float(z)
	for actor: Enemy in enemies:
		if (
			not actor.alive
			or actor.alerted
			or actor.heard != null
			or Enemies_BOSS_TITLES().has(actor.kind)
			or actor.kind == "bessie"
			or actor.kind == "saucer"
		):
			continue
		var dx := actor.x - x
		var dy := actor.y - y
		var reach := radius if actor.hostile else minf(radius, 3.5)
		if dx * dx + dy * dy >= reach * reach:
			continue
		var ear: float = world.elevation(actor.x, actor.y) + actor.z + minf(.90, actor.height * .76)
		if not world.visible(x, y, actor.x, actor.y, source, ear):
			continue
		var ready: float = clock + .22 + sqrt(dx * dx + dy * dy) * .035
		actor.heard = [x, y, ready, clock + (2.6 if actor.hostile else 1.05)]
		if not actor.hostile:
			sound_at("chicken" if actor.kind == "chicken" else "pig", actor.x, actor.y, .43)


## Local copy of Enemies.BOSS_TITLES so this file does not have to reach across
## the module boundary at parse time. Both `.has(kind)` and `.get(kind, ...)`
## are used, so the values are the display titles, not placeholders.
func Enemies_BOSS_TITLES() -> Dictionary:
	return {
		"boss": "ALIEN SHERIFF",
		"jerry": "JERRY JONES",
		"rudy": "RUDY RACKET",
		"foreman": "SPLINTER FOREMAN",
		"baron": "COPPER BARON"
	}


# ----------------------------------------------------------------- damage


func damage(amount: float, source = null, cause := "HIT") -> void:
	if player.health <= 0:
		return
	var p := player
	if cheats.god:
		return
	var mellow: float = (
		.10 * float(15 <= p.drunk and p.drunk <= 56) + .09 * float(16 <= p.gut and p.gut <= 64)
	)
	amount = maxf(1.0, round_even(amount * (1.0 - mellow) * incoming))
	p.health = maxi(0, p.health - int(amount))
	if gallery != null and gallery.active:
		gallery.finish(self, "GALLERY CLOSED. CLEAR THE BOOTH AND RETRY.")
	var heading = null if source == null else atan2(float(source[1]) - p.y, float(source[0]) - p.x)
	damage_feedback = [heading, cause, clock + .64]
	hurt_flash = .27
	set_face("ouch_shock", .32)
	barks.say(self, "low" if p.health <= 25 else "hurt")
	sound.play("player_down" if p.health == 0 else "hurt")
	if p.health == 0:
		message("YOU BOUGHT THE FARM.", 8.0)


func add_pickup(name: String, x: float, y: float) -> void:
	pickups.append([name, x, y])


func collect(name: String) -> bool:
	name = String(ALIAS.get(name, name))
	if Weapons.NAMES.has(name):
		armory.pickup(Weapons.NAMES.find(name), self)
		barks.say(self, "pickup_weapon", true)
		set_face("grin_rampage", .6)
	elif HUD.ITEMS.has(name):
		if int(inventory[name]) >= 5:
			return false
		inventory[name] = int(inventory[name]) + 1
		message(String(PICKUP_NAMES[name]))
		barks.say(self, "pickup_food")
	elif TASK_ITEMS.has(name):
		task_items[name] = true
		message("PA PATCH LEAD. TAKE IT TO THE BACKSTAGE BOOTH.", 3.0)
	elif name.begins_with("key_"):
		keys[name] = true
		message(
			(
				"BRASS KEY - OPEN THE BARN."
				if name.ends_with("brass")
				else "STEEL KEY - OPEN THE PASTURE GATE."
			),
			4.0
		)
	else:
		if not AMMO.has(name):
			return false
		var entry_ammo: Array = AMMO[name]
		var slot := int(entry_ammo[0])
		var amount := int(entry_ammo[1])
		if supply_rule == 1:
			amount = maxi(1, int(round(amount * .70)))
		if not armory.add_ammo(slot, amount):
			return false
		if name == "dynamite" and not armory.owned[Weapons.DYNAMITE]:
			armory.owned[Weapons.DYNAMITE] = true
			message("DYNAMITE [8] - HOLD FIRE, RELEASE TO THROW", 3.5)
		else:
			message(String(PICKUP_NAMES[name]), 1.0)
	sound.play(
		(
			"key_pickup"
			if name.begins_with("key_")
			else "weapon_pickup" if Weapons.NAMES.has(name) else "pickup"
		),
		.8
	)
	return true


func use_item(slot := -1) -> void:
	if slot >= 0:
		inventory_slot = slot
	var i := inventory_slot
	var name: String = HUD.ITEMS[i]
	if int(inventory[name]) == 0:
		message("OUT OF " + String(HUD.ITEM_LABELS[i]) + ".", 1.05)
		return
	inventory[name] = int(inventory[name]) - 1
	var p := player
	var health := p.health
	var text := ""
	var state := ""
	if i == 0:
		p.gut = minf(100.0, p.gut + 37.0)
		p.health = mini(100, p.health + 28)
		if p.drunk > 52:
			p.drunk -= 13
		text = "PORK RINDS. GOOD EATIN'."
		state = "FULL GUT" if p.gut >= 86 else ""
	elif i == 1:
		p.drunk = minf(100.0, p.drunk + 36.0)
		p.health = mini(100, p.health + 16)
		text = "COLD BEER. EASY ON THE STEERING."
		state = "WOBBLY" if p.drunk > 82 else "BUZZED"
	elif i == 3:
		p.drunk = minf(100.0, p.drunk + 55.0)
		p.health = mini(100, p.health + 34)
		text = "WHISKEY. HAIR ON YER CHEST."
		state = "LOOSE" if p.drunk > 70 else "WARM"
	elif i == 4:
		p.gut = minf(100.0, p.gut + 48.0)
		p.drunk = maxf(0.0, p.drunk - 12.0)
		p.health = mini(100, p.health + 12)
		text = "COW PIE. DON'T ASK."
		state = "FULL GUT" if p.gut >= 86 else ""
	else:
		p.drunk = maxf(0.0, p.drunk - 70.0)
		p.gut = maxf(0.0, p.gut - 55.0)
		p.health = mini(100, p.health + 24)
		sprint = 7.0
		text = "THAT'LL PUT HAIR ON THE TRACTOR."
		state = "SPEED UP"
	sound.play(["crunch", "gulp", "moonshine", "whiskey_glug", "cowpie_pick"][i])
	message(text)
	var change := "+%d HP" % (p.health - health) if p.health > health else ""
	var bits: Array = []
	if change != "":
		bits.append(change)
	if state != "":
		bits.append(state)
	item_feedback = [name, "  ".join(bits), clock + 1.05]


# --------------------------------------------------------------- movement


## Mirrors Game.move_actor: axis-separated world move with body separation, so
## the player cannot walk through a hostile actor (or an actor through them).
func move_actor(body, dx: float, dy: float, radius: float) -> void:
	var p := player
	var neighbors: Array = []
	if body == p:
		for enemy: Enemy in enemies:
			if (
				enemy.hostile
				and enemy.alive
				and absf(p.x - enemy.x) < 1.1
				and absf(p.y - enemy.y) < 1.1
			):
				neighbors.append(enemy)
	elif body.hostile and absf(body.x - p.x) < 1.1 and absf(body.y - p.y) < 1.1:
		neighbors = [p]
	var occupied = null
	if not neighbors.is_empty():
		occupied = func(x: float, y: float) -> bool:
			for neighbor in neighbors:
				var enemy = neighbor if body == p else body
				var enemy_base: float = world.elevation(enemy.x, enemy.y) + enemy.z
				var player_base: float = world.elevation(p.x, p.y) + p.air
				if enemy_base >= player_base + (.80 if p.crouched else 1.16):
					continue
				if player_base >= enemy_base + enemy.height:
					continue
				var reach := PLAYER_RADIUS + minf(enemy.radius, .37)
				var distance: float = (
					(x - neighbor.x) * (x - neighbor.x) + (y - neighbor.y) * (y - neighbor.y)
				)
				# An old checkpoint may already overlap a body. Allow motion outward.
				if (
					distance < reach * reach
					and (
						distance
						< (
							(body.x - neighbor.x) * (body.x - neighbor.x)
							+ (body.y - neighbor.y) * (body.y - neighbor.y)
						)
					)
				):
					return true
			return false
	world.move(body, dx, dy, radius, occupied)


# ------------------------------------------------------------------- death


func enemy_down(enemy: Enemy) -> void:
	kills += 1
	if enemy.hostile:
		barks.kill(self)
	if not Enemies_BOSS_TITLES().has(enemy.kind):
		for actor: Enemy in enemies:
			if (
				Enemy.LOSS_RESPONDERS.has(actor.kind)
				and actor.alive
				and actor.alerted
				and not actor.responded
				and not actor.windup
				and sqrt(pow(actor.x - enemy.x, 2) + pow(actor.y - enemy.y, 2)) < 2.85
				and world.visible(actor.x, actor.y, enemy.x, enemy.y)
			):
				actor.retreat_from(self, enemy.x, enemy.y)
				sound_at("county_fall_back", actor.x, actor.y, .67)
				break
	if enemy == boss:
		if jerry != null:
			jerry.dormant = false
			jerry.wake(self, player.x, player.y)
			jerry.cooldown = 1.25
		message("THE SHERIFF'S DOWN. HERE COMES JERRY!", 4.0)
		sound.play("jerry_intro")
	elif enemy == jerry:
		message("THAT'S THE BALL GAME! GO GET BESSIE.", 5.0)
		sound.play("yee_haw")
		sound.sting("shakedown_end")
	elif enemy == finale:
		hazards.clear()
		var kept: Array = []
		for shot in shots:
			if shot.kind != "foreman_cut" and shot.kind != "rudy_horn":
				kept.append(shot)
		shots = kept
		var reward := String(
			{"rudy": "rocket_ammo", "foreman": "rivet_ammo", "baron": "pressure_ammo"}.get(
				enemy.kind, "bullets"
			)
		)
		add_pickup(String(reward), enemy.x, enemy.y)
		message(
			(
				String(Enemies_BOSS_TITLES().get(enemy.kind, "BOSS"))
				+ " IS DOWN. CLEAR THE LAST VARMINTS."
			),
			3.0
		)
		sound.sting(enemy.kind + "_end")
	elif enemy.kind == "boilerback":
		add_pickup("pressure_ammo", enemy.x, enemy.y)
	elif enemy.kind == "chalk_spitter" and rng.random() < .42 and supply_rule != 2:
		add_pickup("bullets", enemy.x, enemy.y)
	elif (
		(enemy.kind == "clone" or enemy.kind == "coot") and rng.random() < .65 and supply_rule != 2
	):
		add_pickup("bullets", enemy.x, enemy.y)
	elif enemy.kind == "billy" and rng.random() < .60 and supply_rule != 2:
		add_pickup("shells", enemy.x, enemy.y)
	if (
		enemy.hostile
		and not Enemies_BOSS_TITLES().has(enemy.kind)
		and supply_rule != 2
		and rng.random() < .07
	):
		add_pickup(String(rng.choice(HUD.ITEMS)), enemy.x + .2, enemy.y)
		message("FEELIN' LUCKY. SOMETHING DROPPED.", 1.6)
	if (
		world.extraction != null
		and world.extraction.shutdown in stations_done
		and _wave_has(enemy)
		and not _wave_alive()
	):
		message("THE EXIT IS CLEAR. GET MOVING.", 4.0)
		sound.play("gate")


func _wave_has(enemy: Enemy) -> bool:
	for member: Enemy in wave:
		if member == enemy:
			return true
	return false


func _wave_alive() -> bool:
	for member: Enemy in wave:
		if member.alive:
			return true
	return false


func set_face(value: String, duration: float) -> void:
	if face == "ouch_shock" and clock < face_until and value != "ouch_shock":
		return
	face = value
	face_until = clock + duration


func face_name() -> String:
	var health := player.health
	if health <= 0:
		return "dead"
	if face_until > clock:
		return face
	if player.drunk > 47:
		return "drunk_dizzy"
	if health <= 25:
		return "hurt_75"
	if health <= 50:
		return "hurt_50"
	if health <= 75:
		return "hurt_25"
	var phase := fmod(clock, 5.9)
	if 1.7 < phase and phase < 2.04:
		return "look_left"
	if 3.3 < phase and phase < 3.62:
		return "look_right"
	return "idle_blink" if phase > 5.75 else "idle_center"


# -------------------------------------------------------------- interaction


## Mirrors Game.use_target: returns [target, x, y] or null.
func use_target():
	if gallery != null and gallery.active:
		return [gallery, GALLERY_STAND.x, GALLERY_STAND.y]
	var facing := Vector2(cos(player.view_angle()), sin(player.view_angle()))
	if bessie != null and bessie.alive:
		var dx: float = bessie.x - player.x
		var dy: float = bessie.y - player.y
		var distance := sqrt(dx * dx + dy * dy)
		if (
			distance < 1.52
			and (distance < .55 or dx * facing.x + dy * facing.y > distance * .40)
			and world.visible(player.x, player.y, bessie.x, bessie.y)
		):
			return ["bessie", bessie.x, bessie.y]
	var doors: Array = []
	for door: LevelData.Door in world.doors:
		if (
			door.opened
			and (door.blast_only or world.controlled_doors.has(Vector2i(door.x, door.y)))
		):
			continue
		var centre := door.center()
		doors.append([door, centre.x, centre.y])
	var devices: Array = []
	for station: LevelData.Station in world.stations:
		if not station.reveals_secret or not stations_done.has(station.id):
			devices.append([station, station.x, station.y])
	if world.extraction != null:
		devices.append([world.extraction, world.extraction.x, world.extraction.y])
	if level.rescue:
		devices.append(["jukebox", 7.26, 17.14])
		devices.append(["sink", 3.2, 13.5])
	if gallery != null:
		devices.append([gallery, GALLERY_STAND.x, GALLERY_STAND.y])
	for note: LevelData.Note in level.notes:
		devices.append([note, note.x, note.y])
	# Rank candidates exactly like the reference: (not aimed, distance), so an
	# aimed target always beats an unaimed one no matter how far away it is.
	var best_worse := true
	var best_distance := INF
	var result = null
	for group in [[doors, 1.57, .50, .48], [devices, 1.45, .52, .40]]:
		var candidates: Array = group[0]
		var reach: float = group[1]
		var touch: float = group[2]
		var cone: float = group[3]
		for candidate in candidates:
			var target = candidate[0]
			var x: float = candidate[1]
			var y: float = candidate[2]
			var dx := x - player.x
			var dy := y - player.y
			var distance := sqrt(dx * dx + dy * dy)
			var aimed := dx * facing.x + dy * facing.y > distance * cone
			var worse := aimed == false
			# Reference rank is the tuple (not aimed, distance) compared with <.
			var better: bool
			if worse == best_worse:
				better = distance < best_distance
			else:
				better = worse == false
			if (
				distance < reach
				and (aimed or distance < touch)
				and better
				and world.visible(player.x, player.y, x, y)
			):
				best_worse = worse
				best_distance = distance
				result = [target, x, y]
	return result


func use_prompt() -> String:
	var found = use_target()
	if found == null:
		return ""
	var target = found[0]
	if target is String:
		if target == "bessie":
			var boss_alive: bool = boss != null and boss.alive
			var jerry_alive: bool = jerry != null and jerry.alive
			return "CLEAR THE PEN FIRST" if boss_alive or jerry_alive else "E  RESCUE BESSIE"
		if target == "jukebox":
			return "E  STOP JUKEBOX" if jukebox_on else "E  PLAY JUKEBOX"
		if target == "sink":
			return "E  USE SINK"
	if target is Gallery:
		return target.prompt()
	if target is LevelData.Note:
		return "E  READ " + target.label
	if target is LevelData.Station:
		var station: LevelData.Station = target
		if stations_done.has(station.id):
			return "ALREADY SET"
		if station.reveals_secret:
			return "E  CHECK THE LOOSE PANEL"
		for key in station.requires:
			if not stations_done.has(String(key)):
				return objective()
		if station.held != "" and not task_items.has(station.held):
			return "FIND THE PATCH LEAD AT THE RAFFLE OFFICE"
		if station.action == "strike":
			return "STRIKE THE BELT RELEASE"
		if station.action == "crank":
			return "E  TURN THE CONDENSER  %d/3" % int(valve_turns.get(station.id, 0))
		return "E  " + station.label
	if target is LevelData.Extraction:
		return "E  " + target.label if exit_ready() else "EXIT LOCKED / CHECK TAB MAP"
	var door: LevelData.Door = target
	if world.controlled_doors.has(Vector2i(door.x, door.y)):
		return "" if door.opened else "CONTROLLED BY A REMOTE SWITCH"
	if door.blast_only:
		return "POWDER STORE  /  BLAST PANEL"
	if door.key != "" and not keys.has(door.key):
		return "BRASS KEY NEEDED" if door.key.ends_with("brass") else "STEEL KEY NEEDED"
	if door.secret and not door.discovered:
		if world.crouch_doors.has(Vector2i(door.x, door.y)):
			return "CROUCH / USE THE LOW HATCH"
		return ""
	return "E  CLOSE DOOR" if door.opened else "E  OPEN DOOR"


func interact() -> void:
	if showing_tally or player.health <= 0:
		return
	var gate = portal_target()
	if gate != null:
		if world.locked_gates.has(gate):
			message(gate_text(gate), 3.0)
			sound.play("empty")
		elif armory.fuse > 0.0:
			message("THROW THE LIT STICK BEFORE LEAVING.", 3.0)
		else:
			portal_request = gate.destination
		return
	if in_hub:
		var clue = hub_clue()
		if clue != null:
			message(String(clue[4]), 4.0)
			if String(clue[0]) == "dispatch":
				if clock >= hub_dispatch_until:
					hub_dispatch_until = clock + 6.0
					var place := sound_position(HUB_BOARD.x, HUB_BOARD.y, .64)
					sound.play_voice("county_dispatch_%d" % hub_milestone, place.x, place.y)
					if voice_captions:
						caption = String(HUB_DISPATCH[hub_milestone][2])
						caption_until = clock + 2.4
			else:
				hub_findings[String(clue[0])] = true
				sound.play("menu_accept", .55)
		return
	var found = use_target()
	if found == null:
		return
	var target = found[0]
	var x: float = found[1]
	var y: float = found[2]
	if target is String:
		if target == "bessie":
			if (boss != null and boss.alive) or (jerry != null and jerry.alive):
				message("CLEAR THE PASTURE BEFORE YOU FREE BESSIE.", 2.4)
			elif revisiting:
				message("BESSIE IS SAFE. RETURN VIA THE ROAD GATE.", 2.4)
			else:
				finish_level("got_bessie")
			return
		if target == "jukebox":
			jukebox_on = not jukebox_on
			radio_check = 0.0
			sound_at("menu_accept", x, y, .54)
			message("JUKEBOX: HICKSTON SHUFFLE" if jukebox_on else "JUKEBOX OFF", 1.45)
			return
		if target == "sink":
			if clock >= flush_until:
				flush_until = clock + 1.35
				sound_at("sink_flush", x, y, .83)
				burst(x, y, .86, "splash", 8, .47)
				message("WASH UP, YOU ANIMAL.", 1.5)
			return
	if target is Gallery:
		target.toggle(self)
		return
	if target is LevelData.Note:
		message(target.text, 4.0)
		sound.play("menu_move", .40)
		return
	if target is LevelData.Station:
		operate_station(target)
		return
	if target is LevelData.Extraction:
		if revisiting:
			message("SHIFT DONE. RETURN VIA THE ROAD GATE.", 2.4)
		elif exit_ready():
			finish_level("gate")
		else:
			message(objective(), 3.0)
		return
	var door: LevelData.Door = target
	if world.controlled_doors.has(Vector2i(door.x, door.y)):
		if not door.opened:
			message("THAT GATE HAS A REMOTE SWITCH.", 2.5)
		return
	if door.key != "" and not keys.has(door.key):
		message(
			(
				"NEEDS THE BRASS BARN KEY."
				if door.key.ends_with("brass")
				else "NEEDS THE STEEL PASTURE KEY."
			),
			2.7
		)
		sound.play("empty")
		return
	if door.blast_only:
		message("POWDER STORE. THAT PANEL NEEDS DYNAMITE.", 2.65)
		sound.play("empty", .56)
		return
	if (
		world.crouch_doors.has(Vector2i(door.x, door.y))
		and not player.crouched
		and not door.discovered
	):
		message("GET LOW AND TRY THE HATCH AGAIN.", 3.0)
		return
	toggle_door(door, not door.opened)


# ----------------------------------------------------------------- stations


func set_station_lights(station: LevelData.Station) -> void:
	for sector_v in station.sectors:
		var sector := int(sector_v)
		var n := world.area.size()
		for i in n:
			if int(world.area[i]) == sector:
				world.light[i] += .26
		for i in world.wall_count:
			var o := i * LevelData.WALL_STRIDE
			if int(world.walls[o + 8]) == sector:
				world.walls[o + 5] += .26


func activate_station(station: LevelData.Station) -> void:
	if stations_done.has(station.id):
		return
	for key in station.requires:
		if not stations_done.has(String(key)):
			message(objective(), 3.0)
			sound.play("empty")
			return
	stations_done[station.id] = true
	set_station_lights(station)
	for door: LevelData.Door in world.doors:
		var point := Vector2i(door.x, door.y)
		var required = world.access_doors.get(point)
		var satisfied := false
		if required != null:
			satisfied = true
			for key in required:
				if not stations_done.has(String(key)):
					satisfied = false
					break
		if station.opens.has(point) or (satisfied and not door.opened):
			toggle_door(door, true)
	if station.reveals_secret:
		secrets += 1
	if world.extraction != null and station.id == world.extraction.shutdown:
		for enemy: Enemy in wave:
			enemy.dormant = false
			enemy.wake(self, player.x, player.y)
			enemy.cooldown = 2.05 if enemy == finale else 1.15
		if finale != null:
			sound.sting(finale.kind + "_intro")
	sound_at(station.cue, station.x, station.y, .95)
	message(station.message, 4.0)


func operate_station(station: LevelData.Station) -> void:
	if stations_done.has(station.id):
		return
	if station.action == "strike":
		message("THE HANDLE'S STRIPPED. HIT THE BELT RELEASE.", 3.0)
		return
	if station.held != "" and not task_items.has(station.held):
		message("NEEDS THE PATCH LEAD FROM THE RAFFLE OFFICE.", 3.0)
		return
	if station.action == "crank":
		if clock < next_valve_turn:
			return
		next_valve_turn = clock + .20
		var turns := int(valve_turns.get(station.id, 0)) + 1
		if turns < 3:
			valve_turns[station.id] = turns
			sound_at("scenery_pipe", station.x, station.y, .67)
			message("CONDENSER VALVE  %d/3. KEEP TURNING." % turns, 2.0)
			return
		valve_turns.erase(station.id)
	activate_station(station)


func exit_ready() -> bool:
	if world.extraction == null:
		return false
	return stations_done.has(world.extraction.shutdown) and not _wave_alive()


func finish_level(cue: String) -> void:
	if not won:
		won = true
		shots.clear()
		hazards.clear()
		blasts.clear()
		specks.clear()
		sound.pause_world()
		sound.set_score("victory")
		sound.play(cue)


func portal_target(reach := 2.62):
	var portals: Array = world.hub_gates if in_hub else [world.return_gate]
	for gate in portals:
		if gate == null:
			continue
		if gate.approach(player.x, player.y, player.view_angle(), reach):
			var face: float = gate.y + (.17 if player.y - gate.y >= 0.0 else -.17)
			if world.visible(
				player.x,
				player.y,
				player.x,
				face,
				player.eye,
				world.elevation(player.x, face) + .93
			):
				return gate
	return null


func hub_clue():
	var label: String = String(HUB_DISPATCH[hub_milestone][0])
	var text: String = String(HUB_DISPATCH[hub_milestone][1])
	var best = null
	var nearest := 1.32 * 1.32
	var candidates: Array = world.hub_clues.duplicate()
	candidates.append(["dispatch", HUB_BOARD.x, HUB_BOARD.y, "READ " + label, text])
	for clue in candidates:
		var x: float = clue[1]
		var y: float = clue[2]
		var dx := x - player.x
		var dy := y - player.y
		var square := dx * dx + dy * dy
		if (
			square < nearest
			and dx * cos(player.view_angle()) + dy * sin(player.view_angle()) > .22
			and world.visible(player.x, player.y, x, y, player.eye, world.elevation(x, y) + .96)
		):
			best = clue
			nearest = square
	return best


func gate_text(gate: LevelData.Gate) -> String:
	if gate.destination == "hub":
		return "E  RETURN TO COUNTY CROSSROADS"
	if world.locked_gates.has(gate):
		var index := Campaign.ORDER.find(gate.destination)
		var previous: String = Campaign.ORDER[index - 1] if index > 0 else ""
		return "LOCKED / FINISH " + Campaign.title_of(previous)
	return (
		"E  "
		+ String(gate_modes.get(gate.destination, "ENTER"))
		+ " "
		+ Campaign.title_of(gate.destination)
	)


func toggle_door(door: LevelData.Door, opened: bool) -> void:
	door.opened = opened
	if door.blast_only and opened:
		door.progress = 1.0
		var centre := door.center()
		burst(centre.x, centre.y, .86, "dust", 11, 1.6)
	else:
		var centre := door.center()
		sound_at(
			"secret_slide" if door.secret else "gate" if door.key != "" else "door",
			centre.x,
			centre.y
		)
	if door.secret and not door.discovered:
		door.discovered = true
		secrets += 1
		message("YOU FOUND A SECRET!", 2.4)
		barks.say(self, "secret")
		sound.play("yee_haw")


# ------------------------------------------------------------ projectiles


func launch(
	x: float,
	y: float,
	z: float,
	angle: float,
	speed: float,
	kind: String,
	vz := 0.0,
	enemy := false,
	damage := 0,
	life := -1.0
) -> void:
	if life <= 0.0:
		life = 2.6 if kind == "blade" else 3.8 if enemy else 1.55
	shots.append(
		Shot.new(
			x,
			y,
			z,
			cos(angle) * speed,
			sin(angle) * speed,
			vz,
			kind,
			life,
			enemy,
			damage,
			3 if kind == "blade" else 0
		)
	)


func throw_dynamite(remaining: float) -> void:
	var p := player
	var aim := p.view_angle()
	var dx := cos(aim)
	var dy := sin(aim)
	var x := p.x + dx * .21
	var y := p.y + dy * .21
	if world.blocked(x, y, .05):
		x = p.x
		y = p.y
	if remaining <= 0.0:
		explode(Shot.new(p.x, p.y, p.eye - .30, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0))
		damage(21, [p.x, p.y], "LIT DYNAMITE")
		return
	shots.append(
		Shot.new(
			x,
			y,
			p.eye - .17,
			dx * 6.1,
			dy * 6.1,
			1.55 + p.pitch * .037,
			"tnt",
			remaining,
			false,
			0,
			5
		)
	)


## Mirrors Game.hitscan: hits actors, drums and breakable scenery, or chips the
## wall behind them. Returns true when anything was hit.
func hitscan(
	angle: float,
	slope: float,
	amount: float,
	max_range: float,
	spread: float,
	spark := true,
	pressure := false
) -> bool:
	var p := player
	var ax := cos(angle)
	var ay := sin(angle)
	var best: Enemy = null
	var near := max_range
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.kind == "bessie":
			continue
		var dx := enemy.x - p.x
		var dy := enemy.y - p.y
		var d := dx * ax + dy * ay
		var z := p.eye + d * slope
		var feet: float = enemy.z + world.elevation(enemy.x, enemy.y)
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < enemy.radius + spread
			and feet - .10 < z
			and z < feet + enemy.height + .10
			and world.visible(p.x, p.y, enemy.x, enemy.y, p.eye, z)
		):
			best = enemy
			near = d
	var drum = null
	for point in drums.keys():
		var vec: Vector2 = point
		var dx := vec.x - p.x
		var dy := vec.y - p.y
		var d := dx * ax + dy * ay
		var base: float = world.elevation(vec.x, vec.y)
		var z := p.eye + d * slope
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < .24 + spread
			and base <= z
			and z <= base + 1.10
			and world.visible(p.x, p.y, vec.x, vec.y, p.eye, z)
		):
			drum = vec
			near = d
	var scenery = null
	for prop: LevelData.Scenery in world.scenery:
		if scenery_used(prop):
			continue
		var dx := prop.x - p.x
		var dy := prop.y - p.y
		var d := dx * ax + dy * ay
		var height := p.eye + d * slope
		var base: float = world.elevation(prop.x, prop.y) + prop.z
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < prop.radius + spread
			and base - .08 < height
			and height < base + prop.height + .08
			and world.visible(p.x, p.y, prop.x, prop.y, p.eye, height)
		):
			scenery = prop
			near = d
	if scenery != null:
		hit_scenery(scenery)
		return true
	if drum != null:
		drum_hit(drum, amount)
		return true
	if best != null:
		best.hurt(amount, self, false, pressure)
		return true
	if spark:
		var steps := int(ceil(max_range / .105))
		for i in range(1, steps + 1):
			var d: float = i * max_range / steps
			var x := p.x + ax * d
			var y := p.y + ay * d
			var z := p.eye + d * slope
			var ix := clampi(int(x), 0, world.width - 1)
			var iy := clampi(int(y), 0, world.height - 1)
			var cell := iy * world.width + ix
			var floor_z: float = world.ground[cell]
			var roof_z: float = world.roof[cell]
			var surface_tile = null
			if z < floor_z:
				surface_tile = int(world.floor_tile[cell])
			elif 0.0 < roof_z and roof_z < z:
				surface_tile = int(world.ceiling_tile[cell])
			if surface_tile != null or world.blocked(x, y, .024, z):
				var pane = world.pane_at(x, y, z, .025)
				if pane != null:
					shatter(pane, z)
					return true
				var mark = (
					null
					if surface_tile != null
					else renderer.wall_mark(p.x, p.y, p.eye, ax, ay, slope, d)
				)
				var surface := ""
				if mark != null:
					surface = String(mark.material)
				else:
					var tile := int(world.solid[cell])
					if surface_tile == null and tile < 0:
						var candidates: Array = world.near_doors.get(Vector2i(ix, iy), [])
						for door: LevelData.Door in candidates:
							if door.blocks(x, y, .024):
								tile = door.material
								break
						if tile < 0:
							tile = int(world.floor_tile[cell])
					surface = world.impact_surface(
						int(surface_tile) if surface_tile != null else tile
					)
				if (
					mark != null
					and (
						armory.active == Weapons.REVOLVER
						or armory.active == Weapons.RIFLE
						or armory.active == Weapons.SHOTGUN
					)
				):
					wall_marks.append(mark)
					if wall_marks.size() > 38:
						wall_marks.pop_front()
				var hit_d: float = (i - .70) * max_range / steps
				x = p.x + ax * hit_d
				y = p.y + ay * hit_d
				if specks.size() < 144:
					var particle := String(
						(
							{"wood": "chips", "metal": "spark", "plaster": "powder", "dirt": "soil"}
							. get(surface, "chips")
						)
					)
					var pspeed := float(
						{"wood": .64, "metal": 1.21, "plaster": .53, "dirt": .48}.get(surface, .64)
					)
					burst(
						x,
						y,
						maxf(.04, minf(1.8, p.eye + hit_d * slope)),
						String(particle),
						3,
						float(pspeed)
					)
				if (
					(
						armory.active == Weapons.REVOLVER
						or armory.active == Weapons.RIFLE
						or armory.active == Weapons.SHOTGUN
						or armory.active == Weapons.RIVETER
						or armory.active == Weapons.PRESSURE
					)
					and clock >= wall_sound
				):
					wall_sound = clock + .08
					var cue := String(
						(
							{
								"wood": "impact_wood",
								"metal": "ricochet",
								"plaster": "impact_plaster",
								"dirt": "impact_dirt"
							}
							. get(surface, "impact_wood")
						)
					)
					if armory.active == Weapons.RIVETER:
						cue = "impact_rivet"
					elif armory.active == Weapons.PRESSURE:
						cue = "impact_pressure"
					sound_at(cue, x, y, .64)
				break
	return false


func assisted_aim(angle: float, slope: float) -> Array:
	if aim_assist == 0:
		return [angle, slope]
	var p := player
	var threshold := .047 if aim_assist == 2 else .025
	var best := INF
	var correction = null
	for e: Enemy in enemies:
		if not e.hostile or not e.alive:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var distance := sqrt(dx * dx + dy * dy)
		if not (.46 < distance and distance < 18.0):
			continue
		var yaw := atan2(dy, dx)
		var error := absf(fposmod(yaw - angle + PI, TAU) - PI)
		if error > threshold:
			continue
		var target: float = world.elevation(e.x, e.y) + e.z + e.height * .58
		var vertical := (target - p.eye) / distance
		if absf(vertical - slope) > .19:
			continue
		var score := error * 12.0 + absf(vertical - slope) * .4 + distance * .009
		if score < best and world.visible(p.x, p.y, e.x, e.y, p.eye, target):
			correction = [yaw if aim_assist == 2 else angle, vertical]
			best = score
	return correction if correction != null else [angle, slope]


func shatter(pane: Vector2i, z := .99) -> void:
	if world.broken_panes.has(pane):
		return
	world.broken_panes[pane] = true
	var x := float(pane.x) + .5
	var y := float(pane.y) + .5
	sound_at("glass_break", x, y, .96)
	burst(x, y, minf(1.6, maxf(.38, z)), "glass", 17, 1.95)
	disturb(x, y, 6.8, minf(1.6, maxf(.38, z)))


func burst(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	if kind == "gore" and not gore:
		return
	for _i in count:
		var angle := rng.random() * TAU
		var v := rng.uniform(.24, speed)
		specks.append(
			Speck.new(
				x,
				y,
				z,
				cos(angle) * v,
				sin(angle) * v,
				rng.uniform(.2, speed * 1.3),
				rng.uniform(.18, .68),
				kind
			)
		)


func drum_hit(point: Vector2, amount: float) -> void:
	if not drums.has(point):
		return
	drums[point] = int(drums[point]) - int(amount)
	var x := point.x
	var y := point.y
	var z: float = world.elevation(x, y) + .57
	if int(drums[point]) <= 0:
		drums.erase(point)
		explode(Shot.new(x, y, z, 0.0, 0.0, 0.0, "fuel", 0.0, false, 0))
	else:
		sound_at("ricochet", x, y, .6)
		burst(x, y, z, "spark", 4, .8)


func explode(shot: Shot) -> void:
	var x := shot.x
	var y := shot.y
	var z := maxf(.07, shot.z)
	var energy := shot.kind == "arm_bolt"
	var radius := 1.40 if energy else 2.8
	var strength := float(shot.damage) if energy else (125.0 if shot.kind == "fuel" else 160.0)
	if shot.kind == "bottle_rocket":
		radius = 1.72
		strength = float(shot.damage)
	elif shot.kind == "keg":
		radius = 3.7
		strength = 240.0
	elif shot.kind == "cow":
		radius = 2.3
		strength = float(shot.damage)
		sound_at("cow_moo", x, y, .9)
	blast_flash = maxf(blast_flash, .14 if energy else .27)
	duck = maxf(duck, 1.1 if not energy else .5)
	blasts.append(Blast.new(x, y, z, "energy" if energy else "fire"))
	var cue := (
		"arm_impact" if energy else ("rocket_pop" if shot.kind == "bottle_rocket" else "explosion")
	)
	sound_at(cue, x, y)
	burst(x, y, z, "plasma" if energy else "spark", 12 if energy else 23, 2.2 if energy else 3.3)
	burst(x, y, z, "dust", 6 if energy else 16, 2.3)
	wake_nearby(8.0 if energy else 16.0, x, y)
	if not energy:
		disturb(x, y, 3.5, z)
	for enemy: Enemy in enemies:
		var distance := sqrt((enemy.x - x) * (enemy.x - x) + (enemy.y - y) * (enemy.y - y))
		if enemy.alive and distance < radius and world.visible(x, y, enemy.x, enemy.y):
			enemy.hurt(maxi(1, int(strength * (1.0 - distance / (radius + .3)))), self, not energy)
	for prop: LevelData.Scenery in world.scenery:
		if (
			sqrt((prop.x - x) * (prop.x - x) + (prop.y - y) * (prop.y - y)) < radius
			and world.visible(x, y, prop.x, prop.y)
		):
			hit_scenery(prop)
	var p := player
	var distance := sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))
	if distance < radius * .75 and world.visible(x, y, p.x, p.y):
		damage(
			maxi(2, int((13.0 if energy else 30.0) * (1.0 - distance / (radius * .75)))),
			[x, y],
			"BLAST" if shot.enemy or shot.kind == "fuel" else "BACKBLAST"
		)
	if not energy:
		for pane in world.pane_tiles:
			if sqrt(pow(float(pane.x) + .5 - x, 2) + pow(float(pane.y) + .5 - y, 2)) < 2.0:
				shatter(pane)
		for point in drums.keys():
			var vec: Vector2 = point
			if (
				sqrt(pow(vec.x - x, 2) + pow(vec.y - y, 2)) < 2.2
				and world.visible(x, y, vec.x, vec.y)
			):
				drum_hit(vec, 20)
		for door: LevelData.Door in world.doors:
			var centre := door.center()
			if (
				(level.rescue or door.blast_only)
				and shot.kind != "bottle_rocket"
				and door.secret
				and not door.opened
				and sqrt(pow(centre.x - x, 2) + pow(centre.y - y, 2)) < 1.27
			):
				toggle_door(door, true)


func scenery_used(prop: LevelData.Scenery) -> bool:
	return scenery_spent.has(prop.id) or stations_done.has(prop.station)


func hit_scenery(prop: LevelData.Scenery) -> void:
	if scenery_used(prop):
		return
	scenery_spent[prop.id] = true
	var reaction: Array = REACTIONS.get(prop.kind, ["scenery_scrap", "dust", 6])
	var cue: String = reaction[0]
	var particle: String = reaction[1]
	var count: int = reaction[2]
	var height: float = world.elevation(prop.x, prop.y) + prop.z + prop.height * .51
	sound_at(cue, prop.x, prop.y, .72)
	if prop.kind in ["pipe", "belt", "cans", "bottles"]:
		disturb(prop.x, prop.y, 5.2, height)
	if world.ruptures.has(prop.id):
		var rupture: Array = world.ruptures[prop.id]
		add_hazard("steam", float(rupture[0]), float(rupture[1]), .48, .66, 2.20, 8)
		sound_at("pressure_vent", float(rupture[0]), float(rupture[1]), .52)
		message(String(rupture[2]), 2.2)
	burst(prop.x, prop.y, height, particle, count, 1.1)
	if not prop.opens.is_empty():
		for door: LevelData.Door in world.doors:
			if prop.opens.has(Vector2i(door.x, door.y)):
				toggle_door(door, true)
		message("THE SERVICE CUT IS OPEN.", 2.8)
	if prop.station != "":
		for station: LevelData.Station in world.stations:
			if station.id == prop.station:
				activate_station(station)
				break


func finish_shot(shot: Shot) -> void:
	if shot.kind in ["bolt", "arm_bolt", "tnt", "bottle_rocket", "keg", "cow"]:
		explode(shot)
	elif shot.kind == "football":
		burst(shot.x, shot.y, shot.z, "dust", 8, 1.3)
		sound_at("football_bounce", shot.x, shot.y)
	elif shot.kind == "chalk_lob":
		add_hazard("chalk", shot.x, shot.y, .89, .08, 2.75, 6)
		sound_at("chalk_pop", shot.x, shot.y, .67)
	elif shot.kind == "fair_bottle":
		burst(shot.x, shot.y, shot.z, "glass", 13, 1.7)
		sound_at("tosser_glass", shot.x, shot.y, .8)
		var p := player
		if (
			p.air < .27
			and sqrt(pow(p.x - shot.x, 2) + pow(p.y - shot.y, 2)) < .77
			and world.visible(shot.x, shot.y, p.x, p.y, shot.z, p.eye)
		):
			damage(10, [shot.x, shot.y], "GLASS")
	elif shot.kind in ["deputy_slug", "chain_hook", "valve_slug"]:
		burst(shot.x, shot.y, shot.z, "spark" if shot.kind == "chain_hook" else "dust", 3, .75)


func move_shot(shot: Shot, dt: float) -> bool:
	# Small swept steps catch narrow doors, shallow floors and fast enemies.
	var distance: float = sqrt(shot.vx * shot.vx + shot.vy * shot.vy + shot.vz * shot.vz) * dt
	var steps := maxi(1, int(ceil(distance / .09)))
	dt /= steps
	var gravity: float = float(GRAVITY_SHOT.get(shot.kind, 0.0))
	var tnt := shot.kind == "tnt"
	for _step in steps:
		shot.life -= dt
		if shot.life <= 0.0:
			finish_shot(shot)
			return false
		if shot.resting:
			continue
		var x := shot.x + shot.vx * dt
		var y := shot.y + shot.vy * dt
		var z := shot.z + shot.vz * dt
		shot.vz -= dt * gravity
		var wall := world.blocked(x, y, .045, z)
		if wall and not shot.enemy and not tnt:
			var pane = world.pane_at(x, y, z, .045)
			if pane != null:
				shatter(pane, z)
				wall = world.blocked(x, y, .045, z)
		var roof: float = world.roof[int(y) * world.width + int(x)] if not wall else 0.0
		var plane: bool = (
			not wall and (z < world.elevation(x, y) + .045 or (0.0 < roof and roof <= z + .045))
		)
		if wall or plane:
			if tnt and (shot.bounces <= 0 or (plane and absf(shot.vz) < .77 and not wall)):
				shot.vx = 0.0
				shot.vy = 0.0
				shot.vz = 0.0
				shot.resting = true
				continue
			if shot.bounces <= 0:
				finish_shot(shot)
				return false
			if wall:
				var across_x := world.blocked(x, shot.y, .045, z)
				var across_y := world.blocked(shot.x, y, .045, z)
				if across_x or not across_y:
					shot.vx *= -.57 if tnt else -.86
				if across_y or not across_x:
					shot.vy *= -.57 if tnt else -.86
			else:
				shot.vz *= -.46 if tnt else -.88
				if tnt:
					shot.vx *= .64
					shot.vy *= .64
			shot.bounces -= 1
			sound_at("tnt_bounce" if tnt else "saw_bounce", shot.x, shot.y)
			if not tnt:
				burst(shot.x, shot.y, shot.z, "spark", 6, 1.4)
			continue
		var travel: float = sqrt(pow(x - shot.x, 2) + pow(y - shot.y, 2))
		if shot.kind == "bottle_rocket" and shot.travelled < .78 and shot.travelled + travel >= .78:
			sound_at("rocket_whistle", x, y, .68)
		shot.travelled += travel
		shot.x = x
		shot.y = y
		shot.z = z
		var p := player
		var ricochet: bool = shot.kind == "blade" and shot.bounces < 3 and shot.travelled > .72
		if (
			((shot.enemy and shot.kind != "chalk_lob" and shot.kind != "fair_bottle") or ricochet)
			and sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) < .28
			and p.eye - (.80 if not p.crouched else .55) < z
			and z < p.eye + .32
		):
			damage(
				float(shot.damage) if shot.enemy else 24.0,
				[shot.x - shot.vx * .18, shot.y - shot.vy * .18],
				"FIRE" if shot.enemy else "RICOCHET"
			)
			finish_shot(shot)
			return false
		if shot.enemy or tnt:
			continue
		var drum = null
		for point in drums.keys():
			var vec: Vector2 = point
			if (
				sqrt(pow(vec.x - x, 2) + pow(vec.y - y, 2)) < .27
				and 0.0 <= z - world.elevation(vec.x, vec.y)
				and z - world.elevation(vec.x, vec.y) <= 1.07
			):
				drum = vec
				break
		if drum != null:
			drum_hit(drum, 25)
			return false
		for enemy: Enemy in enemies:
			if not enemy.alive or enemy.kind == "bessie":
				continue
			var dz: float = z - enemy.z - world.elevation(enemy.x, enemy.y)
			if (
				-.07 < dz
				and dz < enemy.height + .05
				and sqrt(pow(enemy.x - x, 2) + pow(enemy.y - y, 2)) < enemy.radius + .10
			):
				if shot.kind == "blade":
					enemy.hurt(shot.damage, self)
					sound_at("saw_hit", x, y)
				elif shot.kind == "bowling":
					var key := shot.get_instance_id()
					if not bowled.has(key):
						bowled[key] = {}
					var seen: Dictionary = bowled[key]
					var eid := enemy.get_instance_id()
					if not seen.has(eid):
						seen[eid] = true
						enemy.hurt(shot.damage, self)
						sound_at("bowling_hit", x, y)
						burst(x, y, z, "dust", 6, 1.4)
						shot.vx *= .8
						shot.vy *= .8
				else:
					finish_shot(shot)
				return false
	return true


func update_shots(dt: float) -> void:
	var kept: Array = []
	for shot in shots:
		if move_shot(shot, dt):
			kept.append(shot)
	shots = kept
	if finale != null and not finale.alive:
		var filtered: Array = []
		for shot in shots:
			if shot.kind != "foreman_cut" and shot.kind != "rudy_horn":
				filtered.append(shot)
		shots = filtered
	for speck in specks:
		speck.life -= dt
		speck.z += speck.vz * dt
		speck.vz -= dt * 6.0
		var x: float = speck.x + speck.vx * dt
		var y: float = speck.y + speck.vy * dt
		if not world.blocked(x, y):
			speck.x = x
			speck.y = y
	var alive_specks: Array = []
	for speck in specks:
		if speck.life > 0.0 and speck.z >= -.05:
			alive_specks.append(speck)
	specks = alive_specks
	gore_fx.tick(dt)
	for blast in blasts:
		blast.age += dt
	var alive_blasts: Array = []
	for blast in blasts:
		if blast.age < .64:
			alive_blasts.append(blast)
	blasts = alive_blasts


func add_hazard(
	kind: String, x: float, y: float, radius: float, warning: float, life: float, damage_amount: int
) -> void:
	if not world.blocked(x, y, .04):
		hazards.append(Hazard.new(kind, x, y, radius, warning, life, damage_amount))
		if hazards.size() > 7:
			hazards.pop_front()


func update_hazards(dt: float) -> void:
	var p := player
	for hazard: Hazard in hazards:
		hazard.age += dt
		if (
			hazard.warning <= hazard.age
			and hazard.age < hazard.life
			and hazard.age >= hazard.next_hit
			and p.air < .28
			and sqrt(pow(p.x - hazard.x, 2) + pow(p.y - hazard.y, 2)) < hazard.radius
			and world.visible(hazard.x, hazard.y, p.x, p.y)
		):
			damage(
				hazard.damage, [hazard.x, hazard.y], "STEAM" if hazard.kind == "steam" else "CHALK"
			)
			hazard.next_hit = hazard.life if hazard.kind == "steam" else hazard.age + .68
	var kept: Array = []
	for hazard: Hazard in hazards:
		if hazard.age < hazard.life:
			kept.append(hazard)
	hazards = kept


func relief_open() -> bool:
	return stations_done.has("relief-west") or stations_done.has("relief-east")


func pressure_ports(attacks: int) -> Array:
	var ports: Array = world.pressure_ports
	if ports.is_empty():
		return []
	var count := 1 if relief_open() else 2
	var offset := int(attacks / 2) % ports.size()
	var out: Array = []
	for i in count:
		out.append(ports[(offset + i) % ports.size()])
	return out


# -------------------------------------------------------------- ground marks


## Mirrors Game.ground_marks: decals, hazard rings, boss telegraphs, actor
## shadows. `dress_marks` rows stay raw JSON ([x,y,z,angle,reach,width,image]).
func ground_marks() -> Array:
	var p := player
	var marks: Array = []
	for row in world.dress_marks:
		var x := float(row[0])
		var y := float(row[1])
		var image := String(row[6])
		if level.rescue and ((y > 33.0) != in_hub):
			continue
		var reach := 14.0 if image == "fx_shadow" else 9.49
		if (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) >= reach * reach:
			continue
		marks.append(
			Renderer.GroundMark.new(
				x, y, float(row[2]), float(row[3]), float(row[4]), float(row[5]), image
			)
		)
	for stain: Renderer.GroundMark in gore_fx.blood_marks:
		if (stain.x - p.x) * (stain.x - p.x) + (stain.y - p.y) * (stain.y - p.y) < 81.0:
			marks.append(stain)
	if in_hub:
		return marks
	for hazard: Hazard in hazards:
		var kind := hazard.kind if hazard.age >= hazard.warning else "warning"
		marks.append(_spot(hazard.x, hazard.y, hazard.radius, kind))
	if player.y < 13.0:
		for point: Vector2 in world.pressure_ports:
			marks.append(_spot(point.x, point.y, .38, "outlet"))
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.windup <= 0.0 or enemy.aim_mark == null:
			continue
		var mark: Array = enemy.aim_mark
		var mx: float = mark[0]
		var my: float = mark[1]
		if enemy.kind == "chalk_spitter":
			marks.append(_spot(mx, my, .89, "warning"))
		elif enemy.kind == "bottle_tosser":
			marks.append(_spot(mx, my, .77, "warning"))
		elif enemy.kind == "baron" and enemy.attacks % 2 == 0:
			for point: Vector2 in pressure_ports(enemy.attacks):
				marks.append(_spot(point.x, point.y, .94, "warning"))
		elif enemy.kind == "foreman":
			var direction := atan2(my - enemy.y, mx - enemy.x)
			for lane in enemy.saw_lanes(direction, enemy.attacks + 1):
				var sx: float = lane[0]
				var sy: float = lane[1]
				var bearing: float = lane[2]
				var length := 0.0
				while length < 10.0:
					var step := length + .32
					if world.blocked(sx + cos(bearing) * step, sy + sin(bearing) * step, .03):
						break
					length = step
				if length > .4:
					var hx := sx + cos(bearing) * length / 2.0
					var hy := sy + sin(bearing) * length / 2.0
					marks.append(
						Renderer.GroundMark.new(
							hx,
							hy,
							world.elevation(sx, sy) + .003,
							bearing,
							length / 2.0,
							.30,
							"mark_lane"
						)
					)
	var nearby: Array = []
	for enemy: Enemy in enemies:
		if not enemy.alive:
			continue
		var distance: float = (enemy.x - p.x) * (enemy.x - p.x) + (enemy.y - p.y) * (enemy.y - p.y)
		if distance < 64.0:
			nearby.append([distance, enemy])
	nearby.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(6, nearby.size()):
		var enemy: Enemy = nearby[i][1]
		var radius := enemy.radius * (1.03 if enemy.z <= .02 else 1.28)
		marks.append(
			Renderer.GroundMark.new(
				enemy.x,
				enemy.y,
				world.elevation(enemy.x, enemy.y) + .003,
				enemy.angle,
				radius * 1.24,
				radius,
				"fx_shadow"
			)
		)
	return marks


func _spot(x: float, y: float, radius: float, kind: String) -> Renderer.GroundMark:
	return Renderer.GroundMark.new(
		x, y, world.elevation(x, y) + .003, 0.0, radius, radius, "mark_" + kind
	)


# ---------------------------------------------------------------- exchanges


func tick_exchanges(combat: bool) -> void:
	if exchanges.is_empty() or (not voice_captions and sound.voice_gain == 0.0):
		return
	if combat or won:
		if caption_until > clock or exchange_pending != null:
			sound.stop_voice()
			caption_until = 0.0
			exchange_pending = null
		exchange_next = clock + 3.5
		return
	if clock < exchange_next:
		return
	exchange_next = clock + .55
	var pending = exchange_pending
	exchange_pending = null
	var pool: Array = [pending] if pending != null else exchanges
	for exchange in pool:
		if (
			stations_done.has(exchange.stop_at)
			or (pending == null and heard_exchanges.has(exchange.id))
		):
			continue
		var p := player
		if (
			sqrt((p.x - exchange.x) * (p.x - exchange.x) + (p.y - exchange.y) * (p.y - exchange.y))
			> 4.25
		):
			continue
		if not world.visible(
			p.x, p.y, exchange.x, exchange.y, p.eye, world.elevation(exchange.x, exchange.y) + .95
		):
			continue
		var index := 0 if pending == null else 1
		var place := sound_position(exchange.x, exchange.y, .74, false)
		var length: float = sound.play_voice("talk_%s_%d" % [exchange.id, index], place.x, place.y)
		caption = String(exchange.lines[index])
		caption_until = clock + maxf(1.35, length + .15)
		if pending == null:
			heard_exchanges[exchange.id] = true
			exchange_pending = exchange
			exchange_next = caption_until + .18
		else:
			exchange_next = caption_until + 8.0
		break


# --------------------------------------------------------------------- tick


## Mirrors Game.tick: player physics, ambience, pickups, combat and hazards.
func tick(dt: float, controls) -> void:
	var p := player
	if showing_tally or p.health <= 0 or portal_request != "":
		if sound != null:
			sound.set_fuse(false)
			sound.set_tool(false)
			sound.stop_voice()
		return
	clock += dt
	spawn_grace = maxf(0.0, spawn_grace - dt)
	duck = maxf(0.0, duck - dt)
	if sound != null and sound.has_method("level_music"):
		sound.level_music(
			sound.music_gain * (1.0 - .5 * minf(1.0, duck) - (.2 if barks.visible(self) else 0.0))
		)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	blast_flash = maxf(0.0, blast_flash - dt)
	p.gut = maxf(0.0, p.gut - dt * .40)
	p.drunk = maxf(0.0, p.drunk - dt * (2.4 if sprint else .77))
	sprint = maxf(0.0, sprint - dt)
	var intoxication := maxf(0.0, (p.drunk - 23.0) / 77.0)
	if p.gut >= 66.0 and clock >= next_belch:
		next_belch = clock + 5.6
		sound.play("belch", .76)
		wake_nearby(5.7, p.x, p.y)
	if p.drunk > 62.0:
		barks.say(self, "drunk")
	p.sway = sin(clock * 3.15) * intoxication * 11.0
	p.drift = sin(clock * 2.3) * pow(intoxication, 2.0) * .12
	p.angle = fposmod(p.angle + controls.turn, TAU)
	p.pitch = maxf(-53.0, minf(53.0, p.pitch + controls.look))
	var forward: float = controls.forward
	var strafe: float = controls.strafe + (sin(clock * 4.0) * .39 if p.drunk > 82.0 else 0.0)
	var magnitude := maxf(1.0, sqrt(forward * forward + strafe * strafe))
	var speed: float = (3.85 if controls.running else 2.75) * (1.42 if sprint else 1.0) / magnitude
	speed *= 1.0 - maxf(0.0, p.gut - 65.0) * .004 - maxf(0.0, p.drunk - 70.0) * .004
	if world.surface_sound(int(world.floor_tile[world.cell(p.x, p.y)])) == "water":
		speed *= .69
	p.crouched = controls.crouch and p.air <= .01
	if p.crouched:
		speed *= .51
	var vx := cos(p.view_angle())
	var vy := sin(p.view_angle())
	var ox := p.x
	var oy := p.y
	var response := (
		1.0 - exp(-dt * (7.0 if p.air else 23.0 if forward != 0.0 or strafe != 0.0 else 30.0))
	)
	p.vx += (speed * (forward * vx - strafe * vy) - p.vx) * response
	p.vy += (speed * (forward * vy + strafe * vx) - p.vy) * response
	move_actor(p, p.vx * dt, p.vy * dt, PLAYER_RADIUS)
	if p.x == ox and absf(p.vx) > .02:
		p.vx = 0.0
	if p.y == oy and absf(p.vy) > .02:
		p.vy = 0.0
	if controls.jump and not p.jump_held and p.air == 0.0 and not controls.crouch:
		p.vertical_speed = 2.7
	p.jump_held = controls.jump
	var landed := false
	if p.air > 0.0 or p.vertical_speed > 0.0:
		p.air = maxf(0.0, p.air + p.vertical_speed * dt)
		p.vertical_speed -= dt * 9.2
		if p.air == 0.0:
			p.vertical_speed = 0.0
			landed = true
	var ground: float = world.elevation(p.x, p.y)
	var eye := (.68 if p.crouched else .95) + ground + p.air
	var roof: float = world.roof[world.cell(p.x, p.y)]
	if roof != 0.0 and eye > roof - .22:
		eye = roof - .22
		p.vertical_speed = minf(0.0, p.vertical_speed)
	p.eye += (eye - p.eye) * minf(1.0, dt * 17.0)
	p.motion = minf(
		1.0, sqrt((p.x - ox) * (p.x - ox) + (p.y - oy) * (p.y - oy)) / maxf(dt * 2.0, .0001)
	)
	if p.air == 0.0:
		p.walk_phase += (
			dt * 11.0 * p.motion * (1.25 if controls.running else .80 if p.crouched else 1.0)
		)
	p.bob = sin(p.walk_phase * 2.0) * p.motion * (0.0 if p.air else 1.9) * bob_scale
	var iy := int(p.y)
	var ix := int(p.x)
	var area := int(world.area[world.cell(p.x, p.y)])
	var ambience := level.ambience
	if (
		ambience == "mill"
		and (
			stations_done.has("relay")
			or (
				roof == 0.0 and sqrt((p.x - 24.3) * (p.x - 24.3) + (p.y - 6.7) * (p.y - 6.7)) > 13.0
			)
		)
	):
		ambience = "mill_bank"
	elif ambience == "quarry":
		ambience = (
			"quarry_after"
			if stations_done.has("bottling")
			else "quarry_line" if roof != 0.0 else "quarry"
		)
	elif ambience == "fair" and stations_done.has("broadcast"):
		ambience = "fair_after"
	var recovery = level.recovery_room
	if recovery != null and ambience != "quarry_after" and ambience != "fair_after":
		if (
			float(recovery[0]) <= p.x
			and p.x <= float(recovery[2])
			and float(recovery[1]) <= p.y
			and p.y <= float(recovery[3])
		):
			ambience = String(recovery[4])
	var room: String = ambience
	if room == "":
		room = "creek" if area == 9 else "barn" if area == 4 else "room" if roof != 0.0 else "yard"
	sound.set_room(room)
	if clock >= radio_check:
		radio_check = clock + .045
		if (
			level.rescue
			and jukebox_on
			and sqrt((p.x - 7.26) * (p.x - 7.26) + (p.y - 17.14) * (p.y - 17.14)) < 11.0
		):
			var place := sound_position(7.26, 17.14, .60)
			sound.set_radio(true, place.x, place.y)
		else:
			sound.set_radio(false)
	if area != district and p.motion > .15:
		district = area
		district_until = clock + 2.1
	if clock >= amb_clock:
		amb_clock = clock + 5.9
		if not world.distant_cues.is_empty():
			for cue_row in world.distant_cues:
				var cx: float = cue_row[0]
				var cy: float = cue_row[1]
				var cue := String(cue_row[2])
				if sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)) >= 10.0:
					continue
				if (
					(cue == "distant_mill_pump" and stations_done.has("relay"))
					or (
						cue in ["distant_quarry_bottler", "distant_quarry_pipe"]
						and stations_done.has("bottling")
					)
					or (
						cue in ["distant_fair_motif", "distant_fair_generator"]
						and stations_done.has("broadcast")
					)
				):
					continue
				if cue == "distant_fair_pa":
					if (
						stations_done.has("broadcast")
						or sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)) > 5.0
						or not world.visible(p.x, p.y, cx, cy)
						or clock < message_until
					):
						continue
					message("PA: WINNERS MUST FEED THEIR PRIZES.", 3.5)
				sound_at(cue, cx, cy, .55)
		elif level.rescue and area in [0, 5, 8, 9, 10] and roof == 0.0:
			var cue2 := "distant_dog" if area in [0, 8] else "distant_crow"
			sound.play(cue2, .24, .7 if int(clock) % 2 else -.64)
	var step := int(p.walk_phase / PI)
	if landed or step != step_number:
		var surface: String = world.surface_sound(int(world.floor_tile[world.cell(p.x, p.y)]))
		sound.play(
			"step_%s_%d" % [surface, step % 2], .77 if landed else .31 if controls.crouch else .55
		)
		if surface == "water":
			burst(p.x, p.y, ground + .16, "splash", 5 if landed else 3, .52)
		step_number = step
	visited[Vector2i(ix, iy)] = true
	if in_hub:
		return
	for point: Vector2i in world.discovery_rooms:
		var span: Array = world.discovery_rooms[point]
		if int(span[0]) <= ix and ix <= int(span[2]) and int(span[1]) <= iy and iy <= int(span[3]):
			for door: LevelData.Door in world.doors:
				if door.x == point.x and door.y == point.y:
					if not door.discovered:
						toggle_door(door, true)
					break
	world.update(dt, p, enemies)
	var remaining: Array = []
	for entry in pickups:
		var name := String(entry[0])
		var x := float(entry[1])
		var y := float(entry[2])
		if (
			(p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) >= .43 * .43
			or not world.visible(p.x, p.y, x, y)
			or not collect(name)
		):
			remaining.append(entry)
	pickups = remaining
	armory.tick(dt, self)
	if gallery != null and gallery.active:
		gallery.tick(dt, self, controls.fire or controls.alt_fire)
	elif controls.fire or controls.alt_fire:
		armory.fire(self, controls.alt_fire)
	else:
		armory.release_dynamite(self)
	sound.set_fuse(armory.fuse != 0.0)
	sound.set_tool(
		(
			armory.active == Weapons.RIPSAW
			and controls.alt_fire
			and armory.grinding
			and not armory.holstered
			and armory.reload == 0.0
			and p.health > 0
		)
	)
	for enemy: Enemy in enemies:
		enemy.tick(dt, self)
	update_shots(dt)
	if not hazards.is_empty():
		update_hazards(dt)
	var combat: bool = controls.fire or controls.alt_fire or hurt_flash > 0.0
	if not combat:
		for enemy: Enemy in enemies:
			if (
				enemy.alive
				and enemy.hostile
				and (enemy.windup > 0.0 or enemy.recovery > 0.0)
				and absf(enemy.x - p.x) < 6.0
				and absf(enemy.y - p.y) < 6.0
			):
				combat = true
				break
	tick_exchanges(combat)


# --------------------------------------------------------------- reflection


func reflection():
	if is_nan(world.mirror_x):
		return null
	var p := player
	var facing := fposmod(TAU - p.angle, TAU) - PI
	var direction := mini(4, int(absf(facing) / (PI / 4.0) + .5))
	var heading: String = ["front", "quarter", "side", "away", "back"][direction]
	var stride := 0
	if p.motion > .15 and p.air == 0.0:
		stride = int(round(sin(p.walk_phase)))
	var height := 1.24 if p.crouched else 1.65
	var feet: float = world.elevation(p.x, p.y) + p.air
	var out := Renderer.Sprite.new(p.x, p.y, "player_%s_%d" % [heading, stride], height, feet)
	out.flip = facing < 0.0 and direction < 4
	return out


# ------------------------------------------------------------------ sprites


func sprites() -> Array:
	var sprites: Array = []
	if in_hub:
		for sprite: Renderer.Sprite in props:
			if sprite.y >= 28.0 and sprite.x < HUB_WIDTH:
				sprites.append(sprite)
	else:
		sprites = props.duplicate()
	for board: LevelData.Billboard in world.billboards:
		if (in_hub and board.y < 33.0) or (level.rescue and not in_hub and board.y >= 34.0):
			continue
		var image := board.image
		if board.signal_name == "legacy-key":
			if legacy_key_route:
				image = "wing_town_legacy_key"
		elif board.signal_name != "":
			var active := (
				exit_ready()
				if board.signal_name == "exit"
				else won if board.signal_name == "cleared" else stations_done.has(board.signal_name)
			)
			image += "_on" if active else "_off"
		var z: float = world.elevation(board.x, board.y) + board.z
		var spr := Renderer.Sprite.new(board.x, board.y, image, board.height, z)
		spr.glow = board.glow
		spr.plane = board.plane
		sprites.append(spr)
		if board.back != "":
			var back := Renderer.Sprite.new(board.x, board.y, board.back, board.height, z)
			back.plane = board.plane + PI
			sprites.append(back)
	for point in drums.keys():
		var vec: Vector2 = point
		sprites.append(
			Renderer.Sprite.new(vec.x, vec.y, "prop_fuel", 1.04, world.elevation(vec.x, vec.y))
		)
	for sprite: Renderer.Sprite in sprites:
		if sprite.image.begins_with("prop_windmill_"):
			sprite.image = "prop_windmill_%d" % (int(clock * 5.0) % 3)
	if in_hub:
		# plane = 0: these are flat boards fixed in the world, as in the
		# reference, not sprites that turn to face the camera.
		var dispatch := Renderer.Sprite.new(
			HUB_BOARD.x, HUB_BOARD.y, "county_dispatch_%d" % hub_milestone, .46, 1.02
		)
		dispatch.plane = 0.0
		sprites.append(dispatch)
		if hub_milestone != 0:
			var trunk := hub_milestone in [2, 3]
			var prop := "county_dispatch_trunk" if trunk else "county_dispatch_tag"
			var tag := Renderer.Sprite.new(29.67, 44.12, prop, .31 if trunk else .24, .83)
			tag.plane = 0.0
			sprites.append(tag)
		var detail: int = renderer.world_motion
		var motion_speed: float = [1.0, .32, 0.0][detail]
		var dust_rows: Array = [
			[30.40, 46.85, 1.46, .19], [30.48, 45.95, 1.64, .28], [30.73, 44.95, 1.48, .37]
		]
		var dust: Array = []
		for i in 3 - detail:
			var row: Array = dust_rows[i]
			var dx: float = float(row[0]) + .11 * sin(clock * motion_speed * .68 + float(row[1]))
			var puff := Renderer.Sprite.new(
				dx, float(row[1]), "hub_dust", float(row[2]), float(row[3])
			)
			puff.translucent = true
			puff.plane = 0.0
			dust.append(puff)
		dust.sort_custom(
			func(a, b):
				return (
					sqrt(pow(a.x - player.x, 2) + pow(a.y - player.y, 2))
					> sqrt(pow(b.x - player.x, 2) + pow(b.y - player.y, 2))
				)
		)
		sprites.append_array(dust)
		return sprites
	for note: LevelData.Note in level.notes:
		var note_sprite := Renderer.Sprite.new(
			note.x, note.y, "county_note", .23, world.elevation(note.x, note.y) + .90
		)
		note_sprite.plane = note.plane
		sprites.append(note_sprite)
	if gallery != null:
		var gallery_sign := Renderer.Sprite.new(25.95, 32.72, "county_gallery_sign", .51, 1.03)
		gallery_sign.plane = 0.0
		sprites.append(gallery_sign)
		var backstop := Renderer.Sprite.new(29.90, 33.48, "county_gallery_backstop", 1.49, .19)
		backstop.plane = PI / 2.0
		sprites.append(backstop)
		if gallery.active:
			sprites.append(gallery.sprite(self))
	for room: LevelData.Interior in level.interior_art:
		var room_sprite := Renderer.Sprite.new(
			room.x,
			room.y,
			"county_room_" + room.art,
			room.height,
			world.elevation(room.x, room.y) + room.z
		)
		room_sprite.plane = room.plane
		sprites.append(room_sprite)
	for prop: LevelData.Scenery in world.scenery:
		var state := "spent" if scenery_used(prop) else "whole"
		sprites.append(
			Renderer.Sprite.new(
				prop.x,
				prop.y,
				"scenery_%s_%s" % [prop.kind, state],
				prop.height,
				world.elevation(prop.x, prop.y) + prop.z
			)
		)
	if finale != null and finale.kind == "rudy" and finale.alive:
		for point: Vector2 in world.boss_decoys:
			var decoy := Renderer.Sprite.new(
				point.x, point.y, "rudy_decoy", 1.65, world.elevation(point.x, point.y)
			)
			decoy.plane = 0.0
			sprites.append(decoy)
	for hazard: Hazard in hazards:
		if hazard.age >= hazard.warning:
			var mist := Renderer.Sprite.new(
				hazard.x,
				hazard.y,
				"fx_%s_mist" % hazard.kind,
				.47 if hazard.kind == "steam" else .32,
				world.elevation(hazard.x, hazard.y) + .03
			)
			mist.translucent = true
			sprites.append(mist)
	var observer := [player.x, player.y]
	var relieved := not world.pressure_ports.is_empty() and relief_open()
	for enemy: Enemy in enemies:
		var sprite = enemy.sprite(observer, relieved, clock)
		if sprite != null:
			sprite.z += world.elevation(sprite.x, sprite.y)
			sprites.append(sprite)
	for entry in pickups:
		var x := float(entry[1])
		var y := float(entry[2])
		var hover := .06 + sin(clock * 3.5 + x) * .035
		sprites.append(
			Renderer.Sprite.new(
				x, y, "item_" + String(entry[0]), .33, world.elevation(x, y) + hover
			)
		)
	for shot: Shot in shots:
		if (
			shot.enemy
			or shot.kind == "tnt"
			or (
				sqrt(
					(
						(shot.x - player.x) * (shot.x - player.x)
						+ (shot.y - player.y) * (shot.y - player.y)
					)
				)
				> .95
			)
		):
			var name := (
				"blade_%d" % (int(shot.travelled * 9.0) % 3) if shot.kind == "blade" else shot.kind
			)
			if shot.kind == "tnt":
				var phase := (
					int(shot.travelled * 12.0) if not shot.resting else int(shot.life * 9.0)
				)
				name += "_%d" % (phase % 3)
			var size: float = float(SHOT_SIZES.get(shot.kind, .14 if shot.enemy else .10))
			var shot_sprite := Renderer.Sprite.new(shot.x, shot.y, "fx_" + name, size, shot.z)
			shot_sprite.glow = GLOW_SHOTS.has(shot.kind)
			sprites.append(shot_sprite)
	for fx: Speck in specks:
		var speck_sprite := Renderer.Sprite.new(fx.x, fx.y, "fx_" + fx.kind, .095, fx.z)
		speck_sprite.glow = fx.kind == "spark"
		sprites.append(speck_sprite)
	for g: Gore.Gib in gore_fx.gibs:
		var chunk := Renderer.Sprite.new(g.x, g.y, g.image, g.size, g.z)
		chunk.flip = g.flip
		sprites.append(chunk)
	var blast_order: Array = []
	for blast: Blast in blasts:
		blast_order.append(
			[
				sqrt(
					(
						(blast.x - player.x) * (blast.x - player.x)
						+ (blast.y - player.y) * (blast.y - player.y)
					)
				),
				blast
			]
		)
	blast_order.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for entry in blast_order:
		var blast: Blast = entry[1]
		var smoke := blast.age >= .27
		var age := blast.age - .27 if smoke else blast.age
		var frame := mini(3, int(age * (11.0 if smoke else 16.0)))
		var size := .55 + blast.age * 1.3
		var z := maxf(.03, blast.z - size * .43 + blast.age * .63)
		var blast_sprite := Renderer.Sprite.new(
			blast.x, blast.y, "fx_%s_%d" % ["smoke" if smoke else blast.kind, frame], size, z
		)
		blast_sprite.glow = not smoke
		blast_sprite.translucent = true
		sprites.append(blast_sprite)
	return sprites


# ---------------------------------------------------------------- objective


func objective() -> String:
	if in_hub:
		return "FACE A GATE AND PRESS E OR SPACE"
	if revisiting:
		return "COMPLETED / RETURN AT THE ROAD GATE"
	if not level.rescue:
		var exit: LevelData.Extraction = world.extraction
		if exit == null:
			return ""
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return ""
		var primary: Array = []
		for key in shutdown.requires:
			if not world.objective_side_tasks.has(key):
				primary.append(String(key))
		var pending: Array = []
		for key in primary:
			if not stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in world.stations:
				if station.id == pending[0]:
					if station.held != "" and not task_items.has(station.held):
						return "FIND THE PA PATCH LEAD AT THE RAFFLE OFFICE"
					return station.label
		if not pending.is_empty():
			return world.control_name
		for station: LevelData.Station in world.stations:
			if world.objective_side_tasks.has(station.id) and not stations_done.has(station.id):
				return station.label
		if not stations_done.has(shutdown.id):
			return shutdown.label
		var threats := 0
		for enemy: Enemy in wave:
			if enemy.alive:
				threats += 1
		return "CLEAR EXIT THREATS: %d" % threats if threats else exit.label
	if (boss == null or not boss.alive) and (jerry == null or not jerry.alive):
		return "RESCUE BESSIE"
	if jerry != null and jerry.alive and not jerry.dormant:
		return "PASTURE / BEAT JERRY"
	if keys.has("key_steel"):
		return "PASTURE / FIND BESSIE"
	if keys.has("key_brass"):
		return (
			"BARN / STEEL KEY AT THE FEED SCALE"
			if legacy_key_route
			else "STEEL KEY / EAST AT THE STOCK REGISTRY"
		)
	return "STANKY'S / BRASS KEY IN DISPATCH"


func objective_target():
	if in_hub or revisiting:
		return null
	if not level.rescue:
		var exit: LevelData.Extraction = world.extraction
		if exit == null:
			return null
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return null
		var primary: Array = []
		for key in shutdown.requires:
			if not world.objective_side_tasks.has(key):
				primary.append(String(key))
		var pending: Array = []
		for key in primary:
			if not stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in world.stations:
				if station.id == pending[0]:
					if not (station.held != "" and not task_items.has(station.held)):
						return Vector2(station.x, station.y)
		if not pending.is_empty():
			var options: Array = []
			for station: LevelData.Station in world.stations:
				if pending.has(station.id):
					options.append(station)
			if options.is_empty():
				return null
			var near: LevelData.Station = options[0]
			for station: LevelData.Station in options:
				if (
					(
						(station.x - player.x) * (station.x - player.x)
						+ (station.y - player.y) * (station.y - player.y)
					)
					< (
						(near.x - player.x) * (near.x - player.x)
						+ (near.y - player.y) * (near.y - player.y)
					)
				):
					near = station
			return Vector2(near.x, near.y)
		for station: LevelData.Station in world.stations:
			if world.objective_side_tasks.has(station.id) and not stations_done.has(station.id):
				return Vector2(station.x, station.y)
		if not stations_done.has(shutdown.id):
			return Vector2(shutdown.x, shutdown.y)
		var threats: Array = []
		for enemy: Enemy in wave:
			if enemy.alive:
				threats.append(enemy)
		if not threats.is_empty():
			var near2: Enemy = threats[0]
			for enemy: Enemy in threats:
				if (
					(
						(enemy.x - player.x) * (enemy.x - player.x)
						+ (enemy.y - player.y) * (enemy.y - player.y)
					)
					< (
						(near2.x - player.x) * (near2.x - player.x)
						+ (near2.y - player.y) * (near2.y - player.y)
					)
				):
					near2 = enemy
			return Vector2(near2.x, near2.y)
		return Vector2(exit.x, exit.y)
	if boss != null and boss.alive:
		return Vector2(boss.x, boss.y)
	if jerry != null and jerry.alive:
		return Vector2(jerry.x, jerry.y)
	if bessie != null and bessie.alive:
		return Vector2(bessie.x, bessie.y)
	return null


func gate_prompt() -> String:
	var gate = portal_target()
	if gate != null:
		return gate_text(gate)
	var clue = hub_clue() if in_hub else null
	return "E  " + String(clue[3]) if clue != null else ""


# ---------------------------------------------------------------- feedback


func feedback(c: Canvas) -> void:
	if not in_hub:
		var p := player
		var alert = null
		var nearest := 10.5 * 10.5
		for enemy: Enemy in enemies:
			if not (
				enemy.alive
				and enemy.windup > 0.0
				and enemy.player_seen
				and (Enemy.RANGED.has(enemy.kind) or enemy.kind in ["clone", "billy", "coot"])
			):
				continue
			var dx := enemy.x - p.x
			var dy := enemy.y - p.y
			var square := dx * dx + dy * dy
			var turn := fposmod(atan2(dy, dx) - p.view_angle() + PI, TAU) - PI
			if absf(turn) > .70 and square < nearest:
				alert = turn
				nearest = square
		if alert != null:
			var side := "REAR" if absf(alert) > 2.41 else "LEFT" if float(alert) < 0.0 else "RIGHT"
			var label := "WINDUP " + side
			var width := 10 + PixelType.text_width(label, "mini")
			var x := (
				(WIDTH - width) / 2
				if side == "REAR"
				else 6 if side == "LEFT" else WIDTH - width - 6
			)
			HUD.panel(c, x, 74, width, 14, Canvas.rgb(40, 29, 22))
			HUD.text(c, label, x + 5, 78, "mini", Canvas.rgb(233, 188, 111), false, false)
	if item_feedback != null:
		var name := String(item_feedback[0])
		var text := String(item_feedback[1])
		var end := float(item_feedback[2])
		if clock < end:
			var y := 102 + int(round(maxf(0.0, end - clock - .79) * 25.0 * bob_scale))
			var label: String = (
				text if text != "" else String(HUD.ITEM_LABELS[HUD.ITEMS.find(name)])
			)
			HUD.panel(c, 8, y, 29 + PixelType.text_width(label, "mini"), 20, Canvas.rgb(38, 27, 21))
			var image := art.art("item_" + name)
			var iw: int = image["w"]
			var ih: int = image["h"]
			var data: PackedByteArray = image["data"]
			for ty in 16:
				var sy := clampi(ty * ih / 16, 0, ih - 1)
				for tx in 16:
					var sx := clampi(tx * iw / 16, 0, iw - 1)
					var sp := (sy * iw + sx) * 4
					if data[sp + 3] == 0:
						continue
					c.set_pixel(11 + tx, y + 2 + ty, data[sp], data[sp + 1], data[sp + 2])
			HUD.text(c, label, 30, y + 7, "mini", Canvas.rgb(249, 205, 144), false, false)
	if damage_feedback != null:
		var heading = damage_feedback[0]
		var cause := String(damage_feedback[1])
		var end2 := float(damage_feedback[2])
		if clock >= end2:
			return
		var side := ""
		if heading != null and not NO_MARK_SURFACE.has(cause):
			var turn2 := fposmod(float(heading) - player.view_angle() + PI, TAU) - PI
			side = (
				" REAR"
				if absf(turn2) > 2.41
				else " LEFT" if turn2 < -.40 else " RIGHT" if turn2 > .40 else " FRONT"
			)
		HUD.banner(c, cause + side, 87, 288, Canvas.rgb(244, 160, 108))


# ---------------------------------------------------------------- main draw


func draw(c: Canvas, crosshair := 1, grade := true) -> void:
	var p := player
	look_live = false
	tone_live = false
	hurt_alpha = 0
	if showing_tally:
		hud.intermission(c, self)
		return
	var practice := gallery != null and gallery.active
	var weapon = gallery.pistol if practice else armory
	var flash: float = (weapon.flash * 4.0 + blast_flash * .85) * flash_scale
	renderer.time = clock
	var t0 := Time.get_ticks_usec()
	var marks: Array = ground_marks()
	var marks_list: Array = wall_marks if bullet_marks else []
	if not gore_fx.walls.is_empty():
		marks_list = marks_list + gore_fx.walls
	var listed: Array = sprites()
	var t1 := Time.get_ticks_usec()
	var view_frame: PackedByteArray = renderer.render(
		p.as_render_player(), listed, reflection(), flash, marks_list, marks
	)
	var t2 := Time.get_ticks_usec()
	# render() hands back a private copy so the HUD, weapon and grade passes can
	# composite into it while the renderer keeps its own band buffers untouched.
	c.pixels = view_frame
	if p.health > 0 and not in_hub and (weapon_view != 2 or armory.fuse > 0.0):
		weapon.draw(
			c.pixels,
			art,
			p,
			world.light[world.cell(p.x, p.y)],
			bob_scale,
			flash_scale,
			12 if weapon_view == 1 else 0
		)
	var t3 := Time.get_ticks_usec()
	if hurt_flash > 0.0 and flash_scale > 0.0:
		_apply_hurt_flash(c)
	if p.drunk >= 38.0 and flash_scale > 0.0:
		_drunk_warp(c)
	# The look pass and the brightness grade touch the same view rectangle; the
	# lookup table is folded into the look pass when both are active.
	var graded := false
	look_live = retro_look and flash_scale > 0.0
	tone_live = grade and tone != null
	if gpu_look:
		# The display shader grades the view; only its numbers are worked out here.
		if look_live:
			_look_params()
	else:
		if look_live:
			var table = tone if grade else null
			_look_pass(c, table)
			graded = tone_live
		if tone_live and not graded:
			_grade_view(c)
	var t4 := Time.get_ticks_usec()
	stage_ms = [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, 0.0]
	if p.health > 0:
		if crosshair == 2:
			c.circle(160, VIEW / 2, 4, Canvas.rgb(188, 168, 132), false)
		elif crosshair != 0:
			c.set_pixel(160, VIEW / 2, 188, 168, 132)
		var after_notice := 5
		if not map:
			if practice:
				after_notice = HUD.banner(c, gallery.hud(), 5) + 3
			elif message_until > clock and (hints or notice != level.introduction):
				after_notice = HUD.banner(c, notice, 5) + 3
			elif district_labels and district_until > clock:
				after_notice = (
					HUD.banner(c, level.districts[district], 5, 288, Canvas.rgb(245, 196, 122)) + 3
				)
			var boss = (
				finale if finale != null else (jerry if jerry != null and jerry.alive else boss)
			)
			if boss != null:
				var in_finale: bool = (
					sqrt((boss.x - p.x) * (boss.x - p.x) + (boss.y - p.y) * (boss.y - p.y)) < 14.0
					if finale != null
					else p.y < 10.0
				)
				if in_finale and boss.alive and boss.alerted and not in_hub:
					var y := after_notice
					var tell: String = String(
						Enemies_TELLS().get(
							boss.kind, "PLASMA CHARGE" if boss == self.boss else "WHISTLE"
						)
					)
					if boss.kind == "baron" and boss.attacks % 2 == 1:
						tell = "STEAM SWEEP"
					if boss.kind == "foreman" and boss.attacks % 2 == 1:
						tell = "GAP IN THE MIDDLE"
					if boss.kind == "rudy":
						tell = "LEFT HORN" if boss.attacks % 2 == 1 else "RIGHT HORN"
					var phase: String = (
						tell if boss.windup > 0.0 else "RECOVERING" if boss.recovery > .16 else ""
					)
					HUD.panel(
						c,
						193,
						y,
						122,
						27 if phase != "" else 20,
						Canvas.rgb(35, 24, 20),
						Canvas.rgb(126, 85, 57)
					)
					HUD.text(c, _boss_title(boss.kind), 253, y + 3, "body", HUD.INK, true, false)
					c.fill_rect(199, y + 12, 110, 4, Canvas.rgb(70, 42, 32))
					c.fill_rect(
						199,
						y + 12,
						int(round(110.0 * boss.hp / boss.max_hp)),
						4,
						Canvas.rgb(236, 143, 69) if boss.windup > 0.0 else Canvas.rgb(204, 77, 47)
					)
					if phase != "":
						HUD.text(
							c, phase, 253, y + 19, "mini", Canvas.rgb(249, 194, 124), true, false
						)
		if not map and armory.fuse == 0.0:
			var hint := gate_prompt()
			if hint == "" and hints and not in_hub:
				hint = use_prompt()
			if hint != "":
				HUD.banner(c, hint, 137, 288, Canvas.rgb(251, 207, 142))
			if voice_captions and caption_until > clock:
				HUD.banner(c, caption, 121 if hint != "" else 137, 288, Canvas.rgb(209, 221, 179))
			elif barks.visible(self) and hint == "":
				HUD.banner(c, '"' + barks.text + '"', 137, 288, Canvas.rgb(255, 214, 150))
		if not map:
			feedback(c)
	else:
		HUD.panel(c, 27, 54, 266, 52, Canvas.rgb(43, 26, 22))
		HUD.text(c, "YOU BOUGHT THE FARM", 160, 64, "heading", HUD.INK, true)
		HUD.text(
			c,
			(
				"ENTER CROSSROADS  /  ESC TITLE"
				if revisiting
				else "ENTER RETRY  /  F9 QUICKLOAD  /  ESC TITLE"
			),
			160,
			90,
			"body",
			HUD.INK,
			true
		)
	if map and p.health > 0:
		automap(c)
	hud.draw(c, self, weapon)
	stage_ms[4] = (Time.get_ticks_usec() - t4) / 1000.0


func _boss_title(kind: String) -> String:
	return String(
		(
			{
				"boss": "ALIEN SHERIFF",
				"jerry": "JERRY JONES",
				"rudy": "RUDY RACKET",
				"foreman": "SPLINTER FOREMAN",
				"baron": "COPPER BARON"
			}
			. get(kind, "BOSS")
		)
	)


# ------------------------------------------------------------- view effects

## rampage2.look_pass tables: wash tint, vignette and ordered dither.
var _grit_r := PackedFloat32Array()
var _grit_g := PackedFloat32Array()
var _grit_b := PackedFloat32Array()
var _dither := PackedFloat32Array()

const GRAIN_STRIDE := 936
const GRAIN_FRAMES := 6


func _build_grit() -> void:
	var count := WIDTH * VIEW
	_grit_r.resize(count)
	_grit_g.resize(count)
	_grit_b.resize(count)
	_dither.resize(count)
	var wash: Array = WASH.get(level.id, [255, 255, 255, 0])
	var amount := float(wash[3])
	var tr := float(wash[0]) / 255.0
	var tg := float(wash[1]) / 255.0
	var tb := float(wash[2]) / 255.0
	var w := float(maxi(WIDTH - 1, 1))
	var h := float(maxi(VIEW - 1, 1))
	for y in VIEW:
		var ny := (float(y) / h - .5) * 2.0
		for x in WIDTH:
			var nx := (float(x) / w - .5) * 2.0
			var radius := sqrt(nx * nx + ny * ny) / 1.4142
			var vignette := 1.0 - .13 * pow(radius, 2.1)
			var i := y * WIDTH + x
			_grit_r[i] = ((1.0 - amount) + tr * amount) * vignette
			_grit_g[i] = ((1.0 - amount) + tg * amount) * vignette
			_grit_b[i] = ((1.0 - amount) + tb * amount) * vignette
			_dither[i] = (float(BAYER[(x % 4) * 4 + (y % 4)]) / 16.0 - .5) * 6.0


func _apply_hurt_flash(c: Canvas) -> void:
	var alpha := clampi(int(round(hurt_flash * 310.0 * flash_scale)), 0, 255)
	hurt_alpha = alpha if gpu_look else 0
	if alpha == 0 or gpu_look:
		return
	var pix := c.pixels
	var inv := 255 - alpha
	var n := WIDTH * VIEW * 3
	var i := 0
	while i < n:
		pix[i] = (131 * alpha + pix[i] * inv) / 255
		pix[i + 1] = (27 * alpha + pix[i + 1] * inv) / 255
		pix[i + 2] = (17 * alpha + pix[i + 2] * inv) / 255
		i += 3


## rampage2.drunk_warp: per-row sine shear, ghost double image, amber tint.
func _drunk_warp(c: Canvas) -> void:
	var drunk := player.drunk
	if drunk < 38.0:
		return
	var strength := minf(1.0, (drunk - 38.0) / 62.0)
	var width := WIDTH
	var source := PackedByteArray()
	source.resize(width * VIEW * 3)
	var shift := PackedInt32Array()
	shift.resize(VIEW)
	for y in VIEW:
		shift[y] = int(round(sin(y * .16 + clock * 3.1) * (1.0 + 3.4 * strength)))
	var pix := c.pixels
	for y in VIEW:
		var row := y * width * 3
		var offset := shift[y]
		for x in width:
			var sx := posmod(x + offset, width)
			var sp := row + sx * 3
			var dp := row + x * 3
			source[dp] = pix[sp]
			source[dp + 1] = pix[sp + 1]
			source[dp + 2] = pix[sp + 2]
	var ghost_dx := int(2 + 4 * strength)
	if sin(clock * 1.7) <= 0.0:
		ghost_dx = -ghost_dx
	var mix := .30 * strength
	for y in VIEW:
		var row := y * width * 3
		for x in width:
			var gx := posmod(x - ghost_dx, width)
			var gp := row + gx * 3
			var dp := row + x * 3
			var r := float(source[dp]) * (1.0 - mix) + float(source[gp]) * mix
			var g := float(source[dp + 1]) * (1.0 - mix) + float(source[gp + 1]) * mix
			var b := float(source[dp + 2]) * (1.0 - mix) + float(source[gp + 2]) * mix
			pix[dp] = clampi(int(r * (1.0 + .06 * strength)), 0, 255)
			pix[dp + 1] = clampi(int(g), 0, 255)
			pix[dp + 2] = clampi(int(b * (1.0 - .10 * strength)), 0, 255)


## This frame's lamp buzz, grain frame and blast lift, for either look path.
func _look_params() -> void:
	var indoors: bool = world.roof[world.cell(player.x, player.y)] != 0.0
	var gain := 1.0
	# SCREEN FLASH below FULL also stills the lamp buzz, as in the reference.
	if indoors and flicker and flash_scale == 1.0:
		var buzz := .985 + .015 * sin(clock * 53.0)
		if int(clock * 7.3) % 29 == 0 and fmod(clock * 7.3, 1.0) < .35:
			buzz -= .07
		gain = buzz
	_look_gain = gain
	_look_frame = int(clock * 17.0) % GRAIN_FRAMES
	_look_blast = blast_flash * 60.0


func _look_pass(c: Canvas, grade_tone = null) -> void:
	_look_params()
	_look_tone = grade_tone
	# Row-banded across explicit threads. This pass is ~10 ms of per-pixel float
	# work at 50k pixels, so it is worth splitting. Each worker owns a private
	# output buffer for its own rows; only writes need a single owner, and a
	# shared buffer would make every worker detach on its first write (packed
	# arrays are copy-on-write). The bands are concatenated natively with
	# append_array, and the status rows below VIEW are carried over verbatim.
	var src := c.pixels
	var view_bytes := WIDTH * VIEW * 3
	var bands := _look_band_count()
	if bands <= 1:
		var dst := src.slice(0)
		_look_rows(dst, src, 0, VIEW)
		c.pixels = dst
		return
	_look_rows_per = int(ceil(float(VIEW) / bands))
	while _look_threads.size() < bands:
		_look_threads.append(Thread.new())
	for i in bands:
		var t: Thread = _look_threads[i]
		if t.is_started():
			t.wait_to_finish()
		t.start(_look_worker.bind(src, i))
	# Each worker builds and returns its own buffer, so no band ever writes into
	# memory another thread can see; the main thread collects the results.
	var out := PackedByteArray()
	for i in bands:
		var part: PackedByteArray = _look_threads[i].wait_to_finish()
		if part.size() > 0:
			out.append_array(part)
	if src.size() > view_bytes:
		out.append_array(src.slice(view_bytes))
	c.pixels = out


var _look_threads: Array[Thread] = []
var _look_rows_per := 0
var _look_gain := 1.0
var _look_frame := 0
var _look_blast := 0.0
var _look_tone = null


func _look_band_count() -> int:
	if VIEW < 48 or not OS.has_feature("threads"):
		return 1
	if look_bands > 0:
		return mini(look_bands, VIEW)
	# Four bands measured fastest: the renderer already fills the machine with
	# its own band threads, and more look workers just contend with them.
	return mini(4, VIEW)


func _look_worker(src: PackedByteArray, slot: int) -> PackedByteArray:
	var y0 := slot * _look_rows_per
	var y1 := mini(VIEW, y0 + _look_rows_per)
	if y0 >= y1:
		return PackedByteArray()
	# Private buffer: one owner, so the band write cannot race with a detach.
	var part := PackedByteArray()
	part.resize((y1 - y0) * WIDTH * 3)
	_look_rows(part, src, y0, y1)
	return part


## Apply the look + tone passes to rows [y0, y1) of `src`, writing them into
## `dst` starting at its row 0. Both buffers are row-aligned to `y0`.
func _look_rows(dst: PackedByteArray, src: PackedByteArray, y0: int, y1: int) -> void:
	var grain := art.grain
	var grit_r := _grit_r
	var grit_g := _grit_g
	var grit_b := _grit_b
	var dither := _dither
	var tone = _look_tone
	var gain := _look_gain
	var blast_add := _look_blast
	var frame_index := _look_frame
	# Yields: the reference runs look_pass over (0,0,WIDTH,VIEW) and then the
	# brightness grade over the same rectangle, so folding the two passes
	# together here produces identical pixels for half the memory traffic.
	var dst_row := 0
	var y := y0
	while y < y1:
		var i := y * WIDTH
		var o := dst_row
		var so := i * 3
		var gx := frame_index * VIEW + y
		var x := 0
		while x < WIDTH:
			var add := float(int(grain[gx]) - 2) + blast_add + dither[i]
			var r := clampi(int(float(src[so]) * (grit_r[i] * gain) + add), 0, 255)
			var g := clampi(int(float(src[so + 1]) * (grit_g[i] * gain) + add), 0, 255)
			var b := clampi(int(float(src[so + 2]) * (grit_b[i] * gain) + add), 0, 255)
			if tone != null:
				dst[o] = tone[r]
				dst[o + 1] = tone[g]
				dst[o + 2] = tone[b]
			else:
				dst[o] = r
				dst[o + 1] = g
				dst[o + 2] = b
			gx += GRAIN_STRIDE
			i += 1
			o += 3
			so += 3
			x += 1
		dst_row += WIDTH * 3
		y += 1


func _grade_view(c: Canvas) -> void:
	var pix := c.pixels
	var n := WIDTH * VIEW * 3
	for i in n:
		pix[i] = tone[pix[i]]


# ----------------------------------------------------------------- automap

var _map_base := PackedByteArray()
var _map_geom := {}


func automap(c: Canvas) -> void:
	if _map_base.is_empty() or _map_signature_changed():
		_build_map_base()
	_blit_region(c, 37, 5)
	var geom := _map_geom
	var width: int = geom["width"]
	var height: int = geom["height"]
	var start_y: int = geom["start_y"]
	for key: Vector2i in visited:
		if key.x >= 0 and key.x < width and key.y >= start_y and key.y < start_y + height:
			var rect := _map_tile(float(key.x), float(key.y))
			c.fill_rect(
				rect.position.x, rect.position.y, rect.size.x, rect.size.y, Canvas.rgb(152, 120, 75)
			)
	if not in_hub:
		for door: LevelData.Door in world.doors:
			if not door.secret or door.discovered:
				var color := (
					Canvas.rgb(110, 120, 88)
					if door.opened
					else Canvas.rgb(200, 119, 56) if door.key != "" else Canvas.rgb(146, 112, 77)
				)
				var rect2 := _map_tile(float(door.x), float(door.y))
				c.fill_rect(rect2.position.x, rect2.position.y, rect2.size.x, rect2.size.y, color)
	var labels: Array = []
	if in_hub:
		for gate: LevelData.Gate in world.hub_gates:
			labels.append(
				[
					String(Campaign.GATE_LABELS.get(gate.destination, "")),
					gate.x,
					gate.y,
					not world.locked_gates.has(gate)
				]
			)
		for clue in world.hub_clues:
			if hub_findings.has(String(clue[0])):
				var at := _map_tile(float(clue[1]), float(clue[2]))
				var cx := at.position.x
				var cy := at.position.y
				c.polygon(
					[
						Vector2(cx, cy - 3),
						Vector2(cx + 3, cy),
						Vector2(cx, cy + 3),
						Vector2(cx - 3, cy)
					],
					Canvas.rgb(200, 173, 111)
				)
	else:
		for row in level.map_labels:
			labels.append([String(row[0]), float(row[1]), float(row[2]), true])
	for label_row in labels:
		var label := String(label_row[0])
		var at := _map_tile(float(label_row[1]), float(label_row[2]))
		var left_edge := (
			at.position.x - PixelType.text_width(label) / 2 if in_hub else at.position.x
		)
		c.fill_rect(
			left_edge - 2,
			at.position.y - 1,
			PixelType.text_width(label) + 4,
			9,
			Canvas.rgb(35, 27, 22)
		)
		HUD.text(
			c,
			label,
			left_edge,
			at.position.y,
			"body",
			Canvas.rgb(244, 223, 185) if bool(label_row[3]) else Canvas.rgb(185, 123, 85),
			false,
			false
		)
	for station: LevelData.Station in world.stations:
		if not station.reveals_secret and (not station.hidden or stations_done.has(station.id)):
			var at2 := _map_tile(station.x, station.y)
			c.fill_rect(
				at2.position.x - 2,
				at2.position.y - 2,
				4,
				4,
				(
					Canvas.rgb(151, 187, 110)
					if stations_done.has(station.id)
					else Canvas.rgb(230, 163, 83)
				)
			)
	if world.extraction != null:
		var at3 := _map_tile(world.extraction.x, world.extraction.y)
		c.circle(
			at3.position.x,
			at3.position.y,
			3,
			Canvas.rgb(151, 187, 110) if exit_ready() else Canvas.rgb(170, 103, 82),
			false
		)
	var geom2 := _map_geom
	var px := 37 + int(round(float(geom2["left"]) + player.x * float(geom2["scale_x"])))
	var py := 5 + int(round(5.0 + (player.y - float(geom2["start_y"])) * float(geom2["scale_y"])))
	c.circle(px, py, 2, Canvas.rgb(235, 154, 78))
	c.line(
		px,
		py,
		px + int(round(cos(player.angle) * 6.0)),
		py + int(round(sin(player.angle) * 6.0)),
		Canvas.rgb(235, 154, 78)
	)
	c.line(48, 114, 271, 114, Canvas.rgb(120, 87, 59))
	HUD.text(
		c, objective() if hints else level.title, 160, 121, "body", Canvas.rgb(248, 199, 127), true
	)
	var footer := (
		"ROAD NOTES %d/%d   /   TAB TO CLOSE" % [hub_findings.size(), world.hub_clues.size()]
		if in_hub
		else "SECRETS %d/%d   /   TAB TO CLOSE" % [secrets, total_secrets]
	)
	HUD.text(c, footer, 160, 137, "body", HUD.INK, true)


func _map_signature_changed() -> bool:
	var signature: Array = []
	for door: LevelData.Door in world.doors:
		if door.secret and not door.discovered:
			signature.append(Vector2i(door.x, door.y))
	return signature != map_signature


func _build_map_base() -> void:
	var width := int(world.width)
	var height := int(world.height)
	var start_y := 33 if in_hub else 0
	if level.rescue:
		height = height - start_y if in_hub else 34
	if in_hub:
		width = int(HUB_WIDTH)
	var scale_x: float = minf(4.0, 208.0 / float(width))
	var scale_y: float = minf(3.0, 102.0 / float(height))
	var left: float = (246.0 - width * scale_x) / 2.0
	_map_geom = {
		"width": width,
		"height": height,
		"start_y": start_y,
		"scale_x": scale_x,
		"scale_y": scale_y,
		"left": left
	}
	var signature: Array = []
	for door: LevelData.Door in world.doors:
		if door.secret and not door.discovered:
			signature.append(Vector2i(door.x, door.y))
	map_signature = signature
	var concealed := {}
	for point: Vector2i in signature:
		concealed[point] = true
		for room in level.hidden_rooms:
			if room[0] == point:
				var box: Vector4i = room[1]
				for yy in range(box.y, box.w + 1):
					for xx in range(box.x, box.z + 1):
						concealed[Vector2i(xx, yy)] = true
	var base := Canvas.new()
	base.fill_rect(37, 5, 246, 149, Canvas.rgb(30, 24, 19))
	base.rect_outline(37, 5, 246, 149, Canvas.rgb(149, 117, 81))
	for yy in range(start_y, start_y + height):
		for xx in width:
			var cell := yy * int(world.width) + xx
			if int(world.solid[cell]) < 0 and not concealed.has(Vector2i(xx, yy)):
				var color := (
					Canvas.rgb(74, 86, 76) if world.roof[cell] == 0.0 else Canvas.rgb(104, 85, 66)
				)
				if world.surface_sound(int(world.floor_tile[cell])) == "water":
					color = Canvas.rgb(67, 104, 106)
				var rect := _map_tile(float(xx), float(yy))
				base.fill_rect(rect.position.x, rect.position.y, rect.size.x, rect.size.y, color)
	var data := PackedByteArray()
	data.resize(246 * 149 * 3)
	for row in 149:
		var src := ((5 + row) * Canvas.WIDTH + 37) * 3
		for k in 246 * 3:
			data[row * 246 * 3 + k] = base.pixels[src + k]
	_map_base = data


func _map_tile(x: float, y: float) -> Rect2i:
	var left: float = _map_geom["left"]
	var scale_x: float = _map_geom["scale_x"]
	var scale_y: float = _map_geom["scale_y"]
	var start_y: int = _map_geom["start_y"]
	var x0 := int(round(left + x * scale_x))
	var y0 := int(round(5.0 + (y - start_y) * scale_y))
	var x1 := int(round(left + (x + 1.0) * scale_x))
	var y1 := int(round(5.0 + (y - start_y + 1.0) * scale_y))
	return Rect2i(37 + x0, 5 + y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


## Fast region copy of the cached 246x149 map panel into the 320x200 canvas.
func _blit_region(c: Canvas, dx: int, dy: int) -> void:
	var pix := c.pixels
	var row_bytes := 246 * 3
	for row in 149:
		var src := row * row_bytes
		var dst := ((dy + row) * Canvas.WIDTH + dx) * 3
		for k in row_bytes:
			pix[dst + k] = _map_base[src + k]


# ------------------------------------------------------------------ controls

## game.Controls: one sim step's input.
## Milliseconds the last draw spent listing sprites, rendering the scene, drawing
## the weapon, grading the view and drawing the HUD; read by tools/bench.gd.
var stage_ms: Array = [0.0, 0.0, 0.0, 0.0, 0.0]


class Controls:
	var forward := 0.0
	var strafe := 0.0
	var turn := 0.0
	var look := 0.0
	var running := false
	var fire := false
	var alt_fire := false
	var jump := false
	var crouch := false
