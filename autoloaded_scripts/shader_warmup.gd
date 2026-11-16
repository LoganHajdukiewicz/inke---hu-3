extends Node
## SHADER WARM-UP (fixes the "rainbow textures + slow for ~30s" start).
##
## Forward+ compiles GPU pipelines the first time each material/lighting
## combination is drawn. Until they're ready it draws with fallback shaders
## and stalls - garbled/rainbow surfaces and a crawling frame rate right
## after a level loads. On every scene change this node:
##   1. covers the screen with a "Loading..." panel and pauses the game
##   2. puts one small quad per UNIQUE material in the scene (plus the scene
##      itself, seen from the camera) in front of the camera, so the GPU
##      compiles everything now
##   3. waits until the engine reports no more pipeline compilations for a
##      moment (or a timeout), then removes the quads and unpauses
## The shader cache keeps the result, so later launches are much faster.

@export var max_wait: float = 25.0        # hard cap (seconds)
@export var quiet_time: float = 0.6       # no new compilations for this long = done

var _scene: Node = null
var _busy := false
var _overlay: CanvasLayer
var _label: Label


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


func _warm(scene: Node) -> void:
	if _busy or not is_instance_valid(scene):
		return
	_busy = true
	_show_overlay()
	var was_paused := get_tree().paused
	get_tree().paused = true
	# wait a couple of frames so the scene's own _ready()s build their meshes
	for i in range(3):
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
	# one quad per unique material (overrides, surface overrides, mesh mats)
	var seen := {}
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var i := 0
	for gi in scene.find_children("*", "GeometryInstance3D", true, false):
		var mats := []
		if gi.material_override:
			mats.append(gi.material_override)
		if gi is MeshInstance3D and gi.mesh:
			for si in range(gi.mesh.get_surface_count()):
				var m: Material = gi.get_surface_override_material(si)
				if m == null:
					m = gi.mesh.surface_get_material(si)
				if m:
					mats.append(m)
		for m in mats:
			if seen.has(m):
				continue
			seen[m] = true
			var q := MeshInstance3D.new()
			q.mesh = quad
			q.material_override = m
			q.position = Vector3((i % 20) * 0.06 - 0.6, (i / 20) * 0.06 - 0.3, 0)
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(q)
			i += 1
	_label.text = "Loading...  (preparing %d materials)" % seen.size()
	# wait for compilation to settle
	var t := 0.0
	var last := _compilations()
	var quiet := 0.0
	while t < max_wait:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var now := _compilations()
		if now != last:
			last = now
			quiet = 0.0
		else:
			quiet += dt
		# at least ~10 frames so everything got drawn once, then settle
		if t > 0.4 and quiet >= quiet_time:
			break
	holder.queue_free()
	await get_tree().process_frame
	get_tree().paused = was_paused
	_hide_overlay()
	# tell the FPS guard not to judge the frames we just spent compiling
	var gq = get_node_or_null("/root/GraphicsQuality")
	if gq and "_cooldown" in gq:
		gq._cooldown = 3.0
	_busy = false
	print("ShaderWarmup: %d materials, %.1fs" % [seen.size(), t])


func _show_overlay() -> void:
	if _overlay == null:
		_overlay = CanvasLayer.new()
		_overlay.layer = 128
		var bg := ColorRect.new()
		bg.color = Color(0.06, 0.05, 0.08)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.add_child(bg)
		_label = Label.new()
		_label.text = "Loading..."
		_label.add_theme_font_size_override("font_size", 32)
		_label.set_anchors_preset(Control.PRESET_CENTER)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_overlay.add_child(_label)
		add_child(_overlay)
	_overlay.visible = true


func _hide_overlay() -> void:
	if _overlay:
		_overlay.visible = false
