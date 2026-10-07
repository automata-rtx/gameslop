// The Coherence renderer's post stack, scene pass (02 §4 step 6, §8 Null): a full-screen
// spatial quad, because only a spatial shader can read the depth buffer. It draws only
// the Null halo and core, and CoherenceRenderer shows it only while g_null_radius > 0.
// The grade (CA, desaturation, warmth, grain, vignette, scanline, pulses) runs after TAA
// over everything, transparent surfaces included, in coherence_screen.gdshader.
// The quad is drawn first in the transparent pass (render_priority minimum).
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform, shadows_disabled;

global uniform vec3 g_null_pos;
global uniform float g_null_radius;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform vec4 line_color : source_color = vec4(0.902, 0.902, 0.902, 1.0);

// 02 §8 Null: the 2 m core paints black with the halo over everything.
const float NULL_CORE = 2.0;             // NULL_CORE_RADIUS
// Laplacian / depth ratio over which a crease becomes a full line.
const float EDGE_LO = 0.06;              // shader-local: edge detector threshold
const float EDGE_HI = 0.15;              // shader-local: edge detector full strength

void vertex() {
	// Reversed-Z (Godot 4.3+): z = 1 is the near plane, so the quad always covers the view.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;

	float dn = distance(CAMERA_POSITION_WORLD, g_null_pos);
	float prox = g_null_radius > 0.0 ? clamp(1.0 - dn / g_null_radius, 0.0, 1.0) : 0.0;
	float core = g_null_radius > 0.0 ? 1.0 - smoothstep(NULL_CORE * 0.8, NULL_CORE, dn) : 0.0;
	if (prox > 0.0) {
		// The 21 unique device-depth taps of a 5 x 5 block without its corners, fetched once.
		// Index (y + 2) * 5 + (x + 2).
		float t[25];
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				int i = (y + 2) * 5 + (x + 2);
				if (abs(x) == 2 && abs(y) == 2) {
					t[i] = 0.0;
				} else {
					t[i] = textureLod(depth_tex, uv + vec2(float(x), float(y)) * px, 0.0).r;
				}
			}
		}
		// Nearest depth in the 3 x 3 block around each of five centres (reversed Z: larger
		// is nearer). Unrendered surfaces are screen-door dithered; the dilation closes the
		// holes so the halo outlines the geometry, not every discarded pixel.
		float d[5];
		ivec2 centres[5] = ivec2[](ivec2(0, 0), ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));
		for (int c = 0; c < 5; c++) {
			float m = 0.0;
			for (int y = -1; y <= 1; y++) {
				for (int x = -1; x <= 1; x++) {
					m = max(m, t[(centres[c].y + y + 2) * 5 + (centres[c].x + x + 2)]);
				}
			}
			d[c] = m;
		}
		// Device depth is affine in screen space across any plane, so its Laplacian is zero on
		// flat surfaces and spikes only at creases and silhouettes. Signed: only the nearer
		// side of a discontinuity draws, so the line is 1 px and a dithered hole never lights.
		float lap = 4.0 * d[0] - (d[1] + d[2] + d[3] + d[4]);
		float edge = smoothstep(EDGE_LO, EDGE_HI, lap / max(d[0], 1e-6));
		col = mix(col, vec3(0.0), core);
		col = mix(col, line_color.rgb, edge * max(prox, core));
	}
	ALBEDO = col;
}
