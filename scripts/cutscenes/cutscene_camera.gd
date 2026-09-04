extends Camera3D
class_name CutsceneCamera

## A camera you can POSE - for cutscenes and free-roam debugging.
##
## POSING IN THE EDITOR
##   Add a CutsceneCamera node (Add Node dialog), move/rotate it like any
##   node. Select it and tick the editor's built-in "Preview" checkbox in
##   the viewport to see exactly what it sees. Save the pose in the scene.
##
## USING IT IN CUTSCENES (from any script):
##   $CutsceneCamera.activate(1.5)    # blend from gameplay cam over 1.5s
##   ...dialogue, moves, etc...
##   $CutsceneCamera.deactivate(1.0)  # blend back to gameplay cam
##   activate() also tells CutsceneManager a cutscene started (optional
##   toggle below), which hides gameplay UI.
##
## FREE ROAM / DEBUG FLY
##   Press F10 in game at ANY time - no node needed, GameManager spawns a
##   fly camera from the current view. Fly it, frame your shot, press P to
##   print the pose (position/rotation to paste into the Inspector),
##   F10 again to jump back to gameplay.
##     WASD = move   Q/E = down/up   Shift = fast   Mouse = look
##     Scroll = fly speed   P = print pose
##   The player is frozen while flying so nothing runs off a cliff.

@export_group("Cutscene")
## Seconds to glide from the gameplay camera to this one on activate().
@export var default_blend_time: float = 1.2
## Tell CutsceneManager a cutscene started/ended on activate()/deactivate()
## (hides gameplay UI like the paint HUD).
@export var reports_to_cutscene_manager: bool = true

@export_group("Fly Mode")
## Allow flying this camera at runtime while it's active (for posing).
@export var fly_enabled: bool = true
@export var fly_speed: float = 12.0
@export var fly_fast_multiplier: float = 3.5
@export var fly_mouse_sensitivity: float = 0.0022

var is_flying: bool = false            # runtime fly-control active
var _prev_camera: Camera3D = null      # camera to restore on deactivate()
var _blend_tween: Tween = null
var _yaw: float = 0.0
var _pitch: float = 0.0
var _speed_mult: float = 1.0


func _ready():
	# Never steal the view just by existing in a scene.
	if not Engine.is_editor_hint():
		current = false
	set_process(false)


# ---------------------------------------------------------------------------
# Cutscene API
# ---------------------------------------------------------------------------
func activate(blend_time: float = -1.0) -> void:
	"""Make this the live camera, gliding from the current one."""
	if blend_time < 0.0:
		blend_time = default_blend_time
	var from_cam := get_viewport().get_camera_3d()
	if from_cam != self:
		_prev_camera = from_cam
	if reports_to_cutscene_manager:
		var cm = get_node_or_null("/root/CutsceneManager")
		if cm:
			cm.start_cutscene()
	if from_cam and from_cam != self and blend_time > 0.05:
		_blend_from(from_cam.global_transform, from_cam.fov, blend_time)
	else:
		make_current()
	if fly_enabled:
		_begin_fly()


func deactivate(blend_time: float = -1.0) -> void:
	"""Hand the view back to the gameplay camera."""
	if blend_time < 0.0:
		blend_time = default_blend_time
	_end_fly()
	if reports_to_cutscene_manager:
		var cm = get_node_or_null("/root/CutsceneManager")
		if cm:
			cm.end_cutscene()
	if _prev_camera and is_instance_valid(_prev_camera):
		if blend_time > 0.05:
			# Glide back: fly a temporary clone to the gameplay cam pose,
			# then hand over.
			var pose := global_transform
			var f := fov
			_prev_camera.make_current()
			var ghost := Camera3D.new()
			get_tree().current_scene.add_child(ghost)
			ghost.global_transform = pose
			ghost.fov = f
			ghost.make_current()
			var target_cam := _prev_camera
			var tw := ghost.create_tween()
			tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tw.tween_method(func(t: float):
				if is_instance_valid(target_cam):
					ghost.global_transform = pose.interpolate_with(target_cam.global_transform, t)
					ghost.fov = lerpf(f, target_cam.fov, t)
			, 0.0, 1.0, blend_time)
			tw.tween_callback(func():
				if is_instance_valid(target_cam):
					target_cam.make_current()
				ghost.queue_free()
			)
		else:
			_prev_camera.make_current()
	_prev_camera = null


func snap_to(pose: Transform3D) -> void:
	"""Instantly move the camera to a pose (for hard cuts between shots)."""
	global_transform = pose


func move_to(pose: Transform3D, duration: float = 2.0,
		trans: Tween.TransitionType = Tween.TRANS_SINE) -> Tween:
	"""Glide this camera to a new pose - chain shots by awaiting the tween:
	   await cam.move_to(pose_b, 3.0).finished"""
	if _blend_tween and _blend_tween.is_valid():
		_blend_tween.kill()
	_blend_tween = create_tween()
	_blend_tween.set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	var start := global_transform
	_blend_tween.tween_method(func(t: float):
		global_transform = start.interpolate_with(pose, t)
	, 0.0, 1.0, duration)
	return _blend_tween


func _blend_from(from_pose: Transform3D, from_fov: float, duration: float) -> void:
	var target_pose := global_transform
	var target_fov := fov
	global_transform = from_pose
	fov = from_fov
	make_current()
	if _blend_tween and _blend_tween.is_valid():
		_blend_tween.kill()
	_blend_tween = create_tween()
	_blend_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_blend_tween.tween_method(func(t: float):
		global_transform = from_pose.interpolate_with(target_pose, t)
		fov = lerpf(from_fov, target_fov, t)
	, 0.0, 1.0, duration)


# ---------------------------------------------------------------------------
# Fly mode (runtime posing / free roam)
# ---------------------------------------------------------------------------
func _begin_fly() -> void:
	if is_flying:
		return
	is_flying = true
	_yaw = rotation.y
	_pitch = rotation.x
	_speed_mult = 1.0
	set_process(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _end_fly() -> void:
	if not is_flying:
		return
	is_flying = false
	set_process(false)


func _process(delta: float) -> void:
	if not is_flying or not current:
		return
	var speed := fly_speed * _speed_mult
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fly_fast_multiplier
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += global_transform.basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP
	if dir.length_squared() > 0.001:
		global_position += dir.normalized() * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if not is_flying or not current:
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * fly_mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * fly_mouse_sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed_mult = clampf(_speed_mult * 1.2, 0.1, 20.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed_mult = clampf(_speed_mult / 1.2, 0.1, 20.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_P:
		print_pose()
		get_viewport().set_input_as_handled()


func print_pose() -> void:
	"""Print this camera's pose in Inspector-friendly form."""
	var rd := rotation_degrees
	print("=== CutsceneCamera pose ===")
	print("  position = Vector3(%.3f, %.3f, %.3f)" % [global_position.x, global_position.y, global_position.z])
	print("  rotation_degrees = Vector3(%.2f, %.2f, %.2f)" % [rd.x, rd.y, rd.z])
	print("  fov = %.1f" % fov)
