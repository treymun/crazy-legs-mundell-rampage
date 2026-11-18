// The fine debris of a break (wreck_layer.gd, a MultiMesh of small boxes:
// splinters, straw, shards, slivers, crumbs): each box its own colour
// (INSTANCE COLOR, the palette's), lit in its cell (INSTANCE_CUSTOM: the
// area's tint, the cell's light) as a wreck piece is, its top a little
// brighter than its sides. Solid: no ALPHA.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

varying vec3 map_p;
varying vec3 map_n;
varying vec3 own_colour;
varying vec4 own_tone;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(n.x, n.z, n.y);
	own_colour = COLOR.rgb;
	own_tone = INSTANCE_CUSTOM;
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	vec3 texel = floor(own_colour * 255.0 + 0.5);
	texel = floor(texel * (0.8 + 0.2 * abs(map_n.z)));
	float t = -VERTEX.z;
	float lit = stepped_light(own_tone.a, t);
	vec3 colour = clamp(floor(texel * lit * own_tone.rgb), 0.0, 255.0);
	if (effects_on) {
		vec3 cam = vec3(CAMERA_POSITION_WORLD.x, CAMERA_POSITION_WORLD.z, CAMERA_POSITION_WORLD.y);
		vec3 nf = dot(map_n, cam - map_p) < 0.0 ? -map_n : map_n;
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
