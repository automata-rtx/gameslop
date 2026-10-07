// The world shader (02 §5): one opaque ubershader for all level geometry, props and
// held objects. Variation comes from uniforms and the stratum's noise textures only.
// Never alpha blends: unrender is a dithered ALPHA_SCISSOR so the material stays in
// the opaque pipeline (depth writes, SSAO/SSIL, volumetric fog, decals all correct).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 14 §11: written every frame by CoherenceRenderer (and NullPresence through it).
global uniform float g_coherence;
global uniform float g_noclip_charge;
global uniform float g_noclip_commit;
global uniform vec3 g_null_pos;
global uniform float g_null_radius;
global uniform float g_time;

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
uniform float u_floor = 0.0;
// 02 §7 Cycle 2: vertex jitter floor (0.004).
uniform float jitter_floor = 0.0;
// 02 §7 Substrate: grid lines emit x1.5.
uniform float line_emission = 1.0;

// Constants mirrored from Tuning (02 §5); shaders cannot read GDScript.
const float JITTER_MAX = 0.012;
const float JITTER_NOCLIP = 0.04;
const float JITTER_HZ = 20.0;
const float UNRENDER_INNER = 0.6;
const float NOCLIP_RADIUS = 3.0;
const float NOCLIP_AIM_MAX = 2.5;
const float NOCLIP_PREVIEW_U = 0.9;
const float GRID_SPACING = 0.5;
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // #E6E6E6 in linear
const float UNRENDER_FULL = 0.95;
const float SCREEN_DOOR_MAX = 0.6;
const float SOFT_BAND_HZ = 0.5;
const float SOFT_BAND_AMPLITUDE = 0.03;
const float SOFT_PREVIEW_U = 0.3;
const float SOFT_PREVIEW_DIST = 2.0;
const float SOFT_PREVIEW_SPAN = 1.2;
const float CHECKER_SIZE = 1.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Patterns use the undisturbed position so they never swim; only the geometry trembles.
	v_world_pos = wp;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 02 §5: jitter = 0.012 smoothstep(0.5, 1, 1 - coherence) + 0.04 commit. Hashing the
	// world position keeps coincident vertices of neighbouring meshes together (no cracks).
	float drain = 1.0 - g_coherence;
	float jitter = max(jitter_floor, JITTER_MAX * smoothstep(0.5, 1.0, drain)) + JITTER_NOCLIP * g_noclip_commit;
	jitter *= 1.0 - held;
	if (jitter > 0.0) {
		// Stepped at 20 Hz so the tremble reads as a glitch rather than a blur under TAA.
		float step_t = floor(g_time * JITTER_HZ);
		VERTEX += (hash33(floor(wp * 100.0) + step_t * 7.31) * 2.0 - 1.0) * jitter;
	}
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

// Anti-aliased 1 px lines on a unit grid (fwidth-based, 02 §5).
float grid_mask(vec2 g) {
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 d = abs(fract(g - 0.5) - 0.5) / fw;
	return 1.0 - clamp(min(d.x, d.y), 0.0, 1.0);
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
		float tint = (hash12(cell) - 0.5) * 0.05;
		base = mix(a * (1.0 + tint), b, seam_mask(puv, pattern_scale, pattern_detail));
	} else if (pattern_mode == 2) {
		// Vertical stripes: secondary of width pattern_detail every pattern_scale metres.
		float x = fract(puv.x / pattern_scale) * pattern_scale;
		float fw = max(fwidth(puv.x), 1e-5);
		float s = smoothstep(-fw, fw, x) * (1.0 - smoothstep(pattern_detail - fw, pattern_detail + fw, x));
		base = mix(a, b, s);
	} else if (pattern_mode == 3) {
		// Carpet: two octaves of mottling plus fibre speckle.
		float m1 = texture(noise_albedo, puv * pattern_scale * 0.11).r;
		float m2 = texture(noise_albedo, puv * pattern_scale * 0.73 + 0.37).r;
		float fibre = hash12(floor(puv * 400.0));
		float k = m1 * 0.6 + m2 * 0.4;
		base = mix(b, a, 0.5) * mix(0.78, 1.18, k) * mix(0.92, 1.06, fibre);
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
		float tint = (hash12(cell) - 0.5) * 0.03;
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
				soft_u = SOFT_PREVIEW_U * (1.0 - smoothstep(SOFT_PREVIEW_SPAN * 0.6, SOFT_PREVIEW_SPAN, distance(hit, v_world_pos)));
			}
		}
	}

	// ---- unrender term u (02 §5) ----
	float u = u_floor;
	if (g_null_radius > 0.0) {
		u = max(u, smoothstep(g_null_radius, g_null_radius * UNRENDER_INNER, distance(v_world_pos, g_null_pos)));
	}
	float d_cam = distance(v_world_pos, cam);
	u = max(u, g_noclip_commit * smoothstep(NOCLIP_RADIUS, NOCLIP_RADIUS * 0.8, d_cam));
	if (g_noclip_charge > 0.001) {
		// 02 §9: preview around the aimed point (the ray within the 2.5 m aim range),
		// radius growing with charge. Capped below full so a cancelled charge never shows
		// what is behind the wall.
		float t = clamp(dot(v_world_pos - cam, fwd), 0.0, NOCLIP_AIM_MAX);
		float r = NOCLIP_RADIUS * g_noclip_charge;
		float dp = distance(v_world_pos, cam + fwd * t);
		u = max(u, NOCLIP_PREVIEW_U * g_noclip_charge * (1.0 - smoothstep(r * UNRENDER_INNER, r, dp)));
	}
	u = max(u, soft_u);
	u *= 1.0 - held;

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
		line = grid_mask(puv / GRID_SPACING) * smoothstep(0.0, 0.25, u);
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

	// Screen-door (02 §5): fully unrendered fills drop about 60% of pixels; lines stay.
	float door = u >= UNRENDER_FULL ? SCREEN_DOOR_MAX * u : 0.0;
	float h = hash12(floor(FRAGCOORD.xy));
	ALPHA = (line < 0.5 && h < door) ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
