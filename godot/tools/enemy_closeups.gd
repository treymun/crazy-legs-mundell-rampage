## Close-up pictures of the regular enemies in a level they walk, through the
## software view: standing, walking past, the wind-up's first beat, the aim,
## the attack, hurt (under half health) standing and limping past, the flinch
## and the body. One row a kind, one sheet a run (each shot cropped round the
## enemy).
##
##   godot --headless --path godot --script res://tools/enemy_closeups.gd \
##       -- out=<png> [kinds=billy,coot] [states=whole,wind,hurt]
##
## Looks only: nothing is ticked, the enemy is posed by hand (hp, windup,
## recovery, gait, died_at) and every other enemy is put to sleep. A kind no
## level places (a variant) stands in for one of its base kind; one enemies.cfg
## does not know yet borrows its base's numbers for the picture.
extends SceneTree

## Kind, a level it is in, and the kind it stands in for when no level has it.
const CAST := [
	["clone", "hickston", ""],
	["billy", "hickston", ""],
	["big_billy", "hickston", "billy"],
	["coot", "hickston", ""],
	["drunk_coot", "hickston", "coot"],
	["alien", "hickston", ""],
	["yard_deputy", "hickston", ""],
	["shield_deputy", "hickston", "yard_deputy"],
	["skeeter", "hickston", ""],
	["saucer", "hickston", ""],
	["barker", "fair", ""],
	["bottle_tosser", "fair", ""],
	["crawler", "fair", ""],
	["millhand", "sawmill", ""],
	["chain_hand", "sawmill", ""],
	["lantern", "sawmill", ""],
	["boilerback", "quarry", ""],
	["chalk_spitter", "quarry", ""],
	["valve_rat", "quarry", ""],
	["noodler", "bayou", ""],
	["chum_tosser", "bayou", ""],
	["gator", "bayou", ""],
	["pit_mechanic", "speedway", ""],
	["tire_roller", "speedway", ""],
	["nitro_huffer", "speedway", ""],
	["flagman", "speedway", ""],
	["drone", "mothership", ""],
	["tin_guard", "mothership", ""],
	["probe", "mothership", ""],
	["chicken", "hickston", ""],
	["pig", "hickston", ""],
	["bessie", "hickston", ""],
]
const STATES := ["whole", "walk", "wind", "aim", "attack", "hurt", "hurt_walk", "pain", "down"]
const CROP := Rect2i(80, 0, 160, 158)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://enemy_closeups.png"
	var kinds: Array = []
	var states: Array = STATES.duplicate()
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("kinds="):
			kinds = Array(text.substr(6).split(","))
		elif text.begins_with("states="):
			states = Array(text.substr(7).split(","))
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var rows: Array = []
	for row: Array in CAST:
		if not kinds.is_empty() and not kinds.has(row[0]):
			continue
		rows.append(_row(row, states, assets, hud, sound))
	var sheet := Image.create_empty(
		CROP.size.x * states.size(), CROP.size.y * rows.size(), false, Image.FORMAT_RGB8
	)
	for r in rows.size():
		for c in states.size():
			var shot: Image = rows[r][c]
			sheet.blit_rect(shot, CROP, Vector2i(c * CROP.size.x, r * CROP.size.y))
	sheet.save_png(out)
	print("ENEMY CLOSEUPS: %d kinds -> %s" % [rows.size(), out])
	Renderer.stop_crew()
	quit()


## A kind enemies.cfg does not list yet takes its base's numbers (picture only).
func _borrow(kind: String, base: String) -> void:
	if Enemy.KINDS.has(kind) or base == "":
		return
	Enemy.DEFS[kind] = Enemy.DEFS[base].duplicate()
	Enemy.DEFS[kind]["brain"] = base
	Enemy.KINDS[kind] = Enemy.KINDS[base].duplicate()
	for table: Array in [Enemy.TURN_CELS, Enemy.CREATURE_FALLS, Enemy.FIDGET_CELS]:
		if table.has(base):
			table.append(kind)
	for table: Dictionary in [Enemy.RECOVERY_TIMES, Enemy.WINDUP]:
		if table.has(base):
			table[kind] = table[base]


func _row(row: Array, states: Array, assets: Assets, hud: HUD, sound: Sound) -> Array:
	var kind := String(row[0])
	var base := String(row[2])
	_borrow(kind, base)
	var shots := []
	for state: String in states:
		var game := Game.new(assets, hud, sound, String(row[1]))
		game.configure(SessionStore.defaults())
		var foe: Enemy = null
		for e: Enemy in game.enemies:
			if foe == null and (e.kind == kind or (base != "" and e.kind == base)):
				foe = e
			else:
				e.dormant = true
		if foe == null:
			shots.append(Image.create_empty(320, 200, false, Image.FORMAT_RGB8))
			continue
		if foe.kind != kind:
			var stand_in := Enemy.new(kind, foe.x, foe.y, foe.angle)
			game.enemies[game.enemies.find(foe)] = stand_in
			foe = stand_in
		foe.dormant = false
		foe.alerted = true
		foe.variant = 1.0
		var reach := 2.8 if foe.brain in ["saucer", "gator", "bessie"] else 2.3
		if foe.brain in ["skeeter", "probe", "chicken"]:
			reach = 1.7
		_stand_player(game, foe, reach)
		game.clock = 10.0
		foe.pose = 1.0
		foe.last_stride = 0.0
		var turned := false
		match state:
			"walk":
				foe.last_stride = foe.pose
				foe.gait = PI * .5 + .1
				turned = true
			"wind":
				foe.windup = 1.0
			"aim":
				foe.windup = 1.0
				foe.sprite(null, false, game.clock)
				foe.windup = .3
			"attack":
				foe.recovery = foe.recovery_time()
			"hurt":
				foe.hp = foe.max_hp * .4
			"hurt_walk":
				foe.hp = foe.max_hp * .4
				foe.last_stride = foe.pose
				foe.gait = PI * .5 + .1
				turned = true
			"pain":
				foe.flinch = .2
			"down":
				foe.hp = 0.0
				foe.alive = false
				foe.died_at = game.clock - 30.0
		if turned:
			# Walking across the player's view, a little toward.
			foe.angle += PI * .62
		var p := game.player
		var canvas := Canvas.new()
		canvas.clear(0, 0, 0)
		game.armory.holstered = true
		game.armory.lower = 1.0
		game.message_until = 0.0
		game.district_until = 0.0
		p.sway = 0.0
		game.draw(canvas, 1, false)
		shots.append(Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels))
	return shots


## The player a few paces off the enemy's face (or the nearest clear side),
## looking at it, the enemy turned to the player.
func _stand_player(game, foe: Enemy, reach: float) -> void:
	var p = game.player
	for k in 16:
		var a := foe.angle + k * TAU / 16.0 * (1 if k % 2 == 0 else -1)
		var x := foe.x + cos(a) * reach
		var y := foe.y + sin(a) * reach
		if game.world.blocked(x, y, .3) or not game.world.visible(x, y, foe.x, foe.y):
			continue
		p.x = x
		p.y = y
		break
	p.angle = atan2(foe.y - p.y, foe.x - p.x)
	foe.angle = atan2(p.y - foe.y, p.x - foe.x)
	p.eye = .95 + game.world.stand(p)
	p.pitch = 0.0
	p.drunk = 0.0
