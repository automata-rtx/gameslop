// Server cages (07 §5.5 "GLASS-like mesh fences", M2.2): the GLASS edges of a cage drawn as
// galvanised chain-link, a 5 cm diamond mesh of 3 mm wire, through which the aisle and the
// item inside stay visible (sight passes, 07 §2). The mesh is cut with the alpha scissor:
// where a wire is narrower than a pixel its coverage is dithered on a screen lattice (TAA
// resolves it), so the fence fades to a grey haze at distance instead of vanishing. A
// bottom and a top rail and the posts (the plan's wall class) frame each 2 m panel. A small
// prop shader (02 §5): the Coherence jitter, and the world's unrender lines and screen door.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 wire_color : source_color = vec4(0.43, 0.46, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
uniform float pitch = 0.05;
uniform float wire = 0.003;
uniform float rail_bottom = 0.06;
uniform float rail_top_from = 3.42;

const float GRID_SPACING = 0.5;          // WORLD_GRID_SPACING
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // WORLD_GRID_LINE_COLOR in linear

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX += coh_jitter(v_wp, 0.0, 0.0);
}

void fragment() {
	vec3 an = abs(normalize(v_wn));
	float s = an.x > an.z ? v_wp.z : v_wp.x;
	vec2 p = vec2(s, v_wp.y);
	// Diamond lattice: lines along both diagonals.
	vec2 g = vec2(p.x + p.y, p.x - p.y) / (pitch * 1.41421);
	vec2 fw = max(fwidth(g), vec2(1e-5));
	float w = wire / (pitch * 1.41421);
	// Distance to the nearest wire centre, in lattice units; a wire narrower than a pixel is
	// widened to one and its coverage scaled down to match (energy kept).
	vec2 dist = 0.5 - abs(fract(g) - 0.5);
	vec2 ww = max(vec2(w), fw);
	vec2 m = (1.0 - smoothstep(ww * 0.5 - fw * 0.5, ww * 0.5 + fw * 0.5, dist)) * (w / ww);
	float cover = 1.0 - (1.0 - m.x) * (1.0 - m.y);
	bool rail = v_wp.y < rail_bottom || v_wp.y > rail_top_from;
	if (rail) {
		cover = 1.0;
	}
	float dither = coh_hash12(floor(FRAGCOORD.xy));
	float u = max(max(coh_null_u(v_wp), coh_commit_u(v_wp, CAMERA_POSITION_WORLD)), coh_preview_u(v_wp));
	vec3 base = wire_color.rgb * (rail ? 0.8 : 1.0);
	float line = 0.0;
	if (u > 0.0) {
		vec2 gl = p / GRID_SPACING;
		vec2 gfw = max(fwidth(gl), vec2(1e-5));
		vec2 gd = abs(fract(gl - 0.5) - 0.5) / gfw;
		vec2 lm = 1.0 - clamp(gd, 0.0, 1.0);
		line = max(lm.x, lm.y) * smoothstep(0.0, 0.25, u);
		base = mix(base, vec3(0.0), u);
	}
	ALBEDO = base * (1.0 - line);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = GRID_COLOR * line;
	ALPHA = (cover > dither || line > 0.5) && !(line < 0.5 && coh_screen_door(v_wp, u)) ? 1.0 : 0.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
