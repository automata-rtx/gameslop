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
// 02 §7 Cycle 2: faces of cells the generator flagged UNFINISHED (vertex colour G) take this u.
uniform float unfinished_u = 0.0;
// Stripes: the secondary colour pushed this far from the primary (1 = the palette pair).
uniform float pattern_contrast = 1.0;
// Stripes: strength of the printed detail (diamond print, pinstripes at the stripe edges).
uniform float print_amount = 0.0;
// Stripes: metres over which the stripe contrast falls back to the palette pair (1.0), so far
// walls read as one tone with the print, not as bars. x = start, y = end; y <= x = off.
uniform vec2 contrast_fade = vec2(0.0);
// Level surfaces (07 §8 vertex colour): +- tint per cell from the R hash (0 = off).
uniform float cell_tint = 0.0;
// Walls (vertical faces, 02 §7 Halls): a darker, glossier baseboard band below this height
// (m above the floor; 0 = off), its darkening and roughness.
uniform float baseboard_height = 0.0;
uniform float baseboard_darken = 0.4;
uniform float baseboard_roughness = 0.45;
// Walls: a thin shadow line under the ceiling at this height (m; 0 = off), its width and depth.
uniform float ceiling_line_y = 0.0;
uniform float ceiling_line_width = 0.05;
uniform float ceiling_line_darken = 0.35;
// A painted horizontal band on walls (02 §7 Garage: #D9D0B0 at 1.2 m): its centre height
// above each floor level `band_period` apart (0: absolute), its width (0 = off) and colour.
uniform vec4 band_color : source_color = vec4(0.85, 0.82, 0.69, 1.0);
uniform float band_y = 1.2;
uniform float band_width = 0.0;
uniform float band_period = 0.0;
// Floors (vertex colour B = metres to the nearest wall, 07 §8): darkening at the wall seam
// within floor_seam_width metres (0 = off), and carpet wear lanes along corridor centre lines
// (vertex colour A marks corridors): lighter, flattened pile where B > wear_from.
uniform float floor_seam = 0.0;
uniform float floor_seam_width = 0.25;
uniform float wear = 0.0;
uniform float wear_from = 0.55;
// Tiles (02 §7 Pools): the grout's roughness (< 0: the tile's), and a bevel of this width (m;
// 0 = off) where the glazed tile's edge rolls into the grout, so fixture highlights break on
// the grid. The bevel fades out once a tile is a few pixels wide (no shimmer under TAA).
uniform float grout_roughness = -1.0;
uniform float tile_bevel = 0.0;
// Wet sheen (02 §7 Pools): `wet` makes the whole surface wet (basin interiors); `puddles` is
// the share of a floor under standing water, in low-frequency noise patches about
// `puddle_scale` metres across. Wet tile is darker and near-mirror smooth.
uniform float wet = 0.0;
uniform float puddles = 0.0;
uniform float puddle_scale = 3.0;
uniform float wet_roughness = 0.05;
uniform float wet_darken = 0.12;

// Constants mirrored from Tuning (02 §5); a test parses each line against tuning.gd.
const float GRID_SPACING = 0.5;          // WORLD_GRID_SPACING
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // WORLD_GRID_LINE_COLOR in linear
const float SOFT_BAND_HZ = 0.5;          // WORLD_SOFT_BAND_HZ
const float SOFT_BAND_AMPLITUDE = 0.08;  // WORLD_SOFT_BAND_AMPLITUDE
const float SOFT_BAND_K = 6.3;           // WORLD_SOFT_BAND_K
const float SOFT_PREVIEW_U = 0.3;        // WORLD_SOFT_PREVIEW_U
const float SOFT_PREVIEW_DIST = 2.0;     // WORLD_SOFT_PREVIEW_DIST
const float SOFT_PREVIEW_SPAN = 1.2;     // WORLD_SOFT_PREVIEW_SPAN
const float CHECKER_SIZE = 1.0;          // WORLD_PLACEHOLDER_CHECKER
const float CARPET_LOOPS = 90.0;         // WORLD_CARPET_LOOPS_PER_M
const float PRINT_PERIOD = 0.15;         // WORLD_WALLPAPER_PRINT_PERIOD
const float PREVIEW_DASH = 8.0;          // WORLD_NOCLIP_INVALID_DASHES_PER_M
const float COMMIT_LINE_PX = 2.5;        // WORLD_COMMIT_LINE_PX
const float COMMIT_LINE_GAIN = 3.0;      // WORLD_COMMIT_LINE_GAIN

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Patterns use the undisturbed position so they never swim; only the geometry trembles.
	v_world_pos = wp;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 02 §5: jitter = 0.012 smoothstep(0.5, 1, 1 - coherence) + 0.04 commit, in object
	// space before projection; the offset is hashed from the world position (include).
	// M3.2: geometry inside the noclip commit radius is drawn as lines; it does not take the
	// commit's 0.04 m tremble, so the lines the player passes through hold still.
	float commit_hold = 1.0 - coh_commit_u(wp, CAMERA_POSITION_WORLD);
	VERTEX += coh_jitter(wp, jitter_floor, held) * commit_hold;
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

// Anti-aliased lines on a unit grid (fwidth-based, 02 §5): `width_px` pixels wide on screen
// whatever the distance (1 normally). x: the lines of constant g.x (running along g.y);
// y: the lines of constant g.y.
vec2 grid_masks(vec2 g, float width_px) {
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 d = abs(fract(g - 0.5) - 0.5) / fw;
	return 1.0 - clamp(d - (width_px - 1.0) * 0.5, 0.0, 1.0);
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
float carpet_pile(vec2 p, float flatten) {
	vec2 lp = p * CARPET_LOOPS;
	float row = floor(lp.y);
	lp.x += 0.5 * mod(row, 2.0);
	vec2 cell = floor(lp);
	vec2 f = fract(lp) - 0.5;
	float crown = 1.0 - smoothstep(0.12, 0.48, length(f * vec2(1.0, 1.35)));
	float yarn = coh_hash12(cell);
	float pile = mix(mix(0.7, 1.1, crown) * mix(0.9, 1.08, yarn), 0.97, flatten);
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
	float grout = 0.0;
	vec2 bevel_n = vec2(0.0);
	if (pattern_mode == 1) {
		vec2 cell = floor(puv / pattern_scale);
		float tint = (coh_hash12(cell) - 0.5) * 0.05;
		grout = seam_mask(puv, pattern_scale, pattern_detail);
		base = mix(a * (1.0 + tint), b, grout);
		if (tile_bevel > 0.0) {
			// Distance to the tile's edge along each axis (m); the bevel rolls the normal toward
			// the grout over tile_bevel, faded out when a tile is under ~6 px.
			vec2 f = (fract(puv / pattern_scale) - 0.5) * pattern_scale;
			vec2 edge = 0.5 * (pattern_scale - pattern_detail) - abs(f);
			vec2 roll = (1.0 - smoothstep(0.0, tile_bevel, edge)) * sign(f) * step(0.0, edge);
			float tiles_px = pattern_scale / max(max(fwidth(puv.x), fwidth(puv.y)), 1e-5);
			bevel_n = roll * 0.35 * smoothstep(6.0, 14.0, tiles_px);
		}
	} else if (pattern_mode == 2) {
		// Vertical stripes: secondary of width pattern_detail every pattern_scale metres.
		float x = fract(puv.x / pattern_scale) * pattern_scale;
		float fw = max(fwidth(puv.x), 1e-5);
		float s = smoothstep(-fw, fw, x) * (1.0 - smoothstep(pattern_detail - fw, pattern_detail + fw, x));
		float contrast = pattern_contrast;
		if (contrast_fade.y > contrast_fade.x) {
			contrast = mix(pattern_contrast, 1.0, smoothstep(contrast_fade.x, contrast_fade.y, distance(v_world_pos, CAMERA_POSITION_WORLD)));
		}
		vec3 b2 = max(a + (b - a) * contrast, vec3(0.0));
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
		// Wear lanes (02 §7 Halls): the corridor's walked middle is flattened and paler.
		float lane = wear * COLOR.a * smoothstep(wear_from, 0.9, COLOR.b);
		base = mix(b, a, 0.5) * mix(0.78, 1.18, k) * carpet_pile(puv, lane) * (1.0 + 0.6 * lane);
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
	base *= 1.0 + (COLOR.r * 2.0 - 1.0) * cell_tint;

	// ---- seams (02 §7 Halls): baseboard and ceiling shadow line on walls, floor seam ----
	float rough = roughness;
	bool vertical = an.y < 0.5;
	if (vertical && baseboard_height > 0.0) {
		float fw = max(fwidth(v_world_pos.y), 1e-5);
		float band = 1.0 - smoothstep(baseboard_height - fw, baseboard_height + fw, v_world_pos.y);
		// A 1 cm lip catches light at the top edge of the board.
		float lip = aa_band(v_world_pos.y - baseboard_height + 0.006, 0.004);
		base *= mix(1.0, 1.0 - baseboard_darken, band) * (1.0 + 0.25 * lip);
		rough = mix(rough, baseboard_roughness, band);
	}
	if (vertical && ceiling_line_y > 0.0) {
		float d = ceiling_line_y - v_world_pos.y;
		base *= 1.0 - ceiling_line_darken * (1.0 - smoothstep(0.0, ceiling_line_width, d));
	}
	if (vertical && band_width > 0.0) {
		float yy = band_period > 0.0 ? mod(v_world_pos.y, band_period) : v_world_pos.y;
		float band = aa_band(yy - band_y, band_width * 0.5);
		base = mix(base, band_color.rgb * mix(0.92, 1.04, nz), band);
	}
	if (!vertical && n.y > 0.5 && floor_seam > 0.0) {
		base *= 1.0 - floor_seam * (1.0 - smoothstep(0.0, floor_seam_width, COLOR.b));
	}
	if (grout_roughness >= 0.0) {
		rough = mix(rough, grout_roughness, grout);
	}
	float wetness = wet;
	if (puddles > 0.0 && n.y > 0.5) {
		float pn = texture(noise_albedo, puv / puddle_scale * 0.25 + 0.13).r;
		// The noise texture sits around 0.5 (p50 0.49, p98 0.8), so the threshold for a share
		// `puddles` of the floor runs from 0.8 (none) down to the median (half), soft-edged.
		float th = mix(0.8, 0.49, clamp(puddles * 2.0, 0.0, 1.0));
		wetness = max(wetness, smoothstep(th - 0.05, th + 0.05, pn));
	}
	if (wetness > 0.0) {
		// Water fills the grout first: a wet floor is smooth over the grid too.
		base *= 1.0 - wet_darken * wetness;
		rough = mix(rough, wet_roughness, wetness);
		bevel_n *= 1.0 - wetness;
	}

	// 02 §5 soft walls: a faint moving interference band, 0.5 Hz, amplitude 0.08 (R11: 0.03
	// did not read). Bands about 1 m apart drift up the wall at the band rate, their strength
	// beating slowly along it, so the wall shimmers rather than breathing as one tone.
	float soft_u = 0.0;
	float soft_band = 0.0;
	if (soft > 0.5) {
		float ph = TAU * SOFT_BAND_HZ * g_time;
		float beat = 0.6 + 0.4 * sin(ph * 0.5 - puv.x * 3.1 + v_world_pos.y * 0.7);
		soft_band = SOFT_BAND_AMPLITUDE * sin(ph - v_world_pos.y * SOFT_BAND_K) * beat;
		base += soft_band;
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
	u_other = max(u_other, unfinished_u * step(0.5, COLOR.g));
	u_other = max(u_other, coh_null_u(v_world_pos));
	u_other = max(u_other, coh_commit_u(v_world_pos, cam));
	u_other = max(u_other, soft_u);
	// 02 §9: the charge preview, a disc anchored at the noclip target.
	float u_prev = coh_preview_u(v_world_pos);
	float u = max(u_other, u_prev) * (1.0 - held);

	// ---- normal (noise, triplanar dominant plane) ----
	if (normal_strength > 0.0 || tile_bevel > 0.0) {
		vec2 nm = texture(noise_normal, puv * triplanar_scale).xy * 2.0 - 1.0;
		vec2 tilt = (nm * normal_strength + bevel_n) * (1.0 - u);
		vec3 nw = normalize(n + ta * tilt.x + tb * tilt.y);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}

	// ---- compose ----
	vec3 emit = emission.rgb * emission_strength;
	float line = 0.0;
	if (u > 0.0) {
		// M3.2 (11 §2 "world lines within 3 m"): during the commit the lines near the player
		// are wider and brighter so the pass reads through TAA and the commit pulse.
		float commit_k = coh_commit_u(v_world_pos, cam);
		vec2 lines = grid_masks(puv / GRID_SPACING, 1.0 + (COMMIT_LINE_PX - 1.0) * commit_k);
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
		ROUGHNESS = rough;
		METALLIC = metallic;
		SPECULAR = 0.5 * (1.0 - u);
	}
	float line_boost = 1.0;
	if (u > 0.0) {
		line_boost += (COMMIT_LINE_GAIN - 1.0) * coh_commit_u(v_world_pos, cam);
	}
	EMISSION = emit * (1.0 - line) + GRID_COLOR * line * line_emission * line_boost;
	// M2.3: where a soft wall's fill is unrendered (the Substrate's u floor) its albedo band is
	// gone with the fill, so the band glows instead, scaled by the material u floor.
	EMISSION += vec3(soft_band + SOFT_BAND_AMPLITUDE) * 0.5 * u_floor * (1.0 - line) * step(0.5, soft);

	// Screen door (02 §5): at u >= 0.95 a fraction 0.6 u of fill cells is discarded, on a
	// world-anchored lattice so the pattern sticks to the surface; lines always stay.
	ALPHA = (line < 0.5 && coh_screen_door(v_world_pos, u)) ? 0.0 : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
