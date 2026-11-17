// A county event's twister (src/event_twister.gd) as the 3D view shows it,
// three parts on one shader (world_view.gd _twister stands them each frame):
//   part 0  the funnel: a rope of churning cloud from the wall cloud down to
//           the ground, narrow at its foot and flaring at its top, bent and
//           swaying, its bands spiralling up and round fast; dust brown low
//           down, storm grey high up, its edges thicker than its middle (more
//           of it in the line of sight), boards and tin whirled round in it
//           as black silhouettes;
//   part 1  the debris cloud round its foot: a squat skirt of dirt and junk
//           churning outward;
//   part 2  the wall cloud it hangs from: a great dark disc turning slowly.
// Posterised into a few steps, dithered along the streaks of its own spin (a
// 1997 palette's look). Forming and lifting (`strength` under 1) the rope
// shows only from the cloud down to where it has reached. See-through, so a
// shader of its own (it writes ALPHA).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform int part = 0;
// 0 a rope high in the cloud .. 1 on the ground in full.
uniform float strength = 1.0;
// How tall (cells), its radius at the foot and the top, which way it leans.
uniform float tall = 30.0;
uniform float foot_r = 0.6;
uniform float top_r = 9.5;
uniform vec2 lean = vec2(0.0);
uniform float base_z = 0.0;

varying vec3 map_p;
varying float up01;
varying float around;
varying vec3 axis_p;

// The rope's middle at height h (0..1 of `tall`), off its foot: bent by the
// lean and swaying in a slow S.
vec2 bend(float h, float tm) {
	float sway = sin(h * 3.1 + tm * 0.55) * 1.1 + sin(h * 7.3 - tm * 1.1) * 0.25;
	return lean * h * h * 6.0 + vec2(cos(tm * 0.21), sin(tm * 0.17)) * sway * h;
}

float radius_at(float h, float tm) {
	if (part == 1) {
		// The skirt: wide in the middle of its height, ragged.
		return mix(1.6, 3.4, sin(h * 3.1416)) + 0.3 * sin(around * 5.0 + tm * 2.0);
	}
	if (part == 2) {
		return 1.0;
	}
	float r = mix(foot_r, top_r, pow(h, 1.1));
	r *= 1.0 + 0.12 * sin(h * 21.0 - tm * 3.3) + 0.05 * sin(h * 47.0 + tm * 5.0);
	return r * mix(0.55, 1.0, strength);
}

void vertex() {
	float tm = anim_time * motion;
	around = atan(VERTEX.z, VERTEX.x);
	if (part == 2) {
		// The wall cloud: a flat disc, a little thicker in the middle.
		up01 = 1.0;
		float rr = length(VERTEX.xz);
		VERTEX.y = (VERTEX.y + 0.5) * 2.4 * (1.0 - rr * 0.7);
	} else {
		up01 = VERTEX.y + 0.5;
		float h = part == 1 ? up01 * 3.6 : up01 * tall;
		float r = radius_at(up01, tm);
		vec2 off = part == 1 ? vec2(0.0) : bend(up01, tm);
		VERTEX = vec3(cos(around) * r + off.x, h, sin(around) * r + off.y);
	}
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	axis_p = vec3(around, up01, 0.0);
}

void fragment() {
	float tm = anim_time * motion;
	float h = up01;
	float dist = length(eye - map_p);
	// The bands, spiralling up and round: fast low down, slower high.
	float spin = tm * (part == 2 ? 0.08 : (part == 1 ? 1.2 : 2.4 - 1.2 * h));
	float a = around / 6.2831853;
	float twist = part == 0 ? h * tall * 0.07 : 0.0;
	float u = a + twist - spin;
	float bands = 0.5 + 0.28 * sin(u * 6.2831853 * 5.0 + h * 9.0) + 0.22 * sin(u * 6.2831853 * 11.0 - h * 23.0 + tm * 0.7);
	float roll = 0.5 + 0.5 * sin(u * 6.2831853 * 2.0 + h * 5.0 + sin(h * 13.0 + tm) * 1.5);
	// Fine churning streaks wound up the rope, over the broad bands.
	float wisp = 0.5 + 0.5 * sin(u * 6.2831853 * 23.0 + sin(h * 31.0 + tm * 1.7) * 2.0);
	float mass = clamp(bands * 0.45 + roll * 0.3 + wisp * 0.25, 0.0, 1.0);
	// Dithered along streaks of its own spin, not a screen-door pattern.
	float lane = floor((u + h * 0.3) * 160.0);
	float streak = hash12(vec2(lane, floor(h * 60.0 + tm * 4.0)));
	vec2 px = floor(FRAGCOORD.xy * (320.0 / view_size.x));
	float grain = 0.5 + (hash12(px + float(part) * 5.3) - 0.5) * 0.6;
	float dither = mix(streak, grain, smoothstep(14.0, 30.0, dist));
	float step_k = floor(mass * 3.0 + dither) / 3.0;
	vec3 dust = vec3(66.0, 52.0, 38.0);
	vec3 storm = vec3(58.0, 62.0, 72.0);
	vec3 colour;
	float body;
	float facing = abs(dot(normalize(NORMAL), normalize(VERTEX)));
	if (part == 0) {
		colour = mix(dust * 0.8, storm, smoothstep(0.05, 0.5, h));
		colour *= 0.4 + 1.05 * step_k;
		// Lit a little from the dusk on one side.
		colour += vec3(26.0, 22.0, 18.0) * step_k * smoothstep(0.2, 1.0, sin(around + 0.8));
		// Thicker at its edges, where the line of sight runs through more,
		// but frayed right at the silhouette into ragged wisps.
		body = 0.55 + 0.32 * (1.0 - facing) + 0.12 * step_k;
		float fray = smoothstep(0.0, 0.3, facing);
		body *= mix(step(0.55, mass + (dither - 0.5) * 0.5), 1.0, fray);
		// Forming or lifting: only from the cloud down to where it reaches.
		float reach = 1.0 - strength;
		body *= smoothstep(reach - 0.04, reach + 0.04, h);
		// Its foot frays into the dust.
		body *= smoothstep(0.0, 0.035, h);
	} else if (part == 1) {
		// The skirt: churning dirt, thin and torn, darker where it is thick.
		colour = dust * (0.42 + 0.7 * step_k);
		float torn = step(0.4, mass + (dither - 0.5) * 0.6);
		body = (0.42 + 0.4 * step_k) * torn * (1.0 - smoothstep(0.35, 1.0, h)) * smoothstep(0.0, 0.06, h);
		body *= 0.5 + 0.5 * facing;
		body *= strength;
	} else {
		colour = storm * (0.45 + 0.5 * step_k);
		body = 0.9;
	}
	// Boards, tin and hay whirled round in the funnel's lower part and the
	// skirt: black silhouettes.
	float solid = 0.0;
	if (part < 2) {
		float hh = part == 1 ? h * 3.6 : h * tall;
		vec2 q = vec2((a - spin * 1.3) * 28.0, hh * 1.6 - tm * 1.4);
		vec2 cell = floor(q);
		float r = hash12(cell + float(part) * 7.0);
		if (r < 0.11 && hh < 14.0) {
			vec2 local = fract(q) - 0.5;
			float turn = tm * (2.0 + 5.0 * fract(r * 9.1)) + r * 40.0;
			vec2 rot = vec2(cos(turn) * local.x - sin(turn) * local.y, sin(turn) * local.x + cos(turn) * local.y);
			float kind = fract(r * 23.7);
			if (kind < 0.5) {
				solid = (abs(rot.x) < 0.34 && abs(rot.y) < 0.07) ? 1.0 : 0.0;
			} else if (kind < 0.8) {
				solid = (abs(rot.x) < 0.2 && abs(rot.y) < 0.16) ? 1.0 : 0.0;
			} else {
				solid = length(rot * vec2(1.0, 1.6)) < 0.15 ? 1.0 : 0.0;
			}
		}
	}
	colour = min(colour * (1.0 + lightning * vec3(1.3, 1.4, 1.6)), vec3(255.0));
	colour = mix(colour, vec3(10.0, 9.0, 8.0), solid);
	// The fog veils it less than a wall: it stands out dark against the dusk.
	float fog = smoothstep(fog_range.x * 1.5, fog_range.y * 3.0, dist) * fog_range.z * 0.75;
	colour = mix(colour, fog_color * 255.0, fog);
	float near = smoothstep(0.4, 2.2, -VERTEX.z);
	ALBEDO = to_output(floor(colour));
	ALPHA = clamp(max(body, solid * step(0.02, body)) * near, 0.0, 0.96);
}
