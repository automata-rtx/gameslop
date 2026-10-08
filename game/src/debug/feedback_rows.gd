class_name FeedbackRows
extends RefCounted
## The rows of the Feedback Contract (11 §2 player actions, §3 things that happen to the
## player) as data.
##   listed    the channels the table fills in (I S M R; a dash column is absent)
##   window    physics ticks watched after the trigger
##   lookback  per channel, ticks before the anchor a continuous channel may already be
##             moving (a step lands inside a walk, a hold's bar fills before its tick)
##   expect    per channel, substrings of the spy keys that count as the row's own feedback
##             (a sound id, a HUD part), so a coincidental change elsewhere can never pass
##             a row; a channel without an entry accepts any change
##   chained   continues the previous row's flow (the drop's arrival, the Landing): the bench
##             neither waits for quiet nor releases input before it
## Status: `implemented`; `pending` (the feature does not exist yet, with the reason); `gap`
## (implemented, but a listed channel is not wired today: the bench reports it, the test pins
## it, and the row is promoted to implemented when the game closes it).
##
## Minimum channels asserted per row: min(3, listed.size()). 11 §1 asks for three; the rows
## that list fewer (Crouch/Stand, Still within 8 m, Still observed, Unlock earned) are sparse
## on purpose or by the table (CHANGELOG 2026-10-07, pillar 3), and keep their own count.
## docs/qa/feedback_checklist.md is generated from these ids.

const IMPLEMENTED := &"implemented"
const PENDING := &"pending"
const GAP := &"gap"
const DEFAULT_WINDOW := 24

## Rows in the order the automatic sequence fires them. The order is load-bearing: the
## level-bound rows come first; the drop, the exit and the dissolve end the Descent and so
## come last.
static func all() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	# --- 11 §2 player actions, on foot ----------------------------------------------------
	rows.append(_row(&"walk_step", "Walk step", "11 §2", "ISM", {&"lookback": {&"I": 60, &"M": 60},
			&"expect": {&"S": ["play.foot_"]}}))
	rows.append(_row(&"sprint_start", "Sprint start", "11 §2", "ISMR",
			{&"expect": {&"S": ["loop.sprint_breath"], &"R": ["Stamina", "Crosshair"]}}))
	rows.append(_row(&"sprint_stop", "Sprint stop", "11 §2", "ISM",
			{&"expect": {&"S": ["loop.sprint_breath"]}}))
	rows.append(_row(&"stamina_empty", "Stamina empty", "11 §2", "SMR",
			{&"expect": {&"S": ["play.stamina_empty_gasp"], &"R": ["Stamina", "Crosshair"]}}))
	rows.append(_row(&"crouch", "Crouch", "11 §2", "SM", {&"expect": {&"S": ["play.crouch"]}}))
	rows.append(_row(&"stand", "Stand", "11 §2", "SM", {&"expect": {&"S": ["play.crouch"]}}))
	rows.append(_row(&"flashlight_on", "Flashlight on", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.flashlight_toggle"], &"R": ["Crank"]}}))
	rows.append(_row(&"flashlight_off", "Flashlight off", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.flashlight_toggle"], &"R": ["Crank"]}}))
	rows.append(_row(&"crank", "Crank (hold)", "11 §2", "ISMR",
			{&"expect": {&"S": ["loop.crank_loop", "loop.crank_whine"], &"R": ["Crank"]}}))
	rows.append(_row(&"crank_full", "Crank full", "11 §2", "ISR",
			{&"expect": {&"S": ["play.crank_full"], &"R": ["Crank"]}}))
	rows.append(_row(&"item_select", "Item select", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.ui_move"], &"R": ["Belt"]}}))
	rows.append(_row(&"item_polaroid", "Item use: Polaroid", "11 §2", "ISMR",
			{&"window": 90, &"expect": {&"S": ["play.polaroid_charge"]}}))
	rows.append(_row(&"item_glowstick", "Item use: Glowstick", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.glowstick_crack"], &"R": ["Belt"]}}))
	rows.append(_row(&"chalk_stamp", "Chalk stamp", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.chalk_mark"], &"R": ["Belt"]}}))
	rows.append(_row(&"item_flare", "Item use: Flare", "11 §2", "ISMR", {}, PENDING, "Flare lands with M2.8"))
	rows.append(_row(&"item_radio", "Item use: Radio", "11 §2", "ISMR", {}, PENDING, "Radio lands with M2.8"))
	# --- 11 §2 interaction and noclip -----------------------------------------------------
	rows.append(_row(&"interact_press", "Interact press", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.door_"], &"R": ["Prompt"]}}))
	rows.append(_row(&"interact_hold", "Interact hold", "11 §2", "ISR", {&"window": 30,
			&"lookback": {&"I": 20, &"R": 20}, &"expect": {&"S": ["play.ui_hold_tick"], &"R": ["Prompt"]}}))
	rows.append(_row(&"noclip_charge", "Noclip charge", "11 §2", "ISMR",
			{&"expect": {&"S": ["loop.noclip_charge"], &"R": ["Crosshair"]}}))
	rows.append(_row(&"noclip_cancel", "Noclip cancel", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.noclip_cancel"], &"R": ["Crosshair"]}}))
	rows.append(_row(&"noclip_invalid", "Noclip invalid", "11 §2", "ISR",
			{&"expect": {&"S": ["play.noclip_fail"], &"R": ["Crosshair"]}}))
	rows.append(_row(&"noclip_commit_wall", "Noclip commit (wall)", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.noclip_commit"], &"R": ["Coherence"]}}))
	rows.append(_row(&"hide_enter", "Enter hide spot", "11 §2", "ISR", {&"expect": {&"S": ["play.crouch"]}}))
	rows.append(_row(&"hide_leave", "Leave hide spot", "11 §2", "ISMR", {&"expect": {&"S": ["play.crouch"]}}))
	# --- 11 §3 things that happen to the player -------------------------------------------
	rows.append(_row(&"coherence_loss", "Coherence loss", "11 §3", "ISR",
			{&"expect": {&"S": ["play.coherence_loss_tick"], &"R": ["Coherence"]}}))
	rows.append(_row(&"coherence_gain", "Coherence gain", "11 §3", "ISMR",
			{&"expect": {&"S": ["play.coherence_gain"], &"R": ["Coherence"]}}))
	rows.append(_row(&"error_contact", "Error contact", "11 §3", "ISMR",
			{&"expect": {&"S": ["play.error_contact_hit"], &"R": ["Coherence"]}}))
	rows.append(_row(&"inside_static", "Inside Static", "11 §3", "ISMR", {&"window": 36,
			&"expect": {&"S": ["loop.static_hum", "loop.static_band"], &"R": ["Coherence"]}}))
	rows.append(_row(&"still_within_8m", "Still within 8 m", "11 §3", "SR", {&"window": 48,
			&"expect": {&"S": ["duck.Ambience"], &"R": ["Caption"]}}, GAP,
			"AudioManager emits EventBus.audio_cue ([silence]) but no HUD subscribes until the captions task (M2.12)"))
	rows.append(_row(&"still_observed", "Still observed 2 s", "11 §3", "IS",
			{&"expect": {&"I": ["still."], &"S": ["play.still_tick"]}}))
	rows.append(_row(&"flicker_lunge", "Flicker lunge", "11 §3", "ISMR", {}, PENDING, "Flicker lands with M2.5"))
	rows.append(_row(&"echo_4m", "Echo at 4 m", "11 §3", "ISR", {}, PENDING, "Echo lands with M2.4"))
	rows.append(_row(&"null_radius", "Null radius", "11 §3", "ISM", {}, PENDING, "Null lands with M2.6"))
	rows.append(_row(&"null_core", "Null core", "11 §3", "ISMR", {}, PENDING, "Null lands with M2.6"))
	rows.append(_row(&"exit_seen", "Exit seen", "11 §3", "ISR",
			{&"expect": {&"S": ["play.exit_latch"], &"R": ["Depth"]}}))
	rows.append(_row(&"breaker", "Breaker thrown by player", "11 §3", "ISMR", {&"window": 30,
			&"expect": {&"S": ["play.breaker_lever"]}}))
	rows.append(_row(&"exit_unlocked", "Exit unlocked", "11 §3", "ISR",
			{&"expect": {&"S": ["play.exit_open", "play.exit_latch"], &"R": ["Depth", "Notifications"]}}))
	rows.append(_row(&"note_found", "Note found", "11 §3", "ISR",
			{&"expect": {&"S": ["play.note_pickup"], &"R": ["NoteSheet", "Notifications"]}}))
	rows.append(_row(&"unlock_earned", "Unlock earned", "11 §3", "SR",
			{&"expect": {&"S": ["play.ui_unlock"], &"R": ["Notifications"]}}, GAP,
			"ui_unlock is in the audio manifest but nothing plays it; Hud._on_unlock_earned should call AudioManager.play_2d(&\"ui_unlock\")"))
	# --- the Descent: these end the level, so they run last ---------------------------------
	rows.append(_row(&"noclip_commit_floor", "Noclip commit (floor)", "11 §2", "ISMR",
			{&"expect": {&"S": ["play.noclip_commit"], &"R": ["Coherence"]}}))
	rows.append(_row(&"arrival_drop", "Arrival (drop)", "11 §3", "ISMR",
			{&"chained": true, &"expect": {&"S": ["play.drop_arrival"]}}))
	rows.append(_row(&"enter_exit", "Enter exit", "11 §3", "ISMR", {&"window": 20,
			&"expect": {&"S": ["play.exit_open"]}}))
	rows.append(_row(&"landing", "Landing", "11 §3", "ISMR",
			{&"chained": true, &"expect": {&"S": ["play.exit_latch", "loop.fixture_hum"]}}))
	rows.append(_row(&"arrival_proper", "Arrival (proper)", "11 §3", "ISR",
			{&"chained": true, &"expect": {&"S": ["play.exit_open"], &"R": ["Depth"]}}))
	rows.append(_row(&"dissolve", "Dissolve", "11 §3", "ISMR", {&"window": 36,
			&"expect": {&"S": ["play.dissolve"], &"R": ["Coherence"]}}))
	rows.append(_row(&"threshold", "Threshold crossed", "11 §3", "ISR", {}, PENDING, "the ending scene lands with M2.15"))
	return rows


static func _row(id: StringName, label: String, ref: String, listed: String, opts: Dictionary = {},
		status: StringName = IMPLEMENTED, reason: String = "") -> Dictionary:
	return {
		&"id": id,
		&"label": label,
		&"ref": ref,
		&"listed": listed,
		&"min": mini(3, listed.length()),
		&"status": status,
		&"reason": reason,
		&"window": int(opts.get(&"window", DEFAULT_WINDOW)),
		&"lookback": opts.get(&"lookback", {}),
		&"expect": opts.get(&"expect", {}),
		&"chained": bool(opts.get(&"chained", false)),
	}


## Rows the bench fires (implemented or gap).
static func active() -> Array[Dictionary]:
	return all().filter(func(r: Dictionary) -> bool: return r[&"status"] != PENDING)


static func pending() -> Array[Dictionary]:
	return all().filter(func(r: Dictionary) -> bool: return r[&"status"] == PENDING)


static func find(id: StringName) -> Dictionary:
	for r in all():
		if r[&"id"] == id:
			return r
	return {}
