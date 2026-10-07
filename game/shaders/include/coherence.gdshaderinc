// Shared Coherence helpers (02 §5, §8): the global parameters, hashes, vertex jitter and
// the unrender terms. Included by world_surface.gdshader and by every small prop shader
// (water, monitor, rack LEDs, Static's field) so global effects reach every surface the
// same way. The grade (desaturation, warmth, vignette, grain, CA) is not here: it runs
// once over the whole image in coherence_screen.gdshader, transparent surfaces included.

// 14 §11: written every frame by CoherenceRenderer.
global uniform float g_coherence;
global uniform float g_noclip_charge;
global uniform float g_noclip_commit;
global uniform vec3 g_noclip_target;
global uniform vec3 g_noclip_target_normal;
global uniform float g_noclip_invalid;
global uniform vec3 g_null_pos;
global uniform float g_null_radius;
global uniform float g_time;

// Constants mirrored from Tuning (a test parses every `const` line against tuning.gd).
const float COH_JITTER_MAX = 0.012;          // WORLD_JITTER_MAX
const float COH_JITTER_SMOOTH_MIN = 0.5;     // WORLD_JITTER_SMOOTH_MIN
const float COH_JITTER_SMOOTH_MAX = 1.0;     // WORLD_JITTER_SMOOTH_MAX
const float COH_JITTER_NOCLIP = 0.04;        // WORLD_JITTER_NOCLIP
const float COH_JITTER_HZ = 20.0;            // WORLD_JITTER_HZ
const float COH_UNRENDER_INNER = 0.6;        // WORLD_UNRENDER_INNER
const float COH_NOCLIP_RADIUS = 3.0;         // NOCLIP_UNRENDER_RADIUS_COMMIT
const float COH_NOCLIP_PREVIEW_U = 0.9;      // WORLD_NOCLIP_PREVIEW_U
const float COH_NOCLIP_PREVIEW_DEPTH = 0.3;  // WORLD_NOCLIP_PREVIEW_DEPTH
const float COH_UNRENDER_FULL = 0.95;        // WORLD_UNRENDER_FULL
const float COH_SCREEN_DOOR_MAX = 0.6;       // WORLD_SCREEN_DOOR_MAX
const float COH_SCREEN_DOOR_CELL = 0.01;     // WORLD_SCREEN_DOOR_CELL

float coh_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float coh_hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 coh_hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// 1 - coherence: the input of every curve.
float coh_drain() {
	return clamp(1.0 - g_coherence, 0.0, 1.0);
}

// 02 §5 vertex jitter amplitude in metres: 0.012 smoothstep(0.5, 1, drain) + 0.04 commit,
// never below `jitter_floor` (Cycle 2), zero for held objects.
float coh_jitter_amount(float jitter_floor, float held) {
	float j = max(jitter_floor, COH_JITTER_MAX * smoothstep(COH_JITTER_SMOOTH_MIN, COH_JITTER_SMOOTH_MAX, coh_drain()));
	return (j + COH_JITTER_NOCLIP * g_noclip_commit) * (1.0 - held);
}

// The jitter offset for a vertex at world position `wp`. Hashing the world position keeps
// coincident vertices of neighbouring meshes together (no cracks); stepped at 20 Hz so the
// tremble reads as a glitch rather than a blur under TAA.
vec3 coh_jitter(vec3 wp, float jitter_floor, float held) {
	float j = coh_jitter_amount(jitter_floor, held);
	if (j <= 0.0) {
		return vec3(0.0);
	}
	float step_t = floor(g_time * COH_JITTER_HZ);
	return (coh_hash33(floor(wp * 100.0) + step_t * 7.31) * 2.0 - 1.0) * j;
}

// 1 at or inside `inner`, 0 at or beyond `outer` (inner < outer). Spelled out because
// smoothstep with edge0 > edge1 is undefined in GLSL.
float coh_falloff(float inner, float outer, float d) {
	return 1.0 - smoothstep(inner, outer, d);
}

// 02 §5: u from Null, 1 inside 0.6 r, 0 beyond r.
float coh_null_u(vec3 wp) {
	if (g_null_radius <= 0.0) {
		return 0.0;
	}
	return coh_falloff(g_null_radius * COH_UNRENDER_INNER, g_null_radius, distance(wp, g_null_pos));
}

// 02 §5: during the commit, geometry within 3 m of the player goes to lines.
float coh_commit_u(vec3 wp, vec3 cam) {
	return g_noclip_commit * coh_falloff(COH_NOCLIP_RADIUS * 0.8, COH_NOCLIP_RADIUS, distance(wp, cam));
}

// 02 §9: the charge preview, a disc on the target surface growing with the charge (radius
// 3 m at full charge), peaking at u 0.9 so a cancelled charge never shows what is behind.
// Only surfaces within 0.3 m of the target plane take part, so a wall target does not
// unrender the floor in front of it. With no target normal it falls back to a sphere.
float coh_preview_u(vec3 wp) {
	if (g_noclip_charge <= 0.001) {
		return 0.0;
	}
	vec3 off = wp - g_noclip_target;
	float nl = length(g_noclip_target_normal);
	float across = length(off);
	float depth = 0.0;
	if (nl > 0.5) {
		vec3 nn = g_noclip_target_normal / nl;
		depth = abs(dot(off, nn));
		across = length(off - nn * dot(off, nn));
	}
	float r = COH_NOCLIP_RADIUS * g_noclip_charge;
	return COH_NOCLIP_PREVIEW_U * g_noclip_charge * coh_falloff(r * COH_UNRENDER_INNER, r, across)
			* coh_falloff(COH_NOCLIP_PREVIEW_DEPTH * 0.5, COH_NOCLIP_PREVIEW_DEPTH, depth);
}

// 02 §5 screen door, world-anchored: at u >= 0.95, a fraction 0.6 u of fill cells is
// discarded. Cells sit on a world lattice of 1 cm halved or doubled by octaves until one
// cell is at most one pixel, so the pattern sticks to the surface (no swimming when the
// camera moves) and the holes stay 1 px, which the Null halo's dilation closes and TAA
// resolves. Fragment stage only. Returns true when this fragment's cell is discarded.
bool coh_screen_door(vec3 wp, float u) {
	if (u < COH_UNRENDER_FULL) {
		return false;
	}
	vec3 fw = fwidth(wp);
	float footprint = max(max(fw.x, fw.y), max(fw.z, 1e-5));
	float cell = COH_SCREEN_DOOR_CELL * exp2(floor(log2(footprint / COH_SCREEN_DOOR_CELL)));
	return coh_hash13(floor(wp / cell) + 0.5) < COH_SCREEN_DOOR_MAX * u;
}
