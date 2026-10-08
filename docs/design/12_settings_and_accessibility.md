# 12 — Settings and Accessibility

**Depends on:** `00_OVERVIEW.md`, `02_visual_direction.md`, `03_audio_direction.md`, `04_ui_design_language.md`, `06_player.md`
**Skills to read:** `godot-input-handling`, `godot-save-load-systems`, `godot-platform-desktop`, `godot-ui-containers`

---

## 1. Rules

- Every option applies immediately (no "apply" button) except window mode and resolution, which apply on confirm with a 10 s revert countdown.
- Every option persists to `user://settings.cfg` (`13`) on change, debounced 0.5 s.
- Every option has a one-line description, a default, and a range. Defaults are chosen for a mid-range PC at 1080p.
- Settings are reachable from the title and from pause; changing them mid-run is allowed and safe.
- Mouse sensitivity, FOV, and keybindings are the three things the store reviews will mention first; they must be flawless.

## 2. DISPLAY

| Option | Type | Range / values | Default | Description |
|---|---|---|---|---|
| Window mode | enum | Fullscreen (borderless), Exclusive fullscreen, Windowed | Fullscreen | |
| Resolution | enum | the monitor's modes ≥ 1280 × 720 | native | Windowed and exclusive only |
| VSync | enum | Off, On, Adaptive | On | |
| Max FPS | int | 30 to 360, or Unlimited | Unlimited (VSync governs) | |
| Render scale | float | 0.5 to 1.5, step 0.05 | 1.0 | Below 1.0 the "Upscaling" choice applies; above 1.0 is bilinear supersampling |
| Upscaling | enum | Bilinear, FSR 2 | FSR 2 | Only active when render scale < 1.0. FSR 2 replaces anti-aliasing (the AA row is greyed and shows `FSR 2` while active) and is incompatible with MSAA |
| UI scale | float | 0.75 to 1.5, step 0.05 | 1.0 at 1080p, auto-derived from height | |
| Brightness (gamma) | float | 0.8 to 1.4, step 0.02 | 1.0 | Applied as the Environment's `adjustment_brightness`; a test strip with 8 greys and the words "the darkest bar should be barely visible" |
| Field of view | int | 70 to 110, step 1 | 90 | Horizontal FOV at 16:9. Converted to vertical (`vfov = 2·atan(tan(hfov/2) × 9/16)`) and applied with `KEEP_HEIGHT`, so wider monitors gain width and never lose height |
| Head bob | float | 0 to 1 | 1.0 | |
| Screen shake | float | 0 to 1 | 1.0 | Scales camera trauma |

## 3. GRAPHICS

| Option | Values | Default | Description |
|---|---|---|---|
| Preset | Low, Medium, High, Custom | Medium | Sets everything below (`02` §12); editing any item switches to Custom |
| Anti-aliasing | Off, FXAA, TAA, MSAA 2x, MSAA 4x | TAA | |
| Shadow quality | Off, Low (2048, 0 shadowed fixtures), Medium (4096, 2), High (8192, 4) | Medium | Flashlight shadows always on except Off |
| Ambient occlusion | Off, On | On | SSAO |
| Indirect lighting | Off, On | Off | SSIL |
| Volumetric fog | Off, Low, High | Low | Off uses distance fog |
| Glow | Off, On | On | |
| Particles | Low, Full | Full | |
| Light pool size | 10 to 32 | 16 | Advanced; shown under Custom only |
| Texture detail | Low, High | High | Noise texture resolution 512 or 1024 |

## 4. AUDIO

| Option | Range | Default |
|---|---|---|
| Master | 0 to 100 | 80 |
| Effects (World and Player buses) | 0 to 100 | 100 |
| Ambience | 0 to 100 | 100 |
| Music | 0 to 100 | 80 |
| UI | 0 to 100 | 80 |
| Output device | enum of `AudioServer.get_output_device_list()` | Default |
| Mute when unfocused | toggle | On |

Sliders map to dB with `linear_to_db(v / 100)` and −80 dB at 0. Each slider plays the slider tick at the new level.

## 5. CONTROLS

- **Mouse sensitivity:** 0.10 to 3.00, step 0.01, default 1.00, numeric field, and the live test square (`04` §7). Internally `0.0022 rad per pixel × value`.
- **Invert Y:** toggle, default Off.
- **Sprint:** Hold / Toggle, default Hold. **Crouch:** Hold / Toggle, default Hold.
- **Raw mouse input:** toggle, default On (`Input.use_accumulated_input` off; `MOUSE_MODE_CAPTURED`).
- **Key bindings:** every action in `06` §2 except the `ui_*` built-ins. Each row: action name, primary binding, secondary binding. Enter to rebind (captures the next key or mouse button; Esc cancels; Backspace clears). Conflicts: the two actions swap bindings (`04` §7) and both rows flash `ui_accent` for 2 s. Mouse buttons and wheel are bindable. Bindings display with `OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(...))` so a French AZERTY player sees Z Q S D. Physical keycodes are stored.
- `RESET TAB TO DEFAULTS` restores the default map.

## 6. ACCESSIBILITY

| Option | Values | Default | Effect |
|---|---|---|---|
| Sound cue captions | Off, On | Off | Captions per `04` §10 |
| Reduce visual noise | Off, On | Off | Caps grain, CA, scanline (`02` §4). Desaturation and vignette stay. |
| Reduce flashing | Off, On | Off | Replaces 2-frame white flashes (Flicker lunge, contact, Polaroid) with a 200 ms soft fade to 60% white; disables the title's unrender flicker |
| Flicker intensity | 0.3 to 1.0 | 1.0 | Scales the fixture flicker depth (Flicker's tell remains visible at 0.3 as a slow pulse 2 Hz) |
| Crosshair | Off, Dot, Dot and ring | Dot and ring | |
| HUD | Full, Minimal (Coherence, prompts, captions), Off (Coherence bar only) | Full | |
| Hints | On, Off | On | First-run guidance (`04` §9) |
| Text size | 0.9 to 1.4 | 1.0 | Multiplies note and caption sizes only |
| Hold-to-press | Off, On | Off | All hold interactions become presses (breaker, leave hide spot). Noclip remains a hold (it is the mechanic). |
| Colour-blind safe accent | Off, On | Off | Accent `#FFB000` becomes `#FFD166` with a 1 px outline on `ui_accent` elements; danger adds a `!` glyph; cold adds a `~` glyph |

## 7. GAMEPLAY

| Option | Values | Default |
|---|---|---|
| Show depth and stratum | On, Off | On |
| Exit status line | On, Off | On |
| Auto-sprint after stamina refill | Off, On | Off (if sprint was held) |
| Debug overlay (debug builds only) | Off, On | Off |

## 8. Persistence and defaults

- `SettingsManager` autoload loads `user://settings.cfg` at startup before the title (so the window mode is right from the first frame), validates every value against its range, and writes defaults for missing keys. Corrupt file: back it up as `settings.cfg.bad` and recreate.
- A `settings_version` key supports migrations.
- Window mode is applied in `_ready` before the first frame via `DisplayServer`.

## 9. Verification

- Unit tests: range clamping, migration from an older version, rebind conflict resolution, sensitivity math, FOV to `Camera3D.fov` conversion for 16:9 and 21:9.
- Manual: every option toggled in the pause menu during play at depth 3 with Still present; no crash, no stuck mouse mode, no HUD overlap at UI scale 1.5 and text size 1.4 on 1280 × 720.

## Interfaces

- `SettingsManager`: `get_value(key) -> Variant`, `set_value(key, v)`, signal `changed(key, v)`, `apply_preset(name)`, `reset_tab(tab)`, `bindings() -> Dictionary`, `rebind(action, event, slot)`.
- Consumers subscribe to `changed` for: FOV, sensitivity, invert, bob, shake, audio buses, post caps, captions, HUD mode, flashing, crosshair, text size.

### Interface additions during production
- M2.11 `SettingsManager`: `rebind(action, event, slot = 0) -> StringName` returns the swap partner (&"" when none); `binding(action, slot)`, `clear_binding(action, slot)`, `reset_bindings()`, signal `bindings_changed`; window changes from the menu go through `try_display(key, v)` / `keep_display()` / `revert_display()` / `is_display_pending()` / `display_seconds_left()`, signal `display_resolved(kept)`; `load_settings()`, `save_settings()`, `flush()`, `is_dirty()`, `settings_path()`, `bad_path()`, static `migrate(raw, version)`; `directory` (user://, user://tests under the test runner), `persist`, `now_msec` (test hook). Setting `preset` to Low/Medium/High applies it. Unknown keys are kept in memory and never written.
- `SettingsSchema` (`game/src/core/settings_schema.gd`, pure): `OPTIONS`, `DEFAULTS`, `TABS`, `option(key)`, `keys_for(tab)`, `validate(key, v)`, `preset_values(preset)`, `resolutions_for(screen)`. `SettingsBindings` holds the two slots per action (text form `key:<physical>:<location>`, `mouse:<button>`). `SettingsApply` reaches the window, vsync, max FPS, UI scale, raw mouse, output device, and the graphics profile (root viewport, every `WorldEnvironment`, `LightPool`, `GPUParticles3D`; re-applied on `level_entered`).
- New keys beyond the M0.2 set: every option of §2 to §7, including `texture_detail` (`low`/`high`, read by `CoherenceRenderer.apply_texture_detail`), `captions`, `hints`, `colorblind_accent`, `flicker_intensity`, `auto_sprint`, `debug_overlay`, `raw_mouse`, `audio_output_device`.
- M2.12: `SettingsApply.colorblind(on)` and `SettingsApply.text_size(v)` (through `UiAccessibility`) apply `colorblind_accent` and `text_size` at boot and on change. Consumers: HUD captions (`captions`), HUD hints (`hints`; set false by `HudHints` the first time a level at depth 3 or deeper is entered), the HUD repaint (`colorblind_accent`). `tests/unit/test_accessibility.gd` toggles every §6 option end to end (except `flicker_intensity`, which has no consumer yet).
