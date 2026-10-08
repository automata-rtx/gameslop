// Server racks (02 §7, M2.2): the merged rack blocks of a level (BuildPlan class C_RACK).
// Body #15181F metal in 0.6 m rack units with dark seams and a 0.1 m post at each cell edge;
// on the fronts (vertex colour B = 1, the faces across the rows) server slots carry 1 cm
// status LEDs in columns, each a hashed one of #2EFF7A / #FF3B3B / #3B8BFF blinking at a
// hashed period of 0.5 to 4 s, emission x4. Ends and tops are plain panels. A small prop
// shader (02 §5): the Coherence jitter, and the world's unrender (Null, the noclip commit
// and its charge preview): albedo and LEDs to black, the 0.5 m world grid lines, and the
// world-anchored screen door at full unrender, in the opaque pipeline like the world.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 body_color : source_color = vec4(0.082353, 0.094118, 0.121569, 1.0);
uniform vec4 seam_color : source_color = vec4(0.02, 0.022, 0.03, 1.0);
uniform vec4 plate_color : source_color = vec4(0.12, 0.13, 0.16, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
uniform float metallic : hint_range(0.0, 1.0) = 0.4;
// Rack geometry (Tuning SERVER_RACK_UNIT_WIDTH, GRID_CELL_SIZE, SERVER_RACK_HEIGHT).
uniform float unit_width = 0.6;
uniform float cell_size = 2.0;
uniform float post_width = 0.1;
uniform float rack_top = 2.0;
// Server slots on a front: height and the dark gap between two.
uniform float slot_height = 0.0889;
uniform float slot_gap = 0.006;
uniform float led_radius = 0.005;
uniform float led_emission = 4.0;
uniform vec4 led_green : source_color = vec4(0.180392, 1.0, 0.478431, 1.0);
uniform vec4 led_red : source_color = vec4(1.0, 0.231373, 0.231373, 1.0);
uniform vec4 led_blue : source_color = vec4(0.231373, 0.545098, 1.0, 1.0);
uniform vec2 blink_period = vec2(0.5, 4.0);
// Fraction of LEDs that are lit at all (dark slots read as empty bays).
uniform float led_lit = 0.7;

const float GRID_SPACING = 0.5;          // WORLD_GRID_SPACING
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // WORLD_GRID_LINE_COLOR in linear

varying vec3 v_wp;
varying vec3 v_wn;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wp = wp;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float commit_hold = 1.0 - coh_commit_u(wp, CAMERA_POSITION_WORLD);
	VERTEX += coh_jitter(wp, 0.0, 0.0) * commit_hold;
}

vec2 grid_masks(vec2 g) {
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 d = abs(fract(g - 0.5) - 0.5) / fw;
	return 1.0 - clamp(d, 0.0, 1.0);
}

// 1 inside a band of half-width w around 0, anti-aliased.
float aa_band(float d, float w) {
	float fw = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(w - fw * 0.5, w + fw * 0.5, abs(d));
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec3 an = abs(n);
	bool vertical = an.y < 0.5;
	// Along the face horizontally, and the coordinate across it (which face this is).
	float s = an.x > an.z ? v_wp.z : v_wp.x;
	float across = an.x > an.z ? v_wp.x : v_wp.z;
	vec2 puv = vertical ? vec2(s, v_wp.y) : v_wp.xz;
	// Position within the cell along the row: [0, post) post, then three units, then post.
	float local = mod(s + cell_size * 0.5, cell_size);
	float in_units = local - post_width;
	float unit = floor(in_units / unit_width);
	float ul = in_units - unit * unit_width;
	bool post = local < post_width || local > cell_size - post_width;
	float rack_id = floor((s + cell_size * 0.5) / cell_size) * 3.0 + unit;

	vec3 base = body_color.rgb;
	vec3 emit = vec3(0.0);
	if (vertical) {
		float seam = max(aa_band(ul, 0.004), aa_band(ul - unit_width, 0.004));
		if (post) {
			base = seam_color.rgb * 1.6;
		} else if (COLOR.b > 0.5) {
			// A front: slots from 0.06 m to the top, each a faceplate with vents and LEDs.
			float y = v_wp.y - 0.06;
			float slot = floor(y / slot_height);
			float sy = y - slot * slot_height;
			float h = coh_hash13(vec3(rack_id, slot, floor(across * 2.0 + 0.5)));
			bool filled = y > 0.0 && v_wp.y < rack_top - 0.06 && h < 0.86;
			if (filled) {
				base = plate_color.rgb * mix(0.85, 1.1, h);
				// Vent slots across the right half of the plate.
				float vent = step(0.25, ul / unit_width) * aa_band(fract(ul * 90.0) - 0.5, 0.18) * aa_band(sy - slot_height * 0.5, slot_height * 0.28);
				base *= 1.0 - 0.45 * vent;
				// Three LEDs in a column near the left edge of the plate.
				for (int k = 0; k < 3; k++) {
					vec2 c = vec2(0.03 + float(k) * 0.016, slot_height * 0.5);
					vec2 d = vec2(ul, sy) - c;
					float fw = max(fwidth(ul), 1e-5);
					float r = max(led_radius, fw * 0.75);
					float m = (1.0 - smoothstep(r - fw * 0.5, r + fw * 0.5, length(d))) * (led_radius * led_radius) / (r * r);
					vec3 hh = coh_hash33(vec3(rack_id * 7.0 + float(k), slot, floor(across * 2.0 + 0.5)));
					if (hh.x > led_lit) {
						continue;
					}
					vec3 col = hh.y < 0.6 ? led_green.rgb : (hh.y < 0.85 ? led_blue.rgb : led_red.rgb);
					float period = mix(blink_period.x, blink_period.y, hh.z);
					float steady = step(0.55, fract(hh.z * 13.7));
					float on = max(steady, step(0.5, fract(TIME / period + hh.x * 5.3)));
					emit += col * led_emission * m * on;
				}
			}
			base = mix(base, seam_color.rgb, max(aa_band(sy, slot_gap * 0.5), seam));
		} else {
			// Side panels at the row ends: plain with the unit seams.
			base = mix(base, seam_color.rgb, seam);
		}
	} else {
		// The rack top: dark, with the unit seams across it.
		base *= 0.8;
	}

	float u = max(max(coh_null_u(v_wp), coh_commit_u(v_wp, CAMERA_POSITION_WORLD)), coh_preview_u(v_wp));
	float line = 0.0;
	if (u > 0.0) {
		vec2 lines = grid_masks(puv / GRID_SPACING);
		line = max(lines.x, lines.y) * smoothstep(0.0, 0.25, u);
		base = mix(base, vec3(0.0), u);
		emit = mix(emit, vec3(0.0), u);
	}
	ALBEDO = base * (1.0 - line);
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.5 * (1.0 - u);
	EMISSION = emit * (1.0 - line) + GRID_COLOR * line;
	ALPHA = (line < 0.5 && coh_screen_door(v_wp, u)) ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
