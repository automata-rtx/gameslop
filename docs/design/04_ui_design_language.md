# 04 — UI Design Language

**Depends on:** `00_OVERVIEW.md`, `02_visual_direction.md`
**Skills to read:** `godot-ui-theming`, `godot-ui-containers`, `godot-ui-rich-text`, `godot-tweening`, `godot-input-handling`
**Pulls engagement levers:** push-your-luck dial (Coherence always visible), decisions every minute (prompts are explicit), mastery ceiling (summary and Archive).

---

## 1. Thesis: the readout

The UI is what the world prints about you. It is a diagnostic overlay: monospace, white on black, one accent colour, thin lines, no icons that are not one-weight line glyphs, no panels with drop shadows, no rounded corners. It is sparse in play and dense in menus. It never animates for decoration; it animates to show a value changing.

If a screen could be mistaken for a 2015 mobile game menu, it is wrong. If it could be mistaken for a terminal printout of a building management system, it is right.

## 2. Typography

- **Typeface:** one monospace family, bundled under its open license: first choice JetBrains Mono (OFL), fallback IBM Plex Mono (OFL). Weights used: Regular and Bold only. `CREDITS.md` lists the license.
- **Sizes** (at 1080p; UI scale setting multiplies): HUD body 18 px, HUD numerals 24 px Bold, prompts 20 px, menu items 22 px, menu headings 28 px Bold, title wordmark 160 px Bold with letter spacing 0.18 em, note sheets 20 px, captions 20 px.
- **Casing:** HUD and headings in UPPERCASE. Note text in sentence case. Menu descriptions in sentence case.
- **Tracking:** uppercase strings use +0.08 em letter spacing.
- Text never has an outline or shadow. Contrast comes from a 60% black backing rectangle only where the world would make it unreadable (prompts, captions).

## 3. Colour

| Token | Hex | Use |
|---|---|---|
| `ui_fg` | `#F2F2F2` | All text and lines |
| `ui_dim` | `#8C8C8C` | Secondary text, inactive items, bar tracks |
| `ui_bg` | `#000000` | Menu backgrounds, backing rectangles at 60% alpha |
| `ui_accent` | `#FFB000` | Interactables, the selected menu item, Coherence gain flashes, the current depth label. The Halls fixture amber, so the accent belongs to the world. |
| `ui_danger` | `#FF3B3B` | Only: Coherence below 25, stamina empty, "DISSOLVED" banner. Never used for emphasis. |
| `ui_cold` | `#3B8BFF` | Only: noclip charge arc and the Substrate depth label. |

Rules: at most two colours on screen besides `ui_fg` and `ui_dim` at any time. Accent is for "you can act on this". Danger is for "you are about to lose". Cold is for "unreal".

## 4. Geometry and motion

- **Grid:** 8 px base unit. Margins 32 px from screen edges (safe area). All HUD elements snap to the grid.
- **Lines:** 1 px at 1080p (scaled with UI scale, minimum 1 px). Bars are 2 px tall tracks with a 4 px fill.
- **Panels:** no borders except a single 1 px top rule on menus. No background on HUD elements except prompts and captions.
- **Motion:** values tween with `TRANS_EXPO`/`EASE_OUT` over 180 ms. Elements appear with a 120 ms **slice-in**: the element is revealed by 6 horizontal bands opening at staggered 10 ms offsets (a shutter), never by fade or scale. Elements leave by the same shutter closing. Screen transitions use a 120 ms glitch: the previous frame is held, sliced horizontally into 8 to 14 bands offset by ±12 px with CA 0.02, then cut.
- **Typing effect:** notifications and the summary's lines print at 60 characters per second with a block cursor `▌` (U+258C, present in the bundled font) that blinks at 2 Hz and disappears when the line finishes.
- **Sound:** every motion has its UI sound (`03` §4).

## 5. Glyphs

All icons are hand-written SVGs in `game/assets/ui/glyphs/`, 24 × 24 viewBox, 1.5 px stroke, round caps, no fills except where noted, `ui_fg` by default. Required set:

`polaroid` (square with thicker bottom band), `glowstick` (rounded rod with a diagonal split), `flare` (rod with three ray lines), `chalk` (short tapered stick), `radio` (box with antenna and two dials), `fuse` (cylinder with end caps), `key` (card with notch), `flashlight` (cylinder with beam lines), `crank` (circle with handle), `noclip` (square with one side dashed), `exit` (door with arrow), `breaker` (lever in box), `note` (sheet with folded corner), `eye` (Still codex), `wave` (Static codex), `bolt` (Flicker codex), `steps` (Echo codex), `null` (empty square, dashed), `depth` (downward chevron stack), `coherence` (circle with inner concentric), `settings` (sliders), `archive` (box with lid), `daily` (calendar square), `endless` (loop), `check`, `cross`, `arrow_l`, `arrow_r`, `arrow_u`, `arrow_d`, `mouse_l`, `mouse_r`, `mouse_wheel`, `key_cap` (generic keycap outline for binding display).

## 6. The HUD (in play)

Layout at 1920 × 1080 (grid-snapped; positions scale with UI scale and anchor to safe margins):

```
┌──────────────────────────────────────────────────────────────┐
│ COHERENCE 087 ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬░░░░        DEPTH 03 · GARAGE │
│                                                 EXIT: POWERED │
│                                                               │
│                                                               │
│                            ·                                  │
│                          ( + )        ← crosshair, stamina arc│
│                            ·                                  │
│                                                               │
│                      [E] OPEN DOOR                            │
│                                                               │
│ ⟟ 62%  ← crank gauge                 1 PO ×2  2 GL ×1  3 —  4 —│
└──────────────────────────────────────────────────────────────┘
```

- **Coherence** (top-left): `COHERENCE` label in `ui_dim`, numeral in `ui_fg` Bold, 240 px bar beneath. The numeral ticks (not jumps) at 30 units per second. Loss: the lost segment of the bar stays lit in `ui_danger` for 600 ms then shutters out. Gain: the gained segment flashes `ui_accent` 200 ms. Below 25: label and numeral turn `ui_danger` and the bar track pulses at the heartbeat rate. The bar is always visible; it never auto-hides (pillar 1).
- **Depth** (top-right): `DEPTH 03 · GARAGE`. Depth numeral in `ui_accent` (Substrate: `ui_cold`). Beneath it, exit status line in `ui_dim`: `EXIT: UNKNOWN` until the exit is seen, then `EXIT: OPEN`, `EXIT: POWERED` (needs breaker), `EXIT: KEYED`, `EXIT: SEALED 02:14` (timed), switching to `ui_fg` when the lock is cleared. Seen means the exit entered the camera frustum within 25 m and unoccluded.
- **Crosshair** (centre): a 2 px dot. On an interactable within reach: the dot becomes a 12 px circle with a 2 px gap. **Stamina arc:** a 180° arc below the crosshair, radius 18 px, visible only when stamina < 100, `ui_fg`, turning `ui_danger` when empty, shuttering out 1 s after refill.
- **Noclip charge arc:** a full 360° arc at radius 24 px in `ui_cold` filling clockwise with charge, with a 1 px outer "echo" ring that completes 100 ms before commit as a readiness tell. The arc shows the target type as a glyph at its top: `noclip` glyph for wall, `arrow_d` for floor. If the target is invalid, the arc is drawn dashed in `ui_dim` and a one-word reason prints below the crosshair: `SOLID`, `NO SPACE`, `TOO FAR`.
- **Prompt** (centre, 120 px below crosshair): `[E] OPEN DOOR`, `[E] PICK UP POLAROID`, `[E] HIDE`, `[E] FLIP BREAKER`, `[E] INSERT FUSE`, `[HOLD E] LEAVE HIDING`. Key cap drawn as a 1 px box around the key name from the current binding. Backing rectangle 60% black. Appears with the shutter.
- **Crank gauge** (bottom-left): `crank` glyph plus percent. The glyph's handle rotates while cranking. Turns `ui_dim` at 100%. Below 15%: percent in `ui_danger`.
- **Item belt** (bottom-right): four slots as `N GLYPH ×count`. Selected slot has a 1 px underline in `ui_accent`. Empty slots show `—`. Selecting pulses the glyph 1.15× for 100 ms.
- **Notifications** (top-centre, below the safe margin): single-line typed messages, `ui_dim`, 4 s, max two stacked: `ARCHIVE: NOTE G2`, `ITEM UNLOCKED: RADIO`, `EXIT UNLOCKED`.
- **Threat vignette and heartbeat** are the renderer's (`02`), not HUD elements.
- **Hidden state:** while hiding (`09`), the HUD dims to 40% except the crosshair, which becomes a `eye` glyph; the prompt reads `[HOLD E] LEAVE`.
- **Noclip down confirmation:** none. The charge time is the confirmation.
- **HUD hide option** (`12`): hides everything except Coherence bar, prompts, and captions.

## 7. Menus

All menus share one scene (`ui/menu_shell.tscn`): black background, a title line at the top-left (28 px Bold), a 1 px rule under it, a left column list (22 px, 40 px row height, `ui_accent` selected item with a `▸` prefix), and a right column detail area. Keyboard navigation (arrows, Enter, Esc) and mouse both work; the selected item follows the hovered item. The list never scrolls more than one screen; use submenus instead.

### Title screen
- Background: a live, slowly moving camera through a generated Halls corridor (seed 0, no errors), fog up 30%, the Coherence renderer at 85 so there is faint grain. Every 25 to 40 s a 200 ms unrender flicker ripples through the corridor.
- Wordmark `NOCLIP` centred-left at 160 px, with a 1 px grid of 8 px cells behind the letters that only renders where the wordmark's letters are not. Beneath, in `ui_dim` 18 px: `v1.0.0 · MADE BY AN AI · SEED OF THE DAY 20261007`.
- Menu: `DESCEND`, `DAILY DESCENT`, `ENDLESS` (shown only after a win), `ARCHIVE`, `SETTINGS`, `QUIT`. Detail column shows for DESCEND: best depth, runs, wins, last cause of death, loadout selector (`05`).
- Boot: on launch, 1.2 s of black with the typed line `rendering…` then the shutter reveals the title. Skippable after the first launch.

### Pause
- Overlays the frozen frame with a 70% black and the glitch hold. Items: `RESUME`, `SETTINGS`, `ABANDON DESCENT` (confirmation: `This ends the run. Depth and notes found are kept.` with `ABANDON` / `BACK`), `QUIT TO TITLE`.

### Settings
- Tabs as the left column: `DISPLAY`, `GRAPHICS`, `AUDIO`, `CONTROLS`, `ACCESSIBILITY`, `GAMEPLAY`. Detail column lists options as `LABEL ………… value` rows with a 1 px dotted leader. Sliders are 200 px tracks with the numeric value to the right, editable by typing. Every option has a one-line description in `ui_dim` shown when selected. `RESET TAB TO DEFAULTS` at the bottom of each tab. Full option list in `12`.
- Controls tab: list of actions with current binding; Enter to rebind, Esc to cancel, Backspace to clear; conflicts resolved by swapping and shown in `ui_accent` for 2 s. Mouse sensitivity slider has a live `TEST` area: a 200 px square with a dot that moves with the mouse at the chosen sensitivity.

### Archive
- Left column: `NOTES`, `ERRORS`, `STATISTICS`, `UNLOCKS`. Notes grid: 6 columns (strata) × 6 rows, each cell either the note ID or `··`. Selecting a found note shows its sheet in the detail column. Errors: five entries, each locked (`··`) until first encounter; after 3 encounters the codex adds the counter line as a builder memo. Statistics: total runs, wins, best depth, best score, deaths by error, distance walked, walls passed, floors dropped, Coherence spent, notes found. Unlocks: the 14 milestones with condition and state.

### Run summary (after death or win)
- Full black. Top line typed: `DISSOLVED BY STILL · DEPTH 03 · GARAGE` (or `THRESHOLD CROSSED · DEPTH 06`), Bold, `ui_danger` or `ui_accent`.
- Then a table typed line by line: `DEPTH 3`, `TIME 11:42`, `COHERENCE SPENT 112`, `WALLS PASSED 4`, `FLOORS DROPPED 1`, `NOTES FOUND 2`, `ERRORS EVADED 5`, `SCORE 2,310`, `BEST 4,880`. Then unlock lines in `ui_accent`.
- Items: `DESCEND AGAIN` (default selected; Enter restarts within 1 s), `ARCHIVE`, `TITLE`.

### Loadout select (inside DESCEND detail column)
- Four cards in a row (only unlocked ones selectable): name, one-line description, starting items as glyphs. Left/right to change, Enter to start.

## 8. Note sheets and the captions

- **Note sheet:** lower third, 720 px wide, 8 px padding, backing `#1A1A1A` at 92% with a 1 px `ui_dim` top rule; faller notes tint the backing `#1F1B14`, builder memos `#141A1F`, strays `#171717`. The header line: `NOTE H3 · HANDWRITTEN`, `RENDER NOTE 0014`, or `FOUND OBJECT`. Text types at 90 characters per second. Any movement key held 0.5 s dismisses with the shutter. The world does not pause.
- **Captions** (`12` accessibility): bottom-centre above the prompt, `ui_fg` on 60% black: `[hum, left]`, `[footsteps, behind, late]`, `[lights stutter]`, `[door slams, far]`, `[grid tone, ahead]`, `[silence]`. Direction derived from the listener-relative angle in 8 sectors; distance as `near` (<6 m), none (6 to 20 m), `far` (>20 m).

## 9. First-run guidance (no tutorial screens)

Contextual hints are single prompt-style lines, `ui_dim`, shown once each, in the prompt position, for 6 s or until the action is performed:

All key names below are rendered from the current bindings (`SettingsManager.bindings()`); the defaults are shown.

1. On spawn: `[W A S D] MOVE · [MOUSE] LOOK` (shown until 3 m walked).
2. At 15 s or when ambient light drops: `[F] FLASHLIGHT`.
3. When the flashlight is first below 60%: `[HOLD R] CRANK`.
4. First soft wall within 3 m and aimed at: `[HOLD LMB] NOCLIP`.
5. First time aiming at the floor with no soft wall for 5 s on depth 2 or deeper: `[HOLD LMB ON FLOOR] DROP A LEVEL · COSTS COHERENCE`.
6. First item picked up: `[1-4] SELECT · [RMB] USE`.
7. First time Coherence drops below 50: `COHERENCE IS HOW REAL YOU ARE`.

These are suppressed after the player has reached depth 3 once. The settings `GAMEPLAY` tab can turn them back on.

## 10. Caption text table

| Event | Caption |
|---|---|
| Static audible | `[hum, {dir}{dist}]` |
| Still within 8 m (silence) | `[silence]` |
| Still render tick | `[a line]` |
| Flicker present in a group | `[lights stutter, {dir}{dist}]` |
| Flicker jump | `[sparks, {dir}]` |
| Flicker lunge | `[flash]` |
| Echo footstep | `[footsteps, {dir}, late]` |
| Null audible | `[grid tone, {dir}{dist}]` |
| Door slam (Director) | `[door slams, {dir}{dist}]` |
| Payphone ring | `[phone rings, {dir}{dist}]` |
| Breaker | `[breaker thrown]` |
| Power wave | `[lights waking]` |
| Noclip commit | `[tear]` |
| Error contact | `[contact]` |

## 11. Verification

- A `ui_gallery.tscn` debug scene shows every HUD state (all values at 100/50/10, every prompt, every lock status, hiding, each note voice) and every menu for screenshot review.
- Every string shown to the player lives in `game/data/strings.gd` as constants, uppercase keys, so that a tone pass can review them in one file.

## Interfaces

- `HUD` scene methods: `set_coherence(v: float, delta: float)`, `set_depth(depth: int, stratum: StringName)`, `set_exit_status(status: StringName, timer: float)`, `set_stamina(v: float)`, `set_crank(v: float)`, `set_noclip(charge: float, target: StringName, valid: bool, reason: StringName)`, `show_prompt(text: String)`, `hide_prompt()`, `set_items(slots: Array[ItemSlot], selected: int)`, `notify(text: String)`, `show_note(note: NoteData)`, `set_hidden(on: bool)`, `caption(text: String)`.
- `MenuShell` scene: `open(menu_id: StringName)`, `close()`, with submenus as `Control` children registered by id.
- `Theme` resource `game/assets/ui/noclip_theme.tres` provides fonts, colours, and the dotted leader `StyleBox`.
