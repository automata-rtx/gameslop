// Static's field (02 §8): screen-space refraction driven by noise (0.04 offset) and a
// faint grey-noise fill (alpha 0.08), no lighting, no edge. Drawn on the sphere's back
// faces with the depth test off, so it shows from inside and outside; its strength is the
// part of the view ray inside the field and in front of the scene (depth buffer), weighted
// by the field's falloff, so a field behind a wall draws nothing and the rim fades to zero.
// It reads as a faint refraction shimmer, not smoke: the noise cells are large (a coherent
// wobble that bends what is behind it instead of scrambling it), the offset takes the
// falloff a second time (strength squared) so it eases to nothing toward the rim, and the
// offset shrinks with distance like a real refraction, so a field down a corridor does not
// smear the dark corridor end across the lit walls.
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

#include "res://shaders/include/coherence.gdshaderinc"

const float STATIC_OFFSET = 0.04;          // STATIC_DISTORTION_OFFSET
const float STATIC_FILL = 0.08;            // STATIC_FILL_ALPHA
const float STATIC_INNER = 0.6;            // STATIC_FIELD_FULL_FRACTION
const float STATIC_NOISE_CELLS = 7.0;      // shader-local: noise cells across the screen height
const float STATIC_NOISE_FINE = 2.7;       // shader-local: second octave, x the base cells
const float STATIC_NOISE_FINE_MIX = 0.3;   // shader-local: weight of the second octave
const float STATIC_NOISE_SPEED = 0.7;      // shader-local: noise drift, cells per second
const float STATIC_NEAR = 4.0;             // shader-local: full offset when the bent ray is this near (m)
const float STATIC_THICK = 0.8;            // shader-local: ray length (x r) inside the field for full strength
const float STATIC_GRAIN_FPS = 24.0;       // POST_GRAIN_FPS

instance uniform float radius = 4.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float static_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = coh_hash12(i);
	float b = coh_hash12(i + vec2(1.0, 0.0));
	float c = coh_hash12(i + vec2(0.0, 1.0));
	float d = coh_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// View space: the camera is at the origin.
	vec3 dir = normalize(VERTEX);
	vec3 c = (VIEW_MATRIX * vec4(NODE_POSITION_WORLD, 1.0)).xyz;
	float b = dot(c, dir);
	float d_axis = length(dir * b - c);
	float h2 = radius * radius - d_axis * d_axis;
	float strength = 0.0;
	float near = 1.0;
	if (h2 > 0.0) {
		float h = sqrt(h2);
		float t0 = max(b - h, 0.0);
		float t1 = b + h;
		float depth = texture(depth_tex, SCREEN_UV).r;
		vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		float scene_t = length(sv.xyz / sv.w);
		float seg = max(min(t1, scene_t) - t0, 0.0);
		float density = coh_falloff(radius * STATIC_INNER, radius, d_axis);
		strength = density * clamp(seg / (radius * STATIC_THICK), 0.0, 1.0);
		// The middle of the bent part of the ray (the camera inside the field: t0 = 0).
		near = STATIC_NEAR / max(t0 + 0.5 * seg, STATIC_NEAR);
	}
	float aspect = VIEWPORT_SIZE.x / max(VIEWPORT_SIZE.y, 1.0);
	vec2 p = SCREEN_UV * vec2(aspect, 1.0) * STATIC_NOISE_CELLS;
	float t = g_time * STATIC_NOISE_SPEED;
	vec2 n = vec2(static_value_noise(p + vec2(t, 0.0)), static_value_noise(p * 1.3 + vec2(0.0, -t) + 17.0));
	vec2 q = p * STATIC_NOISE_FINE;
	vec2 fine = vec2(static_value_noise(q + vec2(0.0, 2.0 * t) + 5.0), static_value_noise(q + vec2(-2.0 * t, 0.0) + 29.0));
	n = mix(n, fine, STATIC_NOISE_FINE_MIX);
	vec2 uv = clamp(SCREEN_UV + (n * 2.0 - 1.0) * STATIC_OFFSET * strength * strength * near, vec2(0.0), vec2(1.0));
	vec3 refracted = textureLod(screen_tex, uv, 0.0).rgb;
	float grain = coh_hash12(floor(FRAGCOORD.xy) + floor(g_time * STATIC_GRAIN_FPS) * 13.7);
	// The 8% fill is mixed in display space, so it stays faint over dark rooms (a linear
	// 0.04 would lift a dark corridor to mid-grey).
	vec3 shown = pow(max(refracted, vec3(0.0)), vec3(1.0 / 2.2));
	ALBEDO = pow(mix(shown, vec3(grain), STATIC_FILL), vec3(2.2));
	ALPHA = strength;
}
