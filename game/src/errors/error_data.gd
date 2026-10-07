class_name ErrorData
extends Resource
## Static definition of one of the five errors (08 §1) plus its Archive codex memo.
## Runtime state lives on ErrorBase; this resource is never mutated.

@export var id: StringName = &""
@export var display_name: String = ""
## The four columns of the law of errors (08 §1): rule, counter, tell, cost. One each.
@export_multiline var rule: String = ""
@export_multiline var counter: String = ""
@export_multiline var tell: String = ""
@export_multiline var cost: String = ""
## Coherence taken on contact (Still 35, Flicker 30, Echo 25). 0 for fields.
@export var contact_cost: float = 0.0
## Coherence per second inside the field (Static 4, Null 12 in its 2 m core). 0 otherwise.
@export var drain_per_second: float = 0.0
## Stratum that teaches this error (05 §3). Empty for Static (every stratum).
@export var native_stratum: StringName = &""
## Archive codex counter line, a builder memo (08 §3 to §7).
@export_multiline var codex_text: String = ""
## Encounters (noticed_player) before the codex shows the counter line (05 §6).
@export var codex_encounters: int = 3
## Archive glyph name (04 §5): wave, eye, bolt, steps, null.
@export var glyph_name: StringName = &""
