extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0

# Double jump variables
var has_double_jumped: bool = false
var can_double_jump: bool = false

# Wall jump variables
var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0 

# Coyote time variables
var coyote_time_duration: float = 0.15  # How long after leaving ground player can still jump
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

# Gear collection variables
var gear_collection_area: Area3D = null
var gear_collection_distance: float = 0.5 # Collection radius for Inke

@export var grindrays: Node3D
@export var wall_jump_rays: Node3D 

# References
@onready var player = self
#@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Initialize the State Machine
@onready var state_machine: StateMachine = $StateMachine

# GameManager reference
@onready var game_manager = "/root/GameManager"

func _ready():
	$CameraController.initialize_camera()
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.register_player(self)
		print("Player: Registered with GameManager")
	else:
		print("Player: GameManager not found!")
	
	# Set up gear collection area
	setup_gear_collection()

func setup_gear_collection():
	"""Set up Area3D for gear collection"""
	# Create Area3D for gear detection if it doesn't exist
	gear_collection_area = Area3D.new()
	gear_collection_area.name = "GearCollectionArea"
	add_child(gear_collection_area)
	
	# Create CollisionShape3D for the Area3D
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = gear_collection_distance
	collision_shape.shape = sphere_shape
	gear_collection_area.add_child(collision_shape)
	
	# Connect signals
	gear_collection_area.body_entered.connect(_on_gear_body_entered)
	gear_collection_area.area_entered.connect(_on_gear_area_entered)
	
	print("Inke: Gear collection system initialized with radius: ", gear_collection_distance)

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)
	
	# Update coyote time
	update_coyote_time(delta)
	
	# Update wall jump cooldown
	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta
	
	# Check for nearby gears to collect
	check_for_nearby_gears()
	
	# Check for rail grinding opportunity (only if not already grinding and timer is complete)
	check_for_rail_grinding()
	
	# Check for wall jump opportunity
	check_for_wall_jump()
	
	# Handle double jump reset when on floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
	
	$CameraController.follow_character(position, velocity)

func check_for_nearby_gears():
	"""Check for gears within collection distance and collect them"""
	var gears = get_tree().get_nodes_in_group("Gear")
	
	for gear in gears:
		if not is_instance_valid(gear):
			continue
		
		# Skip if gear is already collected
		if gear.has_method("get") and gear.get("collected"):
			continue
		
		# Check distance
		var distance = global_position.distance_to(gear.global_position)
		if distance <= gear_collection_distance:
			collect_gear(gear)

func collect_gear(gear: Node):
	"""Collect a gear as Inke"""
	if not gear or not is_instance_valid(gear):
		return
	
	# Check if gear has already been collected
	if gear.has_method("get") and gear.get("collected"):
		return
	
	# Try to collect using gear's method
	if gear.has_method("collect_gear"):
		# Standard gear collection method
		gear.collect_gear()
	elif gear.has_method("collect_gear_by_player"):
		# Player-specific collection method
		gear.collect_gear_by_player()
	else:
		# Fallback - mark as collected and remove
		if gear.has_method("set"):
			gear.set("collected", true)
		gear.queue_free()
	
	# Add to GameManager's gear count
	if game_manager:
		game_manager.add_gear(1)
	
	print("Inke: Collected gear! Total gears: ", get_gear_count())

func _on_gear_body_entered(body: Node3D):
	"""Handle when a gear body enters collection area"""
	if body.is_in_group("Gear"):
		collect_gear(body)

func _on_gear_area_entered(area: Area3D):
	"""Handle when a gear area enters collection area"""
	if area.is_in_group("Gear"):
		# Get the gear node (usually the parent of the area)
		var gear_node = area.get_parent()
		if gear_node and gear_node.is_in_group("Gear"):
			collect_gear(gear_node)
		else:
			# If the area itself is the gear
			collect_gear(area)

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


# === ABILITY CHECK METHODS (Using GameManager) ===

func can_perform_double_jump() -> bool:
	"""Check if the player can perform a double jump"""
	var can_double_jump_ability = game_manager.can_double_jump() if game_manager else false
	return can_double_jump_ability and not has_double_jumped and can_double_jump and not is_on_floor()

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
	var can_wall_jump_ability = game_manager.can_wall_jump() if game_manager else false
	return (can_wall_jump_ability and 
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



# === HEALTH METHODS ===

func set_health(new_health: int):
	"""Set player health (called by GameManager)"""
	print("Player: Health set to ", new_health)
	# Update any player-specific health UI or effects here

func take_damage(amount: int):
	"""Player takes damage"""
	if game_manager:
		game_manager.damage_player(amount)

func heal(amount: int):
	"""Player heals"""
	if game_manager:
		game_manager.heal_player(amount)

func get_health() -> int:
	"""Get current health from GameManager"""
	return game_manager.get_player_health() if game_manager else 3

# === GEAR/CURRENCY METHODS ===

func add_gear_count(amount: int):
	"""Called when gears are collected (forwards to GameManager)"""
	if game_manager:
		game_manager.add_gear(amount)

func get_gear_count() -> int:
	"""Get total gear count from GameManager"""
	return game_manager.get_gear_count() if game_manager else 0

func get_CRED_count() -> int:
	"""Get CRED count from GameManager"""
	return game_manager.get_CRED_count() if game_manager else 0

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
