// Pools water (02 §7): a planar, translucent surface #2E8B8B at alpha 0.75, two scrolling
// normal layers from the stratum's NoiseTexture2D, specular highlights from the fixtures,
// a 0.03 screen-space refraction of what lies below, no foam. M2.13a polish:
// - drip rings: a few hashed expanding ripples (the Pools drips, 02 §10) on top of the layers;
// - Fresnel: grazing views reflect the stratum's air (fog colour, the "sky", 02 §6) and turn
//   opaque, steep views look through;
// - depth tint: opacity grows with the water's thickness along the view (Beer-Lambert) up to
//   the 0.75 of the look sheet, and the colour deepens with the depth under the surface, so
//   shallow steps read clear and a full 1.8 m basin reads deep;
// - caustics: the submerged floor and walls (reconstructed from the depth buffer behind the
//   surface) carry a moving web of caustic lines (shader math: drifting, warped Voronoi borders),
//   projected from above and scaled by how lit that surface already is.
// A small prop shader (02 §5): it includes the Coherence globals, takes the vertex jitter and
// unrenders (black with the 0.5 m world grid, fading out) where Null or the noclip commit
// unrender the world. Its grade (desaturation, grain, CA) is the screen pass, which runs over
// the finished image, transparent surfaces included.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, specular_schlick_ggx;

#include "res://shaders/include/coherence.gdshaderinc"

uniform vec4 water_color : source_color = vec4(0.180392, 0.545098, 0.545098, 0.75);
// The colour deep water tends to (with the depth under the surface).
uniform vec4 deep_color : source_color = vec4(0.07451, 0.270588, 0.278431, 1.0);
uniform sampler2D normal_noise : hint_normal, filter_linear_mipmap, repeat_enable;
// Repeats of the normal map per metre for the two layers, and their drift (repeats/s).
uniform float scale_a = 0.09;
uniform float scale_b = 0.23;
uniform vec2 drift_a = vec2(0.011, 0.006);
uniform vec2 drift_b = vec2(-0.007, 0.009);
uniform float normal_strength = 0.35;
// Drip rings: one possible drip per cell of this many metres, its slope and period range (s).
uniform float drip_cell = 4.0;
uniform float drip_strength = 0.35;
uniform vec2 drip_period = vec2(2.5, 6.0);
// Screen-space refraction (02 §7: 0.03).
uniform float refraction = 0.03;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;
// Fresnel: the reflected air colour (the stratum's fog) and its energy.
uniform vec4 reflect_color : source_color = vec4(0.372549, 0.658824, 0.639216, 1.0);
uniform float reflect_energy = 0.35;
// Depth tint: metres of water (along the view) for the tint to reach 63% of the opacity, and
// metres under the surface for the colour to reach 63% of deep_color.
uniform float tint_depth = 0.6;
uniform float deep_depth = 1.2;
// Caustics: web cells per metre, line width (cell units), drift speed, strength on the lit
// floor, and the depth (m) over which they fade.
uniform float caustic_scale = 2.0;
uniform float caustic_width = 0.12;
uniform float caustic_speed = 1.0;
uniform float caustic_strength = 1.6;
uniform float caustic_fade_depth = 2.5;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

// Constants mirrored from Tuning (a test parses every `const` line against tuning.gd).
const float GRID_SPACING = 0.5;          // WORLD_GRID_SPACING
const vec3 GRID_COLOR = vec3(0.7913, 0.7913, 0.7913); // WORLD_GRID_LINE_COLOR in linear
const float MAX_ALPHA = 0.75;            // POOLS_WATER_ALPHA
const float FRESNEL_F0 = 0.02;           // shader-local: water's reflectance at normal incidence

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += coh_jitter(v_world_pos, 0.0, 0.0);
}

// The slope of the drip rings at p (world xz): one hashed drip per cell, its ring growing
// out to 1.4 m over its period and fading. The drip point stays 1.5 m inside its cell so a
// ring never crosses into the next one.
vec2 drip_slope(vec2 p) {
	vec2 cell = floor(p / drip_cell);
	vec2 h = vec2(coh_hash12(cell + 0.17), coh_hash12(cell + 7.31));
	vec2 centre = (cell + 0.5) * drip_cell + (h - 0.5) * (drip_cell - 3.0);
	float period = mix(drip_period.x, drip_period.y, coh_hash12(cell + 3.7));
	float ph = fract(g_time / period + h.x);
	float r = ph * 1.4;
	vec2 d = p - centre;
	float dist = length(d);
	float x = dist - r;
	float env = (1.0 - smoothstep(0.0, 0.25, abs(x))) * (1.0 - ph);
	return normalize(d + 1e-5) * cos(x * 26.0) * env * drip_strength;
}

// Distance between the nearest and second-nearest of a cell grid's drifting points: 0 on
// the cells' borders (a Voronoi edge), where the caustic lines are.
float voronoi_edge(vec2 p, float t) {
	vec2 g = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 h = vec2(coh_hash12(g + o), coh_hash12(g + o + 17.3));
			vec2 pt = o + 0.5 + 0.4 * sin(vec2(t, t * 0.8) + TAU * h);
			float d = length(pt - f);
			d2 = d < d1 ? d1 : min(d2, d);
			d1 = min(d1, d);
		}
	}
	return d2 - d1;
}

// A caustic web at p (cells), 0..1: two warped layers of drifting Voronoi borders.
float caustic_web(vec2 p, float t) {
	vec2 w = p + 0.18 * sin(vec2(p.y * 2.1 + t * 0.7, p.x * 1.9 - t * 0.6));
	float l1 = 1.0 - sqrt(clamp(voronoi_edge(w, t) / caustic_width, 0.0, 1.0));
	float l2 = 1.0 - sqrt(clamp(voronoi_edge(w * 1.6 + vec2(3.1, 7.7), t * 1.3) / (caustic_width * 1.3), 0.0, 1.0));
	return clamp(l1 * 0.7 + l2 * 0.5, 0.0, 1.0);
}

// View-space position of the opaque surface behind this pixel at `uv` (reversed-Z depth).
vec3 view_pos_at(vec2 uv, mat4 inv_proj) {
	float depth = textureLod(depth_tex, uv, 0.0).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	vec2 na = texture(normal_noise, p * scale_a + drift_a * g_time).xy * 2.0 - 1.0;
	vec2 nb = texture(normal_noise, p * scale_b + drift_b * g_time).xy * 2.0 - 1.0;
	vec2 slope = (na + nb) * 0.5 * normal_strength + drip_slope(p);
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	if (!FRONT_FACING) {
		nw = -nw;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// What lies below, bent by the ripples. A bent read that lands on something in front of
	// the water (a ladder, the rim) falls back to the straight read so nothing above leaks in.
	vec2 uv = clamp(SCREEN_UV + slope * refraction, vec2(0.001), vec2(0.999));
	vec3 behind = view_pos_at(uv, INV_PROJECTION_MATRIX);
	if (behind.z > VERTEX.z) {
		uv = SCREEN_UV;
		behind = view_pos_at(uv, INV_PROJECTION_MATRIX);
	}
	vec3 below = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 behind_world = (INV_VIEW_MATRIX * vec4(behind, 1.0)).xyz;
	float thickness = max(distance(behind, VERTEX), 0.0);
	float under = max(v_world_pos.y - behind_world.y, 0.0);

	// Caustics on the submerged surfaces, projected from above (walls get the slanted
	// projection), anti-aliased away once a line is under a pixel, fading with depth.
	vec2 cp = (behind_world.xz + vec2(behind_world.y * 0.45, -behind_world.y * 0.3)) * caustic_scale;
	// Faded out once a web cell is under a few pixels (no shimmer under TAA).
	float cells_px = 1.0 / max(max(fwidth(cp.x), fwidth(cp.y)), 1e-5);
	float caustic = caustic_web(cp, g_time * caustic_speed) * caustic_strength * smoothstep(1.5, 4.0, cells_px)
			* step(0.02, under) * (1.0 - smoothstep(0.0, caustic_fade_depth, under));
	below *= 1.0 + caustic;

	// Depth tint and Fresnel.
	float a = min(water_color.a, MAX_ALPHA) * (1.0 - exp(-thickness / tint_depth));
	vec3 tint = mix(water_color.rgb, deep_color.rgb, 1.0 - exp(-under / deep_depth));
	vec3 view_dir = normalize(-VERTEX);
	float fres = FRESNEL_F0 + (1.0 - FRESNEL_F0) * pow(1.0 - clamp(abs(dot(NORMAL, view_dir)), 0.0, 1.0), 5.0);
	a = mix(a, 1.0, fres);

	// Unrender (02 §5): to black with the world grid where Null or the commit take the world.
	float u = max(coh_null_u(v_world_pos), coh_commit_u(v_world_pos, CAMERA_POSITION_WORLD));
	vec2 g = p / GRID_SPACING;
	vec2 fw = max(fwidth(g), vec2(1e-5));
	vec2 gd = abs(fract(g - 0.5) - 0.5) / fw;
	float line = max(1.0 - clamp(gd.x, 0.0, 1.0), 1.0 - clamp(gd.y, 0.0, 1.0)) * smoothstep(0.0, 0.25, u);

	ALBEDO = tint * a * (1.0 - u) * (1.0 - line);
	EMISSION = (below * (1.0 - a) + reflect_color.rgb * reflect_energy * fres) * (1.0 - u) * (1.0 - line)
			+ GRID_COLOR * line;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.6 * (1.0 - u);
	ALPHA = max(1.0 - 0.6 * u, line);
}
