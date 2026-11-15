// A pickup in the 3D view (pickup_layer.gd): its picture pushed out into a
// slab (pickup_models.gd), lit, tinted, fogged and paletted as the sprite it
// replaces was (sprite_body.gdshaderinc with MESH). Solid: it never writes ALPHA.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled, skip_vertex_transform;

#define MESH
#include "res://src/view3d/sprite_body.gdshaderinc"
