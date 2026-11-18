// A piece of broken scenery (wreck_layer.gd): a cut of a prop's model with
// its baked texture, or a board of a picture or a tile, lit as the prop or
// the sprite it came from was (prop.gdshader's light: light_at stepped in
// 32nds, the area's tint, then LIGHTS AND GLOW, grade and fog). A picture's
// clear texels are not drawn (a sign's ragged edge). Solid: no ALPHA. Holes,
// scorch and char as a prop has them (thing_marks.gdshaderinc).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"
#include "res://src/view3d/thing_marks.gdshaderinc"

uniform sampler2D baked : filter_nearest, repeat_disable;
// The area's tint (rgb) and the cell's light (a).
uniform vec4 tone = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 map_p;
varying vec3 map_n;

void vertex() {
	own_p = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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
	vec4 texel4 = texelFetch(baked, at, 0);
	if (texel4.a < 0.4) {
		discard;
	}
	vec3 texel = floor(texel4.rgb * 255.0 + 0.5);
	float t = -VERTEX.z;
	float lit = stepped_light(tone.a, t);
	vec3 colour = thing_marks(clamp(floor(texel * lit * tone.rgb), 0.0, 255.0));
	if (effects_on) {
		vec3 cam = vec3(CAMERA_POSITION_WORLD.x, CAMERA_POSITION_WORLD.z, CAMERA_POSITION_WORLD.y);
		vec3 nf = dot(map_n, cam - map_p) < 0.0 ? -map_n : map_n;
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.0), 0.0, 2);
	}
	ALBEDO = to_output(colour);
}
