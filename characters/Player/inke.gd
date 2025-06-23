extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0
var gear_count: int = 0


@export var grindrays: Node3D

# References
@onready var player = self
#@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Initialize the State Machine
@onready var state_machine: StateMachine = $StateMachine

func _ready():
	$CameraController.initialize_camera()

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)
	
	# Check for rail grinding opportunity (only if not already grinding and timer is complete)
	check_for_rail_grinding()
	
	$CameraController.follow_character(position, velocity)

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()


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
