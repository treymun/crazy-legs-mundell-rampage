// The window glazing of the level (world.gdshader's surfaces, see-through).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#define GLASS
#include "res://src/view3d/world_body.gdshaderinc"
