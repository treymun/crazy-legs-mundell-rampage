// The body of world.gdshader and world_glass.gdshader (GLASS: see-through).
// The level's walls, floors and roofs (level_mesh.gd) as the old renderer
// drew them, then the old view shader's touches with LIGHTS AND GLOW: water that
// sways and mirrors the sky, puddles on wet ground, relief, the lights, grade
// and fog. The Crossroads' runoff and the water tower's shadow.
#include "res://src/view3d/view_light.gdshaderinc"

// The tiles with their mip levels (view_tiles.gd): read with texelFetch at
// the level tile_lod picks, so the sampler's filter is never used.
global uniform sampler2DArray tiles;
global uniform float flash;
// True in the moments the liquor tube dips (render_surfaces.gd flicker).
global uniform bool liquor_flicker;
// The reflection the mirror shows (world_view.gd's mirror camera's picture).
global uniform sampler2D mirror_tex;

const int KIND_GLOW = 1;
const int KIND_FLICKER = 2;
const int KIND_SHADOW = 3;
const int KIND_MESH = 4;
const int KIND_MIRROR = 6;
const int KIND_PLANKS = 7;
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

// Plank j's stretch knocked out [lo, hi) in sixteenths (lo >= hi: none),
// from a cell's three words (features/wall_looks.gd Planks.words).
vec2 plank_band(vec4 words, int j) {
	float word = j < 3 ? words.x : (j < 6 ? words.y : words.z);
	int b = (int(word + 0.5) >> ((j - (j / 3) * 3) * 8)) & 255;
	return vec2(float(b & 15), float((b >> 4) + 1));
}

// How far a broken plank's end stands into its gap at texel column x (in
// sixteenths of the cell's height): teeth a few texels apart, each its own
// height, by the plank (seed).
float plank_teeth(float x, float seed) {
	float period = 4.0 + floor(hash12(vec2(seed, 1.7)) * 4.0);
	float shift = x + hash12(vec2(seed, 9.1)) * period;
	float tri = abs(fract(shift / period) * 2.0 - 1.0);
	return tri * (0.35 + 1.1 * hash12(vec2(seed, floor(shift / period))));
}

// A plank wall shot about (KIND_PLANKS; features/wall_looks.gd hands the
// view the cells nearest the eye, view_rows): -2 not one of them (drawn as
// its tile), -1 knocked out here (what is behind shows), 0 drawn as its
// whole tile, 1 a splintered end (pale), 2 a plank's side beside a gap
// (shadowed). Each plank is an eighth of the cell along the fence, its
// knocked-out stretch in sixteenths of the cell's height, its ends broken
// jagged by the texel column. Only on the faces along the fence, on a cell's
// edge (an end of the run or a gap's side keeps its boards); the stockyard's
// posts and rails stay (posts).
int plank_damage(vec3 p, vec3 n, int pv, bool posts) {
	if (view_row(ROW_PLANK0, 0).x < 0.0) {
		return -2;
	}
	bool face_x = abs(n.y) > 0.5;
	float across = face_x ? p.y : p.x;
	if (abs(across - floor(across + 0.5)) > 0.01) {
		return -2;
	}
	vec2 ca = floor(p.xy + n.xy * 0.02);
	vec2 cb = floor(p.xy - n.xy * 0.02);
	int found = -1;
	vec4 e = vec4(0.0);
	for (int i = 0; i < 32; i++) {
		e = view_row(i < 16 ? ROW_PLANK0 : ROW_PLANK2, i & 15);
		if (e.x < 0.0) {
			break;
		}
		if (e.xy == ca || e.xy == cb) {
			found = i;
			break;
		}
	}
	if (found < 0 || (e.w > 0.0) != face_x) {
		return -2;
	}
	vec4 words = view_row(found < 16 ? ROW_PLANK1 : ROW_PLANK3, found & 15);
	float span = abs(e.w);
	int xi = clamp(int(floor(((face_x ? p.x : p.y) - (face_x ? e.x : e.y)) * 128.0)), 0, 127);
	int j = xi >> 4;
	float h = (p.z - e.z) / span * 16.0;
	if (posts && (xi < 5 || xi > 122 || (pv >= 21 && pv <= 32) || (pv >= 57 && pv <= 68) || (pv >= 99 && pv <= 110))) {
		return 0;
	}
	vec2 band = plank_band(words, j);
	float row = 16.0 / span / 100.0;
	if (band.y > band.x) {
		// The ends broken in teeth (plank_teeth) pointing into the gap; a
		// tooth's top and its sides where it stands past the one beside it
		// pale (raw wood), so each break reads as one splintered line.
		float seed = e.x * 7.13 + e.y * 3.71 + float(j) * 1.37;
		float x = float(xi);
		float lo = band.x <= 0.0 ? -1.0 : band.x + plank_teeth(x, seed);
		float hi = band.y >= 16.0 ? 16.0 : band.y - plank_teeth(x, seed + 31.7);
		if (h > lo && h < hi) {
			return -1;
		}
		float edge = 2.2 * row;
		if (band.x > 0.0 && h <= lo) {
			float side = min(band.x + plank_teeth(x - 1.0, seed), band.x + plank_teeth(x + 1.0, seed));
			if (h > lo - edge || h > side) {
				return 1;
			}
		}
		if (band.y < 16.0 && h >= hi) {
			float side = max(band.y - plank_teeth(x - 1.0, seed + 31.7), band.y - plank_teeth(x + 1.0, seed + 31.7));
			if (h < hi + edge || h < side) {
				return 1;
			}
		}
	}
	int in_plank = xi & 15;
	if (in_plank <= 1 && j > 0) {
		vec2 left = plank_band(words, j - 1);
		if (left.y > left.x && h > left.x + 0.5 && h < left.y - 0.5) {
			return 2;
		}
	}
	if (in_plank >= 14 && j < 7) {
		vec2 right = plank_band(words, j + 1);
		if (right.y > right.x && h > right.x + 0.5 && h < right.y - 0.5) {
			return 2;
		}
	}
	return 0;
}

// The tile's mip level for a texel footprint (texels a view pixel, from the
// screen derivatives of the texel coordinates): 0 up close, one level more
// each time a pixel spans twice the texels, as Quake's software renderer
// stepped down its mips. The larger of the two axes, so a road seen low
// settles too.
int tile_lod(vec2 dx, vec2 dy) {
	float rho = max(length(dx), length(dy));
	return clamp(int(floor(log2(max(rho, 1.0)))), 0, 7);
}

// How a tile's relief slopes at texel (pu, pv): darker texels raised (the
// mortar between bricks), scaled by the tile's relief depth.
vec2 relief_at(int tile, int pu, int pv, vec3 here) {
	float h = luma(here);
	float left = luma(texelFetch(tiles, ivec3((pu + 127) & 127, pv, tile), 0).rgb);
	float up = luma(texelFetch(tiles, ivec3(pu, (pv + 127) & 127, tile), 0).rgb);
	return vec2(h - left, h - up);
}

// County Run's storm front where it meets the ground (storm_ring): the
// ground soaked dark from a few cells inside the wall on out under it, and a
// ragged line of churned dirt clods where the wall stands, in 1/12-cell
// blocks.
vec3 storm_ground(vec3 colour, float lit, inout float gloss) {
	vec2 rel = map_p.xy - storm_ring.xy;
	float edge = length(rel) - storm_ring.z;
	if (edge < -4.5) {
		return colour;
	}
	float soak = smoothstep(-4.0, 0.6, edge);
	colour = floor(colour * (1.0 - 0.34 * soak));
	gloss = max(gloss, 0.55 * soak);
	vec2 q = floor(map_p.xy * 12.0);
	float turn = atan(rel.y, rel.x);
	float rag = 0.22 * sin(turn * floor(storm_ring.z * 1.3)) + 0.14 * sin(turn * floor(storm_ring.z * 3.7) + 1.1);
	float band = edge - rag - (hash12(q) - 0.5) * 0.3;
	if (band > -0.45 && band < 0.4) {
		float h = hash12(q + 17.3);
		vec3 dirt = h > 0.78 ? vec3(78.0, 62.0, 44.0) : (h < 0.3 ? vec3(28.0, 21.0, 15.0) : vec3(50.0, 38.0, 27.0));
		float cover = (band < -0.3 || band > 0.28) ? 0.5 : 0.85;
		colour = floor(mix(colour, dirt * lit, cover));
		gloss = min(gloss, 0.2);
	}
	return colour;
}

void fragment() {
	// The texel footprints, worked out before anything branches.
	vec2 floor_uv = map_p.xy * 128.0;
	vec2 floor_dx = dFdx(floor_uv);
	vec2 floor_dy = dFdy(floor_uv);
	vec2 wall_dx = dFdx(tex);
	vec2 wall_dy = dFdy(tex);
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
	int planks = -2;
	if (floor_) {
		pu = int(map_p.x * 128.0) & 127;
		pv = int(map_p.y * 128.0) & 127;
		vec4 flow = view_row(ROW_FLOW, 0);
		if (tile == int(flow.x)) {
			pv = (pv + int(flow.z)) & 127;
		}
		if (tile == int(flow.y)) {
			pv = (pv + int(flow.w)) & 127;
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
		if (kind == KIND_PLANKS) {
			// Its whole tile, less than 0 (-1 - it) for the stockyard's.
			bool posts = c1.y < -0.5;
			int whole = posts ? int(-c1.y + 0.5) - 1 : int(c1.y + 0.5);
			planks = plank_damage(map_p, map_n, pv, posts);
			if (planks == -1) {
				discard;
			}
			if (planks >= 0) {
				tile = whole;
			}
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
	int lod = floor_ ? tile_lod(floor_dx, floor_dy) : tile_lod(wall_dx, wall_dy);
	vec4 fetched = texelFetch(tiles, ivec3(pu >> lod, pv >> lod, tile), lod);
	vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
	if (planks == 1) {
		// A plank's broken end: pale raw wood, the splinters catching light.
		texel = floor(vec3(206.0, 176.0, 130.0) * (0.82 + 0.3 * hash12(vec2(float(pu), float(pv)))));
	} else if (planks == 2) {
		texel = floor(texel * 0.55);
	}
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
	float glow = effects_on ? (1.0 - fetched.a) * (1.0 - blackout) : 0.0;
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
				// A long storm's water spreads them: more, bigger puddles, even
				// on ground that holds little (grass).
				float gather = max(info.b, 0.5 * pool);
				if (info.b > 0.0 && low > 1.0 - wet * gather * (0.34 + 0.36 * pool)) {
					colour = water_over(colour * 0.5, map_p.xy, t, sy, column, 0.85, lit, tm);
					gloss = 1.0;
					done = true;
				} else {
					colour = floor(colour * (1.0 - 0.17 * wet));
					gloss = 0.4 * wet;
				}
			}
			if (storm_ring.w > 0.0 && open && info.r <= 0.0) {
				colour = storm_ground(colour, lit, gloss);
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
