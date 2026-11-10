shader_type canvas_item;
render_mode unshaded;

// Convert the composed 320x200 RGB frame to the project's VGA-style 256-color
// grade, exactly like period_palette.VGAPalette.apply (RGB555 -> palette LUT).
uniform sampler2D lut : filter_nearest, repeat_disable;

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	ivec3 q = ivec3(clamp(c, 0.0, 1.0) * 255.0 + 0.5);
	int r5 = (q.r * 31 + 127) / 255;
	int g5 = (q.g * 31 + 127) / 255;
	int b5 = (q.b * 31 + 127) / 255;
	int code = (r5 << 10) | (g5 << 5) | b5;
	ivec2 pos = ivec2(code & 255, code >> 8);
	COLOR = vec4(texelFetch(lut, pos, 0).rgb, 1.0);
}
