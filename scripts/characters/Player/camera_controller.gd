extends Node3D

# Camera Speed as a Decimal Percent.
const BASE_CAMERA_SPEED : float = 0.15
const FAST_CAMERA_SPEED : float = 0.25
const SPEED_THRESHOLD : float = 12.0  # Speed above which we use faster camera

# Camera Limits
const MIN_PITCH : float = -10.0
const MAX_PITCH : float = 5.0

# Camera variables
var mouse_sensitivity := 0.002
var controller_sensitivity := 2.0
var twist_input := 0.0
var pitch_input := 0.0
var mouse_captured := false

func initialize_camera():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func handle_camera_input(delta: float):
	# Handle right stick camera input
	var right_stick_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if right_stick_input.length() > 0.1:  # Deadzone
		twist_input -= right_stick_input.x * controller_sensitivity * delta
		pitch_input -= right_stick_input.y * controller_sensitivity * delta
	
	# Clamp pitch to prevent over-rotation
	pitch_input = clamp(pitch_input, deg_to_rad(MIN_PITCH), deg_to_rad(MAX_PITCH))
	
	# Apply camera rotations
	rotation.y = twist_input
	$CameraTarget.rotation.x = pitch_input

func follow_character(character_position: Vector3, character_velocity: Vector3 = Vector3.ZERO):
	# Calculate horizontal speed of the character
	var horizontal_speed = Vector2(character_velocity.x, character_velocity.z).length()
	
	# Use faster camera speed when character is moving fast
	var camera_speed = BASE_CAMERA_SPEED
	if horizontal_speed > SPEED_THRESHOLD:
		# Interpolate between base and fast speed based on character speed
		var speed_factor = min((horizontal_speed - SPEED_THRESHOLD) / 10.0, 1.0)
		camera_speed = lerp(BASE_CAMERA_SPEED, FAST_CAMERA_SPEED, speed_factor)
	
	position = lerp(position, character_position, camera_speed)

func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured:
		twist_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity
	
	if event.is_action_pressed("ui_cancel"):
		if mouse_captured:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_captured = false
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			mouse_captured = true
	
	# Click to capture mouse
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true
