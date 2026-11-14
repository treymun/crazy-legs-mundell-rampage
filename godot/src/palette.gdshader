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
// The renderer's per-frame parts, stacked one after another, as plain bytes
// so a frame is only copied, never converted. Each part holds only the view's
// rows it wrote anything in this frame: the wall pixels (walls, codes, their
// distances) rows px_rows.x to px_rows.y - 1, the sprites/ground marks
// (colour, coverage, distance) over_rows, the window panes pane_rows; a pixel
// outside them is empty there. colours (RGB, a view wide): walls (from row 0),
// sprites/ground marks (premultiplied, from over_row), then from stream_row a
// stream of bytes read three to a texel: the wall codes (four bytes a pixel),
// then the sprite/ground mark coverage (one byte a pixel, from byte cover_at),
// then the window panes from pane_row. The distances (walls, sprites/ground
// marks, window panes) are a float stream in `spans`, four to a texel, from
// row dist_row, each band from float dist_start[band] (dist_at()). A part the
// renderer left empty this frame is not sent at all: pixels_on off means no
// wall pixel (every wall a span), over_on off no sprite or ground mark pixel,
// pane_on off no pane.
uniform sampler2D colours : filter_nearest, repeat_disable;
uniform bool pixels_on = true;
uniform bool over_on = true;
uniform ivec2 px_rows = ivec2(0, 156);
uniform ivec2 over_rows = ivec2(0, 156);
uniform ivec2 pane_rows = ivec2(0, 156);
uniform int over_row = 156;
uniform int stream_row = 468;
uniform int cover_at = 199680;
uniform int pane_row = 312;
uniform ivec3 dist_start = ivec3(0, 49920, 99840);
// The walls the renderer drew as whole spans down a column, two texels a
// span (renderer: render_state.gd SPAN_K), only as many rows as the fullest
// column needs; then from row count_row each column's span count (r) and where
// the shader's own walk starts in its block's list (g, walk_walls); then the
// sprite table: sprite i's texel k is texel i * 4 + k counted on across the
// rows, from row sprite_row. Then the distances from dist_row.
uniform sampler2D spans : filter_nearest, repeat_disable;
uniform int count_row = 24;
uniform int sprite_row = 25;
uniform int dist_row = 0;
// Walls the shader finds itself (walk_walls; render_state.gd gpu_walls): from
// row wall_row of `spans`, four texels a wall, then from texel block_at one a
// block of block_w columns, then from texel entry_at the blocks' lists.
uniform bool walls_on = false;
uniform int wall_row = 0;
uniform int block_at = 0;
uniform int entry_at = 0;
uniform int block_w = 8;
// The level's plane table (plane()), sent when the level or its light changes.
uniform sampler2D planes : filter_nearest, repeat_disable;
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
// The plane table (plane()): row 0 floor heights nearest
// first (height, first cap, cap count), row 1 roof heights (the same), row 2
// cap rectangles, row 3 cap tiles, row 4 tints, rows 5 and 6 each cap's two
// cut lines (nx, ny, c: inside where nx x + ny y <= c), rows 7 to 11 the
// sloped surfaces (plane, box, tile and tint, two cut lines; level format 2),
// and from LIGHT_ROW each cell's light.
const int LIGHT_ROW = 12;
uniform ivec2 map_size = ivec2(1);
uniform int floor_count = 0;
uniform int roof_count = 0;
uniform int tint_count = 1;
uniform int slope_count = 0;
// The camera, as the renderer used it.
uniform vec3 eye = vec3(0.0);
uniform vec2 fwd = vec2(1.0, 0.0);
uniform vec2 side = vec2(0.0, 1.0);
uniform float view_angle = 0.0;
uniform float horizon = 78.0;
uniform float focal = 230.0;
uniform ivec2 view_size = ivec2(320, 156);
uniform int view_div = 1;
// HD: the view is drawn at twice the size each way and shown at that size; the
// weapon and HUD layer stays 320x200.
uniform int view_mul = 1;
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
// The weather, the water and the shimmer of hot air, all behind effects_on
// (features/weather.gd, features/water.gd, view_lights.gd, effects.cfg):
// what each tile is to them sits in one row of tiles_tex from info_row (r
// water, g relief, b puddles; tile_info()). rain is how hard it rains (streaks
// over the view, rings on water and puddles), wet how wet the ground is
// (puddles, a sheen on walls under the sky), flash_dir where the lightning
// is, fog_banks how thick the banks rolling over a bayou night are, motion
// how much it all moves (EASY ON THE EYES: 1, .4, 0). rings: where bodies
// wade, x, y, age in seconds and size. light_flags: bit 1 a light pools on
// the ground under it. haze_box: over each hot thing in sight, its centre
// column, base row, half width and height in view pixels; haze_amp how far
// its air sways.
uniform int info_row = 0;
uniform float rain = 0.0;
uniform float wet = 0.0;
uniform vec2 flash_dir = vec2(0.6, -0.8);
uniform float fog_banks = 0.0;
uniform float motion = 1.0;
uniform int ring_count = 0;
uniform vec4 rings[16];
uniform int light_flags[16];
uniform int haze_count = 0;
uniform vec4 haze_box[4];
uniform float haze_amp[4];
// How much relief catches a light raking across it, and the sky's light from
// above; how big a pool of lamp light is against the lamp's reach.
const float RELIEF_K = 1.5;
const float RELIEF_SKY = 0.45;
const float POOL_REACH = 0.36;
const float RELIEF_FAR = 10.0;
const vec3 SKY_LIGHT = vec3(-0.33, -0.42, 0.85);

int byte_of(float v) {
	return int(v * 255.0 + 0.5);
}

// What `tile` is to the weather (scene_layers.gd _tile_info): r water, g
// relief (-1 to 1: below 0 the darker texels are raised), b puddles.
vec4 tile_info(int tile) {
	vec4 info = texelFetch(tiles_tex, ivec2(tile, info_row), 0);
	info.g = (info.g * 255.0 - 128.0) / 127.0;
	return info;
}

// No roof over this point of the map: under the open sky (the cells' second
// band, g; scene_layers.gd _load_level).
bool open_sky(vec2 at) {
	ivec2 cell = ivec2(floor(at));
	if (cell.x < 0 || cell.y < 0 || cell.x >= map_size.x || cell.y >= map_size.y) {
		return true;
	}
	return texelFetch(tiles_tex, cell + ivec2(0, cells_row + map_size.y), 0).g > 0.5;
}

float luma(vec3 c) {
	return dot(c, vec3(0.30, 0.59, 0.11));
}

// How a tile's brightness climbs into texel (pu, pv) from the one before it
// across and the one above: raised where a texel is brighter than its
// neighbours (brick faces over mortar, plank faces over the gaps, the ridges
// of tin). `here` is the texel, 0-1.
vec2 relief_at(int tile, int pu, int pv, vec3 here) {
	ivec2 o = ivec2((tile % 16) * 128, (tile / 16) * 128);
	float h = luma(here);
	float left = luma(texelFetch(tiles_tex, o + ivec2((pu + 127) & 127, pv), 0).rgb);
	float up = luma(texelFetch(tiles_tex, o + ivec2(pu, (pv + 127) & 127), 0).rgb);
	return vec2(h - left, h - up);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// The rings on water where bodies wade (features/water.gd), 0 to about 1 at
// `at` (snapped to the chunky grid).
float wading_rings(vec2 at) {
	float glint = 0.0;
	for (int i = 0; i < ring_count; i++) {
		vec4 r = rings[i];
		float d = distance(at, r.xy);
		float size = sqrt(r.w);
		float radius = (0.06 + r.z * 0.62) * size;
		float width = 0.03 + 0.018 * r.w;
		float fade = (1.0 - r.z / 1.6) * min(r.w, 1.4);
		float band = 1.0 - abs(d - radius) / width;
		if (band > 0.0) {
			glint = max(glint, fade * (band > 0.5 ? 1.0 : 0.5));
		}
		if (r.w > 1.1) {
			float inner = 1.0 - abs(d - radius * 0.55) / width;
			if (inner > 0.0) {
				glint = max(glint, fade * (inner > 0.5 ? 0.6 : 0.3));
			}
		}
		if (r.z < 0.16 && d < 0.06 * r.w) {
			glint = max(glint, 1.3);
		}
	}
	return glint;
}

// Rain falling on water: a little ring where each drop lands, more of them the
// harder it rains, 0 to 1.
float rain_rings(vec2 at, float tm) {
	if (rain <= 0.0) {
		return 0.0;
	}
	vec2 g = floor(at * 3.0);
	float phase = hash12(g + 5.3);
	float beat = tm * 1.5 + phase;
	float cycle = floor(beat);
	float h = hash12(g + cycle * 3.71);
	if (h > rain * 0.8) {
		return 0.0;
	}
	float age = fract(beat);
	vec2 c = (g + 0.25 + 0.5 * vec2(fract(h * 7.13), fract(h * 13.7))) / 3.0;
	float band = 1.0 - abs(distance(at, c) - age * 0.13) / 0.028;
	return band > 0.0 ? (1.0 - age) * (band > 0.5 ? 0.9 : 0.45) : 0.0;
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

// What this frame's lights add at a point: a fraction per channel. nf is the
// surface's own normal, nb the same with its relief: a bump facing a light
// takes more of it and one facing away less, so the gun's flash and the lamps
// rake across brick and tin. A glossy surface (water, puddles, walls in the
// rain) gives back a glint of each lamp toward the eye (`view`); on a floor,
// a light that pools (light_flags) lays a banded, coloured pool under it.
vec3 lights_at(vec3 p, vec3 nf, vec3 nb, bool ground, float gloss, vec3 view) {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 at = light_pos[i];
		vec3 d = at.xyz - p;
		float dist = length(d);
		float reach = clamp(1.0 - dist / at.w, 0.0, 1.0);
		if (reach <= 0.0) {
			continue;
		}
		vec3 l = d / max(dist, 0.001);
		float k = reach * reach * max(0.0, 1.0 + RELIEF_K * (dot(nb, l) - dot(nf, l)));
		if (gloss > 0.0) {
			k += gloss * reach * pow(max(dot(nb, normalize(l + view)), 0.0), 24.0) * 2.2;
		}
		if (ground && (light_flags[i] & 1) != 0) {
			float q = clamp(1.0 - length(d.xy) / (at.w * POOL_REACH), 0.0, 1.0);
			k += floor(q * 3.0 + 0.999) / 3.0 * 0.85;
		}
		sum += light_col[i].rgb * light_col[i].a * k;
	}
	return sum;
}

// Texel c of the plane table.
vec4 plane(ivec2 c) {
	return texelFetch(planes, c, 0);
}

// The distance band b (0 walls, 1 sprites and ground marks, 2 window panes)
// holds at this view pixel, which lies in the band's rows.
float dist_at(ivec2 lp, int b) {
	int first = b == 0 ? px_rows.x : b == 1 ? over_rows.x : pane_rows.x;
	int i = dist_start[b] + (lp.y - first) * view_size.x + lp.x;
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

// A water floor (effects.cfg [water], how much `deep`) or a puddle on wet
// ground, over the floor's lit colour: a broken reflection of the sky in
// bands that sway, glints on the ripples' crests, rings where bodies wade and
// where the rain lands. `light` is how lit the floor is; column and sy the
// pixel's, for the sky it mirrors.
vec3 water_over(vec3 colour, vec2 at, float t, float sy, int column, float deep, float light, float tm) {
	vec2 q = floor(at * 16.0) / 16.0;
	float sway = sin(q.y * 9.0 + sin(q.x * 3.1) * 1.4 + tm * 1.6);
	vec3 mirrored = sky_at(column + int(floor(sway * 1.6 + 0.5)), -sy * (1.0 + 0.05 * sway));
	float grazing = clamp(t * 0.14, 0.25, 1.0);
	float band = sin(q.y * 11.0 + sin(q.x * 2.7) * 1.5 + tm * 1.1) > -0.2 ? 1.0 : 0.35;
	float shine = deep * (0.2 + 0.4 * grazing) * band;
	vec3 out_colour = colour * (1.0 - shine) + mirrored * 0.85 * shine;
	float crest = sin(q.x * 4.7 + q.y * 3.1 + tm * 1.9) + sin(q.y * 7.3 - q.x * 2.2 - tm * 1.4);
	float glint = (crest > 1.5 ? 0.42 : 0.0) * deep;
	// Rings catch the light whatever the water: they are what moves on it.
	glint = max(glint, wading_rings(q) * 1.2);
	glint = max(glint, rain_rings(q, tm) * 0.8);
	return out_colour + vec3(84.0, 92.0, 100.0) * glint * (0.45 + 0.5 * min(light, 1.2));
}

// The nearest floor (sy >= 0) or ceiling along this pixel's ray: its distance
// (1e9 when there is none) and its lit colour, 0-255. With effects_on, `surf`
// says how its relief slopes (x, y along the map, texel steps) and how glossy
// it is (z: water, puddles, wet ground); `column` is the pixel's.
// Whether `at` is inside cap k's two cut lines (rows 5 and 6).
bool cap_cut(int k, vec2 at) {
	vec4 a = plane(ivec2(k, 5));
	vec4 b = plane(ivec2(k, 6));
	return a.x * at.x + a.y * at.y <= a.z && b.x * at.x + b.y * at.y <= b.z;
}

float flat_plane_at(vec2 dir, float sy, int column, out vec3 colour, out vec3 surf) {
	colour = vec3(0.0);
	surf = vec3(0.0);
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
		}
		int first = int(entry.g + 0.5);
		int last = first + int(entry.b + 0.5);
		for (int k = first; k < last; k++) {
			vec4 box = plane(ivec2(k, 2));
			if (at.x >= box.x && at.x <= box.z && at.y >= box.y && at.y <= box.w && cap_cut(k, at)) {
				tile = int(floor(plane(ivec2(k, 3)).r + 0.5));
				break;
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
		vec4 band = texelFetch(tiles_tex, cell + ivec2(0, cells_row + map_size.y), 0);
		vec4 info = vec4(0.0);
		bool open = false;
		float tm = anim_time * motion;
		if (effects_on && !overhead) {
			info = tile_info(tile);
			open = band.g > 0.5;
			if (info.r > 0.0) {
				// Water sways its texels a little, in chunky steps.
				vec2 q = floor(at * 16.0) / 16.0;
				pu = (pu + int(floor(sin(q.y * 6.3 + tm * 1.7 + sin(q.x * 2.3)) * 2.0 + 0.5))) & 127;
				pv = (pv + int(floor(sin(q.x * 5.1 - tm * 1.3) * 1.5 + 0.5))) & 127;
			}
		}
		vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
		vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
		float raw = (plane(cell + ivec2(0, LIGHT_ROW)).r * (overhead ? 0.77 : 0.94) + flash_light) / (1.0 + 0.102 * t);
		float lit = max(float(min(int(max(raw, 0.19) * 32.0 + 0.5), 96)) / 32.0, glow_of(fetched));
		if (effects_on && anim_count > 0) {
			lit *= anim_light(tile);
		}
		int tint_at = min(byte_of(band.r), tint_count - 1);
		vec3 tint = plane(ivec2(tint_at, 4)).rgb;
		if (hub_fx && !overhead) {
			if (tile == hub_runoff) {
				texel = running_water(texel, at.x, at.y);
			} else if (tile == hub_patch || tile == hub_wall) {
				lit *= tower_shadow(at.x, at.y, h);
			}
		}
		colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
		if (effects_on) {
			if (info.r > 0.0) {
				colour = water_over(colour, at, t, sy, column, info.r, lit, tm);
				surf.z = info.r;
			} else if (open && wet > 0.0) {
				// Wet ground darkens; where it lies low it holds a puddle.
				vec2 q = floor(at * 10.0) / 10.0;
				float low = 0.5 + 0.25 * sin(q.x * 1.7 + sin(q.y * 1.3) * 1.8) + 0.25 * sin(q.y * 2.3 + sin(q.x * 0.9) * 2.1);
				if (info.b > 0.0 && low > 1.0 - wet * info.b * 0.34) {
					colour = water_over(colour * 0.5, at, t, sy, column, 0.85, lit, tm);
					surf.z = 1.0;
					return t;
				}
				colour = floor(colour * (1.0 - 0.17 * wet));
				surf.z = 0.4 * wet;
			}
			if (abs(info.g) > 0.01 && t < RELIEF_FAR) {
				surf.xy = relief_at(tile, pu, pv, fetched.rgb) * info.g * 3.0 * (1.0 - glow_of(fetched));
			}
		}
		return t;
	}
	return 1e9;
}

// The nearest floor or ceiling along this pixel's ray (flat_plane_at), or a
// sloped surface nearer than it (level format 2: a ramp's top, a sloped
// underside; drawn plain, without the weather's or the water's touches). The
// ray's height falls by sy / focal per unit along it, so it meets the plane
// z = z0 + gx (x - x0) + gy (y - y0) where
//   t = (eye.z - plane at the eye) / (sy / focal + gx dir.x + gy dir.y).
float plane_at(vec2 dir, float sy, int column, out vec3 colour, out vec3 surf) {
	float t = flat_plane_at(dir, sy, column, colour, surf);
	for (int i = 0; i < slope_count; i++) {
		vec4 pl = plane(ivec2(i, 7));
		vec4 box = plane(ivec2(i, 8));
		float num = eye.z - (pl.x + pl.y * (eye.x - box.x) + pl.z * (eye.y - box.y));
		float den = sy / focal + pl.y * dir.x + pl.z * dir.y;
		if (num * pl.w <= 0.0 || den * pl.w <= 1e-6) {
			continue;
		}
		float ts = num / den;
		if (ts < 0.015 || ts > 80.0 || ts >= t) {
			continue;
		}
		vec2 at = eye.xy + ts * dir;
		if (at.x < box.x || at.x > box.z || at.y < box.y || at.y > box.w) {
			continue;
		}
		vec4 a = plane(ivec2(i, 10));
		vec4 b = plane(ivec2(i, 11));
		if (a.x * at.x + a.y * at.y > a.z || b.x * at.x + b.y * at.y > b.z) {
			continue;
		}
		ivec2 cell = ivec2(at);
		if (cell.x < 0 || cell.y < 0 || cell.x >= map_size.x || cell.y >= map_size.y) {
			continue;
		}
		vec4 info = plane(ivec2(i, 9));
		int tile = int(floor(info.r + 0.5));
		int pu = int(at.x * 128.0) & 127;
		int pv = int(at.y * 128.0) & 127;
		vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
		vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
		float raw = (plane(cell + ivec2(0, LIGHT_ROW)).r * (pl.w > 0.0 ? 0.94 : 0.77) + flash_light) / (1.0 + 0.102 * ts);
		float lit = max(float(min(int(max(raw, 0.19) * 32.0 + 0.5), 96)) / 32.0, glow_of(fetched));
		vec3 tint = plane(ivec2(min(int(info.g + 0.5), tint_count - 1), 4)).rgb;
		colour = clamp(floor(texel * lit * tint), 0.0, 255.0);
		surf = vec3(0.0);
		t = ts;
	}
	return t;
}

// Byte i of the stream in `colours` (from stream_row).
int stream_byte(int i) {
	int t = i / 3;
	vec3 texel = texelFetch(colours, ivec2(t % view_size.x, stream_row + t / view_size.x), 0).rgb;
	int k = i - t * 3;
	return int((k == 0 ? texel.r : k == 1 ? texel.g : texel.b) * 255.0 + 0.5);
}

// How the relief of `tile` slopes at texel (pu, pv) along a wall (effects.cfg
// [relief]; none on a texel that glows, nor past RELIEF_FAR, where it cannot
// be seen: `t` is the distance).
vec2 wall_relief(int tile, int pu, int pv, vec4 fetched, float t) {
	if (!effects_on || t >= RELIEF_FAR) {
		return vec2(0.0);
	}
	float deep = tile_info(tile).g;
	return abs(deep) > 0.01 ? relief_at(tile, pu, pv, fetched.rgb) * deep * 3.0 * (1.0 - glow_of(fetched)) : vec2(0.0);
}

// A wall pixel's colour (renderer.gd _wall_band and its shade table), and its
// relief (wall_relief). The pixel lies in px_rows.
vec3 wall_at(ivec2 lp, out vec2 bump) {
	bump = vec2(0.0);
	int at = ((lp.y - px_rows.x) * view_size.x + lp.x) * 4;
	ivec4 code = ivec4(stream_byte(at), stream_byte(at + 1), stream_byte(at + 2), stream_byte(at + 3));
	int shade_row = (code.b >> 5) | (code.a << 3);
	if (shade_row == 2047) {
		return texelFetch(colours, lp - ivec2(0, px_rows.x), 0).rgb * 255.0;
	}
	int tile = ((code.b & 31) << 2) | (code.g >> 6);
	int pv = ((code.g & 63) << 1) | (code.r >> 7);
	int pu = code.r & 127;
	vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
	bump = wall_relief(tile, pu, pv, fetched, pixels_on ? dist_at(lp, 0) : 0.0);
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

// A wall's colour at height wz (render_surfaces.gd _wall_band): texel column
// pu of `tile` (`plain` outside the window band, mode 2), lit by shade row
// shade_row (tint * 99 + light step); plain walls, glowing signs (kind 1, 2),
// and the hub walls the water tower shades (kind 3, at the point hit).
vec3 wall_colour(int tile, int plain, int pu, int mode, int kind, int shade_row, float wz, float bottom, float top, vec2 hit, float t, out vec2 bump) {
	int pv;
	if (mode == 0) {
		pv = clamp(int((top - wz) / (top - bottom) * 128.0), 0, 127);
	} else {
		pv = int((1.96 - wz) * 100.0) & 127;
		if (mode == 2 && (wz < 1.0 || wz > 1.68)) {
			tile = plain;
		}
	}
	vec4 fetched = texelFetch(tiles_tex, ivec2((tile % 16) * 128 + pu, (tile / 16) * 128 + pv), 0);
	bump = wall_relief(tile, pu, pv, fetched, t);
	vec3 texel = floor(fetched.rgb * 255.0 + 0.5);
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

// The colour of span k of a column the renderer drew (its second texel says
// what it is: render_state.gd SPAN_K).
vec3 span_at(int column, int k, float wz, float bottom, float top, vec2 hit, float t, out vec2 bump) {
	vec4 b = texelFetch(spans, ivec2(column, k * 2 + 1), 0);
	int how = int(b.z + 0.5);
	return wall_colour(int(b.x + 0.5), int(b.y + 0.5), (how & 511) >> 2, how & 3, how >> 9, int(b.w + 0.5), wz, bottom, top, hit, t, bump);
}

// Texel i of the walls the shader walks (render_surfaces.gd _pack_walls), in
// `spans` from row wall_row.
vec4 wall_texel(int i) {
	return texelFetch(spans, ivec2(i % view_size.x, wall_row + i / view_size.x), 0);
}

// The nearest wall at this pixel among those the shader walks: column lp.x's
// block's walls, nearest first, past the `skip` the renderer drew in this
// column, nearer than `drawn` and no farther than `bound` (the floor or
// ceiling there), with the renderer's own tests (_wall_band, then view_at's
// for a span). Returns its place in the table, or -1, and lowers `drawn` to
// its distance; `found` is its height here, bottom, top and u along it, and
// `terms` its per-column terms (wall_frame()).
int walk_walls(ivec2 lp, float sy, float bound, int skip, inout float drawn, out vec4 found, out vec4 terms) {
	found = vec4(0.0);
	terms = vec4(0.0);
	vec4 block = wall_texel(block_at + lp.x / block_w);
	if (float(lp.y) < block.z || float(lp.y) > block.w) {
		return -1;
	}
	int first = int(block.x + 0.5) + skip;
	int last = int(block.x + 0.5) + int(block.y + 0.5);
	float offset = float(lp.x) + 0.5 - float(view_size.x) * 0.5;
	float row = float(lp.y);
	float lowest = float(view_size.y - 1);
	int best = -1;
	vec4 quad = vec4(0.0);
	for (int e = first; e < last; e++) {
		int q = e & 3;
		if (q == 0 || e == first) {
			quad = wall_texel(entry_at + (e >> 2));
		}
		int slot = int((q == 0 ? quad.x : q == 1 ? quad.y : q == 2 ? quad.z : quad.w) + 0.5);
		vec4 w0 = wall_texel(slot * 4);
		if (w0.y > min(bound, drawn)) {
			break;
		}
		int cols = int(w0.x + 0.5);
		int reach = int(w0.w + 0.5);
		if (lp.x < (cols & 1023) || lp.x >= (cols >> 10) || lp.y < (reach & 1023) || lp.y > ((reach >> 10) & 1023)) {
			continue;
		}
		vec4 w1 = wall_texel(slot * 4 + 1);
		float den = w1.x + offset * w1.y;
		if (abs(den) < 1e-6) {
			continue;
		}
		float t = w0.z / den;
		if (t <= 0.015 || t >= 160.0 || t >= drawn) {
			continue;
		}
		float u = (w1.z + offset * w1.w) / den;
		if (u < -0.00002 || u > 1.00002) {
			continue;
		}
		vec4 w2 = wall_texel(slot * 4 + 2);
		if (row < max(0.0, ceil(w2.z / t + horizon - 0.5)) || row > min(lowest, floor(w2.w / t + horizon - 0.5))) {
			continue;
		}
		float wz = eye.z - sy * (t / focal);
		if (wz < w2.x || wz > w2.y) {
			continue;
		}
		float tex_u = den < 0.0 ? 1.0 - u : u;
		if (reach >= 1048576) {
			// The road shed's open mesh shows what is behind.
			int pv = clamp(int((w2.y - wz) / (w2.y - w2.x) * 128.0), 0, 127);
			if (span_hole(clamp(int(tex_u * 128.0), 0, 127), pv)) {
				continue;
			}
		}
		drawn = t;
		best = slot;
		found = vec4(wz, w2.x, w2.y, tex_u);
		terms = w1;
	}
	return best;
}

// The way a walked wall faces (toward the eye) and the way its texture's u
// runs along it, from its per-column terms (render_surfaces.gd _pack_walls):
// t = num / (w1.x + offset * w1.y) puts the wall's normal along
// w1.x * fwd + w1.y * focal * side, and u = (w1.z + offset * w1.w) / den.
void wall_frame(vec4 w1, vec2 dir, float t, float offset, out vec3 normal, out vec3 along) {
	vec2 n = w1.x * fwd + w1.y * focal * side;
	n = length(n) > 1e-6 ? normalize(n) : -normalize(dir);
	if (dot(n, dir) > 0.0) {
		n = -n;
	}
	vec2 run = vec2(-n.y, n.x);
	float den = w1.x + offset * w1.y;
	// Which way the hit point moves along the wall, and u with it, a column on.
	vec2 moves = t * (side / focal - (w1.y / den) * dir);
	float du = w1.w * w1.x - w1.z * w1.y;
	float flip = sign(dot(moves, run)) * sign(du) * (den < 0.0 ? -1.0 : 1.0);
	normal = vec3(n, 0.0);
	along = vec3(run * (flip == 0.0 ? 1.0 : flip), 0.0);
}

// The colour of the walked wall in table place `slot` at distance t
// (render_surfaces.gd _wall_band's texel column and light step for its span).
vec3 walked_at(int slot, float t, vec4 found, vec2 hit, out vec2 bump) {
	vec4 w3 = wall_texel(slot * 4 + 3);
	int tiles = int(w3.x + 0.5);
	int how = int(w3.w + 0.5);
	int mode = how & 3;
	int pu = mode == 1 ? int(found.w * w3.y) & 127 : clamp(int(found.w * 128.0), 0, 127);
	float lit = max(w3.z / (1.0 + 0.102 * t), 0.19);
	int step = clamp(int(floor(lit * 32.0 + 0.5)), 0, 96);
	return wall_colour(tiles & 4095, tiles >> 12, pu, mode, (how >> 2) & 7, (how >> 5) + step, found.x, found.y, found.z, hit, t, bump);
}

// Texel k of sprite i of the sprite table (in `spans`, after the wall spans).
vec4 sprite_texel(int i, int k) {
	int at = i * 4 + k;
	return texelFetch(spans, ivec2(at % view_size.x, sprite_row + at / view_size.x), 0);
}

// Rolling fog banks over a bayou night (effects.cfg fog_banks): how much more
// fog hangs where this ray meets them, low over the ground, drifting slowly.
// `reach` is how far along the ray (capped), `sy` the pixel's row offset.
float fog_bank(vec2 dir, float sy, float reach) {
	vec2 q = eye.xy + dir * reach;
	float tm = anim_time * motion;
	float roll = 0.5 + 0.28 * sin(q.x * 0.21 + tm * 0.05 + sin(q.y * 0.13) * 1.7) + 0.22 * sin(q.y * 0.17 - tm * 0.037 + q.x * 0.07);
	float high = (eye.z - sy * reach / focal) - (eye.z - 0.95);
	float low = clamp(1.4 - high, 0.0, 1.0);
	return fog_banks * smoothstep(0.56, 0.9, roll) * low * smoothstep(3.0, 9.0, reach);
}

// The view's own lights and weather over a surface's colour (effects_on):
// the frame's lights with relief and pools, the level's tint and fog, a wet
// sheen on what stands under the rain, the lightning lighting the yard. The
// surface: its point p, normal nf, the ways its texture's u and v run (tu,
// tv), how its relief slopes (bump), how glossy it is, and what it is (kind
// 0 a floor or ceiling, 1 a wall, 2 a sprite).
vec3 surface_light(vec3 base, vec3 p, vec2 dir, float sy, float nearest, vec3 nf, vec3 tu, vec3 tv, vec2 bump, float gloss, int kind) {
	vec3 nb = (bump.x != 0.0 || bump.y != 0.0) ? normalize(nf - bump.x * tu - bump.y * tv) : nf;
	bool ground = kind == 0 && nf.z > 0.0;
	bool outside = false;
	if (rain > 0.0 || wet > 0.0 || lightning > 0.0) {
		outside = open_sky(p.xy - dir * 0.02);
	}
	if (outside && wet > 0.0 && kind == 1) {
		// Walls and things under the sky get wet: darker, glossy, with runs
		// of water down them.
		float run_at = floor(dot(p.xy, tu.xy) * 18.0);
		float h = hash12(vec2(run_at, 3.0));
		float flow = fract(p.z * 1.3 + anim_time * motion * 0.7 + h * 7.0);
		base *= 1.0 - 0.14 * wet;
		if (h < 0.22 && flow < 0.35) {
			base += vec3(26.0, 28.0, 32.0) * wet * (1.0 - flow / 0.35);
		}
		gloss = max(gloss, 0.5 * wet);
	}
	// The sky's light from above: relief reads even where no lamp is.
	if (nb != nf) {
		vec3 sun = normalize(SKY_LIGHT);
		base *= 1.0 + RELIEF_SKY * (dot(nb, sun) - dot(nf, sun));
	}
	if (light_count > 0 && nearest < 160.0) {
		vec3 view = normalize(vec3(eye.xy, eye.z) - p);
		base = min(floor(base * (vec3(1.0) + lights_at(p, nf, nb, ground, outside ? gloss : gloss * 0.5, view))), vec3(255.0));
	}
	// The level's mood: its tint, the rain greying it, and the fog of distance.
	base = min(base * grade * (outside ? 1.0 - 0.05 * rain : 1.0), vec3(255.0));
	if (lightning > 0.0) {
		// The flash lights the yard, most where a face looks its way; under a
		// roof only a little comes in.
		vec3 toward = normalize(vec3(flash_dir, 1.1));
		float lift = outside ? 0.4 + 0.5 * clamp(dot(nb, toward), 0.0, 1.0) + gloss * 0.2 : 0.14;
		base = min(base * (vec3(1.0) + lightning * lift * vec3(0.86, 0.93, 1.12)), vec3(255.0));
	}
	float soak = 1.0 - 0.12 * rain;
	float fog = min(fog_range.z + 0.06 * rain, 1.0) * smoothstep(fog_range.x * soak, fog_range.y * soak, nearest);
	if (fog_banks > 0.0) {
		fog = fog + (1.0 - fog) * fog_bank(dir, sy, min(nearest, 14.0));
	}
	return floor(mix(base, fog_color * 255.0, fog));
}

// One pixel of the view, 0-255, before the weapon and HUD layer. `fine` is the
// screen pixel in view_mul steps of a 320x200 one (HD: 640x400). `far` is the
// distance of the nearest thing drawn there (1e9: the sky).
vec3 view_at(ivec2 fine, out float far) {
	ivec2 lp = fine / view_div;
	float ray = (float(lp.x) + 0.5 - float(view_size.x) * 0.5) / focal;
	vec2 dir = fwd + side * ray;
	float sy = float(lp.y) + 0.5 - horizon;
	float drawn = pixels_on && lp.y >= px_rows.x && lp.y < px_rows.y ? dist_at(lp, 0) : 160.0;
	// The nearest whole span covering this pixel, if it is nearer still.
	int best = -1;
	float best_wz = 0.0;
	float best_bottom = 0.0;
	float best_top = 0.0;
	vec4 counts = texelFetch(spans, ivec2(lp.x, count_row), 0);
	int count = int(counts.r + 0.5);
	for (int k = 0; k < count; k++) {
		vec4 a = texelFetch(spans, ivec2(lp.x, k * 2), 0);
		if (a.x >= drawn) {
			continue;
		}
		int rows = int(a.w + 0.5);
		if (lp.y < (rows >> 10) || lp.y > (rows & 1023)) {
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
	vec3 surf;
	float plane = plane_at(dir, sy, lp.x, base, surf);
	// Then the walls the renderer left to the shader in this column, after the
	// ones it drew here (counts.g of them, nearest first).
	int walked = -1;
	vec4 found = vec4(0.0);
	vec4 terms = vec4(0.0);
	if (walls_on) {
		walked = walk_walls(lp, sy, plane, int(counts.g + 0.5), drawn, found, terms);
	}
	// What the nearest surface is, for the lights and weather (surface_light):
	// a floor or ceiling until a wall or a sprite is nearer.
	vec3 nf = vec3(0.0, 0.0, sy < 0.0 ? -1.0 : 1.0);
	vec3 tu = vec3(1.0, 0.0, 0.0);
	vec3 tv = vec3(0.0, 1.0, 0.0);
	vec2 bump = surf.xy;
	float gloss = surf.z;
	int kind = 0;
	if (plane >= drawn) {
		bump = vec2(0.0);
		gloss = 0.0;
		kind = 1;
		nf = -normalize(vec3(dir, 0.0));
		tu = vec3(-nf.y, nf.x, 0.0);
		tv = vec3(0.0, 0.0, -1.0);
		if (walked >= 0) {
			base = walked_at(walked, drawn, found, eye.xy + dir * drawn, bump);
			if (effects_on) {
				wall_frame(terms, dir, drawn, float(lp.x) + 0.5 - float(view_size.x) * 0.5, nf, tu);
			}
		} else if (best >= 0) {
			base = span_at(lp.x, best, best_wz, best_bottom, best_top, eye.xy + dir * drawn, drawn, bump);
		} else if (drawn < 160.0) {
			base = wall_at(lp, bump);
		} else {
			base = sky_at(lp.x, sy);
		}
	}
	float nearest = min(plane, drawn);
	int over_y = lp.y - over_rows.x;
	float cover = over_on && over_y >= 0 && lp.y < over_rows.y ? float(stream_byte(cover_at + over_y * view_size.x + lp.x)) / 255.0 : 0.0;
	if (cover > 0.0) {
		float reach = dist_at(lp, 1);
		// A sprite shows unless a surface the shader drew is in front of it; a ground
		// mark shows only on the surface it lies on.
		bool shown = reach > 0.0 ? nearest > reach - 0.014 : abs(-reach - nearest) < 0.13;
		if (shown) {
			base = floor(texelFetch(colours, ivec2(lp.x, over_row + over_y), 0).rgb * 255.0 + (1.0 - cover) * base + 0.5);
			if (reach > 0.0 && cover > 0.5) {
				bump = vec2(0.0);
				gloss = 0.0;
				kind = 2;
			}
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
			bump = vec2(0.0);
			gloss = 0.0;
			kind = 2;
			nf = -normalize(vec3(dir, 0.0));
			tu = vec3(-nf.y, nf.x, 0.0);
			tv = vec3(0.0, 0.0, -1.0);
		}
	}
	if (effects_on && nearest < 160.0) {
		vec3 p = vec3(eye.xy + dir * nearest, eye.z - sy * nearest / focal);
		base = surface_light(base, p, dir, sy, nearest, nf, tu, tv, bump, gloss, kind);
	} else if (effects_on && fog_banks > 0.0) {
		// Fog banks lie along the treeline against the sky too.
		base = floor(mix(base, fog_color * 255.0, fog_bank(dir, sy, 14.0)));
	}
	if (pane_on && lp.y >= pane_rows.x && lp.y < pane_rows.y) {
		float glass = dist_at(lp, 2);
		if (glass < 160.0 && glass < nearest) {
			base = floor(base * vec3(0.67, 0.78, 0.82) + texelFetch(colours, ivec2(lp.x, pane_row + lp.y - pane_rows.x), 0).rgb * 255.0 * 0.33);
		}
	}
	far = nearest;
	return clamp(base, 0.0, 255.0);
}

// Rain over the view (effects_on, features/weather.gd): streaks falling on a
// slant in three sheets, near, middle and far, on the 320-wide grid whatever
// the detail, each streak shown only where the open sky is over it at its own
// distance and nothing nearer stands in front.
vec3 rain_over(vec3 base, ivec2 fine, float far) {
	vec2 q = (vec2(fine) + 0.5) / float(view_mul);
	ivec2 lp = fine / view_div;
	vec2 dir = fwd + side * ((float(lp.x) + 0.5 - float(view_size.x) * 0.5) / focal);
	// Turning carries the rain round with the world, not with the screen.
	float f320 = focal * 320.0 / float(view_size.x);
	float turn = mod(view_angle, 6.2831853) * f320;
	vec3 drop = min(vec3(124.0, 134.0, 148.0) * (1.0 + lightning * 0.9), vec3(255.0));
	for (int k = 0; k < 3; k++) {
		float depth = k == 0 ? 1.3 : (k == 1 ? 2.8 : 6.0);
		if (far <= depth) {
			break;
		}
		float cw = k == 0 ? 7.0 : (k == 1 ? 5.0 : 4.0);
		float len = k == 0 ? 10.0 : (k == 1 ? 7.0 : 4.0);
		float speed = k == 0 ? 330.0 : (k == 1 ? 250.0 : 180.0);
		float seg_len = len * 3.5;
		float v = q.y - anim_time * speed;
		float u = q.x + turn + v * 0.18;
		float col = mod(floor(u / cw), floor(6.2831853 * f320 / cw));
		float seg = floor(v / seg_len);
		float h = hash12(vec2(col, seg) + float(k) * 41.0);
		if (h > rain * (k == 0 ? 0.3 : 0.5)) {
			continue;
		}
		float in_v = v - seg * seg_len;
		float yo = floor(fract(h * 53.3) * (seg_len - len));
		if (floor(u - floor(u / cw) * cw) != floor(fract(h * 91.7) * (cw - 1.0)) || in_v < yo || in_v >= yo + len) {
			continue;
		}
		if (!open_sky(eye.xy + dir * depth)) {
			continue;
		}
		float a = (k == 0 ? 0.32 : (k == 1 ? 0.24 : 0.16)) * (0.55 + 0.45 * (in_v - yo) / len);
		base = mix(base, max(base, drop), a);
	}
	return base;
}

// How far the air over a hot thing sways this pixel (haze_box), in fine
// pixels across: a chunky shimmer, strongest low and in the middle.
int haze_shift(ivec2 fine) {
	ivec2 lp = fine / view_div;
	float shift = 0.0;
	for (int i = 0; i < haze_count; i++) {
		vec4 b = haze_box[i];
		float across = (float(lp.x) + 0.5 - b.x) / max(b.z, 1.0);
		float up = (b.y - float(lp.y) - 0.5) / max(b.w, 1.0);
		if (abs(across) >= 1.0 || up < 0.0 || up >= 1.0) {
			continue;
		}
		float fade = (1.0 - across * across) * (1.0 - up) * min(up * 6.0, 1.0);
		shift += sin(float(lp.y) * 0.6 + anim_time * 8.0 + float(i) * 2.1) * haze_amp[i] * fade;
	}
	return int(floor(shift + 0.5)) * view_div;
}

// The finished view pixel: the weapon and HUD layer over the view.
vec3 picture_at(ivec2 px, ivec2 fine, vec3 frame) {
	vec4 o = texelFetch(post_tex, px, 0);
	if (o.a >= 1.0) {
		return o.rgb * 255.0;
	}
	vec3 under = vec3(0.0);
	if (scene_on && px.y < 156) {
		if (haze_count > 0) {
			fine.x = clamp(fine.x + haze_shift(fine), 0, 320 * view_mul - 1);
		}
		float far;
		under = view_at(fine, far);
		if (effects_on && rain > 0.0 && motion > 0.0) {
			under = rain_over(under, fine, far);
		}
	} else if (base_on) {
		under = frame;
	}
	return floor(o.rgb * 255.0 + (1.0 - o.a) * under + 0.5);
}

void fragment() {
	ivec2 px = ivec2(UV * vec2(320.0, 200.0));
	ivec2 fine = ivec2(UV * vec2(320.0, 200.0) * float(view_mul));
	ivec2 sub = fine - px * view_mul;
	vec3 c;
	if (overlay_on) {
		if (drunk > 0.0 && px.y < 156) {
			// game.gd _drunk_warp(): per-row shear, ghost double image, amber tint.
			int shift = int(floor(sin(float(px.y) * 0.16 + drunk_phase) * (1.0 + 3.4 * drunk) + 0.5));
			int sx = (px.x + shift + 640) % 320;
			int gx = (px.x - drunk_ghost + shift + 640) % 320;
			float blend = 0.30 * drunk;
			vec3 v = picture_at(ivec2(sx, px.y), ivec2(sx, px.y) * view_mul + sub, texelFetch(TEXTURE, ivec2(sx, px.y), 0).rgb * 255.0) * (1.0 - blend)
					+ picture_at(ivec2(gx, px.y), ivec2(gx, px.y) * view_mul + sub, texelFetch(TEXTURE, ivec2(gx, px.y), 0).rgb * 255.0) * blend;
			c = floor(vec3(v.r * (1.0 + 0.06 * drunk), v.g, v.b * (1.0 - 0.10 * drunk)));
		} else {
			c = picture_at(px, fine, texelFetch(TEXTURE, px, 0).rgb * 255.0);
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
			// On the view's own grid: in HD each of a 320x200 pixel's four gets its
			// own grain (another of the six frames) and dither, so the look does not
			// blur HD back to 320 wide. At HIGH (view_mul 1) this is the 320 grid.
			vec2 at = (vec2(fine) + 0.5) / float(view_mul) - 0.5;
			vec2 n = (at / vec2(319.0, 155.0) - 0.5) * 2.0;
			float vignette = 1.0 - 0.13 * pow(length(n) / 1.4142, 2.1);
			int frame_k = (grain_frame + sub.x + 2 * sub.y) % 6;
			float g = texelFetch(looks, ivec2(frame_k * 156 + px.y, GRAIN_ROW + px.x), 0).r * 255.0;
			float add = g - 2.0 + blast + (BAYER[(fine.x % 4) * 4 + (fine.y % 4)] / 16.0 - 0.5) * 6.0;
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
