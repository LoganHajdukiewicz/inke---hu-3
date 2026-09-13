extends Node

## GhostRecorder (autoload) - MARIO KART GHOST for debugging.
##
## Silently records the player's path every session (position + facing,
## 10 samples/sec, per scene). Press F7 to spawn a 50%-transparent ghost
## that replays LAST session's path through the current level - watch
## where you (or a playtester) actually went. F7 again removes it.
##
## Recordings are saved per scene to user://ghosts/{scene}.ghost on scene
## change and quit. Only the LAST completed session is kept - the current
## session's recording replaces it when the scene is left.
##
## The ghost is visual-only: no collision, no physics, can't touch
## gameplay. It plays the path once, holds a beat, then loops.

const SAMPLE_INTERVAL := 0.1        # 10 Hz
const GHOST_DIR := "user://ghosts"
const GHOST_ALPHA := 0.5            # 50% transparent, as ordered

var _samples: PackedFloat32Array = PackedFloat32Array()  # x,y,z,yaw per sample
var _sample_timer := 0.0
var _recording_scene: String = ""

var _ghost: Node3D = null
var _ghost_data: PackedFloat32Array = PackedFloat32Array()
var _ghost_time := 0.0
var _ghost_playing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	get_tree().node_removed.connect(_on_node_removed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		# Stop listening the moment shutdown starts - node_removed fires for
		# EVERY node during teardown and the tree reference goes stale.
		var tree := get_tree() if is_inside_tree() else null
		if tree and tree.node_removed.is_connected(_on_node_removed):
			tree.node_removed.disconnect(_on_node_removed)
		_flush_recording()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F7 or event.physical_keycode == KEY_F7:
			toggle_ghost()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	# --- Record the live player --------------------------------------------
	var player := _find_player()
	if player:
		var scene = get_tree().current_scene
		var scene_key := _scene_key(scene)
		if scene_key != _recording_scene:
			_flush_recording()          # Leaving a scene saves its recording
			_recording_scene = scene_key
			_samples = PackedFloat32Array()
			_sample_timer = 0.0
		_sample_timer -= delta
		if _sample_timer <= 0.0:
			_sample_timer = SAMPLE_INTERVAL
			_samples.append(player.global_position.x)
			_samples.append(player.global_position.y)
			_samples.append(player.global_position.z)
			_samples.append(player.rotation.y)
	
	# --- Play the ghost ------------------------------------------------------
	if _ghost_playing and _ghost and is_instance_valid(_ghost):
		_advance_ghost(delta)


# =========================================================================
# PUBLIC API
# =========================================================================

func toggle_ghost() -> void:
	"""F7: show/hide last session's ghost for the current scene."""
	if _ghost_playing:
		stop_ghost()
		return
	var scene = get_tree().current_scene
	if scene == null:
		return
	_ghost_data = _load_ghost(_scene_key(scene))
	if _ghost_data.size() < 8:
		_toast("NO GHOST RECORDED FOR THIS LEVEL YET - PLAY A SESSION FIRST (path saves when you leave the level or quit)")
		return
	_spawn_ghost()
	_ghost_time = 0.0
	_ghost_playing = true
	_toast("GHOST PLAYBACK ON - LAST SESSION'S PATH (F7 to hide)")


func stop_ghost() -> void:
	_ghost_playing = false
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


# =========================================================================
# RECORDING
# =========================================================================

func _find_player() -> CharacterBody3D:
	var players = get_tree().get_nodes_in_group("Player")
	return players[0] if players.size() > 0 else null


func _scene_key(scene: Node) -> String:
	if scene == null:
		return ""
	var path := scene.scene_file_path
	if path == "":
		path = str(scene.name)
	return path.get_file().get_basename()


func _on_node_removed(node: Node) -> void:
	# Scene root being removed = scene change; save the session's path.
	# HARD GUARDS: during app quit this fires for every node while the
	# tree is being torn down - get_tree() can be null (we may already be
	# outside the tree ourselves). Bailing silently keeps F1-quit clean.
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	if node == tree.current_scene:
		_flush_recording()
		stop_ghost()


func _flush_recording() -> void:
	"""Persist the current session's path as the new 'last session'."""
	if _recording_scene == "" or _samples.size() < 8:
		return
	var f = FileAccess.open(GHOST_DIR + "/" + _recording_scene + ".ghost", FileAccess.WRITE)
	if f:
		f.store_32(_samples.size())
		for v in _samples:
			f.store_float(v)
		f.close()
	_samples = PackedFloat32Array()
	_recording_scene = ""


func _load_ghost(scene_key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var path := GHOST_DIR + "/" + scene_key + ".ghost"
	if not FileAccess.file_exists(path):
		return out
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var count := f.get_32()
	for i in range(count):
		out.append(f.get_float())
	f.close()
	return out


# =========================================================================
# PLAYBACK
# =========================================================================

func _advance_ghost(delta: float) -> void:
	_ghost_time += delta
	var n := _ghost_data.size() / 4
	var total := (n - 1) * SAMPLE_INTERVAL
	var t := fmod(_ghost_time, total + 1.5)   # Loop with a 1.5s hold at the end
	if t > total:
		t = total
	var idx := int(t / SAMPLE_INTERVAL)
	var frac := (t - idx * SAMPLE_INTERVAL) / SAMPLE_INTERVAL
	var i0 := mini(idx, n - 1) * 4
	var i1 := mini(idx + 1, n - 1) * 4
	var p0 := Vector3(_ghost_data[i0], _ghost_data[i0 + 1], _ghost_data[i0 + 2])
	var p1 := Vector3(_ghost_data[i1], _ghost_data[i1 + 1], _ghost_data[i1 + 2])
	_ghost.global_position = p0.lerp(p1, frac)
	_ghost.rotation.y = lerp_angle(_ghost_data[i0 + 3], _ghost_data[i1 + 3], frac)


func _spawn_ghost() -> void:
	stop_ghost()
	var scene = get_tree().current_scene
	if scene == null:
		return
	_ghost = Node3D.new()
	_ghost.name = "SessionGhost"
	scene.add_child(_ghost)
	
	# Ghost-Inke: capsule body + head sphere, 50% transparent cyan-white
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.9, 1.0, GHOST_ALPHA)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	mat.emission_energy_multiplier = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.5
	body.mesh = cap
	body.material_override = mat
	body.position.y = 0.75
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(body)
	
	# Face marker so you can read which way the ghost was looking
	var visor := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.1, 0.08)
	visor.mesh = box
	visor.material_override = mat
	visor.position = Vector3(0, 1.25, -0.32)
	visor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.add_child(visor)


func _toast(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)
	var label := Label.new()
	label.text = "  " + text + "  "
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position.y = -90
	layer.add_child(label)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(layer.queue_free)
