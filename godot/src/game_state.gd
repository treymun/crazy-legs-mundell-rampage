## The game's state: constants, the small classes it is built from, and every
## field. game.gd is a chain of layers, each extending the one before:
## GameState -> GameWorld -> GameCombat -> GameView -> Game. A layer only
## calls functions of its own or of the layers below it.
class_name GameState
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
		var hit_z: float = p.eye + reach * (p.pitch + p.sway) / Renderer.base_focal
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
## Steps from the player over open floor, for enemies that have lost sight of
## them (flow_field.gd), and the places enemies run from this tick (lit
## dynamite on the ground): Vector3(x, y, radius).
var flow: FlowField
var dangers: Array = []
## The same, measured from the objective over the whole level with its doors
## open: the objective pin points along it instead of through walls.
var route: FlowField
## What the route was last measured with: stations done, keys, doors open.
var route_sig := []
var enemies: Array = []
var partners := {}
var wave: Array = []
var boss = null
var jerry = null
var bessie = null
var finale = null

var props: Array = []
# The sprites that only change with the game's state (props, boards, drums,
# notes, rooms, scenery): game_view.gd lists them again only when the state
# they show changes. Two parts, so the list keeps its order around the
# gallery's moving target.
var fixed_sprites: Array = []
var fixed_sprites_late: Array = []
var fixed_windmills: Array = []
var fixed_sprites_key := []
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
## Game feel (HIT FEEDBACK and SCREEN SHAKE): a short freeze when a shot kills
## or hits hard, the crosshair's hit mark (red after a kill) and its tick, and
## a shake of the view (0 to 1, squared when drawn) from blasts, heavy guns and
## blows. None of it is saved; the freeze stops the world but not the aim.
var hitstop := 0.0
var hitstop_next := 0.0
var hit_mark_until := 0.0
var hit_mark_kill := false
var hit_tick_next := 0.0
var shake := 0.0
var step_number := 0
var next_belch := 0.0

var shots: Array = []
var specks: Array = []
## Gibs, blood pools and wall splats (gore.gd).
## Made in Game._init, which can hand it the whole game.
var gore_fx: Gore
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
## With `layered` (and gpu_look) the display shader also draws the sky, floors
## and ceilings and composes the view; the canvas is then only a layer over it.
## scene_live says whether this frame was drawn that way. drunk_k is the
## moonshine warp's strength for the shader (0 none).
var layered := false
var scene_live := false
var drunk_k := 0.0
## The red hurt wash (0-255) the display shader lays over the view this frame.
var hurt_alpha := 0
var look_live := false
var tone_live := false
var flash_scale := 1.0
var gore := true
var aim_assist := 0
var hit_feedback := true
var shake_scale := 1.0
## ADAPTIVE DIFFICULTY: incoming damage eases after each death and stiffens
## after a chapter finished in good health, between .78 and 1.15 of what the
## DIFFICULTY setting gives. Kept for the session (every Game shares it).
static var adapt := 1.0
var adaptive := true
## The touch overlay is in use (main.gd sets it): aim help reaches further.
var touch_aim := false
## TOUCH AUTO FIRE (game_combat.gd sights_on_enemy): its last answer. The
## guns it fires have auto_fire in weapons.cfg (never one that could blow up
## in the player's face).
var sights_next := 0.0
var sights_last := false
## Real play (main_flow.gd play()) teaches the controls as they come up
## (lessons.gd); tools that build a Game leave it off.
var lessons := false
## Lights level triggers have put up (triggers.gd): [x, y, z, radius, Color,
## strength, until].
var trigger_lights: Array = []
## What happens in play, announced for the features (src/features/) to listen
## to, instead of each feature being written into the code that does it.
signal enemy_killed(enemy: Enemy)
signal player_hurt(amount: float, cause: String)
signal pickup_taken(name: String)
signal station_done(station_id: String)
signal shot_fired(gun: int)
signal hit_landed(amount: float, killed: bool)
signal level_won
signal ticked(dt: float)
## The features, by id (features.gd).
var features := {}
## Level triggers that have fired (saved), and which repeating ones the player
## is inside of now.
var triggers_fired := {}
var triggers_inside := {}
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

var showing_tally: bool:
	get:
		return won and not revisiting

# -------------------------------------------------------------- configure

var _render_open := false

## rampage2.look_pass tables: wash tint, vignette and ordered dither.
var _grit_r := PackedFloat32Array()
var _grit_g := PackedFloat32Array()
var _grit_b := PackedFloat32Array()
var _dither := PackedFloat32Array()

const GRAIN_STRIDE := 936
const GRAIN_FRAMES := 6

var _look_threads: Array[Thread] = []
var _look_rows_per := 0
var _look_gain := 1.0
var _look_frame := 0
var _look_blast := 0.0
var _look_tone = null

var _map_base := PackedByteArray()
## The automap panel as a texture, for a Godot 2D canvas, and the base it shows.
var _map_texture: ImageTexture
var _map_texture_of := PackedByteArray()
var _map_geom := {}

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
