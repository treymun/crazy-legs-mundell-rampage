// The body of sprite.gdshader and sprite_clear.gdshader (CLEAR: blended).
#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2DArray art : filter_nearest, repeat_disable;

const int FLIP = 1;
const int GLOW = 4;
const int BODY = 8;
const int BOARD = 16;

varying flat vec4 data;
varying flat vec4 tone;
varying vec3 map_p;
// A board seen from behind is not drawn (the old renderer's test: its
// back, where it has one, is a board of its own facing the other way).
varying flat float behind;

void vertex() {
	data = INSTANCE_CUSTOM;
	tone = COLOR;
	vec3 w;
	behind = 0.0;
	if ((int(data.w + 0.5) & BOARD) != 0) {
		w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		// Map (x, y) is Godot (x, z); the board's axis is (cos p, sin p).
		vec2 axis = normalize(MODEL_MATRIX[0].xz);
		vec2 to_board = MODEL_MATRIX[3].xz - INV_VIEW_MATRIX[3].xz;
		if (to_board.x * axis.y - to_board.y * axis.x <= 0.02) {
			behind = 1.0;
		}
	} else {
		// A billboard stands parallel to the plane of whichever camera draws it
		// (the eye's, or the mirror's), as the old renderer's sprites did.
		vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
		float width = length(MODEL_MATRIX[0].xyz);
		float height = length(MODEL_MATRIX[1].xyz);
		w = MODEL_MATRIX[3].xyz + right * (VERTEX.x * width) + vec3(0.0, VERTEX.y * height, 0.0);
	}
	map_p = vec3(w.x, w.z, w.y);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (behind > 0.5 || mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	int flags = int(data.w + 0.5) & 255;
	float hurt = floor((data.w + 0.5) / 256.0) / 100.0;
	vec2 uv = UV;
	if ((flags & FLIP) != 0) {
		uv.x = 1.0 - uv.x;
	}
	ivec2 size = ivec2(data.yz);
	ivec2 at = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
	vec4 texel = texelFetch(art, ivec3(at, int(data.x + 0.5)), 0);
	float a = texel.a * 255.0;
#ifdef CLEAR
	if (a <= 12.0) {
#else
	if (a <= 100.0) {
#endif
		discard;
	}
	float t = -VERTEX.z;
	float lit;
	if ((flags & GLOW) != 0) {
		lit = 1.1;
	} else {
		float raw = max(0.19, tone.a / (1.0 + 0.102 * t));
		if ((flags & BODY) != 0) {
			raw = max(raw, 0.58 - 0.021 * t);
		}
		lit = floor(raw * 32.0 + 0.5) / 32.0;
	}
	vec3 colour = clamp(floor(floor(texel.rgb * 255.0 + 0.5) * lit * tone.rgb), 0.0, 255.0);
	if (hurt > 0.0) {
		colour = floor(colour * (1.0 - hurt) + vec3(255.0, 232.0, 208.0) * hurt);
	}
	if (effects_on) {
		vec3 nf = normalize(eye - map_p);
		nf.z = 0.0;
		colour = surface_light(colour, map_p, t, normalize(nf + vec3(1e-5)), vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
#ifdef CLEAR
	ALPHA = texel.a;
#endif
}
