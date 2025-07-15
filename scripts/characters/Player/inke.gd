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

# Wall jump variables
var wall_jump_unlocked: bool = false
var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.05  # Prevent spam wall jumping

# Coyote time variables
var coyote_time_duration: float = 0.15  # How long after leaving ground player can still jump
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

@export var grindrays: Node3D
@export var wall_jump_rays: Node3D  # Add wall jump raycasts

# HU-3 Companion
@onready var hu3_companion: CharacterBody3D = null
var hu3_scene = preload("res://scenes/characters/Player/HU-3.tscn")

# References
@onready var player = self
#@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Initialize the State Machine
@onready var state_machine: StateMachine = $StateMachine

func _ready():
	$CameraController.initialize_camera()
	
	# Load upgrade statuses from merchant
	var merchant_script = load("res://scripts/characters/NPCs/Friendly NPCs/merchant.gd")
	if merchant_script:
		double_jump_unlocked = merchant_script.double_jump_purchased
		wall_jump_unlocked = merchant_script.wall_jump_purchased
	
	# Spawn HU-3 companion
	spawn_hu3_companion()

func spawn_hu3_companion():
	"""Spawn HU-3 companion robot"""
	if hu3_scene:
		hu3_companion = hu3_scene.instantiate()
		
		# Add HU-3 script if it doesn't have one
		if not hu3_companion.has_method("follow_player"):
			var hu3_script = load("res://scripts/characters/Player/hu3_companion.gd")
			if hu3_script:
				hu3_companion.set_script(hu3_script)
		
		# Position HU-3 to the right and above player (out of camera view)
		hu3_companion.global_position = global_position + Vector3(1.5, 1.5, 1.0)
		
		# Add to scene
		get_parent().add_child.call_deferred(hu3_companion)
		
		print("HU-3 companion spawned!")
	else:
		print("Could not load HU-3 scene!")

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)
	
	# Update coyote time
	update_coyote_time(delta)
	
	# Update wall jump cooldown
	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta
	
	# Check for rail grinding opportunity (only if not already grinding and timer is complete)
	check_for_rail_grinding()
	
	# Check for wall jump opportunity
	check_for_wall_jump()
	
	# Handle double jump reset when on floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
	
	$CameraController.follow_character(position, velocity)

func update_coyote_time(delta: float):
	"""Update coyote time counter"""
	var currently_on_floor = is_on_floor()
	
	# If we were on floor and now we're not, start coyote time
	if was_on_floor and not currently_on_floor:
		coyote_time_counter = coyote_time_duration
	
	# If we're on floor, reset coyote time
	if currently_on_floor:
		coyote_time_counter = 0.0
	
	# If we're not on floor, count down coyote time
	if not currently_on_floor and coyote_time_counter > 0:
		coyote_time_counter -= delta
	
	# Update the was_on_floor flag
	was_on_floor = currently_on_floor

func can_coyote_jump() -> bool:
	"""Check if player can perform a coyote time jump"""
	return coyote_time_counter > 0.0 and not is_on_floor()

func consume_coyote_time():
	"""Consume coyote time when jumping"""
	coyote_time_counter = 0.0

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()

func unlock_double_jump():
	"""Called by the merchant when double jump is purchased"""
	double_jump_unlocked = true
	print("Double jump unlocked!")

func unlock_wall_jump():
	"""Called by the merchant when wall jump is purchased"""
	wall_jump_unlocked = true
	print("Wall jump unlocked!")

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

func can_perform_wall_jump() -> bool:
	"""Check if the player can perform a wall jump"""
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	return (wall_jump_unlocked and 
			not is_on_floor() and 
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

# HU-3 Companion Methods
func add_gear_count(amount: int):
	"""Called by HU-3 when it collects gears"""
	gear_count += amount
	print("Player gear count increased to: ", gear_count)

func get_hu3_companion() -> CharacterBody3D:
	"""Get reference to HU-3 companion"""
	return hu3_companion

func get_hu3_health() -> float:
	"""Get HU-3's health percentage"""
	if hu3_companion and hu3_companion.has_method("get_health_percentage"):
		return hu3_companion.get_health_percentage()
	return 0.0

func get_hu3_gear_count() -> int:
	"""Get number of gears collected by HU-3"""
	if hu3_companion and hu3_companion.has_method("get_gear_count"):
		return hu3_companion.get_gear_count()
	return 0

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

## Wall Jump Logic

func check_for_wall_jump():
	# Only check for wall jump if player pressed jump and can wall jump
	if Input.is_action_just_pressed("jump") and can_perform_wall_jump():
		var wall_normal = get_wall_jump_direction()
		if wall_normal.length() > 0.1:
			# Start wall jump
			var wall_jump_state = state_machine.states.get("walljumpingstate")
			if wall_jump_state:
				wall_jump_state.setup_wall_jump(wall_normal)
				state_machine.change_state("WallJumpingState")
				wall_jump_cooldown = wall_jump_cooldown_time
