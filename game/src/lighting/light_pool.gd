class_name LightPool
extends Node3D
## 02 §6 light pooling: only the N fixtures nearest the player have a light (24/16/10 by
## preset), re-evaluated every 0.25 s; the nearest 4/2/0 of those cast shadows. A light
## keeps its fixture while that fixture stays in the nearest set, so only the far edge of
## the set swaps, and a re-assigned light ramps in (with distance_fade) to hide the swap.
## Interface (02): register_fixture, set_group_flicker, power_wave. Also is_lit(pos) for
## the player's observation light queries (06, 08 §4).

## The node the pool measures from (the player's camera or body). Null: the pool origin.
var target: Node3D

var pool_size: int = Tuning.LIGHT_POOL_SIZE_MEDIUM
var shadowed: int = 2
var light_color: Color = Color.WHITE
var light_energy: float = 1.0
var light_range: float = 7.0
var light_attenuation: float = 1.0
var shadow_bias: float = 0.05
## &"omni" or &"spot" (a wide downlight: floor pools and wall scallops, 02 §6 allows either).
var light_kind: StringName = &"omni"
## Metres the pooled light hangs below its fixture (02 §6 tuning: deeper = stronger pools).
var light_drop: float = Tuning.LIGHT_FIXTURE_DROP
var spot_angle: float = 70.0
var spot_attenuation: float = 1.0
## Hum loop ids (03): most fixtures hum, a hashed few buzz.
var hum_id: StringName = &""
var buzz_id: StringName = &""

var _fixtures: Array[Fixture] = []
var _groups: Dictionary = {}
var _lights: Array[Light3D] = []
## Per light: the Fixture it is lent to, or null.
var _assigned: Array = []
## Per light: the fixture index it is lent to, or -1.
var _assigned_i: PackedInt32Array = PackedInt32Array()
var _fade: PackedFloat32Array = PackedFloat32Array()
var _hums: Array = []
var _timer: float = 0.0
## The level grid (optional): enables walking-distance ranking and grid-sight lending.
var grid: LevelGrid:
	set(g):
		grid = g
		_selector = LightSelector.new(g)
		for f in _fixtures:
			_selector.add(f.global_position)
var _selector: LightSelector = LightSelector.new()


## Reads the stratum's fixture light (02 §7) and the preset's pool size and shadow count.
func configure(data: StratumData, preset: StringName = Tuning.QUALITY_PRESET_DEFAULT) -> void:
	var p := StratumEnvironment.preset_of(preset)
	light_color = data.fixture_light_color
	light_energy = data.fixture_light_energy
	light_range = data.fixture_light_range
	light_attenuation = Tuning.LIGHT_FIXTURE_ATTENUATION
	light_kind = Tuning.LIGHT_FIXTURE_KIND.get(data.id, &"omni")
	spot_angle = Tuning.LIGHT_SPOT_ANGLE
	spot_attenuation = Tuning.LIGHT_SPOT_ANGLE_ATTENUATION
	shadow_bias = data.shadow_bias
	hum_id = StringName("fixture_hum_%s" % data.id)
	buzz_id = StringName("fixture_buzz_%s" % data.id)
	_make_lights(int(p[&"lights"]), int(p[&"shadowed"]))


## Re-creates the pooled lights after a change to the light fields (tuning, preset).
func rebuild_lights() -> void:
	_make_lights(pool_size, shadowed)
	reevaluate()


func _make_lights(n: int, shadows: int) -> void:
	for l in _lights:
		l.free()
	_lights.clear()
	_assigned.clear()
	_assigned_i.clear()
	_hums.clear()
	pool_size = clampi(n, 0, Tuning.LIGHT_POOL_SIZE_MAX)
	shadowed = mini(shadows, pool_size)
	_fade.resize(pool_size)
	_fade.fill(0.0)
	for i in pool_size:
		var l := _new_light()
		l.name = "PoolLight%d" % i
		l.light_color = light_color
		l.shadow_bias = shadow_bias
		l.light_energy = 0.0
		l.distance_fade_enabled = true
		l.distance_fade_begin = Tuning.LIGHT_POOL_DISTANCE_FADE_BEGIN
		l.distance_fade_length = Tuning.LIGHT_POOL_DISTANCE_FADE_LENGTH
		l.visible = false
		add_child(l)
		_lights.append(l)
		_assigned.append(null)
		_assigned_i.append(-1)
		_hums.append({})


func _new_light() -> Light3D:
	if light_kind == &"spot":
		var s := SpotLight3D.new()
		s.spot_range = light_range
		s.spot_attenuation = light_attenuation
		s.spot_angle = spot_angle
		s.spot_angle_attenuation = spot_attenuation
		# Points straight down.
		s.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		return s
	var o := OmniLight3D.new()
	o.omni_range = light_range
	o.omni_attenuation = light_attenuation
	return o


func register_fixture(fixture: Fixture) -> void:
	if _fixtures.has(fixture):
		return
	_fixtures.append(fixture)
	_selector.add(fixture.global_position)
	if not _groups.has(fixture.group_id):
		_groups[fixture.group_id] = [] as Array[Fixture]
	(_groups[fixture.group_id] as Array[Fixture]).append(fixture)
	# 03: about one fixture in six carries the tired-ballast buzz instead of the hum.
	var h := hash(Vector3i((fixture.global_position * 10.0).round())) if fixture.is_inside_tree() else _fixtures.size()
	fixture.hum_id = buzz_id if posmod(h, 6) == 0 else hum_id


func fixtures() -> Array[Fixture]:
	return _fixtures


func group(group_id: int) -> Array[Fixture]:
	var out: Array[Fixture] = []
	if _groups.has(group_id):
		out.assign(_groups[group_id])
	return out


func group_ids() -> Array:
	return _groups.keys()


## 08 Flicker: a group flickers only while Flicker is in it.
func set_group_flicker(group_id: int, on: bool) -> void:
	for f in group(group_id):
		f.set_flicker(on)


func set_group_powered(group_id: int, on: bool) -> void:
	for f in group(group_id):
		f.set_powered(on)
	reevaluate()


func set_all_powered(on: bool) -> void:
	for f in _fixtures:
		f.set_powered(on)
	reevaluate()


## 02 §6 breaker: unpowered fixtures light in a wave from `origin` at 12 m/s, 40 ms
## stagger per fixture, overshoot 1.3, settle 400 ms. Returns the seconds until the last.
func power_wave(origin: Vector3) -> float:
	var dark: Array[Fixture] = []
	for f in _fixtures:
		if not f.powered:
			dark.append(f)
	dark.sort_custom(func(a: Fixture, b: Fixture) -> bool:
		return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	var last := 0.0
	for i in dark.size():
		var delay := dark[i].global_position.distance_to(origin) / Tuning.LIGHT_BREAKER_WAVE_SPEED \
			+ i * Tuning.LIGHT_BREAKER_STAGGER_MS / 1000.0
		dark[i].power_on_wave(delay)
		last = maxf(last, delay)
	return last


## 06, 08 §4: a point inside the light range of a powered fixture counts as lit.
func is_lit(pos: Vector3) -> bool:
	var r2 := light_range * light_range
	for f in _fixtures:
		if f.powered and anchor_of(f).distance_squared_to(pos) <= r2:
			return true
	return false


## Where a fixture's pooled light hangs.
func anchor_of(f: Fixture) -> Vector3:
	return f.global_position - Vector3(0.0, light_drop, 0.0)


func active_light_count() -> int:
	var n := 0
	for l in _lights:
		if l.visible:
			n += 1
	return n


func shadowed_light_count() -> int:
	var n := 0
	for l in _lights:
		if l.visible and l.shadow_enabled:
			n += 1
	return n


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = Tuning.LIGHT_POOL_REEVAL_INTERVAL
		reevaluate()
	for i in _lights.size():
		var f: Fixture = _assigned[i]
		if f == null:
			continue
		_fade[i] = minf(1.0, _fade[i] + delta / Tuning.LIGHT_POOL_FADE_IN)
		_lights[i].light_energy = light_energy * f.intensity * _fade[i]


func _origin() -> Vector3:
	return target.global_position if target != null and is_instance_valid(target) else global_position


## Lends the pool's lights to the nearest powered fixtures in view (LightSelector); the
## nearest few cast shadows (02 §3). A light keeps its fixture while it stays selected.
func reevaluate() -> void:
	var eligible := PackedByteArray()
	eligible.resize(_fixtures.size())
	for i in _fixtures.size():
		eligible[i] = 1 if _fixtures[i].powered else 0
	var chosen := _selector.select(_origin(), eligible, pool_size)
	var order: Dictionary = {}
	for k in chosen.size():
		order[chosen[k]] = k
	var free: Array[int] = []
	for i in _lights.size():
		var fi := _assigned_i[i]
		if fi >= 0 and order.has(fi):
			order.erase(fi)
			continue
		_release(i)
		free.append(i)
	# `chosen` is nearest first, so the nearest new fixtures get the free lights first.
	for k in chosen.size():
		var fi := chosen[k]
		if order.has(fi) and not free.is_empty():
			_lend(free.pop_front(), fi)
	var rank: Dictionary = {}
	for k in chosen.size():
		rank[chosen[k]] = k
	for i in _lights.size():
		_lights[i].shadow_enabled = _assigned_i[i] >= 0 and int(rank.get(_assigned_i[i], shadowed)) < shadowed


func _lend(i: int, fi: int) -> void:
	var f := _fixtures[fi]
	_assigned[i] = f
	_assigned_i[i] = fi
	_fade[i] = 0.0
	var l := _lights[i]
	l.global_position = anchor_of(f)
	l.light_energy = 0.0
	l.visible = true
	_set_hum(i, f.hum_id)


func _release(i: int) -> void:
	_assigned[i] = null
	_assigned_i[i] = -1
	_lights[i].visible = false
	_lights[i].shadow_enabled = false
	_set_hum(i, &"")


## Each pooled light carries the hum of the fixture it is lent to (03).
func _set_hum(i: int, id: StringName) -> void:
	var hums: Dictionary = _hums[i]
	for k in hums:
		if k != id:
			(hums[k] as AudioLoop).stop(Tuning.LIGHT_POOL_FADE_IN)
	if id == &"":
		return
	if not hums.has(id):
		hums[id] = AudioManager.loop(id, _lights[i])
	var loop: AudioLoop = hums[id]
	if not loop.is_playing():
		loop.start(Tuning.LIGHT_POOL_FADE_IN)
