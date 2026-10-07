class_name PlayerLayers
extends RefCounted
## Physics layer bits the player uses (14 §7). Layer N is bit (N - 1).

const WORLD := 1
const PLAYER := 2
const ERRORS := 3
const INTERACTABLE := 4
const HIDE_SPOTS := 6
const WATER := 7

const WORLD_MASK := 1 << (WORLD - 1)
const PLAYER_MASK := 1 << (PLAYER - 1)
const INTERACTABLE_MASK := 1 << (INTERACTABLE - 1)
const HIDE_SPOTS_MASK := 1 << (HIDE_SPOTS - 1)
