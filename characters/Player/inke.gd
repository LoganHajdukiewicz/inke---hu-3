extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0

@export var grindrays: Node3D

# References
@onready var player = self
#@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Initialize the State Machine
@onready var state_machine: StateMachine = $StateMachine

func _ready():
	# Let the camera handle mouse capture
	$CameraController.initialize_camera()

func _physics_process(delta: float) -> void:
	# Let camera handle its own input and rotation
	$CameraController.handle_camera_input(delta)
	
	# Check for rail grinding opportunity (only if not already grinding and timer is complete)
	check_for_rail_grinding()
	
	# Camera follows character with velocity for dynamic camera speed
	$CameraController.follow_character(position, velocity)

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()

func check_for_rail_grinding():
	# Only check for grinding if we're not already grinding and the grind timer allows it
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	
	if current_state_name != "RailGrindingState":
		var rail_grinding_state = state_machine.states.get("railgrindingstate")
		
		# Check if grind timer allows new grinding
		if rail_grinding_state and rail_grinding_state.grind_timer_complete:
			var grind_ray = get_valid_grind_ray()
			if grind_ray:
				# Transition to rail grinding state
				state_machine.change_state("RailGrindingState")
				# Set up the grinding after state change
				rail_grinding_state.setup_grinding(grind_ray)

func get_valid_grind_ray():
	if not grindrays:
		return null
		
	for grind_ray in grindrays.get_children():
		if grind_ray.is_colliding() and grind_ray.get_collider() and grind_ray.get_collider().is_in_group("Rail"):
			return grind_ray
	
	return null

# Getter for grinding state - now checks the actual state machine
func is_grinding() -> bool:
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	return current_state_name == "RailGrindingState"
