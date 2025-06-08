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
	print("Checking for rail grinding...")
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	print("Current state: ", current_state_name)
	
	if current_state_name != "RailGrindingState":
		var rail_grinding_state = state_machine.states.get("railgrindingstate")
		
		if rail_grinding_state and rail_grinding_state.grind_timer_complete:
			print("Grind timer allows grinding")
			var grind_ray = get_valid_grind_ray()
			if grind_ray:
				print("Valid grind ray found - starting grinding!")
				state_machine.change_state("RailGrindingState")
				rail_grinding_state.setup_grinding(grind_ray)
			else:
				print("No valid grind ray found")
		else:
			print("Grind timer not ready or rail grinding state not found")
	else:
		print("Already grinding")

func get_valid_grind_ray():
	print("=== GRIND RAY DEBUG ===")
	
	if not grindrays:
		print("ERROR: grindrays node is null!")
		return null
	
	print("grindrays node found: ", grindrays.name)
	print("Number of children: ", grindrays.get_children().size())
	
	for i in range(grindrays.get_children().size()):
		var grind_ray = grindrays.get_children()[i]
		print("\n--- Ray ", i, ": ", grind_ray.name, " ---")
		print("Type: ", grind_ray.get_class())
		
		if not grind_ray is RayCast3D:
			print("ERROR: Child is not a RayCast3D!")
			continue
		
		var raycast = grind_ray as RayCast3D
		print("Enabled: ", raycast.enabled)
		print("Is colliding: ", raycast.is_colliding())
		print("Target position: ", raycast.target_position)
		print("Global position: ", raycast.global_position)
		print("Global target: ", raycast.global_position + raycast.target_position)
		print("Collision mask: ", raycast.collision_mask)
		
		if raycast.is_colliding():
			var collider = raycast.get_collider()
			print("Collider found: ", collider)
			print("Collider name: ", collider.name if collider else "None")
			print("Collider class: ", collider.get_class() if collider else "None")
			print("Collider groups: ", collider.get_groups() if collider else "None")
			print("Collision point: ", raycast.get_collision_point())
			
			if collider and collider.is_in_group("Rail"):
				print("✓ VALID RAIL FOUND!")
				return raycast
			else:
				print("✗ Not in Rail group or no collider")
		else:
			print("No collision detected")
	
	print("\n=== END DEBUG ===")
	return null

# Getter for grinding state - now checks the actual state machine
func is_grinding() -> bool:
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	return current_state_name == "RailGrindingState"
