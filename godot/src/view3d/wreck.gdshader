// A piece of broken scenery (wreck_layer.gd): a cut of a prop's model with
// its baked texture, or a board of a picture or a tile, lit as the prop or
// the sprite it came from was (prop.gdshader's light: light_at stepped in
// 32nds, the area's tint, then LIGHTS AND GLOW, grade and fog). A picture's
// clear texels are not drawn (a sign's ragged edge). Solid: no ALPHA. Holes,
// scorch and char as a prop has them (thing_marks.gdshaderinc). A cut face
// (vertex COLOR alpha 0, wreck_fracture.gd) is drawn raw: the colour of its
// one texel (UV) worked toward its material (COLOR red x 16: wood, tin,
// clay, glass, straw, foam, iron, goo, stuffing, rubber, char; COLOR green
// 1 a rim of fresh broken stuff, 0 an inside face) with that material's
// grain, specks or strands from where it is (UV2, cells), in hard 64ths of
// a cell.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/view3d/view_light.gdshaderinc"
#include "res://src/view3d/thing_marks.gdshaderinc"

uniform sampler2D baked : filter_nearest, repeat_disable;
// The area's tint (rgb) and the cell's light (a).
uniform vec4 tone = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 map_p;
varying vec3 map_n;
varying vec4 raw_of;
varying vec2 raw_at;

// A cut face's colour: its texel worked toward its material, patterned. A
// rim is fresh broken stuff; an inside face of wood is its weathered back.
vec3 raw_face(vec3 texel, int mat, bool rim, vec2 q) {
	vec2 cell = floor(q * 64.0);
	float h = hash12(cell);
	vec3 c = texel;
	if (mat == 0 || mat == 10) {
		if (!rim) {
			c = texel * 0.78;
		} else {
			// Fresh wood: lighter than its skin, fine grain lines along it.
			c = mix(texel * 1.3, vec3(176.0, 132.0, 86.0), 0.35);
			float g = floor(q.y * 64.0 + sin(q.x * 11.0) * 1.4);
			if (mod(g, 5.0) < 1.0) {
				c *= 0.84;
			}
			if (h > 0.95) {
				c *= 0.88;
			}
		}
		if (mat == 10) {
			c = c * 0.45 + (rim && h > 0.9 ? vec3(60.0, 18.0, 6.0) : vec3(0.0));
		}
	} else if (mat == 1) {
		c = rim ? mix(texel, vec3(178.0, 178.0, 168.0), 0.65) : mix(texel, vec3(96.0, 90.0, 82.0), 0.5);
		c *= h > 0.85 ? 0.85 : 1.0;
	} else if (mat == 2) {
		c = mix(texel, vec3(176.0, 104.0, 66.0), rim ? 0.6 : 0.45) * (h > 0.86 ? 1.12 : 1.0);
	} else if (mat == 3) {
		c = mix(texel, vec3(172.0, 216.0, 198.0), 0.5) * (rim && h > 0.7 ? 1.25 : 1.0);
	} else if (mat == 4) {
		c = mix(texel, vec3(200.0, 166.0, 76.0), 0.45);
		if (mod(floor(q.y * 64.0 + h * 2.0), 3.0) < 1.0) {
			c *= 0.78;
		}
	} else if (mat == 5) {
		c = vec3(218.0, 214.0, 200.0) * (h > 0.8 ? 0.9 : 1.0);
	} else if (mat == 6) {
		c = h > 0.72 ? vec3(118.0, 64.0, 38.0) : vec3(66.0, 60.0, 54.0);
	} else if (mat == 7) {
		c = vec3(96.0, 176.0, 64.0) * (h > 0.6 ? 0.82 : 1.0);
	} else if (mat == 8) {
		c = vec3(228.0, 224.0, 210.0) * (h > 0.75 ? 0.88 : 1.0);
	} else if (mat == 9) {
		c = texel * 0.7;
	}
	return clamp(floor(c), 0.0, 255.0);
}

void vertex() {
	own_p = VERTEX;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_p = vec3(w.x, w.z, w.y);
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	map_n = vec3(n.x, n.z, n.y);
	raw_of = COLOR;
	raw_at = UV2;
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
	if (raw_of.a < 0.5) {
		texel = raw_face(texel, int(raw_of.r * 16.0 + 0.5), raw_of.g > 0.5, raw_at);
		texel = floor(texel * (0.8 + 0.2 * abs(map_n.z)));
	}
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
