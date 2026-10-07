extends SceneTree
## Writes game/default_bus_layout.tres from AudioBuses (the 03 §3 bus tree), so the editor
## and the first frame of the game see the same buses AudioManager would build.
##   $GODOT_BIN --headless --path game --script ../tools/audio/make_bus_layout.gd

const OUT := "res://default_bus_layout.tres"


func _initialize() -> void:
	AudioBuses.ensure()
	var err := ResourceSaver.save(AudioServer.generate_bus_layout(), OUT)
	if err != OK:
		push_error("make_bus_layout: could not save %s (%s)" % [OUT, error_string(err)])
	else:
		print("make_bus_layout: wrote %s (%d buses)" % [OUT, AudioServer.bus_count])
	quit(0 if err == OK else 1)
