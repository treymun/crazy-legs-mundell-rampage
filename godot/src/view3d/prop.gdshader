// A modelled prop (prop_layer.gd): its baked texture (materials and the dusk
// stage's light, committed to the palette), lit as the sprite it replaces
// was: light_at(distance, the cell's light) stepped in 32nds, the area's
// tint; then LIGHTS AND GLOW's lights (with the mesh's own normals), grade
// and fog.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2D baked : filter_nearest, repeat_disable;
// The area's tint (rgb) and the cell's light (a).
instance uniform vec4 tone = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 map_p;
varying vec3 map_n;

void vertex() {
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
