// Pools water (02 §7): a planar, translucent surface #2E8B8B at alpha 0.75, two scrolling
// normal layers from the stratum's NoiseTexture2D, specular highlights from the fixtures,
// a 0.03 screen-space refraction of what lies below, no foam. A small prop shader (02 §5):
// it takes the Coherence jitter and fades to black where the world unrenders (Null, the
// noclip commit), like the tiles around it. The grade runs over it in the screen pass.
// M2.1 basic version; M2.13 polishes.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 water_color : source_color = vec4(0.180392, 0.545098, 0.545098, 0.75);
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap, repeat_enable;
// Metres per normal-map repeat for the two layers, and their drift (m/s).
uniform float scale_a = 0.09;
uniform float scale_b = 0.23;
uniform vec2 drift_a = vec2(0.011, 0.006);
uniform vec2 drift_b = vec2(-0.007, 0.009);
uniform float normal_strength = 0.35;
// Screen-space refraction (02 §7: 0.03).
uniform float refraction = 0.03;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += coh_jitter(v_world_pos, 0.0, 0.0);
}

void fragment() {
	vec2 p = v_world_pos.xz;
	vec2 na = texture(normal_noise, p * scale_a + drift_a * g_time).xy * 2.0 - 1.0;
	vec2 nb = texture(normal_noise, p * scale_b + drift_b * g_time).xy * 2.0 - 1.0;
	vec2 slope = (na + nb) * 0.5 * normal_strength;
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	if (!FRONT_FACING) {
		nw = -nw;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// What lies below, bent by the ripples; it passes through at (1 - alpha).
	vec3 below = textureLod(screen_tex, clamp(SCREEN_UV + slope * refraction, vec2(0.001), vec2(0.999)), 0.0).rgb;
	float a = water_color.a;
	float u = max(coh_null_u(v_world_pos), coh_commit_u(v_world_pos, CAMERA_POSITION_WORLD));
	ALBEDO = water_color.rgb * a * (1.0 - u);
	EMISSION = below * (1.0 - a) * (1.0 - u);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.6 * (1.0 - u);
	ALPHA = 1.0 - 0.6 * u;
}
