extends CharacterBody3D

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var jump_velocity: float = 5.0
var is_being_sprung: bool = false
var ignore_next_jump: bool = false

# Double jump variables
var has_double_jumped: bool = false
var can_double_jump: bool = false

# Air dash variables (NEW - similar to double jump)
var has_air_dashed: bool = false
var can_air_dash: bool = false

# Long jump variables (NEW)
var can_long_jump: bool = false
var long_jump_window: float = 0.3  # Time window after dash to trigger long jump
var long_jump_timer: float = 0.0

# Dash jump momentum storage (NEW)
var stored_dash_momentum: Vector3 = Vector3.ZERO

# Coyote time variables
var coyote_time_duration: float = 0.15  
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

# Wall jump variables (exposed for state compatibility)
var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0

# Damage and death variables
var is_invulnerable: bool = false
var invulnerability_duration: float = 1.5
var invulnerability_timer: float = 0.0
var is_dead: bool = false
var death_y_threshold: float = -50.0  # Fall death threshold
var should_flash: bool = false 

# NEW: Ice floor detection
var is_on_ice: bool = false
var ice_friction_multiplier: float = 0.01  # How much control you have on ice (0.0 = no control, 1.0 = full control)

# Component references (now managed by separate managers)
var jump_shadow_manager: JumpShadowManager
var gear_collection_manager: GearCollectionManager
var rail_detection_manager: RailDetectionManager
var wall_jump_detector: WallJumpDetector
var speed_effects_manager: SpeedEffectsManager

# References
@onready var player = self
@onready var state_machine: StateMachine = $StateMachine
var game_manager 
var checkpoint_manager
var paint_manager

# Export for scene setup
@export var wall_jump_rays: Node3D
@export var rail_grind_area: Area3D 

func _ready():
	# FIX: Get autoload references in _ready instead of @onready
	game_manager = get_node("/root/GameManager")
	checkpoint_manager = get_node("/root/CheckpointManager")
	paint_manager = get_node("/root/PaintManager")
	
	$CameraController.initialize_camera()
	if DialogueManager:
		DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	
	# Get GameManager reference
	if game_manager:
		game_manager.register_player(self)
		# Connect to health changed signal
		if not game_manager.health_changed.is_connected(_on_health_changed):
			game_manager.health_changed.connect(_on_health_changed)
	else:
		print("Player: GameManager not found!")
	
	# Get CheckpointManager reference
	if not checkpoint_manager:
		print("Player: CheckpointManager not found!")
	
	# Register with PaintManager
	if paint_manager:
		paint_manager.register_player(self)
		# Connect to paint signals
		if paint_manager.has_signal("paint_changed"):
			paint_manager.paint_changed.connect(_on_paint_changed)
		if paint_manager.has_signal("paint_used"):
			paint_manager.paint_used.connect(_on_paint_used)
	else:
		print("Player: PaintManager not found!")
	
	# Initialize modular components
	initialize_components()
	
	# Setup damage detection area
	setup_damage_area()

func _on_dialogue_ended():
	"""Called when dialogue ends - ignore the next jump input"""
	ignore_next_jump = true
	# Clear the flag after a short delay
	await get_tree().create_timer(0.01).timeout
	ignore_next_jump = false

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
	
	# Ledge detection 
	var ledge_detection_manager = LedgeDetectionManager.new()
	ledge_detection_manager.name = "LedgeDetectionManager"
	add_child(ledge_detection_manager)
	
	# Wall jump detection
	wall_jump_detector = WallJumpDetector.new()
	wall_jump_detector.name = "WallJumpDetector"
	add_child(wall_jump_detector)
	
	# Attack system
	var attack_manager = AttackManager.new()
	attack_manager.name = "AttackManager"
	add_child(attack_manager)
	
	# Speed effects (motion lines/blur/sonic boom)
	speed_effects_manager = SpeedEffectsManager.new()
	speed_effects_manager.name = "SpeedEffectsManager"
	add_child(speed_effects_manager)

func setup_damage_area():
	"""Setup Area3D for detecting damage sources"""
	var damage_area = Area3D.new()
	damage_area.name = "DamageDetectionArea"
	add_child(damage_area)
	
	# Copy collision shape from player's main collision
	var collision_shape = CollisionShape3D.new()
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.height = 1.5
	capsule_shape.radius = 0.5
	collision_shape.shape = capsule_shape
	collision_shape.position = Vector3(0, 0.849, 0)
	damage_area.add_child(collision_shape)
	
	# Connect signals
	damage_area.body_entered.connect(_on_damage_body_entered)
	damage_area.area_entered.connect(_on_damage_area_entered)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
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
	update_invulnerability(delta)
	update_long_jump_timer(delta)
	update_ice_detection()  # NEW: Check for ice floor using get_last_slide_collision
	check_fall_death()
	
	# Sync wall jump cooldown from detector to player (for state compatibility)
	if wall_jump_detector:
		wall_jump_cooldown = wall_jump_detector.wall_jump_cooldown
	
	# Reset double jump and air dash on the floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
		has_air_dashed = false
		can_air_dash = true
	
	$CameraController.follow_character(position, velocity)

func update_ice_detection():
	"""Check if player is currently on a frozen floor using collision detection"""
	is_on_ice = false
	
	if not is_on_floor():
		return
	
	# Use get_slide_collision to check what we're standing on
	# This is more reliable than raycasting
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider and collider.has_method("get"):
			var floor_type = collider.get("floor_type")
			if floor_type != null and floor_type == 6:  # FloorType.FROZEN
				is_on_ice = true
				print("ON ICE! Friction multiplier: ", ice_friction_multiplier)
				return

func get_ice_friction_multiplier() -> float:
	"""Get the friction multiplier based on whether we're on ice"""
	return ice_friction_multiplier if is_on_ice else 1.0

func update_long_jump_timer(delta: float):
	"""Update the long jump window timer"""
	if long_jump_timer > 0.0:
		long_jump_timer -= delta
		if long_jump_timer <= 0.0:
			can_long_jump = false
			# Clear stored dash momentum when long jump window expires
			stored_dash_momentum = Vector3.ZERO

func enable_long_jump():
	"""Enable long jump window after a dash"""
	can_long_jump = true
	long_jump_timer = long_jump_window
	print("Long jump enabled for ", long_jump_window, " seconds")

func is_long_jump_available() -> bool:
	"""Check if player can perform a long jump"""
	return can_long_jump and long_jump_timer > 0.0

func update_invulnerability(delta: float):
	"""Update invulnerability timer and CONDITIONAL visual feedback"""
	if is_invulnerable:
		invulnerability_timer -= delta
		
		# Only flash if should_flash is true (when hurt, not when stomping)
		if should_flash:
			var flash_speed = 10.0
			@warning_ignore("shadowed_variable_base_class")
			var is_visible = int(invulnerability_timer * flash_speed) % 2 == 0
			visible = is_visible
		
		if invulnerability_timer <= 0:
			is_invulnerable = false
			should_flash = false
			visible = true  # Ensure player is visible when invulnerability ends

func check_fall_death():
	"""Check if player has fallen below death threshold"""
	if global_position.y < death_y_threshold:
		die()

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

# === DAMAGE AND DEATH METHODS ===

func take_damage(amount: int, knockback_dir: Vector3 = Vector3.ZERO):
	"""Player takes damage with optional knockback direction"""
	if is_dead or is_invulnerable:
		return
	
	if game_manager:
		game_manager.damage_player(amount)
	
	# Apply knockback with provided direction
	apply_damage_knockback(knockback_dir)
	
	# Start invulnerability WITH flashing
	is_invulnerable = true
	should_flash = true  # Enable flashing when hurt
	invulnerability_timer = invulnerability_duration
	
	# Check if dead
	if game_manager and game_manager.get_player_health() <= 0:
		die()

func set_invulnerable_without_flash(duration: float):
	"""Set invulnerability without visual flash (for head stomps)"""
	is_invulnerable = true
	should_flash = false  # No flashing for stomps
	invulnerability_timer = duration
	visible = true  # Stay visible

func apply_damage_knockback(knockback_dir: Vector3 = Vector3.ZERO):
	"""Apply knockback when taking damage"""
	# Upward component
	velocity.y = 8.0
	
	# Horizontal knockback
	if knockback_dir.length() > 0:
		# Use provided direction (away from enemy)
		var horizontal_knockback = knockback_dir.normalized()
		velocity.x = horizontal_knockback.x * 10.0
		velocity.z = horizontal_knockback.z * 10.0
	else:
		# Fallback: push backward from player facing
		var knockback_direction = -global_transform.basis.z
		velocity.x = knockback_direction.x * 8.0
		velocity.z = knockback_direction.z * 8.0

func die():
	"""Handle player death"""
	if is_dead:
		return
	
	is_dead = true
	visible = true  # Make sure player is visible during death animation
	print("Player died!")
	
	# Disable controls
	set_physics_process(false)
	
	# Play death animation/effect
	play_death_effect()
	
	# Wait a moment before respawning
	await get_tree().create_timer(1.5).timeout
	
	respawn()

func play_death_effect():
	"""Visual/audio feedback for death"""
	
	# Spin and fall
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:y", rotation.y + TAU * 2, 1.0)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 1.0)

func respawn():
	"""Respawn the player at checkpoint or reload level"""
	# Reset death state
	is_dead = false
	is_invulnerable = false
	should_flash = false
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	visible = true
	
	# Check for checkpoint
	if checkpoint_manager and checkpoint_manager.has_active_checkpoint():
		# Respawn at checkpoint
		global_position = checkpoint_manager.get_checkpoint_position()
		rotation.y = checkpoint_manager.get_checkpoint_rotation().y
		
		# Restore health
		if game_manager:
			game_manager.set_player_health(game_manager.get_player_max_health())
		
		print("Respawning at checkpoint: ", global_position)
		
		# Re-enable controls
		set_physics_process(true)
		
		# Brief invulnerability after respawn
		set_invulnerable_without_flash(2.0)
	else:
		# No checkpoint - reload the level
		print("No checkpoint found - reloading level")
		reload_level()

func reload_level():
	"""Reload the current level"""
	# Reset game state
	if game_manager:
		game_manager.set_player_health(game_manager.get_player_max_health())
	
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_health_changed(new_health: int, max_health: int):
	"""Called when health changes from GameManager"""
	print("Health changed: ", new_health, "/", max_health)
	
	# You can add UI updates here or visual feedback

func _on_damage_body_entered(body: Node3D):
	"""Handle collision with damage-dealing bodies"""
	if is_dead or is_invulnerable:
		return
	
	# Check if it's an enemy
	if body.is_in_group("Enemy"):
		var enemy = body as Enemy
		if enemy:
			# Calculate knockback direction away from enemy
			var knockback_dir = (global_position - enemy.global_position).normalized()
			knockback_dir.y = 0  # Keep horizontal
			take_damage(enemy.damage_to_player, knockback_dir)
	
	# Check for hazards
	if body.is_in_group("Hazard") or body.is_in_group("KillPlane"):
		die()

func _on_damage_area_entered(area: Area3D):
	"""Handle collision with damage-dealing areas"""
	if is_dead or is_invulnerable:
		return
	
	# Check for hazard areas
	if area.is_in_group("Hazard") or area.is_in_group("KillPlane"):
		die()
	
	# Check for damage zones
	if area.is_in_group("DamageZone"):
		var damage_amount = 1
		if area.has_method("get_damage"):
			damage_amount = area.get_damage()
		take_damage(damage_amount)

# === HEALTH METHODS ===

func set_health(new_health: int):
	"""Set player health (called by GameManager)"""
	print("Player: Health set to ", new_health)

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

func _on_paint_changed(new_paint, previous_paint):
	"""Called when player switches paint type"""
	print("Paint changed from ", previous_paint, " to ", new_paint)
	# You can add additional logic here, such as:
	# - Update UI
	# - Change visual effects
	# - Enable/disable certain abilities

func _on_paint_used(paint_type):
	"""Called when player uses their current paint"""
	print("Player used paint type: ", paint_type)
	# Additional logic can be added here if needed
