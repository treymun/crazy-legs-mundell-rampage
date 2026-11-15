## Fail when a shader samples more textures than a WebGL page or phone allows.
##
##   Godot --headless --path godot --script res://tools/check_shader.gd
##
## WebGL 2 and many phone GPUs give a fragment shader 16 texture units, and
## Godot keeps several of them for itself (for the canvas: TEXTURE, normal and
## specular maps, lights, the screen and SDF textures; for 3D: the radiance,
## shadow and screen textures). Measured in Chrome on the old canvas shader:
## with 13 the page drew nothing ("two textures of different types use the
## same sampler location"); nine works. Past the limit the browser and Android
## builds lose their picture while a desktop looks fine.
extends SceneTree

## The display shader (a canvas shader), counting Godot's own TEXTURE.
const LIMIT := 9
## The 3D view's shaders, with their includes.
const LIMIT_3D := 10
const SHADERS_3D := "res://src/view3d/"

var _sampler := RegEx.create_from_string(
	"(?m)^\\s*uniform\\s+(?:sampler2D|sampler2DArray|sampler3D|usampler2D|isampler2D)\\s+(\\w+)"
)
var _include := RegEx.create_from_string('(?m)^\\s*#include\\s+"([^"]+)"')


func _init() -> void:
	var failed := false
	var display := _samplers("res://src/display.gdshader")
	var used := display.size() + 1
	print(
		(
			"display.gdshader samples %d textures (limit %d): TEXTURE, %s"
			% [used, LIMIT, ", ".join(display)]
		)
	)
	failed = used > LIMIT
	for file: String in DirAccess.get_files_at(SHADERS_3D):
		if not file.ends_with(".gdshader"):
			continue
		var found := _samplers(SHADERS_3D + file)
		print("%s samples %d textures (limit %d)" % [file, found.size(), LIMIT_3D])
		if found.size() > LIMIT_3D:
			print("  too many: %s" % ", ".join(found))
			failed = true
	if failed:
		print("FAIL: too many textures for WebGL and many phones")
		quit(1)
		return
	print("SHADER OK")
	quit()


## The sampler uniforms a shader declares, its includes' among them.
func _samplers(path: String) -> PackedStringArray:
	var code := FileAccess.get_file_as_string(path)
	var names := PackedStringArray()
	for found in _include.search_all(code):
		for name in _samplers(found.get_string(1)):
			if not names.has(name):
				names.append(name)
	for found in _sampler.search_all(code):
		if not names.has(found.get_string(1)):
			names.append(found.get_string(1))
	return names
