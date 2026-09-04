@tool
extends StaticBody3D
class_name Floor

## Configurable floor. Per-type behavior lives in small handler files under
## scripts/environments/floor_types/ — this node only owns geometry, editor
## preview and shared state, and delegates runtime behavior to one handler.

enum FloorType {
	NORMAL,
	SPRING,
	FALLING,
	SPINNING,
	MOVING, 
	DAMAGE, # non-lethal damaging floors, i.e. lava, electric
	FROZEN,
	SLIDING,  # Forces player into sliding state, sliding down the slope
	TREADMILL  # Conveyor belt: pushes the player, the ground itself stays put
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
## Extra behaviors layered on top of floor_type. Example: a MOVING floor with
## FROZEN in this list is a moving ice floor. Duplicates of floor_type are ignored.
@export var extra_floor_types: Array[FloorType] = []

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
@export var use_directional_bounce: bool = true  # If true, bounces in the direction the floor is facing
# Assigned by _ensure_nodes_exist (created on demand so a Floor added
# straight from the Add Node dialog works without the .tscn children)
var spring_area: Area3D
var spring_collision: CollisionShape3D

@export_group("Sliding Floor Settings")
@export var slide_max_speed: float = 30.0  # Maximum downhill slide speed
@export var slide_acceleration: float = 25.0  # How fast the player accelerates downhill
@export var slide_steering_strength: float = 6.0  # Sideways steering power while sliding

@export_group("Falling Floor Settings")
@export var fall_speed: float = 5.0
@export var fall_duration: float = 3.0
@export var respawn_delay: float = 2.0
@export var shake_intensity: float = 0.35
@export var shake_duration: float = 1.0

@export_group("Motion Floor Settings")
## MOVING and SPINNING are the same system (one MotionFloor handler that
## carries riders and hands momentum over on exit). The floor type picks
## the default, or force either/both here:
## Translate between two points (defaults on for FloorType.MOVING).
@export var motion_moves_override: bool = false
## Spin around Y (defaults on for FloorType.SPINNING).
@export var motion_spins_override: bool = false
@export_subgroup("Movement")
@export var movement_axis: Vector3 = Vector3(10, 0, 0)  # Distance to move in each axis
@export var movement_duration: float = 3.0  # Time to complete one movement cycle
@export var movement_repeat: bool = true  # Whether to repeat the movement
@export var movement_delay: float = 0.0  # Delay before starting movement
@export var movement_easing: Tween.EaseType = Tween.EASE_IN_OUT
@export var movement_transition: Tween.TransitionType = Tween.TRANS_SINE
@export_subgroup("Spin")
@export var spin_speed: float = 90.0  # degrees per second
@export var spin_direction: SpinDirection = SpinDirection.RIGHT

@export_group("Frozen Floor Settings")
@export var frozen_friction: float = 0.01  # Very low friction for ice
@export var frozen_enable_visual_effects: bool = true  # Enable ice visual effects
@export var frozen_shimmer_speed: float = 2.0  # Speed of the shimmer effect
@export var frozen_shimmer_intensity: float = 0.3  # How noticeable the shimmer is

@export_group("Damage Floor Settings")
@export var damage_amount: int = 1  # Amount of damage to deal
@export var damage_interval: float = 0.5  # Time between damage ticks
@export var damage_knockback_force: float = 15.0  # Horizontal knockback strength
@export var damage_knockback_upward: float = 8.0  # Upward knockback strength

@export_group("Treadmill Floor Settings")
## Belt speed in m/s. The ground never moves - only things standing on it.
@export var treadmill_speed: float = 15.0
## Belt direction in the floor's LOCAL space (rotate the floor to aim it).
@export var treadmill_direction: Vector3 = Vector3(1, 0, 0)
## Scroll the belt texture so the direction reads at a glance.
@export var treadmill_visual_scroll: bool = true

@export_group("Momentum Settings")
@export var momentum_transfer_strength: float = 0.6 : set = _set_momentum_transfer_strength
@export var enable_momentum_transfer: bool = true

# General Variables (see _ensure_nodes_exist)
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D

# Texture Variables
var default_texture: Texture2D
const DEFAULT_TEXTURE_PATH = "res://textures/texture_08.png"

# Shared runtime state (used by handlers)
var players_on_floor: Array[CharacterBody3D] = []
var original_position: Vector3
var start_position: Vector3
var end_position: Vector3

## Does this floor translate? (MOVING type, or forced via override)
var motion_moves: bool:
	get: return motion_moves_override or has_floor_type(FloorType.MOVING)
## Does this floor spin? (SPINNING type, or forced via override)
var motion_spins: bool:
	get: return motion_spins_override or has_floor_type(FloorType.SPINNING)

# Momentum tracking (read by handlers)
var floor_velocity: Vector3 = Vector3.ZERO
var previous_floor_position: Vector3 = Vector3.ZERO
var floor_angular_velocity: float = 0.0

# The active per-type behavior handlers. type_handler is the primary
# (from floor_type); type_handlers includes it plus any extra_floor_types.
var type_handler: FloorTypeHandler = null
var type_handlers: Array[FloorTypeHandler] = []

# Editor preview variables
var editor_material: StandardMaterial3D

# ---------------------------------------------------------------------------
# Property setters that work in editor
# ---------------------------------------------------------------------------

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
	"""Create any missing child nodes. Makes Floor fully self-building, so
	adding it from the Add Node dialog (a bare node with just this script)
	works exactly like instancing floor.tscn."""
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
	
	if not spring_area:
		spring_area = get_node_or_null("SpringArea")
		if not spring_area:
			spring_area = Area3D.new()
			spring_area.name = "SpringArea"
			spring_area.monitoring = false
			add_child(spring_area)
	
	if not spring_collision:
		spring_collision = spring_area.get_node_or_null("CollisionShape3D")
		if not spring_collision:
			spring_collision = CollisionShape3D.new()
			spring_collision.name = "CollisionShape3D"
			spring_area.add_child(spring_collision)

# ---------------------------------------------------------------------------
# Textures / materials (shared by handlers via create_textured_material)
# ---------------------------------------------------------------------------

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
		FloorType.SLIDING:
			base_color = Color(0.9, 0.9, 0.3, 0.8)  # Yellow for sliding floors
		FloorType.TREADMILL:
			base_color = Color(0.25, 0.25, 0.3, 0.8)  # Dark belt grey
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

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready():
	_ensure_nodes_exist()
	if Engine.is_editor_hint():
		setup_floor_geometry()
		_update_editor_preview()
		return
	
	load_default_texture()
	
	if mesh_instance:
		mesh_instance.set_surface_override_material(0, null)
	
	original_position = global_position
	start_position = global_position
	end_position = global_position + movement_axis
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

func setup_floor_type():
	"""Create behavior handlers for the configured floor type(s).
	Floors can combine types: floor_type is the primary, extra_floor_types
	layer additional behaviors (e.g. MOVING + FROZEN = moving ice floor)."""
	type_handlers.clear()
	
	var all_types: Array[FloorType] = [floor_type]
	for extra in extra_floor_types:
		if not all_types.has(extra):
			all_types.append(extra)
	
	for t in all_types:
		var handler := _create_handler(t)
		if handler:
			type_handlers.append(handler)
	
	type_handler = type_handlers[0] if type_handlers.size() > 0 else null
	
	for handler in type_handlers:
		handler.setup()

func _create_handler(t: FloorType) -> FloorTypeHandler:
	match t:
		FloorType.NORMAL:
			return NormalFloor.new(self)
		FloorType.SPRING:
			return SpringFloor.new(self)
		FloorType.FALLING:
			return FallingFloor.new(self)
		FloorType.SPINNING, FloorType.MOVING:
			# One unified motion handler covers both (and both at once).
			# Don't create it twice if MOVING + SPINNING are combined.
			for h in type_handlers:
				if h is MotionFloor:
					return null
			return MotionFloor.new(self)
		FloorType.FROZEN:
			return FrozenFloor.new(self)
		FloorType.DAMAGE:
			return DamageFloor.new(self)
		FloorType.SLIDING:
			return SlidingFloor.new(self)
		FloorType.TREADMILL:
			return TreadmillFloor.new(self)
	return null

func has_floor_type(t: FloorType) -> bool:
	"""True if this floor behaves as the given type (primary OR extra).
	Use this instead of comparing floor_type directly."""
	if floor_type == t:
		return true
	return extra_floor_types.has(t)

func _process(delta):
	if Engine.is_editor_hint():
		return
	
	calculate_floor_velocity(delta)
	
	for handler in type_handlers:
		handler.process(delta)

func calculate_floor_velocity(delta: float):
	"""Track the floor's velocity for momentum transfer"""
	if delta <= 0:
		return
	
	floor_velocity = (global_position - previous_floor_position) / delta
	previous_floor_position = global_position
	
	if motion_spins:
		var rotation_speed = spin_speed * (PI / 180.0)
		floor_angular_velocity = rotation_speed if spin_direction == SpinDirection.RIGHT else -rotation_speed

# ---------------------------------------------------------------------------
# Player detection (shared by all types)
# ---------------------------------------------------------------------------

func _on_spring_area_body_entered(body):
	"""When a player enters the floor's detection area"""
	if body.is_in_group("Player"):
		if not players_on_floor.has(body):
			players_on_floor.append(body)
			for handler in type_handlers:
				handler.on_player_entered(body)

func _on_spring_area_body_exited(body):
	"""When a player exits the floor's detection area"""
	if body.is_in_group("Player"):
		for handler in type_handlers:
			handler.on_player_exited(body)
		players_on_floor.erase(body)
