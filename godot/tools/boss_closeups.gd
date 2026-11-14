## Close-up pictures of every boss in its own level, through the software view:
## whole, phase two (under half health), phase three (under a fifth), the
## wind-up's first beat, the aim, the attack and the fall. One sheet a run.
##
##   godot --headless --path godot --script res://tools/boss_closeups.gd \
##       -- out=<png> [kinds=boss,maw]
##
## Looks only: nothing is ticked, the boss is posed by hand (hp, windup,
## recovery, died_at) and every other enemy is put to sleep for the picture.
extends SceneTree

const BOSSES := [
	["boss", "hickston"],
	["jerry", "hickston"],
	["rudy", "fair"],
	["foreman", "sawmill"],
	["baron", "quarry"],
	["swamp_king", "bayou"],
	["derby_champ", "speedway"],
	["maw", "mothership"],
]
const STATES := ["whole", "phase2", "phase3", "wind", "aim", "attack", "fall"]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://boss_closeups.png"
	var kinds: Array = []
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("kinds="):
			kinds = Array(text.substr(6).split(","))
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var rows: Array = []
	for pair: Array in BOSSES:
		if not kinds.is_empty() and not kinds.has(pair[0]):
			continue
		rows.append(_row(String(pair[0]), String(pair[1]), assets, hud, sound))
	var sheet := Image.create_empty(
		320 * STATES.size(), 200 * rows.size(), false, Image.FORMAT_RGB8
	)
	for r in rows.size():
		for c in STATES.size():
			var shot: Image = rows[r][c]
			sheet.blit_rect(shot, Rect2i(0, 0, 320, 200), Vector2i(c * 320, r * 200))
	sheet.save_png(out)
	print("BOSS CLOSEUPS: %d bosses -> %s" % [rows.size(), out])
	Renderer.stop_crew()
	quit()


func _row(kind: String, level: String, assets: Assets, hud: HUD, sound: Sound) -> Array:
	var shots := []
	for state: String in STATES:
		var game := Game.new(assets, hud, sound, level)
		game.configure(SessionStore.defaults())
		var boss: Enemy = null
		for e: Enemy in game.enemies:
			if e.kind == kind and boss == null:
				boss = e
			else:
				e.dormant = true
		if boss == null:
			shots.append(Image.create_empty(320, 200, false, Image.FORMAT_RGB8))
			continue
		boss.dormant = false
		boss.alerted = true
		_stand_player(game, boss, 6.2 if kind == "maw" else 3.6)
		game.clock = 10.0
		match state:
			"phase2":
				boss.hp = boss.max_hp * .4
			"phase3":
				boss.hp = boss.max_hp * .15
			"wind":
				boss.windup = 1.0
			"aim":
				boss.windup = 1.0
				boss.sprite(null, false, game.clock)
				boss.windup = .3
			"attack":
				boss.recovery = boss.recovery_time()
			"fall":
				boss.hp = 0.0
				boss.alive = false
				boss.died_at = game.clock - Enemy.DEATH_TIME * .5
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


## The player a few paces off the boss's face (or the nearest clear side),
## looking at it, the boss turned to the player.
func _stand_player(game, boss: Enemy, reach: float) -> void:
	var p = game.player
	for k in 16:
		var a := boss.angle + k * TAU / 16.0 * (1 if k % 2 == 0 else -1)
		var x := boss.x + cos(a) * reach
		var y := boss.y + sin(a) * reach
		if game.world.blocked(x, y, .3) or not game.world.visible(x, y, boss.x, boss.y):
			continue
		p.x = x
		p.y = y
		break
	p.angle = atan2(boss.y - p.y, boss.x - p.x)
	boss.angle = atan2(p.y - boss.y, p.x - boss.x)
	p.eye = .95 + game.world.stand(p)
	p.pitch = 8.0 if boss.kind == "maw" else 0.0
	p.drunk = 0.0
