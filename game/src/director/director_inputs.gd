class_name DirectorInputs
extends RefCounted
## The Director's listeners (10 Interfaces: "listens to"), split out of Director (14 §6
## 400-line limit, M2.7): EventBus noise, notes, breaker and exit status; the Player's
## Coherence and noclip commits; the Flashlight's crank tick; the level Exit's `seen`. Each
## feeds DirectorPacing's 10 §2 rows. Also the 06 §8 wall-pass sight check.

var director: Director
var _los_check_at: float = -1.0
var _los_chasers: Array[ErrorBase] = []
var _exit: Node
var _flashlight: Node


func _pacing() -> DirectorPacing:
	return director.pacing


func connect_all() -> void:
	var d := director
	var player := d.player
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.note_found.connect(_on_note)
	EventBus.breaker_thrown.connect(_on_breaker)
	EventBus.exit_status_changed.connect(_on_exit_status)
	if player != null:
		player.coherence_changed.connect(_on_coherence)
		if player.has_signal(&"noclip_committed"):
			player.noclip_committed.connect(_on_noclip_committed)
		# 10 §2 crank row (per 0.5 s): the Flashlight's own tick, not a radius match.
		_flashlight = player.get(&"flashlight") as Node
		if _flashlight != null and _flashlight.has_signal(&"crank_tick"):
			_flashlight.connect(&"crank_tick", _on_crank_tick)
	_exit = null
	if d.level != null and d.is_inside_tree():
		for n in d.get_tree().get_nodes_in_group(&"exits"):
			if d.level.is_ancestor_of(n) and n.has_signal(&"seen"):
				_exit = n
				n.connect(&"seen", _on_exit_seen)
				break


func disconnect_all() -> void:
	for pair: Array in [[EventBus.noise_emitted, _on_noise], [EventBus.note_found, _on_note],
			[EventBus.breaker_thrown, _on_breaker], [EventBus.exit_status_changed, _on_exit_status]]:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	var player := director.player
	if player != null and is_instance_valid(player):
		if player.coherence_changed.is_connected(_on_coherence):
			player.coherence_changed.disconnect(_on_coherence)
		if player.noclip_committed.is_connected(_on_noclip_committed):
			player.noclip_committed.disconnect(_on_noclip_committed)
	if _flashlight != null and is_instance_valid(_flashlight) and _flashlight.is_connected(&"crank_tick", _on_crank_tick):
		_flashlight.disconnect(&"crank_tick", _on_crank_tick)
	_flashlight = null
	if _exit != null and is_instance_valid(_exit) and _exit.is_connected(&"seen", _on_exit_seen):
		_exit.disconnect(&"seen", _on_exit_seen)
	_exit = null


## Only the player's own sprint steps count here; the crank (the Flashlight's
## `crank_tick`), the breaker and the noclip commit arrive by their own signals.
func _on_noise(pos: Vector3, _radius: float, kind: StringName) -> void:
	var player := director.player
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	if pos.distance_to(player.global_position) > Tuning.DIRECTOR_PLAYER_NOISE_DIST:
		return
	if kind == Tuning.NOISE_KIND_STEP and player.state_machine.is_in(PlayerStateMachine.SPRINT):
		_pacing().on_sprint_step()


## One crank noise tick (every 0.5 s while the wheel turns): +0.10.
func _on_crank_tick() -> void:
	_pacing().on_crank()


func _on_note(_id: StringName) -> void:
	_pacing().on_note()


func _on_breaker(_pos: Vector3) -> void:
	_pacing().on_breaker()


func _on_coherence(value: float, _delta: float, _source: StringName) -> void:
	_pacing().on_coherence(value)


func _on_exit_seen() -> void:
	_pacing().on_exit_seen()


## Without an Exit node (benches), the first status announcement stands in for "seen".
func _on_exit_status(_status: StringName, _timer: float) -> void:
	if _exit == null:
		_pacing().on_exit_seen()


func _on_noclip_committed(target: StringName, _from: Vector3, _to: Vector3) -> void:
	_pacing().on_noclip_commit()
	if target == NoclipQuery.TARGET_FLOOR:
		return
	_los_chasers = director.hunters.chasers()
	if not _los_chasers.is_empty():
		_los_check_at = director.now() + Tuning.DIRECTOR_NOCLIP_LOS_CHECK_DELAY


## 06 §8, 10 §2: a wall pass that broke every chaser's sight lowers intensity.
func noclip_los_check() -> void:
	if _los_check_at < 0.0 or director.now() < _los_check_at:
		return
	_los_check_at = -1.0
	for e in _los_chasers:
		if is_instance_valid(e) and e.senses != null and e.senses.sees_player:
			_los_chasers.clear()
			return
	_los_chasers.clear()
	_pacing().on_noclip_broke_los()
