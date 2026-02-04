@tool
extends StaticBody3D
class_name Floor

enum FloorType {
	NORMAL,
	SPRING,
	FALLING,
	SPINNING,
	MOVING, 
	DAMAGE, # non-lethal damaging floors, i.e. lava, electric
	FROZEN
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

@export_category("Texture Settings")
@export var use_default_texture: bool = true : set = _set_use_default_texture
@export var custom_texture: Texture2D : set = _set_custom_texture
@export var texture_scale: Vector2 = Vector2(1.0, 1.0) : set = _set_texture_scale

@export_category("Box Dimensions")
@export var floor_shape: FloorShape = FloorShape.BOX : set = _set_floor_shape
@export var floor_size: Vector3 = Vector3(10, 0.5, 10) : set = _set_floor_size  # X, Y, Z dimensions for box

@export_category("Cylinder Dimensions")
@export var cylinder_radius: float = 5.0 : set = _set_cylinder_radius  # Radius for cylinder
@export var cylinder_height: float = 0.5 : set = _set_cylinder_height  # Height for cylinder
@export var cylinder_segments: int = 32 : set = _set_cylinder_segments  # Number of segments for cylinder smoothness

@export_group("Spring Floor Settings")
@export var spring_force: float = 20.0
@export var spring_cooldown: float = 0.5
@export var spring_tween_duration: float = 0.1
@onready var spring_area: Area3D = $SpringArea
@onready var spring_collision: CollisionShape3D = $SpringArea/CollisionShape3D

@export_group("Falling Floor Settings")
@export var fall_speed: float = 5.0
@export var fall_duration: float = 3.0
@export var respawn_delay: float = 2.0
@export var shake_intensity: float = 0.35
@export var shake_duration: float = 1.0

@export_group("Spinning Floor Settings")
@export var spin_speed: float = 90.0  # degrees per second
@export var spin_direction: SpinDirection = SpinDirection.RIGHT

@export_group("Moving Floor Settings")
@export var movement_axis: Vector3 = Vector3(10, 0, 0)  # Distance to move in each axis
@export var movement_duration: float = 3.0  # Time to complete one movement cycle
@export var movement_repeat: bool = true  # Whether to repeat the movement
@export var movement_delay: float = 0.0  # Delay before starting movement
@export var movement_easing: Tween.EaseType = Tween.EASE_IN_OUT
@export var movement_transition: Tween.TransitionType = Tween.TRANS_SINE

@export_group("Frozen Floor Settings")
@export var frozen_friction: float = 0.01  # Very low friction for ice (reduced from 0.05)
@export var frozen_enable_visual_effects: bool = true  # Enable ice visual effects
@export var frozen_shimmer_speed: float = 2.0  # Speed of the shimmer effect
@export var frozen_shimmer_intensity: float = 0.3  # How noticeable the shimmer is

@export_group("Damage Floor Settings")
@export var damage_amount: int = 1  # Amount of damage to deal
@export var damage_interval: float = 0.5  # Time between damage ticks
@export var damage_knockback_force: float = 15.0  # Horizontal knockback strength
@export var damage_knockback_upward: float = 8.0  # Upward knockback strength

@export_group("Momentum Settings")
@export var momentum_transfer_strength: float = 0.6 : set = _set_momentum_transfer_strength
@export var enable_momentum_transfer: bool = true

# General Variables
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Texture Variables
var default_texture: Texture2D
const DEFAULT_TEXTURE_PATH = "res://textures/texture_08.png"

# Spring Floor Variables
var players_on_floor: Array[CharacterBody3D] = []
var spring_cooldown_timer: float = 0.0

# Falling Floor Variables
var fall_timer: float = 0.0
var is_falling: bool = false
var has_fallen: bool = false
var fall_triggered: bool = false
var original_position: Vector3
var fall_tween: Tween

# Spinning Floor Variables And Moving Floor Variables
var movement_tween: Tween
var start_position: Vector3
var end_position: Vector3
var is_moving: bool = false
var players_to_move: Array[CharacterBody3D] = []
var last_floor_position: Vector3

# Frozen Floor Variables
var frozen_time: float = 0.0

# Damage Floor Variables
var damage_timers: Dictionary = {}  # Track damage timer per player

# Momentum tracking variables
var floor_velocity: Vector3 = Vector3.ZERO
var previous_floor_position: Vector3 = Vector3.ZERO
var floor_angular_velocity: float = 0.0

# Editor preview variables
var editor_material: StandardMaterial3D
var runtime_material: StandardMaterial3D

# Property setters that work in editor
func _set_floor_type(value: FloorType):
	floor_type = value
	if Engine.is_editor_hint():
		_update_editor_preview()

func _set_use_default_texture(value: bool):
	use_default_texture = value
	if Engine.is_editor_hint():
		_update_editor_preview()

func _set_custom_texture(value: Texture2D):
	custom_texture = value
	if Engine.is_editor_hint():
		_update_editor_preview()

func _set_texture_scale(value: Vector2):
	texture_scale = value
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

func _set_momentum_transfer_strength(value: float):
	momentum_transfer_strength = clamp(value, 0.0, 2.0)

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

func load_default_texture():
	"""Load the default texture from file"""
	if ResourceLoader.exists(DEFAULT_TEXTURE_PATH):
		default_texture = load(DEFAULT_TEXTURE_PATH)
	else:
		print("Warning: Default texture not found at ", DEFAULT_TEXTURE_PATH)
		default_texture = create_fallback_texture()

func create_fallback_texture() -> ImageTexture:
	"""Create a simple fallback texture if the default texture file is not found"""
	var image = Image.create(64, 64, false, Image.FORMAT_RGB8)
	
	for x in range(64):
		for y in range(64):
			@warning_ignore("integer_division")
			var checker = ((x / 8) + (y / 8)) % 2
			var color = Color.GRAY if checker == 0 else Color.WHITE
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.new()
	texture.set_image(image)
	return texture

func get_texture_to_use() -> Texture2D:
	"""Get the texture that should be applied to the floor"""
	if not use_default_texture and custom_texture:
		return custom_texture
	
	if not default_texture:
		load_default_texture()
	
	return default_texture

func create_textured_material(base_color: Color = Color.WHITE) -> StandardMaterial3D:
	"""Create a material with the appropriate texture applied"""
	var material = StandardMaterial3D.new()
	
	var texture = get_texture_to_use()
	if texture:
		material.albedo_texture = texture
		material.uv1_scale = Vector3(texture_scale.x, texture_scale.y, 1.0)
	
	material.albedo_color = base_color
	material.metallic = 0.1
	material.roughness = 0.7
	
	return material

func _update_editor_preview():
	_ensure_nodes_exist()
	
	if not mesh_instance:
		return
	
	if not editor_material:
		editor_material = StandardMaterial3D.new()
		editor_material.flags_transparent = true
		editor_material.flags_unshaded = true
		editor_material.albedo_color.a = 0.8
	
	var base_color: Color
	match floor_type:
		FloorType.NORMAL:
			base_color = Color(0, 0.8, 0, 0.8)
		FloorType.SPRING:
			base_color = Color(1.0, 0.5, 0.0, 0.8)
		FloorType.FALLING:
			base_color = Color(1.0, 0.2, 0.2, 0.8)
		FloorType.SPINNING:
			base_color = Color(0.8, 0.2, 1.0, 0.8)
		FloorType.MOVING:
			base_color = Color(0.2, 0.7, 1.0, 0.8)
		FloorType.DAMAGE:
			base_color = Color(1.0, 0.3, 0.0, 0.8)
		FloorType.FROZEN:
			base_color = Color(0.6, 0.9, 1.0, 0.8)
		_:
			base_color = Color(0.5, 0.5, 0.5, 0.8)
	
	editor_material.albedo_color = base_color
	
	if use_default_texture or custom_texture:
		var texture = get_texture_to_use()
		if texture:
			editor_material.albedo_texture = texture
			editor_material.uv1_scale = Vector3(texture_scale.x, texture_scale.y, 1.0)
		else:
			editor_material.albedo_texture = null
	else:
		editor_material.albedo_texture = null
	
	mesh_instance.set_surface_override_material(0, editor_material)

func _ready():
	if Engine.is_editor_hint():
		_ensure_nodes_exist()
		setup_floor_geometry()
		_update_editor_preview()
		return
	
	load_default_texture()
	
	if mesh_instance:
		mesh_instance.set_surface_override_material(0, null)
	
	original_position = global_position
	start_position = global_position
	end_position = global_position + movement_axis
	last_floor_position = global_position
	previous_floor_position = global_position
	
	setup_floor_geometry()
	setup_floor_type()
	
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
	var box_mesh = BoxMesh.new()
	box_mesh.size = floor_size
	mesh_instance.mesh = box_mesh
	
	var box_shape = BoxShape3D.new()
	box_shape.size = floor_size
	collision_shape.shape = box_shape
	
	if not Engine.is_editor_hint() and spring_collision:
		var spring_shape = BoxShape3D.new()
		spring_shape.size = Vector3(floor_size.x, floor_size.y + 0.5, floor_size.z)
		spring_collision.shape = spring_shape
		spring_collision.position.y = floor_size.y * 0.25

func setup_cylinder_geometry():
	"""Setup cylinder-shaped floor geometry"""
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.bottom_radius = cylinder_radius
	cylinder_mesh.top_radius = cylinder_radius
	cylinder_mesh.height = cylinder_height
	cylinder_mesh.radial_segments = cylinder_segments
	mesh_instance.mesh = cylinder_mesh
	
	var cylinder_shape = CylinderShape3D.new()
	cylinder_shape.radius = cylinder_radius
	cylinder_shape.height = cylinder_height
	collision_shape.shape = cylinder_shape
	
	if not Engine.is_editor_hint() and spring_collision:
		var spring_shape = CylinderShape3D.new()
		spring_shape.radius = cylinder_radius
		spring_shape.height = cylinder_height + 0.5
		spring_collision.shape = spring_shape
		spring_collision.position.y = cylinder_height * 0.25

func _process(delta):
	if Engine.is_editor_hint():
		return
	
	calculate_floor_velocity(delta)
	
	if spring_cooldown_timer > 0:
		spring_cooldown_timer -= delta
	
	if floor_type == FloorType.SPRING and spring_cooldown_timer <= 0:
		if players_on_floor.size() > 0:
			activate_spring()
	
	if floor_type == FloorType.FALLING and not is_falling and not has_fallen and not fall_triggered:
		if players_on_floor.size() > 0:
			fall_timer += delta
			fall_triggered = true
			start_falling()
	
	if floor_type == FloorType.SPINNING:
		handle_spinning(delta)
	
	if floor_type == FloorType.MOVING and is_moving:
		move_players_with_floor()
	
	if floor_type == FloorType.FROZEN:
		handle_frozen_floor(delta)
	
	if floor_type == FloorType.DAMAGE:
		handle_damage_floor(delta)

func calculate_floor_velocity(delta: float):
	"""Calculate the floor's current velocity for momentum transfer"""
	if delta <= 0:
		return
	
	floor_velocity = (global_position - previous_floor_position) / delta
	previous_floor_position = global_position
	
	if floor_type == FloorType.SPINNING:
		var rotation_speed = spin_speed * (PI / 180.0)
		floor_angular_velocity = rotation_speed if spin_direction == SpinDirection.RIGHT else -rotation_speed

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
		FloorType.FROZEN:
			setup_frozen_floor()
		FloorType.DAMAGE:
			setup_damage_floor()

func setup_normal_floor():
	"""Setup a normal floor"""
	var material = create_textured_material(Color(0.8, 1.0, 0.8, 1))
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = false
		spring_area.visible = false

func setup_spring_floor():
	"""Setup a spring floor"""
	var material = create_textured_material(Color(1.0, 0.8, 0.4, 1))
	material.metallic = 0.2
	material.roughness = 0.3
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		var floor_shape_obj = collision_shape.shape as BoxShape3D
		if floor_shape_obj and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
				spring_collision.position.y = floor_shape_obj.size.y * 0.25

func setup_falling_floor():
	"""Setup a falling floor"""
	var material = create_textured_material(Color(1.0, 0.6, 0.6, 1))
	material.metallic = 0.1
	material.roughness = 0.4
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		var floor_shape_obj = collision_shape.shape as BoxShape3D
		if floor_shape_obj and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
				spring_collision.position.y = floor_shape_obj.size.y * 0.25

func setup_moving_floor():
	"""Setup a moving floor"""
	var material = create_textured_material(Color(0.6, 0.8, 1.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		var floor_shape_obj = collision_shape.shape as BoxShape3D
		if floor_shape_obj and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
				spring_collision.position.y = floor_shape_obj.size.y * 0.25
	
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	start_moving()

func setup_spinning_floor():
	"""Setup a spinning floor"""
	var material = create_textured_material(Color(0.9, 0.6, 1.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true

func setup_frozen_floor():
	"""Setup a frozen/icy floor with physics material"""
	var material = create_textured_material(Color(0.7, 0.9, 1.0, 0.95))
	material.metallic = 0.4
	material.roughness = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	if frozen_enable_visual_effects:
		material.emission_enabled = true
		material.emission = Color(0.6, 0.8, 1.0)
		material.emission_energy = 0.2
	
	mesh_instance.set_surface_override_material(0, material)
	
	# CRITICAL: Set up physics material for classic ice behavior
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = frozen_friction  # Very low friction
	physics_mat.bounce = 0.0  # No bounce
	physics_material_override = physics_mat
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		var floor_shape_obj = collision_shape.shape as BoxShape3D
		if floor_shape_obj and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
				spring_collision.position.y = floor_shape_obj.size.y * 0.25

func setup_damage_floor():
	"""Setup a damage floor (lava, electric, etc.)"""
	var material = create_textured_material(Color(1.0, 0.4, 0.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.0)
	material.emission_energy = 0.5
	
	mesh_instance.set_surface_override_material(0, material)
	
	if spring_area:
		spring_area.monitoring = true
		spring_area.visible = true
		
		var floor_shape_obj = collision_shape.shape as BoxShape3D
		if floor_shape_obj and spring_collision:
			var spring_shape = spring_collision.shape as BoxShape3D
			if spring_shape:
				spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
				spring_collision.position.y = floor_shape_obj.size.y * 0.25

func handle_frozen_floor(delta: float):
	"""Handle frozen floor visual effects only - physics are handled by PhysicsMaterial"""
	if frozen_enable_visual_effects:
		frozen_time += delta
		
		var material = mesh_instance.get_surface_override_material(0)
		if material and material is StandardMaterial3D:
			var shimmer = sin(frozen_time * frozen_shimmer_speed) * frozen_shimmer_intensity
			material.emission_energy = 0.2 + shimmer
	
	# Classic ice floor behavior:
	# The low friction is handled by the physics_material_override
	# No forced state changes - player keeps full control but slides more due to low friction

func handle_damage_floor(delta: float):
	"""Handle damage floor logic - deal damage and knockback to players on floor"""
	for player in players_on_floor:
		if not player or not is_instance_valid(player):
			continue
		
		# Skip if player is dead or invulnerable
		if player.has_method("get"):
			if player.get("is_dead") or player.get("is_invulnerable"):
				continue
		
		# Get or initialize damage timer for this player
		if not damage_timers.has(player):
			damage_timers[player] = 0.0
		
		# Update damage timer
		damage_timers[player] -= delta
		
		# Deal damage if timer expired
		if damage_timers[player] <= 0.0:
			apply_damage_to_player(player)
			damage_timers[player] = damage_interval

func apply_damage_to_player(player: CharacterBody3D):
	"""Apply damage and knockback to a player"""
	if not player or not is_instance_valid(player):
		return
	
	# Calculate knockback direction (away from floor center, upward)
	var knockback_direction = (player.global_position - global_position).normalized()
	knockback_direction.y = 0  # Remove vertical component for horizontal calculation
	
	if knockback_direction.length() < 0.1:
		# If player is directly on center, use random horizontal direction
		knockback_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	
	# Create knockback velocity
	var knockback_velocity = knockback_direction * damage_knockback_force
	knockback_velocity.y = damage_knockback_upward
	
	# Apply damage with knockback
	if player.has_method("take_damage"):
		player.take_damage(damage_amount, knockback_velocity)
		print("Damage floor dealt ", damage_amount, " damage to player with knockback: ", knockback_velocity)

func start_moving():
	"""Start the moving floor sequence"""
	if is_moving:
		return
	
	is_moving = true
	last_floor_position = global_position
	
	if movement_repeat:
		_start_movement_loop()
	else:
		_create_single_movement()
	
	print("Moving floor started! Moving from ", start_position, " to ", end_position)

func _start_movement_loop():
	"""Start the repeating movement loop with delays"""
	_create_movement_cycle()

func _create_movement_cycle():
	"""Create one complete movement cycle (start->end->start) with delays"""
	if not is_moving:
		return
	
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", end_position, movement_duration)
	
	movement_tween.tween_callback(func(): _handle_mid_cycle_delay())

func _handle_mid_cycle_delay():
	"""Handle delay between start->end and end->start movement"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", start_position, movement_duration)
	
	movement_tween.tween_callback(func(): _handle_end_cycle_delay())

func _handle_end_cycle_delay():
	"""Handle delay at the end of a complete cycle before starting next cycle"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	_create_movement_cycle()

func _create_single_movement():
	"""Create a single movement cycle without looping"""
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	
	movement_tween.tween_property(self, "global_position", end_position, movement_duration)
	movement_tween.tween_callback(func(): _handle_single_movement_delay())

func _handle_single_movement_delay():
	"""Handle delay in single movement mode"""
	if movement_delay > 0:
		await get_tree().create_timer(movement_delay).timeout
	
	if not is_moving:
		return
	
	movement_tween = create_tween()
	movement_tween.set_trans(movement_transition)
	movement_tween.set_ease(movement_easing)
	movement_tween.tween_property(self, "global_position", start_position, movement_duration)
	
	movement_tween.tween_callback(func(): is_moving = false)

func move_players_with_floor():
	"""Move players that are on the floor along with the floor"""
	var floor_delta = global_position - last_floor_position
	
	if floor_delta.length() > 0.001:
		var players_to_remove = []
		for player in players_on_floor:
			if player and is_instance_valid(player):
				if player.is_on_floor() or player.velocity.y <= 0.1:
					player.global_position += floor_delta
				else:
					players_to_remove.append(player)
		
		for player in players_to_remove:
			players_on_floor.erase(player)
			if enable_momentum_transfer:
				transfer_momentum_to_player(player)
	
	last_floor_position = global_position

func stop_moving():
	"""Stop the moving floor"""
	if movement_tween:
		movement_tween.kill()
	is_moving = false
	print("Moving floor stopped")

func handle_spinning(delta):
	"""Handle the spinning floor rotation"""
	var rotation_amount = spin_speed * delta
	
	var rotation_radians = deg_to_rad(rotation_amount)
	if spin_direction == SpinDirection.LEFT:
		rotation_radians = -rotation_radians
	
	rotate_y(rotation_radians)
	
	spin_players_with_floor(rotation_radians)

func spin_players_with_floor(rotation_radians: float):
	"""Move players to follow the floor's rotation"""
	if players_on_floor.size() == 0:
		return
	
	var center = global_position
	var players_to_remove = []
	
	for player in players_on_floor:
		if player and is_instance_valid(player):
			if not player.is_on_floor() and player.velocity.y > 0:
				players_to_remove.append(player)
				continue
			
			var player_pos = player.global_position
			var relative_pos = player_pos - center
			
			var rotated_x = relative_pos.x * cos(rotation_radians) + relative_pos.z * sin(rotation_radians)
			var rotated_z = -relative_pos.x * sin(rotation_radians) + relative_pos.z * cos(rotation_radians)
			
			player.global_position = center + Vector3(rotated_x, relative_pos.y, rotated_z)
	
	for player in players_to_remove:
		players_on_floor.erase(player)
		if enable_momentum_transfer:
			transfer_momentum_to_player(player)

func transfer_momentum_to_player(player: CharacterBody3D):
	"""Transfer the floor's momentum to a player when they leave the floor"""
	if not player or not is_instance_valid(player):
		return
	
	if player.velocity.y > 0 or not player.is_on_floor():
		
		match floor_type:
			FloorType.MOVING:
				transfer_linear_momentum(player)
			FloorType.SPINNING:
				transfer_rotational_momentum(player)

func transfer_linear_momentum(player: CharacterBody3D):
	"""Transfer linear momentum from moving floors"""
	var momentum_to_add = Vector3(
		floor_velocity.x * momentum_transfer_strength,
		0,
		floor_velocity.z * momentum_transfer_strength
	)
	
	player.velocity += momentum_to_add
	
	print("Transferred linear momentum: ", momentum_to_add, " to player")
	
func transfer_rotational_momentum(player: CharacterBody3D):
	"""Transfer rotational momentum from spinning floors"""
	var center = global_position
	var player_relative_pos = player.global_position - center
	
	var radius = Vector2(player_relative_pos.x, player_relative_pos.z).length()
	
	if radius < 0.01:
		return
	
	var tangential_speed = abs(floor_angular_velocity) * radius
	
	var radius_direction = Vector2(player_relative_pos.x, player_relative_pos.z).normalized()
	
	var tangent_direction_2d: Vector2
	if spin_direction == SpinDirection.RIGHT:
		tangent_direction_2d = Vector2(radius_direction.y, -radius_direction.x)
	else:
		tangent_direction_2d = Vector2(-radius_direction.y, radius_direction.x)
	
	var tangent_direction = Vector3(tangent_direction_2d.x, 0, tangent_direction_2d.y)
	
	var momentum_to_add = tangent_direction * tangential_speed * momentum_transfer_strength
	
	player.velocity += momentum_to_add
	
	print("Transferred rotational momentum: ", momentum_to_add, " to player")

func _on_spring_area_body_entered(body):
	"""When a player enters the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		if not players_on_floor.has(body):
			players_on_floor.append(body)
			
			if floor_type == FloorType.MOVING:
				if not players_to_move.has(body):
					players_to_move.append(body)

func _on_spring_area_body_exited(body):
	"""When a player exits the spring area"""
	if body.is_in_group("Player") or body.get_script().get_global_name() == "CharacterBody3D":
		if enable_momentum_transfer:
			transfer_momentum_to_player(body)
		
		players_on_floor.erase(body)
		
		# Clean up damage timer for this player
		if damage_timers.has(body):
			damage_timers.erase(body)
		
		if floor_type == FloorType.MOVING:
			players_to_move.erase(body)

func activate_spring():
	"""Activate the spring effect for all players on the floor"""
	for player in players_on_floor:
		if player and is_instance_valid(player):
			apply_spring_effect(player)
	
	spring_cooldown_timer = spring_cooldown

func apply_spring_effect(player: CharacterBody3D):
	"""Apply spring effect to a specific player"""
	if not player:
		return
	
	if player.has_method("get") and player.get("has_double_jumped") != null:
		player.has_double_jumped = false
		player.can_double_jump = true
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	var original_y = player.global_position.y
	
	tween.tween_method(
		func(pos_y): _set_player_y_position(player, pos_y),
		original_y,
		original_y + 0.3,
		spring_tween_duration
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	
	_apply_spring_velocity(player)
	
	tween.tween_callback(func(): _apply_spring_velocity(player)).set_delay(spring_tween_duration)

func _set_player_y_position(player: CharacterBody3D, y_pos: float):
	"""Helper function to set player Y position"""
	if player and is_instance_valid(player):
		player.global_position.y = y_pos

func _apply_spring_velocity(player: CharacterBody3D):
	"""Apply upward velocity to the player"""
	if player and is_instance_valid(player):
		player.velocity.y = spring_force
		
		if player.has_method("get") and player.get("state_machine"):
			var state_machine = player.get("state_machine")
			if state_machine and state_machine.has_method("change_state"):
				state_machine.change_state("JumpingState")
		
		player.move_and_slide()

func start_falling():
	"""Start the falling sequence"""
	if is_falling or has_fallen:
		return
	
	is_falling = true
	print("Floor starting to fall!")
	
	create_warning_shake()
	
	await get_tree().create_timer(shake_duration).timeout
	
	collision_shape.disabled = true
	if spring_area:
		spring_area.monitoring = false
	
	fall_tween = create_tween()
	fall_tween.tween_property(self, "global_position", 
		original_position + Vector3(0, -20, 0), fall_duration)
	fall_tween.tween_callback(func(): _on_fall_complete())

func create_warning_shake():
	"""Create a warning shake effect"""
	var shake_tween = create_tween()
	var shake_loops = int(shake_duration / 0.1)
	var offset_x = 0.44
	var offset_z = 0.45
	shake_tween.set_loops(shake_loops)
	
	shake_tween.tween_property(self, "global_position", 
		original_position + Vector3(offset_x, 0, offset_z), 0.05)
	shake_tween.tween_property(self, "global_position", original_position, 0.05)

func _on_fall_complete():
	"""Called when the floor has finished falling"""
	has_fallen = true
	is_falling = false
	
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 0.3
	
	await get_tree().create_timer(respawn_delay).timeout
	respawn_floor()

func respawn_floor():
	"""Respawn the floor at its original position"""
	print("Floor respawning!")
	
	global_position = original_position
	
	collision_shape.disabled = false
	if spring_area:
		spring_area.monitoring = true
	
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 1.0
	
	is_falling = false
	has_fallen = false
	fall_triggered = false
	fall_timer = 0.0
	players_on_floor.clear()
	
	create_respawn_effect()

func create_respawn_effect():
	"""Create a visual effect when the floor respawns"""
	var respawn_tween = create_tween()
	respawn_tween.set_parallel(true)
	
	var original_scale = scale
	scale = Vector3(0.1, 0.1, 0.1)
	respawn_tween.tween_property(self, "scale", original_scale, 0.5)
	respawn_tween.tween_property(self, "scale", original_scale, 0.5).set_trans(Tween.TRANS_BOUNCE)
	
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		var original_color = material.albedo_color
		material.albedo_color = Color.WHITE
		respawn_tween.tween_property(material, "albedo_color", original_color, 0.3)
