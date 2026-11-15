// Rain falling past the eye (the old view shader rain_over): three layers of
// streaks, hung in front of the camera at 1.3, 2.8 and 6 units (world_view.gd),
// so whatever stands nearer than a layer hides it. A streak shows only where
// the sky is open over its layer; turning carries the rain with the world.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform int layer_k = 0;

varying vec3 map_p;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
}

void fragment() {
	if (!effects_on || rain <= 0.0 || motion <= 0.0) {
		discard;
	}
	int k = layer_k;
	// In 320-wide steps, whatever the view's size (HD, LOW).
	vec2 q = (floor(FRAGCOORD.xy) + 0.5) * (320.0 / view_size.x);
	float f320 = focal * 320.0 / view_size.x;
	float turn = mod(view_angle, 6.2831853) * f320;
	vec3 drop = min(vec3(124.0, 134.0, 148.0) * (1.0 + lightning * 0.9), vec3(255.0));
	float cw = k == 0 ? 7.0 : (k == 1 ? 5.0 : 4.0);
	float len = k == 0 ? 10.0 : (k == 1 ? 7.0 : 4.0);
	float speed = k == 0 ? 330.0 : (k == 1 ? 250.0 : 180.0);
	float seg_len = len * 3.5;
	float v = q.y - anim_time * speed;
	float u = q.x + turn + v * 0.18;
	float col = mod(floor(u / cw), floor(6.2831853 * f320 / cw));
	float seg = floor(v / seg_len);
	float h = hash12(vec2(col, seg) + float(k) * 41.0);
	if (h > rain * (k == 0 ? 0.3 : 0.5)) {
		discard;
	}
	float in_v = v - seg * seg_len;
	float yo = floor(fract(h * 53.3) * (seg_len - len));
	if (floor(u - floor(u / cw) * cw) != floor(fract(h * 91.7) * (cw - 1.0)) || in_v < yo || in_v >= yo + len) {
		discard;
	}
	if (!open_sky(map_p.xy)) {
		discard;
	}
	ALBEDO = to_output(drop);
	ALPHA = (k == 0 ? 0.32 : (k == 1 ? 0.24 : 0.16)) * (0.55 + 0.45 * (in_v - yo) / len);
}
