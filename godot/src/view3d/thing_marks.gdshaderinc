// What shots, blasts and fire left on a modelled thing (thing_marks.gd): a
// prop (prop.gdshader), a vehicle (a prop too) or a wreck piece
// (wreck.gdshader). Include after view_light.gdshaderinc; the shader passes
// the vertex's own place (VERTEX, before any sway) as own_p.
//
// mark0..mark5: xyz where, in the mesh's own space; w its kind and size,
// kind * 10 + radius (own units): kind 1 a bullet hole, 2 a scorch; 0 none.
// char_k: how burnt it is (0 to 1).
uniform vec4 mark0 = vec4(0.0);
uniform vec4 mark1 = vec4(0.0);
uniform vec4 mark2 = vec4(0.0);
uniform vec4 mark3 = vec4(0.0);
uniform vec4 mark4 = vec4(0.0);
uniform vec4 mark5 = vec4(0.0);
uniform float char_k = 0.0;

varying vec3 own_p;

// One mark m over the colour c at p: a chunky hole (a black core, a dark
// rim, flecks of the bare stuff under the paint) or a scorch of soot.
vec3 thing_mark(vec3 c, vec3 p, vec4 m) {
	if (m.w <= 0.0) {
		return c;
	}
	float kind = floor(m.w / 10.0);
	float r = m.w - kind * 10.0;
	if (kind < 1.5) {
		// In blocks a third of the hole's radius: square-ish, as a 1997 decal.
		float block = r * 0.34;
		vec3 q = (floor(p / block) + 0.5) * block;
		float d = distance(q, m.xyz) / r;
		if (d >= 1.0) {
			return c;
		}
		if (d < 0.45) {
			return floor(c * 0.1) + vec3(6.0, 5.0, 4.0);
		}
		if (d < 0.75) {
			return floor(c * 0.45);
		}
		vec3 g = floor(p / block);
		return hash12(g.xy + g.z * 3.7) > 0.55 ? min(floor(c * 1.3) + vec3(14.0, 12.0, 8.0), vec3(255.0)) : c;
	}
	vec3 g = floor(p / (r * 0.2));
	float n = hash12(g.xy + g.z * 5.3);
	float d = distance(p, m.xyz) / r + (n - 0.5) * 0.35;
	float soot = 1.0 - smoothstep(0.35, 1.0, d);
	return mix(c, floor(c * 0.22) + vec3(8.0, 7.0, 6.0), soot * 0.9);
}

vec3 thing_marks(vec3 c) {
	if (char_k > 0.0) {
		vec3 g = floor(own_p * 14.0);
		float n = hash12(g.xy + g.z * 7.1);
		float burnt = min(1.0, char_k * (0.85 + 0.3 * n));
		c = mix(c, floor(c * 0.16) + vec3(9.0, 7.0, 6.0), burnt);
	}
	c = thing_mark(c, own_p, mark0);
	c = thing_mark(c, own_p, mark1);
	c = thing_mark(c, own_p, mark2);
	c = thing_mark(c, own_p, mark3);
	c = thing_mark(c, own_p, mark4);
	c = thing_mark(c, own_p, mark5);
	return c;
}
