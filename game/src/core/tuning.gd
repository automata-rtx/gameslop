class_name Tuning
extends RefCounted
## Every gameplay and presentation number in the design documents (M0.3).
## Constants only: no logic, no state. Sections are named for the document and section
## they mirror; if a number changes, change the document in the same commit (00 §8 rule 2).
## Naming: SYSTEM_THING; units in a trailing comment (s, ms, m, m/s, deg, Hz, dB, px).
## Speeds are *_SPEED (m/s); durations are *_TIME (s) or *_MS; distances are *_RADIUS,
## *_RANGE or *_DIST (m) unless the comment says cells.
## Where two documents disagree, the lower-numbered one is used; see docs/design/CHANGELOG.md.
## "LOW"/"HIGH" on aggression-scaled pairs mean the value at aggression 0.25 / 0.75 (08 §8).


# =====================================================================================
# 00 / 05 §2, 05 §8  Seeds, modes and run structure
# =====================================================================================
const SEED_DERIVE_FORMAT := "%d:%s"                 # Seeds.derive(base, label) = hash(SEED_DERIVE_FORMAT % [base, label])
const SEED_LABEL_DEPTH := "depth:%d"                # level seed label (05 §2)
const SEED_LABEL_LAYOUT := "layout"                 # 07 §1 sub-seeds
const SEED_LABEL_PLACEMENT := "placement"
const SEED_LABEL_PROPS := "props"
const SEED_LABEL_FIXTURES := "fixtures"
const SEED_LABEL_ERROR := "error:%s:%d"             # per-error rng: Seeds.derive(level_seed, label % [id, index]) (M1.7)
const SEED_LABEL_STRATA := "strata"                 # 05 §2 strata order of a run
const SEED_LABEL_DROP := "drop"                     # 05 §4 drop arrival cell (per level seed)
const SEED_LABEL_LANDING := "landing"               # 05 §4 Landing item choice (per depth)
const SEED_LABEL_ITEMS := "items"                   # ItemSpawner photos and note draws (per level seed)
const SEED_DAILY_PREFIX := "NOCLIP:"                # run_seed = hash(prefix + "YYYYMMDD" UTC) (05 §8, 13 §4)
const SEED_DAILY_DATE_FORMAT := "YYYYMMDD"

const RUN_FINAL_DEPTH := 6                          # the Threshold is here (Descent ends)
const RUN_CYCLE_LENGTH := 6                         # depths per Cycle
const RUN_ARRIVE_PROPER := &"proper"                # 14 §4 level_entered arrival values
const RUN_ARRIVE_DROP := &"drop"
const RUN_ARRIVE_START := &"start"

const MODE_DESCENT := &"descent"
const MODE_DAILY := &"daily"
const MODE_ENDLESS := &"endless"
const MODE_DAILY_LOADOUT := &"faller"               # Daily Descent always uses Faller (05 §7)

const STRATUM_HALLS := &"halls"
const STRATUM_POOLS := &"pools"
const STRATUM_GARAGE := &"garage"
const STRATUM_OFFICES := &"offices"
const STRATUM_SERVER := &"server"
const STRATUM_SUBSTRATE := &"substrate"
const STRATA_ALL: Array[StringName] = [&"halls", &"pools", &"garage", &"offices", &"server", &"substrate"]
const STRATUM_DEPTH1 := &"halls"                    # depth 1 is always Halls
const STRATUM_DEPTH6 := &"substrate"                # depth 6 is always Substrate
const STRATUM_DEPTH2_CHOICES: Array[StringName] = [&"pools", &"garage"]                      # coin flip by seed
const STRATUM_DEPTH3_CHOICES: Array[StringName] = [&"pools", &"garage", &"offices"]          # not the depth 2 stratum; Server never
const STRATUM_DEPTH4_CHOICES: Array[StringName] = [&"pools", &"garage", &"offices", &"server"]  # remaining; depth 5 is the last one left
const STRATUM_SERVER_MIN_DEPTH := 4                 # Server never before depth 4 (01 §4)

## 05 §2 level size and time budget, keyed by depth.
const LEVEL_TARGET_TIME: Dictionary = {1: 180.0, 2: 240.0, 3: 300.0, 4: 300.0, 5: 360.0, 6: 240.0}  # s, competent player to exit
const LEVEL_WALKABLE_CELLS: Dictionary = {1: 300, 2: 380, 3: 460, 4: 520, 5: 580, 6: 360}          # 2 m cells (07 §2)
const LEVEL_WALKABLE_TOLERANCE := 0.25              # validation: within +-25% of target (07 §2, §8)
const RUN_TIME_PRESSURE_TARGET_MULT := 2.0          # time pressure starts beyond 2x the level's target time (10 §3)
const RUN_RESTART_MAX_TIME := 3.0                   # s, restart to control (05 §2)

## 05 §3 error roster per depth (initial tuning). Keys: &"static", &"native", &"met_hunter", error ids.
const ROSTER_BY_DEPTH: Dictionary = {
	1: {&"static": 1},                                                          # first Descent ever: Static only, far from critical path
	2: {&"static": 1, &"native": 1},
	3: {&"static": 1, &"native": 1},
	4: {&"static": 1, &"native": 1, &"met_hunter": 1},                          # met_hunter: Still or Echo already met this run
	5: {&"static": 2, &"still": 1, &"echo": 1, &"flicker": 1},                  # Server: all three; other strata: native plus two
	6: {&"null": 1, &"static": 2},
}
const ROSTER_CYCLE2_EXTRA_STATIC := 1               # Cycle 2: +1 Static (05 §3, 07 §9)
## Native hunter per stratum (05 §3). Halls has none; Server's slot is a previously met hunter.
const STRATUM_NATIVE_ERROR: Dictionary = {
	&"pools": &"echo", &"garage": &"still", &"offices": &"flicker", &"substrate": &"null",
}
const AGGRESSION_BASE_BY_DEPTH: Dictionary = {1: 0.25, 2: 0.35, 3: 0.45, 4: 0.55, 5: 0.65, 6: 0.75}
const AGGRESSION_CYCLE2_BONUS := 0.15               # 05 §3, 10 §3 (CYCLE_BONUS)
const AWAKE_ONE_DROP := 0.15                        # aggression bonus after one drop
const AWAKE_TWO_DROPS := 0.25                       # two or more; also the cap (05 §3, 05 §9 rule 7)
const AWAKE_SEARCHING_HUNTERS_ONE := 1              # hunters starting in Search after one drop
const AWAKE_SEARCHING_HUNTERS_TWO := 2
const AWAKE_SEARCH_DIST := 30.0                     # m, last_known_pos for awake hunters (05 §3, 10 §4)
const FIRST_DESCENT_DEPTH1_AGGRESSION := 0.2        # dormant Still/Echo from the second Descent on (05 §10)
const FIRST_DESCENT_NOTE_DIST := 10.0               # m, note H1 within 10 m of spawn (05 §10)
const FIRST_DESCENT_SOFT_WALL_TIME := 60.0          # s of walking, soft wall on the critical path (05 §10, 07 §5.1)

## 05 §4 transitions
const LANDING_TIME := 6.0                           # s, the Landing cabin
const LANDING_CHOICE_COUNT := 2                     # two-item panel
const LANDING_MAX_EXTRA_WAIT := 3.0                 # s, extra hold until the level is ready (07 §3)
const DROP_FALL_TIME := 1.2                         # s of grain and sub thump
const DROP_ARRIVAL_MIN_ERROR_DIST := 15.0           # m from every error (05 §4, 06 §11)
const DROP_ARRIVAL_FADE_MS := 400                   # black and grain to world (11 §3)
const ARRIVAL_MIN_WALL_DIST := 2.0                  # m, never spawn facing a wall closer than this (06 §11)
const LANDING_LACKING_WEIGHT_MULT := 2.0            # 09 §2 "favouring kinds the player holds none of" (09 gives no number)
const LANDING_RIPPLE_AT := 0.5                      # fraction of LANDING_TIME when the unrender ripple crosses (11 §3 "once")

## 05 §5 scoring
const SCORE_PER_DEPTH := 1000
const SCORE_PER_PROPER_EXIT := 300
const SCORE_PER_COHERENCE := 5                      # x coherence_at_end
const SCORE_PER_NOTE := 150
const SCORE_PER_EVASION := 50
const SCORE_TIME_BONUS_BASE := 1800.0               # s; win only: max(0, 1800 - seconds) x rate
const SCORE_TIME_BONUS_RATE := 0.5

## 05 §6 unlock thresholds (milestones, no currency). Ids are proposed in strings.gd/13; order is milestone # 1..14.
const UNLOCK_IDS: Array[StringName] = [
	&"glowstick", &"radio", &"flare", &"fuse", &"cartographer", &"lightbearer", &"diver",
	&"daily", &"endless", &"codex_still", &"codex_echo", &"codex_flicker", &"codex_null", &"note_u6",
]
const UNLOCK_COUNT := 14
const UNLOCK_GLOWSTICK_DEPTH := 2
const UNLOCK_RADIO_DEPTH := 3
const UNLOCK_FLARE_DEPTH := 4
const UNLOCK_FUSE_DEPTH := 5
const UNLOCK_CARTOGRAPHER_NOTES := 5                # find 5 notes
const UNLOCK_LIGHTBEARER_FLICKER_EVASIONS := 3      # in one run
const UNLOCK_DIVER_DEPTH := 4
const UNLOCK_DIVER_TIMES := 2                       # reach depth 4 twice
const UNLOCK_DAILY_DEPTH := 3
const UNLOCK_CODEX_ENCOUNTERS := 3                  # encounter Still/Echo/Flicker/Null 3 times
const UNLOCK_NOTE_U6_NOTES := 35                    # find all 35 other notes
const NOTES_TOTAL := 36
const FUSE_VARIANT_B_CHANCE := 0.5                  # of Powered exits once Fuse is unlocked (07 §6)

## 05 §7 loadouts. items: {kind: count}; chalk count = uses.
const LOADOUTS: Dictionary = {
	&"faller": {&"coherence": 100, &"start_depth": 1, &"items": {&"polaroid": 1, &"chalk": 8}, &"crank_mult": 1.0, &"flicker_attract_mult": 1.0},
	&"cartographer": {&"coherence": 90, &"start_depth": 1, &"items": {&"chalk": 20, &"radio": 1}, &"crank_mult": 1.0, &"flicker_attract_mult": 1.0},
	&"lightbearer": {&"coherence": 100, &"start_depth": 1, &"items": {&"glowstick": 3, &"flare": 1}, &"crank_mult": 1.5, &"flicker_attract_mult": 1.5},
	&"diver": {&"coherence": 70, &"start_depth": 3, &"items": {&"polaroid": 2}, &"crank_mult": 1.0, &"flicker_attract_mult": 1.0},
}
const LOADOUT_DEFAULT := &"faller"


# =====================================================================================
# 06 §3  Body and movement
# =====================================================================================
const PLAYER_CAPSULE_RADIUS := 0.35                 # m
const PLAYER_CAPSULE_HEIGHT := 1.8                  # m
const PLAYER_CAPSULE_HEIGHT_CROUCH := 1.1           # m
const PLAYER_CAMERA_HEIGHT := 1.65                  # m
const PLAYER_CAMERA_HEIGHT_CROUCH := 0.95           # m
const PLAYER_WALK_SPEED := 3.2                      # m/s
const PLAYER_SPRINT_SPEED := 5.6                    # m/s
const PLAYER_CROUCH_SPEED := 1.6                    # m/s (also the cap while cranking or charging noclip)
const PLAYER_WADE_SPEED_MULT := 0.6                 # water deeper than PLAYER_WADE_DEPTH
const PLAYER_WADE_NOISE_MULT := 1.6
const PLAYER_WADE_DEPTH := 0.3                      # m
const PLAYER_ACCEL := 12.0                          # m/s^2 grounded
const PLAYER_DECEL := 16.0                          # m/s^2 grounded
const PLAYER_STEP_HEIGHT := 0.3                     # m (floor_snap_length 0.3)
const PLAYER_FLOOR_MAX_ANGLE := 46.0                # deg
const PLAYER_GRAVITY := 9.8                         # m/s^2
const PLAYER_CROUCH_TRANSITION_MS := 120
const PLAYER_PITCH_LIMIT := 89.0                    # deg, +-
const PLAYER_MOUSE_SENS_MIN := 0.1
const PLAYER_MOUSE_SENS_MAX := 3.0
const PLAYER_MOUSE_SENS_DEFAULT := 1.0
const PLAYER_MOUSE_RAD_PER_PIXEL := 0.0022          # rad per pixel at sensitivity 1.0

# 06 §4  Stamina
const STAMINA_MAX := 100.0
const STAMINA_SPRINT_DRAIN := 20.0                  # per s
const STAMINA_REGEN := 25.0                         # per s
const STAMINA_REGEN_DELAY := 1.0                    # s after sprint released
const STAMINA_LOCKOUT_TIME := 2.0                   # s at 0 (regen continues)
const STAMINA_WADE_DRAIN_MULT := 1.5

# 06 §5  Flashlight and crank
const FLASH_CHARGE_MAX := 100.0
const FLASH_DRAIN := 1.6                            # charge per s while on (about 62 s)
const FLASH_ENERGY_MIN := 0.5                       # at empty charge (never dark; T1)
const FLASH_ENERGY_MAX := 1.6                       # lerp(0.5, 1.6, charge/100); same as 02 §6
const FLASH_CONE_FULL_DEG := 38.0                   # full cone at charge >= 30 (Godot spot_angle is the half: 19)
const FLASH_CONE_TIRED_FULL_DEG := 30.0             # full cone as charge falls below 30
const FLASH_TIRED_BELOW := 30.0                     # charge threshold of the "tired" beam
const FLASH_SPOT_ANGLE := 19.0                      # deg, SpotLight3D.spot_angle (02 §6)
const FLASH_RANGE := 22.0                           # m (02 §6)
const FLASH_ATTENUATION_ANGLE := 1.2                # spot_angle_attenuation (02 §6)
const FLASH_HAND_LIGHT_RANGE := 1.5                 # m, secondary omni at the hand (02 §6)
const FLASH_HAND_LIGHT_ENERGY := 0.15
const CRANK_RATE := 25.0                            # charge per s
const CRANK_RATE_LIGHTBEARER_MULT := 1.5
const CRANK_NOISE_RADIUS := 12.0                    # m, emitted every CRANK_NOISE_INTERVAL
const CRANK_NOISE_INTERVAL := 0.5                   # s
const CRANK_GAUGE_DANGER_BELOW := 15.0              # percent (04 §6)

# 06 §6  Noise model (radii in m; kind in parentheses)
const NOISE_KIND_STEP := &"step"
const NOISE_KIND_MECH := &"mech"
const NOISE_KIND_TEAR := &"tear"
const NOISE_KIND_DOOR := &"door"
const NOISE_KIND_IMPACT := &"impact"
const NOISE_KIND_LIGHT := &"light"
const NOISE_STEP_RADIUS: Dictionary = {&"carpet": 5.0, &"tile": 7.0, &"concrete": 7.0, &"raised_floor": 8.0, &"substrate": 6.0}
const NOISE_STEP_WATER_RADIUS := 10.0
const NOISE_SPRINT_MULT := 1.8                      # x walk radius
const NOISE_CROUCH_MULT := 0.4                      # x walk radius
const NOISE_CRANK_RADIUS := 12.0                    # per 0.5 s (mech)
const NOISE_NOCLIP_COMMIT_RADIUS := 20.0            # tear
const NOISE_FLASHLIGHT_TOGGLE_RADIUS := 2.0         # mech
const NOISE_DOOR_OPEN_RADIUS := 8.0
const NOISE_DOOR_CLOSE_RADIUS := 8.0
const NOISE_DOOR_SLAM_RADIUS := 18.0
const NOISE_ITEM_DROP_RADIUS := 6.0                 # impact: glowstick, flare landing
const NOISE_FLARE_BURNING_RADIUS := 14.0            # light, per 1 s
const NOISE_RADIO_RADIUS := 10.0                    # mech, per 1 s
const NOISE_BREAKER_RADIUS := 25.0                  # mech
const NOISE_CONTACT_RADIUS := 15.0                  # tear
const NOISE_VENDING_RADIUS := 8.0                   # mech (09 §5)
const NOISE_PAYPHONE_RADIUS := 18.0                 # door-class (09 §5, 10 §5)
const NOISE_WALL_ATTENUATION := 0.35                # effective radius reduced 35% per wall in the straight line
const NOISE_WALL_RAYCASTS := 3                      # up to 3 raycasts
const STEP_DISTANCE_WALK := 0.55                    # m walked per step
const STEP_DISTANCE_SPRINT := 0.45
const STEP_DISTANCE_CROUCH := 0.7

# 06 §7  Interaction
const INTERACT_RANGE := 2.2                         # m, camera ray on the interactable layer
const INTERACT_HOLD_TIME := 0.6                     # s, hold prompts (breaker, leave hiding)

# 06 §8  Noclip
const NOCLIP_RANGE := 2.5                           # m, targeting ray
const NOCLIP_WALL_NORMAL_MAX_DEG := 30.0            # surface normal within 30 deg of horizontal
const NOCLIP_FLOOR_NORMAL_MAX_DEG := 20.0           # within 20 deg of up
const NOCLIP_FREE_SPACE_MIN := 0.3                  # m beyond the surface, free-space search band
const NOCLIP_FREE_SPACE_MAX := 2.0
const NOCLIP_SOFT_TIME := 0.35                      # s charge
const NOCLIP_WALL_TIME := 0.6
const NOCLIP_FLOOR_TIME := 2.5
const NOCLIP_SOFT_COST := 5.0                       # Coherence
const NOCLIP_WALL_COST := 10.0
const NOCLIP_FLOOR_COST := 30.0
const NOCLIP_COMMIT_HITSTOP_MS := 80
const NOCLIP_PASS_TIME_MS := 250                    # camera passes through the wall
const NOCLIP_FLOOR_FALL_TIME := 1.2                 # s into black with grain (= DROP_FALL_TIME)
const NOCLIP_COOLDOWN := 1.0                        # s before another charge
const NOCLIP_FOV_PULL_DEG := 6.0                    # slow pull-in during charge (11: -6 over the charge)
const NOCLIP_FOV_PUNCH_DEG := 8.0                   # on commit
const NOCLIP_FOV_PUNCH_RETURN_MS := 300
const NOCLIP_UNRENDER_RADIUS_COMMIT := 3.0          # m, geometry within 3 m is lines during the pass (02 §5)
const NOCLIP_REASON_SOLID := &"SOLID"
const NOCLIP_REASON_NO_SPACE := &"NO SPACE"
const NOCLIP_REASON_TOO_FAR := &"TOO FAR"
const NOCLIP_REASON_TOO_THIN := &"TOO THIN"         # coherence <= cost: a noclip can never kill (06 §8)
const NOCLIP_DIRECTOR_RELIEF_DROP := 0.20           # intensity drop for a pass that broke line of sight (10 §2)
const NOCLIP_DIRECTOR_RELIEF_TIME := 15.0           # s the Director stays lowered (06 §8)
# Noclip task constants (M1.4; 06 gives no number, CHANGELOG):
const NOCLIP_PROBE_RANGE := 30.0                    # m: the aim names targets beyond 2.5 m so TOO FAR can show
const NOCLIP_LANDING_STEP := 0.05                   # m between capsule probes across the free-space band
const NOCLIP_LANDING_LIFT := 0.02                   # m the landing capsule sits above the floor
const NOCLIP_FLOOR_PROBE := 1.0                     # m above and below the body the landing floor is looked for
const NOCLIP_INVALID_PREVIEW := 0.15                # g_noclip_charge shown while invalid, so the dashed preview reads (11 §2)
# Noclip review task constants (R6; 06 gives no number, CHANGELOG):
const NOCLIP_PLANE_TOLERANCE := 0.05                # m: two wall hits on one plane are one target (charge keeps across seams)
const NOCLIP_PLANE_NORMAL_DOT := 0.99               # normals at least this aligned are one plane
const NOCLIP_LANDING_COARSE_STEP := 0.25            # m between coarse landing probes before the 5 cm fine pass
const NOCLIP_LANDING_CACHE_QUANT := 0.05            # m pose quantum of the landing cache
const NOCLIP_LANDING_CACHE_FRAMES := 6              # physics frames a cached landing stays good
const NOCLIP_FALL_CLAMP_BELOW := 2.0                # m below the floor the drop's fall stops (06 §8: into black, not out of the world)

# 06 §9  Coherence
const COHERENCE_MAX := 100.0
const COHERENCE_GAIN_PROPER_EXIT := 20.0
const COHERENCE_GAIN_POLAROID := 25.0
const COHERENCE_ENDING_RESTORE_TO := 100.0
const COHERENCE_ENDING_RESTORE_TIME := 6.0          # s (01 §8)
const COHERENCE_LOSS_STATIC_PER_S := 4.0            # at the field centre, scaled by falloff
const COHERENCE_LOSS_NULL_PER_S := 12.0             # inside the 2 m core
const COHERENCE_LOSS_CYCLE2_SUBSTRATE_PER_S := 0.2  # ambient drain, Substrate only, Cycle 2
const COHERENCE_CONTACT_STILL := 35.0
const COHERENCE_CONTACT_ECHO := 25.0
const COHERENCE_CONTACT_FLICKER := 30.0
const COHERENCE_MAX_SINGLE_HIT := 35.0              # 05 §9 rule 5
const COHERENCE_DANGER_BELOW := 25.0                # HUD danger state, near-monochrome
const COHERENCE_HEARTBEAT_FLOOR_BPM := 90.0         # below the danger threshold
const COHERENCE_DISSOLVE_TIME := 1.5                # s
const COHERENCE_LOW_INTENSITY_BELOW := 30.0         # Director +0.10 once when crossing (10 §2)
const COHERENCE_HINT_BELOW := 50.0                  # hint 7 (04 §9)
const COHERENCE_TICK_RATE := 30.0                   # HUD numeral ticks at 30 units per s (04 §6, 11 §3)
const COHERENCE_BAR_WIDTH := 240.0                  # px (04 §6)

# 06 §9  Contact rules
const CONTACT_STUN_TIME := 1.2                      # s: no sprint, no noclip, crouch speed
const CONTACT_TRAUMA := 0.6                         # camera trauma
const CONTACT_PUSH_DIST := 1.5                      # m away from the error
const CONTACT_SATIATED_TIME := 20.0                 # s
const CONTACT_EXCLUSIVITY_TIME := 3.0               # s between any two contacts
const CONTACT_HITSTOP_MS := 60                      # 11 §4
const CONTACT_RADIUS_FRAMES := 2                    # consecutive physics frames within contact radius (08 §2)

# 06 §10  Hiding
const HIDE_LEAVE_HOLD_TIME := 0.6                   # s
const HIDE_YAW_LIMIT_DEFAULT := 35.0                # deg, +-
const HIDE_ENTER_MIN_ERROR_DIST := 3.0              # m, no error within 3 m (09 §6)
const HIDE_HUD_DIM := 0.4                           # HUD alpha while hidden (04 §6)
const HIDE_CAMERA_SLIDE_TIME := 0.6                 # s (11 §2)

# 06 §12 / 06 §2  Input actions (canonical names)
const INPUT_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"crouch", &"interact",
	&"flashlight", &"crank", &"noclip", &"use_item", &"item_1", &"item_2", &"item_3", &"item_4",
	&"item_next", &"item_prev", &"status", &"pause",
]
const INPUT_HOLD_TOGGLE_ACTIONS: Array[StringName] = [&"sprint", &"crouch"]   # Hold by default; toggle option (12 §5)


# =====================================================================================
# 08 §2  Shared error architecture
# =====================================================================================
const ERROR_IDS: Array[StringName] = [&"static", &"still", &"flicker", &"echo", &"null"]
const ERROR_EYE_HEIGHT := 1.6                       # m, sight ray origin
const ERROR_REACTION_WINDOW_LOW := 1.5              # s at aggression 0.25 (08 §2, §8)
const ERROR_REACTION_WINDOW_HIGH := 0.8             # s at aggression 0.75
const ERROR_SUSPICION_STEP := 0.6                   # per heard step noise
const ERROR_SUSPICION_LOUD := 1.0                   # per tear/door/mech noise in range
const ERROR_SUSPICION_SEEN_PER_S := 0.67
const ERROR_SUSPICION_DECAY_PER_S := 0.5
const ERROR_SUSPICION_CHASE_AT := 1.0
const ERROR_SEARCH_INSPECT_CELLS := 3               # nearby cells inspected
const ERROR_SEARCH_INSPECT_RADIUS := 6.0            # m
const ERROR_SEARCH_TIME := 10.0                     # s before giving up to Wander (an evasion)
const ERROR_NAV_REPATH_INTERVAL := 0.3              # s, at most
const ERROR_NAV_CLOSED_DOOR_COST := 3.0             # s of path time in the Director's model
const ERROR_SATIATED_TIME := 20.0                   # s retreat; also the chase lockout
const ERROR_SATIATED_RETREAT_DIST := 20.0           # m, hinted retreat point
const ERROR_FAR_DIST := 50.0                        # m: senses evaluated every ERROR_FAR_SENSE_INTERVAL
const ERROR_FAR_SENSE_INTERVAL := 0.5               # s
const ERROR_DORMANT_TICK := 1.0                     # s, Dormant timer
const ERROR_SPAWN_MIN_DIST := 20.0                  # m from the player (also: not inside the frustum)
const ERROR_STATE_DORMANT := &"dormant"
const ERROR_STATE_WANDER := &"wander"
const ERROR_STATE_SEARCH := &"search"
const ERROR_STATE_CHASE := &"chase"
const ERROR_STATE_SATIATED := &"satiated"
# Per-error extra states (08 §5, §6). Still, Static and Null have none beyond the common five
# (Null's calm window is Dormant; it then Chases).
const ERROR_STATE_FOLLOW := &"follow"                # Echo: its Chase
const ERROR_STATE_RESIDENT := &"resident"            # Flicker
const ERROR_STATE_STALK := &"stalk"
const ERROR_STATE_LUNGE := &"lunge"
const ERROR_STATE_ATTACHED := &"attached"
const ERROR_PROXIMITY_HZ := 10.0                    # error_proximity emission rate
const ERROR_PROXIMITY_INTERVAL := 0.1               # s
# Build-task constants (M1.7; 08 gives no number): how errors walk.
const ERROR_ARRIVE_DIST := 0.6                      # m (XZ): a nav target counts as reached
const ERROR_WAYPOINT_DIST := 0.3                    # m (R7, 3D: the path runs 0.2 m above the floor): a path corner counts as passed (0.6 cut corners into jambs and wall ends)
const ERROR_DOOR_OPEN_DIST := 1.6                   # m (XZ): a closed door this near on the path is opened
const ERROR_RETREAT_SAMPLES := 12                   # candidate points tried for an unhinted retreat
const ERROR_CONTACT_MAX_DY := 2.0                   # m: contact also needs the bodies on one floor
const ERROR_LOG_LINES := 8                          # transitions kept per error for the debug overlay

# 08 §8  Aggression mapping: linear between the columns, clamped outside [0.25, 0.75]
const AGGR_MIN := 0.25
const AGGR_MAX := 0.75
const STILL_SPEED_MULT_LOW := 0.9
const STILL_SPEED_MULT_HIGH := 1.15
const STILL_HIDE_CHECK_CHANCE_LOW := 0.30
const STILL_HIDE_CHECK_CHANCE_HIGH := 0.60
const ECHO_HEARING_MULT_LOW := 1.0
const ECHO_HEARING_MULT_HIGH := 1.4
const ECHO_TRAIL_LOSS_TIME_LOW := 6.0               # s
const ECHO_TRAIL_LOSS_TIME_HIGH := 4.0              # s
const FLICKER_HOP_MULT_LOW := 1.2                   # hop interval multiplier
const FLICKER_HOP_MULT_HIGH := 0.7
const FLICKER_LUNGE_CHARGE_MULT_LOW := 1.3
const FLICKER_LUNGE_CHARGE_MULT_HIGH := 0.8
const STATIC_DRIFT_SPEED_LOW := 0.6                 # m/s
const STATIC_DRIFT_SPEED_HIGH := 0.9
const STATIC_SEARCH_SPEED_LOW := 0.9                # m/s (08 §3: 0.9 to 1.2 by aggression)
const STATIC_SEARCH_SPEED_HIGH := 1.2
const NULL_SPEED_CYCLE1 := 2.4                      # m/s; Null ignores aggression
const NULL_SPEED_CYCLE2 := 2.8

# 08 §3  Static
const STATIC_RADIUS_MIN := 3.0                      # m, by seed
const STATIC_RADIUS_MAX := 5.0
const STATIC_WANDER_CELLS := 10                     # pick a walkable cell within 10 cells
const STATIC_WANDER_SPEED := STATIC_DRIFT_SPEED_LOW  # m/s (0.6)
const STATIC_DWELL_MIN := 5.0                       # s
const STATIC_DWELL_MAX := 15.0
const STATIC_SEARCH_STEPS_HEARD := 3                # step noises ...
const STATIC_SEARCH_STEPS_WINDOW := 10.0            # ... within 10 s (or any tear)
const STATIC_SEARCH_DWELL := 20.0                   # s
const STATIC_DRAIN_PER_S := 4.0                     # Coherence at the centre
const STATIC_FIELD_FULL_FRACTION := 0.6             # full drain in the inner 60% (smoothstep(r, r*0.6, d))
const STATIC_FLARE_RANGE := 6.0                     # m, flare pushes it away
const STATIC_FLARE_PUSH_SPEED := 1.2                # m/s
const STATIC_FAIR_CHECK_INTERVAL := 5.0             # s, critical-path cut test
const STATIC_FAIR_CUMULATIVE_LIMIT := 40.0          # s before it is hinted off (05 §9 rule 6)
const STATIC_FAIR_NUDGE_SPEED := 1.2                # m/s
const STATIC_SPAWN_MIN_FROM_SPAWN_ROOM := 20.0      # m
const STATIC_MIN_EVADE_TIME := 2.0                  # s inside before release counts as an evasion
const STATIC_NOTICE_REARM_TIME := 5.0              # s outside the field before a new entry is a new notice (08 §2, 2026-10-08)
const STATIC_FORCED_DRAIN := 0.6                    # renderer drain floor inside the field (08 §3)
const STATIC_FORCED_BED := 0.6                      # static bed inside the field
const STATIC_VISIBLE_DIST := 15.0                   # m, distortion visible at (08 §1)
const STATIC_CENTRE_HEIGHT := 1.5                   # m above the floor (M1.7: the field is centred at chest height)
const STATIC_BAND_OUTSIDE_DB := -24.0               # static_band loop gain outside the field (03 "rises inside")
const STATIC_BAND_INSIDE_DB := 0.0                  # ... at full field strength
const STATIC_FLARE_GROUP := &"flares_burning"       # burning flares join this group (M1.7 contract for 09)

# 08 §4  Still
const STILL_CAPSULE_RADIUS := 0.5                   # m (reading: "0.5 x 2.6" = radius x height, as Echo/player)
const STILL_CAPSULE_HEIGHT := 2.6                   # m
const STILL_COLUMN_DOORWAY_HEIGHT := 2.05          # m (LEVELBUILD_DOOR_HEIGHT - 0.05), drawn column top while it overlaps a door header strip (R9, presentation only)
const STILL_BODY_RADIUS := NAV_AGENT_RADIUS         # m, collision only (R7): the 0.5 m column must pass a 1.0 m doorway
const STILL_BODY_HEIGHT := NAV_AGENT_HEIGHT         # m, collision only (R7): ... and its 2.1 m header (the column draws 2.6 m)
const STILL_WANDER_SPEED := 1.8                     # m/s
const STILL_SEARCH_SPEED := 3.6
const STILL_CHASE_SPEED := 5.0
const STILL_CHASE_SPEED_CAP := 5.4                  # sprint (5.6) must stay an escape
const STILL_OBSERVE_MAX_DIST := 30.0                # m (also Player.is_observing, 06 Interfaces)
const STILL_OBSERVE_BEAM_ANGLE := 25.0              # deg of the beam axis
const STILL_OBSERVE_GLOWSTICK_DIST := 4.0           # m
const STILL_OBSERVE_FLARE_DIST := 8.0               # m
const STILL_SKIP_UNOBSERVED_TIME := 4.0             # s unobserved in Chase ...
const STILL_SKIP_MIN_DIST := 12.0                   # m ... and farther than this
const STILL_SKIP_INTERVAL := 8.0                    # s, once per
const STILL_SKIP_STEP := 6.0                        # m closer along its path
const STILL_SIGHT_RANGE := 25.0                     # m
const STILL_HEARING_MULT := 1.0
const STILL_HIDE_SEARCH_RADIUS := 6.0               # m, hide spots checked by Search
const STILL_NOCLIP_LOS_BREAK_TIME := 2.0            # s without line of sight -> Search
const STILL_CONTACT_RADIUS := 1.0                   # m
const STILL_CONTACT_COST := COHERENCE_CONTACT_STILL
const STILL_RENDER_TICK_AFTER := 2.0                # s observed continuously
const STILL_RENDER_TICK_DURATION_MS := 100
const STILL_RENDER_TICK_INTERVAL := 2.0             # s, once per
const STILL_RENDER_TICK_BLIP_HZ := 6000.0           # Hz blip (03)
const STILL_RENDER_TICK_BLIP_MS := 10
const STILL_SILENCE_RANGE := 8.0                    # m: ambience -6 dB
const STILL_SILENCE_DB := -6.0
const STILL_WANDER_RADIUS := 14.0                   # m: an unhinted Wander leg ends within this (M1.7)
const STILL_EYE_POINT_TOP := 0.2                    # m below the column top: the upper observe point (M1.7)

# 08 §5  Flicker
const FLICKER_HOP_MIN := 6.0                        # s, x hop multiplier
const FLICKER_HOP_MAX := 12.0
const FLICKER_HOP_NEAR_CHANCE_BASE := 0.4           # 0.4 + 0.4 x aggression (nearest group to last_known_pos)
const FLICKER_HOP_NEAR_CHANCE_PER_AGGR := 0.4
const FLICKER_HEARING_MULT := 0.8
const FLICKER_GROUP_ADJACENT_DIST := 8.0            # m, any fixture pair (or sharing a door)
const FLICKER_LIT_AREA_DIST := 3.0                  # m XZ of any lit fixture of the group
const FLICKER_LIT_AREA_CELL_DIST := 4.0             # m XZ, cell whose nearest lit fixture belongs to the group
const FLICKER_CHARGE_TIME := 2.0                    # s, x lunge charge multiplier
const FLICKER_CHARGE_DRAIN := 2.0                   # per s when leaving the lit area
const FLICKER_STUTTER_MIN_HZ := 8.0
const FLICKER_STUTTER_MAX_HZ := 20.0
const FLICKER_LUNGE_FLASH_FRAMES := 2
const FLICKER_LUNGE_RANGE := 6.0                    # m from a fixture of the group
const FLICKER_LUNGE_COST := COHERENCE_CONTACT_FLICKER
const FLICKER_DARK_TIME := 1.5                      # s, group dark after a lunge
const FLICKER_ATTACH_DIST := 4.0                    # m, flashlight on near a fixture of its group
const FLICKER_ATTACH_DIST_LIGHTBEARER := 6.0        # m
const FLICKER_ATTACH_TIME := 1.5                    # s continuous
const FLICKER_SHED_DIST := 10.0                     # m, nearest habitable group on shed
const FLICKER_RESPAWN_INTERVAL := 60.0              # s, Director respawn at most once per (10 §4)
const FLICKER_RESPAWN_MIN_DIST := 20.0              # m, lit group
const FLICKER_HABITAT_LOST_DIST := 10.0             # m: no lit group within 10 m -> respawn
const FLICKER_SPARK_SIZE := 0.01                    # m (1 cm sparks)
const FLICKER_SPARK_LIFETIME := 0.3                 # s

# 08 §6  Echo
const ECHO_CAPSULE_RADIUS := 0.35                   # m
const ECHO_CAPSULE_HEIGHT := 1.8                    # m
const ECHO_TRAIL_DELAY := 0.8                       # s (800 ms), relative to the newest heard entry
const ECHO_TRAIL_DELAY_MS := 800
const ECHO_FOLLOW_STEPS := 3                        # heard steps ...
const ECHO_FOLLOW_STEPS_WINDOW := 5.0               # ... within 5 s -> Follow
const ECHO_SEARCH_TIME := 10.0                      # s
const ECHO_SEARCH_MIN_POINT_DIST := 2.0             # m, never the point itself
const ECHO_SHIMMER_RANGE := 4.0                     # m
const ECHO_CONTACT_RADIUS := 1.0                    # m
const ECHO_CONTACT_COST := COHERENCE_CONTACT_ECHO
const ECHO_STEP_PLAYBACK_DB := -3.0
const ECHO_STEP_EXTRA_REVERB_MS := 20
const ECHO_BREATH_SWELL_INTERVAL := 2.0             # s, within 4 m (03)
const ECHO_LURE_IMPACT_RADIUS := 6.0                # m, thrown glowstick/flare landing
const ECHO_LURE_RADIO_RADIUS := 10.0                # m per s while on
const ECHO_CORNER_GAIN := 0.05                      # about 5% per corner trimmed

# 08 §7  Null
const NULL_UNRENDER_RADIUS := 12.0                  # m
const NULL_UNRENDER_RADIUS_CYCLE2 := 24.0           # m, from depth 12 in Endless
const NULL_CYCLE2_RADIUS_FROM_DEPTH := 12
const NULL_CORE_RADIUS := 2.0                       # m
const NULL_DRAIN_PER_S := 12.0                      # inside the core
const NULL_UNRENDER_ALPHA := 0.85                 # superseded: 08 §7 "alpha 0.85" reads as 02 §5
                                                    # (lines on black, fills screen-door dithered at
                                                    # u >= 0.95); no shader reads this. CHANGELOG R3.
const NULL_SPAWN_PATH_FRACTION := 0.55              # of the critical path (07 §5.6)
const NULL_SPAWN_MIN_DIST := 20.0                   # m from the player
const NULL_DEAD_END_MAX_CELLS := 4                  # validator invariant

# 08 shared: contact cost lookup
const ERROR_CONTACT_COST: Dictionary = {&"still": 35.0, &"echo": 25.0, &"flicker": 30.0}


# =====================================================================================
# 10  The Director
# =====================================================================================
const DIRECTOR_UPDATE_HZ := 10.0                    # intensity update rate (10 §2)
# 10 §2 intensity inputs
const INTENSITY_TIME_PER_S := 0.010                 # after the calm window
const INTENSITY_NOISE_SPRINT_STEP := 0.02
const INTENSITY_NOISE_CRANK := 0.10                 # per 0.5 s
const INTENSITY_NOISE_NOCLIP := 0.20
const INTENSITY_NOISE_BREAKER := 0.25
const INTENSITY_NEAREST_HUNTER_RANGE := 20.0        # m: clamp((20 - d)/20, 0, 1)
const INTENSITY_NEAREST_HUNTER_PER_S := 0.05
const INTENSITY_CHASE_PER_S := 0.15                 # hunter in Chase/Follow/Stalk (cap 1.0)
const INTENSITY_LOW_COHERENCE := 0.10               # once, when crossing below 30
const INTENSITY_EXIT_SEEN := -0.15                  # once
const INTENSITY_EVASION := -0.30
const INTENSITY_CONTACT := -0.40
const INTENSITY_NOTE := -0.10
const INTENSITY_NOCLIP_BROKE_LOS := -0.20
const INTENSITY_DECAY_RELIEF_PER_S := -0.03
const INTENSITY_DECAY_PER_S := -0.01
const INTENSITY_MIN := 0.0
const INTENSITY_MAX := 1.0
# 10 §2 phases
const DIRECTOR_PHASE_CALM := &"calm"
const DIRECTOR_PHASE_BUILD := &"build"
const DIRECTOR_PHASE_PEAK := &"peak"
const DIRECTOR_PHASE_RELIEF := &"relief"
const DIRECTOR_PHASE_PURSUIT := &"pursuit"
const DIRECTOR_CALM_TIME := 30.0                    # s (proper exit arrival)
const DIRECTOR_CALM_TIME_AFTER_DROP := 15.0
const DIRECTOR_CALM_HUNTER_MIN_DIST := 30.0         # m, hunters dormant or wandering far
const DIRECTOR_HINT_INTERVAL := 20.0                # s, re-hint toward the player's region
const DIRECTOR_HINT_RANGE_MIN := 15.0               # m, random walkable cell from the player
const DIRECTOR_HINT_RANGE_MAX := 30.0
const DIRECTOR_WAKE_INTENSITY := 0.8                # wake the nearest dormant hunter ...
const DIRECTOR_WAKE_HINT_DIST := 12.0               # m ... and hint it to 12 m
const DIRECTOR_PEAK_MAX_TIME := 45.0                # s, then retreat(20) the chaser
const DIRECTOR_PEAK_RETREAT_TIME := 20.0            # s
const DIRECTOR_RELIEF_MIN_TIME := 20.0              # s
const DIRECTOR_RELIEF_MAX_TIME := 40.0
const DIRECTOR_RELIEF_AFTER_CONTACT_TIME := 40.0
const DIRECTOR_RELIEF_HINT_AWAY_DIST := 25.0        # m, hunters hinted away
const DIRECTOR_PURSUIT_CALM_TIME := 30.0            # Substrate: calm, then Null wakes (Pursuit)
const DIRECTOR_PURSUIT_STATIC_HINT_INTERVAL := 60.0 # s, Static hinted across the critical path
const DIRECTOR_PURSUIT_INTENSITY_FLOOR := 0.6
# 10 §3 aggression
const DIRECTOR_TIME_PRESSURE_PER_MINUTE := 0.10     # per full minute beyond 2x target time
const DIRECTOR_TIME_PRESSURE_CAP := 0.30
const DIRECTOR_AGGRESSION_UPDATE_INTERVAL := 1.0    # s, at most
# 10 §4 roster and spawning
const DIRECTOR_SPAWN_MIN_WALK_DIST := 20.0          # m walking distance from the player
const DIRECTOR_SPAWN_NATIVE_PATH_MIN := 0.35        # native hunter at 35% to 65% of the critical path
const DIRECTOR_SPAWN_NATIVE_PATH_MAX := 0.65
const DIRECTOR_MAX_CHASERS: Dictionary = {1: 1, 2: 1, 3: 1, 4: 2, 5: 2, 6: 2}   # depth 6: Null plus 1 (Static does not count)
const DIRECTOR_CONTACT_REFUSED_RETREAT := 5.0       # s, retreat(5) for the refused error
# M1.8 build-task constants (10 gives no number)
const DIRECTOR_TICK := 0.1                          # s, one intensity step (1 / DIRECTOR_UPDATE_HZ)
const DIRECTOR_CHASE_STATES: Array[StringName] = [&"chase", &"follow", &"stalk"]   # 10 §2 "in Chase/Follow/Stalk"
const DIRECTOR_PLAYER_NOISE_DIST := 2.0             # m, a noise this close to the player is the player's
const DIRECTOR_CALM_CHECK_INTERVAL := 1.0           # s, Calm keeps awake hunters >= 30 m (hints)
const DIRECTOR_HINT_AWAY_MAX := 40.0                # m, Relief/Calm hint-away cells lie 25 (30) to 40 m out
const DIRECTOR_HINT_DIST_TOLERANCE := 2.0           # m, "a cell 12 m / 30 m from the player" within one cell
const DIRECTOR_NOCLIP_LOS_CHECK_DELAY := 0.5        # s after a wall commit: did the chaser lose sight?
const DIRECTOR_STATIC_OFF_PATH_CLEARANCE := 6.0     # m from every critical-path cell (Static radius max 5)
const DIRECTOR_STATIC_OFF_PATH_SEARCH_CELLS := 15   # walking cells searched for an off-path cell
const DIRECTOR_TELEMETRY_INTERVAL := 1.0            # s per telemetry row (10 §9)
const DIRECTOR_SPAWN_EYE_HEIGHT := 1.3              # m, the point tested against the frustum and sight
const DIRECTOR_SPAWN_FRUSTUM_MARGIN_DEG := 10.0     # widen the horizontal half-FOV (conservative)
const SEED_LABEL_DIRECTOR := "director"             # Director rng (Relief length, hint cells, roster picks)
# 10 §5 scares (Build phase only)
const SCARE_MIN_INTERVAL := 30.0                    # s, at most one scare per 30 s
const SCARE_INTENSITY_NONE_BELOW := 0.2
const SCARE_INTENSITY_ALL_ABOVE := 0.5
const SCARE_DOOR_SLAM_MIN_DIST := 20.0              # m and out of the frustum
const SCARE_DOOR_SLAM_INTERVAL := 60.0
const SCARE_PAYPHONE_DIST_MIN := 15.0               # m
const SCARE_PAYPHONE_DIST_MAX := 40.0
const SCARE_PAYPHONE_RING_TIME := 30.0              # s, rings until answered or 30 s
const SCARE_PAYPHONE_NOISE_INTERVAL := 6.0          # s, 18 m noise
const SCARE_PAYPHONE_INTERVAL := 90.0
const SCARE_STATIC_SWELL_DB := 4.0
const SCARE_STATIC_SWELL_TIME := 3.0                # s
const SCARE_STATIC_SWELL_INTERVAL := 45.0
const SCARE_FIXTURE_DROPOUT_MIN_DIST := 12.0        # m
const SCARE_FIXTURE_DROPOUT_INTERVAL := 40.0
const SCARE_PRE_ECHO_MIN_DIST := 25.0               # m, Echo dormant or wandering
const SCARE_PRE_ECHO_INTERVAL := 50.0
# 10 §6 outputs
const THREAT_RANGE := 15.0                          # m: clamp((15 - d)/15, 0, 1)
const THREAT_CHASE_MULT := 1.0
const THREAT_OTHER_MULT := 0.5
const THREAT_STATIC_BONUS := 0.3                    # inside Static's field
const THREAT_NULL_RADIUS := NULL_UNRENDER_RADIUS   # 1 - d/12 inside Null's radius
const THREAT_SMOOTH_UP_TIME := 0.5                  # s time constant
const THREAT_SMOOTH_DOWN_TIME := 2.0
# 10 §8 doc names (knobs mirrored from the Director document)
const CALM_SECONDS := DIRECTOR_CALM_TIME
const CALM_SECONDS_AFTER_DROP := DIRECTOR_CALM_TIME_AFTER_DROP
const PEAK_MAX_SECONDS := DIRECTOR_PEAK_MAX_TIME
const RELIEF_MIN := DIRECTOR_RELIEF_MIN_TIME
const RELIEF_MAX := DIRECTOR_RELIEF_MAX_TIME
const RELIEF_AFTER_CONTACT := DIRECTOR_RELIEF_AFTER_CONTACT_TIME
const HINT_INTERVAL := DIRECTOR_HINT_INTERVAL
const HINT_RANGE_MIN := DIRECTOR_HINT_RANGE_MIN
const HINT_RANGE_MAX := DIRECTOR_HINT_RANGE_MAX
const WAKE_INTENSITY := DIRECTOR_WAKE_INTENSITY
const TIME_PRESSURE_PER_MINUTE := DIRECTOR_TIME_PRESSURE_PER_MINUTE
const TIME_PRESSURE_CAP := DIRECTOR_TIME_PRESSURE_CAP
const AWAKE_ONE := AWAKE_ONE_DROP
const AWAKE_TWO := AWAKE_TWO_DROPS
const CYCLE_BONUS := AGGRESSION_CYCLE2_BONUS


# =====================================================================================
# 09  Items and interactables
# =====================================================================================
const ITEM_BELT_SLOTS := 4
const ITEM_USE_TIME_MAX := 1.2                      # s, nothing takes longer
const ITEM_KINDS: Array[StringName] = [&"polaroid", &"glowstick", &"flare", &"chalk", &"radio", &"fuse"]
const ITEM_CAP: Dictionary = {&"polaroid": 3, &"glowstick": 4, &"flare": 2, &"chalk": 20, &"radio": 1, &"fuse": 1}
const ITEM_WEIGHT: Dictionary = {&"polaroid": 3, &"glowstick": 3, &"chalk": 2, &"flare": 2, &"radio": 1, &"fuse": 1}   # base, before unlock gating
const ITEM_COUNT_BASE := 2                          # items per level = 2 + floor(depth / 2)
const ITEM_COUNT_DEPTH_DIV := 2
const ITEM_PLACE_WEIGHT_DEAD_END := 3.0             # Poisson placement weights
const ITEM_PLACE_WEIGHT_ROOM := 2.0
const ITEM_PLACE_WEIGHT_CAGE := 4.0                 # Server cages
const ITEM_PLACE_WEIGHT_OFF_PATH := 2.0
const ITEM_PICKUP_TWEEN_MS := 300
const ITEM_WORLD_LIGHT_ENERGY := 0.15
const ITEM_WORLD_LIGHT_RANGE := 1.0                 # m
const ITEM_WORLD_BOB_HZ := 0.2
const ITEM_WORLD_BOB_AMPLITUDE := 0.02              # m
const ITEM_WORLD_REST_HEIGHT := 0.03                # m, a pickup's lowest point above the floor (R4 constant)
const ITEM_PLACE_JITTER := 0.35                     # m, +- offset in the cell, from the placement rng (R4 constant)
const ITEM_HELD_TWEEN_MS := 500                     # lower-in / raise-out
const ITEM_HELD_BOB_SCALE := 0.6                    # share of the flashlight's bob
const NOTES_PER_LEVEL := 2                          # depths 1 to 5
const NOTES_PER_LEVEL_DEPTH6 := 1
const NOTES_FIRST_PATH_FRACTION := 0.4              # one of the two within the first 40% of the critical path
const NOTES_FOUND_REPEAT_WEIGHT := 0.5              # already-found notes at half weight

const POLAROID_USE_TIME := 1.2                      # s
const POLAROID_IMAGE_COUNT := 8
const POLAROID_IMAGE_SIZE := 256                    # px
const POLAROID_NARROW_DEG := 3.0                    # view narrows 3 deg over 1 s (11)
const POLAROID_NARROW_TIME := 1.0
const POLAROID_FRAMES := 12                         # floating frames converging (02 §10)
# Implementation number 09 leaves open (M1.10): how long the frames take to converge before
# the flash. (The `on_polaroid` cone numbers went with the hook: no error reacts to the Polaroid.)
const POLAROID_FRAMES_TIME := 0.4                   # s, ends on the flash

const GLOWSTICK_THROW_DIST := 8.0                   # m at 45 deg
const GLOWSTICK_THROW_ANGLE := 45.0                 # deg
const GLOWSTICK_DROP_HOLD := 0.5                    # s hold use_item to drop at the feet
const GLOWSTICK_LIGHT_ENERGY := 0.9
const GLOWSTICK_LIGHT_RANGE := 4.0                  # m
const GLOWSTICK_LIFETIME := 90.0                    # s
const GLOWSTICK_DIM_TIME := 20.0                    # s, dimming over the last 20 s
const GLOWSTICK_OBSERVE_DIST := STILL_OBSERVE_GLOWSTICK_DIST
const GLOWSTICK_BOUNCE := 0.35                      # bounces once, then settles (09 §2)

const FLARE_BURN_TIME := 40.0                       # s
const FLARE_LIGHT_ENERGY := 2.2
const FLARE_LIGHT_RANGE := 8.0                      # m
const FLARE_FLUTTER_HZ := 1.0
const FLARE_NOISE_RADIUS := NOISE_FLARE_BURNING_RADIUS
const FLARE_STATIC_PUSH_RANGE := STATIC_FLARE_RANGE
const FLARE_OBSERVE_DIST := STILL_OBSERVE_FLARE_DIST
const FLARE_FLAME_PARTICLES := 60

const CHALK_USES_MAX := 20
const CHALK_PICKUP_USES := 8
const CHALK_STAMP_TIME := 0.3                       # s
const CHALK_STAMP_RANGE := 2.0                      # m
const CHALK_YAW_SNAP := 45.0                        # deg
const CHALK_DECAL_SIZE := 0.4                       # m
const CHALK_DECAL_DEPTH := 0.1                      # m
const CHALK_DECAL_EMISSION := 0.15
const CHALK_MAX_DECALS := 40                        # per level, oldest removed
const CHALK_SCRAPES := 3                            # sound (03)
const CHALK_SCALE_IN_MS := 100

const RADIO_CHARGES := 3
const RADIO_CHARGE_TIME := 30.0                     # s each
const RADIO_NOISE_RADIUS := NOISE_RADIO_RADIUS
const RADIO_PING_FAST_DEG := 20.0                   # facing the exit within 20 deg: fast ping
const RADIO_PING_SLOW_DEG := 60.0                   # within 60 deg: slow; else noise

const FUSE_INSERT_TIME := 0.8                       # s (also pull out)
const FUSE_PATH_MIN := 0.35                         # Variant B fuse at 35% to 70% critical-path distance
const FUSE_PATH_MAX := 0.70
const KEYCARD_PATH_MIN := 0.35                      # keycard at 35% to 70%
const KEYCARD_PATH_MAX := 0.70
const KEYCARD_VISIBLE_DIST := 20.0                  # m, pulsing ui_accent emissive

# 09 §5 interactables
const DOOR_SWING_TIME := 0.6                        # s, ease-out
const DOOR_SLAM_TIME := 0.15                        # s, chasing error opens with a slam
const BREAKER_LEVER_TIME := 0.3                     # s
const BREAKER_HOLD_TIME := INTERACT_HOLD_TIME       # hold interact 0.6 s (07 §6)
const VENDING_WHIR_TIME := 1.0                      # s, once per machine
const PAYPHONE_LINE_HUM_TIME := 2.0                 # s after answering
const PAYPHONE_RING_ON_TIME := 2.0                  # s on (03)
const PAYPHONE_RING_OFF_TIME := 4.0                 # s off
const HIDE_UNDER_CAR_SLIDE_TIME := 0.6              # s
const HIDE_UNDER_CAR_CAMERA_HEIGHT := 0.35          # m
const HIDE_UNDER_CAR_SLOT_HEIGHT := 0.4             # m (06 §10)
const HIDE_UNDER_DESK_CAMERA_HEIGHT := 0.5          # m
const HIDE_UNDER_DESK_GAP := 0.3                    # m
const HIDE_LOCKER_YAW_LIMIT := 20.0                 # deg
const HIDE_LOCKER_SLITS := 6
const HIDE_UNDER_CAR_YAW_LIMIT := 35.0              # deg
const SOFT_WALL_MIN_SAVING := 20.0                  # m of walking each soft wall saves (09 §8, 07 §8)


# =====================================================================================
# 07  Level generation
# =====================================================================================
# 07 §2 grid model
const GRID_CELL_SIZE := 2.0                         # m
const GRID_WALL_THICKNESS := 0.2                    # m
const GRID_PARTITION_HEIGHT := 1.5                  # m
const GRID_SIZE_BY_DEPTH: Dictionary = {1: 24, 2: 28, 3: 32, 4: 34, 5: 36, 6: 28}   # square, cells
const GRID_CYCLE2_EXTRA := 2                        # +2 to each dimension
const STRATUM_CEILING_HEIGHT: Dictionary = {
	&"halls": 3.0, &"pools": 6.0, &"garage": 3.2, &"offices": 3.0, &"server": 3.5, &"substrate": 3.0,
}   # m (garage: per deck)
const GRID_WALL_TYPES: Array[StringName] = [&"NONE", &"WALL", &"SOLID", &"SOFT", &"PARTITION", &"DOOR", &"GLASS"]

# 07 §3 pipeline timing
const LEVELGEN_RETRIES := 8                         # regenerate with sub_seed + 1, then fall back
const LEVELGEN_WORKER_BUDGET_MS := 300              # layout and placement
const LEVELBUILD_SLICE_MS := 4                      # per frame
const LEVELBUILD_CHUNK_CELLS := 8                   # 8x8
const NAV_AGENT_RADIUS := 0.4                       # m
const NAV_AGENT_HEIGHT := 1.8                       # m
const NAV_MAX_CLIMB := 0.3                          # m
const NAV_CELL_SIZE := 0.2                          # m (agent radius 0.4 is two cells)
const NAV_DOOR_JAMB_INSET := 0.1                    # m (R7): jambs enter the bake 0.1 m back from the opening, so a 1.0 m doorway stays one lane after the 2-cell erosion
const NAV_CELL_HEIGHT := 0.1                        # m, voxel height (build-task constant: 1.8 m and 0.3 m divide it)
const NAV_WATER_EXCLUDE_DEPTH := 1.3                # m, deeper water excluded
const NAV_BAKE_BUDGET := 2.0                        # s, largest level (14 §10)
const CHUNK_HIDE_DIST := 40.0                       # m
const CHUNK_VISIBILITY_END := 45.0                  # m, no fade (fade would alpha-blend level geometry, 02 §5)
# Build-task constants (07 gives no number; M1.2).
const LEVELBUILD_MESH_MAX_EDGE := 0.5               # m, level mesh subdivision so vertex jitter trembles (02 §5)
const LEVELBUILD_DOOR_HEIGHT := 2.1                 # m, door opening; the edge strip is solid above it
const LEVELBUILD_DOOR_LEAF_WIDTH := 1.0             # m, hinged leaf; jamb panels fill the rest of the 1.8 m strip
const LEVELBUILD_SLICE_HEADROOM := 0.75             # start no job past 75% of the slice budget
const LEVELBUILD_SHAPES_PER_JOB := 24               # collision shapes added per build job
const LEVELBUILD_WALL_DIST_MAX := 1.0               # m, floor vertex colour B: distance to the nearest wall, clamped

# 07 §5.1 Halls
const HALLS_ROOMS_MIN := 5
const HALLS_ROOMS_MAX := 8
const HALLS_ROOM_SIZE_MIN := Vector2i(3, 3)
const HALLS_ROOM_SIZE_MAX := Vector2i(6, 5)
const HALLS_ROOM_MARGIN := 2                        # cells
const HALLS_SPAWN_ROOM_SIZE := Vector2i(3, 3)
const HALLS_EXIT_ROOM_SIZE := Vector2i(3, 3)
const HALLS_BREAKER_ROOM_SIZE := Vector2i(2, 2)
const HALLS_CLOSETS_MIN := 1
const HALLS_CLOSETS_MAX := 2
const HALLS_BRAID := 0.15
const HALLS_STRAIGHTEN := 0.10                      # fraction of corridor turns straightened
const HALLS_CORRIDOR_WIDTH := 2.0                   # m
const HALLS_ROOM_PROPS_MAX := 2                     # 0 to 2 per generic room
const HALLS_PAYPHONES_PER_LEVEL := 1                # on a corridor wall
const HALLS_FIXTURE_SPACING_CELLS := 2              # tubes along corridors
const HALLS_GROUP_MAX_FIXTURES := 6                 # per corridor segment
const HALLS_SOFT_WALLS := 4
const HALLS_HIDE_SPOTS := 2

# 07 §5.2 Pools
const POOLS_BRANCHES_MIN := 3
const POOLS_BRANCHES_MAX := 5
const POOLS_HALLS_MIN := 6
const POOLS_HALLS_MAX := 9
const POOLS_HALL_SIZE_MIN := Vector2i(8, 6)
const POOLS_HALL_SIZE_MAX := Vector2i(14, 10)
const POOLS_BASIN_INSET := 2                        # cells
const POOLS_BASIN_DEPTHS: Array[float] = [0.6, 1.2, 1.8]          # m (floor_y negated), by rng
const POOLS_FILL_WEIGHTS: Array[int] = [30, 40, 30]               # dry / shallow / full
const POOLS_FILL_SHALLOW := 0.5                     # m
const POOLS_RAMP_CELLS := 2
const POOLS_STEP_HEIGHT := 0.25                     # m
const POOLS_IMPASSABLE_DEPTH := 1.2                 # m: full basins deeper than this only via the steps
const POOLS_WADE_LIMIT := 1.3                       # m, deeper is SOLID for movement
const POOLS_PUMP_ROOMS_MIN := 1
const POOLS_PUMP_ROOMS_MAX := 2
const POOLS_PUMP_ROOM_SIZE := Vector2i(2, 2)
const POOLS_EXIT_BASIN_DEPTH := 1.8                 # m, forced dry
const POOLS_FIXTURE_SPACING_HALL_CELLS := 3
const POOLS_FIXTURE_SPACING_CORRIDOR_CELLS := 2
const POOLS_HALLS_PER_LIFEGUARD_CHAIR := 3
const POOLS_SOFT_WALLS := 3
const POOLS_SPAWN_ROOM_SIZE := Vector2i(3, 3)       # tiled antechamber on the perimeter
# Build-task constants (07 §5.2 gives no number; M2.1).
const POOLS_HALL_MIN_SIDE := 7                      # cells: the basin (inset 2) is >= 3 long, 2 step cells and a floor
const POOLS_BRANCH_SPACING := 8                     # cells between two branches on one side of the spine
const POOLS_EXTRA_ARCH_CHANCE := 0.35               # a hall's second arch (fewer dead ends)
const POOLS_FULL_SURFACE_DROP := 0.05               # m, a full basin's water sits this far under the rim
const POOLS_DEEP_RAIL_HEIGHT := 0.9                 # m above the rim: the invisible edge of deep water (SOLID for movement)
const POOLS_DRIPS_PER_HALL := 1                     # 02 §10 drips at hashed ceiling points

# 07 §5.3 Garage
const GARAGE_DECKS := 2
const GARAGE_PILLAR_SPACING_CELLS := 4
const GARAGE_STRIPS_MIN := 3
const GARAGE_STRIPS_MAX := 5
const GARAGE_STRIP_LENGTH_MIN := 4                  # cells
const GARAGE_STRIP_LENGTH_MAX := 10
const GARAGE_CORES_PER_DECK := 2
const GARAGE_CORE_SIZE := Vector2i(3, 3)
const GARAGE_RAMPS_MIN := 2
const GARAGE_RAMPS_MAX := 3
const GARAGE_RAMP_LENGTH_CELLS := 4
const GARAGE_CAR_FILL := 0.35                       # of bays (Poisson, min spacing 1 cell)
const GARAGE_CAR_MIN_SPACING_CELLS := 1
const GARAGE_BARRIER_FRACTION := 0.10               # of bay ends
const GARAGE_QUADRANT_CELLS := 4                    # fixture groups are 4x4-cell quadrants
const GARAGE_SPAWN_LOBBY_SIZE := Vector2i(3, 3)
const GARAGE_SOFT_WALLS := 3
# Build-task constants (07 §5.3 gives no number; M2.1). Split-level decks: deck 1 beside
# deck 0, GARAGE_DECK_RISE higher, the ramps crossing a band of ramp-length cells between.
const GARAGE_DECK_RISE := 3.2                       # m, deck 1 floor (07 §2: "Garage deck 1 at +3.2")
const GARAGE_DECK_WIDTH_MIN := 10                   # cells along the band
const GARAGE_RAMP_SPACING := 3                      # cells between two ramps
const GARAGE_LAMP_HEIGHT := 2.85                    # m above the deck, the lamp's mount on the pillar face
const GARAGE_PILLAR_SIZE := 0.6                     # m, square pillar in its void cell
const GARAGE_EXIT_SIGN_HEIGHT := 2.45               # m, above the stairwell door

# 07 §5.4 Offices
const OFFICES_RING_INSET := 3                       # cells from the perimeter
const OFFICES_CROSS_CORRIDORS_MIN := 1
const OFFICES_CROSS_CORRIDORS_MAX := 2
const OFFICES_OPEN_COUNT_MIN := 2
const OFFICES_OPEN_COUNT_MAX := 3
const OFFICES_OPEN_SIZE_MIN := Vector2i(10, 8)
const OFFICES_OPEN_SIZE_MAX := Vector2i(14, 10)
const OFFICES_SMALL_COUNT_MIN := 6
const OFFICES_SMALL_COUNT_MAX := 10
const OFFICES_SMALL_SIZE_MIN := Vector2i(3, 3)
const OFFICES_SMALL_SIZE_MAX := Vector2i(5, 4)
const OFFICES_MEETING_SIZE := Vector2i(5, 4)
const OFFICES_BREAKER_ROOM_SIZE := Vector2i(2, 2)
const OFFICES_CLOSETS_MIN := 1
const OFFICES_CLOSETS_MAX := 2
const OFFICES_BRAID := 0.35                         # inside open offices
const OFFICES_DESK_FRACTION := 0.60                 # of cubicle cells
const OFFICES_CHAIR_MIN_SPACING_CELLS := 3          # corridors only
const OFFICES_DARK_GROUP_FRACTION := 0.40           # groups start unpowered
const OFFICES_FIXTURE_SPACING_CELLS := 2
const OFFICES_GROUP_MAX_FIXTURES := 6               # corridor segments
const OFFICES_SOFT_WALLS := 4

# 07 §5.5 Server
const SERVER_ROW_LENGTH_MIN := 6                    # cells
const SERVER_ROW_LENGTH_MAX := 12
const SERVER_CROSS_AISLE_MIN := 6                   # cells
const SERVER_CROSS_AISLE_MAX := 10
const SERVER_CAGES_MIN := 2
const SERVER_CAGES_MAX := 4
const SERVER_CAGE_SIZE := Vector2i(4, 4)
const SERVER_AISLE_STRAIGHT_MAX := 12               # cells
const SERVER_EMERGENCY_SPACING_CELLS := 6
const SERVER_FAN_SPACING_CELLS := 5
const SERVER_RACK_GAP_HIDE_SPOTS := 3
const SERVER_SPAWN_ROOM_SIZE := Vector2i(3, 3)
const SERVER_EXIT_ROOM_SIZE := Vector2i(3, 3)
const SERVER_RACK_DEPTH := 1.0                      # m
const SERVER_SOFT_WALLS := 0

# 07 §5.6 Substrate
const SUBSTRATE_VOID_CLUSTER_FRACTION := 0.20       # of corridor cells removed
const SUBSTRATE_VOID_CLUSTER_MIN := 2               # cells per cluster
const SUBSTRATE_VOID_CLUSTER_MAX := 5
const SUBSTRATE_UNFINISHED_FRACTION := 0.30         # of built surfaces, by room or segment
const SUBSTRATE_FLOOR_OFFSET_FRACTION := 0.25       # of rooms
const SUBSTRATE_FLOOR_OFFSET := 0.25                # m, +- (within the step height)
const SUBSTRATE_STUDIO_LIGHTS_MIN := 6
const SUBSTRATE_STUDIO_LIGHTS_MAX := 10
const SUBSTRATE_STUDIO_LIGHT_SPACING_CELLS := 6
const SUBSTRATE_PATH_MIN := 140.0                   # m of walking, spawn to Threshold
const SUBSTRATE_PATH_MAX := 220.0
const SUBSTRATE_THRESHOLD_POCKET_SIZE := Vector2i(3, 3)
const SUBSTRATE_SOFT_WALLS := 6
const SUBSTRATE_STATIC_COUNT := 2
const SUBSTRATE_VOID_FRACTION_MIN := 0.15           # validation (07 §8 rule 10)
const SUBSTRATE_VOID_FRACTION_MAX := 0.25
const SUBSTRATE_THRESHOLD_REACH_TIME := 90.0        # s of walking along the critical path (05 §9 rule 8)
const SUBSTRATE_STUDIO_LIGHT_ENERGY := 0.6          # 02 §7
const SUBSTRATE_STUDIO_LIGHT_RANGE := 15.0          # m
const SUBSTRATE_MODULE_OFFSET := 0.4                # m vertical offsets of floating modules

# 07 §6 exits and locks
const LOCK_OPEN := &"open"
const LOCK_POWERED := &"powered"
const LOCK_KEYED := &"keyed"
const LOCK_CYCLED := &"cycled"
const LOCK_WEIGHTS_DEPTH1: Dictionary = {&"open": 40, &"powered": 60}
const LOCK_WEIGHTS_DEPTH1_FIRST_RUN: Dictionary = {&"powered": 100}
const LOCK_WEIGHTS_DEPTH2_3: Dictionary = {&"open": 20, &"powered": 40, &"keyed": 40}
const LOCK_WEIGHTS_DEPTH4_5: Dictionary = {&"powered": 30, &"keyed": 35, &"cycled": 35}
const LOCK_WEIGHTS_DEPTH6: Dictionary = {&"open": 100}
const CYCLED_SEALED_TIME := 70.0                    # s
const CYCLED_OPEN_TIME := 20.0                      # s
const CYCLED_WARNING_TIME := 5.0                    # s, tone before opening
const CYCLED_TONE_MAX_DISTANCE := 60.0              # m, heard through walls
const EXIT_ENTER_TWEEN_TIME := 0.6                  # s walk-in tween
const EXIT_SEEN_DIST := 25.0                        # m, frustum + unoccluded
const EXIT_STATUS_UNKNOWN := &"unknown"
const EXIT_STATUS_OPEN := &"open"
const EXIT_STATUS_POWERED := &"powered"
const EXIT_STATUS_KEYED := &"keyed"
const EXIT_STATUS_SEALED := &"sealed"

# 07 §8 validation
const VALIDATE_SEEDS_PER_STRATUM := 1000
const VALIDATE_ERROR_SPAWNS_MIN := 6
const VALIDATE_ERROR_SPAWN_MIN_WALK := 20.0         # m from spawn
const VALIDATE_DEAD_END_CHAIN_MAX := 12             # cells
const VALIDATE_HALLS_PATH_MIN := 80.0               # m at depth 1, scaling by size
const VALIDATE_HALLS_PATH_MAX := 160.0
const BREAKER_EXIT_MIN_PATH_FRACTION := 0.5         # breaker room >= 50% of the critical path's length from the exit, walking (07, 05 §10; 2026-10-08)
const VALIDATE_POOLS_PATH_MIN := 40.0               # m at depth 2 (28 cells), scaling by size (M2.1; 07 gives none)
const VALIDATE_POOLS_PATH_MAX := 140.0
const VALIDATE_GARAGE_PATH_MIN := 40.0              # m at depth 2, scaling by size (M2.1; 07 gives none)
const VALIDATE_GARAGE_PATH_MAX := 140.0

# 07 §9 Cycle 2 corruption (generator side)
const CYCLE2_BRAID_MULT := 0.5
const CYCLE2_EXTRA_STATIC := 1
const CYCLE2_FIXTURES_REMOVED := 0.10               # corridor fixtures
const CYCLE2_EXTRA_SOFT_WALLS := 1
const CYCLE2_OFFICES_DARK_FRACTION := 0.60
const CYCLE2_FIXTURE_HUE_SHIFT := 12.0              # deg toward the next stratum's light colour (02 §7)
const CYCLE2_FIXTURES_DARK := 0.25                  # of fixtures
const CYCLE2_FOG_MULT := 1.3
const CYCLE2_JITTER_FLOOR := 0.004
const CYCLE2_SURFACE_UNRENDER_FRACTION := 0.10
const CYCLE2_SURFACE_UNRENDER_U := 0.2


# =====================================================================================
# 02  Visual direction
# =====================================================================================
# 02 §3 renderer
const RENDER_AO_RADIUS := 1.0
const RENDER_AO_INTENSITY := 2.0
const RENDER_AO_LIGHT_AFFECT := 0.5                 # AO darkens direct light too, so seams read under fixtures (render-task constant)
const RENDER_GLOW_THRESHOLD := 1.0                  # HDR
const RENDER_GLOW_INTENSITY := 0.6
const RENDER_GLOW_BLOOM := 0.1
const RENDER_FRAME_BUDGET_MS := 16.6                # 14 §10
const RENDER_FPS_TARGET := 60
# Render-task implementation constants (02 gives no number; chosen against T1/T3 in the
# render bench, M1.5). Volumetric fog: emission in the fog colour keeps unlit air visible.
const RENDER_FOG_EMISSION_ENERGY := 0.2
const RENDER_FOG_EMISSION_STRATUM: Dictionary = {&"garage": 0.8}   # per-stratum override (M2.1: the Garage's dark fog read flat black, T3)
const RENDER_FOG_AMBIENT_INJECT := 1.0
const RENDER_FOG_LENGTH := 64.0                     # m of froxel volume
const RENDER_FOG_FROXEL_DEPTH := 64                 # froxel depth slices
const RENDER_FOG_LOW_LIGHT_ENERGY := 1.0            # Low preset distance fog

# 02 §4 Coherence renderer (post stack)
const POST_CA_MAX := 0.012                          # lerp(0, 0.012, drain)
const POST_DRAIN_SMOOTH_MIN := 0.1                  # drain eased smoothstep(0.1, 1.0, drain)
const POST_DRAIN_SMOOTH_MAX := 1.0
const POST_SAT_MIN := 0.08                          # lerp(1.0, 0.08, smoothstep(0.3, 1.0, drain))
const POST_SAT_SMOOTH_MIN := 0.3
const POST_SAT_SMOOTH_MAX := 1.0
const POST_GRAIN_MIN := 0.02
const POST_GRAIN_MAX := 0.18
const POST_VIGNETTE_MIN := 0.15
const POST_VIGNETTE_MAX := 0.45
const POST_THREAT_VIGNETTE_MAX := 0.3
const POST_NULL_LINE_COLOR := "#E6E6E6"
const POST_PULSE_HIT_CA := 0.03
const POST_PULSE_HIT_INVERT_FRAMES := 2
const POST_PULSE_HIT_DECAY_MS := 400
const POST_PULSE_NOCLIP_CA := 0.05
const POST_PULSE_NOCLIP_SCANLINE := 1.0
const POST_PULSE_NOCLIP_DECAY_MS := 300
const POST_PULSE_GAIN_SATURATION := 1.15
const POST_PULSE_GAIN_WARMTH := 0.05
const POST_PULSE_GAIN_MS := 600
const POST_PULSE_DISSOLVE_TIME := 1.5               # s; grain to 1.0, saturation to 0
const POST_REDUCED_GRAIN_CAP := 0.06                # reduce_visual_noise (02 §4, 12 §6)
const POST_REDUCED_CA_CAP := 0.004
const POST_STATIC_GRAIN := 0.6                      # inside Static (02 §8)
const POST_STATIC_CA := 0.02
const POST_DISSOLVE_GRID := Vector2i(48, 27)        # quads (02 §10)
# `flash` is the Polaroid's white flash only (09); Flicker's lunge flash is the fixture
# group's, not the post stack's. `ripple`: Landing (11 §3). `drop`: the floor commit fires
# it (1.2 s to black with grain, then held), the drop arrival fires it again (black to the
# world over 400 ms).
const POST_PULSE_KINDS: Array[StringName] = [&"hit", &"noclip_commit", &"coherence_gain", &"dissolve", &"flash", &"ripple", &"drop"]
# Render-task constants of the screen pass (02 gives no number; chosen in the render bench).
const POST_GRAIN_FPS := 24.0                        # grain re-seeds at film cadence
const POST_TEAR_ROWS := 0.035                       # fraction of rows torn at scan 1
const POST_TEAR_SHIFT := 0.025                      # max sideways shift, fraction of the width
const POST_TEAR_LIGHT := 0.03                       # torn rows carry a faint light line
const POST_PULSE_RIPPLE_MS := 600                   # Landing ripple crosses the screen
const POST_RIPPLE_WIDTH := 0.05                     # ring half-width, fraction of the height
const POST_RIPPLE_SHIFT := 0.008                    # radial displacement in the ring
const POST_RIPPLE_LIGHT := 0.12                     # ring brightening in the grid colour
const POST_TIME_WRAP_S := 3600.0                    # g_time and grain time wrap (render-task constant: shader float precision)

# 02 §5 world shader
const WORLD_JITTER_MAX := 0.012
const WORLD_JITTER_SMOOTH_MIN := 0.5
const WORLD_JITTER_SMOOTH_MAX := 1.0
const WORLD_JITTER_NOCLIP := 0.04                   # x g_noclip_commit
const WORLD_JITTER_HZ := 20.0                       # jitter re-seeds 20 times per second (TAA)
const WORLD_UNRENDER_INNER := 0.6                   # u = smoothstep(r, r*0.6, d)
const WORLD_GRID_SPACING := 0.5                     # m
const WORLD_GRID_LINE_COLOR := "#E6E6E6"
const WORLD_UNRENDER_FULL := 0.95                   # u >= 0.95: fully lines, screen-door transparent
const WORLD_SCISSOR_THRESHOLD := 0.5
const WORLD_SCREEN_DOOR_MAX := 0.6                  # at u >= 0.95 a fraction 0.6 x u of fill cells is
                                                    # discarded: ALPHA = hash(cell) < 0.6 u ? 0 : 1
const WORLD_SCREEN_DOOR_CELL := 0.01                # m; hash cell lattice: 1 cm, halved/doubled by octaves
                                                    # until one cell is at most a pixel (world-anchored)
const WORLD_SOFT_BAND_HZ := 0.5
const WORLD_SOFT_BAND_AMPLITUDE := 0.03
const WORLD_SOFT_PREVIEW_U := 0.3
const WORLD_SOFT_PREVIEW_DIST := 2.0                # m crosshair range
const WORLD_SOFT_PREVIEW_SPAN := 1.2                # m around the aimed point (render-task constant)
const WORLD_NOCLIP_PREVIEW_U := 0.9                 # charge preview peak, below WORLD_UNRENDER_FULL so a
                                                    # cancelled charge never shows what is behind a wall
const WORLD_NOCLIP_PREVIEW_DEPTH := 0.3             # m; surfaces this far off the target plane are outside the disc
const WORLD_NOCLIP_INVALID_DASHES_PER_M := 8.0      # invalid noclip: the preview grid is dashed (11 §2)
const WORLD_COMMIT_LINE_PX := 2.5                   # px, grid line width within 3 m during the noclip commit (M3.2 render constant)
const WORLD_COMMIT_LINE_GAIN := 3.0                 # x line emission there (M3.2 render constant)
const WORLD_CARPET_LOOPS_PER_M := 90.0              # Halls loop pile (60 to 120 per m reads at 1 to 3 m)
const WORLD_WALLPAPER_PRINT_PERIOD := 0.15          # m; Halls wallpaper diamond print
const WORLD_PLACEHOLDER_CHECKER := 1.0              # m checker, magenta #FF00FF and black
const WORLD_SUBSTRATE_U_FLOOR := 0.55
const WORLD_NOISE_TEXTURE_MAX := 1024               # px (14 §10)
const WORLD_PATTERN_FLAT := 0                       # pattern_mode values
const WORLD_PATTERN_TILES := 1
const WORLD_PATTERN_STRIPES := 2
const WORLD_PATTERN_CARPET := 3
const WORLD_PATTERN_CONCRETE := 4
const WORLD_PATTERN_CHECKER := 5
const WORLD_PATTERN_PANEL := 6

# 02 §6 lighting
const LIGHT_POOL_REEVAL_INTERVAL := 0.25            # s
const LIGHT_POOL_SIZE_HIGH := 24
const LIGHT_POOL_SIZE_MEDIUM := 16
const LIGHT_POOL_SIZE_LOW := 10
const LIGHT_POOL_SIZE_MIN := 10                     # 12 §3 range
const LIGHT_POOL_SIZE_MAX := 32
const LIGHT_POOL_SIGHT_CANDIDATES := 3              # x pool size: nearest fixtures tested for grid line of sight
const LIGHT_POOL_FADE_IN := 0.2                     # s, a light re-assigned to a fixture ramps in (render-task constant)
const LIGHT_POOL_DISTANCE_FADE_BEGIN := 18.0        # m, distance_fade on pooled lights hides the swap (render-task constant)
const LIGHT_POOL_DISTANCE_FADE_LENGTH := 6.0        # m
const LIGHT_FIXTURE_ATTENUATION := 2.0              # omni_attenuation of pooled fixture lights (render-task constant)
const LIGHT_FIXTURE_ATTENUATION_STRATUM: Dictionary = {&"pools": 1.0, &"garage": 1.0}   # M2.1: 6 m pool ceilings and 8 m sodium spacing (T1)
const LIGHT_FIXTURE_KIND: Dictionary = {&"halls": &"omni"}   # pooled light per stratum: omni or spot (02 §6)
const LIGHT_SPOT_ANGLE := 70.0                      # deg, spot fixtures: a wide downlight (render-task constant)
const LIGHT_SPOT_ANGLE_ATTENUATION := 1.0
const LIGHT_FIXTURE_DROP := 0.7                    # m, pooled light hangs below the tube so the ceiling reads lit
const LIGHT_FIXTURE_DROP_STRATUM: Dictionary = {&"garage": 0.25}   # M2.1: sodium lamps on pillars light from the lamp (short pillar shadows, T1)
const LIGHT_FIXTURE_BUZZ_ENERGY := 0.85             # the one-in-six buzzing fixtures: tube and light energy (R4 V3)
const LIGHT_FIXTURE_BUZZ_TINT := Color(0.9, 1.0, 0.86)   # and a slightly greener tube and light (multiplier)
const LIGHT_FIXTURE_GLOW_ENERGY := 1.0              # ceiling halo around a lit tube (fixture_glow.gdshader; R4 V3)
const LIGHT_FIXTURE_EMISSION_MIN := 4.0
const LIGHT_FIXTURE_EMISSION_MAX := 12.0
const LIGHT_AMBIENT_ENERGY_MIN := 0.08
const LIGHT_AMBIENT_ENERGY_MAX := 0.2
const LIGHT_BREAKER_WAVE_SPEED := 12.0              # m/s
const LIGHT_BREAKER_STAGGER_MS := 40
const LIGHT_BREAKER_OVERSHOOT := 1.3
const LIGHT_BREAKER_SETTLE_MS := 400
const LIGHT_FLICKER_VISUAL_MIN_HZ := 8.0
const LIGHT_FLICKER_VISUAL_MAX_HZ := 20.0
const LIGHT_FLICKER_LUNGE_FLASH_FRAMES := 2
const LIGHT_FLICKER_LUNGE_DARK_TIME := 1.5          # s
const LIGHT_FLICKER_REDUCED_FADE_MS := 200          # reduce flashing: soft fade to 60% white (12 §6)
const LIGHT_FLICKER_REDUCED_WHITE := 0.6
const SUBSTRATE_FOG_START := 25.0                   # m, distance fog to #000000 (02 §7)
const SUBSTRATE_FOG_END := 45.0                     # (02 §6 says "to black at 40 m"; 02 §7 range used)

## Per-stratum look numbers (02 §6, §7). Colours live in StratumData; these are the scalars.
const STRATUM_FOG_DENSITY: Dictionary = {
	&"halls": 0.02, &"pools": 0.035, &"garage": 0.015, &"offices": 0.02, &"server": 0.03, &"substrate": 0.0,
}
const STRATUM_AMBIENT_ENERGY: Dictionary = {
	&"halls": 0.08, &"pools": 0.2, &"garage": 0.12, &"offices": 0.15, &"server": 0.1, &"substrate": 0.05,
}
const STRATUM_EXPOSURE: Dictionary = {
	&"halls": 1.0, &"pools": 1.05, &"garage": 0.95, &"offices": 1.0, &"server": 1.1, &"substrate": 1.0,
}
const STRATUM_FIXTURE_ENERGY: Dictionary = {
	&"halls": 1.4, &"pools": 1.2, &"garage": 1.4, &"offices": 1.1, &"server": 0.5,
}   # server: emergency box; substrate has no fixtures
const STRATUM_FIXTURE_RANGE: Dictionary = {
	&"halls": 7.0, &"pools": 10.0, &"garage": 12.0, &"offices": 6.0, &"server": 5.0,
}   # m
const STRATUM_FIXTURE_EMISSION: Dictionary = {
	&"halls": 8.0, &"pools": 10.0, &"garage": 6.0, &"offices": 9.0,
}   # emission_strength multiplier
const STRATUM_FIXTURE_SPACING: Dictionary = {
	&"halls": 4.0, &"pools": 6.0, &"garage": 8.0, &"offices": 4.0, &"server": 12.0,
}   # m (T2: exact grid)
const STRATUM_COLORS: Dictionary = {
	&"halls": {&"fog": "#B49A3C", &"ambient": "#6E5A1E", &"fixture_light": "#FFEFC2", &"fixture_emission": "#FFF2C4"},
	&"pools": {&"fog": "#5FA8A3", &"ambient": "#1F4A47", &"fixture_light": "#DDF0EE", &"fixture_emission": "#E8F6F5"},
	&"garage": {&"fog": "#4A3A22", &"ambient": "#2A221A", &"fixture_light": "#FFA94D", &"fixture_emission": "#FF9A2E"},
	&"offices": {&"fog": "#8E96A0", &"ambient": "#3A4048", &"fixture_light": "#DCE8F5", &"fixture_emission": "#E6F0FF"},
	&"server": {&"fog": "#0D1B2A", &"ambient": "#0C1220", &"fixture_light": "#FF3B3B", &"fixture_emission": "#FF3B3B"},
	&"substrate": {&"fog": "#000000", &"ambient": "#101010"},
}
const SERVER_RACK_LED_LIGHT_ENERGY := 0.35          # one omni per 4 racks, colour #2F5BFF, range 4 m
const SERVER_RACK_LED_LIGHT_RANGE := 4.0
const SERVER_RACKS_PER_LED_LIGHT := 4
const SERVER_RACK_LED_PERIOD_MIN := 0.5             # s, hashed blink periods
const SERVER_RACK_LED_PERIOD_MAX := 4.0
const SERVER_RACK_LED_EMISSION := 4.0
const OFFICES_MONITOR_GLYPH_ODDS := 4000            # 1 in 4,000 frames per monitor shows the NOCLIP glyph
const OFFICES_MONITOR_EMISSION := 2.0
const SERVER_RACK_SIZE := Vector3(0.6, 2.0, 1.0)    # m
const GARAGE_BAND_HEIGHT := 1.2                     # m painted band on perimeter walls
const GARAGE_BAY_LINE_PERIOD := 2.5                 # m
const GARAGE_BAY_LINE_WIDTH := 0.1                  # m
const GARAGE_BEAM_SPACING := 8.0                    # m exposed beams
const POOLS_TILE_SIZE := 0.2                        # m, grout 0.012
const POOLS_TILE_GROUT := 0.012
const POOLS_WATER_ALPHA := 0.75
const POOLS_WATER_REFRACTION := 0.03
const POOLS_BASIN_DEPTH_MIN := 0.6                  # m (02 §7: 0.6 to 1.8)
const POOLS_BASIN_DEPTH_MAX := 1.8
const HALLS_STRIPE_WIDTH := 0.6                     # m
const OFFICES_PANEL_SIZE := 1.2                     # m
const OFFICES_TILE_SIZE := 0.5                      # m carpet tile
const SERVER_FLOOR_TILE := 0.6                      # m
const SERVER_FAN_SPACING := 10.0                    # m, 02 §7 (one per 10 m = 5 cells)
const SUBSTRATE_LINE_EMISSION := 1.5                # emission from the line term
const THRESHOLD_STRIP_HEIGHT := 0.02                # m of daylight under the door
const THRESHOLD_STRIP_EMISSION := 20.0

# 02 §8 error visual signatures
const STATIC_DISTORTION_OFFSET := 0.04
const STATIC_FILL_ALPHA := 0.08
const ECHO_SHIMMER_REFRACTION := 0.015
const FLICKER_VISUAL_SPARK_SIZE := FLICKER_SPARK_SIZE

# 02 §9, §10 held visuals, particles
const FLASHLIGHT_MODEL_LENGTH := 0.18               # m cylinder
const DUST_BOX_SIZE := 12.0                         # m
const DUST_PARTICLES := 200
const DUST_ALPHA := 0.12
const DUST_QUAD_SIZE := 0.0035                      # m (3.5 mm: 1 mm is sub-pixel beyond 1 m)
const PARTICLES_LOW_SCALE := 0.5

# 02 §11 camera
const CAMERA_FOV_DEFAULT := 90                      # deg horizontal at 16:9 (12 §2)
const CAMERA_FOV_MIN := 70
const CAMERA_FOV_MAX := 110
const CAMERA_NEAR := 0.05                           # m
const CAMERA_FAR := 120.0                           # m
const CAMERA_ASPECT_REF := 0.5625                   # 9/16, vfov = 2 atan(tan(hfov/2) x 9/16)
const CAMERA_BOB_VERTICAL := 0.03                   # m at walk
const CAMERA_BOB_LATERAL := 0.015                   # m at walk
const CAMERA_BOB_SPRINT_MULT := 1.6
const CAMERA_LEAN_DEG := 1.5                        # roll on strafe
const CAMERA_DIP := 0.05                            # m over 120 ms (landing/crouch)
const CAMERA_DIP_MS := 120
const CAMERA_SHAKE_MAX_TRANSLATION := 0.04          # m
const CAMERA_SHAKE_MAX_ROTATION := 1.2              # deg
const CAMERA_TRAUMA_DECAY := 1.5                    # per s; shake = trauma^2

# 02 §12 quality presets (the "visual contract" per tier)
const QUALITY_PRESETS: Dictionary = {
	&"low": {
		&"lights": 10, &"shadowed": 0, &"volumetric_fog": &"off", &"fog_froxel_px": 0, &"ssao": false, &"ssil": false,
		&"aa": &"fxaa", &"shadow_atlas": 2048, &"render_scale": 0.8, &"particles": 0.5,
	},
	&"medium": {
		&"lights": 16, &"shadowed": 2, &"volumetric_fog": &"on", &"fog_froxel_px": 64, &"ssao": true, &"ssil": false,
		&"aa": &"taa", &"shadow_atlas": 4096, &"render_scale": 1.0, &"particles": 1.0,
	},
	&"high": {
		&"lights": 24, &"shadowed": 4, &"volumetric_fog": &"on", &"fog_froxel_px": 128, &"ssao": true, &"ssil": true,
		&"aa": &"taa", &"shadow_atlas": 8192, &"render_scale": 1.0, &"particles": 1.0,
	},
}
const QUALITY_PRESET_DEFAULT := &"medium"
const QUALITY_TEXTURE_SIZE_LOW := 512               # noise texture resolution (12 §3)
const QUALITY_TEXTURE_SIZE_HIGH := 1024
const T1_FLOOR_VISIBLE_DIST := 12.0                 # m (6 m in Server and Substrate), luminance > 8%
const T1_FLOOR_VISIBLE_DIST_DARK := 6.0
const T1_FLOOR_MIN_LUMINANCE := 0.08


# =====================================================================================
# 03  Audio direction (mix numbers)
# =====================================================================================
const AUDIO_SAMPLE_RATE := 48000
const AUDIO_ERRORS_DUCK_AMBIENCE_DB := -4.0         # when any error is within AUDIO_ERRORS_DUCK_DIST
const AUDIO_ERRORS_DUCK_DIST := 10.0                # m
const AUDIO_NOCLIP_DUCK_DB := -8.0                  # everything but Player
const AUDIO_NOCLIP_DUCK_MS := 300
const AUDIO_NOTE_DUCK_MUSIC_DB := -6.0              # for the sheet's duration
const AUDIO_LIMITER_CEILING_DB := -1.0
const AUDIO_PLAYER_LOW_SHELF_DB := 2.0
const AUDIO_PLAYER_LOW_SHELF_HZ := 90.0
const AUDIO_OCCLUSION_INTERVAL := 0.2               # s
const AUDIO_OCCLUSION_LOWPASS_HZ := 800.0
const AUDIO_OCCLUSION_DB := -6.0
const AUDIO_OCCLUSION_TWEEN_MS := 100
const AUDIO_UNIT_SIZE := 1.0
const AUDIO_STATIC_MAX_DISTANCE := 40.0             # m, heard through walls
const AUDIO_NULL_MAX_DISTANCE := 60.0               # m, heard through walls
const AUDIO_PLAYER_POOL_SIZE := 32                  # AudioStreamPlayer3D pool (14 §3)
const AUDIO_PLAYER_STEP_DB_PEAK := -14.0            # walk footsteps always audible
const AUDIO_ERRORS_BUS_MAX_DB := -6.0               # before the limiter
const AUDIO_ROOM_TONE_FLOOR_DB := -40.0
const AUDIO_STILL_SILENCE_FLOOR_DB := -46.0
const AUDIO_SAMPLE_FADE_IN_MS := 2
const AUDIO_PITCH_VARIATION := 0.04                 # +-4%
const AUDIO_LOSS_TICK_MAX_HZ := 20.0                # Coherence loss tick, one per unit lost, rate-limited (03)
const AUDIO_VARIATIONS_MIN := 3                     # per one-shot
const AUDIO_VARIATIONS_MAX := 5
const AUDIO_REVERB_CROSSFADE := 1.0                 # s on level load
const AUDIO_REVERB: Dictionary = {
	&"halls": {&"room": 0.5, &"damping": 0.6, &"wet": 0.2},
	&"pools": {&"room": 0.9, &"damping": 0.2, &"wet": 0.45, &"predelay_ms": 40},
	&"garage": {&"room": 0.8, &"damping": 0.4, &"wet": 0.3},
	&"offices": {&"room": 0.4, &"damping": 0.7, &"wet": 0.15},
	&"server": {&"room": 0.3, &"damping": 0.8, &"wet": 0.1},
	&"substrate": {&"room": 1.0, &"damping": 0.0, &"wet": 0.5, &"highpass_hz": 300},
}
const AUDIO_BUSES: Array[StringName] = [
	&"Master", &"World", &"Footsteps", &"Interact", &"Errors", &"Ambience", &"Player", &"Music", &"UI",
]
const AUDIO_HEARTBEAT_MIN_BPM := 60.0               # by threat
const AUDIO_HEARTBEAT_MAX_BPM := 140.0
const AUDIO_BED_CUTOFF_MIN_HZ := 200.0              # static bed lerp(200, 6000, drain)
const AUDIO_BED_CUTOFF_MAX_HZ := 6000.0
const AUDIO_BED_GAIN_MIN_DB := -60.0                # lerp(-60, -18, drain^1.5)
const AUDIO_BED_GAIN_MAX_DB := -18.0
const AUDIO_NULL_TONE_HZ: Array[float] = [55.0, 82.5, 110.0]
const AUDIO_STATIC_HUM_HZ: Array[float] = [50.0, 100.0]
const AUDIO_SLIDER_MUTE_DB := -80.0                 # 12 §4

# 03 §5 music
const MUSIC_CHORDS: Dictionary = {
	&"halls": ["A2", "E3", "B3"], &"pools": ["D2", "A2", "F3"], &"garage": ["G1", "D2", "Bb2"],
	&"offices": ["E2", "B2", "G3"], &"server": ["C2", "G2", "Eb3"], &"substrate": ["A1"],
}
const MUSIC_PAD_LOOP_TIME := 12.0                   # s, 2 s crossfades, three variations
const MUSIC_PAD_CROSSFADE := 2.0
const MUSIC_VOICE_CHANGE_MIN := 20.0                # s between voice changes
const MUSIC_VOICE_CHANGE_MAX := 45.0
const MUSIC_INTENSITY_OPEN := 0.6                   # above this the LP opens and a 4th voice fades in
const MUSIC_LP_CLOSED_HZ := 600.0
const MUSIC_LP_OPEN_HZ := 1800.0
const MUSIC_FOURTH_VOICE_DB := -10.0
const MUSIC_PEAK_SILENCE_TIME := 4.0                # s of silence at the start of a chase
const MUSIC_TITLE_TREMOLO_HZ := 0.2
const MUSIC_ENDING_CHORD: Array[String] = ["A3", "C#4", "E4"]
const MUSIC_ENDING_TIME := 40.0                     # s


# =====================================================================================
# 04  UI design language
# =====================================================================================
const UI_FONT_HUD_BODY := 18                        # px at 1080p (UI scale multiplies)
const UI_FONT_HUD_NUMERAL := 24                     # Bold
const UI_FONT_PROMPT := 20
const UI_FONT_MENU_ITEM := 22
const UI_FONT_MENU_HEADING := 28                    # Bold
const UI_FONT_WORDMARK := 160                       # Bold
const UI_FONT_NOTE := 20
const UI_FONT_CAPTION := 20
const UI_WORDMARK_SPACING_EM := 0.18
const UI_UPPERCASE_SPACING_EM := 0.08
const UI_COLOR_FG := "#F2F2F2"
const UI_COLOR_DIM := "#8C8C8C"
const UI_COLOR_BG := "#000000"
const UI_COLOR_ACCENT := "#FFB000"
const UI_COLOR_DANGER := "#FF3B3B"
const UI_COLOR_COLD := "#3B8BFF"
const UI_COLOR_ACCENT_CB := "#FFD166"               # colour-blind safe accent (12 §6)
const UI_BACKING_ALPHA := 0.6                       # prompts and captions
const UI_PAUSE_OVERLAY_ALPHA := 0.7
const UI_GRID_UNIT := 8                             # px
const UI_MARGIN := 32                               # px, safe area
const UI_LINE_WIDTH := 1                            # px
const UI_BAR_TRACK_HEIGHT := 2
const UI_BAR_FILL_HEIGHT := 4
const UI_TWEEN_MS := 180                            # value changes
const UI_SHUTTER_MS := 120                          # slice-in / slice-out
const UI_SHUTTER_BANDS := 6
const UI_SHUTTER_STAGGER_MS := 10
const UI_GLITCH_MS := 120
const UI_GLITCH_BANDS_MIN := 8
const UI_GLITCH_BANDS_MAX := 14
const UI_GLITCH_OFFSET_PX := 12                     # +-
const UI_GLITCH_CA := 0.02
const UI_TYPING_CPS := 60                           # notifications and summary lines
const UI_NOTE_TYPING_CPS := 90
const UI_CURSOR_BLINK_HZ := 2.0
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 1.5
const UI_SCALE_STEP := 0.05
const UI_TEXT_SIZE_MIN := 0.9
const UI_TEXT_SIZE_MAX := 1.4
const UI_MENU_ROW_HEIGHT := 40                      # px
const UI_SLIDER_WIDTH := 200                        # px
const UI_SENS_TEST_SIZE := 200                      # px square
const UI_REBIND_FLASH_TIME := 2.0                   # s, swapped rows flash ui_accent

# 04 §6 HUD
const HUD_LOSS_LINGER_MS := 600                     # lost segment stays ui_danger
const HUD_GAIN_FLASH_MS := 200
const HUD_CROSSHAIR_DOT := 2                        # px
const HUD_CROSSHAIR_RING := 12                      # px circle on an interactable
const HUD_CROSSHAIR_RING_GAP := 2
const HUD_STAMINA_ARC_RADIUS := 18                  # px, 180 degree arc
const HUD_STAMINA_ARC_HIDE_DELAY := 1.0             # s after refill
const HUD_NOCLIP_ARC_RADIUS := 24                   # px, 360 degrees
const HUD_NOCLIP_ECHO_RING_LEAD_MS := 100           # outer ring completes 100 ms before commit
const HUD_PROMPT_OFFSET_Y := 120                    # px below the crosshair
const HUD_NOTIFY_TIME := 4.0                        # s
const HUD_NOTIFY_MAX_STACK := 2
const HUD_DEPTH_STRATUM_PAD := 2                    # DEPTH 03
const HUD_COHERENCE_PAD := 3                        # COHERENCE 087

# 04 §7 menus and screens
const MENU_TITLE_FOG_BOOST := 0.3                   # fog up 30%
const MENU_TITLE_COHERENCE := 85                    # renderer at 85 (faint grain)
const MENU_TITLE_FLICKER_MIN := 25.0                # s between unrender flickers
const MENU_TITLE_FLICKER_MAX := 40.0
const MENU_TITLE_FLICKER_MS := 200
const MENU_TITLE_GRID_CELL := 8                     # px grid behind the wordmark
const MENU_BOOT_TIME := 1.2                         # s of black with the typed line
const MENU_SUMMARY_RESTART_MAX := 1.0               # s, Enter restarts within 1 s
const ARCHIVE_NOTE_GRID := Vector2i(6, 6)           # columns (strata) x rows

# 04 §8 note sheets and captions
const NOTE_SHEET_WIDTH := 720                       # px
const NOTE_SHEET_PADDING := 8
const NOTE_SHEET_ALPHA := 0.92
const NOTE_SHEET_BACKING := "#1A1A1A"
const NOTE_SHEET_BACKING_FALLER := "#1F1B14"
const NOTE_SHEET_BACKING_BUILDER := "#141A1F"
const NOTE_SHEET_BACKING_STRAY := "#171717"
const NOTE_SHEET_DISMISS_HOLD := 0.5                # s, any movement key
const NOTE_SHEET_AUTO_LOWER_TIME := 8.0             # s (01 §7)
const NOTE_MAX_WORDS := 70                          # hard limit (01 §6)
const CAPTION_NEAR_DIST := 6.0                      # m: "near" under, none 6 to 20, "far" over
const CAPTION_FAR_DIST := 20.0
const CAPTION_SECTORS := 8                          # listener-relative angle sectors

# 04 §9 first-run guidance
const HINT_SHOW_TIME := 6.0                         # s or until performed
const HINT_MOVE_DIST := 3.0                         # m walked
const HINT_FLASHLIGHT_DELAY := 15.0                 # s on spawn, or when ambient light drops
const HINT_CRANK_BELOW := 60.0                      # percent
const HINT_SOFT_WALL_DIST := 3.0                    # m, aimed at
const HINT_FLOOR_AIM_TIME := 5.0                    # s with no soft wall, depth 2 or deeper
const HINT_FLOOR_MIN_DEPTH := 2
const HINT_SUPPRESS_DEPTH := 3                      # suppressed after reaching depth 3 once
const HINT_COUNT := 7


# =====================================================================================
# 11  Feedback contract
# =====================================================================================
const FEEDBACK_MAX_LATENCY_MS := 50                 # three channels within 50 ms
const FEEDBACK_MAX_LATENCY_FRAMES := 3              # bench check at 60 fps
const FEEDBACK_SPRINT_FOV_DEG := 4.0                # +4 over 200 ms, back over 300 ms
const FEEDBACK_SPRINT_FOV_UP_MS := 200
const FEEDBACK_SPRINT_FOV_DOWN_MS := 300
const FEEDBACK_SPRINT_BREATH_IN := 2.0              # s fade in
const FEEDBACK_SPRINT_BREATH_OUT := 1.0             # s fade out
const FEEDBACK_STAMINA_EMPTY_BOB_CUT := 0.2         # bob reduces 20% for 2 s
const FEEDBACK_STAMINA_EMPTY_BOB_TIME := 2.0
const FEEDBACK_STAMINA_BLINKS := 2
const FEEDBACK_STRAFE_ROLL_DEG := CAMERA_LEAN_DEG
const FEEDBACK_FLASHLIGHT_ROLL_KICK_DEG := 0.3
const FEEDBACK_CRANK_SWAY_HZ := 1.0
const FEEDBACK_CRANK_SWAY := 0.004                  # m
const FEEDBACK_INTERACT_NOD_DEG := 0.2
const FEEDBACK_INTERACT_HOLD_TICK := 0.2            # s per tick
const FEEDBACK_ITEM_PULSE := 1.15                   # glyph pulse on select (100 ms, 04 §6)
const FEEDBACK_ITEM_PULSE_MS := 100
const FEEDBACK_ITEM_USE_BLINK_MS := 100
const FEEDBACK_ITEM_SELECT_BOB := 0.012             # m, hand bob depth on select, one cycle (11 §2; R4 constant)
const FEEDBACK_ITEM_SELECT_BOB_MS := 300            # one cycle
const FEEDBACK_ITEM_SELECT_NOD_DEG := 0.3           # the view nods with it
const FEEDBACK_THROW_RECOIL_DEG := 2.0
const FEEDBACK_NOCLIP_FLASHLIGHT_DIM := 0.3         # held flashlight dims 30% while charging
const FEEDBACK_NOCLIP_SWAY := 0.003                 # m
const FEEDBACK_NOCLIP_CANCEL_COLLAPSE_MS := 100
const FEEDBACK_NOCLIP_CANCEL_FOV_MS := 150
const FEEDBACK_NOCLIP_COMMIT_TRAUMA := 0.8
const FEEDBACK_NOCLIP_FALL_PITCH_DEG := 10.0
const FEEDBACK_NOCLIP_SOUND_GAP_MS := 60
const FEEDBACK_CHALK_NOD_DEG := 1.0
const FEEDBACK_CHALK_MISS_NOD_DEG := 0.3            # chalk at nothing: a smaller nod (R4 constant)
const FEEDBACK_GAIN_FOV_DEG := 2.0                  # +2 then back over 400 ms
const FEEDBACK_GAIN_FOV_MS := 400
const FEEDBACK_STATIC_JITTER := 0.002               # m
const FEEDBACK_FLICKER_LUNGE_TRAUMA := 0.4          # 11 §3; 06 §9 contact trauma 0.6 wins when a contact lands
const FEEDBACK_NULL_RADIUS_JITTER := 0.004          # m
const FEEDBACK_NULL_CORE_JITTER := 0.01             # m
const FEEDBACK_ENTER_EXIT_FOV_DEG := -3.0
const FEEDBACK_LANDING_TRAUMA := 0.3                # at start and end
const FEEDBACK_ARRIVAL_DROP_TRAUMA := 0.3
const FEEDBACK_BREAKER_TRAUMA := 0.3
const FEEDBACK_DISSOLVE_DRIFT := 0.02               # m
const FEEDBACK_DISSOLVE_HUD_SHUTTER := 0.5          # s into the dissolve
const FEEDBACK_HUD_TWEEN_MS := UI_TWEEN_MS
const FEEDBACK_SHUTTER_MS := UI_SHUTTER_MS
const FEEDBACK_FOV_TWEEN_MIN_MS := 200
const FEEDBACK_FOV_TWEEN_MAX_MS := 300
const FEEDBACK_CAMERA_HEIGHT_MS := PLAYER_CROUCH_TRANSITION_MS
const FEEDBACK_HELD_TWEEN_MS := ITEM_HELD_TWEEN_MS
const FEEDBACK_TRAUMA_DECAY := CAMERA_TRAUMA_DECAY


# =====================================================================================
# 12  Settings and accessibility
# =====================================================================================
const SETTINGS_FILE := "user://settings.cfg"
const SETTINGS_BACKUP_SUFFIX := ".bad"
const SETTINGS_SAVE_DEBOUNCE := 0.5                 # s
const SETTINGS_REVERT_COUNTDOWN := 10.0             # s, window mode and resolution
const SETTINGS_MIN_RESOLUTION := Vector2i(1280, 720)
const SETTINGS_FPS_MIN := 30
const SETTINGS_FPS_MAX := 360                       # or Unlimited (0)
const SETTINGS_FPS_UNLIMITED := 0
const SETTINGS_RENDER_SCALE_MIN := 0.5
const SETTINGS_RENDER_SCALE_MAX := 1.5
const SETTINGS_RENDER_SCALE_STEP := 0.05
const SETTINGS_RENDER_SCALE_DEFAULT := 1.0
const SETTINGS_UI_SCALE_DEFAULT := 1.0
const SETTINGS_BRIGHTNESS_MIN := 0.8
const SETTINGS_BRIGHTNESS_MAX := 1.4
const SETTINGS_BRIGHTNESS_STEP := 0.02
const SETTINGS_BRIGHTNESS_DEFAULT := 1.0
const SETTINGS_BRIGHTNESS_TEST_BARS := 8
const SETTINGS_FOV_MIN := CAMERA_FOV_MIN
const SETTINGS_FOV_MAX := CAMERA_FOV_MAX
const SETTINGS_FOV_DEFAULT := CAMERA_FOV_DEFAULT
const SETTINGS_FOV_STEP := 1
const SETTINGS_HEAD_BOB_DEFAULT := 1.0              # 0 to 1
const SETTINGS_SHAKE_DEFAULT := 1.0                 # 0 to 1
const SETTINGS_SENS_STEP := 0.01
const SETTINGS_AUDIO_MASTER_DEFAULT := 80           # 0 to 100
const SETTINGS_AUDIO_EFFECTS_DEFAULT := 100
const SETTINGS_AUDIO_AMBIENCE_DEFAULT := 100
const SETTINGS_AUDIO_MUSIC_DEFAULT := 80
const SETTINGS_AUDIO_UI_DEFAULT := 80
const SETTINGS_AUDIO_MIN := 0
const SETTINGS_AUDIO_MAX := 100
const SETTINGS_MUTE_UNFOCUSED_DEFAULT := true
const SETTINGS_FLICKER_INTENSITY_MIN := 0.3
const SETTINGS_FLICKER_INTENSITY_MAX := 1.0
const SETTINGS_FLICKER_INTENSITY_DEFAULT := 1.0
const SETTINGS_TEXT_SIZE_DEFAULT := 1.0
const SETTINGS_PRESET_DEFAULT := &"medium"
const SETTINGS_SHADOW_QUALITY: Dictionary = {
	&"off": {&"atlas": 0, &"shadowed": 0},
	&"low": {&"atlas": 2048, &"shadowed": 0},
	&"medium": {&"atlas": 4096, &"shadowed": 2},
	&"high": {&"atlas": 8192, &"shadowed": 4},
}
const SETTINGS_WINDOW_MODES: Array[StringName] = [&"fullscreen", &"exclusive_fullscreen", &"windowed"]   # default: fullscreen
const SETTINGS_VSYNC_MODES: Array[StringName] = [&"off", &"on", &"adaptive"]                              # default: on
const SETTINGS_UPSCALING_MODES: Array[StringName] = [&"bilinear", &"fsr2"]                               # default: fsr2 (only below render scale 1.0)
const SETTINGS_AA_MODES: Array[StringName] = [&"off", &"fxaa", &"taa", &"msaa2x", &"msaa4x"]             # default: taa
const SETTINGS_CROSSHAIR_MODES: Array[StringName] = [&"off", &"dot", &"dot_ring"]                        # default: dot_ring
const SETTINGS_HUD_MODES: Array[StringName] = [&"full", &"minimal", &"off"]                              # default: full
const SETTINGS_VOLUMETRIC_FOG_MODES: Array[StringName] = [&"off", &"low", &"high"]                       # default: low
const SETTINGS_BINDING_SLOTS := 2                   # primary and secondary
const SETTINGS_FOV_HFOV_TO_VFOV_NUM := 9.0          # vfov = 2 atan(tan(hfov/2) x 9/16)
const SETTINGS_FOV_HFOV_TO_VFOV_DEN := 16.0
const SETTINGS_FLICKER_REDUCED_PULSE_HZ := 2.0      # Flicker's tell at intensity 0.3
const SETTINGS_REDUCE_FLASHING_FADE_MS := LIGHT_FLICKER_REDUCED_FADE_MS


# =====================================================================================
# 13  Save data and meta
# =====================================================================================
const META_FILE := "user://meta.json"
const META_FILE_TMP := "user://meta.json.tmp"
const META_FILE_BAD := "user://meta.json.bad"
const META_VERSION := 1
const META_DEPTH_MIN := 1                           # validated depth 1 to 999
const META_DEPTH_MAX := 999
const META_CODEX_FIRST_NOTICE := 1                  # name and silhouette glyph
const META_CODEX_COUNTER_LINE := UNLOCK_CODEX_ENCOUNTERS
const META_DAILY_ATTEMPTS_PER_DAY := 1
const META_TELEMETRY_DIR := "user://run_telemetry"
const META_SCREENSHOT_DIR := "user://screenshots"


# =====================================================================================
# 14  Technical architecture (budgets and physics layers)
# =====================================================================================
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ERRORS := 3
const LAYER_INTERACTABLE := 4
const LAYER_ITEMS := 5
const LAYER_HIDE_SPOTS := 6
const LAYER_WATER := 7
const LAYER_THROWN := 8
const BUDGET_DRAW_CALLS := 1500
const BUDGET_ACTIVE_LIGHTS := 24
const BUDGET_SHADOWED_LIGHTS := 4                   # plus the flashlight
const BUDGET_NODES_PER_LEVEL := 3000
const BUDGET_ERRORS_SCRIPT_MS := 0.3                # total per frame
const BUDGET_SCRIPT_MS := 2.5
const BUDGET_PHYSICS_MS := 2.0
const BUDGET_RENDER_MS := 10.0
const BUDGET_VRAM_GB := 1.5
const BUDGET_STARTUP_S := 4.0
const SCRIPT_MAX_LINES := 400                       # 14 §6: scripts over 400 lines are split
const FUNCTION_MAX_LINES := 60
