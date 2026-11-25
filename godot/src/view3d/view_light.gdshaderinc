// The 3D view's shared lighting: the old renderer's distance shading and,
// with LIGHTS AND GLOW (effects_on), the old view shader's surface_light (the
// frame's lights with relief and pools, the level's grade and fog, the rain's
// wet sheen, the lightning). Points are in MAP terms: (x east, y south, z up),
// which is Godot's (x, z, y). Colours are 0-255.
//
// The frame's numbers and the view's textures are global uniforms
// (project.godot [shader_globals], set by world_view.gd _share) and its lists
// rows of view_data (view_row), so no material changes from one frame to the
// next: handing each of the view's ~80 materials the frame's numbers cost
// more than 0.5 ms a frame (pass 10). Every texture is read with texelFetch
// (a global sampler takes no filter hint). A material's own numbers stay
// plain uniforms; no view3d shader has instance uniforms (each model part
// has a material of its own instead: the instance buffer fits 60 parts on
// WebGL and many phones).

global uniform bool effects_on;
global uniform vec3 eye;
global uniform int light_count;
// The frame's lists (world_view.gd _rows), a row each of up to 16 texels of
// RGBA32F: the lights' places and reaches, colours and strengths, flags (low
// and high 16 bits), the wading rings, the moving tiles, SHADOWS' pairs and
// blobs, the flowing floors (x, y their tiles, z, w their shifts).
global uniform sampler2D view_data;
const int ROW_LIGHT_POS = 0;
const int ROW_LIGHT_COL = 1;
const int ROW_LIGHT_FLAGS = 2;
const int ROW_RINGS = 3;
const int ROW_ANIMS = 4;
const int ROW_SHADOW_A = 5;
const int ROW_SHADOW_B = 6;
const int ROW_BLOBS = 7;
const int ROW_FLOW = 8;
// The plank walls shot about (features/wall_looks.gd view_rows): rows 9 and
// 11 their cells (x, y, ground, height; x of -1 ends the list), 10 and 12
// their planks (world_body.gdshaderinc plank_damage).
const int ROW_PLANK0 = 9;
const int ROW_PLANK1 = 10;
const int ROW_PLANK2 = 11;
const int ROW_PLANK3 = 12;
// A blackout (features/county_events.gd): the share of the light gone, before
// the lights (a flashlight's beam, a lantern) add theirs.
global uniform float blackout;
// The moon's rim (world_view.gd _moon_rim): in the night chapter and a
// blackout, what stands in the dark (the enemies' silhouette edges, a
// pickup's outline) catches the sky's cool light, rgb its colour, a how
// strong (0: none). Added past the fog's share, never darkened by a blackout.
global uniform vec4 moon_rim;
global uniform vec3 fog_color;
global uniform vec3 fog_range;
global uniform vec3 grade;
global uniform float lightning;
global uniform vec2 flash_dir;
global uniform float rain;
global uniform float wet;
// The puddles' water (0 to 1: more and bigger the longer it rains) and the
// wind (features/climate.gd): xy the way it blows (cells a second), z how
// hard it gusts (1 calm).
global uniform float pool;
global uniform vec3 wind_now;
global uniform float fog_banks;
global uniform float motion;
global uniform float anim_time;
global uniform int anim_count;
// The cells: r the area's tint index (unused here), g 255 under the open sky.
global uniform sampler2D cells_tex;
global uniform ivec2 map_size;
// One texel a tile: r water, g relief (signed, 128 flat), b puddles.
global uniform sampler2D tile_info_tex;
// The mirror (one level's washroom): its line x = mirror_x. The camera that
// draws the reflection (world_view.gd) sees the layer MIRROR_LAYER, and in
// its pass nothing on the far side of the mirror, nor the mirror, is drawn.
global uniform bool mirror_on;
global uniform float mirror_x;
const uint MIRROR_LAYER = 524288u;
// The sky (sky_at) and what it needs of the camera: the view's size, the
// focal length and the horizon row (view pixels), the view angle.
global uniform sampler2D sky_tex;
global uniform float view_angle;
global uniform float horizon;
global uniform float focal;
global uniform vec2 view_size;
global uniform float res_up;
global uniform float sky_drift;
// The rings bodies leave wading (features/water.gd): x, y, age, size.
global uniform int ring_count;
// The Crossroads' water tower shadow and runoff (render_state.gd hub_fx).
global uniform bool hub_fx;
global uniform int hub_runoff;
global uniform int hub_patch;
global uniform int hub_wall;
global uniform bool shadow_still;
global uniform float shadow_gust;
global uniform float shadow_lx;
global uniform float shadow_ly;
global uniform float water_drift;
// County Run's storm front (world_view.gd _storm): the ring's middle (xy), its
// radius (z) and how hard it blows (w; 0: no storm). Outside it the world is
// dimmer, and the eye's line fogs for as far as it runs through the storm.
global uniform vec4 storm_ring;
// SHADOWS (view_shadows.gd): what the strong lights throw on the level's
// floors and walls. Each pair is one body's segment from a (xyz) to b (xyz),
// a.w its radius, b.w the light (an index into light_pos) it stands in. Each
// blob is the sky's soft shadow under a body: x, y, the floor's z, radius.
uniform int shadow_count = 0;
uniform int blob_count = 0;

const float RELIEF_FAR = 10.0;
const float RELIEF_K = 1.5;
const float RELIEF_SKY = 0.45;
const float POOL_REACH = 0.36;
// Sky rows over which the panorama's top fades into its zenith (sky_at).
const float ZENITH_FADE = 10.0;
const vec3 SKY_LIGHT = vec3(-0.33, -0.42, 0.85);

vec4 view_row(int row, int i) {
	return texelFetch(view_data, ivec2(i, row), 0);
}

int light_flag(int i) {
	vec4 f = view_row(ROW_LIGHT_FLAGS, i);
	return int(f.x) | (int(f.y) << 16);
}

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec4 tile_info(int tile) {
	vec4 info = texelFetch(tile_info_tex, ivec2(tile, 0), 0);
	info.g = (info.g * 255.0 - 128.0) / 127.0;
	return info;
}

bool open_sky(vec2 at) {
	ivec2 cell = ivec2(floor(at));
	if (cell.x < 0 || cell.y < 0 || cell.x >= map_size.x || cell.y >= map_size.y) {
		return true;
	}
	return texelFetch(cells_tex, cell, 0).g > 0.5;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// The sky in view column `column`, sy rows below the horizon (negative above).
// The panorama's top as one colour: its second row's mean (eight columns).
vec3 sky_zenith() {
	vec3 sum = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		sum += texelFetch(sky_tex, ivec2(i * 64 + 32, 1), 0).rgb;
	}
	return sum * (255.0 / 8.0);
}

vec3 sky_at(int column, float sy) {
	float ray = (float(column) + 0.5 - view_size.x * 0.5) / focal;
	int sx = int((view_angle + atan(ray)) * 81.48733086305042) & 511;
	float row = 93.0 + sy * res_up * 0.95;
	int sr = clamp(int(row), 0, 115);
	// Looking well up runs past the panorama's top row: fade into the zenith
	// from its fourth row over ZENITH_FADE rows, rather than smear the top row
	// up the view in streaks.
	float over = clamp((4.0 - row) / ZENITH_FADE, 0.0, 1.0);
	if (!effects_on) {
		vec3 flat_sky = texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
		return over > 0.0 ? mix(flat_sky, sky_zenith(), over) : flat_sky;
	}
	float lift = clamp(1.0 - float(sr) / 88.0, 0.0, 1.0);
	sx = (sx + int(sky_drift * 512.0 * lift)) & 511;
	vec3 sky = texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
	if (over > 0.0) {
		sky = mix(sky, sky_zenith(), over);
	}
	return min(sky * (1.0 + lightning * 1.8 * (0.4 + lift)) + vec3(18.0, 20.0, 30.0) * lightning, vec3(255.0));
}

float wading_rings(vec2 at) {
	float glint = 0.0;
	for (int i = 0; i < ring_count; i++) {
		vec4 r = view_row(ROW_RINGS, i);
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

float rain_rings(vec2 at, float tm) {
	if (rain <= 0.0) {
		return 0.0;
	}
	vec2 g = floor(at * 3.0);
	float phase = hash12(g + 5.3);
	float beat = tm * 1.5 + phase;
	float cycle = floor(beat);
	float h = hash12(g + cycle * 3.71);
	if (h > rain * (0.8 + 0.2 * pool)) {
		return 0.0;
	}
	float age = fract(beat);
	vec2 c = (g + 0.25 + 0.5 * vec2(fract(h * 7.13), fract(h * 13.7))) / 3.0;
	float band = 1.0 - abs(distance(at, c) - age * 0.13) / 0.028;
	return band > 0.0 ? (1.0 - age) * (band > 0.5 ? 0.9 : 0.45) : 0.0;
}

// A water floor or a puddle over the floor's lit colour (the old view shader
// water_over): a broken reflection of the sky, glints, wading and rain rings.
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
	glint = max(glint, wading_rings(q) * 1.2);
	glint = max(glint, rain_rings(q, tm) * 0.8);
	return out_colour + vec3(84.0, 92.0, 100.0) * glint * (0.45 + 0.5 * min(light, 1.2));
}

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

vec3 running_water(vec3 rgb, float x, float y) {
	float edge = clamp(min(y - 49.0, 51.0 - y) * 1.9, 0.0, 1.0);
	float wave = sin(13.0 * y + 1.7 * sin(x * 2.1 - water_drift) + 0.8 * sin(x * 4.3 - water_drift * 1.6));
	float streak = sin(x * 6.7 - water_drift * 3.0 + 0.8 * sin(y * 22.0));
	float ripples = clamp((wave + 0.36 * streak - 0.63) * 0.62, 0.0, 0.62) * edge;
	float mix_ = edge * 0.38 + ripples * 0.52;
	vec3 water = vec3(88.0 + ripples * 154.0, 120.0 + ripples * 150.0, 132.0 + ripples * 123.0);
	return floor(rgb * (1.0 - mix_) + water * mix_ + 0.5);
}

// True in the mirror's pass for a point the reflection must not show: on
// the mirror's far side from the eye, or on the mirror itself (the old
// renderer skipped everything up to .008 past the line).
bool mirror_clipped(vec3 p, uint layers) {
	if (!mirror_on || (layers & MIRROR_LAYER) == 0u) {
		return false;
	}
	return (p.x - mirror_x) * sign(eye.x - mirror_x) < 0.008;
}

// The worn photograph's colour the cels and prop pictures were graded with
// as they were shrunk (tools/art/paint.gd photo_shrink): a little less
// saturated, more contrast round .42 and lifted; the brightest left alone.
// c is 0-255.
vec3 photo_grade(vec3 c) {
	vec3 x = c / 255.0;
	if (max(x.r, max(x.g, x.b)) > 0.93) {
		return c;
	}
	float grey = (x.r + x.g + x.b) / 3.0;
	x = vec3(grey) + (x - vec3(grey)) * 0.86;
	x = (x - vec3(0.42)) * 1.18 + vec3(0.52);
	return clamp(x, 0.0, 1.0) * 255.0;
}

// The old renderer's light_at(): the light falls off with the distance ahead,
// stops at .19 and is stepped in 32nds.
float stepped_light(float light, float t) {
	float shade = max(0.19, light / (1.0 + 0.102 * t));
	return float(min(int(shade * 32.0 + 0.5), 96)) / 32.0;
}

// How lit a moving tile is this moment (1 for a tile that does not move).
float anim_light(int tile) {
	for (int i = 0; i < anim_count; i++) {
		vec4 a = view_row(ROW_ANIMS, i);
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

// SHADOWS are worked out on a grid of SHADOW_GRID blocks a cell, their soft
// edges dithered on that grid (a 2x2 ordered pattern): chunky, as a 1997
// low-res shadow map was. In a body's shadow a light keeps SHADOW_LEFT of
// what it gives and the surface's own light loses up to SHADOW_DIM (a full
// strength light, close); under a blob the sky's light loses BLOB_DARK.
const float SHADOW_GRID = 10.0;
const float SHADOW_LEFT = 0.12;
const float SHADOW_DIM = 0.6;
const float BLOB_DARK = 0.5;
// What the storm's veil fades to.
const vec3 STORM_FOG = vec3(30.0, 32.0, 40.0);

// The middle of the shadow block p lies in (pushed a hair off its surface).
vec3 shadow_block(vec3 p, vec3 n) {
	return (floor((p + n * 0.02) * SHADOW_GRID) + 0.5) / SHADOW_GRID;
}

// The dither threshold of the block q on a surface facing n (0 to 1).
float shadow_dither(vec3 q, vec3 n) {
	vec2 g = abs(n.z) > 0.5 ? q.xy : vec2(q.x + q.y, q.z);
	ivec2 gi = ivec2(floor(g * SHADOW_GRID));
	return (float(((gi.x & 1) * 2) ^ ((gi.y & 1) * 3)) + 0.5) / 4.0;
}

// How much of the line from q to the light l a body (segment a.xyz to b,
// radius a.w) covers: 1 squarely in its shadow, 0 clear.
float shadow_cover(vec3 q, vec3 l, vec4 a, vec3 b) {
	vec3 d1 = l - q;
	vec3 d2 = b - a.xyz;
	vec3 r = q - a.xyz;
	float aa = max(dot(d1, d1), 1e-6);
	float e = max(dot(d2, d2), 1e-6);
	float f = dot(d2, r);
	float c = dot(d1, r);
	float bb = dot(d1, d2);
	float den = aa * e - bb * bb;
	float s = den > 1e-6 ? clamp((bb * f - c * e) / den, 0.0, 1.0) : 0.0;
	float t = (bb * s + f) / e;
	if (t < 0.0) {
		t = 0.0;
		s = clamp(-c / aa, 0.0, 1.0);
	} else if (t > 1.0) {
		t = 1.0;
		s = clamp((bb - c) / aa, 0.0, 1.0);
	}
	float dist = length(q + d1 * s - a.xyz - d2 * t);
	return 1.0 - smoothstep(a.w * 0.6, a.w * 1.15, dist);
}

// The sky's soft shadow under the bodies at floor point p: 0 none, 1 full.
float blob_shadow(vec3 p, vec3 nf) {
	vec3 q = shadow_block(p, nf);
	float th = shadow_dither(q, nf);
	float dark = 0.0;
	for (int k = 0; k < blob_count; k++) {
		vec4 b = view_row(ROW_BLOBS, k);
		if (abs(p.z - b.z) > 0.25) {
			continue;
		}
		float cover = 1.0 - smoothstep(0.45, 1.0, length(q.xy - b.xy) / b.w);
		if (cover > th) {
			dark = max(dark, cover > 0.85 ? 1.0 : 0.65);
		}
	}
	return dark;
}

// How far the eye's line to p runs through the storm, as the veil it lays
// over p (0 none, at most .82): a ring of radius storm_ring.z round its xy.
float storm_veil(vec3 p) {
	vec2 d = p.xy - eye.xy;
	float a = dot(d, d);
	if (a < 1e-6) {
		return 0.0;
	}
	vec2 f = eye.xy - storm_ring.xy;
	float b = 2.0 * dot(f, d);
	float c = dot(f, f) - storm_ring.z * storm_ring.z;
	float disc = b * b - 4.0 * a * c;
	float inside = 0.0;
	if (disc > 0.0) {
		float root = sqrt(disc);
		inside = clamp((-b + root) / (2.0 * a), 0.0, 1.0) - clamp((-b - root) / (2.0 * a), 0.0, 1.0);
	}
	float through = sqrt(a) * (1.0 - inside);
	return min(0.82, 1.0 - exp(-through * (0.06 + 0.1 * storm_ring.w)));
}

vec3 lights_at(vec3 p, vec3 nf, vec3 nb, bool ground, float gloss, vec3 view, int kind) {
	// Each light's share left by the bodies standing in it (the level's own
	// floors and walls only: a body would shadow itself).
	// A strong light's shadow also darkens what the room's own light gives
	// (as a 1997 shadow decal did): `dim`, by the light's strength and how
	// near it is.
	float shade[16];
	float dim = 1.0;
	bool shadowed = kind < 2 && shadow_count > 0;
	if (shadowed) {
		for (int i = 0; i < 16; i++) {
			shade[i] = 1.0;
		}
		vec3 q = shadow_block(p, nf);
		float th = shadow_dither(q, nf);
		for (int k = 0; k < shadow_count; k++) {
			vec4 sb = view_row(ROW_SHADOW_B, k);
			int li = int(sb.w + 0.5);
			vec4 at = view_row(ROW_LIGHT_POS, li);
			float near = 1.0 - distance(at.xyz, q) / at.w;
			if (li >= light_count || near <= 0.0) {
				continue;
			}
			if (shadow_cover(q, at.xyz, view_row(ROW_SHADOW_A, k), sb.xyz) > th) {
				shade[li] = SHADOW_LEFT;
				dim = min(dim, 1.0 - SHADOW_DIM * clamp(view_row(ROW_LIGHT_COL, li).a * 1.6, 0.0, 1.0) * sqrt(near));
			}
		}
	}
	vec3 sum = vec3(0.0);
	for (int i = 0; i < light_count; i++) {
		vec4 at = view_row(ROW_LIGHT_POS, i);
		vec3 d = at.xyz - p;
		float dist = length(d);
		float reach = clamp(1.0 - dist / at.w, 0.0, 1.0);
		if (reach <= 0.0) {
			continue;
		}
		vec3 l = d / max(dist, 0.001);
		float fall = reach * reach;
		float shine = reach;
		int fl = light_flag(i);
		if ((fl & 2) != 0) {
			// A spot (a flashlight): its way and cone packed in its flags
			// (event_dark.gd spot_flags). A hot middle, a ring, a soft edge,
			// in steps as a 1997 light map would have it; it carries further.
			float yaw = float((fl >> 8) & 1023) / 1024.0 * 6.2831853;
			float tilt = float((fl >> 18) & 511) / 511.0 * 3.1415927 - 1.5707963;
			float cone = float((fl >> 27) & 15) / 15.0 * 0.8 + 0.05;
			vec3 axis = vec3(cos(yaw) * cos(tilt), sin(yaw) * cos(tilt), sin(tilt));
			float c = dot(-l, axis);
			float beam = smoothstep(cos(cone), cos(cone * 0.62), c);
			float hot = smoothstep(cos(cone * 0.34), cos(cone * 0.12), c);
			float ring = smoothstep(cos(cone * 0.7), cos(cone * 0.6), c) * (1.0 - smoothstep(cos(cone * 0.5), cos(cone * 0.4), c));
			beam = floor((beam * 0.7 + hot * 0.6 + ring * 0.2) * 5.0 + 0.5) / 5.0;
			fall = sqrt(reach) * beam;
			shine = reach * beam;
		}
		float k = fall * max(0.0, 1.0 + RELIEF_K * (dot(nb, l) - dot(nf, l)));
		if (gloss > 0.0) {
			k += gloss * shine * pow(max(dot(nb, normalize(l + view)), 0.0), 24.0) * 2.2;
		}
		if (ground && (fl & 1) != 0) {
			float q = clamp(1.0 - length(d.xy) / (at.w * POOL_REACH), 0.0, 1.0);
			k += floor(q * 3.0 + 0.999) / 3.0 * 0.85;
		}
		vec4 col = view_row(ROW_LIGHT_COL, i);
		sum += col.rgb * col.a * k * (shadowed ? shade[i] : 1.0);
	}
	return sum + vec3(dim - 1.0);
}

float fog_bank(vec3 p, float reach, float t) {
	vec2 dir = normalize(p.xy - eye.xy + vec2(1e-5));
	vec2 q = eye.xy + dir * reach;
	float tm = anim_time * motion;
	float roll = 0.5 + 0.28 * sin(q.x * 0.21 + tm * 0.05 + sin(q.y * 0.13) * 1.7) + 0.22 * sin(q.y * 0.17 - tm * 0.037 + q.x * 0.07);
	float ray_z = eye.z + (p.z - eye.z) * reach / max(t, 0.001);
	float high = ray_z - (eye.z - 0.95);
	float low = clamp(1.4 - high, 0.0, 1.0);
	return fog_banks * smoothstep(0.56, 0.9, roll) * low * smoothstep(3.0, 9.0, reach);
}

// How much of the fog's colour lies over a point t ahead (0 to 1).
float fog_share(vec3 p, float t) {
	float soak = 1.0 - 0.12 * rain;
	float fog = min(fog_range.z + 0.06 * rain, 1.0) * smoothstep(fog_range.x * soak, fog_range.y * soak, t);
	if (fog_banks > 0.0) {
		fog = fog + (1.0 - fog) * fog_bank(p, min(t, 14.0), t);
	}
	return fog;
}

// The moon's rim on colour (0-255) at point p, t ahead, `edge` (0 to 1) of
// it: stepped in thirds, as a 1997 light map would have it, and thinned by
// the fog (and the storm's veil) the eye looks through.
vec3 moon_rim_on(vec3 colour, vec3 p, float t, float edge) {
	if (moon_rim.a <= 0.0 || edge <= 0.0) {
		return colour;
	}
	float k = floor(clamp(edge, 0.0, 1.0) * 3.0 + 0.5) / 3.0;
	float clear = 1.0 - fog_share(p, t);
	if (storm_ring.w > 0.0) {
		clear *= 1.0 - storm_veil(p);
	}
	return min(floor(colour + moon_rim.rgb * 255.0 * moon_rim.a * k * clear), vec3(255.0));
}

// A hand's own rim on colour (0-255) at point p, t ahead, `edge` (0 to 1) of
// it (pass 15, actor.gdshader): `rim` rgb its colour (0-1), a how much of it
// up close; `reach` x how much at reach.z cells and beyond (rising from
// reach.y), w the share of the fog it shows through. Stepped in thirds as the
// moon's rim is, never weaker than the moon's by night, and laid over the
// colour (not added: a hand in daylight keeps an edge of it too).
vec3 own_rim_on(vec3 colour, vec3 p, float t, float edge, vec4 rim, vec4 reach) {
	if (rim.a <= 0.0 || edge <= 0.0) {
		return colour;
	}
	float k = floor(clamp(edge, 0.0, 1.0) * 3.0 + 0.5) / 3.0;
	float most = max(mix(rim.a, reach.x, smoothstep(reach.y, reach.z, t)), moon_rim.a);
	float clear = 1.0 - fog_share(p, t) * (1.0 - reach.w);
	if (storm_ring.w > 0.0) {
		clear *= 1.0 - storm_veil(p);
	}
	vec3 hot = rim.rgb * 255.0;
	return floor(mix(colour, max(colour, hot), k * most * clear));
}

// the old view shader surface_light(): kind 0 a floor or ceiling, 1 a wall, 2 a
// sprite. t is the distance ahead (the old renderer's `nearest`).
vec3 surface_light(vec3 base, vec3 p, float t, vec3 nf, vec3 tu, vec3 tv, vec2 bump, float gloss, int kind) {
	vec3 nb = (bump.x != 0.0 || bump.y != 0.0) ? normalize(nf - bump.x * tu - bump.y * tv) : nf;
	bool ground = kind == 0 && nf.z > 0.0;
	bool outside = false;
	vec2 dir = normalize(p.xy - eye.xy + vec2(1e-5));
	if (rain > 0.0 || wet > 0.0 || lightning > 0.0) {
		outside = open_sky(p.xy - dir * 0.02);
	}
	if (outside && wet > 0.0 && kind == 1) {
		float run_at = floor(dot(p.xy, tu.xy) * 18.0);
		float h = hash12(vec2(run_at, 3.0));
		float flow = fract(p.z * 1.3 + anim_time * motion * 0.7 + h * 7.0);
		base *= 1.0 - 0.14 * wet;
		if (h < 0.22 && flow < 0.35) {
			base += vec3(26.0, 28.0, 32.0) * wet * (1.0 - flow / 0.35);
		}
		gloss = max(gloss, 0.5 * wet);
	}
	if (nb != nf) {
		vec3 sun = normalize(SKY_LIGHT);
		base *= 1.0 + RELIEF_SKY * (dot(nb, sun) - dot(nf, sun));
	}
	if (ground && blob_count > 0) {
		base = floor(base * (1.0 - BLOB_DARK * blob_shadow(p, nf)));
	}
	if (blackout > 0.0) {
		base = floor(base * (1.0 - blackout));
	}
	if (light_count > 0 && t < 160.0) {
		vec3 view = normalize(eye - p);
		base = min(floor(base * (vec3(1.0) + lights_at(p, nf, nb, ground, outside ? gloss : gloss * 0.5, view, kind))), vec3(255.0));
	}
	base = min(base * grade * (outside ? 1.0 - 0.05 * rain : 1.0), vec3(255.0));
	float veil = 0.0;
	if (storm_ring.w > 0.0) {
		// Under the storm, out past its wall: darker, and veiled the farther
		// the eye's line runs through it.
		float out_p = length(p.xy - storm_ring.xy) - storm_ring.z;
		base = floor(base * (1.0 - 0.38 * smoothstep(-0.5, 5.0, out_p)));
		veil = storm_veil(p);
	}
	if (lightning > 0.0) {
		vec3 toward = normalize(vec3(flash_dir, 1.1));
		float lift = outside ? 0.4 + 0.5 * clamp(dot(nb, toward), 0.0, 1.0) + gloss * 0.2 : 0.14;
		base = min(base * (vec3(1.0) + lightning * lift * vec3(0.86, 0.93, 1.12)), vec3(255.0));
	}
	float fog = fog_share(p, t);
	base = mix(base, fog_color * 255.0 * (1.0 - blackout * 0.75), fog);
	if (veil > 0.0) {
		base = mix(base, min(STORM_FOG * (1.0 + lightning * 1.6), vec3(255.0)), veil);
	}
	return floor(base);
}

// The picture's colour (0-255) as the frame buffer wants it: the
// Compatibility renderer writes an unshaded ALBEDO into the view's 8-bit
// target as it is, so the old renderer's bytes come out unchanged.
vec3 to_output(vec3 c) {
	return clamp(c / 255.0, 0.0, 1.0);
}
