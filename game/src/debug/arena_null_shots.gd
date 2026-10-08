class_name ArenaNullShots
extends RefCounted
## The error arena's Null signature frames (02 §8, 02 §13), on a Substrate level (depth 6):
## null_20m (Null 20 m down a corridor: outside its 12 m radius, the grid tone only),
## null_8m (8 m: the world within 12 m of it goes to lines on black, fills dithered away,
## the halo), null_core (the camera inside the 2 m core: black with the grid halo).
## Null's own ticking is paused; the shots place it and feed the renderer.

const DISTANCES := {"null_20m": 20.0, "null_8m": 8.0, "null_core": 1.0}


static func capture(arena: ErrorArena, dir: String) -> void:
	var cor := arena._corridor(6)
	var cell: Vector2i = cor[0]
	var fwd := arena._pose_player(cell, cor[1])
	var p := arena.player
	p.flashlight.set_on(true, true)
	var e := arena.spawn(&"null", p.global_position + fwd * 30.0) as ErrorNull
	e.pursue()
	e.set_physics_process(false)
	for shot: String in DISTANCES:
		e.global_position = p.global_position + fwd * float(DISTANCES[shot])
		e._feed()
		await arena.shot(dir, shot)
	arena.free_error(e)
	CoherenceRenderer.set_null(CoherenceRenderer.NULL_POS_ABSENT, 0.0)
	p.rig.set_jitter(0.0)
