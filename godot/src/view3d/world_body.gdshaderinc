// The body of world.gdshader and world_glass.gdshader (GLASS: see-through).
#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2DArray tiles : filter_nearest, repeat_disable;
uniform float flash = 0.0;
// True in the moments the liquor tube dips (render_surfaces.gd flicker).
uniform bool liquor_flicker = false;
uniform int flow_tile[2];
uniform int flow_shift[2];

const int KIND_GLOW = 1;
const int KIND_FLICKER = 2;
const int KIND_MESH = 4;
const int KIND_GLAZING = 5;
const int KIND_FLOOR = 8;
const int KIND_ROOF = 9;

varying vec3 map_p;
varying vec3 map_n;
varying vec2 tex;
varying flat vec4 c0;
varying flat vec4 c1;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	map_n = vec3(NORMAL.x, NORMAL.z, NORMAL.y);
	tex = UV;
	c0 = CUSTOM0;
	c1 = CUSTOM1;
}

bool mesh_hole(int pu, int pv) {
	return pu >= 7 && pu <= 120 && pv >= 7 && pv <= 119
		&& !((pu >= 48 && pu <= 54) || (pv >= 67 && pv <= 73))
		&& !(pv > 95 && pu < 42 + pv / 5)
		&& (pu + pv) % 17 >= 2
		&& (pu - pv + 144) % 18 >= 2;
}

void fragment() {
	int tile = int(c1.x + 0.5);
	int plain = int(c1.y + 0.5);
	float along = c1.z;
	int packed = int(c1.w + 0.5);
	int mode = packed & 3;
	int kind = packed >> 2;
	float t = -VERTEX.z;
	vec3 tint = c0.rgb;
	vec3 tu;
	vec3 tv;
	int pu;
	int pv;
	float lit;
	if (kind >= KIND_FLOOR) {
		pu = int(map_p.x * 128.0) & 127;
		pv = int(map_p.y * 128.0) & 127;
		for (int k = 0; k < 2; k++) {
			if (tile == flow_tile[k]) {
				pv = (pv + flow_shift[k]) & 127;
			}
		}
		float scale = kind == KIND_ROOF ? 0.77 : 0.94;
		float raw = (c0.a * scale + flash) / (1.0 + 0.102 * t);
		lit = float(min(int(max(raw, 0.19) * 32.0 + 0.5), 96)) / 32.0;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 1.0, 0.0);
	} else {
		// Seen from its normal's side a wall's u runs back (tex_u = 1 - u), so
		// its picture always reads left to right.
		bool facing = dot(map_n.xy, eye.xy - map_p.xy) > 0.0;
		float u = facing ? along - tex.x : tex.x;
		if (mode == 0) {
			pu = clamp(int(u), 0, 127);
			pv = clamp(int(tex.y), 0, 127);
		} else {
			pu = int(u) & 127;
			pv = int(tex.y) & 127;
			if (mode == 2 && (map_p.z < 1.0 || map_p.z > 1.68)) {
				tile = plain;
			}
		}
		if (kind == KIND_MESH && mesh_hole(pu, pv)) {
			discard;
		}
		lit = stepped_light(c0.a + flash, t);
		tu = normalize(vec3(-map_n.y, map_n.x, 0.0)) * (facing ? -1.0 : 1.0);
		tv = vec3(0.0, 0.0, -1.0);
	}
	vec4 fetched = texelFetch(tiles, ivec3(pu, pv, tile), 0);
	vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
	if (kind == KIND_GLOW || kind == KIND_FLICKER) {
		bool dips = kind == KIND_FLICKER && liquor_flicker;
		if (texel.r > 156.0 || texel.g > 156.0 || texel.b > 156.0) {
			int step = int(lit * 32.0 + 0.5);
			if (step < 29) {
				lit = dips ? 0.9 * 0.73 : 0.9;
			} else if (dips) {
				lit = lit * 0.73;
			}
		}
	}
	if (effects_on) {
		lit = max(lit, 1.0 - fetched.a);
		if (anim_count > 0) {
			lit *= anim_light(tile);
		}
	}
	vec3 colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
	if (effects_on) {
		vec3 nf = map_n;
		if (kind < KIND_FLOOR && dot(nf.xy, eye.xy - map_p.xy) < 0.0) {
			nf = -nf;
		}
		float gloss = 0.0;
		if (kind >= KIND_FLOOR) {
			gloss = tile_info(tile).r;
		}
		colour = surface_light(colour, map_p, t, nf, tu, tv, vec2(0.0), gloss, kind >= KIND_FLOOR ? 0 : 1);
	}
	ALBEDO = to_output(colour);
#ifdef GLASS
	ALPHA = 0.45;
#endif
}
