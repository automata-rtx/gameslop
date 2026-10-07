class_name Strings
extends RefCounted
## Every string shown to the player, except notes (notes live in data, M0.4). Constants only,
## so a tone pass can review the whole game's voice in one file (04 §11).
## Rules (01 §2, 01 §6 writing rules, GLOSSARY): none of the forbidden words, no
## exclamation marks, no ellipses; HUD and headings are UPPERCASE, descriptions are sentence case;
## errors are "errors" and are named by their glossary names only.
## Placeholders use {name}. Hint and prompt templates name the input action (06 §2) in braces,
## e.g. {interact}: the UI replaces it with the bound key's name (SettingsManager.bindings()).
## {key} is used where a single prompt shows whichever key the interactable uses.


# =====================================================================================
# 04 §7  Title screen
# =====================================================================================
const TITLE_WORDMARK := "NOCLIP"
const TITLE_VERSION_LINE := "v{version} · MADE BY AN AI · SEED OF THE DAY {seed}"   # v1.0.0 · ... 20261007
const TITLE_BOOT_LINE := "rendering"                # typed, then the shutter (04 §7 prints "rendering…"; 01 §6 bans ellipses and wins)
const MENU_DESCEND := "DESCEND"
const MENU_DAILY := "DAILY DESCENT"
const MENU_ENDLESS := "ENDLESS"                     # shown only after a win
const MENU_ARCHIVE := "ARCHIVE"
const MENU_SETTINGS := "SETTINGS"
const MENU_QUIT := "QUIT"
const MENU_SELECTED_PREFIX := "▸ "
const MENU_CURSOR := "▮"                            # block cursor on typed lines
const TITLE_LABEL_BEST_DEPTH := "BEST DEPTH"        # DESCEND detail column
const TITLE_LABEL_RUNS := "RUNS"
const TITLE_LABEL_WINS := "WINS"
const TITLE_LABEL_LAST_CAUSE := "LAST CAUSE OF DEATH"
const TITLE_LABEL_LOADOUT := "LOADOUT"
const TITLE_DAILY_DONE := "SCORE {score} · DEPTH {depth}"   # Daily item once played today (not selectable)
const TITLE_ARCHIVE_RESET := "ARCHIVE RESET"        # 13 §2: shown once after a corrupt meta file

# 04 §7  Pause
const PAUSE_RESUME := "RESUME"
const PAUSE_SETTINGS := "SETTINGS"
const PAUSE_ABANDON := "ABANDON DESCENT"
const PAUSE_QUIT_TITLE := "QUIT TO TITLE"
const PAUSE_ABANDON_CONFIRM := "This ends the run. Depth and notes found are kept."
const PAUSE_ABANDON_YES := "ABANDON"
const PAUSE_ABANDON_NO := "BACK"


# =====================================================================================
# 04 §6  HUD
# =====================================================================================
const HUD_COHERENCE := "COHERENCE"
const HUD_DEPTH_LINE := "DEPTH {depth} · {stratum}"           # DEPTH 03 · GARAGE (depth zero-padded to 2)
const HUD_EXIT_UNKNOWN := "EXIT: UNKNOWN"
const HUD_EXIT_OPEN := "EXIT: OPEN"
const HUD_EXIT_POWERED := "EXIT: POWERED"
const HUD_EXIT_KEYED := "EXIT: KEYED"
const HUD_EXIT_SEALED := "EXIT: SEALED {time}"                # EXIT: SEALED 02:14
const HUD_EXIT_OPEN_TIMED := "EXIT: OPEN {time}"              # Cycled, open window: EXIT: OPEN 00:20 (07 §6)
const HUD_EXIT_STATUS: Dictionary = {                         # keyed by exit_status_changed status ids
	&"unknown": "EXIT: UNKNOWN",
	&"open": "EXIT: OPEN",
	&"powered": "EXIT: POWERED",
	&"keyed": "EXIT: KEYED",
	&"sealed": "EXIT: SEALED {time}",
}
const HUD_BELT_EMPTY := "—"
const HUD_BELT_SLOT := "{slot} {glyph} ×{count}"
const HUD_CRANK_PERCENT := "{percent}%"

# 04 §6, 06 §8  Noclip invalid reasons (one word under the crosshair)
const NOCLIP_REASON_SOLID := "SOLID"
const NOCLIP_REASON_NO_SPACE := "NO SPACE"
const NOCLIP_REASON_TOO_FAR := "TOO FAR"
const NOCLIP_REASON_TOO_THIN := "TOO THIN"                    # 06 §8, added after the lock
const NOCLIP_REASONS: Dictionary = {
	&"SOLID": "SOLID", &"NO SPACE": "NO SPACE", &"TOO FAR": "TOO FAR", &"TOO THIN": "TOO THIN",
}

# 04 §6, 09 §5, 11  Prompts. Format: PROMPT_PRESS or PROMPT_HOLD around one of the texts below.
# Press or hold is the interactable's hold_time (06 §7), not part of the text.
const PROMPT_PRESS := "[{key}] {text}"
const PROMPT_HOLD := "[HOLD {key}] {text}"
const PROMPT_OPEN_DOOR := "OPEN DOOR"
const PROMPT_CLOSE_DOOR := "CLOSE DOOR"
const PROMPT_PICK_UP := "PICK UP {item}"
const PROMPT_SWAP := "SWAP FOR {item}"
const PROMPT_HIDE := "HIDE"
const PROMPT_LEAVE_HIDING := "LEAVE HIDING"
const PROMPT_LEAVE := "LEAVE"                                 # hidden-state prompt (04 §6, 09 §5)
const PROMPT_FLIP_BREAKER := "FLIP BREAKER"                   # 04 §6 wording wins over 09 "THROW BREAKER"; it is a hold (09, 07 §6)
const PROMPT_INSERT_FUSE := "INSERT FUSE"
const PROMPT_PULL_FUSE := "PULL FUSE"
const PROMPT_FUSE_MISSING := "FUSE MISSING"                   # ui_dim, no key
const PROMPT_SWIPE := "SWIPE"
const PROMPT_NO_CARD := "NO CARD"                             # ui_dim
const PROMPT_USE := "USE"
const PROMPT_ANSWER := "ANSWER"
const PROMPT_READ := "READ"
const PROMPT_LANDING_SLOT := "[{key}] {item}"                 # [1] / [2] from the item_1 / item_2 bindings (05 §4)

# 04 §6, 05 §4, 11 §3  Notifications and status messages
const MSG_DESCENDING := "DESCENDING"
const MSG_DROPPED := "DROPPED · THEY ARE AWAKE"
const MSG_EXIT_UNLOCKED := "EXIT UNLOCKED"
const MSG_COHERENCE_GAIN := "COHERENCE +{amount}"             # Landing panel: COHERENCE +20
const MSG_COHERENCE_LOSS := "COHERENCE −{amount}"
const MSG_CHOOSE_ONE := "CHOOSE ONE"                          # shown once, the first Landing at depth 2 (05 §10)
const MSG_ARCHIVE_NOTE := "ARCHIVE: NOTE {id}"
const MSG_ITEM_UNLOCKED := "ITEM UNLOCKED: {name}"
const MSG_LOADOUT_UNLOCKED := "LOADOUT UNLOCKED: {name}"
const MSG_MODE_UNLOCKED := "MODE UNLOCKED: {name}"            # same pattern for modes (inferred from 01 §9)
const MSG_ARCHIVE_UNLOCKED := "ARCHIVE: {name}"               # codex lines and the builder's note (inferred from 01 §9)

# 04 §9  First-run hints (templates; {action} is replaced by the bound key name)
const HINT_MOVE := "[{move_forward} {move_left} {move_back} {move_right}] MOVE · [MOUSE] LOOK"
const HINT_FLASHLIGHT := "[{flashlight}] FLASHLIGHT"
const HINT_CRANK := "[HOLD {crank}] CRANK"
const HINT_NOCLIP := "[HOLD {noclip}] NOCLIP"
const HINT_DROP := "[HOLD {noclip} ON FLOOR] DROP A LEVEL · COSTS COHERENCE"
const HINT_ITEMS := "[{item_1}-{item_4}] SELECT · [{use_item}] USE"
const HINT_COHERENCE := "COHERENCE IS HOW REAL YOU ARE"
const HINTS_IN_ORDER: Array[String] = [
	HINT_MOVE, HINT_FLASHLIGHT, HINT_CRANK, HINT_NOCLIP, HINT_DROP, HINT_ITEMS, HINT_COHERENCE,
]

# 04 §9, 12 §5  Key and button names for bindings that are not keyboard keys
const BINDING_MOUSE_LEFT := "LMB"
const BINDING_MOUSE_RIGHT := "RMB"
const BINDING_MOUSE_MIDDLE := "MMB"
const BINDING_WHEEL_UP := "WHEEL UP"
const BINDING_WHEEL_DOWN := "WHEEL DOWN"
const BINDING_NONE := "—"


# =====================================================================================
# 04 §8, 04 §10  Captions (sound cue captions; {dir} and {dist} from the 8-sector listener angle)
# =====================================================================================
const CAPTION_STATIC := "[hum, {dir}{dist}]"
const CAPTION_STILL_SILENCE := "[silence]"
const CAPTION_STILL_TICK := "[a line]"
const CAPTION_FLICKER_PRESENT := "[lights stutter, {dir}{dist}]"
const CAPTION_FLICKER_JUMP := "[sparks, {dir}]"
const CAPTION_FLICKER_LUNGE := "[flash]"
const CAPTION_ECHO_FOOTSTEP := "[footsteps, {dir}, late]"
const CAPTION_NULL := "[grid tone, {dir}{dist}]"
const CAPTION_DOOR_SLAM := "[door slams, {dir}{dist}]"
const CAPTION_PAYPHONE := "[phone rings, {dir}{dist}]"
const CAPTION_BREAKER := "[breaker thrown]"
const CAPTION_POWER_WAVE := "[lights waking]"
const CAPTION_NOCLIP_COMMIT := "[tear]"
const CAPTION_CONTACT := "[contact]"
## {dist}: "near" (< 6 m), nothing (6 to 20 m), "far" (> 20 m); the fragment carries its own comma.
const CAPTION_DIST_NEAR := ", near"
const CAPTION_DIST_MID := ""
const CAPTION_DIST_FAR := ", far"
## {dir}: listener-relative, 8 sectors clockwise from straight ahead (04 §8 shows ahead, behind, left).
const CAPTION_DIRECTIONS: Array[String] = [
	"ahead", "ahead right", "right", "behind right", "behind", "behind left", "left", "ahead left",
]


# =====================================================================================
# 04 §7, 13 §5  Archive
# =====================================================================================
const ARCHIVE_NOTES := "NOTES"
const ARCHIVE_ERRORS := "ERRORS"
const ARCHIVE_STATISTICS := "STATISTICS"
const ARCHIVE_UNLOCKS := "UNLOCKS"
const ARCHIVE_LOCKED_CELL := "··"                   # undiscovered note or error
const NOTE_HEADER_FALLER := "NOTE {id} · HANDWRITTEN"
const NOTE_HEADER_BUILDER := "RENDER NOTE {number}"
const NOTE_HEADER_STRAY := "FOUND OBJECT"
const STAT_RUNS := "RUNS"
const STAT_WINS := "WINS"
const STAT_BEST_DEPTH := "BEST DEPTH"
const STAT_BEST_SCORE := "BEST SCORE"
const STAT_DEATHS_BY := "DEATHS BY"
const STAT_DISTANCE_WALKED := "DISTANCE WALKED"
const STAT_WALLS_PASSED := "WALLS PASSED"
const STAT_FLOORS_DROPPED := "FLOORS DROPPED"
const STAT_COHERENCE_SPENT := "COHERENCE SPENT"
const STAT_NOTES_FOUND := "NOTES FOUND"
const STAT_POLAROIDS_SEEN := "POLAROIDS SEEN"        # 13 §5: thumbnails of images seen
const STATS_ORDER: Array[String] = [
	"RUNS", "WINS", "BEST DEPTH", "BEST SCORE", "DEATHS BY", "DISTANCE WALKED", "WALLS PASSED",
	"FLOORS DROPPED", "COHERENCE SPENT", "NOTES FOUND",
]

## Error names (GLOSSARY) and builder-memo codex text (08 §3 to §7).
const ERROR_NAMES: Dictionary = {
	&"static": "STATIC", &"still": "STILL", &"flicker": "FLICKER", &"echo": "ECHO", &"null": "NULL",
}
const ERROR_CODEX: Dictionary = {
	&"static": "RENDER NOTE. Sound fill drifts at 0.6 m/s and leans toward footsteps. It is thin at the edge. It does not pass a flame.",
	&"still": "RENDER NOTE. Object is updated only when unobserved. Observation requires illumination. Audio is culled within 8 m. Known issue: object may be closer than last drawn.",
	&"flicker": "RENDER NOTE. Fixture process escapes its loop. Habitat: powered fixtures. Jumps to handheld electrical sources within 4 m. Does not persist in darkness. Does not recognise chemical light.",
	&"echo": "RENDER NOTE. Playback trails input by 800 ms in tiled volumes. Rate matches input. Stops when input stops. Will not fix.",
	# 08 §7 reads "implemented as an entity"; "entity" is a forbidden word (01 §2, GLOSSARY), so "object" (as in Still's memo) is used.
	&"null": "RENDER NOTE. Draw distance implemented as an object. Speed 2.4 m/s. Passes all geometry. Nothing inside it. Do not name it.",
}


# =====================================================================================
# 04 §7  Run summary
# =====================================================================================
const SUMMARY_TOP_LINE := "{cause} · DEPTH {depth} · {stratum}"          # DISSOLVED BY STILL · DEPTH 03 · GARAGE
const SUMMARY_WIN_LINE := "THRESHOLD CROSSED · DEPTH {depth}"             # THRESHOLD CROSSED · DEPTH 06
const SUMMARY_LINE_DEPTH := "DEPTH {value}"
const SUMMARY_LINE_TIME := "TIME {value}"                                  # mm:ss
const SUMMARY_LINE_COHERENCE_SPENT := "COHERENCE SPENT {value}"
const SUMMARY_LINE_WALLS_PASSED := "WALLS PASSED {value}"
const SUMMARY_LINE_FLOORS_DROPPED := "FLOORS DROPPED {value}"
const SUMMARY_LINE_NOTES_FOUND := "NOTES FOUND {value}"
const SUMMARY_LINE_ERRORS_EVADED := "ERRORS EVADED {value}"
const SUMMARY_LINE_SCORE := "SCORE {value}"                                # thousands separator: 2,310
const SUMMARY_LINE_BEST := "BEST {value}"
const SUMMARY_DESCEND_AGAIN := "DESCEND AGAIN"
const SUMMARY_ARCHIVE := "ARCHIVE"
const SUMMARY_TITLE := "TITLE"
## Cause-of-death lines, keyed by the cause id passed to run_ended (06 §9, 08 §1, 05 §8).
const CAUSE_LINES: Dictionary = {
	&"static": "DISSOLVED BY STATIC",
	&"still": "DISSOLVED BY STILL",
	&"flicker": "DISSOLVED BY FLICKER",
	&"echo": "DISSOLVED BY ECHO",
	&"null": "DISSOLVED BY NULL",
	&"substrate": "DISSOLVED BY THE SUBSTRATE",
	&"threshold": "THRESHOLD CROSSED",
	&"abandoned": "DESCENT ABANDONED",              # not in the design text; a run can end by abandonment (05 §1)
}
const CAUSE_DISSOLVED_BY := "DISSOLVED BY {error}"
const CAUSE_DISSOLVED_BY_SUBSTRATE := "DISSOLVED BY THE SUBSTRATE"


# =====================================================================================
# 05 §2, 01 §4  Strata, 05 §8 modes, 05 §7 loadouts, 05 §6 unlocks
# =====================================================================================
const STRATUM_NAMES: Dictionary = {
	&"halls": "HALLS", &"pools": "POOLS", &"garage": "GARAGE", &"offices": "OFFICES",
	&"server": "SERVER", &"substrate": "SUBSTRATE",
}
const MODE_NAMES: Dictionary = {
	&"descent": "DESCENT", &"daily": "DAILY DESCENT", &"endless": "ENDLESS",
}
const ITEM_NAMES: Dictionary = {
	&"polaroid": "POLAROID", &"glowstick": "GLOWSTICK", &"flare": "FLARE",
	&"chalk": "CHALK", &"radio": "RADIO", &"fuse": "FUSE", &"keycard": "KEYCARD",
}
const LOADOUT_NAMES: Dictionary = {
	&"faller": "FALLER", &"cartographer": "CARTOGRAPHER", &"lightbearer": "LIGHTBEARER", &"diver": "DIVER",
}
const LOADOUT_DESCRIPTIONS: Dictionary = {
	&"faller": "Polaroid and eight uses of chalk. Coherence 100. No trade-off.",
	&"cartographer": "Twenty uses of chalk and a radio. Starts with 90 Coherence.",
	&"lightbearer": "Three glowsticks and a flare. Cranks 1.5 times faster. No Polaroid. Flicker is drawn to your light from 1.5 times the distance.",
	&"diver": "Two Polaroids. Starts at depth 3 with 70 Coherence. Skips depths 1 and 2 and their rewards.",
}
const LOADOUT_UNLOCK_CONDITIONS: Dictionary = {
	&"faller": "Always available.",
	&"cartographer": "Find 5 notes.",
	&"lightbearer": "Evade Flicker 3 times in one run.",
	&"diver": "Reach depth 4 twice.",
}
const LOADOUT_LOCKED := "LOCKED"

## The 14 milestone unlocks (05 §6), in order. Ids match Tuning.UNLOCK_IDS and the meta.json "unlocks" keys (13 §2).
const UNLOCK_NAMES: Dictionary = {
	&"glowstick": "GLOWSTICK",
	&"radio": "RADIO",
	&"flare": "FLARE",
	&"fuse": "FUSE",
	&"cartographer": "CARTOGRAPHER",
	&"lightbearer": "LIGHTBEARER",
	&"diver": "DIVER",
	&"daily": "DAILY DESCENT",
	&"endless": "ENDLESS",
	&"codex_still": "STILL CODEX",
	&"codex_echo": "ECHO CODEX",
	&"codex_flicker": "FLICKER CODEX",
	&"codex_null": "NULL CODEX",
	&"note_u6": "THE BUILDER'S NOTE",
}
const UNLOCK_DESCRIPTIONS: Dictionary = {
	&"glowstick": "Reach depth 2. The glowstick joins the item pool.",
	&"radio": "Reach depth 3. The radio joins the item pool.",
	&"flare": "Reach depth 4. The flare joins the item pool.",
	&"fuse": "Reach depth 5. The fuse joins the item pool, and Powered exits may have an empty fuse socket.",
	&"cartographer": "Find 5 notes. Unlocks the Cartographer loadout.",
	&"lightbearer": "Evade Flicker 3 times in one run. Unlocks the Lightbearer loadout.",
	&"diver": "Reach depth 4 twice. Unlocks the Diver loadout.",
	&"daily": "Reach depth 3. Unlocks Daily Descent.",
	&"endless": "Cross the Threshold. Unlocks Endless and Cycle 2.",
	&"codex_still": "Encounter Still 3 times. Adds its counter line to the Archive.",
	&"codex_echo": "Encounter Echo 3 times. Adds its counter line to the Archive.",
	&"codex_flicker": "Encounter Flicker 3 times. Adds its counter line to the Archive.",
	&"codex_null": "Encounter Null 3 times. Adds its counter line to the Archive.",
	&"note_u6": "Find all 35 other notes. Adds the last note and the ending variant.",
}


# =====================================================================================
# 12  Settings and accessibility
# =====================================================================================
const SETTINGS_TABS: Array[String] = ["DISPLAY", "GRAPHICS", "AUDIO", "CONTROLS", "ACCESSIBILITY", "GAMEPLAY"]
const SETTINGS_TAB_DISPLAY := "DISPLAY"
const SETTINGS_TAB_GRAPHICS := "GRAPHICS"
const SETTINGS_TAB_AUDIO := "AUDIO"
const SETTINGS_TAB_CONTROLS := "CONTROLS"
const SETTINGS_TAB_ACCESSIBILITY := "ACCESSIBILITY"
const SETTINGS_TAB_GAMEPLAY := "GAMEPLAY"
const SETTINGS_RESET_TAB := "RESET TAB TO DEFAULTS"
const SETTINGS_SENS_TEST := "TEST"
const SETTINGS_LICENSES := "LICENSES"               # 16 §6: reachable from the title's settings
const SETTINGS_REVERT_KEEP := "KEEP"                # window mode / resolution confirm (12 §1); wording is ours
const SETTINGS_REVERT_BACK := "REVERT"
const SETTINGS_REVERT_COUNTDOWN := "REVERTING IN {seconds}"
const SETTINGS_BRIGHTNESS_TEST := "The darkest bar should be barely visible."
const SETTINGS_AA_FSR_ACTIVE := "FSR 2"             # the AA row shows this while FSR 2 is active

## Shared value labels for enum options.
const SETTINGS_VALUES: Dictionary = {
	&"off": "OFF", &"on": "ON", &"adaptive": "ADAPTIVE", &"default": "DEFAULT", &"native": "NATIVE",
	&"unlimited": "UNLIMITED",
	&"fullscreen": "FULLSCREEN", &"exclusive_fullscreen": "EXCLUSIVE FULLSCREEN", &"windowed": "WINDOWED",
	&"bilinear": "BILINEAR", &"fsr2": "FSR 2",
	&"fxaa": "FXAA", &"taa": "TAA", &"msaa2x": "MSAA 2X", &"msaa4x": "MSAA 4X",
	&"low": "LOW", &"medium": "MEDIUM", &"high": "HIGH", &"custom": "CUSTOM", &"full": "FULL",
	&"dot": "DOT", &"dot_ring": "DOT AND RING", &"minimal": "MINIMAL",
	&"hold": "HOLD", &"toggle": "TOGGLE",
}
const SETTINGS_SHADOW_VALUES: Dictionary = {
	&"off": "OFF", &"low": "LOW (2048, 0 SHADOWED FIXTURES)", &"medium": "MEDIUM (4096, 2)", &"high": "HIGH (8192, 4)",
}
const SETTINGS_HUD_VALUES: Dictionary = {
	&"full": "FULL", &"minimal": "MINIMAL (COHERENCE, PROMPTS, CAPTIONS)", &"off": "OFF (COHERENCE BAR ONLY)",
}

## Option labels and one-line descriptions, per tab (12 §2 to §7). Keys are the settings keys.
const SETTING_LABELS: Dictionary = {
	# DISPLAY
	&"window_mode": "WINDOW MODE", &"resolution": "RESOLUTION", &"vsync": "VSYNC", &"max_fps": "MAX FPS",
	&"render_scale": "RENDER SCALE", &"upscaling": "UPSCALING", &"ui_scale": "UI SCALE",
	&"brightness": "BRIGHTNESS", &"fov": "FIELD OF VIEW", &"head_bob": "HEAD BOB", &"screen_shake": "SCREEN SHAKE",
	# GRAPHICS
	&"preset": "PRESET", &"anti_aliasing": "ANTI-ALIASING", &"shadow_quality": "SHADOW QUALITY",
	&"ambient_occlusion": "AMBIENT OCCLUSION", &"indirect_lighting": "INDIRECT LIGHTING",
	&"volumetric_fog": "VOLUMETRIC FOG", &"glow": "GLOW", &"particles": "PARTICLES",
	&"light_pool_size": "LIGHT POOL SIZE", &"texture_detail": "TEXTURE DETAIL",
	# AUDIO
	&"audio_master": "MASTER", &"audio_effects": "EFFECTS", &"audio_ambience": "AMBIENCE",
	&"audio_music": "MUSIC", &"audio_ui": "UI", &"audio_output_device": "OUTPUT DEVICE",
	&"mute_unfocused": "MUTE WHEN UNFOCUSED",
	# CONTROLS
	&"mouse_sensitivity": "MOUSE SENSITIVITY", &"invert_y": "INVERT Y", &"sprint_mode": "SPRINT",
	&"crouch_mode": "CROUCH", &"raw_mouse": "RAW MOUSE INPUT", &"key_bindings": "KEY BINDINGS",
	# ACCESSIBILITY
	&"captions": "SOUND CUE CAPTIONS", &"reduce_visual_noise": "REDUCE VISUAL NOISE",
	&"reduce_flashing": "REDUCE FLASHING", &"flicker_intensity": "FLICKER INTENSITY",
	&"crosshair": "CROSSHAIR", &"hud_mode": "HUD", &"hints": "HINTS", &"text_size": "TEXT SIZE",
	&"hold_to_press": "HOLD-TO-PRESS", &"colorblind_accent": "COLOUR-BLIND SAFE ACCENT",
	# GAMEPLAY
	&"show_depth": "SHOW DEPTH AND STRATUM", &"show_exit_status": "EXIT STATUS LINE",
	&"auto_sprint": "AUTO-SPRINT AFTER STAMINA REFILL", &"debug_overlay": "DEBUG OVERLAY",
}
const SETTING_DESCRIPTIONS: Dictionary = {
	&"window_mode": "Borderless fullscreen, exclusive fullscreen or a window. Changes ask for confirmation.",
	&"resolution": "Used by windowed and exclusive fullscreen only. Changes ask for confirmation.",
	&"vsync": "Matches the frame rate to your display.",
	&"max_fps": "Caps the frame rate from 30 to 360, or leaves it to VSync.",
	&"render_scale": "Below 1.0 the upscaling choice applies; above 1.0 is bilinear supersampling.",
	&"upscaling": "Only active when render scale is below 1.0. FSR 2 replaces anti-aliasing.",
	&"ui_scale": "Scales every menu and HUD element.",
	&"brightness": "Adjusts the overall gamma. Use the test strip.",
	&"fov": "Horizontal field of view at 16:9, from 70 to 110.",
	&"head_bob": "Scales the walking camera motion. Zero turns it off.",
	&"screen_shake": "Scales camera shake from impacts. Zero turns it off.",
	&"preset": "Sets every graphics option below. Editing any of them switches to Custom.",
	&"anti_aliasing": "Smooths edges. Greyed out while FSR 2 is active.",
	&"shadow_quality": "Shadow map size and the number of shadowed fixtures. The flashlight always casts shadows unless Off.",
	&"ambient_occlusion": "Contact shadows under desks, racks and cars.",
	&"indirect_lighting": "Screen-space indirect light. Expensive.",
	&"volumetric_fog": "Off replaces volumetric fog with distance fog.",
	&"glow": "Soft bloom around fixtures.",
	&"particles": "Dust, bubbles and sparks. Low halves the counts.",
	&"light_pool_size": "How many fixtures keep a real light. Shown under Custom only.",
	&"texture_detail": "Resolution of the generated noise textures.",
	&"audio_master": "Overall volume.",
	&"audio_effects": "World and player sounds.",
	&"audio_ambience": "Room tones, fixtures, fans and water.",
	&"audio_music": "The drone.",
	&"audio_ui": "Menu sounds.",
	&"audio_output_device": "The device the game plays through.",
	&"mute_unfocused": "Silences the game when its window loses focus.",
	&"mouse_sensitivity": "From 0.10 to 3.00. Type a number or drag the slider.",
	&"invert_y": "Inverts vertical mouse look.",
	&"sprint_mode": "Hold the key, or press once to toggle.",
	&"crouch_mode": "Hold the key, or press once to toggle.",
	&"raw_mouse": "Reads the mouse without operating system acceleration.",
	&"key_bindings": "Enter to rebind, Esc to cancel, Backspace to clear.",
	&"captions": "Prints text for sounds that matter, with a direction and a distance.",
	&"reduce_visual_noise": "Caps grain, chromatic aberration and scanline shimmer. Desaturation and vignette stay.",
	&"reduce_flashing": "Replaces two-frame white flashes with a soft fade, and stops the title's flicker.",
	&"flicker_intensity": "Scales how deep fixture flicker goes. Its tell stays visible at the lowest setting.",
	&"crosshair": "Off, a dot, or a dot with a ring.",
	&"hud_mode": "Full, minimal, or the Coherence bar only.",
	&"hints": "First-run guidance. Turn it back on here after the first Descents.",
	&"text_size": "Scales note and caption text only.",
	&"hold_to_press": "Makes every hold interaction a press. Noclip stays a hold.",
	&"colorblind_accent": "Changes the accent colour, outlines accent elements, and adds a mark to danger and cold.",
	&"show_depth": "Shows the depth and stratum at the top right.",
	&"show_exit_status": "Shows the exit status line beneath the depth.",
	&"auto_sprint": "Resumes sprinting after stamina refills if the key is still held.",
	&"debug_overlay": "Debug builds only.",
}

## Rebinding rows (06 §2 action names to labels).
const ACTION_LABELS: Dictionary = {
	&"move_forward": "MOVE FORWARD", &"move_back": "MOVE BACK", &"move_left": "MOVE LEFT", &"move_right": "MOVE RIGHT",
	&"sprint": "SPRINT", &"crouch": "CROUCH", &"interact": "INTERACT", &"flashlight": "FLASHLIGHT",
	&"crank": "CRANK", &"noclip": "NOCLIP", &"use_item": "USE ITEM",
	&"item_1": "ITEM 1", &"item_2": "ITEM 2", &"item_3": "ITEM 3", &"item_4": "ITEM 4",
	&"item_next": "NEXT ITEM", &"item_prev": "PREVIOUS ITEM", &"status": "STATUS", &"pause": "PAUSE",
}
const CONTROLS_COLUMN_PRIMARY := "PRIMARY"
const CONTROLS_COLUMN_SECONDARY := "SECONDARY"
const CONTROLS_REBIND_PROMPT := "PRESS A KEY"
const CONTROLS_HELP := "ENTER REBIND · ESC CANCEL · BACKSPACE CLEAR"


# =====================================================================================
# 01 §8, 16 §6  Ending and credits
# =====================================================================================
const ENDING_DEPTH := "DEPTH 0"
const ENDING_TITLE_CARD := "NOCLIP"
const CREDITS_AI := "NOCLIP was designed and built by an AI (Claude, Anthropic) using the Godot Engine."
const CREDITS_GODOT := "Godot Engine. MIT license."
const CREDITS_FONT := "Typeface bundled under the SIL Open Font License 1.1."
const CREDITS_THANKS := "Thank you for looking."
const CREDITS_LINES: Array[String] = [CREDITS_AI, CREDITS_GODOT, CREDITS_FONT, CREDITS_THANKS]
