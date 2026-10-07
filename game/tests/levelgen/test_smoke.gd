extends TestCase
## 14 §9 --smoke: boots main.tscn headless, generates and builds depth 1, runs 2 s, quits 0.
## Runs the engine as a child process (the export smoke test does the same).

const MAX_FPS := 120
const MAX_FRAMES := 3600


func test_smoke_exits_zero() -> void:
	var out: Array = []
	var t0 := Time.get_ticks_msec()
	var code := OS.execute(OS.get_executable_path(),
		PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			# A broken build must not hang the gate: at most MAX_FRAMES frames at MAX_FPS.
			"--max-fps", str(MAX_FPS), "--quit-after", str(MAX_FRAMES), "--", "--smoke"]), out, true)
	var log := "\n".join(PackedStringArray(out))
	assert_eq(code, 0, "smoke exit code")
	assert_false(log.contains("SCRIPT ERROR"), "no script errors in the smoke run")
	assert_false(log.contains("did not build"), "depth 1 built")
	assert_true(log.contains("smoke: ok"), "the smoke run reached its end (not the frame cap)")
	print("  # smoke: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
