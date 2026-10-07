// The Coherence renderer's post stack, screen pass (02 §4 steps 1 to 5 and the pulses).
// A canvas pass over the finished 3D image (layer -10, under the HUD), so it runs after
// TAA, which would otherwise average per-frame grain, tearing and flashes away, and it
// grades everything the camera drew, transparent surfaces included.
// Display-referred: amounts read as fractions of white. Fed by CoherencePost each frame.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

uniform float ca = 0.0;          // 1. radial split, fraction of the screen
uniform float sat = 1.0;         // 2. saturation (1 = untouched, > 1 overshoot)
uniform float warmth = 0.0;      // coherence_gain warmth
uniform float grain = 0.02;      // 3. luminance-only grain
uniform float vig = 0.15;        // 4. vignette (base + threat)
uniform float scan = 0.0;        // 5. scanline tearing amount
uniform float invert = 0.0;      // hit: inverted-luminance flash
uniform float flash = 0.0;       // white flash (or the reduced 60% fade)
uniform float black = 0.0;       // drop: the image to black (grain stays on top)
uniform float ripple = -1.0;     // Landing ripple progress 0..1; < 0 when idle
uniform float grain_time = 0.0;  // wall-clock seconds; grain keeps moving through hitstop

const float GRAIN_FPS = 24.0;        // POST_GRAIN_FPS
const float TEAR_ROWS = 0.035;       // POST_TEAR_ROWS
const float TEAR_SHIFT = 0.025;      // POST_TEAR_SHIFT
const float TEAR_LIGHT = 0.03;       // POST_TEAR_LIGHT
const float RIPPLE_WIDTH = 0.05;     // POST_RIPPLE_WIDTH
const float RIPPLE_SHIFT = 0.008;    // POST_RIPPLE_SHIFT
const float RIPPLE_LIGHT = 0.12;     // POST_RIPPLE_LIGHT
const vec3 LINE_COLOR = vec3(0.902, 0.902, 0.902); // POST_NULL_LINE_COLOR

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Every shifted read stays inside the image. A read past an edge is mirrored back in (a
// clamp would repeat the border texel into a streak), then kept half a texel inside.
vec2 inside(vec2 uv, vec2 px) {
	vec2 m = 1.0 - abs(1.0 - abs(uv));
	return clamp(m, px * 0.5, 1.0 - px * 0.5);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	float frame_t = floor(grain_time * GRAIN_FPS);
	float aspect = px.y / px.x;

	// 5. Scanline shimmer: a few 1 px rows torn sideways; nothing at full Coherence.
	float row = floor(FRAGCOORD.y);
	float torn = step(1.0 - TEAR_ROWS * scan, hash12(vec2(row, frame_t)));
	uv.x += torn * (hash12(vec2(frame_t, row)) - 0.5) * 2.0 * TEAR_SHIFT * scan;

	// Landing ripple (11 §3): one ring of unrender crossing the screen from the centre.
	float ring = 0.0;
	vec2 rdir = (uv - 0.5) * vec2(aspect, 1.0);
	if (ripple >= 0.0) {
		float rr = length(rdir);
		ring = (1.0 - smoothstep(0.0, RIPPLE_WIDTH, abs(rr - ripple * 1.1))) * (1.0 - ripple);
		uv += normalize(rdir + 1e-6) / vec2(aspect, 1.0) * RIPPLE_SHIFT * ring;
	}

	// 1. Chromatic aberration: radial RGB split. Red reads the image as is, green and blue
	// progressively pulled toward the centre, so no channel reads past the edge.
	vec2 dir = uv - 0.5;
	vec3 col;
	col.r = textureLod(screen_tex, inside(uv, px), 0.0).r;
	col.g = textureLod(screen_tex, inside(uv - dir * ca, px), 0.0).g;
	col.b = textureLod(screen_tex, inside(uv - dir * 2.0 * ca, px), 0.0).b;

	// 2. Desaturation (and the gain overshoot / warmth).
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(lum), col, sat), vec3(0.0));
	col *= vec3(1.0 + warmth, 1.0 + warmth * 0.3, 1.0 - warmth);

	// 4. Vignette.
	float r = length((SCREEN_UV - 0.5) * vec2(aspect, 1.0)) / 0.9;
	col *= 1.0 - vig * smoothstep(0.25, 1.05, r);

	col += LINE_COLOR * RIPPLE_LIGHT * ring;
	// Drop: black under the grain.
	col *= 1.0 - black;

	// 3. Film grain, luminance only (the same offset on every channel), always present.
	float g = (hash12(FRAGCOORD.xy + frame_t * 17.31) + hash12(FRAGCOORD.yx * 1.37 + frame_t * 7.77)) - 1.0;
	col += vec3(g * grain);
	col += torn * scan * TEAR_LIGHT;

	// Pulses: inverted luminance (hit), then the white flash.
	lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(col, vec3(1.0 - clamp(lum, 0.0, 1.0)), invert);
	col = mix(col, vec3(1.0), flash);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
