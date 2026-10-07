// The Coherence renderer's post stack, screen pass (02 §4 steps 1, 3, 5 and the 2-frame
// pulses). A canvas pass over the finished 3D image, so it runs after TAA: per-frame grain,
// tearing and flashes would otherwise be averaged away by the temporal resolve.
// Display-referred: amounts read as fractions of white. Fed by CoherencePost each frame.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform float ca = 0.0;          // 1. radial split, fraction of the screen
uniform float grain = 0.02;      // 3. luminance-only grain
uniform float scan = 0.0;        // 5. scanline tearing amount
uniform float invert = 0.0;      // hit: inverted-luminance flash
uniform float flash = 0.0;       // white flash (or the reduced 60% fade)
uniform float grain_time = 0.0;  // wall-clock seconds; grain keeps moving through hitstop

const float GRAIN_FPS = 24.0;    // film cadence
const float TEAR_ROWS = 0.035;   // fraction of rows torn at scan 1
const float TEAR_SHIFT = 0.025;  // max sideways shift, fraction of the width
const float TEAR_LIGHT = 0.03;   // torn rows carry a faint light line

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float frame_t = floor(grain_time * GRAIN_FPS);

	// 5. Scanline shimmer: a few 1 px rows torn sideways; nothing at full Coherence.
	float row = floor(FRAGCOORD.y);
	float torn = step(1.0 - TEAR_ROWS * scan, hash12(vec2(row, frame_t)));
	uv.x += torn * (hash12(vec2(frame_t, row)) - 0.5) * 2.0 * TEAR_SHIFT * scan;

	// 1. Chromatic aberration: radial RGB split.
	vec2 dir = uv - 0.5;
	vec3 col;
	col.r = textureLod(screen_tex, uv + dir * ca, 0.0).r;
	col.g = textureLod(screen_tex, uv, 0.0).g;
	col.b = textureLod(screen_tex, uv - dir * ca, 0.0).b;

	// 3. Film grain, luminance only (the same offset on every channel), always present.
	float g = (hash12(FRAGCOORD.xy + frame_t * 17.31) + hash12(FRAGCOORD.yx * 1.37 + frame_t * 7.77)) - 1.0;
	col += vec3(g * grain);
	col += torn * scan * TEAR_LIGHT;

	// Pulses: inverted luminance (hit), then the white flash.
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(1.0 - clamp(lum, 0.0, 1.0)), invert);
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
