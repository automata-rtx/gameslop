class_name SimBotItems
extends RefCounted
## The cautious bot's belt (M2.7): it picks up items a few cells off its way while no hunter
## is near, and uses the counters it has items for, all through the player's own keys (item
## keys 1 to 4 select, use_item taps or holds):
## - Polaroid: Coherence below 55 and nothing hunting near (+25).
## - Flare: Static's field sits on the only way and the bot has waited 2 s (09: a burning flare
##   pushes Static 6 m); it then walks on with the flare burning in hand.
## - Glowstick: thrown at a chasing Still within 12 m (09: lit area counts for observing it), or
##   thrown ahead as an impact lure while standing still for Echo (08 §6); once per 20 s.
## Every use the belt reports (EventBus.item_used) is a decision in the bot's log.

const POLAROID_BELOW := 55.0
const FLARE_WAIT := 2.0
const STILL_GLOW_DIST := 12.0
const GLOW_COOLDOWN := 20.0
const PICKUP_CELLS := 6
const PICKUP_HUNTER_CLEAR := 20.0

var bot: SimBot
var uses: Dictionary = {}
var pickups: int = 0
var _hold_left: float = 0.0
var _pending_kind: StringName = &""
var _pending_hold: float = 0.0
var _pending_frames: int = 0
var _glow_next: float = 0.0
var _skip: Dictionary = {}


func _player() -> Player:
	return bot.run.player


func _inv() -> Inventory:
	return _player().inventory


func has(kind: StringName) -> bool:
	return _inv().has(kind)


## True while a use is being keyed (the bot stands still meanwhile).
func busy() -> bool:
	return _pending_kind != &"" or _hold_left > 0.0 or _inv().is_busy()


## Selects `kind` (its item key) and then presses use_item for one frame (`hold` 0) or holds it.
func use(kind: StringName, hold: float = 0.0) -> bool:
	if busy() or not has(kind) or not _player().can_use_item():
		return false
	var slot := _inv().slot_of(kind)
	if _inv().selected != slot:
		bot.tap(StringName("item_%d" % (slot + 1)))
	_pending_kind = kind
	_pending_hold = hold
	_pending_frames = 2
	return true


## Every physics frame, before the bot moves.
func tick(dt: float) -> void:
	if _hold_left > 0.0:
		_hold_left -= dt
		if _hold_left <= 0.0:
			Input.action_release(&"use_item")
		return
	if _pending_kind == &"":
		return
	_pending_frames -= 1
	if _pending_frames > 0:
		return
	if _inv().selected_kind() == _pending_kind:
		uses[_pending_kind] = int(uses.get(_pending_kind, 0)) + 1
		if _pending_hold > 0.0:
			Input.action_press(&"use_item")
			_hold_left = _pending_hold
		else:
			bot.tap(&"use_item")
	_pending_kind = &""


## Polaroid when Coherence is low and nothing hunts near.
func maybe_polaroid(hunter_near: bool) -> bool:
	if hunter_near or _player().coherence >= POLAROID_BELOW:
		return false
	return use(&"polaroid")


## Static on the only way: strike a flare (it burns in hand and pushes the field).
func maybe_flare(field_wait: float) -> bool:
	if field_wait < FLARE_WAIT or not has(&"flare"):
		return false
	var slot := _inv().slots[_inv().slot_of(&"flare")] as ItemSlot
	if FlareItem.is_burning(slot):
		return false
	return use(&"flare")


## A chasing Still within 12 m (the bot faces it), or Echo following while the bot stands
## still: throw a glowstick (lit area for observation; an impact lure for Echo).
func maybe_glowstick(chaser: ErrorBase, chase_d: float) -> bool:
	if chaser == null or bot.time() < _glow_next or not has(&"glowstick"):
		return false
	var want := (chaser.error_id == &"still" and chase_d < STILL_GLOW_DIST) or chaser.error_id == &"echo"
	if not want:
		return false
	_glow_next = bot.time() + GLOW_COOLDOWN
	return use(&"glowstick")


## The nearest pickup within a few cells' walk that the belt can take, while no hunter is
## within 20 m; null otherwise.
func nearby_pickup() -> ItemPickup:
	var run := bot.run
	if bot.hunter_within(PICKUP_HUNTER_CLEAR):
		return null
	var grid := run.data.grid
	var walk := grid.distance_field(grid.cell_of(_player().global_position))
	var best: ItemPickup = null
	var best_w := PICKUP_CELLS + 1
	for n in bot.tree.get_nodes_in_group(ItemPickup.GROUP):
		var it := n as ItemPickup
		if it == null or it.picked or _skip.has(it.get_instance_id()) or not run.level.is_ancestor_of(it):
			continue
		if not it.can_take(_inv()):
			continue
		var c := grid.cell_of(it.global_position)
		if not grid.in_bounds(c):
			continue
		var w := walk[grid.idx(c)]
		if w >= 0 and w < best_w:
			best = it
			best_w = w
	return best


## Takes `it` when in reach. Returns true when it was taken (or given up on).
func take_in_reach(it: ItemPickup) -> bool:
	if it == null or DirectorSpawn.flat_dist(_player().global_position, it.global_position) >= SimBot.REACH:
		return false
	if it.interactable.can_interact(_player()):
		it.interactable.interact(_player())
	if it.picked:
		pickups += 1
	else:
		_skip[it.get_instance_id()] = true
	return true


## Releases any held key (run teardown).
func release() -> void:
	Input.action_release(&"use_item")
	_hold_left = 0.0
	_pending_kind = &""
