// The 3D view's shared lighting: the old renderer's distance shading and,
// with LIGHTS AND GLOW (effects_on), the old view shader's surface_light (the
// frame's lights with relief and pools, the level's grade and fog, the rain's
// wet sheen, the lightning). Points are in MAP terms: (x east, y south, z up),
// which is Godot's (x, z, y). Colours are 0-255.

uniform bool effects_on = false;
uniform vec3 eye = vec3(0.0);
uniform int light_count = 0;
uniform vec4 light_pos[16];
uniform vec4 light_col[16];
uniform int light_flags[16];
uniform vec3 fog_color = vec3(0.0);
uniform vec3 fog_range = vec3(1000.0, 2000.0, 0.0);
uniform vec3 grade = vec3(1.0);
uniform float lightning = 0.0;
uniform vec2 flash_dir = vec2(0.6, -0.8);
uniform float rain = 0.0;
uniform float wet = 0.0;
uniform float fog_banks = 0.0;
uniform float motion = 1.0;
uniform float anim_time = 0.0;
uniform int anim_count = 0;
uniform vec4 anims[8];
// The cells: r the area's tint index (unused here), g 255 under the open sky.
uniform sampler2D cells_tex : filter_nearest, repeat_disable;
uniform ivec2 map_size = ivec2(1);
// One texel a tile: r water, g relief (signed, 128 flat), b puddles.
uniform sampler2D tile_info_tex : filter_nearest, repeat_disable;
// The mirror (one level's washroom): its line x = mirror_x. The camera that
// draws the reflection (world_view.gd) sees the layer MIRROR_LAYER, and in
// its pass nothing on the far side of the mirror, nor the mirror, is drawn.
uniform bool mirror_on = false;
uniform float mirror_x = 0.0;
const uint MIRROR_LAYER = 524288u;
// The sky (sky_at) and what it needs of the camera: the view's size, the
// focal length and the horizon row (view pixels), the view angle.
uniform sampler2D sky_tex : filter_nearest, repeat_disable;
uniform float view_angle = 0.0;
uniform float horizon = 78.0;
uniform float focal = 230.0;
uniform vec2 view_size = vec2(320.0, 156.0);
uniform float res_up = 1.0;
uniform float sky_drift = 0.0;
// The rings bodies leave wading (features/water.gd): x, y, age, size.
uniform int ring_count = 0;
uniform vec4 rings[16];
// The Crossroads' water tower shadow and runoff (render_state.gd hub_fx).
uniform bool hub_fx = false;
uniform int hub_runoff = -1;
uniform int hub_patch = -1;
uniform int hub_wall = -1;
uniform bool shadow_still = false;
uniform float shadow_gust = 0.0;
uniform float shadow_lx = 1.15;
uniform float shadow_ly = 0.73;
uniform float water_drift = 0.0;

const float RELIEF_FAR = 10.0;
const float RELIEF_K = 1.5;
const float RELIEF_SKY = 0.45;
const float POOL_REACH = 0.36;
const vec3 SKY_LIGHT = vec3(-0.33, -0.42, 0.85);

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
vec3 sky_at(int column, float sy) {
	float ray = (float(column) + 0.5 - view_size.x * 0.5) / focal;
	int sx = int((view_angle + atan(ray)) * 81.48733086305042) & 511;
	int sr = clamp(int(93.0 + sy * res_up * 0.95), 0, 115);
	if (!effects_on) {
		return texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
	}
	float lift = clamp(1.0 - float(sr) / 88.0, 0.0, 1.0);
	sx = (sx + int(sky_drift * 512.0 * lift)) & 511;
	vec3 sky = texelFetch(sky_tex, ivec2(sx, sr), 0).rgb * 255.0;
	return min(sky * (1.0 + lightning * 1.8 * (0.4 + lift)) + vec3(18.0, 20.0, 30.0) * lightning, vec3(255.0));
}

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
	if (light_count > 0 && t < 160.0) {
		vec3 view = normalize(eye - p);
		base = min(floor(base * (vec3(1.0) + lights_at(p, nf, nb, ground, outside ? gloss : gloss * 0.5, view))), vec3(255.0));
	}
	base = min(base * grade * (outside ? 1.0 - 0.05 * rain : 1.0), vec3(255.0));
	if (lightning > 0.0) {
		vec3 toward = normalize(vec3(flash_dir, 1.1));
		float lift = outside ? 0.4 + 0.5 * clamp(dot(nb, toward), 0.0, 1.0) + gloss * 0.2 : 0.14;
		base = min(base * (vec3(1.0) + lightning * lift * vec3(0.86, 0.93, 1.12)), vec3(255.0));
	}
	float soak = 1.0 - 0.12 * rain;
	float fog = min(fog_range.z + 0.06 * rain, 1.0) * smoothstep(fog_range.x * soak, fog_range.y * soak, t);
	if (fog_banks > 0.0) {
		fog = fog + (1.0 - fog) * fog_bank(p, min(t, 14.0), t);
	}
	return floor(mix(base, fog_color * 255.0, fog));
}

// The picture's colour (0-255) as the frame buffer wants it: the
// Compatibility renderer writes an unshaded ALBEDO into the view's 8-bit
// target as it is, so the old renderer's bytes come out unchanged.
vec3 to_output(vec3 c) {
	return clamp(c / 255.0, 0.0, 1.0);
}
