## Pictures of every boss's ending in a real window (the graphics-card view
## players see): each boss is met in its arena, felled by a load of the
## player's buckshot, and the whole sequence from the killing blow to the
## next screen is taken as it plays through the front end's own frame (the
## cinematic, the slow motion, the return to play or the rematch's result).
## One sheet per boss, <kind>.png in out=<dir>: frames read left to right,
## then down, each one stamped with its real seconds after the blow.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/boss_end_frames.gd -- out=<dir> [kinds=boss,maw]
##       [campaign] [coop] [skip] [every=8] [seconds=9] [big=40,100]
##
## By default each fight is a BOSS REMATCH (ends on the result board);
## campaign plays the boss in its chapter instead (ends back in play), coop
## with a second player along, skip presses a key a second into the ending.
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0
const CELL := Vector2i(320, 200)
const COLUMNS := 5

var main
var out := ""
var kinds: Array = []
var campaign := false
var coop := false
var skip := false
var every := 8
var seconds := 9.0
## Frames (by count after the blow) also saved whole: big=40,100,200.
var big: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	kinds = BossRematch.BOSSES.duplicate()
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("kinds="):
			kinds = Array(a.substr(6).split(",", false))
		elif a == "campaign":
			campaign = true
		elif a == "coop":
			coop = true
		elif a == "skip":
			skip = true
		elif a.begins_with("every="):
			every = maxi(1, int(a.substr(6)))
		elif a.begins_with("big="):
			for f in a.substr(4).split(",", false):
				big.append(int(f))
		elif a.begins_with("seconds="):
			seconds = float(a.substr(8))
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	BossRematch.unlock_all = true
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	for kind: String in kinds:
		await _ending(str(kind))
	print("boss ending frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


## The front end's play frame, as main.gd runs it (the cinematic or the
## replay holding the game, else play advancing), then the draw.
func _frame(controls: Game.Controls) -> void:
	if main.state != "play" or main.game == null:
		main.render()
		return
	if "boss_end" in main and main.boss_end.start(main):
		main.boss_end.frame(main, STEP)
		main.advance(STEP, Game.Controls.new())
	elif main.kill_cam.playing or main.kill_cam.start(main):
		main.kill_cam.frame(main, STEP)
	else:
		main.advance(STEP, controls)
	main.watch_rematch()
	main.sound.tick_score(STEP)
	main.render()


func _ending(kind: String) -> void:
	if campaign:
		main.start(str(BossRematch.LEVEL_OF[kind]))
		main.state = "play"
	else:
		main.start_rematch(kind, false)
	var g: Game = main.game
	if g == null:
		print(kind, ": no game (", main.menu_note, ")")
		return
	var boss := BossFight.of_kind(g, kind)
	if boss == null:
		print(kind, ": no boss")
		return
	for e: Enemy in g.enemies:
		if e != boss and e.hostile and campaign:
			e.dormant = true
	g.cheats.god = true
	_place(g, boss)
	if coop and g.players.size() < 2:
		var one: Player = g.player
		Players.join(g, one.x - cos(one.angle) * .8, one.y - sin(one.angle) * .8, one.angle)
	boss.dormant = false
	boss.alerted = true
	boss.wake(g, g.player.x, g.player.y)
	var still := Game.Controls.new()
	# Into the fight: past its entrance, a few seconds of it.
	for i in 300:
		_frame(still)
		if main.game != g:
			print(kind, ": the game went away in the fight (", main.state, ")")
			return
		_face(g, boss)
		await process_frame
	_place(g, boss)
	boss.hp = minf(boss.hp, 30.0)
	boss.windup = 0.0
	boss.cooldown = 2.0
	for i in 6:
		_frame(still)
		await process_frame
	var frames: Array[Image] = []
	var stamps: Array[String] = []
	g.hit_point = Vector3(boss.x, boss.y, g.world.stand(boss) + boss.height * .5)
	boss.hurt(boss.hp + 200.0, g, false, false, null, "shotgun")
	var n := 0
	var limit := int(seconds / STEP)
	var after_end := -1
	while n < limit:
		var press := Game.Controls.new()
		if skip and n == 60:
			if "boss_end" in main:
				main.boss_end.skip()
			else:
				main.kill_cam.stop(main)
		_frame(still if not skip or n != 60 else press)
		await RenderingServer.frame_post_draw
		if big.has(n):
			var whole := root.get_texture().get_image()
			whole.resize(640, 400, Image.INTERPOLATE_BILINEAR)
			whole.save_png(out.path_join("%s_%03d.png" % [kind, n]))
		if n % every == 0:
			frames.append(_cell())
			stamps.append("%.2f %s" % [n * STEP, main.state])
		if main.state != "play" and after_end < 0:
			after_end = n
		if after_end >= 0 and n - after_end > 30:
			break
		n += 1
	_sheet(kind, frames, stamps)
	print(kind, ": ", frames.size(), " frames, ended ", main.state, " at ", n * STEP)
	if main.state != "play":
		main.state = "title"


## The player a few cells off the boss, inside its room, in plain sight of it.
func _place(g: Game, boss: Enemy) -> void:
	var p := g.player
	var w: LevelData = g.world
	var toward := atan2(p.y - boss.y, p.x - boss.x)
	for r: float in [5.0, 6.0, 4.0, 7.0, 3.2]:
		for k in 24:
			var turn: int = int((k + 1) / 2.0) * (1 if k % 2 else -1)
			var a := toward + turn * TAU / 24.0
			var at := Vector2(boss.x + cos(a) * r, boss.y + sin(a) * r)
			if w.blocked(at.x, at.y, .4) or w.deep_at(at.x, at.y):
				continue
			if not w.visible(at.x, at.y, boss.x, boss.y):
				continue
			if (
				not BossFight.lock_of(g, boss.kind).is_empty()
				and not BossFight.in_room(g, boss.kind, at.x, at.y)
			):
				continue
			p.x = at.x
			p.y = at.y
			p.eye = w.stand(p) + .95
			_face(g, boss)
			return


func _face(g: Game, boss: Enemy) -> void:
	var p := g.player
	p.angle = atan2(boss.y - p.y, boss.x - p.x)
	p.pitch = 0.0


func _cell() -> Image:
	var img := root.get_texture().get_image()
	img.resize(CELL.x, CELL.y, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	return img


func _sheet(kind: String, frames: Array[Image], stamps: Array[String]) -> void:
	if frames.is_empty():
		return
	# At most 30 frames on a sheet, taken evenly.
	var picked: Array[int] = []
	var count := mini(30, frames.size())
	for i in count:
		picked.append(int(round(i * (frames.size() - 1) / maxf(1.0, count - 1.0))))
	var rows := int(ceil(count / float(COLUMNS)))
	var sheet := Image.create_empty(CELL.x * COLUMNS, CELL.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color(.1, .1, .1))
	for i in count:
		var at := Vector2i((i % COLUMNS) * CELL.x, (i / COLUMNS) * CELL.y)
		sheet.blit_rect(frames[picked[i]], Rect2i(Vector2i.ZERO, CELL), at)
		_stamp(sheet, at, stamps[picked[i]])
	sheet.save_png(out.path_join(kind + ".png"))


## A small white label in the cell's corner (a 3x5 digit font, no font files).
func _stamp(sheet: Image, at: Vector2i, text: String) -> void:
	const GLYPHS := {
		"0": "111101101101111",
		"1": "010110010010111",
		"2": "111001111100111",
		"3": "111001111001111",
		"4": "101101111001001",
		"5": "111100111001111",
		"6": "111100111101111",
		"7": "111001001001001",
		"8": "111101111101111",
		"9": "111101111001111",
		".": "000000000000010",
		" ": "000000000000000",
	}
	var x := at.x + 3
	for ch in text.substr(0, text.find(" ") if text.find(" ") > 0 else text.length()):
		var glyph: String = GLYPHS.get(ch, "000000000000000")
		for i in 15:
			if glyph[i] == "1":
				for dy in 2:
					for dx in 2:
						sheet.set_pixel(x + (i % 3) * 2 + dx, at.y + 3 + (i / 3) * 2 + dy, Color(1, 1, 0))
		x += 8
	if text.find("rematch_done") >= 0 or text.find("title") >= 0:
		sheet.fill_rect(Rect2i(at.x + CELL.x - 10, at.y + 3, 6, 6), Color(1, 0, 0))
