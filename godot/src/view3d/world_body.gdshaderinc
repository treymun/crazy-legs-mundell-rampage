// The body of world.gdshader and world_glass.gdshader (GLASS: see-through).
// The level's walls, floors and roofs (level_mesh.gd) as the old renderer
// drew them, then the old view shader's touches with LIGHTS AND GLOW: water that
// sways and mirrors the sky, puddles on wet ground, relief, the lights, grade
// and fog. The Crossroads' runoff and the water tower's shadow.
#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2DArray tiles : filter_nearest, repeat_disable;
uniform float flash = 0.0;
// True in the moments the liquor tube dips (render_surfaces.gd flicker).
uniform bool liquor_flicker = false;
uniform int flow_tile[2];
uniform int flow_shift[2];
// The reflection the mirror shows (world_view.gd's mirror camera's picture).
uniform sampler2D mirror_tex : filter_nearest, repeat_disable;

const int KIND_GLOW = 1;
const int KIND_FLICKER = 2;
const int KIND_SHADOW = 3;
const int KIND_MESH = 4;
const int KIND_MIRROR = 6;
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

// How a tile's relief slopes at texel (pu, pv): darker texels raised (the
// mortar between bricks), scaled by the tile's relief depth.
vec2 relief_at(int tile, int pu, int pv, vec3 here) {
	float h = luma(here);
	float left = luma(texelFetch(tiles, ivec3((pu + 127) & 127, pv, tile), 0).rgb);
	float up = luma(texelFetch(tiles, ivec3(pu, (pv + 127) & 127, tile), 0).rgb);
	return vec2(h - left, h - up);
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	int tile = int(c1.x + 0.5);
	int plain = int(c1.y + 0.5);
	float along = c1.z;
	int packed = int(c1.w + 0.5);
	int mode = packed & 3;
	int kind = packed >> 2;
	float t = -VERTEX.z;
	vec3 tint = c0.rgb;
	float tm = anim_time * motion;
	int column = int(FRAGCOORD.x);
	float sy = floor(FRAGCOORD.y) + 0.5 - horizon;
	vec3 tu;
	vec3 tv;
	int pu;
	int pv;
	float lit;
	bool floor_ = kind >= KIND_FLOOR;
	bool overhead = kind == KIND_ROOF;
	vec4 info = vec4(0.0);
	if (floor_) {
		pu = int(map_p.x * 128.0) & 127;
		pv = int(map_p.y * 128.0) & 127;
		for (int k = 0; k < 2; k++) {
			if (tile == flow_tile[k]) {
				pv = (pv + flow_shift[k]) & 127;
			}
		}
		if (effects_on && !overhead) {
			info = tile_info(tile);
			if (info.r > 0.0) {
				// Water sways its texels a little, in chunky steps.
				vec2 q = floor(map_p.xy * 16.0) / 16.0;
				pu = (pu + int(floor(sin(q.y * 6.3 + tm * 1.7 + sin(q.x * 2.3)) * 2.0 + 0.5))) & 127;
				pv = (pv + int(floor(sin(q.x * 5.1 - tm * 1.3) * 1.5 + 0.5))) & 127;
			}
		}
		float raw = (c0.a * (overhead ? 0.77 : 0.94) + flash) / (1.0 + 0.102 * t);
		lit = float(min(int(max(raw, 0.19) * 32.0 + 0.5), 96)) / 32.0;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 1.0, 0.0);
	} else {
		// Seen from its normal's side a wall's u runs back (tex_u = 1 - u), so
		// its picture always reads left to right.
		vec3 cam = vec3(CAMERA_POSITION_WORLD.x, CAMERA_POSITION_WORLD.z, CAMERA_POSITION_WORLD.y);
		bool facing = dot(map_n.xy, cam.xy - map_p.xy) > 0.0;
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
	if (kind == KIND_MIRROR && mirror_on) {
		// The reflection, flipped (its camera saw the room unmirrored), tinted
		// and flecked as the old renderer composited it.
		ivec2 at = ivec2(int(view_size.x) - 1 - int(FRAGCOORD.x), int(FRAGCOORD.y));
		vec3 r = floor(texelFetch(mirror_tex, at, 0).rgb * 255.0 + 0.5);
		vec3 m = floor(r * vec3(0.81, 0.86, 0.84) + vec3(7.0, 8.0, 6.0));
		if ((at.x + int(FRAGCOORD.y) * 2) % 61 == 0) {
			m = floor(m * 0.88) + vec3(14.0, 13.0, 11.0);
		}
		ALBEDO = to_output(m);
#ifdef GLASS
		ALPHA = 0.45;
#endif
	} else {
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
	float glow = effects_on ? 1.0 - fetched.a : 0.0;
	lit = max(lit, glow);
	if (effects_on && anim_count > 0) {
		lit *= anim_light(tile);
	}
	if (hub_fx && floor_ && !overhead) {
		if (tile == hub_runoff) {
			texel = running_water(texel, map_p.x, map_p.y);
		} else if (tile == hub_patch || tile == hub_wall) {
			lit *= tower_shadow(map_p.x, map_p.y, map_p.z);
		}
	}
	vec3 colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
	if (hub_fx && kind == KIND_SHADOW) {
		colour = floor(colour * tower_shadow(map_p.x, map_p.y, map_p.z));
	}
	if (effects_on) {
		float gloss = 0.0;
		vec2 bump = vec2(0.0);
		bool done = false;
		if (floor_ && !overhead) {
			bool open = open_sky(map_p.xy);
			if (info.r > 0.0) {
				colour = water_over(colour, map_p.xy, t, sy, column, info.r, lit, tm);
				gloss = info.r;
			} else if (open && wet > 0.0) {
				// Wet ground darkens; where it lies low it holds a puddle.
				vec2 q = floor(map_p.xy * 10.0) / 10.0;
				float low = 0.5 + 0.25 * sin(q.x * 1.7 + sin(q.y * 1.3) * 1.8) + 0.25 * sin(q.y * 2.3 + sin(q.x * 0.9) * 2.1);
				if (info.b > 0.0 && low > 1.0 - wet * info.b * 0.34) {
					colour = water_over(colour * 0.5, map_p.xy, t, sy, column, 0.85, lit, tm);
					gloss = 1.0;
					done = true;
				} else {
					colour = floor(colour * (1.0 - 0.17 * wet));
					gloss = 0.4 * wet;
				}
			}
		}
		if (!done && t < RELIEF_FAR) {
			float deep = tile_info(tile).g;
			if (abs(deep) > 0.01) {
				bump = relief_at(tile, pu, pv, fetched.rgb) * deep * 3.0 * (1.0 - glow);
			}
		}
		vec3 nf = map_n;
		if (!floor_ && dot(nf.xy, eye.xy - map_p.xy) < 0.0) {
			nf = -nf;
		}
		colour = surface_light(colour, map_p, t, nf, tu, tv, bump, gloss, floor_ ? 0 : 1);
	}
	ALBEDO = to_output(colour);
#ifdef GLASS
	ALPHA = 0.45;
#endif
	}
}
