## Fail when the display shader samples more textures than a WebGL page allows.
##
##   Godot --headless --path godot --script res://tools/check_shader.gd
##
## WebGL 2 and many phone GPUs give a fragment shader 16 texture units, and
## Godot's canvas renderer keeps several of them for itself (TEXTURE, normal
## and specular maps, lights, the screen and SDF textures). Measured in Chrome:
## with 13 the page drew nothing ("two textures of different types use the
## same sampler location"); nine works. Past the limit the browser and Android
## builds lose their picture while a desktop looks fine.
extends SceneTree

const LIMIT := 9


func _init() -> void:
	var code := FileAccess.get_file_as_string("res://src/palette.gdshader")
	var samplers := PackedStringArray()
	var pattern := RegEx.create_from_string(
		"(?m)^\\s*uniform\\s+(?:sampler2D|sampler2DArray|sampler3D|usampler2D|isampler2D)\\s+(\\w+)"
	)
	for found in pattern.search_all(code):
		samplers.append(found.get_string(1))
	var used := samplers.size() + 1
	print(
		(
			"palette.gdshader samples %d textures (limit %d): TEXTURE, %s"
			% [used, LIMIT, ", ".join(samplers)]
		)
	)
	if used > LIMIT:
		print("FAIL: too many textures for WebGL and many phones")
		quit(1)
		return
	print("SHADER OK")
	quit()
