class_name NoteData
extends Resource
## One of the 36 lore sheets (01 §6). Text is copied verbatim from the design document.
## Interface (01): id, stratum, voice, tier, text.

## Voices: faller (handwritten), builder (RENDER NOTE memo), stray (found object),
## builder_final (the one note unlocked in the Archive).
const VOICES: Array[StringName] = [&"faller", &"builder", &"stray", &"builder_final"]
## Tier value for U6: Archive only, never placed in a level.
const TIER_ARCHIVE_ONLY := 3
## 01 §6: tier 1 can appear from the first run; tier 2 only once the stratum has been reached.
const TIER_FIRST_RUN := 1
const TIER_STRATUM_REACHED := 2

@export var id: StringName = &""
@export var stratum: StringName = &""
@export var voice: StringName = &"faller"
## 1 or 2 (01 §6), or TIER_ARCHIVE_ONLY for U6.
@export var tier: int = 1
@export_multiline var text: String = ""
