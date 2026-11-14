// Marks laid on the world (sprite_layer.gd show_marks): bullet holes, blood
// and scorches on walls (Renderer.WallMark) and stains, tracks and splats on
// floors (Renderer.GroundMark), blended over the surface by their alpha as
// the old renderer did: a wall mark at light_at(d, 1), a ground mark at
// max(.63, light_at(d, 1.12)), neither tinted. Each quad is pulled a hair
// toward the eye so it lies on its surface instead of fighting it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled, skip_vertex_transform;

#include "res://src/view3d/view_light.gdshaderinc"

uniform sampler2DArray art : filter_nearest, repeat_disable;

varying flat vec4 data;
varying vec3 map_p;

void vertex() {
	data = INSTANCE_CUSTOM;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = length(VERTEX);
	VERTEX *= 1.0 - max(0.004, 0.0016 * d) / max(d, 0.01);
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (mirror_clipped(map_p, CAMERA_VISIBLE_LAYERS)) {
		discard;
	}
	ivec2 size = ivec2(data.yz);
	ivec2 at = clamp(ivec2(UV * vec2(size)), ivec2(0), size - 1);
	vec4 texel = texelFetch(art, ivec3(at, int(data.x + 0.5)), 0);
	bool ground = data.w > 0.5;
	float a = texel.a * 255.0;
	if (a <= (ground ? 0.0 : 20.0)) {
		discard;
	}
	float t = -VERTEX.z;
	float lit = ground ? max(0.63, stepped_light(1.12, t)) : stepped_light(1.0, t);
	vec3 colour = clamp(floor(floor(texel.rgb * 255.0 + 0.5) * lit), 0.0, 255.0);
	if (effects_on) {
		vec3 nf = ground ? vec3(0.0, 0.0, 1.0) : normalize(vec3(eye.xy - map_p.xy, 0.0) + vec3(1e-5));
		colour = surface_light(colour, map_p, t, nf, vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec2(0.0), 0.0, ground ? 0 : 1);
	}
	ALBEDO = to_output(colour);
	ALPHA = texel.a;
}
