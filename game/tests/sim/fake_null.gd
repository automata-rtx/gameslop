extends ErrorBase
## A stand-in for Null (M2.6 has no scene yet) for the Director's Pursuit tests: id `null`,
## no senses, no motion. Counts `pursue()` calls; `pursue()` puts it in Chase, as a woken
## Null hunting openly would be.

var pursued: int = 0


func _init() -> void:
	super()
	error_id = &"null"


func _ready() -> void:
	navigation_ready = true


func pursue() -> void:
	pursued += 1
	state = Tuning.ERROR_STATE_CHASE


func _process_error(_delta: float) -> void:
	pass
