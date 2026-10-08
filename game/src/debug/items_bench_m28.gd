class_name ItemsBenchM28
extends RefCounted
## The M2.8 half of the items bench (09 §10): the rest of the items and interactables in the
## bench room (flare, radio, fuse and keycard pickups, a vending machine, a payphone, a card
## reader, a Variant B breaker, a car and a stand-in desk with their hide spots, a locker, a
## pump corner and a rack gap) and the screenshots that go with them (`-- --bench-shots <dir>`).

const CAR_SCENE := "res://scenes/props/garage/car.tscn"
const VENDING_SCENE := "res://scenes/props/halls/vending.tscn"
const PAYPHONE_SCENE := "res://scenes/props/halls/payphone.tscn"
const READER_SCENE := "res://scenes/interactables/card_reader.tscn"
const BREAKER_SCENE := "res://scenes/interactables/breaker.tscn"
const SPOT_SCENE := "res://scenes/interactables/hide_spot_%s.tscn"


## Places everything; returns the nodes the shots and keys need.
static func build(bench: Node3D, wall_mat: Material) -> Dictionary:
	var out := {}
	var row := [&"flare", &"radio", &"fuse", &"keycard"]
	for i in row.size():
		ItemPickup.spawn(bench, row[i], 0, {}, Vector3(-2.25 + 1.5 * float(i), 0.0, 2.9))
	out[&"vending"] = _place(bench, VENDING_SCENE, Vector3(-5.5, 0.0, -5.6), PI)
	out[&"payphone"] = _place(bench, PAYPHONE_SCENE, Vector3(-3.4, 0.0, -5.75), PI)
	out[&"reader"] = _place(bench, READER_SCENE, Vector3(-1.4, 0.0, -5.9), PI)
	var breaker := (load(BREAKER_SCENE) as PackedScene).instantiate() as Breaker
	breaker.variant = Breaker.VARIANT_B
	breaker.position = Vector3(0.8, 0.0, -5.85)
	breaker.rotation.y = PI
	bench.add_child(breaker)
	out[&"breaker"] = breaker
	# A car parked along the east wall with its under-car spot at its centre, looking out of the
	# aisle (west) side, as the Garage grammar and LevelPlacer place them.
	out[&"car"] = _place(bench, CAR_SCENE, Vector3(5.0, 0.0, -2.0), 0.0)
	out[&"car_spot"] = _place(bench, SPOT_SCENE % "under_car", Vector3(5.0, 0.0, -2.0), PI * 0.5)
	out[&"desk"] = _desk(bench, Vector3(-5.2, 0.0, 2.4), wall_mat)
	out[&"desk_spot"] = _place(bench, SPOT_SCENE % "under_desk", Vector3(-5.2, 0.0, 2.4), 0.0)
	out[&"locker"] = _place(bench, SPOT_SCENE % "locker", Vector3(6.85, 0.0, 3.2), -PI * 0.5)
	out[&"pump"] = _place(bench, SPOT_SCENE % "pump_corner", Vector3(-1.0, 0.0, -2.6), 0.0)
	out[&"rack"] = _place(bench, SPOT_SCENE % "rack_gap", Vector3(2.4, 0.0, -2.6), 0.0)
	return out


static func _place(bench: Node3D, path: String, pos: Vector3, yaw: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	n.position = pos
	n.rotation.y = yaw
	bench.add_child(n)
	return n


## A stand-in office desk: a top, two side panels and a modesty rail above the 0.5 m eye line,
## so the kneehole is open to the room at the camera's height (the Offices prop is M2.2's).
static func _desk(bench: Node3D, pos: Vector3, mat: Material) -> Node3D:
	var desk := Node3D.new()
	desk.name = "StandInDesk"
	desk.position = pos
	bench.add_child(desk)
	var parts := [
		[Vector3(1.6, 0.05, 0.8), Vector3(0, 0.74, 0)],
		[Vector3(0.05, 0.72, 0.75), Vector3(-0.78, 0.36, 0)],
		[Vector3(0.05, 0.72, 0.75), Vector3(0.78, 0.36, 0)],
		[Vector3(1.5, 0.16, 0.03), Vector3(0, 0.62, -0.33)],
	]
	for p in parts:
		var body := StaticBody3D.new()
		body.collision_layer = PlayerLayers.WORLD_MASK
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = p[0]
		shape.shape = bs
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		bm.material = mat
		mesh.mesh = bm
		body.add_child(mesh)
		body.position = p[1]
		desk.add_child(body)
	return desk


# --- screenshots ------------------------------------------------------------------------------

static func shots(b: Node3D, dir: String, refs: Dictionary) -> void:
	var inv: Inventory = b.player.inventory
	inv.reset()
	# Pickups of the new kinds and the props along the wall.
	b._pose(Vector3(0.0, 0.0, 5.0), 0.0, -0.22)
	await b._wait(0.6)
	b._save(dir + "/items_pickups_new.png")
	b._pose(Vector3(-3.0, 0.0, -2.0), deg_to_rad(8.0), -0.05)
	await b._wait(0.6)
	b._save(dir + "/interactables_wall.png")
	# Held: flare unlit then struck, radio on, fuse.
	inv.add(&"flare", 2)
	inv.add(&"radio")
	inv.add(&"fuse")
	b.fixture.visible = false
	b._pose(Vector3(0.0, 0.0, 5.0), 0.0, -0.1)
	inv.select(inv.slot_of(&"fuse"))
	await b._wait(1.0)
	b._save(dir + "/items_held_fuse.png")
	inv.select(inv.slot_of(&"radio"))
	await b._wait(1.0)
	b._save(dir + "/items_held_radio_off.png")
	inv.use_selected()
	await b._wait(0.6)
	b._save(dir + "/items_held_radio_on.png")
	inv.use_selected()
	inv.select(inv.slot_of(&"flare"))
	await b._wait(1.0)
	b._save(dir + "/items_held_flare.png")
	inv.use_selected()
	await b._wait(1.2)
	b._save(dir + "/items_held_flare_burning.png")
	# Thrown into the dark half: burning on the floor.
	var fi := inv.behavior_for(&"flare") as FlareItem
	fi._strike_left = 0.0
	inv.use_selected()
	await b._wait(3.0)
	b._pose(Vector3(1.0, 0.0, 5.0), deg_to_rad(6.0), -0.12)
	await b._wait(0.5)
	b._save(dir + "/items_flare_floor.png")
	# The radio set down, playing.
	inv.select(inv.slot_of(&"radio"))
	await b._wait(0.8)
	inv.use_selected()
	var radio := inv.behavior_for(&"radio") as RadioItem
	b._pose(Vector3(-2.0, 0.0, 5.0), 0.0, -0.1)
	radio.put_down(inv.selected_slot())
	await b._wait(1.0)
	b._pose(Vector3(-2.0, 0.0, 4.2), deg_to_rad(8.0), -0.38)
	await b._wait(0.6)
	b._save(dir + "/items_radio_placed.png")
	b.fixture.visible = true
	# Under the car: from the aisle, then hidden.
	var car_spot: HideSpot = refs[&"car_spot"]
	b._pose(Vector3(2.9, 0.0, -2.0), deg_to_rad(-90.0), -0.35)
	await b._wait(0.6)
	b._save(dir + "/hide_under_car_outside.png")
	b.player.enter_hide(car_spot)
	await b._wait(1.0)
	b._save(dir + "/hide_under_car.png")
	b.player.rig.anchored_look(deg_to_rad(-30.0), 0.0, car_spot.yaw_limit_deg)
	await b._wait(0.3)
	b._save(dir + "/hide_under_car_turned.png")
	b.player.leave_hide()
	await b._wait(1.0)
	# Under the desk.
	var desk_spot: HideSpot = refs[&"desk_spot"]
	b._pose(Vector3(-5.2, 0.0, 4.2), 0.0, -0.1)
	await b._wait(0.6)
	b._save(dir + "/hide_under_desk_outside.png")
	b.player.enter_hide(desk_spot)
	await b._wait(1.0)
	b._save(dir + "/hide_under_desk.png")
	b.player.leave_hide()
	await b._wait(1.0)
	# The pump corner and the rack gap, for the record.
	for key: StringName in [&"pump", &"rack"]:
		var spot: HideSpot = refs[key]
		b._pose(spot.global_position + Vector3(0.0, 0.0, 1.0), 0.0, 0.0)
		b.player.enter_hide(spot)
		await b._wait(1.0)
		b._save(dir + "/hide_%s.png" % key)
		b.player.leave_hide()
		await b._wait(1.0)
