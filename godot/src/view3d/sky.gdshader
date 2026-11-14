// The sky behind everything (palette.gdshader sky_at): the level's 512x116
// panorama, 512 columns a whole turn, its row 93 on the horizon. A quad hung
// near the far end of the camera's reach covers whatever nothing else does.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2D sky_tex : filter_nearest, repeat_disable;
uniform float view_angle = 0.0;
uniform float horizon = 78.0;
uniform float focal = 230.0;
uniform vec2 view_size = vec2(320.0, 156.0);
uniform float res_up = 1.0;
uniform float sky_drift = 0.0;

void fragment() {
	vec2 px = FRAGCOORD.xy;
	float row = px.y;
	float ray = (floor(px.x) + 0.5 - view_size.x * 0.5) / focal;
	int sx = int((view_angle + atan(ray)) * 81.48733086305042) & 511;
	float sy = floor(row) + 0.5 - horizon;
	int sr = clamp(int(93.0 + sy * res_up * 0.95), 0, 115);
	vec3 sky;
	if (!effects_on) {
		sky = texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
	} else {
		float lift = clamp(1.0 - float(sr) / 88.0, 0.0, 1.0);
		sx = (sx + int(sky_drift * 512.0 * lift)) & 511;
		sky = texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
		sky = min(sky * (1.0 + lightning * 1.8 * (0.4 + lift)) + vec3(18.0, 20.0, 30.0) * lightning, vec3(255.0));
	}
	ALBEDO = to_output(floor(sky + 0.5));
}
