extends Node
## SHADER WARM-UP (fixes the "rainbow textures + slow for ~30s" start).
##
## Forward+ compiles GPU pipelines the first time each material/lighting
## combination is drawn. Until they're ready it draws with fallback shaders
## and stalls - garbled/rainbow surfaces and a crawling frame rate right
## after a level loads. On every 3D scene load this node:
##   1. covers the screen with a Loading panel and pauses the game
##   2. draws one tiny quad per UNIQUE material in front of the camera (the
##      level itself also renders behind the panel), so the GPU compiles
##      everything now instead of during play
##   3. finishes only when BOTH signals say "ready":
##        a) the engine's pipeline-compilation counters stopped changing
##           (quiet_time seconds), and
##        b) the frame rate has been steady for steady_time seconds: every
##           frame faster than steady_frame_ms. A compile in progress stalls
##           frames, so this catches it even when the counters don't move
##           (they read 0 on the Compatibility/OpenGL renderer).
##      A hard cap (max_wait) guarantees the game always starts.
## All timing uses a REAL clock (Time.get_ticks_usec), not summed deltas,
## and the log reports how long the screen was actually up.

## Never show the loading screen longer than this (seconds, real time).
@export var max_wait: float = 30.0
## Minimum time on screen so every material has been drawn at least once.
@export var min_time: float = 0.5
## Pipeline counters must stay unchanged this long (seconds).
@export var quiet_time: float = 0.6
## Frames must ALL be faster than this...
@export var steady_frame_ms: float = 50.0
## ...for this long in a row (seconds) before we call it smooth.
@export var steady_time: float = 1.0
## If the machine simply can't reach steady_frame_ms, accept "no frame
## slower than 2x the median" after this many seconds instead of waiting
## for the cap (slow PCs still get the loading screen, not a 30s hang).
@export var relaxed_after: float = 6.0

var _scene: Node = null
var _busy := false
var _overlay: CanvasLayer
var _label: Label
var _sub: Label
var _bar: ProgressBar

signal warmup_finished(seconds: float, materials: int)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_d: float) -> void:
	var s := get_tree().current_scene
	if s != _scene and s != null:
		_scene = s
		if s is Node3D or s.find_children("*", "MeshInstance3D", true, false).size() > 0:
			_warm.call_deferred(s)


func is_busy() -> bool:
	return _busy


func _compilations() -> int:
	var total := 0
	for m in ["PIPELINE_COMPILATIONS_CANVAS", "PIPELINE_COMPILATIONS_MESH", "PIPELINE_COMPILATIONS_SURFACE", "PIPELINE_COMPILATIONS_DRAW", "PIPELINE_COMPILATIONS_SPECIALIZATION"]:
		if m in Performance:
			total += int(Performance.get_monitor(Performance.get(m)))
	return total


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _warm(scene: Node) -> void:
	if _busy or not is_instance_valid(scene):
		return
	_busy = true
	var start := _now()
	_show_overlay()
	var was_paused := get_tree().paused
	get_tree().paused = true
	# let the scene's own _ready()s build their meshes first
	for i in range(3):
		await get_tree().process_frame
	_label.text = "Loading..."
	_sub.text = "Gathering materials"
	await get_tree().process_frame

	var cam := get_viewport().get_camera_3d()
	var holder := Node3D.new()
	holder.name = "_ShaderWarmup"
	holder.process_mode = Node.PROCESS_MODE_ALWAYS
	if cam:
		cam.add_child(holder)
		holder.position = Vector3(0, 0, -2.0)
	else:
		scene.add_child(holder)
	var mats := _unique_materials(scene)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	# Add the quads in batches so the progress bar actually moves and the
	# GPU gets them a few at a time
	var batch := 25
	for i in range(mats.size()):
		var q := MeshInstance3D.new()
		q.mesh = quad
		q.material_override = mats[i]
		q.position = Vector3((i % 20) * 0.06 - 0.6, (i / 20) * 0.06 - 0.3, 0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		holder.add_child(q)
		if i % batch == batch - 1 or i == mats.size() - 1:
			_bar.value = float(i + 1) / maxf(mats.size(), 1) * 70.0
			_sub.text = "Preparing materials  %d / %d" % [i + 1, mats.size()]
			await get_tree().process_frame

	# --- wait until BOTH signals say we're ready ----------------------------
	var last_comp := _compilations()
	var last_comp_change := _now()
	var steady_since := -1.0
	var last_frame := _now()
	var frame_times := []
	var reason := "timeout"
	while true:
		await get_tree().process_frame
		var now := _now()
		var ft := (now - last_frame) * 1000.0
		last_frame = now
		frame_times.append(ft)
		if frame_times.size() > 90:
			frame_times.pop_front()
		var comp := _compilations()
		if comp != last_comp:
			last_comp = comp
			last_comp_change = now
		var elapsed := now - start
		# steadiness: strict threshold, relaxed to "no frame > 2x median"
		# on machines that can't hit it at all
		var limit := steady_frame_ms
		if elapsed > relaxed_after and frame_times.size() >= 10:
			var sorted := frame_times.duplicate()
			sorted.sort()
			limit = maxf(steady_frame_ms, sorted[sorted.size() / 2] * 2.0)
		if ft <= limit:
			if steady_since < 0.0:
				steady_since = now
		else:
			steady_since = -1.0
		var quiet: bool = now - last_comp_change >= quiet_time
		var steady: bool = steady_since >= 0.0 and now - steady_since >= steady_time
		var fps: float = 1000.0 / maxf(ft, 0.001)
		_bar.value = 70.0 + 30.0 * clampf((now - steady_since) / steady_time if steady_since >= 0.0 else 0.0, 0.0, 1.0)
		_sub.text = "Settling...  %s  ·  %d fps" % ["shaders ready" if quiet else "compiling shaders", int(fps)]
		if elapsed >= min_time and quiet and steady:
			reason = "ready"
			break
		if elapsed >= max_wait:
			break
	holder.queue_free()
	await get_tree().process_frame
	get_tree().paused = was_paused
	_hide_overlay()
	var secs := _now() - start
	# tell the FPS guard not to judge the frames we just spent compiling
	var gq = get_node_or_null("/root/GraphicsQuality")
	if gq and "_cooldown" in gq:
		gq._cooldown = 3.0
	_busy = false
	print("ShaderWarmup: %d materials, loading screen up %.1fs (%s, %d pipeline compilations)" % [mats.size(), secs, reason, last_comp])
	warmup_finished.emit(secs, mats.size())


func _unique_materials(scene: Node) -> Array:
	var seen := {}
	var out := []
	for gi in scene.find_children("*", "GeometryInstance3D", true, false):
		var list := []
		if gi.material_override:
			list.append(gi.material_override)
		if gi is MeshInstance3D and gi.mesh:
			for si in range(gi.mesh.get_surface_count()):
				var m: Material = gi.get_surface_override_material(si)
				if m == null:
					m = gi.mesh.surface_get_material(si)
				if m:
					list.append(m)
		for m in list:
			if not seen.has(m):
				seen[m] = true
				out.append(m)
	return out


func _show_overlay() -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 128
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.05, 0.08)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(bg)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.custom_minimum_size = Vector2(520, 0)
		box.position = Vector2(-260, -60)
		box.add_theme_constant_override("separation", 12)
		_overlay.add_child(box)
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 36)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_label)
		_bar = ProgressBar.new()
		_bar.custom_minimum_size = Vector2(520, 18)
		_bar.show_percentage = false
		box.add_child(_bar)
		_sub = Label.new()
		_sub.add_theme_font_size_override("font_size", 18)
		_sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_sub)
		add_child(_overlay)
	_label.text = "Loading..."
	_sub.text = ""
	_bar.value = 0.0
	_overlay.visible = true


func _hide_overlay() -> void:
	if _overlay:
		_overlay.visible = false
