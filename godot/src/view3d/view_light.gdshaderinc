// The 3D view's shared lighting: the old renderer's distance shading and,
// with LIGHTS AND GLOW (effects_on), palette.gdshader's surface_light (the
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

// palette.gdshader surface_light(): kind 0 a floor or ceiling, 1 a wall, 2 a
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
