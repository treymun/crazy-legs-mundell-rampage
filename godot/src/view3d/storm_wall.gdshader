// County Run's storm front (src/modes/county_storm.gd) as the 3D view shows
// it: a towering wall of storm round the safe ground, two open cylinders
// (world_view.gd stands and sizes them each frame): the front curtain at the
// ring (layer 0) and a darker one OUTER cells behind it (layer 1), so the
// wall has depth as the eye moves. Each is a dark churning curtain in posterised
// steps, darkest at its foot where it kicks up dirt, rolling up and carried
// round with the wind, thinning into the sky at its top; lightning flickers
// inside it, lighting the billows from within (now and then a fork), and
// boards, tin and hay fly round in it as black silhouettes. EASY ON THE EYES
// (motion) slows all of it and stills it, flickers and all; storm_rich off
// (QUALITY LOW: LIGHTS AND GLOW off or VIEW DETAIL LOW) keeps one plain
// curtain. See-through, so it has a shader of its own (it writes ALPHA).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

// The ring's radius (cells), how hard the storm blows (0 to 1), the ground's
// height under it, and whether the rich wall is drawn.
uniform float storm_r = 10.0;
uniform float storm_k = 0.5;
uniform float storm_base = 0.0;
uniform bool storm_rich = true;
// 0 the front curtain, 1 the one behind it.
uniform int layer_k = 0;

const float OUTER = 2.5;
const float TOP = 27.0;

varying vec3 map_p;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
}

// The curtain's density at (around, up), 0 to 1: shafts of rain hanging down
// it, swaying and rolling up and round with the wind (sums of waves bent by
// waves: no lattice to show through).
float curtain(vec2 at, float tm, float drift, float layer) {
	float x = at.x + layer * 37.0;
	float up = at.y;
	float bend = sin(up * 0.21 + tm * 0.35 + x * 0.05) * 1.8 + sin(up * 0.53 - tm * 0.6) * 0.6;
	float shafts = 0.5 + 0.3 * sin((x + drift) * 0.62 + bend) + 0.2 * sin((x + drift * 1.3) * 1.71 - bend * 0.7);
	float roll = 0.5 + 0.5 * sin(x * 0.17 + drift * 0.4 + up * 0.31 - tm * 0.5 + sin(x * 0.07 - tm * 0.2) * 2.0);
	return clamp(shafts * 0.65 + roll * 0.35, 0.0, 1.0);
}

// A flicker of lightning inside the curtain at (around, up): how lit, 0 to
// about 1.3 (a fork's line brightest).
float inner_flash(vec2 at, float layer) {
	// One flicker a patch of 10 x 8 cells at most, each on its own beat.
	vec2 size = vec2(10.0, 8.0);
	vec2 cell = floor(at / size);
	float h = hash12(cell + layer * 13.1);
	float beat = anim_time * 0.5 * (0.6 + storm_k) * motion + h * 17.0;
	if (hash12(cell + floor(beat) * 1.37) > 0.14 + 0.22 * storm_k) {
		return 0.0;
	}
	float age = fract(beat);
	// A double flicker, then a dying glow: over in about a sixth of a beat.
	float k = age < 0.05 ? 1.0 : (age < 0.08 ? 0.3 : (age < 0.13 ? 0.85 : max(0.0, 0.3 - (age - 0.13) * 2.5)));
	if (k <= 0.0) {
		return 0.0;
	}
	vec2 middle = (cell + vec2(0.4 + 0.2 * fract(h * 7.3), 0.4 + 0.2 * fract(h * 3.1))) * size;
	vec2 off = (at - middle) / vec2(4.2, 3.4);
	float glow = max(0.0, 1.0 - dot(off, off));
	// The fork itself: a jagged line down through the glow at its peaks.
	float fork = 0.0;
	if (k > 0.8 && abs(off.y) < 0.9) {
		float jag = (hash12(vec2(floor(at.y * 1.5), cell.x + h)) - 0.5) * 1.1 + off.y * 0.8 * (fract(h * 5.7) - 0.5);
		fork = abs(at.x - middle.x - jag) < 0.13 ? 1.3 : 0.0;
	}
	return max(k * glow, fork);
}

// Boards, tin and hay carried round in the wind: 1 on a silhouette, else 0.
float debris(vec2 at, float tm, float speed, float seed) {
	float size = 1.7;
	vec2 q = vec2(at.x + tm * speed, at.y - tm * 0.35 + sin(at.x * 0.21 + seed) * 0.8);
	vec2 cell = floor(q / size);
	float h = hash12(cell + seed);
	if (h > 0.09 + 0.1 * storm_k || at.y < 0.7 || at.y > 15.0) {
		return 0.0;
	}
	vec2 local = (fract(q / size) - 0.5) * size;
	float turn = tm * (1.5 + 4.0 * fract(h * 9.1)) + h * 40.0;
	vec2 r = vec2(cos(turn) * local.x - sin(turn) * local.y, sin(turn) * local.x + cos(turn) * local.y);
	float kind = fract(h * 23.7);
	if (kind < 0.45) {
		return (abs(r.x) < 0.34 && abs(r.y) < 0.06) ? 1.0 : 0.0;
	}
	if (kind < 0.75) {
		return (abs(r.x) < 0.2 && abs(r.y) < 0.15) ? 1.0 : 0.0;
	}
	return length(r * vec2(1.0, 1.6)) < 0.14 ? 1.0 : 0.0;
}

// The threshold the curtain's steps are dithered by at (around, up), `far`
// units from the eye (`frag` the pixel): streaks of rain on the curtain near, a grain of the
// 320-wide pixels far, mixed a pixel at a time between 5 and 11 units.
float dither_of(vec2 at, float tm, float drift, float layer, float far, vec2 frag) {
	// A streak a fourteenth of a cell wide and half a cell long, each its own
	// shade, falling with the wind; staggered so no two columns line up.
	float lane = floor(at.x * 14.0 + drift * 6.0);
	float fall = (at.y + tm * 6.5) * 2.2 + hash12(vec2(lane, layer)) * 7.0;
	float streak = hash12(vec2(lane, floor(fall)) + layer * 19.0);
	vec2 px = floor(frag * (320.0 / view_size.x));
	// Ragged only along the steps' edges, so the rolls of cloud keep their
	// shapes.
	float grain = 0.5 + (hash12(px + layer * 5.3) - 0.5) * 0.65;
	float pick = hash12(px.yx + 2.7);
	return pick < smoothstep(5.0, 11.0, far) ? grain : streak;
}

void fragment() {
	float layer = float(layer_k);
	float tm = anim_time * motion;
	float r = storm_r + layer * OUTER;
	// Round the ring and up it, in cells.
	vec2 at = vec2(UV.x * 6.2831853 * r, map_p.z - storm_base);
	float up = at.y;
	float drift = tm * (0.9 + 1.6 * storm_k) * (1.0 - 0.35 * layer);
	// The curtain in four steps, dithered between them as a 1997 palette
	// would show it: the shafts hanging down it over the great rolls of
	// cloud, darkest at its foot, its top lit pale by the sky where it thins
	// out. Never a fine ordered pattern (it read as a screen door up close):
	// near, the steps break along streaks of driven rain hung on the curtain
	// itself, falling and carried with the wind; far, where a streak is under
	// a pixel, a ragged grain in the 320-wide pixels whatever the view's size.
	float dither = dither_of(at, tm, drift, layer, -VERTEX.z, FRAGCOORD.xy);
	float mass = curtain(at * vec2(0.45, 0.35), tm * 0.6, drift * 0.5, layer + 3.0);
	float fine = curtain(at * 1.8, tm * 1.3, drift * 1.8, layer);
	float billow = floor((mass * 0.5 + fine * 0.5) * 3.0 + dither) / 3.0;
	float rise = smoothstep(-0.5, 12.0, up);
	vec3 colour = mix(vec3(17.0, 18.0, 23.0), vec3(58.0, 62.0, 76.0), rise);
	colour = colour * (0.38 + 1.3 * billow);
	float crown = smoothstep(TOP * 0.35, TOP * 0.7, up + mass * 4.0);
	colour = mix(colour, vec3(92.0, 96.0, 110.0) * (0.7 + 0.45 * billow), crown * 0.7);
	colour *= 1.0 - 0.3 * layer;
	// Dirt kicked up along its foot.
	colour = mix(colour, vec3(46.0, 36.0, 26.0) * (0.7 + 0.5 * billow), (1.0 - smoothstep(0.0, 2.6, up + fine * 0.8)) * 0.7);
	float solid = 0.0;
	if (storm_rich) {
		float flash = motion > 0.0 ? inner_flash(at, layer) * (1.0 - 0.3 * layer) : 0.0;
		colour += flash * (0.45 + 0.55 * billow) * vec3(118.0, 126.0, 158.0);
		if (layer_k == 0) {
			solid = max(debris(at, tm, 3.0 + 4.0 * storm_k, 3.0), debris(at, tm, 5.0 + 5.0 * storm_k, 11.0));
		}
	}
	colour = min(colour * (1.0 + lightning * vec3(1.4, 1.5, 1.7)), vec3(255.0));
	colour = mix(colour, vec3(9.0, 8.0, 7.0), solid);
	float top = 1.0 - smoothstep(TOP * 0.55, TOP, up + mass * 5.0);
	float near = smoothstep(0.3, 2.5, -VERTEX.z);
	float body = (layer_k == 0 ? 0.84 : 0.66) + 0.1 * storm_k + 0.08 * (1.0 - rise);
	ALBEDO = to_output(floor(colour));
	ALPHA = clamp(max(body * top, solid * 0.97 * step(0.01, top)) * near, 0.0, 0.97);
}
