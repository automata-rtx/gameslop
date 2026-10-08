class_name LevelGenerator
extends RefCounted
## Entry point of level generation (07 Interfaces). Worker-thread safe: no nodes, no
## autoloads, only the static Tuning and Seeds and freshly made data. Runs the stratum's
## grammar, validates (07 §8), retries with every sub-seed + 1 up to 8 times, then falls
## back to the stratum's simplest grammar (07 §1 rule 5, 14 §12).

## Extra seeds the simplest grammar may try before giving up and shipping its best try.
const FALLBACK_TRIES := 32


## Grammar for a stratum id, or null while that grammar is not built yet.
static func grammar_for(stratum: StringName) -> StratumGenerator:
	match stratum:
		&"halls":
			return HallsGenerator.new()
		&"pools":
			return PoolsGenerator.new()
		&"garage":
			return GarageGenerator.new()
	return null


static func supports(stratum: StringName) -> bool:
	return grammar_for(stratum) != null


## Generates a validated level. The level seed is
## Seeds.for_depth(run_seed, depth). `options` keys are listed on StratumGenerator.
## Returns null only for a stratum whose grammar does not exist.
static func generate(stratum: StringName, depth: int, run_seed: int, first_run: bool = false,
		cycle: int = 1, options: Dictionary = {}) -> LevelData:
	if not supports(stratum):
		push_error("LevelGenerator: no grammar for stratum '%s'" % stratum)
		return null
	for attempt in Tuning.LEVELGEN_RETRIES:
		var level := grammar_for(stratum).generate(stratum, depth, run_seed, first_run, cycle, options, attempt, false)
		level.failures = LevelValidator.validate(level)
		if level.failures.is_empty():
			return level
	var best: LevelData = null
	for k in FALLBACK_TRIES:
		var level := grammar_for(stratum).generate(stratum, depth, run_seed, first_run, cycle, options,
			Tuning.LEVELGEN_RETRIES + k, true)
		level.failures = LevelValidator.validate(level)
		if level.failures.is_empty():
			return level
		if best == null or level.failures.size() < best.failures.size():
			best = level
	push_error("LevelGenerator: %s depth %d seed %d failed validation: %s" % [stratum, depth, run_seed, best.failures])
	return best
