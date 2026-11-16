## Port of county_events.Gallery (the tin rooster shooting booth) at the fair.
## The game's `gallery` (game.gd makes one on the fair); typed as
## GameState.Gallery (game_state.gd preloads this file under that name).
extends RefCounted

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

## Where this level's booth stands relative to the first fair's
## (GALLERY_STAND): its targets and its bounds move with it.
var offset := Vector2.ZERO
var rewarded := false
var active := false
var clock := 0.0
var next_target := 2.35
var hits := 0
var spent := 0
var index := 0
var held := true
var pistol: Weapons.Armory = null
## The player who opened the booth (their slot): only they play it.
var slot := 0


func _init() -> void:
	pistol = Weapons.Armory.new(Weapons.REVOLVER)


func toggle(game: Game) -> void:
	if active:
		finish(game, "GALLERY CLOSED. E TO TRY AGAIN.")
		return
	if game.armory.fuse > 0.0:
		game.message("THROW THE LIT STICK FIRST.")
		return
	active = true
	slot = game.player.slot
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
	return "TIN ROOSTER  %d/4  ROUNDS %d  TIME %02d" % [hits, ROUNDS - spent, ceili(LIMIT - clock)]


func sprite(game: Game) -> View.Sprite:
	var t: Vector3 = TARGETS[index] + Vector3(offset.x, offset.y, 0.0)
	var out := View.Sprite.new(
		t.x,
		t.y,
		"county_gallery_target",
		RADIUS * 2.0,
		game.world.elevation(t.x, t.y) + t.z - RADIUS
	)
	out.plane = PI * .5
	return out


func finish(game: Game, message: String) -> void:
	active = false
	game.message(message, 2.6)


func advance_target() -> void:
	index = (index + 1) % TARGETS.size()
	next_target = clock + 2.35


func tick(dt: float, game: Game, fire: bool) -> void:
	var p := game.player
	clock += dt
	pistol.tick(dt, game)
	var at: Vector2 = Vector2(p.x, p.y) - offset
	if not (25.10 <= at.x and at.x <= 28.66 and 32.77 <= at.y and at.y <= 33.94):
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
	var t: Vector3 = TARGETS[index] + Vector3(offset.x, offset.y, 0.0)
	var z: float = t.z + game.world.elevation(t.x, t.y)
	var dx: float = t.x - p.x
	var dy: float = t.y - p.y
	var ax := cos(p.view_angle())
	var ay := sin(p.view_angle())
	var reach: float = dx * ax + dy * ay
	var hit_z: float = p.eye + reach * (p.pitch + p.sway) / View.base_focal
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
