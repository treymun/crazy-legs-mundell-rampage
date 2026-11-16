// The sky behind everything (view_light.gdshaderinc sky_at): the level's
// 512x116 panorama, 512 columns a whole turn, its row 93 on the horizon. A
// quad hung near the far end of the camera's reach covers whatever nothing
// else does.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

void fragment() {
	vec2 px = FRAGCOORD.xy;
	vec3 sky = sky_at(int(px.x), floor(px.y) + 0.5 - horizon);
	// Out under County Run's storm (storm_ring): its dark roof overhead.
	if (storm_ring.w > 0.0 && distance(eye.xy, storm_ring.xy) > storm_ring.z) {
		sky = mix(sky, min(STORM_FOG * (1.0 + lightning * 2.0), vec3(255.0)), 0.72);
	}
	ALBEDO = to_output(floor(sky + 0.5));
}
