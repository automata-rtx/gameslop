class_name Seeds
extends RefCounted
## The one seed derivation function (05 §2, 07 §1, 13 §4).

## Derives a sub-seed from a base seed and a label, e.g. derive(run_seed, "depth:3").
static func derive(base: int, label: String) -> int:
	return hash(Tuning.SEED_DERIVE_FORMAT % [base, label])

## Seed for a depth inside a run.
static func for_depth(run_seed: int, depth: int) -> int:
	return derive(run_seed, Tuning.SEED_LABEL_DEPTH % depth)

## Daily Descent seed for a UTC date dictionary (Time.get_date_dict_from_system(true)).
static func daily(date: Dictionary) -> int:
	var ymd := "%04d%02d%02d" % [int(date.get("year", 1970)), int(date.get("month", 1)), int(date.get("day", 1))]
	return hash(Tuning.SEED_DAILY_PREFIX + ymd)

## Seeded RNG from a seed; the only way gameplay code gets randomness.
static func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r
