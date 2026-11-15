// A modelled prop (prop_layer.gd): its baked texture (materials and the dusk
// stage's light, committed to the palette), lit as the sprite it replaces
// was: light_at(distance, the cell's light) stepped in 32nds, the area's
// tint; then LIGHTS AND GLOW's lights (with the mesh's own normals), grade
// and fog.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2D baked : filter_nearest, repeat_disable;
// The wind sways it (effects.cfg [sway], prop_layer.gd): how far its top
// goes in a full gust (cells; below 0 it hangs from its top and swings), and
// the model's height and width in its own units.
uniform float sway_k = 0.0;
uniform vec2 sway_size = vec2(1.0, 1.0);
// The area's tint (rgb) and the cell's light (a).
instance uniform vec4 tone = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 map_p;
varying vec3 map_n;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (sway_k != 0.0 && motion > 0.0) {
		float h = clamp(VERTEX.y / max(sway_size.x, 0.01), 0.0, 1.0);
		float bend = h * h;
		if (sway_k < 0.0) {
			// Hung from its top: what hangs swings, the posts at its ends stay.
			float across = abs(VERTEX.x) / max(sway_size.y, 0.01);
			bend = (1.0 - h) * (1.0 - smoothstep(0.3, 0.44, across)) * step(0.08, 1.0 - h);
		}
		float strength = clamp(length(wind_now.xy) / 0.6, 0.0, 2.5);
		float tm = anim_time * motion;
		float flutter = sin(tm * 2.3 + w.x * 0.41 + w.z * 0.37) * 0.45 + sin(tm * 5.1 + w.x * 1.3) * 0.15;
		vec2 dir = length(wind_now.xy) > 0.001 ? normalize(wind_now.xy) : vec2(1.0, 0.0);
		vec2 push = dir * abs(sway_k) * bend * (strength * 0.55 + flutter * min(wind_now.z, 2.5) * 0.5);
		w += vec3(push.x, 0.0, push.y);
		VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 1.0)).xyz;
	}
	map_p = vec3(w.x, w.z, w.y);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(n.x, n.z, n.y);
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	ivec2 size = textureSize(baked, 0);
	ivec2 at = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	vec3 texel = floor(texelFetch(baked, at, 0).rgb * 255.0 + 0.5);
	float t = -VERTEX.z;
	float lit = stepped_light(tone.a, t);
	vec3 colour = clamp(floor(texel * lit * tone.rgb), 0.0, 255.0);
	if (effects_on) {
		vec3 cam = vec3(CAMERA_POSITION_WORLD.x, CAMERA_POSITION_WORLD.z, CAMERA_POSITION_WORLD.y);
		vec3 nf = dot(map_n, cam - map_p) < 0.0 ? -map_n : map_n;
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
