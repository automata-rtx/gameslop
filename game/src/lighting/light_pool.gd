class_name LightPool
extends Node3D
## 02 §6 light pooling: only the N fixtures nearest the player have a light (24/16/10 by
## preset), re-evaluated every 0.25 s; the nearest 4/2/0 of those cast shadows. A light
## keeps its fixture while that fixture stays in the nearest set, so only the far edge of
## the set swaps, and a re-assigned light ramps in (with distance_fade) to hide the swap.
## Interface (02): register_fixture, set_group_flicker, power_wave. Also is_lit(pos) for
## the player's observation light queries (06, 08 §4), and Flicker's group queries (08
## Interfaces): group_centroid, groups_adjacent, is_group_lit, lit_fixtures_near, plus its
## presentation hooks (stutter rate, lunge flash and dark). A flickering fixture's hum is
## gated with its off instants (03: the ballast stutter).

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
## Per light: true while its hum is gated off by a stutter instant.
var _hum_gated: PackedByteArray = PackedByteArray()
## Group centroids and adjacency (08 §5), rebuilt lazily after a fixture registers.
var _topology: FixtureGroups
## The level grid (optional): enables walking-distance ranking and grid-sight lending.
var grid: LevelGrid:
	set(g):
		grid = g
		_selector = LightSelector.new(g)
		for f in _fixtures:
			_selector.add(f.global_position)
		_topology = null
var _selector: LightSelector = LightSelector.new()


## Reads the stratum's fixture light (02 §7) and the preset's pool size and shadow count.
func configure(data: StratumData, preset: StringName = Tuning.QUALITY_PRESET_DEFAULT) -> void:
	var p := StratumEnvironment.preset_of(preset)
	light_color = data.fixture_light_color
	light_energy = data.fixture_light_energy
	light_range = data.fixture_light_range
	light_attenuation = float(Tuning.LIGHT_FIXTURE_ATTENUATION_STRATUM.get(data.id, Tuning.LIGHT_FIXTURE_ATTENUATION))
	light_kind = Tuning.LIGHT_FIXTURE_KIND.get(data.id, &"omni")
	light_drop = float(Tuning.LIGHT_FIXTURE_DROP_STRATUM.get(data.id, Tuning.LIGHT_FIXTURE_DROP))
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
	_hum_gated.clear()
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
		_hum_gated.append(0)


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
	_topology = null
	# 03: about one fixture in six carries the tired-ballast buzz instead of the hum.
	var h := hash(Vector3i((fixture.global_position * 10.0).round())) if fixture.is_inside_tree() else _fixtures.size()
	var buzz := posmod(h, 6) == 0 and bool(fixture.light_value(&"buzz", true))
	fixture.hum_id = buzz_id if buzz else hum_id
	# R4 V3: the buzzing ballast also looks tired: greener, 85% energy, steady.
	fixture.set_buzzing(buzz)


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


## 08 §5: the stutter rate of a group (8 Hz resident, up to 20 Hz as Flicker's charge builds).
func set_group_flicker_rate(group_id: int, hz: float) -> void:
	for f in group(group_id):
		f.set_flicker_rate(hz)


## 08 §5, 02 §8 lunge: the whole group flashes white for 2 frames.
func group_lunge_flash(group_id: int) -> void:
	for f in group(group_id):
		f.lunge_flash()


## 08 §5: the whole group dark (not unpowered) for the 1.5 s after a lunge.
func set_group_lunge_dark(group_id: int, on: bool) -> void:
	for f in group(group_id):
		f.set_lunge_dark(on)


# --- Flicker's group queries (08 Interfaces) ---------------------------------------------

## The centroid of a group's fixtures (Flicker's position for proximity and captions).
func group_centroid(group_id: int) -> Vector3:
	return _topo().centroids.get(group_id, Vector3.INF)


## Groups adjacent to `group_id` (fixtures within 8 m in XZ, or sharing a door), sorted.
func groups_adjacent(group_id: int) -> Array[int]:
	return _topo().neighbours(group_id)


## A group is lit (habitable for Flicker) while any of its fixtures is powered: the power
## state, never whether the pool lends it a light (08 §4, §5).
func is_group_lit(group_id: int) -> bool:
	for f in group(group_id):
		if f.powered:
			return true
	return false


## Lit fixtures (powered, not in a lunge dark) within `radius` of `pos` in XZ whose light
## has a clear grid sight line to `pos` (CHANGELOG 2026-10-08), nearest first.
func lit_fixtures_near(pos: Vector3, radius: float) -> Array[Fixture]:
	var out: Array[Fixture] = []
	var d: Array[float] = []
	for f in _fixtures:
		if not f.is_lit():
			continue
		var dist := FixtureGroups.flat_dist(f.global_position, pos)
		if dist > radius:
			continue
		if grid != null and not SightOps.clear(grid, anchor_of(f), pos):
			continue
		var k := d.bsearch(dist)
		d.insert(k, dist)
		out.insert(k, f)
	return out


func _topo() -> FixtureGroups:
	if _topology == null:
		_topology = FixtureGroups.new()
		_topology.build(_groups, grid)
	return _topology


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


## 06, 08 §4: a point inside the light range of a powered fixture counts as lit, when the
## fixture has a clear grid sight line to it (pooled lights cast no shadows, so without the
## grid test they would light through 0.2 m walls; CHANGELOG 2026-10-08).
func is_lit(pos: Vector3) -> bool:
	for f in _fixtures:
		if not f.powered:
			continue
		var r := float(f.light_value(&"range", light_range))
		var a := anchor_of(f)
		if a.distance_squared_to(pos) <= r * r and (grid == null or SightOps.clear(grid, a, pos)):
			return true
	return false


## Where a fixture's pooled light hangs.
func anchor_of(f: Fixture) -> Vector3:
	return f.global_position - Vector3(0.0, float(f.light_value(&"drop", light_drop)), 0.0)


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
		_lights[i].light_energy = float(f.light_value(&"energy", light_energy)) * f.intensity * f.energy_scale() * _fade[i]
		_gate_hum(i, f)


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
		var fi := _assigned_i[i]
		_lights[i].shadow_enabled = fi >= 0 and int(rank.get(fi, shadowed)) < shadowed \
			and bool(_fixtures[fi].light_value(&"shadow", true))


func _lend(i: int, fi: int) -> void:
	var f := _fixtures[fi]
	_assigned[i] = f
	_assigned_i[i] = fi
	_fade[i] = 0.0
	var l := _lights[i]
	l.global_position = anchor_of(f)
	l.light_color = f.light_tint(light_color)
	var r := float(f.light_value(&"range", light_range))
	if l is OmniLight3D:
		(l as OmniLight3D).omni_range = r
	elif l is SpotLight3D:
		(l as SpotLight3D).spot_range = r
	l.light_energy = 0.0
	l.visible = true
	_set_hum(i, f.hum_id)


func _release(i: int) -> void:
	if int(_hum_gated[i]) != 0:
		_hum_gated[i] = 0
		for k in (_hums[i] as Dictionary):
			((_hums[i] as Dictionary)[k] as AudioLoop).set_volume(0.0)
	_assigned[i] = null
	_assigned_i[i] = -1
	_lights[i].visible = false
	_lights[i].shadow_enabled = false
	_set_hum(i, &"")


## 03 Flicker: the ballast stutter is the fixture hum gated at the stutter rate (and
## silent through the lunge dark).
func _gate_hum(i: int, f: Fixture) -> void:
	var off := f.is_flickering() and not f.is_emitting() or f.is_lunge_dark()
	if int(_hum_gated[i]) == int(off):
		return
	_hum_gated[i] = int(off)
	var hums: Dictionary = _hums[i]
	if hums.has(f.hum_id):
		(hums[f.hum_id] as AudioLoop).set_volume(Tuning.AUDIO_SLIDER_MUTE_DB if off else 0.0)


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
