class_name NoclipMotion
extends RefCounted
## The body's motion for a committed noclip (06 §8 steps 2 and 3), owned by
## NoclipTargeting: the 250 ms wall pass with world collision off, where it ends (never
## inside geometry), and the drop's fall into black with the body out of the world.
## The pass eases sine in-out, so the wall crossing falls mid-pass, when the world shader
## draws geometry within 3 m as lines (02 §5, 11 §2).

const PASS_TIME := Tuning.NOCLIP_PASS_TIME_MS / 1000.0

var from: Vector3
var to: Vector3
## Seconds into the pass.
var t: float = 0.0
## The locked aim the landing came from: a blocked landing is looked for again there.
var point: Vector3
var normal: Vector3
var aim: Vector3
var ref_y: float = 0.0
var far: Dictionary = {}
## Seconds into the fall, and the floor it started from (the fall stops 2 m below it).
var fall_t: float = 0.0
var fall_floor_y: float = 0.0
var fall_pitch: float = 0.0

var _p: Player
var _world_off: bool = false
var _layer_off: bool = false
var _saved_layer: int = 0


func _init(player: Player) -> void:
	_p = player


# --- pass ---------------------------------------------------------------------------------

## Starts a pass from the body's position to `locked`'s landing (a NoclipQuery result).
func begin_pass(locked: Dictionary, aim_dir: Vector3) -> void:
	from = _p.global_position
	to = locked[&"landing"]
	t = 0.0
	point = locked[&"point"]
	normal = locked[&"normal"]
	aim = aim_dir
	ref_y = float(locked.get(&"far_floor_y", from.y))
	far = {&"has_cell": bool(locked.get(&"has_far_cell", false)), &"cell": locked.get(&"far_cell", Vector2i.ZERO)}
	set_world_collision(false)


## One frame of the pass; true when the pass time is over.
func pass_frame(delta: float) -> bool:
	t = minf(t + delta, PASS_TIME)
	_p.velocity = Vector3.ZERO
	_p.global_position = from.lerp(to, ease_pass(t / PASS_TIME))
	return t >= PASS_TIME


## 0..1 position along the pass at time fraction `x`: sine in-out.
static func ease_pass(x: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(x, 0.0, 1.0))


## Where the pass ends: the found spot if still free, else a spot found again in the
## landing cell (along the same aim, then the cell centre), else null (back to the start).
func landing_now() -> Variant:
	var space := _p.get_world_3d().direct_space_state
	var shape := _p.collision.shape
	var ex: Array[RID] = [_p.get_rid()]
	if NoclipQuery.is_free(space, to, shape, ex):
		return to
	var again: Variant = NoclipQuery.find_landing(space, point, normal, aim, ref_y, shape, ex, far)
	if again != null:
		return again
	if bool(far.get(&"has_cell", false)):
		var c: Vector2i = far[&"cell"]
		var centre := Vector3(c.x * Tuning.GRID_CELL_SIZE, ref_y, c.y * Tuning.GRID_CELL_SIZE)
		var fy: Variant = NoclipQuery.floor_under(space, centre, ex)
		if fy != null:
			var origin := Vector3(centre.x, float(fy) + Tuning.NOCLIP_LANDING_LIFT, centre.z)
			if NoclipQuery.is_free(space, origin, shape, ex):
				return origin
	return null


## Puts the body down at `at` with collision back on.
func land(at: Vector3) -> void:
	_p.global_position = at
	_p.velocity = Vector3.ZERO
	set_world_collision(true)


## A pass interrupted (the player dissolved mid-pass): snap to whichever of the pass end
## and start is free, so the body never rests inside geometry.
func snap_free() -> void:
	var space := _p.get_world_3d().direct_space_state
	var free_end := NoclipQuery.is_free(space, to, _p.collision.shape, [_p.get_rid()])
	land(to if free_end else from)


# --- fall -----------------------------------------------------------------------------------

## Starts the drop's fall: world collision off and the body off every layer, so nothing
## (an exit trigger, an error's contact area) can take the falling player.
func begin_fall() -> void:
	fall_t = 0.0
	fall_pitch = 0.0
	fall_floor_y = _p.global_position.y
	set_world_collision(false)
	set_body_layer(false)


## One frame of the fall: gravity into the floor, clamped NOCLIP_FALL_CLAMP_BELOW under
## it, the camera pitching down 10 deg over the fall time.
func fall_frame(delta: float) -> void:
	fall_t += delta
	_p.velocity = Vector3.ZERO
	var y := _p.global_position.y - Tuning.PLAYER_GRAVITY * fall_t * delta
	_p.global_position.y = maxf(y, fall_floor_y - Tuning.NOCLIP_FALL_CLAMP_BELOW)
	var want := minf(fall_t / Tuning.NOCLIP_FLOOR_FALL_TIME, 1.0) * Tuning.FEEDBACK_NOCLIP_FALL_PITCH_DEG
	_p.rig.add_pitch(-deg_to_rad(want - fall_pitch))
	fall_pitch = want


func end_fall() -> void:
	set_world_collision(true)
	set_body_layer(true)
	_p.rig.reset_pitch()


## The debug drop arrival (no run flow connected): back at `home`, with 11 §3's arrival
## (black to the world over 400 ms, sub settle, 0.3 trauma) and 11 §2's
## `DROPPED · THEY ARE AWAKE` on a HUD bound to this player.
func debug_arrive(home: Transform3D) -> void:
	_p.global_transform = home
	_p.velocity = Vector3.ZERO
	end_fall()
	CoherenceRenderer.pulse(&"drop")
	_p.sounds.play(&"drop_arrival")
	_p.rig.add_trauma(Tuning.FEEDBACK_ARRIVAL_DROP_TRAUMA)
	if _p.is_inside_tree():
		for n in _p.get_tree().root.find_children("*", "Control", true, false):
			if n is Hud and (n as Hud).player == _p:
				(n as Hud).notify(Strings.MSG_DROPPED)


# --- collision ------------------------------------------------------------------------------

## World collision off for the pass and the fall (06 §8 step 2); back on afterwards.
func set_world_collision(on: bool) -> void:
	if on == _world_off:
		_world_off = not on
		_p.collision_mask = (_p.collision_mask | PlayerLayers.WORLD_MASK) if on else (_p.collision_mask & ~PlayerLayers.WORLD_MASK)


## The body's own layer off while dropping; restored as it was.
func set_body_layer(on: bool) -> void:
	if on and _layer_off:
		_layer_off = false
		_p.collision_layer = _saved_layer
	elif not on and not _layer_off:
		_layer_off = true
		_saved_layer = _p.collision_layer
		_p.collision_layer = 0


func restore() -> void:
	set_world_collision(true)
	set_body_layer(true)
