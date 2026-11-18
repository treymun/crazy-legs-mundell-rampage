// A vehicle's seat view (cab_layer.gd): the driver's own vehicle, drawn
// shrunk toward the eye by `shrink` so it sits nearer than anything in the
// world and never cuts into a wall or hides behind one, looking the size it
// is. Lit as a prop is (prop.gdshader): its baked texture, the light of the
// cell the driver sits in stepped by the distance it would be at full size,
// the area's tint, then LIGHTS AND GLOW's lights at the place it would be,
// grade and fog.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2D baked : filter_nearest, repeat_disable;
// How much nearer than its size it is drawn (cab_layer.gd SHRINK).
uniform float shrink = 0.1;
// The area's tint (rgb) and the cell's light (a), where the driver sits.
uniform vec4 tone = vec4(1.0, 1.0, 1.0, 1.0);
// How much of a part shows (cab_layer.gd: the airboat's prop fading into
// its spinning disc): below 1, an ordered stipple of its pixels is left
// out, as a 1997 game showed a blur, the world showing through.
uniform float opacity = 1.0;
// Up close the stepped light would burn pale paint white: no nearer than
// this (cells) for the light.
const float LIGHT_NEAR = 2.5;

varying vec3 map_p;
varying vec3 map_n;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	// Where it would be at full size.
	vec3 full = cam + (w - cam) / shrink;
	map_p = vec3(full.x, full.z, full.y);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(n.x, n.z, n.y);
}

void fragment() {
	if (opacity < 0.999) {
		ivec2 cell = ivec2(FRAGCOORD.xy) % 4;
		int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
		if ((float(bayer[cell.y * 4 + cell.x]) + 0.5) / 16.0 > opacity) {
			discard;
		}
	}
	ivec2 size = textureSize(baked, 0);
	ivec2 at = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	vec3 texel = floor(texelFetch(baked, at, 0).rgb * 255.0 + 0.5);
	float t = -VERTEX.z / shrink;
	float lit = min(stepped_light(tone.a, max(t, LIGHT_NEAR)), 1.0);
	vec3 colour = clamp(floor(texel * lit * tone.rgb), 0.0, 255.0);
	if (effects_on) {
		vec3 cam = vec3(CAMERA_POSITION_WORLD.x, CAMERA_POSITION_WORLD.z, CAMERA_POSITION_WORLD.y);
		vec3 nf = dot(map_n, cam - map_p) < 0.0 ? -map_n : map_n;
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
