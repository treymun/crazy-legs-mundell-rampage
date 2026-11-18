## Each model part of the 3D view (a prop's, a wreck piece's, an actor's,
## a seat view's) draws with a material of its own, a copy of its model's,
## and its own numbers (its tone, a hit's wash, its look, its marks) are that
## material's uniforms. They were instance uniforms until pass 10: every
## part holding them takes a block of 16 vec4 slots of the shader instance
## buffer, which holds 256 parts on a desktop and 60 where a uniform block
## holds 16 KB (WebGL2, many phones); busy scenes showed 60 to 110 parts and
## past the room parts draw black. A material of its own takes no slot, and
## the frame's numbers are global uniforms (world_view.gd), so it is never
## touched from frame to frame.
class_name OwnMaterial
extends RefCounted


## Give `mesh` its own copy of `base` (the model's material: its baked
## texture, looks and settings) and return it.
static func give(mesh: GeometryInstance3D, base: ShaderMaterial) -> ShaderMaterial:
	var own := base.duplicate() as ShaderMaterial
	mesh.material_override = own
	return own


## Set number `name` on `mesh`'s own material.
static func put(mesh: GeometryInstance3D, name: String, value: Variant) -> void:
	var own := mesh.material_override as ShaderMaterial
	if own != null:
		own.set_shader_parameter(name, value)
