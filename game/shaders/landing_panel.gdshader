// The Landing item panel on the cabin wall (05 §4, 02 §7 Landing cabin): the panel's
// SubViewport (rendered at 2x its layout) drawn unshaded, box-filtered over the pixel's
// footprint with 4 x 4 taps. A viewport texture has no mipmaps, so plain bilinear sampling
// of a texture several times larger than its screen size drops strokes of the text; the
// taps average them instead, so the text reads at 960 x 540 and at 1080p.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform sampler2D panel_tex : source_color, filter_linear, repeat_disable;

const int TAPS = 4;

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec3 c = vec3(0.0);
	for (int i = 0; i < TAPS; i++) {
		for (int j = 0; j < TAPS; j++) {
			vec2 o = (vec2(float(i), float(j)) + 0.5) / float(TAPS) - 0.5;
			c += texture(panel_tex, UV + dx * o.x + dy * o.y).rgb;
		}
	}
	ALBEDO = c / float(TAPS * TAPS);
}
