// The body of sprite.gdshader and sprite_clear.gdshader (CLEAR: blended), and
// of pickup.gdshader (MESH: a pickup's slab, pickup_layer.gd, placed by its
// own transform, each face shaded by which way it looks).
#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2DArray art : filter_nearest, repeat_disable;

const int FLIP = 1;
const int GLOW = 4;
const int BODY = 8;
const int BOARD = 16;
// The flags' word: flags + 256 x hurt (0..100) + SPIN_ONE x the turn (0..SPINS-1).
const int SPIN_ONE = 65536;
const int SPINS = 32;

varying flat vec4 data;
varying flat vec4 tone;
varying vec3 map_p;
// A board seen from behind is not drawn (the old renderer's test: its
// back, where it has one, is a board of its own facing the other way).
varying flat float behind;
#ifdef MESH
varying vec3 map_n;
// Fronts and backs at full light; the side walls darker, as a 1997 voxel's.
varying flat float face;
#endif

void vertex() {
	data = INSTANCE_CUSTOM;
	tone = COLOR;
	vec3 w;
	behind = 0.0;
#ifdef MESH
	w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(wn.x, wn.z, wn.y);
	vec3 an = abs(NORMAL);
	face = an.z > 0.5 ? 1.0 : (an.x > 0.5 ? 0.78 : (NORMAL.y > 0.0 ? 0.9 : 0.62));
#else
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
		int spin = int(data.w + 0.5) / SPIN_ONE;
		if (spin == 0) {
			w = MODEL_MATRIX[3].xyz + right * (VERTEX.x * width) + vec3(0.0, VERTEX.y * height, 0.0);
		} else {
			// A chunk turning over in the view's plane, in SPINS steps, about
			// its middle, lifted so no corner dips under the floor it stands on.
			float a = float(spin) * TAU / float(SPINS);
			float c = cos(a);
			float s = sin(a);
			vec2 p = vec2(VERTEX.x * width, (VERTEX.y - 0.5) * height);
			vec2 r = vec2(p.x * c - p.y * s, p.x * s + p.y * c);
			float lift = 0.5 * (abs(width * s) + abs(height * c));
			w = MODEL_MATRIX[3].xyz + right * r.x + vec3(0.0, lift + r.y, 0.0);
		}
	}
#endif
	map_p = vec3(w.x, w.z, w.y);
	VERTEX = (VIEW_MATRIX * vec4(w, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	if (behind > 0.5 || mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	int flags = int(data.w + 0.5) & 255;
	float hurt = float((int(data.w + 0.5) / 256) & 255) / 100.0;
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
#ifdef MESH
		raw *= face;
#endif
		lit = floor(raw * 32.0 + 0.5) / 32.0;
	}
#ifdef MESH
	if ((flags & GLOW) != 0) {
		lit *= face;
	}
#endif
	vec3 colour = clamp(floor(floor(texel.rgb * 255.0 + 0.5) * lit * tone.rgb), 0.0, 255.0);
	if (hurt > 0.0) {
		colour = floor(colour * (1.0 - hurt) + vec3(255.0, 232.0, 208.0) * hurt);
	}
	if (effects_on) {
#ifdef MESH
		vec3 nf = dot(map_n, eye - map_p) < 0.0 ? -map_n : map_n;
#else
		vec3 nf = normalize(eye - map_p);
		nf.z = 0.0;
		nf = normalize(nf + vec3(1e-5));
#endif
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
#ifdef CLEAR
	ALPHA = texel.a;
#endif
}
