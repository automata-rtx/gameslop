class_name AudioCull
extends RefCounted
## Distance culling for ambient prop loops (M3.5, 14 §10). A Server level hangs about 36
## fan grilles, each with a looping AudioStreamPlayer3D; a playing 3D player costs an
## internal physics step on the main thread and a mix on the audio thread even past its
## max_distance, where it is silent. A loop marked here stops while the listener is farther
## than its max_distance plus CULL_MARGIN and starts again when the listener comes back
## inside that ring, so nothing audible changes: the margin is more than a sprint covers
## between two passes (AudioManager runs this with the 0.2 s occlusion pass). Only loops
## whose owner never reads their playing state opt in (props: fans, vending machines).

const META := &"audio_distance_cull"
## True while this pass (not the owner) has the loop stopped.
const META_CULLED := &"audio_culled"
## Metres past max_distance before a loop stops (sprint 5.6 m/s x 0.2 s = 1.1 m).
const CULL_MARGIN := 3.0


## Marks `loop`'s player for distance culling (it needs a max_distance).
static func mark(loop: AudioLoop) -> void:
	if loop != null and loop.is_valid() and loop.player is AudioStreamPlayer3D:
		loop.player.set_meta(META, true)


static func is_culled(p: Node) -> bool:
	return bool(p.get_meta(META_CULLED, false))


## One pass over `players` (AudioStreamPlayer3D or freed): stop the marked ones out of
## reach, restart the ones this pass stopped once the listener is back in reach.
static func tick(players: Array, listener_pos: Vector3) -> void:
	for p: Variant in players:
		if not is_instance_valid(p):
			continue
		var p3 := p as AudioStreamPlayer3D
		if p3 == null or not bool(p3.get_meta(META, false)) or p3.max_distance <= 0.0 or not p3.is_inside_tree():
			continue
		var far := p3.global_position.distance_to(listener_pos) > p3.max_distance + CULL_MARGIN
		if far and p3.playing:
			p3.set_meta(META_CULLED, true)
			p3.stop()
		elif not far and is_culled(p3):
			p3.set_meta(META_CULLED, false)
			p3.play()
