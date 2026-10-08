class_name FuseItem
extends ItemBase
## The Fuse belt item (09 §2). It is used at a fuse socket, not by the use_item key: a Variant B
## Breaker offers `[E] INSERT FUSE` while one is carried and takes it (Breaker.insert_fuse);
## `[E] PULL FUSE` gives it back. use_item with nothing to put it in is only the hand's dull
## nudge and a pitched-down tick (as chalk at nothing). Carried fuses persist across levels
## with the rest of the belt.

const SOUND_NOTHING := &"ui_hold_tick"
const NOTHING_PITCH := 0.7


func use(slot: ItemSlot) -> bool:
	if slot == null or slot.count <= 0:
		return false
	AudioManager.play_2d(SOUND_NOTHING, 0.0, NOTHING_PITCH)
	flick(Vector3(0.0, 0.0, -0.025), 0.06, 0.15)
	return false
