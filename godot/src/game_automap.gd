## The automap, moved out of game_view.gd: the window over the view showing the
## level drawn at the zoom in use (game.map_zoom), what is walked, the doors,
## stations, exit, labels, the objective pin and the player. Looks only. The
## game's `map_view` (GameState) holds one; GameView.automap() draws it, and
## county_storm.gd draws the storm onto it (point(), scale_now).
class_name GameAutomap
extends RefCounted

## The map over the view: the window it shows the level in, with two lines of
## text under it (the status bar stays below).
const MAP_X := 6
const MAP_Y := 6
const MAP_W := 308
const MAP_H := 126
## Pixels a cell at each zoom; 0 fits the whole level in the window.
const MAP_ZOOMS := [0.0, 2.0, 3.0, 4.0]
const MAP_BACK := Color8(22, 17, 13)
const MAP_WALL := Color8(214, 178, 118)
## Ground not walked yet, then walked: under the sky, under a roof, water.
const MAP_GROUND := [Color8(54, 58, 47), Color8(70, 58, 45), Color8(44, 68, 72)]
## A wall's own mass, against the void beyond the level.
const MAP_MASS := Color8(40, 31, 23)
const MAP_WALKED := [Color8(104, 92, 64), Color8(132, 104, 72), Color8(66, 104, 110)]

## The whole map drawn at the zoom in use, the scale it was drawn at, how much
## of the game's `visited` is painted on it, the cells a secret still hides,
## and this frame's window onto it; the texture the window shows on a 2D
## canvas; what the image showed that can change (_signature()).
var image: Image = null
var built_scale := -1.0
var painted := 0
var hidden := {}
var window_origin := Vector2.ZERO
var scale_now := 1.0
var region_now := Rect2i()
var texture: ImageTexture
var last_signature: Variant = null


func draw(g: Game, c: Canvas) -> void:
	var region := _region(g)
	var scale := _scale_for(g, region)
	if image == null or built_scale != scale or _signature_changed(g):
		_build_image(g, region, scale)
	_paint_walked(g, region, scale)
	# The window follows the player (clamped to the level), or shows it all.
	var full := Vector2(region.size) * scale
	var origin := Vector2.ZERO
	for k in 2:
		var span: float = MAP_W if k == 0 else MAP_H
		var at: float = (g.player.x if k == 0 else g.player.y) - float(region.position[k])
		if full[k] <= span:
			origin[k] = -(span - full[k]) / 2.0
		else:
			origin[k] = clampf(at * scale - span / 2.0, 0.0, full[k] - span)
	window_origin = origin.floor()
	scale_now = scale
	region_now = region
	c.fill_rect(MAP_X - 4, MAP_Y - 4, MAP_W + 8, 152, Canvas.rgb(30, 23, 18))
	c.rect_outline(MAP_X - 4, MAP_Y - 4, MAP_W + 8, 152, Canvas.rgb(149, 117, 81))
	c.rect_outline(MAP_X - 1, MAP_Y - 1, MAP_W + 2, MAP_H + 2, Canvas.rgb(84, 64, 45))
	_blit(c)
	if not g.in_hub:
		for door: LevelData.Door in g.world.doors:
			if not door.secret or door.discovered:
				var color := (
					Canvas.rgb(110, 136, 90)
					if door.opened
					else Canvas.rgb(222, 128, 52) if door.key != "" else Canvas.rgb(176, 132, 82)
				)
				_cell_mark(c, float(door.x), float(door.y), color)
	for station: LevelData.Station in g.world.stations:
		if not station.reveals_secret and (not station.hidden or g.stations_done.has(station.id)):
			var at2 := point(station.x, station.y)
			if shows(at2):
				var done := g.stations_done.has(station.id)
				var mark := Canvas.rgb(151, 187, 110) if done else Canvas.rgb(236, 168, 84)
				c.fill_rect(int(at2.x) - 2, int(at2.y) - 2, 5, 5, Canvas.rgb(22, 17, 13))
				c.fill_rect(int(at2.x) - 1, int(at2.y) - 1, 3, 3, mark)
	if g.world.extraction != null:
		var at3 := point(g.world.extraction.x, g.world.extraction.y)
		if shows(at3):
			c.circle(
				int(at3.x),
				int(at3.y),
				3,
				Canvas.rgb(151, 187, 110) if g.exit_ready() else Canvas.rgb(190, 110, 84),
				false
			)
	_labels(g, c)
	CountyStorm.draw_map(c, g)
	_goal(g, c)
	_player_mark(g, c)
	MapKey.draw(c, MAP_X + 1, MAP_Y + MAP_H - 1)  # what the marks mean
	c.line(MAP_X, MAP_Y + MAP_H + 3, MAP_X + MAP_W - 1, MAP_Y + MAP_H + 3, Canvas.rgb(120, 87, 59))
	HUD.text(
		c,
		g.objective() if g.hints else g.level.title,
		160,
		MAP_Y + MAP_H + 6,
		"body",
		Canvas.rgb(248, 199, 127),
		true
	)
	var tally := (
		"ROAD NOTES %d/%d" % [g.hub_findings.size(), g.world.hub_clues.size()]
		if g.in_hub
		else "SECRETS %d/%d" % [g.secrets, g.total_secrets]
	)
	var keys := "   /   TAP TO ZOOM" if g.touch_aim else "   /   PGUP PGDN ZOOM   /   TAB CLOSE"
	if Modes.is_tactical(g):
		var sites: Dictionary = g.world.tactical.get("sites", {})
		tally = "SITE A MARKED" if sites.size() == 1 else "SITES A AND B MARKED"
		keys = "   /   PGUP PGDN ZOOM   /   M CLOSE"
	HUD.text(c, tally + keys, 160, MAP_Y + MAP_H + 15, "body", HUD.INK, true)


## The part of the level the map covers, in cells: all of it, or the
## Crossroads' own window of hub.json.
func _region(g: Game) -> Rect2i:
	if g.in_hub and not g.level.map_window.is_empty():
		var wnd: Array = g.level.map_window
		return Rect2i(_int(wnd[0]), _int(wnd[1]), _int(wnd[2]), _int(wnd[3]))
	return Rect2i(0, 0, int(g.world.width), int(g.world.height))


func _scale_for(g: Game, region: Rect2i) -> float:
	var fit := minf(float(MAP_W) / region.size.x, float(MAP_H) / region.size.y)
	var zoom: float = MAP_ZOOMS[clampi(g.map_zoom, 0, MAP_ZOOMS.size() - 1)]
	return fit if zoom <= 0.0 or zoom <= fit else zoom


func _signature_changed(g: Game) -> bool:
	return _signature(g) != last_signature


## What the map image shows that can change: the secret doors still hidden,
## and how many cells have opened (a fence broken through).
func _signature(g: Game) -> Array:
	var signature: Array = [g.world.solid_version]
	for door: LevelData.Door in g.world.doors:
		if door.secret and not door.discovered:
			signature.append(Vector2i(door.x, door.y))
	return signature


## The whole map at this scale, in an image: ground by kind, walls drawn as
## lines along every edge between open ground and a wall. Ground still hidden
## behind a secret door stays dark.
func _build_image(g: Game, region: Rect2i, scale: float) -> void:
	var signature := _signature(g)
	last_signature = signature
	hidden.clear()
	for point: Vector2i in signature.slice(1):
		hidden[point] = true
		for room: Array in g.level.hidden_rooms:
			if room[0] == point:
				var box: Vector4i = room[1]
				for yy in range(box.y, box.w + 1):
					for xx in range(box.x, box.z + 1):
						hidden[Vector2i(xx, yy)] = true
	var size := (Vector2(region.size) * scale).ceil()
	image = Image.create_empty(maxi(1, int(size.x)), maxi(1, int(size.y)), false, Image.FORMAT_RGB8)
	image.fill(MAP_BACK)
	built_scale = scale
	region_now = region
	painted = 0
	for yy in range(region.position.y, region.end.y):
		for xx in range(region.position.x, region.end.x):
			if _open(g, xx, yy):
				_paint_cell(g, xx, yy, false)


func _open(g: Game, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= g.world.width or y >= g.world.height:
		return false
	return int(g.world.solid[y * int(g.world.width) + x]) < 0 and not hidden.has(Vector2i(x, y))


func _cell_rect(x: int, y: int) -> Rect2i:
	var region := region_now
	var s := built_scale
	var x0 := int(roundf((x - region.position.x) * s))
	var y0 := int(roundf((y - region.position.y) * s))
	var x1 := int(roundf((x - region.position.x + 1) * s))
	var y1 := int(roundf((y - region.position.y + 1) * s))
	return Rect2i(x0, y0, maxi(1, x1 - x0), maxi(1, y1 - y0))


## One cell of ground, walked or not, with its wall edges.
func _paint_cell(g: Game, x: int, y: int, walked: bool) -> void:
	var cell := y * int(g.world.width) + x
	var kind := 0 if g.world.roof[cell] == 0.0 else 1
	if g.world.surface_sound(int(g.world.floor_tile[cell])) == "water":
		kind = 2
	var r := _cell_rect(x, y)
	var shade: Color = (MAP_WALKED if walked else MAP_GROUND)[kind]
	image.fill_rect(r, shade)
	var line := 2 if built_scale >= 4.0 else 1
	for k: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var n := Vector2i(x, y) + k
		if not _open(g, n.x, n.y) and region_now.has_point(n):
			image.fill_rect(_cell_rect(n.x, n.y), MAP_MASS)
	if not _open(g, x - 1, y):
		image.fill_rect(Rect2i(r.position.x, r.position.y, line, r.size.y), MAP_WALL)
	if not _open(g, x + 1, y):
		image.fill_rect(Rect2i(r.end.x - line, r.position.y, line, r.size.y), MAP_WALL)
	if not _open(g, x, y - 1):
		image.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, line), MAP_WALL)
	if not _open(g, x, y + 1):
		image.fill_rect(Rect2i(r.position.x, r.end.y - line, r.size.x, line), MAP_WALL)


## The ground walked since the image was last brought up to date.
func _paint_walked(g: Game, region: Rect2i, _scale: float) -> void:
	var keys: Array = g.visited.keys()
	for i in range(painted, keys.size()):
		var key: Vector2i = keys[i]
		if region.has_point(key) and _open(g, key.x, key.y):
			_paint_cell(g, key.x, key.y, true)
	painted = keys.size()


## Where a point of the level is on the canvas, this frame.
func point(x: float, y: float) -> Vector2:
	return Vector2(
		MAP_X + (x - region_now.position.x) * scale_now - window_origin.x,
		MAP_Y + (y - region_now.position.y) * scale_now - window_origin.y
	)


func shows(at: Vector2) -> bool:
	return at.x >= MAP_X and at.y >= MAP_Y and at.x < MAP_X + MAP_W and at.y < MAP_Y + MAP_H


func _cell_mark(c: Canvas, x: float, y: float, color: Color) -> void:
	var a := point(x, y)
	var b := point(x + 1.0, y + 1.0)
	var x0 := maxi(MAP_X, int(a.x))
	var y0 := maxi(MAP_Y, int(a.y))
	var x1 := mini(MAP_X + MAP_W, maxi(int(b.x), int(a.x) + 1))
	var y1 := mini(MAP_Y + MAP_H, maxi(int(b.y), int(a.y) + 1))
	if x1 > x0 and y1 > y0:
		c.fill_rect(x0, y0, x1 - x0, y1 - y0, color)


func _labels(g: Game, c: Canvas) -> void:
	var labels: Array = []
	if g.in_hub:
		for gate: LevelData.Gate in g.world.hub_gates:
			labels.append(
				[
					str(Campaign.GATE_LABELS.get(gate.destination, "")),
					gate.x,
					gate.y,
					not g.world.locked_gates.has(gate)
				]
			)
		for clue: Variant in g.world.hub_clues:
			if g.hub_findings.has(str(clue[0])):
				var at := point(_num(clue[1]), _num(clue[2]))
				if shows(at):
					c.polygon(
						[
							Vector2(at.x, at.y - 3),
							Vector2(at.x + 3, at.y),
							Vector2(at.x, at.y + 3),
							Vector2(at.x - 3, at.y)
						],
						Canvas.rgb(200, 173, 111)
					)
	else:
		for row: Variant in g.level.map_labels:
			labels.append([str(row[0]), _num(row[1]), _num(row[2]), true])
	var placed: Array[Rect2i] = []
	for label_row: Array in labels:
		var label := str(label_row[0])
		if label == "":
			continue
		var at := point(_num(label_row[1]), _num(label_row[2]))
		var wide := PixelType.text_width(label)
		var left := int(at.x) - wide / 2
		if left < MAP_X + 1 or left + wide > MAP_X + MAP_W - 1:
			continue
		if at.y < MAP_Y + 1 or at.y > MAP_Y + MAP_H - 9:
			continue
		# Zoomed out, names that would sit on each other: the first one only.
		var box := Rect2i(left - 3, int(at.y) - 2, wide + 6, 11)
		var crowded := false
		for other: Rect2i in placed:
			if other.intersects(box):
				crowded = true
				break
		if crowded:
			continue
		placed.append(box)
		c.fill_rect(left - 2, int(at.y) - 1, wide + 4, 9, Canvas.rgb(30, 23, 18))
		HUD.text(
			c,
			label,
			left,
			int(at.y),
			"body",
			Canvas.rgb(244, 223, 185) if label_row[3] else Canvas.rgb(185, 123, 85),
			false,
			false
		)


## Where the objective pin points: a blinking diamond, or an arrow on the
## window's edge pointing to it when it is off the map.
func _goal(g: Game, c: Canvas) -> void:
	var goal: Variant = g.objective_target()
	if goal == null or not (goal is Vector2):
		return
	var spot: Vector2 = goal
	var at := point(spot.x, spot.y)
	var color := (
		Canvas.rgb(255, 214, 110) if int(g.clock * 3.0) % 2 == 0 else Canvas.rgb(214, 120, 60)
	)
	if shows(at):
		c.polygon(
			[
				Vector2(at.x, at.y - 4),
				Vector2(at.x + 4, at.y),
				Vector2(at.x, at.y + 4),
				Vector2(at.x - 4, at.y)
			],
			color
		)
		return
	var middle := Vector2(MAP_X + MAP_W / 2.0, MAP_Y + MAP_H / 2.0)
	var way := (at - middle).normalized()
	var reach := minf(
		(MAP_W / 2.0 - 6.0) / maxf(.001, absf(way.x)), (MAP_H / 2.0 - 6.0) / maxf(.001, absf(way.y))
	)
	var tip := middle + way * reach
	var side := Vector2(-way.y, way.x)
	c.polygon([tip + way * 4.0, tip - way * 3.0 + side * 3.5, tip - way * 3.0 - side * 3.5], color)


func _player_mark(g: Game, c: Canvas) -> void:
	var at := point(g.player.x, g.player.y)
	var way := Vector2(cos(g.player.angle), sin(g.player.angle))
	var side := Vector2(-way.y, way.x)
	var size := clampf(scale_now * 1.4, 3.0, 5.0)
	var tip := at + way * size * 1.3
	var back_l := at - way * size * .8 + side * size * .8
	var back_r := at - way * size * .8 - side * size * .8
	c.polygon([tip, back_l, at - way * size * .3, back_r], Canvas.rgb(255, 170, 80))
	c.line(int(tip.x), int(tip.y), int(back_l.x), int(back_l.y), Canvas.rgb(70, 32, 14))
	c.line(int(tip.x), int(tip.y), int(back_r.x), int(back_r.y), Canvas.rgb(70, 32, 14))


## The visible part of the map image into the window.
func _blit(c: Canvas) -> void:
	var src := Rect2i(maxi(0, int(window_origin.x)), maxi(0, int(window_origin.y)), 0, 0)
	var dst := Vector2i(
		MAP_X + maxi(0, -int(window_origin.x)), MAP_Y + maxi(0, -int(window_origin.y))
	)
	src.size = Vector2i(
		mini(image.get_width() - src.position.x, MAP_X + MAP_W - dst.x),
		mini(image.get_height() - src.position.y, MAP_Y + MAP_H - dst.y)
	)
	if src.size.x <= 0 or src.size.y <= 0:
		return
	var crop := image.get_region(src)
	if c.gpu:
		if texture == null or texture.get_size() != Vector2(src.size):
			texture = ImageTexture.create_from_image(crop)
		else:
			texture.update(crop)
		c.gpu_texture(texture, dst.x, dst.y, src.size.x, src.size.y)
		return
	var data := crop.get_data()
	var pix := c.pixels
	var row_bytes := src.size.x * 3
	for row in src.size.y:
		var from := row * row_bytes
		var to := ((dst.y + row) * Canvas.WIDTH + dst.x) * 3
		for k in row_bytes:
			pix[to + k] = data[from + k]
		if c.layer:
			var at := (dst.y + row) * Canvas.WIDTH + dst.x
			for k in src.size.x:
				c.cover[at + k] = 255


## float() and int() of a number read from a list or dictionary, typed (the
## same result for a number or a bool).
static func _num(v: Variant) -> float:
	return v


static func _int(v: Variant) -> int:
	return v
