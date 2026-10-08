// Offices glass (07 §2 GLASS, M2.2): the meeting room's corridor wall, and the water
// cooler's bottle. A thin tinted pane, alpha-blended (glass is the one level surface that
// is see-through; it is never a walkable or noclip surface, 07 §7), with a Fresnel rise,
// a bottom rail and a door-height transom rail in the frame colour, and a frosted
// manifestation band at eye level so the pane reads as a pane. A small prop shader (02 §5):
// the Coherence jitter, and it fades out where the world unrenders.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.78, 0.86, 0.86, 0.12);
uniform vec4 frame_color : source_color = vec4(0.42, 0.44, 0.46, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform float fresnel_alpha = 0.35;
// Rails (world metres above y = 0; 0 width = none): bottom rail and transom.
uniform float rail_bottom = 0.08;
uniform float rail_transom_y = 2.1;
uniform float rail_transom = 0.05;
// Frosted band (y range, alpha).
uniform vec2 frost_band = vec2(1.0, 1.25);
uniform float frost_alpha = 0.35;

varying vec3 v_wp;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += coh_jitter(v_wp, 0.0, 0.0);
}

void fragment() {
	float y = v_wp.y;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 col = tint.rgb;
	float a = tint.a + fresnel_alpha * fres;
	bool rail = (rail_bottom > 0.0 && y < rail_bottom) || (rail_transom > 0.0 && abs(y - rail_transom_y) < rail_transom * 0.5);
	if (rail) {
		col = frame_color.rgb;
		a = 1.0;
	} else if (y > frost_band.x && y < frost_band.y) {
		col = mix(col, vec3(0.92), 0.6);
		a = max(a, frost_alpha);
	}
	float u = max(coh_null_u(v_wp), coh_commit_u(v_wp, CAMERA_POSITION_WORLD));
	ALBEDO = col;
	ROUGHNESS = rail ? 0.4 : roughness;
	METALLIC = rail ? 0.6 : 0.0;
	SPECULAR = 0.6;
	ALPHA = a * (1.0 - u);
}
