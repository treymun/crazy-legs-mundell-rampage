// A solid body in the 3D view (solid_layer.gd, solid_kit.gd): a bowling pin
// or ball, a horseshoe, a skee-ball cabinet, a milk bottle and the rest, a
// real mesh turned by its own pose, lit, tinted, fogged and paletted as the
// sprites are (sprite_body.gdshaderinc's light), with a 1997 key light from
// above shading its round sides in steps. Its colours are its materials'
// (UV.x: solid_layer.gd's MATERIALS), not a picture. Solid: no ALPHA.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/view3d/view_light.gdshaderinc"

const int GLOW = 4;
// The materials' colours (0..255): pin white, stripe red, the neck's band,
// the ball, a finger hole, the ball's swirl.
const vec3 PAINT[6] = vec3[6](
	vec3(253.0, 252.0, 247.0),
	vec3(232.0, 74.0, 62.0),
	vec3(214.0, 196.0, 160.0),
	vec3(26.0, 36.0, 56.0),
	vec3(6.0, 8.0, 12.0),
	vec3(58.0, 74.0, 104.0)
);
// The key light's direction (map axes: x, y across, z up) and how glossy each
// material is (the ball shines).
const vec3 KEY = vec3(-0.35, 0.3, 0.89);
const float GLOSS[6] = float[6](0.25, 0.25, 0.1, 0.9, 0.0, 0.9);

varying flat vec4 data;
varying flat vec4 tone;
varying vec3 map_p;
varying vec3 map_n;
varying flat float paint;
varying flat float packed;

void vertex() {
	data = INSTANCE_CUSTOM;
	tone = COLOR;
	paint = UV.x;
	packed = UV.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(wn.x, wn.z, wn.y);
	map_p = vec3(w.x, w.z, w.y);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	int flags = int(data.w + 0.5) & 255;
	int m = clamp(int(paint + 0.5), 0, 5);
	// A face with its own colour (solid_kit.gd): UV.x below zero, UV.y the
	// colour packed r * 65536 + g * 256 + b; -2 shines.
	vec3 base = PAINT[m];
	float gloss = GLOSS[m];
	if (paint < -0.5) {
		base = vec3(floor(packed / 65536.0), mod(floor(packed / 256.0), 256.0), mod(packed, 256.0));
		gloss = paint < -1.5 ? 0.6 : 0.1;
	}
	vec3 n = normalize(map_n);
	vec3 to_eye = normalize(eye - map_p);
	// Round sides in three steps of the key light, as a hand-shaded sprite.
	float key = dot(n, normalize(KEY));
	float shade = key > 0.45 ? 1.0 : (key > -0.1 ? 0.8 : 0.6);
	float t = -VERTEX.z;
	float lit;
	if ((flags & GLOW) != 0) {
		lit = 1.1 * shade;
	} else {
		float raw = max(0.19, tone.a / (1.0 + 0.102 * t)) * shade;
		lit = floor(raw * 32.0 + 0.5) / 32.0;
	}
	vec3 colour = clamp(floor(base * lit * tone.rgb), 0.0, 255.0);
	// A highlight where the key light glances off toward the eye.
	float glint = dot(reflect(-normalize(KEY), n), to_eye);
	if (glint > 0.93) {
		colour = min(colour + vec3(150.0) * gloss * tone.a, vec3(255.0));
	}
	if (effects_on) {
		colour = surface_light(colour, map_p, t, n, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
