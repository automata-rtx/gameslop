class_name DirectorTelemetry
extends RefCounted
## 10 §9 telemetry: one row per second of Director time, kept in memory, written as CSV by
## `dump_csv(path)` for `tools/telemetry/plot.py`. Columns (10 §9's five plus four):
## time, intensity, phase, aggression, threat, nearest_hunter_d, coherence, chasing, scare
## (the 10 §5 scare kind that ran during that second, else empty). The sim runner writes one
## per level (`sim_run.gd --csv`); debug builds launched with `--telemetry` write one per level
## to user://run_telemetry/ when the Director ends (13 §1, `dump_debug`).

const HEADER := "time,intensity,phase,aggression,threat,nearest_hunter_d,coherence,chasing,scare"

var rows: PackedStringArray = []
## Seconds spent in each phase (sampled per row).
var phase_seconds: Dictionary = {}


func record(time_s: float, intensity: float, phase: StringName, aggression: float, threat: float,
		nearest_hunter_d: float, coherence: float, chasing: int, scare: StringName = &"") -> void:
	rows.append("%.1f,%.3f,%s,%.3f,%.3f,%s,%.1f,%d,%s" % [time_s, intensity, phase, aggression, threat,
		"" if is_inf(nearest_hunter_d) else "%.1f" % nearest_hunter_d, coherence, chasing, scare])
	phase_seconds[phase] = float(phase_seconds.get(phase, 0.0)) + Tuning.DIRECTOR_TELEMETRY_INTERVAL


func size() -> int:
	return rows.size()


func clear() -> void:
	rows.clear()
	phase_seconds.clear()


func to_csv() -> String:
	return HEADER + "\n" + "\n".join(rows) + ("\n" if not rows.is_empty() else "")


## Writes the CSV (user:// in builds, any path in tools). Returns the error code.
func dump_csv(path: String) -> Error:
	var dir := path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("DirectorTelemetry: cannot write %s" % path)
		return FileAccess.get_open_error()
	f.store_string(to_csv())
	f.close()
	return OK


## Debug builds launched with `--telemetry` (CliArgs): the level's CSV in
## user://run_telemetry/, named by level seed, depth and wall-clock time. Returns the path
## written, or "" when off (release builds, no flag, nothing recorded).
static func dump_debug(d: Director) -> String:
	if not OS.is_debug_build() or not CliArgs.current().telemetry or d.telemetry.size() == 0:
		return ""
	var seed_value := d.data.level_seed if d.data != null else 0
	var path := Tuning.META_TELEMETRY_DIR.path_join("level_%d_d%d_%d.csv" % [seed_value, d.depth, Time.get_unix_time_from_system()])
	return path if d.telemetry.dump_csv(path) == OK else ""
