## The graphics-card view's lights for one frame (effects.cfg), worked out from
## a Game: the gun's flash, blasts, glowing shots, lamps, the props a light
## stands on, keys, quest lamps and trigger lights; and the hot ones whose air
## shimmers (palette.gdshader haze). Moved out of game_view.gd, which calls in
## here from effect_lights(), gun_light() and heat_sources().
class_name ViewLights
extends RefCounted

## The props that carry a light ([light.*] props), found once a level.
static var _props_of := -1
static var _prop_boards: Array = []
## This frame's gathered lights (gather()) and what they were gathered for.
static var _gathered_key: Array = []
static var _gathered: Array = []


## Every light this frame, nearer or farther, with its flags. Worked out once
## a frame (the gun's light, the shader's lights and the shimmer all ask).
static func gather(g: GameView) -> Array:
	var p := g.player
	var key := [
		g.get_instance_id(), Engine.get_process_frames(), g.clock, p.x, p.y, Effects.version
	]
	if key == _gathered_key:
		return _gathered
	_gathered_key = key
	_gathered = _gather(g)
	return _gathered


static func _gather(g: GameView) -> Array:
	var p := g.player
	var found: Array = []
	if g.armory.flash > 0.0:
		var aim := p.view_angle()
		found.append(
			Effects.light(
				"muzzle",
				p.x + cos(aim) * .45,
				p.y + sin(aim) * .45,
				p.eye - .1,
				g.armory.flash / .072
			)
		)
	for blast: GameState.Blast in g.blasts:
		var source := "blast_energy" if blast.kind == "energy" else "blast_fire"
		if blast.kind != "energy" and blast.kind != "fire":
			continue
		var life := float(Effects.LIGHTS.get(source, {}).get("life", .64))
		found.append(
			Effects.light(source, blast.x, blast.y, blast.z, 1.0 - blast.age / maxf(life, .01))
		)
	for shot in g.shots:
		if Effects.LIGHTS.has("shot_" + String(shot.kind)):
			found.append(Effects.light("shot_" + String(shot.kind), shot.x, shot.y, shot.z))
	var lamps_key := Vector2i(g.world.get_instance_id(), g.props.size())
	if lamps_key != g.lamps_of:
		g.lamps_of = lamps_key
		g.lamp_props = g.props.filter(func(spr): return spr.image == "prop_lamp")
		g.lamp_boards = g.world.billboards.filter(
			func(board): return board.glow and board.image in ["hub_lamp", "town_floodlight_tower"]
		)
	for spr: Renderer.Sprite in g.lamp_props:
		if absf(spr.x - p.x) < 12.0 and absf(spr.y - p.y) < 12.0:
			found.append(Effects.light("lamp", spr.x, spr.y, spr.z, 1.0, g.clock))
	# Street lamps pool their light on the ground; the keys glint where they lie.
	for board: LevelData.Billboard in g.lamp_boards:
		if absf(board.x - p.x) < 14.0 and absf(board.y - p.y) < 14.0:
			var top := g.world.elevation(board.x, board.y) + board.z + board.height * .9
			found.append(Effects.light("streetlamp", board.x, board.y, top, 1.0, g.clock))
	found.append_array(_prop_lights(g))
	found.append_array(_boat_engines(g))
	for entry: Array in g.pickups:
		var item := String(entry[0])
		var quest := item.begins_with("key_") or GameState.TASK_ITEMS.has(item)
		if quest and absf(float(entry[1]) - p.x) < 10.0:
			if absf(float(entry[2]) - p.y) < 10.0:
				var x := float(entry[1])
				var y := float(entry[2])
				found.append(Effects.light(item, x, y, g.world.elevation(x, y) + .4, 1.0, g.clock))
	found.append_array(g._quest_lights())
	for l: Array in g.trigger_lights:
		if g.clock < float(l[6]):
			found.append([l[0], l[1], l[2], l[3], l[4], l[5], 0, 0.0])
	return found.filter(func(l): return l != null)


## The nearest Effects.MAX_LIGHTS lights that give light (a hot source of
## strength 0 only shimmers).
static func effect_lights(g: GameView) -> Array:
	return _nearest(g, gather(g).filter(func(l): return float(l[5]) > 0.0), Effects.MAX_LIGHTS)


## The nearest hot sources within 14 cells, at most `most`: [x, y, z, width]
## (palette.gdshader haze), with the level's own heat spots (effects.cfg heat:
## Vector4(x, y, z, width)).
static func heat_sources(g: GameView, most: int) -> Array:
	var p := g.player
	var hot: Array = []
	for l: Array in gather(g):
		if (int(l[6]) & Effects.HOT) != 0:
			hot.append([l[0], l[1], l[8] if l.size() > 8 else l[2], l[7]])
	for spot in Effects.mood(g.level.id, "heat", []):
		var s: Vector4 = spot
		hot.append([s.x, s.y, s.z, s.w])
	var near: Array = []
	for l: Array in _nearest(g, hot, most):
		if absf(float(l[0]) - p.x) < 14.0 and absf(float(l[1]) - p.y) < 14.0:
			near.append([float(l[0]), float(l[1]), float(l[2]), float(l[3])])
	return near


## The light on the gun: the frame's lights where the player stands (a blast
## turns it orange, a lamp warms it, its own flash brightens it), the level's
## tint and a lightning flash. White is the gun as drawn.
static func gun_light(g: GameView) -> Color:
	var p := g.player
	var sum := Vector3.ONE
	for l: Array in effect_lights(g):
		var reach := clampf(
			1.0 - Vector3(p.x, p.y, p.eye).distance_to(Vector3(l[0], l[1], l[2])) / float(l[3]),
			0,
			1
		)
		var c: Color = l[4]
		sum += Vector3(c.r, c.g, c.b) * float(l[5]) * reach * reach
	var tone: Color = Effects.mood(g.level.id, "grade", Color(1, 1, 1))
	sum *= Vector3(tone.r, tone.g, tone.b) * (1.0 + g.lightning * .5)
	return Color(minf(sum.x, 1.8), minf(sum.y, 1.8), minf(sum.z, 1.8))


static func _nearest(g: GameView, found: Array, most: int) -> Array:
	var p := g.player
	var lights: Array = []
	for l: Array in found:
		var dx: float = l[0] - p.x
		var dy: float = l[1] - p.y
		lights.append([dx * dx + dy * dy, l])
	lights.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in mini(most, lights.size()):
		out.append(lights[i][1])
	return out


## The props a light stands on (a still's fire box, a burn barrel, a lantern
## post, the Mothership's engine): effects.cfg [light.*] props, `at` up its
## height.
static func _prop_lights(g: GameView) -> Array:
	var p := g.player
	if _props_of != g.world.get_instance_id():
		_props_of = g.world.get_instance_id()
		_prop_boards = g.world.billboards.filter(
			func(board): return Effects.PROP_LIGHTS.has(board.image)
		)
	var out: Array = []
	for board: LevelData.Billboard in _prop_boards:
		if absf(board.x - p.x) < 14.0 and absf(board.y - p.y) < 14.0:
			var source: String = Effects.PROP_LIGHTS[board.image]
			var spec: Dictionary = Effects.LIGHTS[source]
			var base := g.world.elevation(board.x, board.y) + board.z
			var l = Effects.light(
				source, board.x, board.y, base + board.height * float(spec["at"]), 1.0, g.clock
			)
			if l != null:
				# The shimmer starts where the fire is (heat_at), whatever the light's height.
				l.append(base + board.height * float(spec.get("heat_at", spec["at"])))
				out.append(l)
	return out


## The swamp king's airboat: its engine's hot breath behind the cage.
static func _boat_engines(g: GameView) -> Array:
	var out: Array = []
	if not Effects.LIGHTS.has("airboat_engine"):
		return out
	for e: Enemy in g.enemies:
		if e.alive and e.brain == "swamp_king":
			var x := e.x - cos(e.angle) * .7
			var y := e.y - sin(e.angle) * .7
			out.append(
				Effects.light("airboat_engine", x, y, g.world.elevation(x, y) + 1.1, 1.0, g.clock)
			)
	return out
