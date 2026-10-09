// Pools bubbles (02 §10): small rising bubbles in the water. A camera-facing quad drawn as a
// thin bright rim around a faint body (a bubble reads by its outline), unshaded and
// translucent. The water surface refracts the opaque image only and writes depth, so
// bubbles draw after it (render_priority 1) without the depth test, testing the opaque
// depth themselves (walls and the deck still hide them), and carry the water themselves:
// the deeper a bubble, the more it takes the water's colour and the fainter it is.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec4 bubble_color : source_color = vec4(0.91, 0.965, 0.96, 1.0);
uniform vec4 water_color : source_color = vec4(0.18, 0.545, 0.545, 1.0);   // #2E8B8B
uniform float rim_alpha = 0.7;
uniform float body_alpha = 0.12;
// Depth under the surface (m) at which a bubble is as faint as it gets.
uniform float fade_depth = 1.8;
uniform float deep_alpha = 0.35;
// A bubble never draws smaller than this on screen (px), so a 1 cm bubble a few metres
// away still reads at 960 x 540 instead of vanishing under TAA; its alpha eases instead.
uniform float min_px = 3.0;
// ...but never more than this many times its real size (a far bubble just fades out).
uniform float max_grow = 4.0;
// Per basin: the water surface's world height.
instance uniform float surface_y = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float v_depth;
varying float v_fade;
// The bubble's drawn size on screen (px): a few-pixel bubble is a solid dot, a large one a rim.
varying float v_px;

void vertex() {
	// Billboard about the particle's own centre, keeping the particle's scale.
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 vc = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	float px = s * PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y * 0.5 / max(-vc.z, 0.05);
	float grow = clamp(min_px / max(px, 0.001), 1.0, max_grow);
	s *= grow;
	v_px = px * grow;
	v_fade = 1.0 / sqrt(grow);
	v_depth = clamp((surface_y - MODEL_MATRIX[3].y) / fade_depth, 0.0, 1.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s,
			INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	// Hidden behind opaque geometry (the opaque depth; the water's own depth is not in it).
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	if (VERTEX.z < sv.z / sv.w) {
		discard;
	}
	float r = length(UV - 0.5) * 2.0;
	float aa = min(fwidth(r) * 1.5, 0.35);
	float disc = 1.0 - smoothstep(1.0 - aa, 1.0, r);
	float rim = smoothstep(0.62 - aa, 0.82, r) * disc;
	float ring = body_alpha * disc + rim_alpha * rim;
	float shape = mix(rim_alpha * disc, ring, smoothstep(4.0, 10.0, v_px));
	ALBEDO = mix(bubble_color.rgb, water_color.rgb, 0.6 * v_depth);
	ALPHA = shape * COLOR.a * v_fade * mix(1.0, deep_alpha, v_depth);
}
