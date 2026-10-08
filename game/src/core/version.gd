class_name Version
extends RefCounted
## The single source of the build version (16 §1). The title shows it; project.godot's
## application/config/version mirrors it (the Windows file and product version come from
## there; tests/unit/test_export_presets.gd checks they match); tools/ci/export.sh reads it
## from this file to name the zips.

const VERSION := "1.0.0"
