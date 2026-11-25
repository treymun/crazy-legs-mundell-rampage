// A body's own rim (pass 15, view3d/actor_rim.gd, effects.cfg [rim]): the
// actor's parts drawn again behind themselves (the material's next pass,
// back faces only), swollen out along its normals by `RIM_PX` of the
// view's pixels, so they show only round the figure's outline: a clean warm
// edge one or two pixels wide on a hand awake, a cool one on a critter, never
// a speck inside the body (the parts in front hide the rest). Its colour is
// the rim's, brighter far off (`reach`), fogged as the body is less
// `reach.w` of it; never dimmer than the moon's rim by night. LIGHTS AND GLOW
// only; ActorRim hangs it on a part only while it has a rim, quieted under a
// hit's wash and a wind-up's amber.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

// rgb the rim's colour (0-1), a how much of it up close.
uniform vec4 rim = vec4(0.0);
// x how much at z cells and beyond (rising from y), w the share of the fog
// it shows through.
uniform vec4 reach = vec4(1.0, 3.0, 15.0, 0.6);
// The body's own swelling (actors.json "min_px"), so the rim stays outside it.
uniform float min_px = 0.0;
// Which way the part's normals point (actor_rim.gd: +1 out of the body, -1
// into it, as some of the models were exported), so the swelling goes out.
uniform float normal_out = 1.0;
// How far out past the body the rim stands, in the view's pixels.
const float RIM_PX = 1.25;

varying vec3 map_p;
varying float ahead;

void vertex() {
	// Pushed out along its own normals (in the model's space, so a bone
	// carries the push with the part), RIM_PX of the view's pixels at its
	// distance past the body's own swelling, and a hair further back so it
	// never shows through the body's front.
	float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.05);
	float pixel = depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5);
	float size = max(1e-4, length(MODEL_MATRIX[0].xyz));
	VERTEX += NORMAL * (normal_out * pixel * (RIM_PX + 0.5 * min_px) / size);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	ahead = depth;
}

void fragment() {
	if (!effects_on || rim.a <= 0.0 || mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	float most = max(mix(rim.a, reach.x, smoothstep(reach.y, reach.z, ahead)), moon_rim.a);
	// In thirds, as the moon's rim and a 1997 light map step.
	most = floor(clamp(most, 0.0, 1.0) * 3.0 + 0.5) / 3.0;
	vec3 colour = rim.rgb * 255.0 * (0.4 + 0.6 * most);
	float fog = fog_share(map_p, ahead) * (1.0 - reach.w);
	if (storm_ring.w > 0.0) {
		fog = max(fog, storm_veil(map_p));
	}
	colour = mix(colour, fog_color * 255.0 * (1.0 - blackout * 0.75), fog);
	ALBEDO = to_output(floor(colour));
}
