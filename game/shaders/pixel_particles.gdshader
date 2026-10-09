// Substrate pixels (02 §10): 1 px white "pixels" drifting upward. A particle draw pass: each
// quad is pinned to its particle's centre and sized in screen pixels (`pixel_px`), so it is
// one pixel at any distance and any resolution; the distance fog to black still takes it.
// Unshaded: a pixel is a rendering artifact, not a lit object.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 pixel_color : source_color = vec4(0.902, 0.902, 0.902, 1.0);
uniform float pixel_px = 1.0;

void vertex() {
	// MODEL_MATRIX carries the particle's transform; VERTEX is the unit quad (-0.5..0.5).
	vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0));
	clip.xy += VERTEX.xy * 2.0 * pixel_px / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = pixel_color.rgb;
	ALPHA = pixel_color.a * COLOR.a;
}
