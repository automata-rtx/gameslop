// Echo (02 §8): no body. Within 4 m a man-sized capsule region of screen-space heat-shimmer:
// refraction 0.015, no fill, no lighting. The offset is a slow coherent wobble (rising like
// heat) that bends what is behind the capsule; it eases to nothing at the silhouette (the
// view-facing term), so there is no edge, and it scales with `presence` (ErrorEcho: 1 within
// 4 m, 0 beyond 4.4 m). Depth-tested: a wall in front hides it, as a body would be hidden.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled, blend_mix, specular_disabled, ambient_light_disabled;

#include "res://shaders/include/coherence.gdshaderinc"

const float ECHO_OFFSET = 0.015;           // 02 §8 refraction
const float ECHO_NOISE_CELLS = 9.0;        // shader-local: wobble cells across the capsule's screen height
const float ECHO_NOISE_SPEED = 0.9;        // shader-local: rise speed, cells per second
const float ECHO_RIM_POWER = 1.5;          // shader-local: falloff toward the silhouette

instance uniform float presence = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

float echo_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = coh_hash12(i);
	float b = coh_hash12(i + vec2(1.0, 0.0));
	float c = coh_hash12(i + vec2(0.0, 1.0));
	float d = coh_hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	// Facing term: 1 where the surface faces the camera, 0 at the silhouette.
	float facing = pow(clamp(dot(normalize(NORMAL), normalize(-VERTEX)), 0.0, 1.0), ECHO_RIM_POWER);
	float t = g_time * ECHO_NOISE_SPEED;
	// Object-space cells so the wobble stays on the body; it rises.
	vec2 p = vec2(atan(v_local.z, v_local.x) * 1.6, v_local.y) * ECHO_NOISE_CELLS * 0.5;
	vec2 n = vec2(echo_value_noise(p + vec2(0.0, -t)), echo_value_noise(p * 1.3 + vec2(11.0, -1.3 * t)));
	float strength = presence * facing;
	vec2 uv = clamp(SCREEN_UV + (n * 2.0 - 1.0) * ECHO_OFFSET * strength, vec2(0.0), vec2(1.0));
	ALBEDO = textureLod(screen_tex, uv, 0.0).rgb;
	ALPHA = clamp(strength * 4.0, 0.0, 1.0);
}
