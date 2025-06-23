extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0
var gear_count: int = 0

# Double jump variables
var double_jump_unlocked: bool = false
var has_double_jumped: bool = false
var can_double_jump: bool = false

@export var grindrays: Node3D

# References
@onready var player = self
#@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Initialize the State Machine
@onready var state_machine: StateMachine = $StateMachine

func _ready():
	$CameraController.initialize_camera()
	
	# Load double jump status from merchant
	var merchant_script = load("res://characters/merchant.gd")
	if merchant_script:
		double_jump_unlocked = merchant_script.double_jump_purchased

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)
	
	# Check for rail grinding opportunity (only if not already grinding and timer is complete)
	check_for_rail_grinding()
	
	# Handle double jump reset when on floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
	
	$CameraController.follow_character(position, velocity)

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()

func unlock_double_jump():
	"""Called by the merchant when double jump is purchased"""
	double_jump_unlocked = true
	print("Double jump unlocked!")

func can_perform_double_jump() -> bool:
	"""Check if the player can perform a double jump"""
	return double_jump_unlocked and not has_double_jumped and can_double_jump and not is_on_floor()

func perform_double_jump():
	"""Execute the double jump"""
	if can_perform_double_jump():
		velocity.y = jump_velocity
		has_double_jumped = true
		can_double_jump = false
		print("Double jump performed!")
		return true
	return false

## Rail Grinding Logic

func check_for_rail_grinding():
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	
	if current_state_name != "RailGrindingState":
		var rail_grinding_state = state_machine.states.get("railgrindingstate")
		
		if rail_grinding_state and rail_grinding_state.grind_timer_complete:
			var grind_ray = get_valid_grind_ray()
			if grind_ray:
				state_machine.change_state("RailGrindingState")
				rail_grinding_state.setup_grinding(grind_ray)

func get_valid_grind_ray():
	for i in range(grindrays.get_children().size()):
		var grind_ray = grindrays.get_children()[i]
		
		if not grind_ray is RayCast3D:
			continue
		
		var raycast = grind_ray as RayCast3D
		
		if raycast.is_colliding():
			var collider = raycast.get_collider()	
			if collider and collider.is_in_group("Rail"):
				return raycast
