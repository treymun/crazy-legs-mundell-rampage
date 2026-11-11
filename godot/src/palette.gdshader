shader_type canvas_item;
render_mode unshaded;

// Convert the composed 320x200 RGB frame to the project's VGA-style 256-color
// grade, exactly like period_palette.VGAPalette.apply (RGB555 -> palette LUT).
// The palette table (rows 0-127, 256 wide), the grain frames (rows 128-447)
// and the brightness table (row 448), in one texture. Godot keeps several of a
// WebGL page's 16 texture units for itself, so this shader samples at most
// nine textures (godot/tools/check_shader.gd keeps count); it uses seven, the
// per-level and per-frame number tables all riding in `spans`.
uniform sampler2D looks : filter_nearest, repeat_disable;
const int GRAIN_ROW = 128;
const int TONE_ROW = 448;

// The game view's look pass (game.gd _look_rows), done here when there is a
// window: level wash and vignette, film grain, ordered dither, lamp buzz and
// blast lift, then the brightness table. Rows from 156 down are the status bar.
uniform bool look = false;
uniform bool tone_on = false;
uniform vec3 wash = vec3(1.0);
uniform float gain = 1.0;
uniform float blast = 0.0;
uniform int grain_frame = 0;
uniform int hurt = 0;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

// ---------------------------------------------------------------- the view
// With scene_on the software renderer (renderer.gd, `layered`) hands over the
// view in parts instead of a finished picture, and the rest is done here per
// pixel, with the renderer's own formulas: the sky, every floor and ceiling,
// the plain walls (whole spans down each column), the sprites and painted
// boards in list order, the window panes, and last the weapon and HUD layer.
// What the renderer still draws itself (the mirror, window glazing, wall
// marks, ground marks, and walls past SPAN_K in a column) arrives as pixels.
uniform bool scene_on = false;
const int SPAN_K = 12;
// With overlay_on the weapon, HUD and menus come from a Godot 2D viewport
// (canvas.gd, gpu): post_tex is that viewport, premultiplied, its alpha the
// coverage, and under it goes the view (scene_on), the software frame in
// TEXTURE (base_on: FAST VIEW off) or black.
uniform bool overlay_on = false;
uniform bool base_on = false;
// The canvas (weapon, HUD) and how much of each of its pixels is painted.
uniform sampler2D post_tex : filter_nearest, repeat_disable;
// Walls. wall_code says, four bytes low to high, which texel of which tile a
// wall pixel shows (21 bits: tile * 16384 + row * 128 + column) and which
// shade row lights it (11 bits: tint * 99 + light step); all ones in the shade
// row means the pixel's finished colour is in `colours` instead (glowing signs,
// the mirror, wall marks). wall_dist is the distance of what the renderer drew.
// The renderer's per-frame parts, stacked a view's height apart, as plain
// bytes so a frame is only copied, never converted. colours (RGB, a view wide):
// walls, sprites/ground marks (premultiplied), window panes, then a stream of
// bytes read three to a texel: the wall codes (four bytes a pixel), then the
// sprite/ground mark coverage (one byte a pixel). The distances (walls,
// sprites/ground marks, window panes) are a float stream in `spans`, four to a
// texel, from row dist_row (dist_at()).
uniform sampler2D colours : filter_nearest, repeat_disable;
// Plain walls as whole spans, up to two texels each down a column, and how
// many spans each column has (renderer: render_state.gd SPAN_K).
// The wall spans (two rows a span), then a row of each column's span count,
// then the sprite table: sprite i's texel k is texel i * 4 + k counted on
// across the rows, from row SPAN_K * 2 + 1. Then the distances from dist_row,
// and the level's plane table from plane_row (plane()).
uniform sampler2D spans : filter_nearest, repeat_disable;
uniform int dist_row = 0;
uniform int plane_row = 0;
uniform int plane_w = 1;
// Sprites and painted boards, drawn here in list order (render_state.gd
// GPU_SPRITES): four texels a sprite in `spans`, the pictures in a texture array.
uniform int sprite_count = 0;
uniform sampler2DArray sprite_art : filter_nearest, repeat_disable;
// Sprites and ground marks: premultiplied colour, coverage, distance
// (above zero a sprite, below zero a ground mark lying on a floor).
// Window panes held back from the walls, washed over what is behind them.
uniform bool pane_on = false;
// The level: 128x128 tiles sixteen to a row, the sky strip, and per map cell
// the floor height index, roof height index, floor tile, ceiling tile; the
// tint index; the light.
// The tiles sixteen to a row, the level's sky strip under them from row
// sky_row, and from row cells_row the cells, then each cell's tint index a
// map's height further down.
uniform sampler2D tiles_tex : filter_nearest, repeat_disable;
uniform int sky_row = 1024;
uniform int cells_row = 1140;
// The plane table, plane_w texels a row (plane()): row 0 floor heights nearest
// first (height, first cap, cap count), row 1 roof heights, row 2 cap
// rectangles, row 3 cap tiles, row 4 tints, and from row 5 each cell's light.
uniform ivec2 map_size = ivec2(1);
uniform int floor_count = 0;
uniform int roof_count = 0;
uniform int tint_count = 1;
// The camera, as the renderer used it.
uniform vec3 eye = vec3(0.0);
uniform vec2 fwd = vec2(1.0, 0.0);
uniform vec2 side = vec2(0.0, 1.0);
uniform float view_angle = 0.0;
uniform float horizon = 78.0;
uniform float focal = 230.0;
uniform ivec2 view_size = ivec2(320, 156);
uniform int view_div = 1;
uniform float res_up = 1.0;
uniform float flash_light = 0.0;
// Tiles that scroll (creek, mill race) and how far along they are.
uniform int flow_tile[2];
uniform int flow_shift[2];
// County Crossroads: the culvert runoff and the water tower's shadow.
uniform bool hub_fx = false;
uniform int hub_runoff = -1;
uniform int hub_patch = -1;
uniform int hub_wall = -1;
uniform bool shadow_still = false;
uniform float shadow_gust = 0.0;
uniform float shadow_lx = 1.15;
uniform float shadow_ly = 0.73;
uniform float water_drift = 0.0;
// Moonshine: strength, the shear's phase and the ghost image's offset.
uniform float drunk = 0.0;
uniform float drunk_phase = 0.0;
uniform int drunk_ghost = 0;
// Lights and glows (data/tuning/effects.cfg, effects.gd): with effects_on a
// tile texel whose alpha is under one lights itself to at least 1 - alpha
// (scene_layers.gd bakes that in), and up to sixteen lights add their colour
// to whatever surface is nearest along each pixel's ray. The software view
// has neither; with effects_on false the two views agree.
uniform bool effects_on = false;
uniform int light_count = 0;
uniform vec4 light_pos[16];
uniform vec4 light_col[16];
// A level's mood (effects.cfg [level.<id>]): the distance fades to fog_color
// from fog_range.x to fog_range.y cells, at most fog_range.z of the way; every
// surface is tinted by grade; the upper sky drifts sky_drift of a turn; and a
// lightning flash (0 to 1) lights the sky and the yard.
uniform vec3 fog_color = vec3(0.0);
uniform vec3 fog_range = vec3(1000.0, 2000.0, 0.0);
uniform vec3 grade = vec3(1.0);
uniform float sky_drift = 0.0;
uniform float lightning = 0.0;
// Tiles that move (effects.cfg [anim.<tile>]): (tile, mode, rate, depth);
// mode 0 a neon tube's buzz and drop-outs, 1 a slow pulse.
uniform int anim_count = 0;
uniform vec4 anims[8];
uniform float anim_time = 0.0;

int byte_of(float v) {
	return int(v * 255.0 + 0.5);
}

// The light a tile texel gives itself (its alpha, see effects_on), or none.
float glow_of(vec4 texel) {
	return effects_on ? 1.0 - texel.a : 0.0;
}

// How lit a moving tile is this moment (1 for a tile that does not move).
float anim_light(int tile) {
	for (int i = 0; i < anim_count; i++) {
		vec4 a = anims[i];
		if (int(a.x + 0.5) != tile) {
			continue;
		}
		if (a.y < 0.5) {
			float beat = floor(anim_time * a.z);
			float roll = fract(sin(beat * 12.9898 + a.x * 78.233) * 43758.5453);
			return roll < a.w ? 0.32 : 1.0 - 0.07 * fract(anim_time * a.z * 7.3);
		}
		return 1.0 - a.w * (0.5 + 0.5 * sin(anim_time * a.z * 6.2831853));
	}
	return 1.0;
}

// A sprite texel that lights itself in the dark: the green of alien glass,
// eyes and plasma, and lamp yellow.
bool self_lit(vec3 c) {
	return (c.g >= 170.0 && c.g > c.r * 1.3 && c.g > c.b * 1.1) || (c.r >= 230.0 && c.g >= 200.0 && c.b <= 150.0);
}

// What this frame's lights add at a point: a fraction per channel.
vec3 lights_at(vec3 p) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 at = light_pos[i];
		float reach = clamp(1.0 - distance(p, at.xyz) / at.w, 0.0, 1.0);
		sum += light_col[i].rgb * light_col[i].a * reach * reach;
	}
	return sum;
}

// Texel c of the plane table, flowing on across the rows of `spans`.
vec4 plane(ivec2 c) {
	int at = c.y * plane_w + c.x;
	return texelFetch(spans, ivec2(at % view_size.x, plane_row + at / view_size.x), 0);
}

// The distance band b (0 walls, 1 sprites and ground marks, 2 window panes)
// holds at this view pixel.
float dist_at(ivec2 lp, int b) {
	int i = (b * view_size.y + lp.y) * view_size.x + lp.x;
	int t = i / 4;
	vec4 v = texelFetch(spans, ivec2(t % view_size.x, dist_row + t / view_size.x), 0);
	int k = i - t * 4;
	return k == 0 ? v.r : k == 1 ? v.g : k == 2 ? v.b : v.a;
}

// renderer.gd tower_shadow()
float tower_shadow(float x, float y, float z) {
	if (shadow_still) {
		float ix = floor((x - 17.0) * 16.0 + 0.5);
		float iy = floor((y - 43.0) * 16.0 + 0.5);
		float iz = floor(z * 16.0 + 0.5);
		if (ix < 0.0 || ix > 160.0 || iy < 0.0 || iy > 128.0 || iz < 0.0 || iz > 16.0) {
			return 1.0;
		}
		x = 17.0 + ix / 16.0;
		y = 43.0 + iy / 16.0;
		z = iz / 16.0;
	}
	float lx = shadow_lx;
	float ly = shadow_ly;
	float rxv = x - 19.05;
	float ryv = y - 45.16;
	float lift = 3.83 - z;
	float tank_x = (rxv - lx * lift) / 1.31;
	float tank_y = (ryv - ly * lift) / 0.92;
	float dark = clamp((1.18 - sqrt(tank_x * tank_x + tank_y * tank_y)) * 3.4, 0.0, 1.0);
	float dxv = rxv + lx * z;
	float dyv = ryv + ly * z;
	if (dxv > -0.93 && dxv < 0.93 + 3.55 * lx && dyv > -0.73 && dyv < 0.73 + 3.55 * ly) {
		float vector = lx * lx + ly * ly;
		for (int k = 0; k < 4; k++) {
			vec2 leg = vec2((k == 0 || k == 2) ? -0.72 : 0.72, k < 2 ? -0.52 : 0.52);
			float qx = dxv - leg.x;
			float qy = dyv - leg.y;
			float along = clamp((qx * lx + qy * ly) / vector, 0.0, 3.55);
			float off = abs(qx - along * lx) + abs(qy - along * ly);
			dark = max(dark, clamp((0.21 - off) * 5.0, 0.0, 0.80));
		}
	}
	float fx_ = (rxv - 2.72) / 1.70;
	float fy_ = (ryv - 1.59) / 0.86;
	if (abs(fx_) < 1.1 && abs(fy_) < 1.1) {
		float fringe = clamp((1.1 - sqrt(fx_ * fx_ + fy_ * fy_)) * 1.55, 0.0, 1.0);
		if (fringe > 0.0) {
			float stems = clamp((sin(rxv * 14.3 + ryv * 5.1 + shadow_gust * 8.0) - 0.25) * 1.2, 0.0, 1.0);
			dark = max(dark, fringe * stems * 0.51);
		}
	}
	return 1.0 - 0.36 * dark;
}

// renderer.gd running_water()
vec3 running_water(vec3 rgb, float x, float y) {
	float edge = clamp(min(y - 49.0, 51.0 - y) * 1.9, 0.0, 1.0);
	float wave = sin(13.0 * y + 1.7 * sin(x * 2.1 - water_drift) + 0.8 * sin(x * 4.3 - water_drift * 1.6));
	float streak = sin(x * 6.7 - water_drift * 3.0 + 0.8 * sin(y * 22.0));
	float ripples = clamp((wave + 0.36 * streak - 0.63) * 0.62, 0.0, 0.62) * edge;
	float mix_ = edge * 0.38 + ripples * 0.52;
	vec3 water = vec3(88.0 + ripples * 154.0, 120.0 + ripples * 150.0, 132.0 + ripples * 123.0);
	return floor(rgb * (1.0 - mix_) + water * mix_ + 0.5);
}

// The nearest floor (sy >= 0) or ceiling along this pixel's ray: its distance
// (1e9 when there is none) and its lit colour, 0-255.
float plane_at(vec2 dir, float sy, out vec3 colour) {
	colour = vec3(0.0);
	bool overhead = sy < 0.0;
	float steep = max(0.02, abs(sy));
	int count = overhead ? roof_count : floor_count;
	int row = overhead ? 1 : 0;
	for (int i = 0; i < count; i++) {
		vec4 entry = plane(ivec2(i, row));
		float h = entry.r;
		if (overhead ? h <= eye.z : h >= eye.z) {
			continue;
		}
		float t = min(abs(h - eye.z) * focal / steep, 80.0);
		if (t < 0.015) {
			continue;
		}
		vec2 at = eye.xy + t * dir;
		ivec2 cell = ivec2(at);
		if (cell.x < 0 || cell.y < 0 || cell.x >= map_size.x || cell.y >= map_size.y) {
			continue;
		}
		vec4 here = texelFetch(tiles_tex, cell + ivec2(0, cells_row), 0);
		int tile = 255;
		if (overhead) {
			if (byte_of(here.g) == i) {
				tile = byte_of(here.a);
			}
		} else {
			if (byte_of(here.r) == i) {
				tile = byte_of(here.b);
			}
			int first = int(entry.g + 0.5);
			int last = first + int(entry.b + 0.5);
			for (int k = first; k < last; k++) {
				vec4 box = plane(ivec2(k, 2));
				if (at.x >= box.x && at.x <= box.z && at.y >= box.y && at.y <= box.w) {
					tile = int(floor(plane(ivec2(k, 3)).r + 0.5));
					break;
				}
			}
		}
		if (tile < 0 || tile >= 255) {
			continue;
		}
		int pu = int(at.x * 128.0) & 127;
		int pv = int(at.y * 128.0) & 127;
		for (int f = 0; f < 2; f++) {
			if (tile == flow_tile[f]) {
				pv = (pv + flow_shift[f]) & 127;
			}
		}
		vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
		vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
		float raw = (plane(cell + ivec2(0, 5)).r * (overhead ? 0.77 : 0.94) + flash_light) / (1.0 + 0.102 * t);
		float lit = max(float(min(int(max(raw, 0.19) * 32.0 + 0.5), 96)) / 32.0, glow_of(fetched));
		if (effects_on && anim_count > 0) {
			lit *= anim_light(tile);
		}
		int tint_at = min(byte_of(texelFetch(tiles_tex, cell + ivec2(0, cells_row + map_size.y), 0).r), tint_count - 1);
		vec3 tint = plane(ivec2(tint_at, 4)).rgb;
		if (hub_fx && !overhead) {
			if (tile == hub_runoff) {
				texel = running_water(texel, at.x, at.y);
			} else if (tile == hub_patch || tile == hub_wall) {
				lit *= tower_shadow(at.x, at.y, h);
			}
		}
		colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
		return t;
	}
	return 1e9;
}

// Byte i of the stream after the three colour bands of `colours`.
int stream_byte(int i) {
	int t = i / 3;
	vec3 texel = texelFetch(colours, ivec2(t % view_size.x, view_size.y * 3 + t / view_size.x), 0).rgb;
	int k = i - t * 3;
	return int((k == 0 ? texel.r : k == 1 ? texel.g : texel.b) * 255.0 + 0.5);
}

// A wall pixel's colour (renderer.gd _wall_band and its shade table).
vec3 wall_at(ivec2 lp) {
	int at = (lp.y * view_size.x + lp.x) * 4;
	ivec4 code = ivec4(stream_byte(at), stream_byte(at + 1), stream_byte(at + 2), stream_byte(at + 3));
	int shade_row = (code.b >> 5) | (code.a << 3);
	if (shade_row == 2047) {
		return texelFetch(colours, lp, 0).rgb * 255.0;
	}
	int tile = ((code.b & 31) << 2) | (code.g >> 6);
	int pv = ((code.g & 63) << 1) | (code.r >> 7);
	int pu = code.r & 127;
	vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
	vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
	float lit = max(float(shade_row % 99) / 32.0, glow_of(fetched));
	if (effects_on && anim_count > 0) {
		lit *= anim_light(tile);
	}
	vec3 tint = plane(ivec2(shade_row / 99, 4)).rgb;
	return clamp(floor(texel * lit * tint), 0.0, 255.0);
}

// The light of shade step k: on the 1/32 grid, but for the sign glow (97) and
// the liquor flicker (98) (render_state.gd _build_shade_rows).
float row_light(int k) {
	if (k == 97) {
		return 0.9;
	}
	if (k == 98) {
		return 0.9 * 0.73;
	}
	return float(k) / 32.0;
}

// The road shed's hardware cloth: true where the open mesh shows what is
// behind (render_surfaces.gd _wall_band, hub_screen).
bool span_hole(int pu, int pv) {
	return pu >= 7 && pu <= 120 && pv >= 7 && pv <= 119
		&& !((pu >= 48 && pu <= 54) || (pv >= 67 && pv <= 73))
		&& !(pv > 95 && pu < 42 + pv / 5)
		&& (pu + pv) % 17 >= 2
		&& (pu - pv + 144) % 18 >= 2; // kept positive: % of a negative is undefined in GLSL
}

// A span's colour at height wz (render_surfaces.gd _wall_band): plain walls,
// glowing signs, and the hub walls the water tower shades (at the point hit).
vec3 span_at(int column, int k, float wz, float bottom, float top, vec2 hit) {
	vec4 b = texelFetch(spans, ivec2(column, k * 2 + 1), 0);
	int how = int(b.z + 0.5);
	int kind = how >> 9;
	how = how & 511;
	int mode = how & 3;
	int tile = int(b.x + 0.5);
	int pv;
	if (mode == 0) {
		pv = clamp(int((top - wz) / (top - bottom) * 128.0), 0, 127);
	} else {
		pv = int((1.96 - wz) * 100.0) & 127;
		if (mode == 2 && (wz < 1.0 || wz > 1.68)) {
			tile = int(b.y + 0.5);
		}
	}
	int pu = how >> 2;
	vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
	vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
	int shade_row = int(b.w + 0.5);
	int step = shade_row % 99;
	float lit = row_light(step);
	vec3 tint = plane(ivec2(shade_row / 99, 4)).rgb;
	if (kind == 1 || kind == 2) {
		// A sign's bright texels light at no less than .9, the liquor tube
		// dipping to .73 of that, or of its own light past it.
		if (texel.r > 156.0 || texel.g > 156.0 || texel.b > 156.0) {
			if (step < 29) {
				lit = row_light(kind == 2 ? 98 : 97);
			} else if (kind == 2) {
				lit = float(step) / 32.0 * 0.73;
			}
		}
	}
	lit = max(lit, glow_of(fetched));
	if (effects_on && anim_count > 0) {
		lit *= anim_light(tile);
	}
	vec3 colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
	if (kind == 3) {
		colour = floor(colour * tower_shadow(hit.x, hit.y, wz));
	}
	return colour;
}

// Texel k of sprite i of the sprite table (in `spans`, after the wall spans).
vec4 sprite_texel(int i, int k) {
	int at = i * 4 + k;
	return texelFetch(spans, ivec2(at % view_size.x, SPAN_K * 2 + 1 + at / view_size.x), 0);
}

// renderer.gd _sky_band()
vec3 sky_at(int column, float sy) {
	float ray = (float(column) + 0.5 - float(view_size.x) * 0.5) / focal;
	int sx = int((view_angle + atan(ray)) * 81.48733086305042) & 511;
	int sr = clamp(int(93.0 + sy * res_up * 0.95), 0, 115);
	if (!effects_on) {
		return texelFetch(tiles_tex, ivec2(sx, sr + sky_row), 0).rgb * 255.0;
	}
	// The clouds drift, faster overhead, still at the treeline.
	float lift = clamp(1.0 - float(sr) / 88.0, 0.0, 1.0);
	sx = (sx + int(sky_drift * 512.0 * lift)) & 511;
	vec3 sky = texelFetch(tiles_tex, ivec2(sx, sr + sky_row), 0).rgb * 255.0;
	return min(sky * (1.0 + lightning * 1.8 * (0.4 + lift)) + vec3(18.0, 20.0, 30.0) * lightning, vec3(255.0));
}

// One pixel of the 320x156 view, 0-255, before the weapon and HUD layer.
vec3 view_at(ivec2 px) {
	ivec2 lp = px / view_div;
	float ray = (float(lp.x) + 0.5 - float(view_size.x) * 0.5) / focal;
	vec2 dir = fwd + side * ray;
	float sy = float(lp.y) + 0.5 - horizon;
	float drawn = dist_at(lp, 0);
	// The nearest whole span covering this pixel, if it is nearer still.
	int best = -1;
	float best_wz = 0.0;
	float best_bottom = 0.0;
	float best_top = 0.0;
	int count = int(texelFetch(spans, ivec2(lp.x, SPAN_K * 2), 0).r + 0.5);
	for (int k = 0; k < count; k++) {
		vec4 a = texelFetch(spans, ivec2(lp.x, k * 2), 0);
		if (a.x >= drawn) {
			continue;
		}
		int rows = int(a.w + 0.5);
		if (lp.y < (rows >> 8) || lp.y > (rows & 255)) {
			continue;
		}
		float wz = eye.z - sy * (a.x / focal);
		if (wz < a.y || wz > a.z) {
			continue;
		}
		vec4 b = texelFetch(spans, ivec2(lp.x, k * 2 + 1), 0);
		int how = int(b.z + 0.5);
		if ((how >> 9) == 4) {
			int pv = clamp(int((a.z - wz) / (a.z - a.y) * 128.0), 0, 127);
			if (span_hole((how >> 2) & 127, pv)) {
				continue;
			}
		}
		drawn = a.x;
		best = k;
		best_wz = wz;
		best_bottom = a.y;
		best_top = a.z;
	}
	vec3 base;
	float plane = plane_at(dir, sy, base);
	if (plane >= drawn) {
		if (best >= 0) {
			base = span_at(lp.x, best, best_wz, best_bottom, best_top, eye.xy + dir * drawn);
		} else if (drawn < 160.0) {
			base = wall_at(lp);
		} else {
			base = sky_at(lp.x, sy);
		}
	}
	float nearest = min(plane, drawn);
	float cover = float(stream_byte(view_size.x * view_size.y * 4 + lp.y * view_size.x + lp.x)) / 255.0;
	if (cover > 0.0) {
		float reach = dist_at(lp, 1);
		// A sprite shows unless a surface the shader drew is in front of it; a ground
		// mark shows only on the surface it lies on.
		bool shown = reach > 0.0 ? nearest > reach - 0.014 : abs(-reach - nearest) < 0.13;
		if (shown) {
			base = floor(texelFetch(colours, lp + ivec2(0, view_size.y), 0).rgb * 255.0 + (1.0 - cover) * base + 0.5);
		}
	}
	// Sprites and painted boards (render_sprites.gd _sprite_band, _draw_sign).
	for (int i = 0; i < sprite_count; i++) {
		vec4 a = sprite_texel(i, 0);
		vec4 b = sprite_texel(i, 1);
		int flags = int(b.w + 0.5);
		bool clear = (flags & 2) != 0;
		vec4 c;
		vec4 d;
		vec3 texel;
		float alpha;
		float dist;
		float light;
		if ((flags & 4) == 0) {
			int left = int(a.x);
			int top = int(a.y);
			int width = int(a.z);
			int height = int(a.w);
			if (lp.x < left || lp.x >= left + width || lp.y < top || lp.y >= top + height) {
				continue;
			}
			dist = b.x;
			if (dist >= nearest + 0.014) {
				continue;
			}
			c = sprite_texel(i, 2);
			d = sprite_texel(i, 3);
			int sw = int(d.x + 0.5);
			int sh = int(d.y + 0.5);
			int sxi = (lp.x - left) * sw / width;
			if ((flags & 1) != 0) {
				sxi = sw - sxi - 1;
			}
			vec4 t = texelFetch(sprite_art, ivec3(sxi, (lp.y - top) * sh / height, int(c.w + 0.5)), 0);
			alpha = floor(t.a * 255.0 + 0.5);
			if (alpha <= (clear ? 12.0 : 100.0)) {
				continue;
			}
			texel = floor(t.rgb * 255.0 + 0.5);
			light = b.y;
			vec3 own = texel;
			texel = clamp(floor(texel * light * c.rgb), 0.0, 255.0);
			if (effects_on && self_lit(own)) {
				texel = max(texel, floor(own * 0.95));
			}
			if (b.z > 0.0) {
				texel = floor(texel * (1.0 - b.z) + vec3(255.0, 232.0, 208.0) * b.z);
			}
		} else {
			d = sprite_texel(i, 3);
			vec2 dv = fwd + side * ((float(lp.x) + 0.5 - float(view_size.x) * 0.5) / focal);
			float den = a.y * dv.x - a.x * dv.y;
			if (den <= 0.001) {
				continue;
			}
			dist = d.w / den;
			if (dist <= 0.13 || dist >= nearest + 0.012) {
				continue;
			}
			float along = ((eye.x - a.z + dv.x * dist) * a.x + (eye.y - a.w + dv.y * dist) * a.y) / b.z + 0.5;
			if (along < 0.0 || along >= 1.0) {
				continue;
			}
			float v = (b.x + b.y - eye.z + sy * dist / focal) / b.y;
			if (v < 0.0 || v >= 1.0) {
				continue;
			}
			c = sprite_texel(i, 2);
			int sw = int(d.x + 0.5);
			int sh = int(d.y + 0.5);
			vec4 t = texelFetch(sprite_art, ivec3(clamp(int(along * float(sw)), 0, sw - 1), clamp(int(v * float(sh)), 0, sh - 1), int(c.w + 0.5)), 0);
			alpha = floor(t.a * 255.0 + 0.5);
			if (alpha <= (clear ? 12.0 : 100.0)) {
				continue;
			}
			light = floor(max(0.19, d.z / (1.0 + 0.102 * dist)) * 32.0 + 0.5) / 32.0;
			texel = floor(floor(t.rgb * 255.0 + 0.5) * light * c.rgb);
		}
		if (clear) {
			float cov = alpha / 255.0;
			base = clamp(floor(base * (1.0 - cov) + texel * cov + 0.5), 0.0, 255.0);
		} else {
			base = clamp(texel, 0.0, 255.0);
			nearest = dist;
		}
	}
	if (effects_on && light_count > 0 && nearest < 160.0) {
		// The point of the nearest surface along this ray, lit by the frame's lights.
		vec3 p = vec3(eye.xy + dir * nearest, eye.z - sy * nearest / focal);
		base = min(floor(base * (vec3(1.0) + lights_at(p))), vec3(255.0));
	}
	if (effects_on && nearest < 160.0) {
		// The level's mood: its tint, a lightning flash, and the fog of distance.
		base = min(base * grade * (1.0 + lightning * 0.55), vec3(255.0));
		float fog = fog_range.z * smoothstep(fog_range.x, fog_range.y, nearest);
		base = floor(mix(base, fog_color * 255.0, fog));
	}
	if (pane_on) {
		float glass = dist_at(lp, 2);
		if (glass < 160.0 && glass < nearest) {
			base = floor(base * vec3(0.67, 0.78, 0.82) + texelFetch(colours, lp + ivec2(0, view_size.y * 2), 0).rgb * 255.0 * 0.33);
		}
	}
	return clamp(base, 0.0, 255.0);
}

// The finished view pixel: the weapon and HUD layer over the view.
vec3 picture_at(ivec2 px, vec3 frame) {
	vec4 o = texelFetch(post_tex, px, 0);
	if (o.a >= 1.0) {
		return o.rgb * 255.0;
	}
	vec3 under = vec3(0.0);
	if (scene_on && px.y < 156) {
		under = view_at(px);
	} else if (base_on) {
		under = frame;
	}
	return floor(o.rgb * 255.0 + (1.0 - o.a) * under + 0.5);
}

void fragment() {
	ivec2 px = ivec2(UV * vec2(320.0, 200.0));
	vec3 c;
	if (overlay_on) {
		if (drunk > 0.0 && px.y < 156) {
			// game.gd _drunk_warp(): per-row shear, ghost double image, amber tint.
			int shift = int(floor(sin(float(px.y) * 0.16 + drunk_phase) * (1.0 + 3.4 * drunk) + 0.5));
			int sx = (px.x + shift + 640) % 320;
			int gx = (px.x - drunk_ghost + shift + 640) % 320;
			float blend = 0.30 * drunk;
			vec3 v = picture_at(ivec2(sx, px.y), texelFetch(TEXTURE, ivec2(sx, px.y), 0).rgb * 255.0) * (1.0 - blend)
					+ picture_at(ivec2(gx, px.y), texelFetch(TEXTURE, ivec2(gx, px.y), 0).rgb * 255.0) * blend;
			c = floor(vec3(v.r * (1.0 + 0.06 * drunk), v.g, v.b * (1.0 - 0.10 * drunk)));
		} else {
			c = picture_at(px, texelFetch(TEXTURE, px, 0).rgb * 255.0);
		}
		c = clamp(c, 0.0, 255.0) / 255.0;
	} else {
		c = texture(TEXTURE, UV).rgb;
	}
	ivec3 q = ivec3(clamp(c, 0.0, 1.0) * 255.0 + 0.5);
	if (px.y < 156 && hurt > 0) {
		q = (ivec3(131, 27, 17) * hurt + q * (255 - hurt)) / 255;
	}
	if (px.y < 156 && (look || tone_on)) {
		vec3 v = vec3(q);
		if (look) {
			vec2 n = (vec2(px) / vec2(319.0, 155.0) - 0.5) * 2.0;
			float vignette = 1.0 - 0.13 * pow(length(n) / 1.4142, 2.1);
			float g = texelFetch(looks, ivec2(grain_frame * 156 + px.y, GRAIN_ROW + px.x), 0).r * 255.0;
			float add = g - 2.0 + blast + (BAYER[(px.x % 4) * 4 + (px.y % 4)] / 16.0 - 0.5) * 6.0;
			v = clamp(trunc(v * (wash * vignette * gain) + add), 0.0, 255.0);
		}
		if (tone_on) {
			v = vec3(texelFetch(looks, ivec2(int(v.r), TONE_ROW), 0).r, texelFetch(looks, ivec2(int(v.g), TONE_ROW), 0).r,
					texelFetch(looks, ivec2(int(v.b), TONE_ROW), 0).r) * 255.0;
		}
		q = ivec3(v + 0.5);
	}
	int r5 = (q.r * 31 + 127) / 255;
	int g5 = (q.g * 31 + 127) / 255;
	int b5 = (q.b * 31 + 127) / 255;
	int code = (r5 << 10) | (g5 << 5) | b5;
	ivec2 pos = ivec2(code & 255, code >> 8);
	COLOR = vec4(texelFetch(looks, pos, 0).rgb, 1.0);
}
