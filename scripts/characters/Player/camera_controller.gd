extends Node3D
## Third-person camera rig - FULL REWRITE.
##
## Node structure (rebuilt in _ready, reusing the scene's Camera3D):
##
##   CameraController  (this node, top_level - smoothed follow position + YAW)
##     CameraTarget    (pivot at head height - PITCH)
##       SpringArm3D   (collision-aware arm - pulls the camera IN when walls,
##                      ceilings or props would otherwise put it outside the
##                      room. This is the "camera is outside my small room"
##                      fix: the arm shape-casts from the pivot and parks the
##                      camera just in front of whatever it hits.)
##         Camera3D    (+ shake offset applied here)
##
## Everything is Inspector-tunable. External API kept from the old camera:
##   handle_camera_input(delta), follow_character(pos, vel),
##   initialize_camera(), get_camera_forward()/get_camera_right(),
##   shake(intensity, duration), auto_behind, lock-on API,
##   transform.basis (yaw-only - movement code reads this).

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
@export_group("Look")
@export var mouse_sensitivity: float = 0.002
@export var controller_sensitivity: float = 2.0
@export var invert_y: bool = false
## Lowest the camera can look (degrees, negative = down).
@export var pitch_min_degrees: float = -65.0
## Highest the camera can look (degrees).
@export var pitch_max_degrees: float = 45.0

@export_group("Framing")
## How far behind the player the camera wants to sit. Change it live in
## the Inspector (runtime too) - the spring arm follows this value.
@export var camera_distance: float = 14.0:
	set(v):
		camera_distance = v
		if spring_arm:
			spring_arm.spring_length = v
			_smoothed_arm_length = v
## Pivot height above the player's feet (roughly head height).
@export var pivot_height: float = 2.1
## Default downward look angle when the game starts.
@export var default_pitch_degrees: float = -12.0

@export_group("Follow")
## How quickly the rig position catches up to the player (higher = snappier).
@export var follow_speed: float = 9.0
## Extra catch-up at high player speeds so fast movement never outruns the camera.
@export var follow_speed_fast: float = 14.0
@export var fast_speed_threshold: float = 12.0

@export_group("Collision")
## Physics layers the camera arm collides with (world geometry).
@export_flags_3d_physics var collision_mask: int = 1
## Gap kept between the camera and the surface it hit.
@export var collision_margin: float = 0.3
## Radius of the sphere the arm sweeps (bigger = camera avoids corners sooner
## and never lets walls clip into the near plane).
@export var collision_sphere_radius: float = 0.4
## How fast the camera glides back OUT after an obstruction clears.
## (Pulling IN is instant so geometry never occludes the player.)
@export var reexpand_speed: float = 6.0

@export_group("Speed FOV")
@export var fov_kick_enabled: bool = true
@export var base_fov: float = 75.0
@export var max_fov: float = 92.0
@export var fov_kick_start_speed: float = 12.0
@export var fov_max_speed: float = 40.0
@export var fov_lerp_speed: float = 4.0

@export_group("Lock On")
@export var lock_on_range: float = 30.0
@export var lock_on_turn_speed: float = 0.3
@export var lock_on_switch_cooldown: float = 0.3

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var twist_input: float = 0.0          # yaw (radians)
var pitch_input: float = 0.0          # pitch (radians)
var mouse_captured: bool = false

var lock_on_active: bool = false
var locked_target: Node3D = null
var lock_on_switch_timer: float = 0.0

# Auto-behind mode (balance beams etc.): the camera swings around to sit
# directly behind the player's facing direction.
var auto_behind: bool = false
const AUTO_BEHIND_SPEED: float = 3.5

var character: Node3D = null
var camera_target: Node3D = null      # pitch pivot
var spring_arm: SpringArm3D = null
var arm_end: Node3D = null            # placed BY the arm; camera hangs off it
var camera_3d: Camera3D = null

var _rad_pitch_min: float
var _rad_pitch_max: float
var _smoothed_arm_length: float = 0.0

# Camera shake
var shake_time_left: float = 0.0
var shake_strength: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO

# Zoom punch (cred pickups etc.)
var _zoom_fov_offset: float = 0.0


func _ready():
	_rad_pitch_min = deg_to_rad(pitch_min_degrees)
	_rad_pitch_max = deg_to_rad(pitch_max_degrees)
	pitch_input = deg_to_rad(default_pitch_degrees)
	
	if get_parent() is CharacterBody3D:
		character = get_parent()
	
	_build_rig()
	
	if character:
		global_position = character.global_position
		rotation.y = character.rotation.y
		twist_input = character.rotation.y


func _build_rig() -> void:
	"""Assemble pivot -> spring arm -> camera, reusing whatever the scene
	already has so saved Camera3D settings (fov, environment...) survive."""
	camera_target = get_node_or_null("CameraTarget")
	if camera_target == null:
		camera_target = Node3D.new()
		camera_target.name = "CameraTarget"
		add_child(camera_target)
	# The pivot sits at head height with NO baked tilt/offset - pitch is
	# applied as pure rotation and the spring arm handles the distance.
	camera_target.transform = Transform3D.IDENTITY
	camera_target.position = Vector3(0, pivot_height, 0)
	
	# Find an existing camera anywhere under us (the old scene had it as a
	# direct child of CameraTarget).
	camera_3d = _find_camera(self)
	
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm3D"
	spring_arm.collision_mask = collision_mask
	spring_arm.margin = collision_margin
	spring_arm.spring_length = camera_distance
	var sphere := SphereShape3D.new()
	sphere.radius = collision_sphere_radius
	spring_arm.shape = sphere
	camera_target.add_child(spring_arm)
	if character:
		spring_arm.add_excluded_object(character.get_rid())
	
	# IMPORTANT STRUCTURE: SpringArm3D repositions its DIRECT children every
	# physics tick. If the camera were a direct child, any code writing
	# camera_3d.position (shake, smoothing) would fight the arm and win on
	# render frames - the camera ends up glued to the pivot (~2m from the
	# player, 'unplayably close'). So the arm owns a bare ArmEnd node and
	# the camera hangs OFF ArmEnd with a local offset the arm never touches.
	arm_end = Node3D.new()
	arm_end.name = "ArmEnd"
	spring_arm.add_child(arm_end)
	
	if camera_3d == null:
		camera_3d = Camera3D.new()
		camera_3d.name = "Camera3D"
		camera_3d.current = true
	elif camera_3d.get_parent():
		camera_3d.get_parent().remove_child(camera_3d)
	arm_end.add_child(camera_3d)
	camera_3d.transform = Transform3D.IDENTITY
	camera_3d.fov = base_fov
	_smoothed_arm_length = camera_distance


func _find_camera(node: Node) -> Camera3D:
	for c in node.get_children():
		if c is Camera3D:
			return c
		var found := _find_camera(c)
		if found:
			return found
	return null


func initialize_camera():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


# ---------------------------------------------------------------------------
# Per-frame driving (called from the player)
# ---------------------------------------------------------------------------
func _process(delta: float):
	_update_shake(delta)
	
	if lock_on_switch_timer > 0.0:
		lock_on_switch_timer -= delta
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock_on()
	if lock_on_active and lock_on_switch_timer <= 0.0:
		_check_lock_on_switch()
	
	_update_arm(delta)


func handle_camera_input(delta: float):
	if lock_on_active and is_instance_valid(locked_target):
		_handle_lock_on_camera(delta)
	elif auto_behind:
		_handle_auto_behind_camera(delta)
	else:
		_handle_free_camera(delta)
	_update_fov_kick(delta)


func _handle_free_camera(delta: float):
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick.length_squared() > 0.01:
		twist_input -= stick.x * controller_sensitivity * delta
		var y := stick.y * controller_sensitivity * delta
		pitch_input += y if invert_y else -y
	_apply_rotation()


func _handle_auto_behind_camera(delta: float):
	"""Swing around to sit directly behind the player's facing (balance
	beams). Pitch stays player-controlled."""
	if not character:
		_handle_free_camera(delta)
		return
	twist_input = lerp_angle(twist_input, character.rotation.y, clampf(AUTO_BEHIND_SPEED * delta, 0.0, 1.0))
	_apply_rotation()


func _handle_lock_on_camera(_delta: float):
	if not is_instance_valid(locked_target):
		disable_lock_on()
		return
	var char_pos: Vector3 = character.global_position if character else global_position
	var to_target: Vector3 = locked_target.global_position - char_pos
	var distance := to_target.length()
	if distance > lock_on_range:
		disable_lock_on()
		return
	var target_yaw := atan2(-to_target.x, -to_target.z)
	var target_pitch := asin(clampf(to_target.y / maxf(distance, 0.001), -1.0, 1.0))
	twist_input = lerp_angle(twist_input, target_yaw, lock_on_turn_speed)
	pitch_input = lerp_angle(pitch_input, target_pitch, lock_on_turn_speed)
	_apply_rotation()


func _apply_rotation():
	pitch_input = clampf(pitch_input, _rad_pitch_min, _rad_pitch_max)
	rotation.y = twist_input
	if camera_target:
		camera_target.rotation.x = pitch_input


func follow_character(character_position: Vector3, character_velocity: Vector3 = Vector3.ZERO):
	"""Smoothly follow the player. Frame-rate independent exponential
	smoothing; catches up faster when the player is moving fast."""
	var delta := get_physics_process_delta_time()
	var h_speed := Vector2(character_velocity.x, character_velocity.z).length()
	var speed := follow_speed
	if h_speed > fast_speed_threshold:
		var t: float = clampf((h_speed - fast_speed_threshold) * 0.1, 0.0, 1.0)
		speed = lerpf(follow_speed, follow_speed_fast, t)
	var alpha := 1.0 - exp(-speed * delta)
	position = position.lerp(character_position, alpha)


func _update_arm(delta: float):
	"""Enclosed-space handling. The SpringArm sweeps a sphere and yields a
	hit length; we snap IN instantly (never let a wall occlude the player)
	but glide back OUT smoothly so clearing a doorway doesn't yank the
	camera."""
	if spring_arm == null:
		return
	# IMPORTANT: spring_length stays at FULL distance so the arm always
	# casts the whole way (shortening it here deadlocks the arm: a capped
	# cast can never report anything farther than the cap). The arm places
	# the camera at the hit instantly (pull-in is immediate = never
	# occluded); re-expansion is smoothed with a local camera offset.
	spring_arm.spring_length = camera_distance
	var hit: float = spring_arm.get_hit_length()
	if hit < _smoothed_arm_length:
		_smoothed_arm_length = hit                      # pull in NOW
	else:
		_smoothed_arm_length = lerpf(_smoothed_arm_length, hit, clampf(reexpand_speed * delta, 0.0, 1.0))
	# The arm parks ArmEnd at `hit`; nudge the camera back toward the player
	# by the not-yet-re-expanded amount (offset <= 0 keeps us inside the
	# swept safe corridor, so this never clips into geometry). The offset
	# lives on camera_3d (child of ArmEnd) - NEVER on a direct arm child.
	if camera_3d:
		camera_3d.position = shake_offset + Vector3(0, 0, _smoothed_arm_length - hit)


func _update_fov_kick(delta: float):
	if not camera_3d or not character:
		return
	var target_fov := base_fov
	if fov_kick_enabled:
		var h_speed := Vector2(character.velocity.x, character.velocity.z).length()
		var t := clampf((h_speed - fov_kick_start_speed) / maxf(fov_max_speed - fov_kick_start_speed, 0.01), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		target_fov = lerpf(base_fov, max_fov, t)
	target_fov += _zoom_fov_offset
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, clampf(fov_lerp_speed * delta, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Shake / zoom effects
# ---------------------------------------------------------------------------
func shake(intensity: float = 0.3, duration: float = 0.25):
	shake_strength = maxf(shake_strength, intensity)
	shake_time_left = maxf(shake_time_left, duration)


func _update_shake(delta: float):
	if shake_time_left > 0.0:
		shake_time_left -= delta
		var amount: float = shake_strength * clampf(shake_time_left / 0.25, 0.0, 1.0)
		shake_offset = Vector3(
			randf_range(-amount, amount),
			randf_range(-amount, amount),
			randf_range(-amount, amount)
		)
		if shake_time_left <= 0.0:
			shake_strength = 0.0
			shake_offset = Vector3.ZERO
	else:
		shake_offset = Vector3.ZERO


func start_zoom_effect(strength: float = 0.3, duration: float = 0.6):
	"""Brief FOV punch-in (cred pickups etc.)."""
	var tween := create_tween()
	tween.tween_property(self, "_zoom_fov_offset", -base_fov * clampf(strength, 0.0, 0.8), duration * 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_zoom_fov_offset", 0.0, duration * 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Lock-on
# ---------------------------------------------------------------------------
func toggle_lock_on():
	if lock_on_active:
		disable_lock_on()
	else:
		enable_lock_on()


func enable_lock_on():
	var nearest := _find_nearest_enemy()
	if nearest:
		lock_on_active = true
		locked_target = nearest


func disable_lock_on():
	lock_on_active = false
	locked_target = null


func _find_nearest_enemy() -> Node3D:
	var enemies := get_tree().get_nodes_in_group("Enemy")
	var nearest: Node3D = null
	var nearest_sq := lock_on_range * lock_on_range
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < nearest_sq:
			nearest_sq = d
			nearest = enemy
	return nearest


func _check_lock_on_switch():
	var camera_input := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if camera_input.length_squared() < 0.5:
		return
	var switch_direction := Vector3(camera_input.x, 0, camera_input.y).normalized()
	var new_target := _find_target_in_direction(switch_direction)
	if new_target and new_target != locked_target:
		locked_target = new_target
		lock_on_switch_timer = lock_on_switch_cooldown


func _find_target_in_direction(direction: Vector3) -> Node3D:
	var best_target: Node3D = null
	var best_score: float = -1.0
	var world_direction := global_transform.basis * direction
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D or enemy == locked_target:
			continue
		var to_enemy: Vector3 = enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance > lock_on_range:
			continue
		var alignment := to_enemy.normalized().dot(world_direction)
		var score := alignment / (distance * 0.1 + 1.0)
		if score > best_score:
			best_score = score
			best_target = enemy
	return best_target


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured and not lock_on_active:
		twist_input -= event.relative.x * mouse_sensitivity
		var y: float = event.relative.y * mouse_sensitivity
		pitch_input += y if invert_y else -y
	
	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE)
	
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func get_camera_forward() -> Vector3:
	return -camera_target.global_transform.basis.z


func get_camera_right() -> Vector3:
	return camera_target.global_transform.basis.x


func is_locked_on() -> bool:
	return lock_on_active


func get_locked_target() -> Node3D:
	return locked_target if lock_on_active else null
