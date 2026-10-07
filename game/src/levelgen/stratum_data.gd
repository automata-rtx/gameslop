class_name StratumData
extends Resource
## Everything that distinguishes one stratum (02 §7 look sheets, 03 reverb, 07 §5 grammar
## tuning). Interface (02): palettes, fixture prefab path and grid spacing, fog colour and
## density, ambient colour and energy, exposure, water presence, prop lists, shadow bias.
## Pattern modes (02 §5): 0 flat, 1 tiles, 2 stripes, 3 carpet, 4 concrete, 5 checker, 6 panel.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Depth and size")
## Depth range where the stratum may appear (01 §4, 05 §2).
@export var depth_min: int = 1
@export var depth_max: int = 1
## Room height in metres (07 §5). Garage: per deck.
@export var height: float = 3.0
## Garage has two decks; every other stratum one.
@export var decks: int = 1
## Grid side length in cells (square) per depth, one entry per depth in depth_min..depth_max
## (07 §2). Cycle 2 adds +2 to each dimension.
@export var grid_sizes: PackedInt32Array = PackedInt32Array()
## Walkable cell target per depth, same indexing (05 §2, 07 §2).
@export var walkable_cells: PackedInt32Array = PackedInt32Array()

@export_group("Walls")
## `*_pattern_scale` is the document's number as written: metres for stripes, tiles and
## panels; the noise scale for carpet and concrete.
@export var wall_color: Color = Color.WHITE
@export var wall_color_secondary: Color = Color.WHITE
@export var wall_pattern_mode: int = 0
@export var wall_pattern_scale: float = 1.0
@export var wall_roughness: float = 0.9
@export var wall_metallic: float = 0.0
@export var wall_normal_strength: float = 0.0

@export_group("Floor")
@export var floor_color: Color = Color.WHITE
@export var floor_color_secondary: Color = Color.WHITE
@export var floor_pattern_mode: int = 0
@export var floor_pattern_scale: float = 1.0
@export var floor_roughness: float = 0.9

@export_group("Ceiling")
@export var ceiling_color: Color = Color.WHITE
@export var ceiling_pattern_mode: int = 0
@export var ceiling_pattern_scale: float = 0.6
@export var ceiling_roughness: float = 0.9

@export_group("Partition")
## Offices cubicle fabric. Unused elsewhere.
@export var partition_color: Color = Color.WHITE
@export var partition_pattern_mode: int = 0
@export var partition_pattern_scale: float = 1.0

@export_group("Fixture")
## tube, panel, sodium_lamp, troffer, emergency_box, or none (Substrate).
@export var fixture_kind: StringName = &"none"
## Scene path of the fixture prefab. The prefabs are authored by the lighting task; the
## path is the contract.
@export var fixture_prefab_path: String = ""
## Metres between fixtures on the stratum's exact grid (T2).
@export var fixture_spacing_m: float = 4.0
@export var fixture_emission_color: Color = Color.WHITE
@export var fixture_emission_strength: float = 8.0
@export var fixture_light_color: Color = Color.WHITE
@export var fixture_light_energy: float = 1.0
@export var fixture_light_range: float = 7.0
## Substrate studio lights (02 §7); 0 elsewhere.
@export var studio_light_energy: float = 0.0
@export var studio_light_range: float = 0.0

@export_group("Atmosphere")
@export var fog_color: Color = Color.BLACK
## Volumetric fog density.
@export var fog_density: float = 0.0
## Distance fog to black. Both 0 = unused (Substrate: 25 to 45 m).
@export var distance_fog_begin: float = 0.0
@export var distance_fog_end: float = 0.0
@export var ambient_color: Color = Color.BLACK
@export var ambient_energy: float = 0.1
@export var exposure: float = 1.0
## Tuned once per stratum by the render task; 0.05 is the placeholder.
@export var shadow_bias: float = 0.05

@export_group("Water")
@export var has_water: bool = false
@export var water_color: Color = Color(0, 0, 0, 0)

@export_group("Reverb")
## 03 §4: swapped per stratum on level load.
@export var reverb_room_size: float = 0.5
@export var reverb_damping: float = 0.5
@export var reverb_wet: float = 0.2
@export var reverb_predelay_ms: float = 0.0
## High-pass on the reverb return in Hz; 0 = none (Substrate 300).
@export var reverb_highpass_hz: float = 0.0

@export_group("Content")
## Props the generator may place in this stratum (09 §7). Shared props are not repeated.
@export var prop_ids: Array[StringName] = []
@export var hide_spot_kinds: Array[StringName] = []
## Exit prefab kind (07 §5) and the Landing cabin shown on leaving (05 §4).
@export var exit_kind: StringName = &""
@export var landing_kind: StringName = &""
## The stratum's teaching error (05 §3). Empty: Halls (Static) and Server (a hunter met earlier).
@export var native_error: StringName = &""
## Soft walls per level (07 §5).
@export var soft_wall_count: int = 0

func contains_depth(depth: int) -> bool:
	return depth >= depth_min and depth <= depth_max

## Walkable cell target for a depth in this stratum's range; 0 outside it.
func walkable_target(depth: int) -> int:
	if not contains_depth(depth) or depth - depth_min >= walkable_cells.size():
		return 0
	return walkable_cells[depth - depth_min]

## Grid side length in cells for a depth in range (before the Cycle 2 +2); 0 outside it.
func grid_size(depth: int) -> int:
	if not contains_depth(depth) or depth - depth_min >= grid_sizes.size():
		return 0
	return grid_sizes[depth - depth_min]
