extends "res://tests/levelgen/test_level_builder_strata.gd"
## The LevelBuilder integration checks on a Garage level (M2.1): decks, ramps, navigation
## across a ramp, noclip on deck 1. The tests live in test_level_builder_strata.gd.


func stratum() -> StringName:
	return &"garage"
