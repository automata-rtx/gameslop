// The world shader (02 §5): one opaque ubershader for all level geometry, props and
// held objects. Variation comes from uniforms and the stratum's noise textures only.
// Never alpha blends: unrender is a dithered ALPHA_SCISSOR so the material stays in
// the opaque pipeline (depth writes, SSAO/SSIL, volumetric fog, decals all correct).
// Globals, jitter and the unrender terms come from the shared Coherence include.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

// 02 §5 per-material uniforms.
uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 albedo_secondary : source_color = vec4(0.8, 0.8, 0.8, 1.0);
// 0 flat, 1 tiles, 2 stripes, 3 carpet, 4 concrete, 5 checker (placeholder), 6 panel.
uniform int pattern_mode : hint_range(0, 6) = 0;
// Metres: tile/panel size, stripe period. Carpet/concrete: noise frequency per metre.
uniform float pattern_scale = 1.0;
// Metres: grout (tiles), seam (panels), secondary stripe width (stripes).
uniform float pattern_detail = 0.01;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_strength = 0.0;
uniform sampler2D noise_albedo : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_strength = 0.0;
// Repeats of the noise textures per metre.
uniform float triplanar_scale = 0.5;
// How much the noise texture modulates albedo (0 = none).
uniform float noise_albedo_amount = 0.15;
uniform float vertex_color_weight = 0.0;
// 02 §5: held objects zero jitter and unrender so the player's hands never dissolve.
uniform float held = 0.0;
// 02 §5, 09: generator-marked passable wall.
uniform float soft = 0.0;
// 02 §7: Substrate permanent partial unrender (0.55); Cycle 2 corrupted surfaces (0.2).
// The placeholder checker (pattern 5) ignores it.
uniform float u_floor = 0.0;
// 02 §7 Cycle 2: vertex jitter floor (0.004).
uniform float jitter_floor = 0.0;
// 02 §7 Substrate: grid lines emit x1.5.
uniform float line_emission = 1.0;
// Stripes: the secondary colour pushed this far from the primary (1 = the palette pair).
uniform float pattern_contrast = 1.0;
// Stripes: strength of the printed detail (diamond print, pinstripes at the stripe edges).
uniform float print_amount = 0.0;

// Constants mirrored from Tuning (02 §5); a test parses each line against tuning.gd.
const float GRID_SPACING = 0.5;          // WORLD_GRID_SPACING
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // WORLD_GRID_LINE_COLOR in linear
const float SOFT_BAND_HZ = 0.5;          // WORLD_SOFT_BAND_HZ
const float SOFT_BAND_AMPLITUDE = 0.03;  // WORLD_SOFT_BAND_AMPLITUDE
const float SOFT_PREVIEW_U = 0.3;        // WORLD_SOFT_PREVIEW_U
const float SOFT_PREVIEW_DIST = 2.0;     // WORLD_SOFT_PREVIEW_DIST
const float SOFT_PREVIEW_SPAN = 1.2;     // WORLD_SOFT_PREVIEW_SPAN
const float CHECKER_SIZE = 1.0;          // WORLD_PLACEHOLDER_CHECKER
const float CARPET_LOOPS = 90.0;         // WORLD_CARPET_LOOPS_PER_M
const float PRINT_PERIOD = 0.15;         // WORLD_WALLPAPER_PRINT_PERIOD
const float PREVIEW_DASH = 8.0;          // WORLD_NOCLIP_INVALID_DASHES_PER_M

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Patterns use the undisturbed position so they never swim; only the geometry trembles.
	v_world_pos = wp;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 02 §5: jitter = 0.012 smoothstep(0.5, 1, 1 - coherence) + 0.04 commit, in object
	// space before projection; the offset is hashed from the world position (include).
	VERTEX += coh_jitter(wp, jitter_floor, held);
}

// Dominant-axis planar coordinates: x runs along the surface horizontally, y runs up on walls.
vec2 plane_uv(vec3 p, vec3 an, vec3 n, out vec3 ta, out vec3 tb) {
	if (an.y >= an.x && an.y >= an.z) {
		ta = vec3(1.0, 0.0, 0.0);
		tb = vec3(0.0, 0.0, 1.0);
		return p.xz;
	} else if (an.x >= an.z) {
		ta = vec3(0.0, 0.0, 1.0);
		tb = vec3(0.0, 1.0, 0.0);
		return p.zy;
	}
	ta = vec3(1.0, 0.0, 0.0);
	tb = vec3(0.0, 1.0, 0.0);
	return p.xy;
}

// Anti-aliased 1 px lines on a unit grid (fwidth-based, 02 §5). x: the lines of constant
// g.x (running along g.y); y: the lines of constant g.y.
vec2 grid_masks(vec2 g) {
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 d = abs(fract(g - 0.5) - 0.5) / fw;
	return 1.0 - clamp(d, 0.0, 1.0);
}

// Seam lines of physical width `w` metres on a grid of cell size `s` (AA, never thinner than 1 px).
float seam_mask(vec2 p, float s, float w) {
	vec2 g = p / s;
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 half_w = vec2(0.5 * w / s);
	vec2 d = abs(fract(g - 0.5) - 0.5);
	vec2 m = 1.0 - smoothstep(half_w - fw * 0.5, half_w + fw * 0.5, d);
	return max(m.x, m.y);
}

// 1 where `d` is within `w` of 0, anti-aliased over one pixel of `d`.
float aa_band(float d, float w) {
	float fw = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(w - fw * 0.5, w + fw * 0.5, abs(d));
}

// Halls carpet (02 §7): a loop pile, ~90 loops per metre in staggered rows. Each loop is a
// lit crown with a dark gap around it; the yarn tone varies per loop. Faded to its mean
// once a loop is under ~2.5 px, so it never shimmers under TAA.
float carpet_pile(vec2 p) {
	vec2 lp = p * CARPET_LOOPS;
	float row = floor(lp.y);
	lp.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(lp);
	vec2 f = fract(lp) - 0.5;
	float crown = 1.0 - smoothstep(0.12, 0.48, length(f * vec2(1.0, 1.35)));
	float yarn = coh_hash12(cell);
	float pile = mix(0.7, 1.1, crown) * mix(0.9, 1.08, yarn);
	float loops_per_px = max(fwidth(lp.x), fwidth(lp.y));
	return mix(0.93, pile, 1.0 - smoothstep(0.15, 0.32, loops_per_px));
}

// Halls wallpaper print: small diamond outlines with a dot, on a 0.15 m half-drop lattice.
float wallpaper_print(vec2 p) {
	vec2 q = p / PRINT_PERIOD;
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 f = fract(q) - 0.5;
	float dia = abs(f.x) + abs(f.y * 1.4);
	return max(aa_band(dia - 0.22, 0.025), 1.0 - smoothstep(0.03, 0.06, dia));
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 an = abs(n);
	vec3 ta;
	vec3 tb;
	vec2 puv = plane_uv(v_world_pos, an, n, ta, tb);
	vec3 cam = CAMERA_POSITION_WORLD;
	// The crosshair ray: the camera's forward axis (-Z of the inverse view).
	vec3 fwd = -normalize(INV_VIEW_MATRIX[2].xyz);

	// ---- surface pattern (02 §5, §7) ----
	vec3 a = albedo.rgb;
	vec3 b = albedo_secondary.rgb;
	float nz = texture(noise_albedo, puv * triplanar_scale).r;
	vec3 base = a;
	bool unlit = false;
	if (pattern_mode == 1) {
		vec2 cell = floor(puv / pattern_scale);
		float tint = (coh_hash12(cell) - 0.5) * 0.05;
		base = mix(a * (1.0 + tint), b, seam_mask(puv, pattern_scale, pattern_detail));
	} else if (pattern_mode == 2) {
		// Vertical stripes: secondary of width pattern_detail every pattern_scale metres.
		float x = fract(puv.x / pattern_scale) * pattern_scale;
		float fw = max(fwidth(puv.x), 1e-5);
		float s = smoothstep(-fw, fw, x) * (1.0 - smoothstep(pattern_detail - fw, pattern_detail + fw, x));
		vec3 b2 = max(a + (b - a) * pattern_contrast, vec3(0.0));
		base = mix(a, b2, s);
		if (print_amount > 0.0) {
			// Pinstripes 6 mm in from each stripe edge, and the diamond print in the wide band.
			float pin = max(aa_band(x - 0.006, 0.0015), aa_band(x - (pattern_detail - 0.006), 0.0015));
			float pr = wallpaper_print(puv) * (1.0 - s);
			base *= 1.0 - print_amount * max(pin, pr * 0.7);
		}
	} else if (pattern_mode == 3) {
		// Carpet: two octaves of mottling, a tuft scale, and the loop pile.
		float m1 = texture(noise_albedo, puv * pattern_scale * 0.11).r;
		float m2 = texture(noise_albedo, puv * pattern_scale * 0.73 + 0.37).r;
		float tuft = texture(noise_albedo, puv * 9.0 + 0.71).r;
		float k = m1 * 0.55 + m2 * 0.3 + tuft * 0.15;
		base = mix(b, a, 0.5) * mix(0.78, 1.18, k) * carpet_pile(puv);
	} else if (pattern_mode == 4) {
		float m1 = texture(noise_albedo, puv * pattern_scale * 0.25).r;
		float m2 = texture(noise_albedo, puv * pattern_scale * 1.7 + 0.5).r;
		base = mix(b, a, 0.5) * mix(0.72, 1.12, m1 * 0.7 + m2 * 0.3);
	} else if (pattern_mode == 5) {
		vec3 c = floor(v_world_pos / CHECKER_SIZE + n * 0.5);
		float k = mod(c.x + c.y + c.z, 2.0);
		base = mix(a, b, k);
		unlit = true;
	} else if (pattern_mode == 6) {
		vec2 cell = floor(puv / pattern_scale);
		float tint = (coh_hash12(cell) - 0.5) * 0.03;
		float fissure = texture(noise_albedo, puv * 3.1).r;
		vec3 panel = a * (1.0 + tint) * mix(0.93, 1.03, fissure);
		base = mix(panel, b, seam_mask(puv, pattern_scale, pattern_detail));
	}
	if (pattern_mode != 5 && pattern_mode != 3 && pattern_mode != 4) {
		base *= mix(1.0, mix(0.85, 1.1, nz), noise_albedo_amount);
	}
	base *= mix(vec3(1.0), COLOR.rgb, vertex_color_weight);

	// 02 §5 soft walls: a faint moving interference band, 0.5 Hz, amplitude 0.03.
	float soft_u = 0.0;
	if (soft > 0.5) {
		float ph = TAU * SOFT_BAND_HZ * g_time;
		base += SOFT_BAND_AMPLITUDE * sin(ph + v_world_pos.y * 2.2) * sin(ph * 0.5 - puv.x * 3.1 + v_world_pos.y * 0.7);
		// Aimed within 2 m: intersect the crosshair ray with this surface's plane.
		float facing = dot(fwd, n);
		if (facing < -0.05) {
			float t = dot(v_world_pos - cam, n) / facing;
			vec3 hit = cam + fwd * t;
			if (t > 0.0 && t < SOFT_PREVIEW_DIST) {
				soft_u = SOFT_PREVIEW_U * coh_falloff(SOFT_PREVIEW_SPAN * 0.6, SOFT_PREVIEW_SPAN, distance(hit, v_world_pos));
			}
		}
	}

	// ---- unrender term u (02 §5) ----
	// The placeholder checker is exempt from the Substrate floor: it must read magenta.
	float u_other = pattern_mode == 5 ? 0.0 : u_floor;
	u_other = max(u_other, coh_null_u(v_world_pos));
	u_other = max(u_other, coh_commit_u(v_world_pos, cam));
	u_other = max(u_other, soft_u);
	// 02 §9: the charge preview, a disc anchored at the noclip target.
	float u_prev = coh_preview_u(v_world_pos);
	float u = max(u_other, u_prev) * (1.0 - held);

	// ---- normal (noise, triplanar dominant plane) ----
	if (normal_strength > 0.0) {
		vec2 nm = texture(noise_normal, puv * triplanar_scale).xy * 2.0 - 1.0;
		vec3 nw = normalize(n + (ta * nm.x + tb * nm.y) * normal_strength * (1.0 - u));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}

	// ---- compose ----
	vec3 emit = emission.rgb * emission_strength;
	float line = 0.0;
	if (u > 0.0) {
		vec2 lines = grid_masks(puv / GRID_SPACING);
		if (g_noclip_invalid > 0.5 && u_prev > u_other) {
			// 11 §2 noclip invalid: the preview grid is dashed.
			lines.x *= step(0.5, fract(puv.y * PREVIEW_DASH));
			lines.y *= step(0.5, fract(puv.x * PREVIEW_DASH));
		}
		line = max(lines.x, lines.y) * smoothstep(0.0, 0.25, u);
		base = mix(base, vec3(0.0), u);
		emit = mix(emit, vec3(0.0), u);
	}
	if (unlit) {
		ALBEDO = vec3(0.0);
		emit += base;
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
	} else {
		ALBEDO = base * (1.0 - line);
		ROUGHNESS = roughness;
		METALLIC = metallic;
		SPECULAR = 0.5 * (1.0 - u);
	}
	EMISSION = emit * (1.0 - line) + GRID_COLOR * line * line_emission;

	// Screen door (02 §5): at u >= 0.95 a fraction 0.6 u of fill cells is discarded, on a
	// world-anchored lattice so the pattern sticks to the surface; lines always stay.
	ALPHA = (line < 0.5 && coh_screen_door(v_world_pos, u)) ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
