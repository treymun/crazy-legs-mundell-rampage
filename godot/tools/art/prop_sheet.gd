## Old picture against new model: for each modelled prop named, a row per
## look (a quest station's to-do and done), its old picture
## (assets/art/town_<picture>.png at the height it was drawn) then its 3D
## model (scenes/props/<name>.tscn with its baked texture mesh_<name>, lit
## by nothing but the bake) seen from the front, from the old picture's
## three-quarter view (turned 28 degrees, 8 degrees down), from its right
## side, from behind and from behind three-quarters. Needs a window.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/art/prop_sheet.gd -- names=a,b out=<file.png> [ppu=96]
##
## The comparison sheets in docs/godot3d/remaster2/props/ come from this.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const BACKDROP := Color8(90, 110, 130)
const GAP := 6
const TURNS: Array[float] = [0.0, -28.0, 90.0, 180.0, 152.0]
const PITCH := 8.0

var ppu := 96.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var names: PackedStringArray = []
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("names="):
			names = arg.substr(6).split(",")
		elif arg.begins_with("out="):
			out = arg.substr(4)
		elif arg.begins_with("ppu="):
			ppu = float(arg.substr(4))
	if names.is_empty() or out == "":
		push_error("prop_sheet.gd -- names=a,b out=<file.png> [ppu=96]")
		quit(1)
		return
	var sizes: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(PropModels.FOLDER.path_join("meshes.json"))
	)
	var pictures: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(Paint.repo("assets/art/town_props.json"))
	)
	var port := SubViewport.new()
	port.own_world_3d = true
	port.transparent_bg = false
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	port.add_child(world_env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	port.add_child(camera)
	var rows: Array[Image] = []
	for name in names:
		if not sizes.has(name):
			push_error("%s: no model" % name)
			continue
		var dims: Array = sizes[name]
		var w: float = dims[0]
		var d: float = dims[1]
		var h: float = dims[2]
		var reach := sqrt(w * w + d * d) + .3
		var span := h + .2 + reach * sin(deg_to_rad(PITCH))
		var cell := Vector2i(ceili(reach * ppu), ceili(span * ppu))
		port.size = cell
		camera.size = span
		var p := deg_to_rad(PITCH)
		var aim := Vector3(0, h * .5, 0)
		camera.transform = Transform3D(
			Basis(Vector3.RIGHT, -p), aim + Vector3(0, sin(p), cos(p)) * 20.0
		)
		var texture := ImageTexture.create_from_image(
			Image.load_from_file(Paint.repo("assets/art/mesh_%s.png" % name))
		)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var packed := load(PropModels.SCENES.path_join(name + ".tscn")) as PackedScene
		var view := packed.instantiate() as PropView
		port.add_child(view)
		for mesh: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
		var looks: Array[String] = [""]
		if pictures.has("quest_%s_off" % name.trim_prefix("quest_")) and not pictures.has(name):
			looks = ["off", "on"]
		for look in looks:
			view.show_look(look)
			var picture := name if look == "" else "%s_%s" % [name, look]
			var old := Image.load_from_file(Paint.repo("assets/art/town_%s.png" % picture))
			# A painted sign is not in town_props.json: drawn as tall as its model.
			var old_h: float = (pictures[picture] as Array)[1] if pictures.has(picture) else h
			var scaled := Vector2i(
				maxi(1, roundi(old.get_width() * old_h * ppu / old.get_height())),
				maxi(1, roundi(old_h * ppu))
			)
			old.resize(scaled.x, scaled.y, Image.INTERPOLATE_NEAREST)
			var shots: Array[Image] = []
			for turn in TURNS:
				view.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(turn)), Vector3.ZERO)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				shots.append(port.get_texture().get_image())
			var row_h := maxi(cell.y, scaled.y)
			var row_w := GAP + scaled.x + GAP + (cell.x + GAP) * shots.size()
			var row := Image.create(row_w, row_h, false, Image.FORMAT_RGBA8)
			row.fill(BACKDROP)
			old.convert(Image.FORMAT_RGBA8)
			row.blend_rect(old, Rect2i(Vector2i.ZERO, scaled), Vector2i(GAP, row_h - scaled.y))
			var x := GAP + scaled.x + GAP
			for shot in shots:
				shot.convert(Image.FORMAT_RGBA8)
				row.blit_rect(shot, Rect2i(Vector2i.ZERO, cell), Vector2i(x, row_h - cell.y))
				x += cell.x + GAP
			rows.append(row)
		view.queue_free()
	var wide := 0
	var tall := 0
	for row in rows:
		wide = maxi(wide, row.get_width())
		tall += row.get_height() + GAP
	var sheet := Image.create(maxi(1, wide), maxi(1, tall), false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(40, 44, 48))
	var y := 0
	for row in rows:
		sheet.blit_rect(row, Rect2i(Vector2i.ZERO, row.get_size()), Vector2i(0, y))
		y += row.get_height() + GAP
	sheet.save_png(out)
	print("PROP SHEET %d rows -> %s" % [rows.size(), out])
	quit()
