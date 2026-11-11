## The developer console: ` (the key under Esc) in play, only when running
## from the project folder. Type a command and press Enter; Up brings back the
## last one, Esc closes it. The player stands still while it is open.
##
##   god                    toggle taking no damage
##   give <gun|all>         a gun by its name in weapons.cfg, or every gun
##   ammo / heal            fill every gun / full health
##   spawn <kind> [n]       enemies from enemies.cfg in front, awake (not saved)
##   killall                every hostile within 14 cells goes down
##   tp <x> <y> / where     move to a map cell / say where you are
##   time <scale>           the game runs at that speed (.1 to 4)
##   trigger <id>           run a level trigger's actions now (triggers.gd)
##   reload / level <id>    reload this level / go to another
##   stats                  how the chapter went (features/chapter_stats.gd)
##   show map|fps|off       overlays: a map of walls, enemies (and the way
##                          hunting ones will take), triggers and lights; a
##                          frame-time graph
##
## run() takes the same text from scripts (tools/check_fixes.gd uses it).
class_name DevConsole
extends RefCounted

const HELP := (
	"GOD  GIVE <GUN|ALL>  AMMO  HEAL  SPAWN <KIND> [N]  KILLALL  TP <X> <Y>  WHERE  "
	+ "TIME <SCALE>  TRIGGER <ID>  RELOAD  LEVEL <ID>  STATS  SHOW MAP|FPS|OFF"
)
const MAP_CELL := 4
const MAP_REACH := 15

var main
var open := false
var line := ""
var last := ""
var log := PackedStringArray()
var show_map := false
var show_fps := false
var frames := PackedFloat32Array()


func _init(owner) -> void:
	main = owner


static func available() -> bool:
	return not OS.has_feature("template")


func toggle() -> void:
	open = not open
	line = ""


## A typed character; true when the console took it.
func text(unicode: int) -> bool:
	if not open or unicode < 32 or unicode >= 127 or unicode == 96:
		return false
	line += String.chr(unicode)
	return true


## A key while open; true when the console took it (all of them, while open).
func key(code: int) -> bool:
	if not open:
		return false
	match code:
		KEY_ENTER, KEY_KP_ENTER:
			if line.strip_edges() != "":
				last = line
				run(line)
			line = ""
		KEY_BACKSPACE:
			line = line.substr(0, maxi(0, line.length() - 1))
		KEY_UP:
			line = last
		KEY_ESCAPE:
			open = false
	return true


func _say(text: String) -> String:
	log.append(text.to_upper())
	if log.size() > 8:
		log = log.slice(log.size() - 8)
	return text


## Do one command; returns what it says.
func run(command: String) -> String:
	var words := command.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		return ""
	_say("> " + command)
	var game: Game = main.game
	var verb := words[0]
	if verb == "help":
		return _say(HELP)
	if verb == "time":
		main.time_scale = clampf(float(words[1]) if words.size() > 1 else 1.0, .1, 4.0)
		return _say("time x%.2f" % main.time_scale)
	if verb == "level":
		if words.size() < 2 or not FileAccess.file_exists(LevelEdit.path_of(words[1])):
			return _say("no such level")
		main.start(words[1])
		return _say("level " + words[1])
	if verb == "show":
		# Each overlay turns on and off by itself; "off" clears both.
		var what := words[1] if words.size() > 1 else "off"
		if what == "map":
			show_map = not show_map
		elif what == "fps":
			show_fps = not show_fps
		else:
			show_map = false
			show_fps = false
		return _say("map %s, fps %s" % ["on" if show_map else "off", "on" if show_fps else "off"])
	if game == null:
		return _say("start a level first")
	var p := game.player
	match verb:
		"god":
			game.cheats.god = not game.cheats.god
			return _say("god " + ("on" if game.cheats.god else "off"))
		"heal":
			p.health = 100
			return _say("health 100")
		"ammo":
			for i in Weapons.COUNT:
				game.armory.reserve[i] = Weapons.MAX_RESERVE[i]
				game.armory.loaded[i] = Weapons.CAPACITY[i]
			return _say("every gun full")
		"give":
			var name := words[1] if words.size() > 1 else "all"
			for i in Weapons.COUNT:
				if name == "all" or String(Weapons.NAMES[i]) == name:
					game.armory.pickup(i, game)
					game.armory.reserve[i] = Weapons.MAX_RESERVE[i]
					if name != "all":
						return _say("given " + name)
			return _say("given every gun" if name == "all" else "no gun called " + name)
		"spawn":
			if words.size() < 2 or not Enemy.KINDS.has(words[1]):
				return _say("no enemy kind " + (words[1] if words.size() > 1 else ""))
			var count := clampi(int(words[2]) if words.size() > 2 else 1, 1, 12)
			var made := 0
			for k in count:
				var at := 2.2 + k * .7
				var side := (k % 3 - 1) * .7
				var x := p.x + cos(p.angle) * at - sin(p.angle) * side
				var y := p.y + sin(p.angle) * at + cos(p.angle) * side
				if game.world.blocked(x, y, .25):
					continue
				var foe := Enemy.new(words[1], x, y, p.angle + PI)
				foe.flank = .42 if k % 2 else -.42
				game.enemies.append(foe)
				game.enemy_ids.append("dev-%s-%d" % [words[1], game.enemies.size()])
				foe.wake(game, p.x, p.y)
				made += 1
			return _say("spawned %d %s" % [made, words[1]])
		"killall":
			var down := 0
			for e: Enemy in game.enemies:
				if e.alive and e.hostile and Vector2(e.x - p.x, e.y - p.y).length() < 14.0:
					e.hurt(9999.0, game)
					down += 1
			return _say("%d down" % down)
		"tp":
			if words.size() < 3:
				return _say("tp <x> <y>")
			var x := float(words[1]) + (.5 if not words[1].contains(".") else 0.0)
			var y := float(words[2]) + (.5 if not words[2].contains(".") else 0.0)
			if x < 0 or y < 0 or x >= game.world.width or y >= game.world.height:
				return _say("outside the map")
			p.x = x
			p.y = y
			p.eye = .95 + game.world.elevation(x, y)
			return _say("at %.1f, %.1f" % [x, y])
		"where":
			return _say("%s at %.2f, %.2f facing %.2f" % [game.level.id, p.x, p.y, p.angle])
		"trigger":
			for trigger: Dictionary in game.level.triggers:
				if words.size() > 1 and String(trigger["id"]) == words[1]:
					game.triggers_fired[String(trigger["id"])] = true
					for action: Dictionary in trigger.get("do", []):
						Triggers.run(game, action)
					return _say("ran " + words[1])
			return _say("no trigger " + (words[1] if words.size() > 1 else ""))
		"stats":
			return _say(game.features["stats"].report())
		"reload":
			main.reload_level_in_place()
			return _say("level reloaded")
	return _say("unknown: " + verb + "  (help lists them)")


func tick(delta: float) -> void:
	frames.append(delta * 1000.0)
	if frames.size() > 120:
		frames = frames.slice(frames.size() - 120)


func draw(c: Canvas) -> void:
	var game: Game = main.game
	if show_map and game != null:
		_draw_map(c, game)
	if show_fps:
		_draw_fps(c)
	if not open:
		return
	c.fill_rect(0, 110, Canvas.WIDTH, 46, Color(.05, .04, .03))
	for i in log.size():
		HUD.text(c, log[i], 3, 112 + i * 5, "mini", HUD.INK, false, false)
	c.fill_rect(0, 150, Canvas.WIDTH, 6, Color(.12, .09, .06))
	var caret := "_" if int(Time.get_ticks_msec() / 400) % 2 == 0 else " "
	HUD.text(c, "] " + line.to_upper() + caret, 3, 151, "mini", HUD.AMBER, false, false)


## Walls, the player, enemies by state (red after the player, orange hunting
## out of sight, grey idle, dark held back) with the way hunting ones will
## walk, trigger areas and this frame's lights.
func _draw_map(c: Canvas, game: Game) -> void:
	var p := game.player
	var size := (MAP_REACH * 2 + 1) * MAP_CELL
	var left := Canvas.WIDTH - size - 3
	var top := 3
	c.fill_rect(left - 1, top - 1, size + 2, size + 2, Color(0, 0, 0))
	var px := int(p.x)
	var py := int(p.y)
	var w := game.world.width
	for gy in range(-MAP_REACH, MAP_REACH + 1):
		for gx in range(-MAP_REACH, MAP_REACH + 1):
			var cx := px + gx
			var cy := py + gy
			if cx < 0 or cy < 0 or cx >= w or cy >= game.world.height:
				continue
			if game.world.solid[cy * w + cx] >= 0:
				c.fill_rect(
					left + (gx + MAP_REACH) * MAP_CELL,
					top + (gy + MAP_REACH) * MAP_CELL,
					MAP_CELL,
					MAP_CELL,
					Color(.42, .38, .32)
				)
	var to_map := func(x: float, y: float) -> Vector2i:
		return Vector2i(
			left + int((x - px + MAP_REACH) * MAP_CELL), top + int((y - py + MAP_REACH) * MAP_CELL)
		)
	var inside := func(at: Vector2i) -> bool:
		return at.x >= left and at.y >= top and at.x < left + size and at.y < top + size
	for trigger: Dictionary in game.level.triggers:
		var box = trigger.get("when", {}).get("area")
		if box is Array:
			var a: Vector2i = to_map.call(float(box[0]), float(box[1]))
			var b: Vector2i = to_map.call(float(box[2]), float(box[3]))
			for x in range(maxi(a.x, left), mini(b.x, left + size)):
				for y in [a.y, b.y]:
					if inside.call(Vector2i(x, y)):
						c.set_pixel(x, y, 240, 160, 40)
			for y in range(maxi(a.y, top), mini(b.y, top + size)):
				for x in [a.x, b.x]:
					if inside.call(Vector2i(x, y)):
						c.set_pixel(x, y, 240, 160, 40)
	for light: Array in game.effect_lights():
		var at: Vector2i = to_map.call(float(light[0]), float(light[1]))
		if inside.call(at):
			c.fill_rect(at.x - 1, at.y - 1, 3, 3, Color(1, .9, .4))
	for e: Enemy in game.enemies:
		if e.hp <= 0.0 or not e.hostile:
			continue
		var at: Vector2i = to_map.call(e.x, e.y)
		if not inside.call(at):
			continue
		var hunting: bool = e.alerted and not e.player_seen and game.clock < e.hunt_until
		var colour := (
			Color(.2, .2, .2)
			if e.dormant
			else (
				Color(.95, .2, .1)
				if e.alerted and e.player_seen
				else Color(1, .55, .1) if hunting else Color(.7, .7, .7)
			)
		)
		if hunting:
			var path: Array = []
			game.flow.waypoint(e.x, e.y, 8, path)
			for cell: Vector2i in path:
				var dot: Vector2i = to_map.call(cell.x + .5, cell.y + .5)
				if inside.call(dot):
					c.set_pixel(dot.x, dot.y, 255, 150, 40)
		c.fill_rect(at.x - 1, at.y - 1, 3, 3, colour)
	var me: Vector2i = to_map.call(p.x, p.y)
	c.fill_rect(me.x - 1, me.y - 1, 3, 3, Color(1, 1, 1))
	for k in range(2, 7):
		var dot: Vector2i = to_map.call(p.x + cos(p.angle) * k * .3, p.y + sin(p.angle) * k * .3)
		c.set_pixel(dot.x, dot.y, 255, 255, 255)


## The last 120 frames' times, with a line at a 60 fps frame.
func _draw_fps(c: Canvas) -> void:
	var left := 4
	var top := 112
	c.fill_rect(left, top, 122, 34, Color(0, 0, 0))
	var worst := 0.0
	for i in frames.size():
		var ms := frames[i]
		worst = maxf(worst, ms)
		var tall := clampi(int(ms), 0, 32)
		var colour := Color(.3, .9, .3) if ms <= 16.8 else Color(.95, .3, .2)
		c.fill_rect(left + 1 + i, top + 33 - tall, 1, tall, colour)
	c.fill_rect(left, top + 33 - 17, 122, 1, Color(.9, .8, .3))
	var mean := 0.0
	for ms in frames:
		mean += ms
	mean /= maxf(1.0, frames.size())
	HUD.text(
		c, "%.1f MS  WORST %.1f" % [mean, worst], left + 2, top + 1, "mini", HUD.INK, false, false
	)
