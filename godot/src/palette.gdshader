shader_type canvas_item;
render_mode unshaded;

// Convert the composed 320x200 RGB frame to the project's VGA-style 256-color
// grade, exactly like period_palette.VGAPalette.apply (RGB555 -> palette LUT).
uniform sampler2D lut : filter_nearest, repeat_disable;

// The game view's look pass (game.gd _look_rows), done here when there is a
// window: level wash and vignette, film grain, ordered dither, lamp buzz and
// blast lift, then the brightness table. Rows from 156 down are the status bar.
uniform bool look = false;
uniform bool tone_on = false;
uniform sampler2D grain : filter_nearest, repeat_disable;
uniform sampler2D tone : filter_nearest, repeat_disable;
uniform vec3 wash = vec3(1.0);
uniform float gain = 1.0;
uniform float blast = 0.0;
uniform int grain_frame = 0;
uniform int hurt = 0;
const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	ivec3 q = ivec3(clamp(c, 0.0, 1.0) * 255.0 + 0.5);
	ivec2 px = ivec2(UV * vec2(320.0, 200.0));
	if (px.y < 156 && hurt > 0) {
		q = (ivec3(131, 27, 17) * hurt + q * (255 - hurt)) / 255;
	}
	if (px.y < 156 && (look || tone_on)) {
		vec3 v = vec3(q);
		if (look) {
			vec2 n = (vec2(px) / vec2(319.0, 155.0) - 0.5) * 2.0;
			float vignette = 1.0 - 0.13 * pow(length(n) / 1.4142, 2.1);
			float g = texelFetch(grain, ivec2(grain_frame * 156 + px.y, px.x), 0).r * 255.0;
			float add = g - 2.0 + blast + (BAYER[(px.x % 4) * 4 + (px.y % 4)] / 16.0 - 0.5) * 6.0;
			v = clamp(trunc(v * (wash * vignette * gain) + add), 0.0, 255.0);
		}
		if (tone_on) {
			v = vec3(texelFetch(tone, ivec2(int(v.r), 0), 0).r, texelFetch(tone, ivec2(int(v.g), 0), 0).r,
					texelFetch(tone, ivec2(int(v.b), 0), 0).r) * 255.0;
		}
		q = ivec3(v + 0.5);
	}
	int r5 = (q.r * 31 + 127) / 255;
	int g5 = (q.g * 31 + 127) / 255;
	int b5 = (q.b * 31 + 127) / 255;
	int code = (r5 << 10) | (g5 << 5) | b5;
	ivec2 pos = ivec2(code & 255, code >> 8);
	COLOR = vec4(texelFetch(lut, pos, 0).rgb, 1.0);
}
