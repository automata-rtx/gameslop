// Fixture ceiling glow (02 §6, §7 Halls; R4 V3): a soft additive halo on the ceiling tile
// around a tube, so a fixture reads as installed in the ceiling rather than stuck on it.
// A small prop shader (02 §5): it reads the Coherence globals and vanishes where the world
// unrenders (Null, the noclip commit), like the surface it sits on.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 glow_color : source_color = vec4(1.0, 0.95, 0.77, 1.0);
// Per fixture (power, the buzzing fixtures' 85%): set_instance_shader_parameter.
instance uniform float energy = 0.0;
// Half size of the glowing tube in the quad's UV space (0..0.5), and the falloff beyond it.
uniform vec2 core = vec2(0.2, 0.1);
uniform float falloff = 0.22;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += coh_jitter(v_world_pos, 0.0, 0.0);
}

void fragment() {
	vec2 q = abs(UV - 0.5);
	// Distance outside the tube's rectangle, in UV units, rounded at the corners.
	vec2 o = max(q - core, vec2(0.0));
	float d = length(o) / falloff;
	float g = exp(-d * d * 3.0) * (1.0 - smoothstep(0.85, 1.0, max(q.x, q.y) * 2.0));
	float u = max(coh_null_u(v_world_pos), coh_commit_u(v_world_pos, CAMERA_POSITION_WORLD));
	// Unshaded: ALBEDO is the output (added to what is behind; HDR, so above 1 is fine).
	ALBEDO = glow_color.rgb * energy * g * (1.0 - u);
}
