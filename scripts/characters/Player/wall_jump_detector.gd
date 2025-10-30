extends Node
class_name WallJumpDetector

var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0

var player: CharacterBody3D
var state_machine: StateMachine
var game_manager
var wall_jump_rays: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	state_machine = player.get_node("StateMachine")
	game_manager = get_node("/root/GameManager")
	wall_jump_rays = player.get_node("WallJumpRays") if player.has_node("WallJumpRays") else null

func _physics_process(delta):
	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta
	
	check_for_wall_jump()

func can_perform_wall_jump() -> bool:
	"""Check if the player can perform a wall jump"""
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	var can_wall_jump_ability = game_manager.can_wall_jump() if game_manager else false
	return (can_wall_jump_ability and 
			not player.is_on_floor() and 
			wall_jump_cooldown <= 0 and
			(current_state_name == "FallingState" or current_state_name == "JumpingState"))

func get_wall_jump_direction() -> Vector3:
	"""Get the direction to wall jump based on wall detection"""
	if not wall_jump_rays:
		return Vector3.ZERO
	
	for ray in wall_jump_rays.get_children():
		if ray is RayCast3D:
			var raycast = ray as RayCast3D
			if raycast.is_colliding():
				var collider = raycast.get_collider()
				if collider and (collider.is_in_group("Wall") or collider is StaticBody3D):
					return raycast.get_collision_normal()
	
	return Vector3.ZERO

func check_for_wall_jump():
	if Input.is_action_just_pressed("jump") and can_perform_wall_jump():
		var wall_normal = get_wall_jump_direction()
		if wall_normal.length() > 0.1:
			var wall_jump_state = state_machine.states.get("walljumpingstate")
			if wall_jump_state:
				wall_jump_state.setup_wall_jump(wall_normal)
				state_machine.change_state("WallJumpingState")
				wall_jump_cooldown = wall_jump_cooldown_time
