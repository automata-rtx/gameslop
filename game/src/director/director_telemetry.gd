class_name DirectorTelemetry
extends RefCounted
## 10 §9 telemetry: one row per second of Director time, kept in memory, written as CSV by
## `dump_csv(path)` for `tools/telemetry/plot.py` (M2.7). Columns:
## time, intensity, phase, aggression, threat, nearest_hunter_d, coherence, chasing.

const HEADER := "time,intensity,phase,aggression,threat,nearest_hunter_d,coherence,chasing"

var rows: PackedStringArray = []
## Seconds spent in each phase (sampled per row).
var phase_seconds: Dictionary = {}


func record(time_s: float, intensity: float, phase: StringName, aggression: float, threat: float,
		nearest_hunter_d: float, coherence: float, chasing: int) -> void:
	rows.append("%.1f,%.3f,%s,%.3f,%.3f,%s,%.1f,%d" % [time_s, intensity, phase, aggression, threat,
		"" if is_inf(nearest_hunter_d) else "%.1f" % nearest_hunter_d, coherence, chasing])
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
