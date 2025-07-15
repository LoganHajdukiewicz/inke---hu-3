@tool
extends StaticBody3D
class_name Floor

enum FloorType {
	NORMAL,
	SPRING,
	FALLING,
	SPINNING,
	MOVING
}

enum FloorShape {
	BOX,
	CYLINDER
}

enum SpinDirection {
	RIGHT,
	LEFT
}

@export var floor_type: FloorType = FloorType.NORMAL : set = _set_floor_type


# Shape and Dimension Settings
@export_group("Shape & Dimensions")
@export var floor_shape: FloorShape = FloorShape.BOX : set = _set_floor_shape
@export var floor_size: Vector3 = Vector3(10, 0.5, 10) : set = _set_floor_size  # X, Y, Z dimensions for box
@export var cylinder_radius: float = 5.0 : set = _set_cylinder_radius  # Radius for cylinder
@export var cylinder_height: float = 0.5 : set = _set_cylinder_height  # Height for cylinder
@export var cylinder_segments: int = 32 : set = _set_cylinder_segments  # Number of segments for cylinder smoothness

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Spring Floor Variables
@export_group("Spring Floor Settings")
@export var spring_force: float = 20.0
@export var spring_cooldown: float = 0.5
@export var spring_tween_duration: float = 0.1
@onready var spring_area: Area3D = $SpringArea
@onready var spring_collision: CollisionShape3D = $SpringArea/CollisionShape3D

# Falling Floor Variables
@export_group("Falling Floor Settings")
@export var fall_speed: float = 5.0
@export var fall_duration: float = 3.0
@export var respawn_delay: float = 2.0
@export var shake_intensity: float = 0.35
@export var shake_duration: float = 1.0

var players_on_floor: Array[CharacterBody3D] = []
var spring_cooldown_timer: float = 0.0
var fall_timer: float = 0.0
var is_falling: bool = false
var has_fallen: bool = false
var fall_triggered: bool = false
var original_position: Vector3
var fall_tween: Tween

# Moving Floor Variables
@export_group("Moving Floor Settings")
@export var movement_axis: Vector3 = Vector3(10, 0, 0)  # Distance to move in each axis
@export var movement_duration: float = 3.0  # Time to complete one movement cycle
@export var movement_repeat: bool = true  # Whether to repeat the movement
@export var movement_delay: float = 0.0  # Delay before starting movement
@export var movement_easing: Tween.EaseType = Tween.EASE_IN_OUT
@export var movement_transition: Tween.TransitionType = Tween.TRANS_SINE

var movement_tween: Tween
var start_position: Vector3
var end_position: Vector3
var is_moving: bool = false
var players_to_move: Array[CharacterBody3D] = []
var last_floor_position: Vector3

# Spinning Floor Variables
@export_group("Spinning Floor Settings")
@export var spin_speed: float = 90.0  # degrees per second
@export var spin_direction: SpinDirection = SpinDirection.RIGHT

# Editor preview variables
var editor_material: StandardMaterial3D
var runtime_material: StandardMaterial3D

# Property setters that work in editor
func _set_floor_type(value: FloorType):
	floor_type = value
	if Engine.is_editor_hint():
		_update_editor_preview()

func _set_floor_shape(value: FloorShape):
	floor_shape = value
	if Engine.is_editor_hint():
		_ensure_nodes_exist()
		setup_floor_geometry()
		_update_editor_preview()

func _set_floor_size(value: Vector3):
	floor_size = value
	if Engine.is_editor_hint() and floor_shape == FloorShape.BOX:
		_ensure_nodes_exist()
		setup_box_geometry()
		_update_editor_preview()

func _set_cylinder_radius(value: float):
	cylinder_radius = value
	if Engine.is_editor_hint() and floor_shape == FloorShape.CYLINDER:
		_ensure_nodes_exist()
		setup_cylinder_geometry()
		_update_editor_preview()

func _set_cylinder_height(value: float):
	cylinder_height = value
	if Engine.is_editor_hint() and floor_shape == FloorShape.CYLINDER:
		_ensure_nodes_exist()
		setup_cylinder_geometry()
		_update_editor_preview()

func _set_cylinder_segments(value: int):
	cylinder_segments = value
	if Engine.is_editor_hint() and floor_shape == FloorShape.CYLINDER:
		_ensure_nodes_exist()
		setup_cylinder_geometry()
		_update_editor_preview()

func _ensure_nodes_exist():
	"""Ensure required nodes exist for editor preview"""
	if not mesh_instance:
		mesh_instance = get_node_or_null("MeshInstance3D")
		if not mesh_instance:
			mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "MeshInstance3D"
			add_child(mesh_instance)
	
	if not collision_shape:
		collision_shape = get_node_or_null("CollisionShape3D")
		if not collision_shape:
			collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			add_child(collision_shape)

# Update the editor preview with debug colors
func _update_editor_preview():
	_ensure_nodes_exist()
	
	if not mesh_instance:
		return
	
	# Get or create editor material
	if not editor_material:
		editor_material = StandardMaterial3D.new()
		editor_material.flags_transparent = true
		editor_material.flags_unshaded = true  # Makes it appear more like a debug overlay
		editor_material.albedo_color.a = 0.8  # Slightly transparent to show it's debug
	
	# Set debug color based on floor type
	match floor_type:
		FloorType.NORMAL:
			editor_material.albedo_color = Color(0, 0.8, 0, 0.8)  # Bright Green
		FloorType.SPRING:
			editor_material.albedo_color = Color(1.0, 0.5, 0.0, 0.8)  # Orange
		FloorType.FALLING:
			editor_material.albedo_color = Color(1.0, 0.2, 0.2, 0.8)  # Bright Red
		FloorType.SPINNING:
			editor_material.albedo_color = Color(0.8, 0.2, 1.0, 0.8)  # Bright Purple
		FloorType.MOVING:
			editor_material.albedo_color = Color(0.2, 0.7, 1.0, 0.8)  # Bright Blue
	
	# Apply the editor material
	mesh_instance.set_surface_override_material(0, editor_material)

func _ready():
	# In editor, setup preview and return
	if Engine.is_editor_hint():
		_ensure_nodes_exist()
		setup_floor_geometry()
		_update_editor_preview()
		return
	
	# Runtime initialization
	original_position = global_position
	start_position = global_position
	end_position = global_position + movement_axis
	last_floor_position = global_position
	
	# Create the mesh and collision based on shape and dimensions
	setup_floor_geometry()
	setup_floor_type()
	
	# Connect spring area signals
	if spring_area:
		spring_area.body_entered.connect(_on_spring_area_body_entered)
		spring_area.body_exited.connect(_on_spring_area_body_exited)

func setup_floor_geometry():
	"""Setup the floor's mesh and collision based on shape and dimensions"""
	match floor_shape:
		FloorShape.BOX:
			setup_box_geometry()
		FloorShape.CYLINDER:
			setup_cylinder_geometry()

func setup_box_geometry():
	"""Setup box-shaped floor geometry"""
	# Create box mesh
	var box_mesh = BoxMesh.new()
	box_mesh.size = floor_size
	mesh_instance.mesh = box_mesh
	
	# Create box collision shape
	var box_shape = BoxShape3D.new()
	box_shape.size = floor_size
	collision_shape.shape = box_shape
	
	# Setup spring area collision to match (only in runtime)
	if not Engine.is_editor_hint() and spring_collision:
		var spring_shape = BoxShape3D.new()
		spring_shape.size = Vector3(floor_size.x, floor_size.y + 0.5, floor_size.z)
		spring_collision.shape = spring_shape
		spring_collision.position.y = floor_size.y * 0.25

func setup_cylinder_geometry():
	"""Setup cylinder-shaped floor geometry"""
	# Create cylinder mesh
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.bottom_radius = cylinder_radius
	cylinder_mesh.top_radius = cylinder_radius
	cylinder_mesh.height = cylinder_height
	cylinder_mesh.radial_segments = cylinder_segments
	mesh_instance.mesh = cylinder_mesh
	
	# Create cylinder collision shape
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = cylinder_radius
	cylinder_shape.height = cylinder_height
	collision_shape.shape = cylinder_shape
	
	# Setup spring area collision to match (only in runtime)
	if not Engine.is_editor_hint() and spring_collision:
		var spring_shape = CylinderShape3D.new()
		spring_shape.radius = cylinder_radius
		spring_shape.height = cylinder_height + 0.5
		spring_collision.shape = spring_shape
		spring_collision.position.y = cylinder_height * 0.25

# [Rest of the script remains the same...]
func _process(delta):
	# Don't run game logic in editor
	if Engine.is_editor_hint():
		return
	
	if spring_cooldown_timer > 0:
		spring_cooldown_timer -= delta
	
	# Handle spring bouncing for players on the floor
	if floor_type == FloorType.SPRING and spring_cooldown_timer <= 0:
		if players_on_floor.size() > 0:
			activate_spring()
	
	# Handle falling floor logic
	if floor_type == FloorType.FALLING and not is_falling and not has_fallen and not fall_triggered:
		if players_on_floor.size() > 0:
			fall_timer += delta
			fall_triggered = true
			start_falling()
	
	# Handle spinning floor logic
	if floor_type == FloorType.SPINNING:
		handle_spinning(delta)
	
	# Handle moving floor - move players with the floor
	if floor_type == FloorType.MOVING and is_moving:
		move_players_with_floor()

func setup_floor_type():
	"""Setup the floor based on the selected type"""
	match floor_type:
		FloorType.NORMAL:
			setup_normal_floor()
		FloorType.SPRING:
			setup_spring_floor()
		FloorType.FALLING:
			setup_falling_floor()
		FloorType.SPINNING:
			setup_spinning_floor()
		FloorType.MOVING:
			setup_moving_floor()

func setup_normal_floor():
	"""Setup a normal floor"""
	# Set normal green color
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(0, 0.41793, 0, 1)  # Green
	
	# Disable spring area
	if spring_area:
		spring_area.monitoring = false
		spring_area.visible = false

func setup_spring_floor():
	"""Setup a spring floor"""
	# Set spring color (bouncy orange/yellow)
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(1.0, 0.6, 0.0, 1)  # Orange
	material.metallic = 0.2
	material.roughness = 0.3
	
	# Enable spring area
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		# Make sure the collision shape matches the floor size
		var floor_shape = collision_shape.shape as BoxShape3D
		if floor_shape and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape.size.x, floor_shape.size.y + 0.5, floor_shape.size.z)
				spring_collision.position.y = floor_shape.size.y * 0.25

func setup_falling_floor():
	"""Setup a falling floor"""
	# Set falling floor color (warning red)
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(0.8, 0.2, 0.2, 1)  # Red
	material.metallic = 0.1
	material.roughness = 0.4
	
	# Enable spring area for detection (reuse the same area)
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		# Make sure the collision shape matches the floor size
		var floor_shape = collision_shape.shape as BoxShape3D
		if floor_shape and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape.size.x, floor_shape.size.y + 0.5, floor_shape.size.z)
				spring_collision.position.y = floor_shape.size.y * 0.25

func setup_moving_floor():
	"""Setup a moving floor"""
	# Set moving floor color (blue)
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(0.2, 0.5, 1.0, 1)  # Blue
	material.metallic = 0.3
	material.roughness = 0.2
	
	# Enable spring area for player detection
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		# Make sure the collision shape matches the floor size
		var floor_shape = collision_shape.shape as BoxShape3D
		if floor_shape and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape.size.x, floor_shape.size.y + 0.5, floor_shape.size.z)
				spring_collision.position.y = floor_shape.size.y * 0.25
	
	# Start moving after initial delay (if any)
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	start_moving()

func setup_spinning_floor():
	"""Setup a spinning floor"""
	# Set spinning floor color (purple/magenta)
	var material = mesh_instance.get_surface_override_material(0)
	if not material:
		material = StandardMaterial3D.new()
		mesh_instance.set_surface_override_material(0, material)
	material.albedo_color = Color(0.6, 0.2, 0.8, 1)  # Purple
	material.metallic = 0.3
	material.roughness = 0.2
	
	# Enable spring area for player detection
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true

func start_moving():
	"""Start the moving floor sequence"""
	if is_moving:
		return
	
	is_moving = true
	last_floor_position = global_position
	
	if movement_repeat:
		# For repeating movement, use a custom loop with delays
		_start_movement_loop()
	else:
		# For single movement, use simple tween
		_create_single_movement()
	
	print("Moving floor started! Moving from ", start_position, " to ", end_position)

func _start_movement_loop():
	"""Start the repeating movement loop with delays"""
	_create_movement_cycle()

func _create_movement_cycle():
	"""Create one complete movement cycle (start->end->start) with delays"""
	if not is_moving:
		return
	
	# Move from start to end position
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", end_position, movement_duration)
	
	# Wait for movement to complete, then add delay and continue
	movement_tween.tween_callback(func(): _handle_mid_cycle_delay())

func _handle_mid_cycle_delay():
	"""Handle delay between start->end and end->start movement"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	# Move from end back to start position
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", start_position, movement_duration)
	
	# Wait for movement to complete, then add delay and start next cycle
	movement_tween.tween_callback(func(): _handle_end_cycle_delay())

func _handle_end_cycle_delay():
	"""Handle delay at the end of a complete cycle before starting next cycle"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	# Start the next cycle
	_create_movement_cycle()

func _create_single_movement():
	"""Create a single movement cycle without looping"""
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	
	# Move from start to end position
	movement_tween.tween_property(self, "global_position", end_position, movement_duration)
	movement_tween.tween_callback(func(): _handle_single_movement_delay())

func _handle_single_movement_delay():
	"""Handle delay in single movement mode"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	# Move from end back to start position
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", start_position, movement_duration)
	
	# Mark as finished
	movement_tween.tween_callback(func(): is_moving = false)

func move_players_with_floor():
	"""Move players that are on the floor along with the floor"""
	var floor_delta = global_position - last_floor_position
	
	# Only move players if the floor actually moved
	if floor_delta.length() > 0.001:  # Small threshold to avoid floating point errors
		for player in players_on_floor:
			if player and is_instance_valid(player):
				# Check if player is actually on the floor (not jumping/falling)
				if player.is_on_floor() or player.velocity.y <= 0.1:
					player.global_position += floor_delta
	
	last_floor_position = global_position

func stop_moving():
	"""Stop the moving floor"""
	if movement_tween:
		movement_tween.kill()
	is_moving = false
	print("Moving floor stopped")

func handle_spinning(delta):
	"""Handle the spinning floor rotation"""
	# Calculate rotation amount for this frame
	var rotation_amount = spin_speed * delta
	
	# Apply rotation based on the spin direction (Y-axis only)
	var rotation_radians = deg_to_rad(rotation_amount)
	if spin_direction == SpinDirection.LEFT:
		rotation_radians = -rotation_radians
	
	rotate_y(rotation_radians)
	
	# Move players with the spinning floor
	spin_players_with_floor(rotation_radians)

func spin_players_with_floor(rotation_radians: float):
	"""Move players to follow the floor's rotation"""
	if players_on_floor.size() == 0:
		return
	
	var center = global_position
	
	for player in players_on_floor:
		if player and is_instance_valid(player):
			# Get player's current position relative to floor center
			var player_pos = player.global_position
			var relative_pos = player_pos - center
			
			# Only rotate the X and Z components (keep Y unchanged)
			var rotated_x = relative_pos.x * cos(rotation_radians) + relative_pos.z * sin(rotation_radians)
			var rotated_z = -relative_pos.x * sin(rotation_radians) + relative_pos.z * cos(rotation_radians)
			
			# Set the new position
			player.global_position = center + Vector3(rotated_x, relative_pos.y, rotated_z)

func _on_spring_area_body_entered(body):
	"""When a player enters the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		if not players_on_floor.has(body):
			players_on_floor.append(body)
			
			# For moving floors, also add to players to move
			if floor_type == FloorType.MOVING:
				if not players_to_move.has(body):
					players_to_move.append(body)

func _on_spring_area_body_exited(body):
	"""When a player exits the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		players_on_floor.erase(body)
		
		if floor_type == FloorType.MOVING:
			players_to_move.erase(body)
		
		# DON'T reset fall timer - once triggered, the floor will fall regardless

func activate_spring():
	"""Activate the spring effect for all players on the floor"""
	for player in players_on_floor:
		if player and is_instance_valid(player):
			apply_spring_effect(player)
	
	# Set cooldown
	spring_cooldown_timer = spring_cooldown

func apply_spring_effect(player: CharacterBody3D):
	"""Apply spring effect to a specific player"""
	if not player:
		return
	
	# Reset double jump ability when using spring
	if player.has_method("get") and player.get("has_double_jumped") != null:
		player.has_double_jumped = false
		player.can_double_jump = true
	
	# Create a tween for the spring effect
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Store original position
	var original_y = player.global_position.y
	
	# Quick upward movement (smaller lift to feel more responsive)
	tween.tween_method(
		func(pos_y): _set_player_y_position(player, pos_y),
		original_y,
		original_y + 0.3,  # Smaller lift for more responsive feel
		spring_tween_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	# Apply upward velocity immediately (don't wait for tween)
	_apply_spring_velocity(player)
	
	# Also apply a callback after tween to ensure velocity is set
	tween.tween_callback(func(): _apply_spring_velocity(player)).set_delay(spring_tween_duration)

func _set_player_y_position(player: CharacterBody3D, y_pos: float):
	"""Helper function to set player Y position"""
	if player and is_instance_valid(player):
		player.global_position.y = y_pos

func _apply_spring_velocity(player: CharacterBody3D):
	"""Apply upward velocity to the player"""
	if player and is_instance_valid(player):
		# Set the velocity directly - this should override gravity
		player.velocity.y = spring_force
		
		# Force the player into jumping state immediately
		if player.has_method("get") and player.get("state_machine"):
			var state_machine = player.get("state_machine")
			if state_machine and state_machine.has_method("change_state"):
				state_machine.change_state("JumpingState")
		
		# Also call move_and_slide to ensure the velocity is applied
		player.move_and_slide()
		
		print("Spring activated! Player bounced with force: ", spring_force, " Current velocity.y: ", player.velocity.y)

func start_falling():
	"""Start the falling sequence"""
	if is_falling or has_fallen:
		return
	
	is_falling = true
	print("Floor starting to fall!")
	
	# Add a slight shake/warning before falling
	create_warning_shake()
	
	# Wait for the shake duration, then start falling
	await get_tree().create_timer(shake_duration).timeout
	
	# Disable collision so players fall through
	collision_shape.disabled = true
	if spring_area:
		spring_area.monitoring = false
	
	# Create falling tween
	fall_tween = create_tween()
	fall_tween.tween_property(self, "global_position", 
		original_position + Vector3(0, -20, 0), fall_duration)
	fall_tween.tween_callback(func(): _on_fall_complete())

func create_warning_shake():
	"""Create a warning shake effect"""
	var shake_tween = create_tween()
	var shake_loops = int(shake_duration / 0.1)  # Calculate loops based on duration
	shake_tween.set_loops(shake_loops)
	shake_tween.tween_property(self, "global_position", 
		original_position + Vector3(randf_range(-shake_intensity, shake_intensity), 0, randf_range(-shake_intensity, shake_intensity)), 0.05)
	shake_tween.tween_property(self, "global_position", original_position, 0.05)

func _on_fall_complete():
	"""Called when the floor has finished falling"""
	has_fallen = true
	is_falling = false
	
	# Make floor semi-transparent to show it's fallen
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 0.3
	
	# Schedule respawn
	await get_tree().create_timer(respawn_delay).timeout
	respawn_floor()

func respawn_floor():
	"""Respawn the floor at its original position"""
	print("Floor respawning!")
	
	# Reset position
	global_position = original_position
	
	# Re-enable collision
	collision_shape.disabled = false
	if spring_area:
		spring_area.monitoring = true
	
	# Reset material transparency
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 1.0
	
	# Reset state
	is_falling = false
	has_fallen = false
	fall_triggered = false
	fall_timer = 0.0
	players_on_floor.clear()
	
	# Create a small respawn effect
	create_respawn_effect()

func create_respawn_effect():
	"""Create a visual effect when the floor respawns"""
	var respawn_tween = create_tween()
	respawn_tween.set_parallel(true)
	
	# Scale effect
	var original_scale = scale
	scale = Vector3(0.1, 0.1, 0.1)
	respawn_tween.tween_property(self, "scale", original_scale, 0.5)
	respawn_tween.tween_property(self, "scale", original_scale, 0.5).set_trans(Tween.TRANS_BOUNCE)
	
	# Color flash effect
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		var original_color = material.albedo_color
		material.albedo_color = Color.WHITE
		respawn_tween.tween_property(material, "albedo_color", original_color, 0.3)
