// The level's walls, floors and roofs (level_mesh.gd), drawn as the old
// renderer drew them: nearest texels of the 128x128 tiles, repeating walls
// laid at 1.28 units from z 1.96, window bands between 1.0 and 1.68, the
// distance-stepped light with the area's tint, sign glow, then (effects_on)
// the lights, grade and fog of surface_light().
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled, fog_disabled;

#include "res://src/view3d/world_body.gdshaderinc"
