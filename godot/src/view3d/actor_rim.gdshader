// A body's own rim (pass 15, view3d/actor_rim.gd, effects.cfg [rim]; ENEMY
// RIM: SOFT or BOLD): the actor's parts drawn again behind themselves (the
// material's next pass, back faces only), swollen out along their normals by
// `look.x` of the view's pixels, so they show only round the figure's
// outline: a warm edge on a hand awake, a cool one on a critter, never a
// speck inside the body (the parts in front hide the rest). The swelling
// thins far off, so a small far figure keeps its own pixels inside and only
// gains an edge, never a filled cutout.
// Its colour is the rim's dulled toward the dark (`look.y` to `look.z` of it,
// more far off by `reach`), fogged as the body is less `reach.w` of it; never
// dimmer than the moon's rim by night. LIGHTS AND GLOW only; ActorRim hangs
// it on a part only while it has a rim, quieted under a hit's wash and a
// wind-up's amber.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

// rgb the rim's colour (0-1), a how much of it up close.
uniform vec4 rim = vec4(0.0);
// x how much at z cells and beyond (rising from y), w the share of the fog
// it shows through.
uniform vec4 reach = vec4(1.0, 3.0, 15.0, 0.6);
// x how far out past the body it stands (about a share of the view's pixel,
// as the pictures measured it: .6 is one at 320 wide), y and z its
// brightness up close and far off (shares of the rim's colour), w the share
// of the swelling taken off far away.
uniform vec4 look = vec4(0.75, 0.32, 0.62, 0.05);
// Which way the part's normals point (actor_rim.gd: +1 out of the body, -1
// into it, as some of the models were exported), so the swelling goes out.
uniform float normal_out = 1.0;

// How far back (cells) the edge is tested against the body.
const float BEHIND = 0.5;

varying vec3 map_p;
varying float ahead;

void vertex() {
	// Pushed out along its own normals (in the model's space, so a bone
	// carries the push with the part), at most look.x of the view's pixels
	// at its distance, less far off. (No push back from the eye: the bones turn the model's space
	// after this, and a push that is not along the normals goes astray.)
	float depth = max(-(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z, 0.05);
	float pixel = depth / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5);
	float size = max(1e-4, length(MODEL_MATRIX[0].xyz));
	// Thinner far off, where a figure is a few pixels: look.w of it gone by
	// 20 cells, so a small far body keeps its own pixels inside its edge.
	float swell = look.x * (1.0 - look.w * smoothstep(8.0, 20.0, depth));
	VERTEX += NORMAL * (normal_out * pixel * swell / size);
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
	vec3 colour = rim.rgb * 255.0 * mix(look.y, look.z, most);
	float fog = fog_share(map_p, ahead) * (1.0 - reach.w);
	if (storm_ring.w > 0.0) {
		fog = max(fog, storm_veil(map_p));
	}
	colour = mix(colour, fog_color * 255.0 * (1.0 - blackout * 0.75), fog);
	ALBEDO = to_output(floor(colour));
	// Tested as if it stood half a cell further back: a part in front (an
	// arm over the chest) never draws its edge over the body behind it, only
	// round the whole figure.
	vec4 behind = PROJECTION_MATRIX * vec4(VERTEX.xy, VERTEX.z - BEHIND, 1.0);
	DEPTH = behind.z / behind.w * 0.5 + 0.5;
}
