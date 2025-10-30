extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0
var is_being_sprung: bool = false

# Double jump variables
var has_double_jumped: bool = false
var can_double_jump: bool = false

# Coyote time variables
var coyote_time_duration: float = 0.15  
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

# Wall jump variables (exposed for state compatibility)
var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0

# Component references (now managed by separate managers)
var jump_shadow_manager: JumpShadowManager
var gear_collection_manager: GearCollectionManager
var rail_detection_manager: RailDetectionManager
var wall_jump_detector: WallJumpDetector

# References
@onready var player = self
@onready var state_machine: StateMachine = $StateMachine
@onready var game_manager = "/root/GameManager"

# Export for scene setup
@export var wall_jump_rays: Node3D
@export var rail_grind_area: Area3D 

func _ready():
	$CameraController.initialize_camera()
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.register_player(self)
	else:
		print("Player: GameManager not found!")
	
	# Initialize modular components
	initialize_components()

func initialize_components():
	"""Initialize all modular component managers"""
	# Jump shadow
	jump_shadow_manager = JumpShadowManager.new()
	jump_shadow_manager.name = "JumpShadowManager"
	add_child(jump_shadow_manager)
	
	# Gear collection
	gear_collection_manager = GearCollectionManager.new()
	gear_collection_manager.name = "GearCollectionManager"
	add_child(gear_collection_manager)
	
	# Rail detection
	rail_detection_manager = RailDetectionManager.new()
	rail_detection_manager.name = "RailDetectionManager"
	add_child(rail_detection_manager)
	
	# Wall jump detection
	wall_jump_detector = WallJumpDetector.new()
	wall_jump_detector.name = "WallJumpDetector"
	add_child(wall_jump_detector)

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)

	var current_state_name = state_machine.current_state.get_script().get_global_name()
	
	# Disable shadow while rail grinding
	if jump_shadow_manager:
		jump_shadow_manager.set_enabled(current_state_name != "RailGrindingState")
	
	if current_state_name != "RailGrindingState":
		# Smoothly return character to upright orientation
		var upright_basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
		upright_basis = upright_basis.rotated(Vector3.UP, rotation.y)
		# Normalize basis before slerp to avoid quaternion conversion errors
		var normalized_basis = basis.orthonormalized()
		basis = normalized_basis.slerp(upright_basis, delta * 10.0).orthonormalized()
	
	update_coyote_time(delta)
	
	# Sync wall jump cooldown from detector to player (for state compatibility)
	if wall_jump_detector:
		wall_jump_cooldown = wall_jump_detector.wall_jump_cooldown
	
	# Reset double jump on the floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
	
	$CameraController.follow_character(position, velocity)

func update_coyote_time(delta: float):
	"""Update coyote time counter"""
	var currently_on_floor = is_on_floor()
	
	if was_on_floor and not currently_on_floor:
		coyote_time_counter = coyote_time_duration
	
	if currently_on_floor:
		coyote_time_counter = 0.0
	
	if not currently_on_floor and coyote_time_counter > 0:
		coyote_time_counter -= delta
	
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
	"""Check if the player can perform a wall jump (delegates to WallJumpDetector)"""
	return wall_jump_detector.can_perform_wall_jump() if wall_jump_detector else false

func get_wall_jump_direction() -> Vector3:
	"""Get the direction to wall jump (delegates to WallJumpDetector)"""
	return wall_jump_detector.get_wall_jump_direction() if wall_jump_detector else Vector3.ZERO

# === HEALTH METHODS ===

func set_health(new_health: int):
	"""Set player health (called by GameManager)"""
	print("Player: Health set to ", new_health)

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
