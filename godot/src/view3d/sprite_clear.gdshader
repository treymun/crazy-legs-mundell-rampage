// The see-through sprites (smoke, blasts, mist): sprite.gdshader, blended.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled, skip_vertex_transform;

#define CLEAR
#include "res://src/view3d/sprite_body.gdshaderinc"
