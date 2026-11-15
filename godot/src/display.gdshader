shader_type canvas_item;
render_mode unshaded;

// The picture players see, 320x200: the 3D view's picture (view3d_tex, at the
// view's own size: 320x156, LOW 160x78, HD 640x312) under the weapon, HUD and
// menus layer (post_tex, from a Godot 2D viewport), with the moonshine's
// warp, the air shimmering over hot things, the hurt flash, then the look
// pass (level wash and vignette, film grain, ordered dither, blast lift, the
// brightness table) and last the project's VGA-style palette (RGB555 ->
// palette lookup). Headless runs and --cpu-canvas hand a finished software
// frame in TEXTURE instead (overlay_on off).
//
// `looks` holds the palette table (rows 0-127, 256 wide), the grain frames
// (rows 128-447) and the brightness table (row 448). WebGL and many phones
// give a shader few texture units: this one samples four (TEXTURE, looks,
// post_tex, view3d_tex); tools/check_shader.gd keeps count.
uniform sampler2D looks : filter_nearest, repeat_disable;
const int GRAIN_ROW = 128;
const int TONE_ROW = 448;

uniform bool look = false;
uniform bool tone_on = false;
uniform vec3 wash = vec3(1.0);
uniform float gain = 1.0;
uniform float blast = 0.0;
uniform int grain_frame = 0;
uniform int hurt = 0;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

uniform bool overlay_on = false;
uniform bool base_on = false;
uniform sampler2D post_tex : filter_nearest, repeat_disable;
uniform bool view3d_on = false;
uniform sampler2D view3d_tex : filter_nearest, repeat_disable;
// The view's grid against the 320x200 one: view_mul 2 in HD, view_div 2 at LOW.
uniform int view_mul = 1;
uniform int view_div = 1;
uniform float anim_time = 0.0;

// The moonshine warp's strength (0 none), its phase and its ghost's offset.
uniform float drunk = 0.0;
uniform float drunk_phase = 0.0;
uniform int drunk_ghost = 0;

// Over each hot thing in sight (view3d/heat_haze.gd): its centre column, base
// row, half width and height in view pixels; haze_amp how far it sways.
uniform int haze_count = 0;
uniform vec4 haze_box[4];
uniform float haze_amp[4];

int haze_shift(ivec2 fine) {
	ivec2 lp = fine / view_div;
	float shift = 0.0;
	for (int i = 0; i < haze_count; i++) {
		vec4 b = haze_box[i];
		float across = (float(lp.x) + 0.5 - b.x) / max(b.z, 1.0);
		float up = (b.y - float(lp.y) - 0.5) / max(b.w, 1.0);
		if (abs(across) >= 1.0 || up < 0.0 || up >= 1.0) {
			continue;
		}
		float fade = (1.0 - across * across) * (1.0 - up) * min(up * 6.0, 1.0);
		shift += sin(float(lp.y) * 0.6 + anim_time * 8.0 + float(i) * 2.1) * haze_amp[i] * fade;
	}
	return int(floor(shift + 0.5)) * view_div;
}

// The finished view pixel: the weapon and HUD layer over the view.
vec3 picture_at(ivec2 px, ivec2 fine, vec3 frame) {
	vec4 o = texelFetch(post_tex, px, 0);
	if (o.a >= 1.0) {
		return o.rgb * 255.0;
	}
	vec3 under = vec3(0.0);
	if (view3d_on && px.y < 156) {
		if (haze_count > 0) {
			fine.x = clamp(fine.x + haze_shift(fine), 0, 320 * view_mul - 1);
		}
		vec2 picture = vec2(textureSize(view3d_tex, 0));
		ivec2 at = ivec2((vec2(fine) + 0.5) * picture / vec2(320.0 * float(view_mul), 156.0 * float(view_mul)));
		under = floor(texelFetch(view3d_tex, at, 0).rgb * 255.0 + 0.5);
	} else if (base_on) {
		under = frame;
	}
	return floor(o.rgb * 255.0 + (1.0 - o.a) * under + 0.5);
}

void fragment() {
	ivec2 px = ivec2(UV * vec2(320.0, 200.0));
	ivec2 fine = ivec2(UV * vec2(320.0, 200.0) * float(view_mul));
	ivec2 sub = fine - px * view_mul;
	vec3 c;
	if (overlay_on) {
		if (drunk > 0.0 && px.y < 156) {
			// Per-row shear, a ghost double image, an amber tint.
			int shift = int(floor(sin(float(px.y) * 0.16 + drunk_phase) * (1.0 + 3.4 * drunk) + 0.5));
			int sx = (px.x + shift + 640) % 320;
			int gx = (px.x - drunk_ghost + shift + 640) % 320;
			float blend = 0.30 * drunk;
			vec3 v = picture_at(ivec2(sx, px.y), ivec2(sx, px.y) * view_mul + sub, texelFetch(TEXTURE, ivec2(sx, px.y), 0).rgb * 255.0) * (1.0 - blend)
					+ picture_at(ivec2(gx, px.y), ivec2(gx, px.y) * view_mul + sub, texelFetch(TEXTURE, ivec2(gx, px.y), 0).rgb * 255.0) * blend;
			c = floor(vec3(v.r * (1.0 + 0.06 * drunk), v.g, v.b * (1.0 - 0.10 * drunk)));
		} else {
			c = picture_at(px, fine, texelFetch(TEXTURE, px, 0).rgb * 255.0);
		}
		c = clamp(c, 0.0, 255.0) / 255.0;
	} else {
		c = texture(TEXTURE, UV).rgb;
	}
	ivec3 q = ivec3(clamp(c, 0.0, 1.0) * 255.0 + 0.5);
	if (px.y < 156 && hurt > 0) {
		q = (ivec3(131, 27, 17) * hurt + q * (255 - hurt)) / 255;
	}
	if (px.y < 156 && (look || tone_on)) {
		vec3 v = vec3(q);
		if (look) {
			// On the view's own grid: in HD each of a 320x200 pixel's four gets its
			// own grain and dither, so the look does not blur HD back to 320 wide.
			vec2 at = (vec2(fine) + 0.5) / float(view_mul) - 0.5;
			vec2 n = (at / vec2(319.0, 155.0) - 0.5) * 2.0;
			float vignette = 1.0 - 0.13 * pow(length(n) / 1.4142, 2.1);
			int frame_k = (grain_frame + sub.x + 2 * sub.y) % 6;
			float g = texelFetch(looks, ivec2(frame_k * 156 + px.y, GRAIN_ROW + px.x), 0).r * 255.0;
			float add = g - 2.0 + blast + (BAYER[(fine.x % 4) * 4 + (fine.y % 4)] / 16.0 - 0.5) * 6.0;
			v = clamp(trunc(v * (wash * vignette * gain) + add), 0.0, 255.0);
		}
		if (tone_on) {
			v = vec3(texelFetch(looks, ivec2(int(v.r), TONE_ROW), 0).r, texelFetch(looks, ivec2(int(v.g), TONE_ROW), 0).r,
					texelFetch(looks, ivec2(int(v.b), TONE_ROW), 0).r) * 255.0;
		}
		q = ivec3(v + 0.5);
	}
	int r5 = (q.r * 31 + 127) / 255;
	int g5 = (q.g * 31 + 127) / 255;
	int b5 = (q.b * 31 + 127) / 255;
	int code = (r5 << 10) | (g5 << 5) | b5;
	ivec2 pos = ivec2(code & 255, code >> 8);
	COLOR = vec4(texelFetch(looks, pos, 0).rgb, 1.0);
}
