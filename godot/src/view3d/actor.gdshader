// An enemy or boss as a rigged model (actor_layer.gd): its baked look (plain,
// hurt, a boss's phase), lit by the dusk stage its old cels were rendered on
// (a warm key from the front left, a cool fill, a hot rim behind one shoulder
// and a cool one behind the other, a dim sky), kept to the camera as the
// cels' lights were; then as its sprite was lit: light_at(distance, the
// cell's light), no darker than a body's floor, the area's tint, a tough
// guy's tint, a hit's wash toward hot white; LIGHTS AND GLOW's lights, grade
// and fog.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2D look_plain : filter_nearest, repeat_disable;
uniform sampler2D look_hurt : filter_nearest, repeat_disable;
uniform sampler2D look_p2 : filter_nearest, repeat_disable;
uniform sampler2D look_p3 : filter_nearest, repeat_disable;
// The area's tint (rgb) and the cell's light (a).
instance uniform vec4 tone = vec4(1.0);
// A tough guy's tint (rgb) and the hit wash (a).
instance uniform vec4 wash = vec4(1.0, 1.0, 1.0, 0.0);
// 0 plain, 1 hurt, 2 a boss's second phase, 3 its third.
instance uniform int look = 0;
// The looks were baked with the dusk stage's light (the front cel's): only a
// turn's shade is added, so a side or back seen keeps some modelling.
uniform bool baked_light = false;

varying vec3 map_p;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
}

vec3 stage_light(vec3 n) {
	// The stage's lights, toward each, in the camera's space (x right, y up,
	// z toward the eye), weighted to come out as bright as Cycles drew them.
	vec3 sum = vec3(0.56, 0.54, 0.58) * 0.62;
	sum += vec3(1.0, 0.86, 0.66) * 1.20 * max(0.0, dot(n, normalize(vec3(-0.50, 0.70, 0.58))));
	sum += vec3(0.66, 0.70, 1.00) * 0.26 * max(0.0, dot(n, normalize(vec3(0.70, 0.25, 0.55))));
	sum += vec3(1.0, 0.70, 0.42) * 0.95 * max(0.0, dot(n, normalize(vec3(0.35, 0.55, -0.75))));
	sum += vec3(0.72, 0.80, 1.00) * 0.55 * max(0.0, dot(n, normalize(vec3(-0.60, 0.35, -0.70))));
	// The cels' dark rim (paint.gd photo_shrink): an edge turned away from the
	// eye darkens, so the figure cuts out against any wall.
	return sum * mix(0.62, 1.0, smoothstep(0.06, 0.32, n.z));
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	vec4 texel;
	ivec2 size = textureSize(look_plain, 0);
	ivec2 at = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	if (look == 1) {
		texel = texelFetch(look_hurt, at, 0);
	} else if (look == 2) {
		texel = texelFetch(look_p2, at, 0);
	} else if (look == 3) {
		texel = texelFetch(look_p3, at, 0);
	} else {
		texel = texelFetch(look_plain, at, 0);
	}
	vec3 albedo = floor(texel.rgb * 255.0 + 0.5);
	vec3 n = normalize(NORMAL);
	vec3 shaded;
	if (baked_light) {
		float turn = 0.88 + 0.12 * max(0.0, dot(n, normalize(vec3(-0.35, 0.55, 0.75))));
		// Only a true silhouette edge darkens: a body lying flat, seen
		// edge on, keeps its colour.
		float rim = mix(0.8, 1.0, smoothstep(0.02, 0.18, n.z));
		shaded = albedo * turn * rim * wash.rgb;
	} else {
		shaded = photo_grade(albedo * stage_light(n)) * wash.rgb;
	}
	float t = -VERTEX.z;
	float raw = max(0.19, tone.a / (1.0 + 0.102 * t));
	raw = max(raw, 0.58 - 0.021 * t);
	float lit = floor(raw * 32.0 + 0.5) / 32.0;
	vec3 colour = clamp(floor(shaded * lit * tone.rgb), 0.0, 255.0);
	if (wash.a > 0.0) {
		colour = floor(colour * (1.0 - wash.a) + vec3(255.0, 232.0, 208.0) * wash.a);
	}
	if (effects_on) {
		vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 nf = vec3(n.x, n.z, n.y);
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
