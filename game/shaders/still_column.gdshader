// Still (02 §8): unlit pure black, alpha 1, no specular, no shadow, no light, no fog: a hole
// in the image. The render-line tick is a single 1 px white line across the column at
// `line_height` (0..1 of its height) while `line_on` is 1 (100 ms, set by ErrorStill).
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled, ambient_light_disabled, fog_disabled;

const float STILL_HEIGHT = 2.6;            // STILL_CAPSULE_HEIGHT

instance uniform float line_on = 0.0;
instance uniform float line_height = 0.5;

varying float v_h;

void vertex() {
	// ErrorStill.column_mesh() stands on its origin.
	v_h = VERTEX.y / STILL_HEIGHT;
}

void fragment() {
	float w = max(fwidth(v_h), 1e-5);
	float line = line_on * (1.0 - step(w * 0.5, abs(v_h - line_height)));
	ALBEDO = vec3(line);
}
