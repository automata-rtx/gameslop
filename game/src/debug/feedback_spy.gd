class_name FeedbackSpy
extends RefCounted
## Feedback Contract instrumentation (11 §1, §7): every process frame it takes a signature of
## each channel and records which keys changed since the previous frame.
##   I Image    CoherenceRenderer state and pulses, the held flashlight and item, the level's
##              dynamic nodes, the exit, hide mask, Still's render line (no GPU needed: the
##              state the renderer is fed, not pixels).
##   S Sound    AudioManager's one-shot pool (a player started), its loops (started, volume,
##              pitch) and its ducks.
##   M Motion   CameraRig: the final camera offset, FOV and eye height plus the parameters
##              behind them (trauma, bob, sway, jitter, FOV holds), and the hitstop.
##   R Readout  every property of the HUD tree (and the Landing panel), plus redraws.
## A key that is already changing in the frames before the trigger is "noisy" and ignored for
## that row, so a continuous animation can never be mistaken for a reaction.
## Debug tooling only: it reads private state on purpose and changes nothing.

const CHANNELS: Array[StringName] = [&"I", &"S", &"M", &"R"]
## Floats closer than this are equal.
const EPS := 0.0001
## Noise window: frames before the anchor looked at, and the changes that make a key noisy.
const NOISE_FRAMES := 8
const NOISE_CHANGES := 3

## Set by the bench: the Run being watched (null before it exists).
var run: Run
## Extra probes a row adds: channel -> {name: Callable returning a Variant}.
var extra: Dictionary = {}
## One entry per sampled frame: {frame, tick, usec, changed: {channel: PackedStringArray}}.
var entries: Array[Dictionary] = []

var _prev: Dictionary = {}
var _audio_state: Dictionary = {}
var _audio_counts: Dictionary = {}
var _draws: Dictionary = {}
var _watched: Dictionary = {}
## Script variables worth reading per script (cached): script -> PackedStringArray.
var _script_vars: Dictionary = {}
## The HUD prompt's hold bar: 11 §2 lists "underline fills on the prompt" as Image and "fill
## bar" as Readout for Interact hold; it is one widget, so it counts on both channels.
var _underline: Dictionary = {}
var _last_charge: float = 0.0


func clear_history() -> void:
	entries.clear()


## Takes one sample. Returns the new entry.
func sample(tree: SceneTree) -> Dictionary:
	var readout := _readout()
	var image := _image(tree)
	image.merge(_underline)
	var now := {&"I": image, &"S": _sound(), &"M": _motion(), &"R": readout}
	for ch: StringName in extra:
		for probe_name: String in extra[ch]:
			var v: Variant = (extra[ch][probe_name] as Callable).call()
			(now[ch] as Dictionary)["x." + probe_name] = v
	var changed: Dictionary = {}
	for ch: StringName in CHANNELS:
		var keys := PackedStringArray()
		var cur: Dictionary = now[ch]
		var old: Dictionary = _prev.get(ch, {})
		for k: String in cur:
			if not old.has(k) or differs(cur[k], old[k]):
				keys.append(k)
		for k: String in old:
			if not cur.has(k):
				keys.append(k)
		changed[ch] = keys
	_prev = now
	var e := {&"frame": Engine.get_process_frames(), &"tick": Engine.get_physics_frames(),
		&"usec": Time.get_ticks_usec(), &"changed": changed}
	entries.append(e)
	return e


static func differs(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return true
	match typeof(a):
		TYPE_FLOAT:
			return absf(float(a) - float(b)) > EPS
		TYPE_VECTOR2:
			return not (a as Vector2).is_equal_approx(b)
		TYPE_VECTOR3:
			return not (a as Vector3).is_equal_approx(b)
		TYPE_COLOR:
			return not (a as Color).is_equal_approx(b)
		TYPE_TRANSFORM3D:
			return not (a as Transform3D).is_equal_approx(b)
		TYPE_DICTIONARY, TYPE_ARRAY:
			return str(a) != str(b)
	return a != b


## Keys that changed in at least NOISE_CHANGES of the NOISE_FRAMES entries before `index`.
func noisy_keys(index: int, channel: StringName) -> Dictionary:
	var counts: Dictionary = {}
	for i in range(maxi(index - NOISE_FRAMES, 0), index):
		for k: String in entries[i][&"changed"][channel]:
			counts[k] = int(counts.get(k, 0)) + 1
	var out: Dictionary = {}
	for k: String in counts:
		if int(counts[k]) >= NOISE_CHANGES:
			out[k] = true
	return out


# --- Image ----------------------------------------------------------------------------------

func _image(tree: SceneTree) -> Dictionary:
	var d: Dictionary = {}
	var cr := CoherenceRenderer
	d["cr.coherence"] = cr.coherence01
	d["cr.noclip_charge"] = cr.noclip_charge
	# The preview's direction (11 §2 noclip cancel: "preview collapses"): the charge value
	# moves every frame while charging, so the turn from growing to collapsing is its own key.
	d["cr.noclip_preview"] = signf(snappedf(cr.noclip_charge - _last_charge, 0.0001))
	_last_charge = cr.noclip_charge
	d["cr.noclip_commit"] = cr.noclip_commit
	d["cr.noclip_invalid"] = cr.noclip_invalid
	d["cr.noclip_target"] = cr.noclip_target
	d["cr.static"] = cr.static_amount
	d["cr.null_radius"] = cr.null_radius
	# 02 §8 Null: the camera inside the radius (lines, halo) and inside the 2 m core (black
	# with the halo); the post shader measures from the camera, as here.
	var vp_cam := tree.root.get_camera_3d()
	var dn := vp_cam.global_position.distance_to(cr.null_pos) if vp_cam != null and cr.null_radius > 0.0 else INF
	d["cr.null_inside"] = dn <= cr.null_radius
	d["cr.null_core"] = dn <= Tuning.NULL_CORE_RADIUS
	d["cr.threat"] = cr.threat
	for k: Variant in cr.post_params:
		d["post.%s" % k] = cr.post_params[k]
	var at: Dictionary = cr.get(&"_pulse_at_frame")
	for kind: Variant in at:
		d["pulse.%s" % kind] = at[kind]
	d["cr.drop_arrive"] = cr.get(&"_drop_arrive_usec")
	if run == null or not is_instance_valid(run):
		return d
	d["run.phase"] = run.phase
	if run.dissolve_grid != null:
		d["dissolve.visible"] = run.dissolve_grid.visible
	var p := run.player
	if p != null:
		var f := p.flashlight
		d["light.on"] = f.on
		d["light.beam"] = f.beam.light_energy
		d["light.beam_vis"] = f.beam.visible
		d["light.hand"] = f.hand_light.light_energy
		d["light.lens"] = f.lens_emission()
		d["light.wheel"] = f.wheel.rotation
		# The wheel turning or stopped (11 §2 crank full: "wheel stops"); its angle is
		# noise while it turns, so the stop itself is its own key.
		d["light.wheel_turning"] = f.is_turning()
		d["light.held"] = f.held.position
		d["light.held_rot"] = f.held.rotation
		d["held.bob_amp"] = snappedf(float(p.rig.get(&"_bob_amp_target")) * p.rig.bob_scale, 0.05)
		var hand: HeldHand = p.inventory.get(&"_hand")
		if hand != null and hand.root != null:
			d["hand.pos"] = hand.root.position
			d["hand.children"] = hand.root.get_child_count()
			if hand.model != null and is_instance_valid(hand.model):
				d["hand.model"] = hand.model.position
				d["hand.model_rot"] = hand.model.rotation
				d["hand.model_vis"] = hand.model.visible
		d["cam.children"] = p.rig.camera.get_child_count()
		if p.hiding.spot != null:
			var mask: CanvasLayer = p.hiding.spot.get(&"_mask")
			d["hide.mask"] = mask != null and mask.visible
	var lvl := run.level
	if lvl != null and is_instance_valid(lvl):
		d["level.content"] = lvl.content.get_child_count()
		d["level.children"] = lvl.get_child_count()
		var lit := 0
		var flash := 0
		var dark := 0
		for f in lvl.light_pool.fixtures():
			lit += 1 if f.powered else 0
			flash += 1 if f.is_flashing() else 0
			dark += 1 if f.is_lunge_dark() else 0
		d["fixtures.powered"] = lit
		d["fixtures.flash"] = flash
		d["fixtures.lunge_dark"] = dark
	d["root.children"] = tree.root.get_child_count()
	if tree.current_scene != null:
		d["scene.children"] = tree.current_scene.get_child_count()
	d["decals"] = tree.get_nodes_in_group(ChalkDecal.GROUP).size()
	var ex := run.exit
	if ex != null and is_instance_valid(ex):
		d["exit.lamp"] = ex.emission_of(ex.lamp)
		d["exit.interior"] = ex.emission_of(ex.interior)
		d["exit.door"] = ex.leaf_open_amount()
		d["exit.light"] = ex.light.light_energy
	var landing := run.landing
	if landing != null and is_instance_valid(landing):
		d["landing.cabin"] = landing.geometry.position
		d["landing.door"] = landing.door_open
	for e in tree.get_nodes_in_group(ErrorBase.GROUP):
		if is_instance_valid(e) and e is ErrorStill:
			d["still.ticks"] = (e as ErrorStill).ticks
			d["still.line"] = (e as ErrorStill).tick_left > 0.0
		elif is_instance_valid(e) and e is ErrorEcho:
			d["echo.presence"] = snappedf((e as ErrorEcho).presence, 0.01)
			d["echo.shimmer"] = (e as ErrorEcho).shimmer.visible
	return d


# --- Sound ----------------------------------------------------------------------------------

func _sound() -> Dictionary:
	var d: Dictionary = {}
	var am := AudioManager
	if am.pool != null:
		for list: Array in [am.pool.players_3d, am.pool.players_2d]:
			for p: Node in list:
				var started: Variant = p.get_meta(AudioPool.META_STARTED, -1.0)
				var playing: bool = p.get(&"playing")
				var id: StringName = p.get_meta(AudioPool.META_ID, &"")
				var prev: Array = _audio_state.get(p, [false, -1.0])
				# A start is counted by its stamp, set the moment `play()` is called: `playing`
				# turns true only when the audio thread picks the playback up, which lags under load.
				var new_start: bool = float(started) >= 0.0 and not is_equal_approx(float(prev[1]), float(started))
				if new_start:
					_audio_counts[id] = int(_audio_counts.get(id, 0)) + 1
				_audio_state[p] = [playing, started]
	for id: Variant in _audio_counts:
		d["play.%s" % id] = _audio_counts[id]
	var loops: Array[Node] = []
	var root: Node = am.get(&"_loops_root")
	if root != null:
		loops.append_array(root.get_children())
	for l: Variant in am.get(&"_loops3d"):
		if is_instance_valid(l) and l is Node:
			loops.append(l)
	for l in loops:
		var id: StringName = l.get_meta(AudioPool.META_ID, &"")
		if id == &"" or not l.has_meta(AudioPool.META_ID):
			continue
		var key := "loop.%s.%d" % [id, l.get_instance_id() % 100000]
		d[key + ".on"] = l.get(&"playing")
		d[key + ".db"] = snappedf(float(l.get(&"volume_db")), 0.5)
		d[key + ".pitch"] = snappedf(float(l.get(&"pitch_scale")), 0.01)
	# The Null grid tone (a runtime generator, not a pool player) and its core mute.
	d["gen.null_tone"] = snappedf(NullTone.amplitude(am.null_distance()), 0.01)
	d["gen.null_core"] = am.in_null_core()
	for bus: StringName in [&"World", &"Music", &"UI", &"Player", &"Ambience", &"Errors"]:
		d["duck.%s" % bus] = snappedf(am.duck_db(bus), 0.5)
	return d


# --- Motion ---------------------------------------------------------------------------------

func _motion() -> Dictionary:
	var d: Dictionary = {}
	d["clock.hitstop"] = Clock.is_hitstopping()
	if run == null or not is_instance_valid(run) or run.player == null:
		return d
	var rig := run.player.rig
	var m: Node3D = rig.get(&"_motion")
	d["cam.offset"] = m.position
	d["cam.rotation"] = m.rotation
	d["cam.fov"] = rig.camera.fov
	d["rig.position"] = rig.position
	d["rig.rotation"] = rig.rotation
	d["rig.trauma"] = rig.trauma
	d["rig.bob_scale"] = rig.bob_scale
	d["rig.bob_amp"] = rig.get(&"_bob_amp_target")
	d["rig.sway"] = rig.get(&"_sway_amp")
	d["rig.jitter"] = rig.get(&"_jitter")
	d["rig.holds"] = rig.fov_hold_total()
	d["rig.anchored"] = rig.is_anchored()
	d["player.pos"] = run.player.global_position
	return d


# --- Readout --------------------------------------------------------------------------------

func _readout() -> Dictionary:
	var d: Dictionary = {}
	_underline = {}
	if run == null or not is_instance_valid(run):
		return d
	if run.hud != null:
		_walk(run.hud, run.hud, d)
	if run.landing != null and is_instance_valid(run.landing) and run.landing.panel != null:
		_walk(run.landing.panel, run.landing.panel, d)
	return d


func _on_draw(id: int) -> void:
	_draws[id] = int(_draws.get(id, 0)) + 1


## The public script variables of `node`'s script (cached per script).
func _vars_of(node: Node) -> PackedStringArray:
	var sc: Script = node.get_script()
	if _script_vars.has(sc):
		return _script_vars[sc]
	var names := PackedStringArray()
	for info in node.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not String(info["name"]).begins_with("_"):
			names.append(info["name"])
	_script_vars[sc] = names
	return names


func _walk(root: Node, node: Node, d: Dictionary) -> void:
	var ci := node as CanvasItem
	if ci != null:
		var key := "%s" % root.get_path_to(node)
		var id := node.get_instance_id()
		if not _watched.has(id):
			_watched[id] = true
			ci.draw.connect(_on_draw.bind(id))
		d[key + ".vis"] = ci.visible
		d[key + ".mod"] = ci.modulate
		d[key + ".selfmod"] = ci.self_modulate
		d[key + ".draws"] = int(_draws.get(id, 0))
		var c := node as Control
		if c != null:
			d[key + ".pos"] = c.position
			d[key + ".size"] = c.size
			d[key + ".scale"] = c.scale
		var l := node as Label
		if l != null:
			d[key + ".text"] = l.text
			d[key + ".chars"] = l.visible_characters
		var r := node as Range
		if r != null:
			d[key + ".value"] = r.value
		if node.get_script() != null:
			for prop in _vars_of(node):
				var v: Variant = node.get(prop)
				match typeof(v):
					TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_COLOR:
						d["%s.%s" % [key, prop]] = v
					TYPE_ARRAY, TYPE_DICTIONARY:
						d["%s.%s" % [key, prop]] = str(v).left(400)
			if "fraction" in node:
				_underline["ui.underline"] = node.get(&"fraction")
	for child in node.get_children():
		_walk(root, child, d)
