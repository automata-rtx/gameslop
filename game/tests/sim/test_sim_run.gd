extends TestCase
## Simulated playtest in the gate (M1.8, R8): the explorer bot plays depth 1 of real runs
## (run.tscn, the Director and its errors active) for three seeds at time scale 1. The sims
## run in a child engine started with `--fixed-fps 60` (1/60 s per step, as in play, but
## not synced to the wall clock), so ~10 minutes of play fit in the gate's budget. Each run
## stops once the Director has entered Relief (or at 200 s).
## Asserts: over the three seeds the Director visits Peak and Relief; every run starts in
## Calm and follows the sawtooth order; the contact log (each error's own
## `contacted_player`, not the Director's counter) keeps 3 s between contacts and 20 s
## between two contacts by the same error (05 §9 rules 4 and 5); every contact follows a
## chase and none lands in Relief; Static spawns; no run gets stuck.
## `test_contact_check_can_fail` proves the contact check catches violations.

const SEEDS := 3
const MAX_SECONDS := 200.0
## Per process: user:// is shared by every checkout and every gate running at once.
const JSON_PATH := "user://sim_gate_%d.json"


func _run_sims() -> Array:
	var json := ProjectSettings.globalize_path(JSON_PATH % OS.get_process_id())
	if FileAccess.file_exists(json):
		DirAccess.remove_absolute(json)
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/sim/sim_run.gd", "--", "--seeds", str(SEEDS), "--profiles", "explorer",
		"--depths", "1", "--stop-after-relief", "--max-seconds", str(MAX_SECONDS), "--json", json])
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	if code != 0:
		# Keep the child's last lines so an intermittent crash explains itself in the gate log.
		var lines := "\n".join(out).split("\n")
		for i in range(maxi(0, lines.size() - 60), lines.size()):
			print("  | " + lines[i])
	assert_eq(code, 0, "the sim engine exits cleanly")
	for chunk: String in out:
		for line in chunk.split("\n"):
			if line.begins_with("sim-run") or line.begins_with("|"):
				print("  # %s" % line)
	var text := FileAccess.get_file_as_string(json)
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Array, "the sim engine wrote its results (%d bytes)" % text.length())
	DirAccess.remove_absolute(json)
	return parsed if parsed is Array else []


func test_explorer_drives_the_sawtooth_on_real_levels() -> void:
	var results := _run_sims()
	assert_eq(results.size(), SEEDS, "one result per seed")
	var peaks := 0
	var reliefs := 0
	var next := {
		"calm": ["build"], "build": ["peak", "relief"], "peak": ["relief"], "relief": ["build"],
	}
	for r: Dictionary in results:
		var tag := "seed %d" % int(r.get("seed", -1))
		assert_false(r.has("error"), "%s: %s" % [tag, r.get("error", "")])
		assert_true(String(r.get("outcome", "")) != "stuck", "%s: the bot was never stuck for 30 s" % tag)
		assert_approx(float(r.get("physics_dt", 0.0)), 1.0 / 60.0, 0.0002, "%s: time scale 1" % tag)
		var phases: Array = r.get("phases", [])
		assert_true(not phases.is_empty() and phases[0] == "calm", "%s: Calm first" % tag)
		for i in range(1, phases.size()):
			assert_true((next[phases[i - 1]] as Array).has(phases[i]), "%s: %s -> %s" % [tag, phases[i - 1], phases[i]])
		var pc: Dictionary = r.get("phase_counts", {})
		peaks += int(pc.get("peak", 0))
		reliefs += int(pc.get("relief", 0))
		var log: Array = r.get("contact_log", [])
		assert_eq(SimBot.contact_violations(log).size(), 0, "%s: %s" % [tag, SimBot.contact_violations(log)])
		assert_eq(int(r.get("contacts", -1)), log.size(), "%s: the Director approved exactly the logged contacts" % tag)
		assert_true(int(r.get("telemetry_rows", 0)) > 10, "%s: telemetry rows" % tag)
		# M1.13 rulings: a contact follows a chase, and Relief is space (no contact in it).
		assert_eq(int(r.get("contacts_unchased", -1)), 0, "%s: every contact followed a chase" % tag)
		assert_eq(int(r.get("contacts_in_relief", -1)), 0, "%s: no contact in Relief" % tag)
		assert_true(bool(r.get("has_static", false)), "%s: Static spawned" % tag)
	assert_gt(peaks, 0, "the Director reached Peak on a real level")
	assert_gt(reliefs, 0, "and Relief after it")


## The contact check is not vacuous: a log breaking either rule is reported.
func test_contact_check_can_fail() -> void:
	assert_eq(SimBot.contact_violations([]).size(), 0)
	var fine := [[10.0, "still", 1], [13.0, "still", 2], [30.0, "still", 1]]
	assert_eq(SimBot.contact_violations(fine).size(), 0, "3 s apart, 20 s for the same error")
	var close := [[10.0, "still", 1], [12.5, "still", 2]]
	assert_eq(SimBot.contact_violations(close).size(), 1, "2.5 s apart breaks the 3 s exclusivity")
	var again := [[10.0, "still", 1], [25.0, "still", 1]]
	var v := SimBot.contact_violations(again)
	assert_eq(v.size(), 1, "the same error 15 s later breaks Satiated")
	assert_true(v[0].begins_with("satiated"))
	var both := [[10.0, "still", 1], [11.0, "still", 1]]
	assert_eq(SimBot.contact_violations(both).size(), 2, "both rules at once")


## M2.7 report helpers: the longest stretch without a decision (00 §5) and contacts that land
## within 5 s after a scare (pillar 3).
func test_decision_gap_and_scare_contact_helpers() -> void:
	assert_approx(SimBot.max_gap([], 90.0), 90.0, 0.001, "no decision: the whole run")
	assert_approx(SimBot.max_gap([10.0, 30.0, 100.0], 120.0), 70.0, 0.001)
	assert_approx(SimBot.max_gap([50.0, 5.0], 60.0), 45.0, 0.001, "unsorted input")
	assert_eq(SimBot.scare_contacts([], [10.0]), 0)
	assert_eq(SimBot.scare_contacts([10.0, 60.0], [12.0, 30.0, 64.9, 70.0]), 2, "12 and 64.9 follow a scare")
	assert_eq(SimBot.scare_contacts([10.0], [9.0]), 0, "a contact before the scare does not count")
