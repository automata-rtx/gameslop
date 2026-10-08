// Offices monitors (02 §7, M2.2): the screen face of a 0.5 x 0.3 m monitor on a desk. Dark
// blue #0E1A2B with slowly scrolling pale text: rows of noise-thresholded "words", emission
// x2. About once in 4,000 frames a monitor shows the NOCLIP glyph for one frame (02 §7: no
// one will be sure they saw it). A small prop shader (02 §5): the Coherence jitter, and the
// screen goes black where the world unrenders. The screen quad's UV runs 0..1 across it.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 screen_color : source_color = vec4(0.054902, 0.101961, 0.168627, 1.0);
uniform vec4 text_color : source_color = vec4(0.62, 0.72, 0.82, 1.0);
uniform float emission_strength = 2.0;
// Text rows on the screen, characters per row, scroll speed in rows per second.
uniform float rows = 16.0;
uniform float columns = 40.0;
uniform float scroll = 0.12;
// Chance per frame per monitor of the one-frame glyph (02 §7: 1 in 4,000 frames).
uniform float glyph_chance = 0.00025;
uniform float frame_rate = 60.0;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += coh_jitter(v_wp, 0.0, 0.0);
}

// 5x6 bitmap letters of NOCLIP, one row per 5 bits (row 0 at the top).
int letter_row(int letter, int row) {
	// N O C L I P
	int n[6] = int[](17, 25, 21, 19, 17, 17);
	int o[6] = int[](14, 17, 17, 17, 17, 14);
	int c[6] = int[](14, 17, 16, 16, 17, 14);
	int l[6] = int[](16, 16, 16, 16, 16, 31);
	int i[6] = int[](14, 4, 4, 4, 4, 14);
	int p[6] = int[](30, 17, 17, 30, 16, 16);
	if (letter == 0) { return n[row]; }
	if (letter == 1) { return o[row]; }
	if (letter == 2) { return c[row]; }
	if (letter == 3) { return l[row]; }
	if (letter == 4) { return i[row]; }
	return p[row];
}

float glyph(vec2 uv) {
	// Six letters, each 5 wide plus a gap, centred on the screen.
	vec2 g = (uv - vec2(0.14, 0.38)) / vec2(0.72, 0.24);
	if (g.x < 0.0 || g.x >= 1.0 || g.y < 0.0 || g.y >= 1.0) {
		return 0.0;
	}
	float cx = g.x * 36.0;
	int letter = int(floor(cx / 6.0));
	int col = int(floor(mod(cx, 6.0)));
	int row = int(floor(g.y * 6.0));
	if (col > 4) {
		return 0.0;
	}
	int bits = letter_row(letter, row);
	return float((bits >> (4 - col)) & 1);
}

void fragment() {
	vec2 uv = UV;
	float seed = coh_hash13(floor(NODE_POSITION_WORLD * 10.0));
	float t = TIME * scroll + seed * 100.0;
	float y = uv.y * rows + t;
	float row = floor(y);
	float in_row = fract(y);
	float col = floor(uv.x * columns);
	// Line length and indentation per row, words of hashed lengths, glyph noise inside.
	float len = coh_hash12(vec2(row, seed * 31.0)) * columns * 0.9;
	float indent = floor(coh_hash12(vec2(row, seed * 17.0 + 3.0)) * 3.0) * 2.0;
	float word = coh_hash12(vec2(floor((col + coh_hash12(vec2(row, 5.0)) * 7.0) / 5.0), row + seed));
	float ink = step(indent, col) * step(col, indent + len) * step(0.18, word);
	ink *= step(0.3, coh_hash12(vec2(col, row) + seed * 9.0));
	ink *= step(0.25, in_row) * step(in_row, 0.75);
	vec3 c = mix(screen_color.rgb, text_color.rgb, ink * 0.8);
	// The one-frame glyph.
	float frame = floor(TIME * frame_rate);
	if (coh_hash12(vec2(frame, seed * 997.0)) < glyph_chance) {
		c = mix(screen_color.rgb * 0.6, vec3(0.9), glyph(uv));
	}
	// A faint scanline and edge falloff, so it reads as a lit tube, not a flat sticker.
	c *= 0.92 + 0.08 * sin(uv.y * rows * 6.2831 * 3.0);
	c *= 1.0 - 0.35 * pow(max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0, 4.0);
	float u = max(coh_null_u(v_wp), coh_commit_u(v_wp, CAMERA_POSITION_WORLD));
	ALBEDO = c * 0.15 * (1.0 - u);
	ROUGHNESS = 0.25;
	SPECULAR = 0.5 * (1.0 - u);
	EMISSION = c * emission_strength * (1.0 - u);
}
