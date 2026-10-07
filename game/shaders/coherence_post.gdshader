// The Coherence renderer's post stack, scene pass (02 §4 steps 2, 4, 6): a full-screen
// spatial quad, because only a spatial shader can read the depth buffer (the Null halo).
// The screen-only steps that change every frame (1 CA, 3 grain, 5 scanline, and the
// 2-frame flashes) run after TAA in coherence_screen.gdshader, or TAA would average them away.
// The quad is drawn first in the transparent pass (render_priority minimum), so it sees
// the opaque image; transparent effects that read g_coherence themselves draw over it.
// All amounts are computed by CoherencePost (GDScript, unit-tested) and fed per frame.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform, shadows_disabled;

global uniform vec3 g_null_pos;
global uniform float g_null_radius;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

uniform float sat = 1.0;         // 2. saturation (1 = untouched, >1 overshoot)
uniform float warmth = 0.0;      // coherence_gain warmth
uniform float vig = 0.15;        // 4. vignette (base + threat)
uniform vec4 line_color : source_color = vec4(0.902, 0.902, 0.902, 1.0);

// 02 §8 Null: the 2 m core paints black with the halo over everything.
const float NULL_CORE = 2.0;

// Nearest device depth in a 3 x 3 block (reversed Z: larger is nearer). Unrendered
// surfaces are screen-door dithered; the dilation closes the holes so the halo outlines
// the geometry, not every discarded pixel.
float near_depth(vec2 uv, vec2 px) {
	float d = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			d = max(d, textureLod(depth_tex, uv + vec2(float(x), float(y)) * px, 0.0).r);
		}
	}
	return d;
}

void vertex() {
	// Reversed-Z (Godot 4.3+): z = 1 is the near plane, so the quad always covers the view.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 col = textureLod(screen_tex, uv, 0.0).rgb;

	// 2. Desaturation (and the gain overshoot / warmth).
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(lum), col, sat), vec3(0.0));
	col *= vec3(1.0 + warmth, 1.0 + warmth * 0.3, 1.0 - warmth);

	// 4. Vignette.
	vec2 dir = uv - 0.5;
	float r = length(dir * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0)) / 0.9;
	col *= 1.0 - vig * smoothstep(0.25, 1.05, r);

	// 6. Edge halo near Null: 1 px outline from the depth buffer; the 2 m core is black.
	if (g_null_radius > 0.0) {
		float dn = distance(CAMERA_POSITION_WORLD, g_null_pos);
		float prox = clamp(1.0 - dn / g_null_radius, 0.0, 1.0);
		float core = 1.0 - smoothstep(NULL_CORE * 0.8, NULL_CORE, dn);
		if (prox > 0.0) {
			// Device depth is affine in screen space across any plane, so its Laplacian is
			// zero on flat surfaces and spikes only at creases and silhouettes.
			float dc = near_depth(uv, px);
			// Signed: only the nearer side of a discontinuity draws, so the line is 1 px and
			// a dithered hole (farther than its neighbours) never lights up.
			float lap = 4.0 * dc - (near_depth(uv - vec2(px.x, 0.0), px) + near_depth(uv + vec2(px.x, 0.0), px)
					+ near_depth(uv - vec2(0.0, px.y), px) + near_depth(uv + vec2(0.0, px.y), px));
			float edge = smoothstep(0.06, 0.15, lap / max(dc, 1e-6));
			col = mix(col, vec3(0.0), core);
			col = mix(col, line_color.rgb, edge * max(prox, core));
		}
	}
	ALBEDO = col;
}
