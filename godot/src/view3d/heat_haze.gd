## The air shimmering over hot things the eye can see (fires, grills, the
## still, burning fuel): up to four boxes of the view for the display shader's
## haze_shift (palette.gdshader), worked out from the 3D view's eye the way
## SceneLayers did for the old view. Each box is its centre column, base row,
## half width and height in view pixels; `sway` how far it moves.
class_name HeatHaze
extends RefCounted


## Set palette.gdshader's haze_count, haze_box and haze_amp for this frame.
static func apply(material: ShaderMaterial, game: Game) -> void:
	var view: Dictionary = game.view_frame
	var r: Renderer = game.renderer
	var motion: float = [1.0, .4, 0.0][clampi(r.world_motion, 0, 2)]
	var boxes := PackedVector4Array()
	var sway := PackedFloat32Array()
	boxes.resize(4)
	sway.resize(4)
	var count := 0
	var sources: Array = (
		ViewLights.heat_sources(game, 6) if motion > 0.0 and Effects.enabled else []
	)
	var eye: Dictionary = view.get("eye", {})
	if eye.is_empty():
		sources = []
	for s: Array in sources:
		if count >= 4:
			break
		var cx: float = eye["x"]
		var cy: float = eye["y"]
		var cz: float = eye["eye"]
		var angle: float = eye["view_angle"]
		var fx := cos(angle)
		var fy := sin(angle)
		var dx := float(s[0]) - cx
		var dy := float(s[1]) - cy
		var depth := dx * fx + dy * fy
		if depth < .6 or depth > 14.0:
			continue
		var column := r.vw * .5 + (-dx * fy + dy * fx) / depth * r.focal
		var half := float(s[3]) / depth * r.focal
		if column + half < 0.0 or column - half > r.vw:
			continue
		if not _clear(game.world, cx, cy, float(s[0]), float(s[1])):
			continue
		var base: float = float(view["horizon"]) + (cz - float(s[2])) / depth * r.focal
		boxes[count] = Vector4(column, base, half, float(s[3]) * 3.2 / depth * r.focal)
		sway[count] = (1.6 - depth * .07) * motion * (2.0 if r.detail < 0 else 1.0)
		count += 1
	material.set_shader_parameter("haze_count", count)
	material.set_shader_parameter("haze_box", boxes)
	material.set_shader_parameter("haze_amp", sway)


## No wall cell nor shut door on the line from the eye to a hot thing.
static func _clear(world: LevelData, ax: float, ay: float, bx: float, by: float) -> bool:
	var steps := maxi(1, int(Vector2(bx - ax, by - ay).length() * 4.0))
	for i in range(1, steps):
		var t := float(i) / steps
		var x := ax + (bx - ax) * t
		var y := ay + (by - ay) * t
		if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
			return false
		if world.solid[int(y) * world.width + int(x)] >= 0:
			return false
		for door: LevelData.Door in world.near_doors.get(Vector2i(int(x), int(y)), []):
			if door.blocks(x, y, 0.0):
				return false
	return true
