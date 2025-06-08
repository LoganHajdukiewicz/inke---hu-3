extends CharacterBody3D

const SPEED = 10.0
const JUMP_VELOCITY = 5

@onready var rail_grind_node = null
@onready var countdown_for_next_grind = 1.0
@onready var countdown_for_next_grind_time_left = 1.0
@onready var grind_timer_complete = true
@onready var start_grind_timer = false
var detached_from_rail: bool = false
@export var grindrays: Node3D

# Camera variables
var mouse_sensitivity := 0.002
var controller_sensitivity := 2.0
var twist_input := 0.0
var pitch_input := 0.0
var mouse_captured := false

# Camera limits
var min_pitch := -10.0
var max_pitch := 5.0

func _ready():
	# Capture mouse initially
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true

func _unhandled_input(event):
	# Handle mouse input for camera
	if event is InputEventMouseMotion and mouse_captured:
		twist_input -= event.relative.x * mouse_sensitivity
		pitch_input -= event.relative.y * mouse_sensitivity
	
	# Toggle mouse capture with escape
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

func _physics_process(delta: float) -> void:
	# Handle right stick camera input
	var right_stick_input = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if right_stick_input.length() > 0.1:  # Deadzone
		twist_input -= right_stick_input.x * controller_sensitivity * delta
		pitch_input -= right_stick_input.y * controller_sensitivity * delta
	
	# Clamp pitch to prevent over-rotation
	pitch_input = clamp(pitch_input, deg_to_rad(min_pitch), deg_to_rad(max_pitch))
	
	# Apply camera rotations
	$CameraController.rotation.y = twist_input
	$CameraController/CameraTarget.rotation.x = pitch_input
	
	# Add the gravity
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Get the input direction and handle the movement/deceleration
	var input_dir := Input.get_vector("left", "right", "forward", "back")
	# Use camera's horizontal rotation for movement direction
	var camera_basis = $CameraController.transform.basis
	var direction: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	move_and_slide()
	
	# Camera follows character
	$CameraController.position = lerp($CameraController.position, position, $CameraController.CAMERASPEED)
