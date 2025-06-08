extends CharacterBody3D


# Initalizes the State Machine
@onready var state_machine: StateMachine = $StateMachine

func _ready():
	# Let the camera handle mouse capture
	$CameraController.initialize_camera()

func _physics_process(delta: float) -> void:
	# Let camera handle its own input and rotation
	$CameraController.handle_camera_input(delta)
	
	# Camera follows character
	$CameraController.follow_character(position)

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()
