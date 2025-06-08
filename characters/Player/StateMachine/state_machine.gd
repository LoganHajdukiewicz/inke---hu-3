extends Node
class_name StateMachine

@export var initial_state: State
var current_state: State
const SPEED : float = 0.0
var states: Dictionary = {}

@onready var player: CharacterBody3D = get_parent()

func _ready():
	# Gets the States
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.state_machine = self
			child.player = player
	
	# Start with initial state
	
	if initial_state:
		current_state = initial_state
		current_state.enter()

func _process(delta):
	if current_state:
		current_state.update(delta)

func _physics_process(delta):
	if current_state:
		current_state.physics_update(delta)

func change_state(new_state_name: String):
	# Convert PascalCase node name to lowercase for lookup
	var lookup_name = new_state_name.to_lower()
	var new_state = states.get(lookup_name)
	if new_state and new_state != current_state:
		if current_state:
			current_state.exit()
		
		current_state = new_state
		current_state.enter()
		
