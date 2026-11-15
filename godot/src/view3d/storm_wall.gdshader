// County Run's storm front (src/modes/county_storm.gd) as the 3D view shows
// it: an open cylinder round the safe ground (world_view.gd stands and sizes
// it each frame), a dark wall of rain and dust, streaks driving down and
// round it with the wind, lit by the lightning, thinning toward its top.
// See-through, so it has a shader of its own (it writes ALPHA).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

// The ring's radius (cells) and how hard the storm blows (0 to 1).
uniform float storm_r = 10.0;
uniform float storm_k = 0.5;

varying vec3 map_p;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
}

void fragment() {
	float tm = anim_time * max(motion, 0.15);
	// Around the ring and up it, in cells: fine streaks of rain driving down,
	// carried round by the wind, over a dark churning curtain.
	float around = UV.x * 6.2831853 * storm_r + tm * 1.5 * (0.5 + storm_k);
	float up = map_p.z;
	float column = floor(around * 18.0);
	float drop = (up * 2.6 + tm * 13.0 + hash12(vec2(column, 7.0)) * 9.0) / 1.1;
	float h = hash12(vec2(column, floor(drop)));
	float streak = h < 0.16 + 0.16 * storm_k ? 1.0 : 0.0;
	float churn = 0.5 + 0.3 * sin(around * 0.23 + tm * 0.7 + up * 0.35) + 0.2 * sin(around * 0.07 - tm * 0.4);
	vec3 colour = mix(vec3(24.0, 26.0, 34.0), vec3(50.0, 54.0, 66.0), churn);
	colour = mix(colour, vec3(104.0, 112.0, 128.0), streak * 0.5);
	colour = min(colour * (1.0 + lightning * vec3(1.4, 1.5, 1.7)), vec3(255.0));
	float top = 1.0 - smoothstep(5.0, 12.0, up);
	float near = smoothstep(0.3, 2.5, -VERTEX.z);
	ALBEDO = to_output(floor(colour));
	ALPHA = clamp((0.66 + 0.24 * storm_k + streak * 0.08) * top * near, 0.0, 0.95);
}
