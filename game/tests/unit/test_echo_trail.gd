extends TestCase
## 08 §6 Echo's trail as data (EchoTrail): the target is the entry 800 ms before the newest
## heard entry (not before now), it stops moving when no entry arrives, the trail starts at
## the earliest heard step of a window, heard steps take the player's recorded surface and
## speed kind, and the speeds mirror the player's.


func _walk_trail(n: int, dt: float) -> EchoTrail:
	var t := EchoTrail.new()
	for i in n:
		t.add(Vector3(0, 0, -0.55 * i), dt * i, &"tile", &"walk")
	return t


func test_target_is_800_ms_before_the_newest_heard_entry() -> void:
	var t := _walk_trail(12, 0.17)  # newest at 1.87 s
	var i := t.target_index()
	assert_eq(i, 6, "1.02 s is the last entry at or before 1.87 - 0.8")
	assert_true(t.newest_time() - float(t.entries[i][&"time"]) >= 0.8)
	assert_true(t.newest_time() - float(t.entries[i + 1][&"time"]) < 0.8)


func test_the_target_does_not_move_when_no_entry_arrives() -> void:
	var t := _walk_trail(12, 0.17)
	var i := t.target_index()
	# Time passes, nothing is heard: the target is relative to the newest entry, not now.
	assert_eq(t.target_index(), i)
	t.advance_to(i)
	assert_true(t.at_target(), "reached: it stands")
	t.add(Vector3(0, 0, -7), 2.04, &"tile", &"walk")
	assert_false(t.at_target(), "a new heard step moves the target on")


func test_early_trail_targets_the_earliest_heard_step() -> void:
	var t := _walk_trail(3, 0.17)
	assert_eq(t.target_index(), 0)
	assert_eq(EchoTrail.new().target_index(), -1)


func test_window_and_drop() -> void:
	var t := EchoTrail.new()
	for s: float in [0.0, 1.0, 6.0, 6.5, 7.0]:
		t.add(Vector3(s, 0, 0), s)
	assert_eq(t.count_since(7.0 - 5.0), 3)
	t.next_index = 3
	t.drop_before(2.0)
	assert_eq(t.size(), 3)
	assert_eq(t.next_index, 1, "the walker's index follows the drop")


func test_capacity_keeps_the_newest() -> void:
	var t := _walk_trail(Tuning.ECHO_TRAIL_CAPACITY + 5, 0.1)
	assert_eq(t.size(), Tuning.ECHO_TRAIL_CAPACITY)
	assert_approx(float(t.entries[0][&"time"]), 0.5, 0.0001)


func test_resolve_takes_the_players_surface_and_speed_kind() -> void:
	var rb := RingBuffer.new(64)
	rb.push({&"position": Vector3(1, 0, 1), &"time": 10.0, &"surface": &"water", &"speed_kind": &"sprint"})
	rb.push({&"position": Vector3(2, 0, 2), &"time": 10.2, &"surface": &"tile", &"speed_kind": &"crouch"})
	var t := EchoTrail.new()
	t.add(Vector3(1, 0, 1), 0.0)
	t.add(Vector3(9, 0, 9), 0.1)
	t.resolve(rb, &"carpet")
	assert_eq(t.entries[0][&"surface"], &"water")
	assert_eq(t.entries[0][&"speed_kind"], &"sprint")
	assert_eq(t.entries[1][&"surface"], &"carpet", "no match: the fallback surface")
	assert_eq(t.entries[1][&"speed_kind"], &"walk")


func test_speeds_mirror_the_player() -> void:
	assert_approx(EchoTrail.speed_for(&"walk"), 3.2, 0.0001)
	assert_approx(EchoTrail.speed_for(&"sprint"), 5.6, 0.0001)
	assert_approx(EchoTrail.speed_for(&"crouch"), 1.6, 0.0001)
