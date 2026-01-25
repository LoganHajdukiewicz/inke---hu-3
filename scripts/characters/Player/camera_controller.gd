extends Node3D

# Camera Speed as a Decimal Percent
const BASE_CAMERA_SPEED: float = 0.15
const FAST_CAMERA_SPEED: float = 0.25
const SPEED_THRESHOLD: float = 12.0
const LOCK_ON_SPEED: float = 0.3

# Camera Limits
const MIN_PITCH: float = -40.0
const MAX_PITCH: float = 25.0

# Lock-on settings
const LOCK_ON_RANGE: float = 30.0
const LOCK_ON_SWITCH_COOLDOWN: float = 0.3

# Camera variables
var mouse_sensitivity: float = 0.002
var controller_sensitivity: float = 2.0
var twist_input: float = 0.0
var pitch_input: float = 0.0
var mouse_captured: bool = false

# Lock-on system
var lock_on_active: bool = false
var locked_target: Node3D = null
var lock_on_switch_timer: float = 0.0

# Cached references
var character: Node3D = null
var camera_target: Node3D = null

# Pre-calculated values
var rad_min_pitch: float
var rad_max_pitch: float

func _ready():
	# Cache the camera target node
	camera_target = $CameraTarget
	
	# Pre-calculate radians for pitch limits
	rad_min_pitch = deg_to_rad(MIN_PITCH)
	rad_max_pitch = deg_to_rad(MAX_PITCH)
	
	# Initialize relative to parent character
	if get_parent() is CharacterBody3D:
		character = get_parent()
		_initialize_relative_position()

func _initialize_relative_position():
	"""Set initial camera position relative to character"""
	if character:
		# Start camera behind and above the character
		global_position = character.global_position
		# Initial rotation can be set to face the character's forward direction
		rotation.y = character.rotation.y

func initialize_camera():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func _process(delta: float):
	# Update lock-on timer
	if lock_on_switch_timer > 0.0:
		lock_on_switch_timer -= delta
	
	# Handle lock-on toggle
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock_on()
	
	# Handle lock-on switching
	if lock_on_active and lock_on_switch_timer <= 0.0:
		_check_lock_on_switch()

func handle_camera_input(delta: float):
	if lock_on_active and is_instance_valid(locked_target):
		_handle_lock_on_camera(delta)
	else:
		_handle_free_camera(delta)

func _handle_free_camera(delta: float):
	"""Handle normal free camera movement"""
	# Handle right stick camera input
	var right_stick_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if right_stick_input.length_squared() > 0.01:  # Squared for optimization
		twist_input -= right_stick_input.x * controller_sensitivity * delta
		pitch_input -= right_stick_input.y * controller_sensitivity * delta
	
	# Clamp pitch to prevent over-rotation
	pitch_input = clamp(pitch_input, rad_min_pitch, rad_max_pitch)
	
	# Apply camera rotations
	rotation.y = twist_input
	camera_target.rotation.x = pitch_input

func _handle_lock_on_camera(_delta: float):
	"""Handle camera when locked onto target"""
	if not is_instance_valid(locked_target):
		disable_lock_on()
		return
	
	# Calculate direction to target from character position
	var char_pos = character.global_position if character else global_position
	var direction_to_target = locked_target.global_position - char_pos
	var distance = direction_to_target.length()
	
	# Check if target is out of range
	if distance > LOCK_ON_RANGE:
		disable_lock_on()
		return
	
	# Calculate desired rotation (fixed direction)
	var target_rotation_y = atan2(-direction_to_target.x, -direction_to_target.z)
	var target_rotation_x = asin(direction_to_target.y / distance)
	
	# Smoothly interpolate to target rotation
	twist_input = lerp_angle(twist_input, target_rotation_y, LOCK_ON_SPEED)
	pitch_input = lerp_angle(pitch_input, target_rotation_x, LOCK_ON_SPEED)
	
	# Clamp pitch
	pitch_input = clamp(pitch_input, rad_min_pitch, rad_max_pitch)
	
	# Apply rotations
	rotation.y = twist_input
	camera_target.rotation.x = pitch_input

func follow_character(character_position: Vector3, character_velocity: Vector3 = Vector3.ZERO):
	"""Follow the character with dynamic camera speed"""
	# Use squared length for optimization (avoid sqrt)
	var horizontal_speed_sq = character_velocity.x * character_velocity.x + character_velocity.z * character_velocity.z
	var threshold_sq = SPEED_THRESHOLD * SPEED_THRESHOLD
	
	# Calculate camera speed based on character velocity
	var camera_speed = BASE_CAMERA_SPEED
	if horizontal_speed_sq > threshold_sq:
		var horizontal_speed = sqrt(horizontal_speed_sq)
		var speed_factor = min((horizontal_speed - SPEED_THRESHOLD) * 0.1, 1.0)
		camera_speed = lerp(BASE_CAMERA_SPEED, FAST_CAMERA_SPEED, speed_factor)
	
	position = lerp(position, character_position, camera_speed)

func toggle_lock_on():
	"""Toggle lock-on mode"""
	if lock_on_active:
		disable_lock_on()
	else:
		enable_lock_on()

func enable_lock_on():
	"""Enable lock-on and find nearest target"""
	var nearest_enemy = _find_nearest_enemy()
	if nearest_enemy:
		lock_on_active = true
		locked_target = nearest_enemy
		print("Locked onto: ", locked_target.name)
	else:
		print("No enemies in range to lock onto")

func disable_lock_on():
	"""Disable lock-on mode"""
	lock_on_active = false
	locked_target = null
	print("Lock-on disabled")

func _find_nearest_enemy() -> Node3D:
	"""Find the nearest enemy within lock-on range"""
	var enemies = get_tree().get_nodes_in_group("Enemy")
	if enemies.is_empty():
		return null
	
	var nearest: Node3D = null
	var nearest_distance_sq: float = LOCK_ON_RANGE * LOCK_ON_RANGE
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		
		var distance_sq = global_position.distance_squared_to(enemy.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = enemy
	
	return nearest

func _check_lock_on_switch():
	"""Check if player wants to switch lock-on target"""
	var camera_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	
	# Only switch if there's significant input
	if camera_input.length_squared() < 0.5:
		return
	
	var switch_direction = Vector3(camera_input.x, 0, camera_input.y).normalized()
	var new_target = _find_target_in_direction(switch_direction)
	
	if new_target and new_target != locked_target:
		locked_target = new_target
		lock_on_switch_timer = LOCK_ON_SWITCH_COOLDOWN
		print("Switched lock-on to: ", locked_target.name)

func _find_target_in_direction(direction: Vector3) -> Node3D:
	"""Find the best target in the given direction"""
	var enemies = get_tree().get_nodes_in_group("Enemy")
	if enemies.is_empty():
		return null
	
	var best_target: Node3D = null
	var best_score: float = -1.0
	
	# Transform direction to world space
	var world_direction = global_transform.basis * direction
	
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		
		if enemy == locked_target:
			continue
		
		var to_enemy = enemy.global_position - global_position
		var distance = to_enemy.length()
		
		if distance > LOCK_ON_RANGE:
			continue
		
		# Calculate how aligned the enemy is with the desired direction
		var alignment = to_enemy.normalized().dot(world_direction)
		
		# Score based on alignment and distance (favor closer and more aligned)
		var score = alignment / (distance * 0.1 + 1.0)
		
		if score > best_score:
			best_score = score
			best_target = enemy
	
	return best_target

func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured:
		if not lock_on_active:  # Don't process mouse movement during lock-on
			twist_input -= event.relative.x * mouse_sensitivity
			pitch_input -= event.relative.y * mouse_sensitivity
	
	if event.is_action_pressed("ui_cancel"):
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE)
	
	# Click to capture mouse
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true

# Public API for external scripts
func get_camera_forward() -> Vector3:
	"""Get the forward direction of the camera"""
	return -camera_target.global_transform.basis.z

func get_camera_right() -> Vector3:
	"""Get the right direction of the camera"""
	return camera_target.global_transform.basis.x

func is_locked_on() -> bool:
	"""Check if camera is currently locked onto a target"""
	return lock_on_active

func get_locked_target() -> Node3D:
	"""Get the current locked target"""
	return locked_target if lock_on_active else null
