# 02 — Visual Direction

**Depends on:** `00_OVERVIEW.md`, `01_fiction_and_tone.md`
**Skills to read before implementing:** `godot-3d-materials`, `godot-3d-lighting`, `godot-shaders-basics`, `godot-particles`, `godot-performance-optimization`
**Pulls engagement levers:** push-your-luck dial (Coherence renderer), readable rules (each error has a distinct visual signature), mundane-made-wrong (pillar 5).

---

## 1. The visual thesis

NOCLIP looks like a photograph of an empty building that is slowly becoming a diagram of itself. Two forces define every frame:

1. **Mundane realism from flat means.** Ordinary spaces, ordinary materials, believable light. Achieved with procedural textures, careful fixture spacing, fog, ambient occlusion, and restraint. No clutter. No decals of grime. Clean, repeated, slightly too regular.
2. **The Coherence renderer.** The image quality is tied to the player's Coherence. At 100 the world is warm, saturated, and solid. As Coherence falls, colour drains, grain rises, edges split into chromatic fringes, and geometry vertices tremble. At the moment of a noclip, and near Null, the world goes to lines.

Everything else is a consequence of these two.

## 2. Visual targets (what "done" looks like)

Agents cannot look at a reference image, so these targets are written as checkable statements. The screenshot tour (`14_technical_architecture.md` §9) produces the frames these statements are checked against.

- **T1 Readability of the floor.** In every stratum at the Medium preset, the floor within 12 m of the camera is visible (luminance above 8% of white) with the flashlight off, except the Server and Substrate strata where the limit is 6 m. Darkness hides threats, not navigation (horror skill rule).
- **T2 Fixture rhythm.** Light fixtures repeat on an exact grid per stratum. Nothing is placed "naturally". Regularity is the wrongness.
- **T3 No flat black, no flat white.** The darkest shadow has visible fog in it; the brightest fixture blooms but never clips to a white rectangle larger than the fixture itself.
- **T4 Coherence is visible without the HUD.** Side-by-side frames at Coherence 100, 60, 30, and 10 must be orderable by anyone with the HUD hidden.
- **T5 Each stratum is identifiable from any single frame** by palette and fixture type alone.
- **T6 Each error is identifiable from a silhouette or signature** at 15 m with the flashlight off.
- **T7 Still frames look like photographs; motion looks like video.** Camera motion is smooth, head bob subtle, no motion blur, no lens flares.
- **T8 Nothing is textured by an imported image.** All surface detail comes from `NoiseTexture2D`, shader math, or vertex colour. (Exception: hand-written SVG for UI glyphs.)

## 3. Renderer and global settings

| Setting | Value | Reason |
|---|---|---|
| Renderer | Forward+ (Vulkan) | Clustered lights, volumetric fog, SSAO, SSIL |
| Tonemapper | AgX | Preserves saturation under fixture bloom; graceful highlight roll-off |
| Exposure | 1.0 base, per-stratum offsets in `StratumData` | |
| Anti-aliasing | TAA default; FXAA and MSAA 2x/4x selectable | TAA hides procedural texture shimmer |
| Render scale | 1.0 default; FSR 2 upscaling available (`12_settings`) | |
| Global illumination | None in v1.0 (no SDFGI, no VoxelGI). Ambient comes from the Environment ambient colour per stratum plus emissive fixtures plus SSIL at High. | Deterministic, cheap, no leaking in thin procedural walls |
| Ambient occlusion | SSAO on at Medium and above, radius 1.0, intensity 2.0 | Contact shadows under desks, racks, cars |
| Screen-space indirect lighting | SSIL on at High only | |
| Volumetric fog | On at Medium and above; density per stratum; off at Low replaced by distance fog | The air must be visible |
| Shadows | Flashlight spot casts shadows always. Up to 4 nearest shadowed omni lights at High, 2 at Medium, 0 at Low. All other fixtures unshadowed. | Shadow atlas budget (lighting skill) |
| Motion blur, lens flare, DOF | Never | T7 |
| Glow | On, HDR threshold 1.0, intensity 0.6, bloom 0.1, blend mode Soft Light | Fixtures bloom softly, nothing else |

## 4. The Coherence renderer (post-processing stack)

Two passes, both driven every frame by `CoherenceRenderer` (an autoload, see `14`) through global shader parameters and uniforms computed by `CoherencePost` (`game/src/core/coherence_post.gd`):

- **Screen pass** (`coherence_screen.gdshader`): a `ColorRect` on a `CanvasLayer` at layer −10 (under the HUD at 0 and up; hide masks sit at −20). It runs after TAA over the finished image, so per-frame grain and tearing are not averaged away, and it grades everything the camera drew, transparent surfaces included. It does steps 1 to 5 and every pulse. Every shifted read (tearing, CA, ripple) is clamped inside the image.
- **Scene pass** (`coherence_post.gdshader`): a full-screen `QuadMesh` (size 2 × 2) that follows the camera, a **spatial** shader with `render_mode unshaded, depth_test_disabled, cull_disabled, fog_disabled` whose vertex function writes clip-space `POSITION` directly (reversed-Z: z = 1 is the near plane). Only a spatial shader can read `hint_depth_texture`, so this pass does only step 6, and it is visible only while `g_null_radius > 0`.

In order:

1. **Chromatic aberration.** Radial RGB split. Amount `ca = lerp(0.0, 0.012, drain)` where `drain = 1 - coherence/100` eased with `smoothstep(0.1, 1.0, drain)`. Plus a transient `ca_pulse` from events (hit, noclip).
2. **Desaturation.** `sat = lerp(1.0, 0.08, smoothstep(0.3, 1.0, drain))`. Below 30 Coherence the world is nearly monochrome. Above 70 it is untouched.
3. **Film grain.** Animated hash noise at 24 fps, luminance-only. `grain = lerp(0.02, 0.18, drain)`. Grain is always present at a minimum so the image never looks "clean digital".
4. **Vignette.** `vig = lerp(0.15, 0.45, drain)` plus `threat_vig` from the Director's proximity signal (`10`), max 0.3 additional, pulsing with the heartbeat: `CoherenceRenderer` accumulates the heartbeat phase each frame (`phase += delta × bpm / 60`, bpm 60 to 140 by threat, never below 90 under 25 Coherence) and exposes `heartbeat_phase()` so the heartbeat sample can lock to it.
5. **Scanline shimmer.** Very faint horizontal 1 px line tearing, amplitude tied to `drain^2` and to `noclip_charge`. At Coherence 100 it is invisible.
6. **Edge halo near Null.** A screen-space outline from the depth buffer (a signed Laplacian of the 3 × 3-dilated device depth, from 21 taps fetched once), blended in by the camera's proximity to Null. Lines are 1 px, colour `#E6E6E6`. Inside the 2 m core the pass paints black with the halo.

**Transient pulses** (`CoherenceRenderer.pulse(kind)`; durations in `11_feedback_contract.md`): `hit` (CA 0.03 and inverted-luminance flash for 2 frames, decays 400 ms), `noclip_commit` (CA 0.004 so the world lines lead, scanline 1.0, grain spike; held through the 80 ms hitstop and the 250 ms pass, then decays 300 ms), `coherence_gain` (brief saturation overshoot 1.15 for 600 ms, warmth +0.05), `dissolve` (progressive: grain to 1.0, saturation to 0, 1.5 s), `flash` (the Polaroid's white flash only), `ripple` (Landing: one ring crossing the screen in 600 ms), `drop` (fired at the floor commit: to black with grain over 1.2 s, held; fired again on the drop arrival: black to the world over 400 ms). **Static** (`set_static(amount)`, 0..1 by the field's falloff) raises grain toward 0.6 and CA toward 0.02 (§8).

**Accessibility:** `reduce_visual_noise` (`12`) caps grain at 0.06, CA at 0.004, and disables scanline shimmer. Desaturation and vignette are preserved because they carry gameplay information. `reduce_flashing` replaces 2-frame flashes and the hit inversion with a 200 ms fade to 60% white.

## 5. The world shader (one ubershader for all level geometry)

All generated level geometry and props use a single `ShaderMaterial` (`world_surface.gdshader`) with per-material uniforms and per-vertex colour, so that global effects reach every surface uniformly. Variation comes from uniform values and the stratum's `NoiseTexture2D` set, not from different shaders.

**Per-material uniforms:** `albedo`, `albedo_secondary` (for tiles, stripes, checker), `pattern_mode` (0 flat, 1 tiles, 2 stripes, 3 carpet, 4 concrete, 5 checker, 6 panel), `pattern_scale`, `roughness`, `metallic`, `emission`, `emission_strength`, `noise_albedo` (sampler, triplanar), `noise_normal` (sampler, triplanar), `normal_strength`, `triplanar_scale`.

**Global uniforms (set by `CoherenceRenderer` and `NullPresence`):** `g_coherence` (0..1), `g_noclip_charge` (0..1), `g_noclip_commit` (0..1 decaying), `g_noclip_target` and `g_noclip_target_normal` (vec3, the aimed surface point and its normal), `g_noclip_invalid` (0 or 1), `g_null_pos` (vec3), `g_null_radius` (float, 0 when absent), `g_time`. They, the hashes, the jitter function and the unrender terms live in `shaders/include/coherence.gdshaderinc`, which every shader that touches level space includes (world, water, monitor, rack LEDs, Static's field).

**Behaviours:**
- **Vertex jitter.** `VERTEX += hash(VERTEX + g_time) * jitter`, `jitter = 0.012 * smoothstep(0.5, 1.0, 1 - g_coherence) + 0.04 * g_noclip_commit`. At full Coherence the world is rock solid. Jitter is applied in object space before projection. Held objects (flashlight, items) use the same shader with the per-material uniform `held = 1.0`, which zeroes jitter and the unrender term so the player's hands never dissolve; UI is not a spatial material.
- **Unrender.** `u = 1 − smoothstep(0.6 × g_null_radius, g_null_radius, distance(world_pos, g_null_pos))` combined with `g_noclip_commit` for the geometry within 3 m of the player during a noclip (descending ramps are always written `1 − smoothstep(lo, hi, x)`; GLSL leaves reversed edges undefined). Where `u > 0`, albedo blends to black, emission to 0, and a **world-space grid line** is drawn: lines every 0.5 m on each axis using `fwidth`-based anti-aliased edges, colour `#E6E6E6`, 1 px, triplanar. At `u >= 0.95` the surface is fully lines on black and **screen-door transparent**: the shader sets `ALPHA_SCISSOR_THRESHOLD = 0.5` and `ALPHA = hash(cell) < 0.6 × u ? 0 : 1`, where `cell = floor(world_pos / s)` on a world lattice `s = 1 cm × 2^k` with the octave `k` chosen so one cell is at most one pixel. Unrendered fills are dithered away (60% of cells at full unrender), the pattern sticks to the surface, and grid lines keep `ALPHA = 1.0`. The material therefore stays in the **opaque pipeline** everywhere (depth writes on, SSAO/SSIL/volumetric fog correct, `Decal` chalk marks project normally, no sorting). Never write a non-scissor `ALPHA` from the world shader; there is no alpha-blend variant of level geometry.
- **Soft walls** (`09`): a uniform `soft = 1.0` on the thin wall segments the generator marks passable. The shader adds a faint moving interference band (0.5 Hz, amplitude 0.08 in albedo, bands about 1 m apart drifting up the wall) and, when the player's crosshair is within 2 m and aimed at it, a stronger 1 px grid preview at `u = 0.3`. Players learn to read soft walls by that shimmer. No HUD marker.
- **Placeholder checker** (`pattern_mode 5`): magenta `#FF00FF` and black 1 m checker, unlit, used only in the Substrate on surfaces the generator marks "unfinished". It ignores the Substrate's `u_floor` (it must read magenta); Null still unrenders it.

Props that must react differently (monitors, LEDs, water, the fixtures' ceiling glow) get their own small shaders listed in §8, all of which still read `g_coherence` for jitter and desaturation consistency.
- **Noclip commit lines** (M3.2): within the 3 m commit radius the grid lines are 2.5 px wide and 3× as bright (`WORLD_COMMIT_LINE_PX`, `WORLD_COMMIT_LINE_GAIN`), and geometry there does not take the commit jitter, so "world lines within 3 m" (11 §2) reads through TAA and the commit pulse.

## 6. Lighting rules

- **Fixtures are the light.** Every stratum has one fixture prefab: an emissive quad or tube (unlit emission in the world shader, `emission_strength` 4 to 12) with an `OmniLight3D` or `SpotLight3D` child. Fixtures are placed on the stratum's exact grid (T2).
- **Light pooling.** Only the 24 fixtures nearest the player have their light node enabled (Medium: 16, Low: 10). "Nearest" is walking distance on the grid, and only fixtures the player can see on the grid (or will see within one step) get a light: pooled lights are unshadowed, so a light lent to a fixture behind a wall would leak through it. The `LightPool` system (`14`) re-evaluates every 0.25 s. Disabled fixtures still glow (emission) so the room reads as lit. `distance_fade` on each light hides the swap.
- **Shadowed lights.** Flashlight always. Nearest 4 fixtures at High, 2 at Medium, 0 at Low. Shadow bias tuned per stratum once and stored in `StratumData`.
- **Flashlight.** `SpotLight3D`, `spot_angle` 19° (a 38° full cone), range 22 m, energy 1.6 at full crank falling to 0.5 at empty, colour `#FFF4E0`, soft 1 px cookie-less edge via `spot_angle_attenuation 1.2`. A subtle secondary `OmniLight3D` (range 1.5 m, energy 0.15) at the player's hand so the near floor is never black with the beam on.
- **Ambient.** Environment ambient light per stratum, low (energy 0.08 to 0.2). Sky colour is the fog colour. No sky texture; cameras never see a sky.
- **Fog.** Volumetric fog density per stratum (Halls 0.02, Pools 0.035, Garage 0.015, Offices 0.02, Server 0.03, Substrate 0.0 with distance fog to black at 40 m). Fog albedo is the stratum's fog colour. Fog is how the air is seen; its colour is the stratum's identity at a distance.
- **Flicker behaviour** is a lighting *rule*, not decoration: fixtures only flicker when Flicker is present in that fixture group (`08`). Elsewhere, fixtures are steady. Players must be able to trust that flicker means something.
- **Breaker events** (`09`): when a floor is powered on, fixtures light in a wave that propagates from the breaker room at 12 m/s with a 40 ms stagger per fixture and an energy overshoot to 1.3 then settle over 400 ms.

## 7. Stratum look sheets

Hex values are the canonical palette. Agents set these in `StratumData` resources; the shader derives everything else.

### Halls
- **Walls:** wallpaper `#C9A227`, secondary `#B8921F` in 0.6 m vertical stripes (pattern 2, the secondary pushed ×1.6 from the primary, easing back to the palette pair between 3 m and 10 m so far walls read as one tone with the print), printed: small diamonds on a 0.15 m half-drop lattice and pinstripes at the stripe edges (`print_amount` 0.14), roughness 0.85, noise normal strength 0.25, ±4% tint per cell. A baseboard band below 0.1 m (45% darker, roughness 0.45, a lit 1 cm lip) and a 5 cm shadow line under the ceiling (35%).
- **Floor:** carpet `#8B7A3A` (pattern 3: carpet noise, scale 4, and a loop pile of 90 loops per metre that fades to its mean below ~2.5 px per loop), roughness 1.0, ±4% tint per cell. Wear lanes along corridor centre lines (paler, flattened pile where the floor is more than 0.55 m from a wall; `wear` 0.5) and a darker seam within 0.25 m of a wall (30%), from the builder's vertex colour (07 §8).
- **Ceiling:** drop tiles `#E8E2CF` (pattern 6: 0.6 m panels, thin seams), roughness 0.9.
- **Fixture:** 1.2 m × 0.3 m recessed tube every 4 m, emission `#FFF2C4` × 8, light colour `#FFEFC2`, energy 1.4, range 7, decay 2 (inverse square), hung 0.7 m below the tube. A soft additive glow on the ceiling tile around each lit tube (`fixture_glow.gdshader`, energy 1.0). The one fixture in six that buzzes (03) has a slightly greener tube and light (× `#E6FFDB`) at 85% energy, steady.
- **Fog:** `#B49A3C`, density 0.02. **Ambient:** `#6E5A1E` 0.08. **Exposure:** 1.0.
- **Props:** none in corridors; rooms get 0 to 2 of: vending machine, payphone, chair, wall clock (`09`).

### Pools
- **Walls/floor:** tile `#9FD5CF`, secondary `#7FBBB5`, pattern 1 (0.2 m tiles, grout 0.012 m), roughness 0.25, metallic 0.0, strong specular from fixtures.
- **Water:** sunken basins (0.6 m to 1.8 m deep). Water shader: planar, translucent `#2E8B8B` alpha 0.75, two scrolling normal layers from `NoiseTexture2D`, specular highlights, screen-space refraction 0.03, foam-less. Player wading slows and emits noise (`06`).
- **Fixture:** 0.5 m square ceiling panel every 6 m, emission `#E8F6F5` × 10, light `#DDF0EE`, energy 1.2, range 10. Ceiling 6 m.
- **Fog:** `#5FA8A3`, density 0.035. **Ambient:** `#1F4A47` 0.2. **Exposure:** 1.05.
- **Props:** pool ladders (two cylinders and rungs), lifeguard chair, floating lane rope.

### Garage
- **Walls/pillars:** concrete `#7D7D78`, pattern 4 (noise albedo scale 2, normal 0.4), roughness 0.95. Horizontal painted band `#D9D0B0` at 1.2 m height on perimeter walls.
- **Floor:** concrete `#5E5E5A` with painted bay lines `#D9D0B0` (pattern 2, 2.5 m period, 0.1 m line).
- **Ceiling:** concrete `#4A4A47`, 3.2 m, exposed beam boxes every 8 m.
- **Fixture:** sodium cage lamp (cylinder) every 8 m on the pillar grid, emission `#FF9A2E` × 6, light `#FFA94D`, energy 1.4, range 12.
- **Fog:** `#4A3A22`, density 0.015. **Ambient:** `#2A221A` 0.12. **Exposure:** 0.95.
- **Props:** cars (box body `#2E2E33`, `#5A1E1E`, `#1E2E5A`, `#CFCFCF` with darker glass box, four cylinder wheels; no details), concrete barriers, exit signs (green emissive box, placed only above real exits).

### Offices
- **Walls:** `#D9D4C7` panels (pattern 6, 1.2 m), roughness 0.8. Cubicle partitions `#8A8F96` fabric (pattern 3 scale 8).
- **Floor:** carpet tile `#4F5A66`, pattern 1 (0.5 m tiles, no grout), roughness 1.0.
- **Ceiling:** drop tiles `#EEEBE2`, 3 m, 0.6 m panels.
- **Fixture:** 1.2 m × 0.6 m troffer every 4 m (every 2 cells), emission `#E6F0FF` × 9 with a 0.02 green tint, light `#DCE8F5`, energy 1.1, range 6.
- **Monitors:** 0.5 m × 0.3 m boxes on desks, screen face runs `monitor.gdshader`: dark blue `#0E1A2B` with a slow-scrolling pale text pattern (noise-thresholded rows), emission × 2. Occasionally one monitor shows the NOCLIP glyph for one frame (1 in 4,000 frames per monitor). No one will be sure they saw it.
- **Fog:** `#8E96A0`, density 0.02. **Ambient:** `#3A4048` 0.15. **Exposure:** 1.0.
- **Props:** desks (box), monitors, chairs in corridors (box seat, cylinder stem, star base), filing cabinets, water cooler (translucent blue cylinder), breaker boxes on walls.

### Server
- **Walls/floor/ceiling:** `#0A0C10`, roughness 0.6, floor tiles pattern 1 (0.6 m, grout `#141820`).
- **Racks:** 0.6 m × 2.0 m × 1.0 m boxes `#15181F` in rows; front faces run `rack_leds.gdshader`: 1 cm status LEDs in columns, each LED a hashed random of `#2EFF7A`, `#FF3B3B`, `#3B8BFF`, blinking at hashed periods (0.5 to 4 s), emission × 4. Rack LEDs are a real light source only in aggregate: one unshadowed `OmniLight3D` per 4 racks, colour `#2F5BFF`, energy 0.35, range 4.
- **Fixture:** none overhead except at aisle ends: small red `#FF3B3B` emergency boxes every 12 m, energy 0.5, range 5.
- **Fans:** ceiling grilles with a rotating 4-blade mesh (looped `AnimationPlayer`), one per 10 m.
- **Fog:** `#0D1B2A`, density 0.03. **Ambient:** `#0C1220` 0.1. **Exposure:** 1.1. The player's flashlight matters most here.

### Substrate
- **Everything** uses the world shader in permanent partial unrender: `u` floor of 0.55 everywhere, rising to 1.0 near Null. Surfaces: `#050505` base with the grid lines `#E6E6E6`. 30% of surfaces (generator-marked) use the placeholder checker.
- **No fixtures.** Light comes from the grid lines themselves (emission from the line term × 1.5) and from the flashlight. A few `OmniLight3D` "studio lights" (white, energy 0.6, range 15, no shadows) float at random positions marking the "finished" pockets.
- **Modules float.** Hall and office modules are placed with gaps and 0.4 m vertical offsets, with visible wireframe scaffolding boxes between them. Falling off is impossible (invisible walls at module edges, drawn as a brighter grid).
- **The Threshold:** a plain white front door with a brass-coloured handle, `#F2F2F2`, in a frame, standing alone on a lit pocket. Under the door, a 2 cm strip of daylight: emission `#FFF7E0` × 20 with glow. This is the only warm light in the stratum. It is visible from far away through unrendered walls (T5 for the player: hope has a colour).
- **Fog:** none. Distance fog to `#000000` from 25 m to 45 m. **Ambient:** `#101010` 0.05. **Exposure:** 1.0.

### The Landing cabin (elevator, `05` §4)
- **Surfaces:** brushed steel panels (world shader panel pattern, 0.5 m panels, dark seams, light noise), a dark rubber floor, a light-panel ceiling.
- **Light:** the ceiling panel plus a warm key light (`#FFDCA8`-ish, spot from above the door wall) so the door and the item panel are the brightest things in the cabin.
- **The door reads:** dark jambs around the opening, a black shaft behind two steel leaves with a 2 cm seam between them, a small warm lamp over the door. The item panel is rendered at 2× so its text stays crisp.

### Cycle 2 corruption (post-win, `05`)
Each stratum keeps its palette but gains: fixture hue shifted 12° towards the next stratum's light colour, 25% of fixtures dark, fog density × 1.3, vertex jitter floor 0.004, and 10% of surfaces in the world shader at `u = 0.2`. The Substrate gains Null at double radius.

## 8. Error visual signatures

Full behaviour in `08_entities.md`. Visual requirements here so that T6 holds.

- **Static:** a `MeshInstance3D` sphere (radius 3 to 5 m) with `static_field.gdshader`: screen-space refraction distortion (noise-driven, 0.04 offset), faint grey-noise fill alpha 0.08, no lighting. Inside it, the post shader's grain goes to 0.6 and CA to 0.02. It has no edge: the distortion falls off smoothly to zero. Audible before visible.
- **Still:** a capsule-topped column, 0.5 m × 2.6 m, material unlit pure black `#000000` with `ALPHA` 1.0 and no specular, so it reads as a hole in the image. When it is observed for more than 2 s, a single 1 px white grid line appears across it at a random height for 100 ms (the only hint it is "being rendered"). Never casts a shadow. Never receives light.
- **Flicker:** no body. Its presence is a fixture group flickering (random on/off at 8 to 20 Hz with `Tween`-driven energy) and a `GPUParticles3D` burst of 1 cm white sparks (lifetime 0.3 s) when it jumps. On a lunge: a 2-frame white flash on the whole fixture group, then the whole group dark for 1.5 s.
- **Echo:** no body. Within 4 m: a man-sized capsule region of screen-space heat-shimmer (refraction 0.015, no fill). Its footsteps are the player's own footstep sounds delayed by 800 ms (`03`).
- **Null:** no body. A sphere of radius 12 m (24 m from depth 12 in Endless) centred on an invisible node drives `g_null_pos`/`g_null_radius`. Inside the radius the world unrenders (§5). At the centre, 2 m radius, the post shader paints pure black with the grid halo (§4 step 6) over everything, using the camera's distance to `g_null_pos` rather than the depth buffer. It is the only error whose "look" is the absence of the world.

## 9. Player-held visuals

- **Hands:** none. The camera is the player. The flashlight is drawn as a 0.18 m cylinder with a lens emissive at the lower right of the viewport, with a small bob (`06`) and a crank wheel on its side that visibly rotates when cranked.
- **Items** when selected appear in the lower-right hand position as primitive-built objects (`09`), 0.5 s lower-in and raise-out tween.
- **Noclip charge:** during charge, the world shader's `g_noclip_charge` drives an unrender preview anchored at the aimed surface point (`g_noclip_target`): a disc in the target surface's plane (surfaces within 0.3 m of it), radius 3 m × charge, peaking at u 0.9, plus the post shader's scanline shimmer. While the noclip is invalid (`g_noclip_invalid`) the preview grid is dashed. On commit: the full `noclip_commit` pulse, camera FOV punch (`11`).

## 10. Particles and small motion

- Dust motes: one `GPUParticles3D` box emitter following the player (12 m box, 200 particles, 3.5 mm quads, slow drift, alpha 0.12, lit by the flashlight). Present in Halls, Garage, Offices. Pools uses rising bubbles near water; Server uses none; Substrate uses 1 px white "pixels" drifting upward.
- Water drips (Pools): particle lines from ceiling at hashed positions, with ripple decal on impact.
- Polaroid use: a white flash and 12 floating "frames" (small quads) converging into the camera.
- Dissolve (death): the camera's view breaks into a 48 × 27 grid of quads that scatter with grain to black over 1.5 s (`11`).

## 11. Camera

- FOV default 90 (vertical FOV derived; settings 70 to 110). Near plane 0.05, far 120.
- Head bob: 0.03 m vertical, 0.015 m lateral at walk, 1.6× at sprint, 0 when still, scaled by the `head_bob` setting.
- Camera lean on strafe: 1.5° roll. Landing/crouch dip: 0.05 m over 120 ms.
- Camera shake: only from the Feedback Contract events, trauma-based (`shake = trauma^2`), max translational 0.04 m, max rotational 1.2°, scaled by the `screen_shake` setting.

## 12. Quality presets (the "visual contract" per tier)

| | Low | Medium | High |
|---|---|---|---|
| Lights enabled (pool) | 10 | 16 | 24 |
| Shadowed fixtures | 0 | 2 | 4 |
| Volumetric fog | off (distance fog) | on, 64 px froxel | on, 128 px |
| SSAO | off | on | on |
| SSIL | off | off | on |
| TAA | FXAA | TAA | TAA |
| Shadow atlas | 2048 | 4096 | 8192 |
| Render scale | 0.8 | 1.0 | 1.0 |
| Particles | 50% counts | 100% | 100% |
Every preset must pass T1, T3, T4, T5 and T6. Low may fail T2 only by fixture pool size.

## 13. Verification

- The screenshot tour (`14` §9) captures each stratum from 3 fixed camera poses at Coherence 100, 60, 30, 10, plus one frame mid-noclip and one with Null at 8 m. Agents check the targets in §2 against the captured frames (using `godot-agent-vision` where available, or by handing the frames to the human).
- A luminance histogram script over each tour frame asserts T1 and T3 numerically.

## Interfaces

- `StratumData` resource (`game/data/strata/*.tres`): palettes, fixture prefab path and grid spacing, fog colour and density, ambient colour and energy, exposure, water presence, prop lists, shadow bias.
- Global shader parameters (declared in `project.godot`): `g_coherence`, `g_noclip_charge`, `g_noclip_commit`, `g_noclip_target`, `g_noclip_target_normal`, `g_noclip_invalid`, `g_null_pos`, `g_null_radius`, `g_time`.
- `CoherenceRenderer` autoload: `set_coherence(v: float)`, `pulse(kind: StringName)`, `set_threat(v: float)`, `set_null(pos: Vector3, radius: float)`, `set_noclip_charge(v)`, `set_noclip_target(pos, normal)`, `set_noclip_invalid(on)`, `set_static(amount)`, `heartbeat_phase()`, `heartbeat_bpm()`, `register_viewport(vp)`, `apply_texture_detail(level)` (see `14` interface additions).
- `LightPool` node in the level scene: `register_fixture(fixture: Node3D)`, `set_group_flicker(group_id: int, on: bool)`, `power_wave(origin: Vector3)`.

### Interface additions during production
- M1.2 `LightPool` (`game/src/lighting/light_pool.gd`): `configure(stratum_data, preset)`, `target` (the node it measures from), `grid` (enables walking-distance ranking and grid-sight lending), `register_fixture`, `set_group_flicker`, `power_wave(origin) -> float` (seconds to the last ignition), `set_group_powered`, `set_all_powered`, `is_lit(pos)` (a player light query: inside a powered fixture's range), `reevaluate()`, `fixtures()`, `group(id)`, `group_ids()`, `active_light_count()`, `shadowed_light_count()`. Selection is `LightSelector` (walking distance, grid sight cached per cell). Each lent light carries its fixture's hum loop (`fixture_hum_<stratum>`, one in six `fixture_buzz_<stratum>`).
- M1.2 `Fixture` (`game/src/lighting/fixture.gd`, prefab per `StratumData.fixture_prefab_path`, group `fixtures`): `group_id`, `powered`, `intensity`, `set_powered(on)`, `power_on_wave(delay)`, `set_flicker(on)`, `is_emitting()`, signal `power_changed(on)`.
