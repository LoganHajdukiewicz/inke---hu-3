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
var coyote_time_duration: float = 0.15  
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

# Gear collection variables
var gear_collection_area: Area3D = null
var gear_collection_distance: float = 0.5 # Collection radius for Inke

# Jump shadow variables
var jump_shadow: MeshInstance3D
var shadow_raycast: RayCast3D
var shadow_max_distance: float = 50.0   # Maximum distance to cast shadow
var shadow_base_size: float = 1.2       # Base size of shadow
var shadow_fade_start: float = 5.0      # Distance where fading starts


# Rail grinding variables
var detected_rail_nodes: Array = []

@export var wall_jump_rays: Node3D
@export var rail_grind_area: Area3D 

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
	else:
		print("Player: GameManager not found!")
	
	setup_gear_collection()
	setup_rail_detection()
	# Defer shadow setup to next frame to ensure everything is ready
	call_deferred("setup_jump_shadow")
	
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

func setup_jump_shadow(): ## TODO: Improperly renders if tilted. 
	"""Set up the jump shadow system"""
	print("Setting up jump shadow...")
	
	await get_tree().process_frame
	
	if not is_inside_tree():
		print("Player not in tree yet, deferring shadow setup")
		call_deferred("setup_jump_shadow")
		return
	
	jump_shadow = MeshInstance3D.new()
	jump_shadow.name = "JumpShadow"
	
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.radial_segments = 32
	cylinder_mesh.rings = 1
	cylinder_mesh.height = 0.01
	cylinder_mesh.top_radius = shadow_base_size * 0.5
	cylinder_mesh.bottom_radius = shadow_base_size * 0.5
	jump_shadow.mesh = cylinder_mesh
	
	var shadow_material = StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0, 0, 0, 0.6)
	shadow_material.flags_transparent = true
	shadow_material.flags_unshaded = true
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	shadow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	shadow_material.no_depth_test = false
	
	jump_shadow.material_override = shadow_material
	jump_shadow.visible = true
	
	shadow_raycast = RayCast3D.new()
	shadow_raycast.name = "ShadowRaycast"
	shadow_raycast.target_position = Vector3(0, -shadow_max_distance, 0)
	shadow_raycast.collision_mask = 1  # Only check layer 1 (ground/walls)
	shadow_raycast.enabled = true
	shadow_raycast.collide_with_areas = false
	shadow_raycast.collide_with_bodies = true
	shadow_raycast.exclude_parent = true
	
	# Add the raycast to the player
	add_child(shadow_raycast)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(jump_shadow)
		print("Jump shadow setup complete!")
	else:
		print("Could not add shadow to scene - no current scene found")

func setup_rail_detection():
	"""Connect signals for the existing RailGrindArea"""
	if not rail_grind_area:
		rail_grind_area = get_node("RailGrindArea")
	
	if rail_grind_area:
		# Connect signals for rail detection
		if not rail_grind_area.body_entered.is_connected(_on_rail_body_entered):
			rail_grind_area.body_entered.connect(_on_rail_body_entered)
		if not rail_grind_area.body_exited.is_connected(_on_rail_body_exited):
			rail_grind_area.body_exited.connect(_on_rail_body_exited)
		if not rail_grind_area.area_entered.is_connected(_on_rail_area_entered):
			rail_grind_area.area_entered.connect(_on_rail_area_entered)
		if not rail_grind_area.area_exited.is_connected(_on_rail_area_exited):
			rail_grind_area.area_exited.connect(_on_rail_area_exited)
		
		print("Rail detection setup complete with RailGrindArea")
	else:
		print("Warning: RailGrindArea not found! Please add an Area3D node named 'RailGrindArea' to the player.")

func _physics_process(delta: float) -> void:
	$CameraController.handle_camera_input(delta)

	var current_state_name = state_machine.current_state.get_script().get_global_name()
	if current_state_name != "RailGrindingState":
		# Smoothly return character to upright orientation
		var upright_basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
		upright_basis = upright_basis.rotated(Vector3.UP, rotation.y)  # Preserve Y rotation (facing direction)
		
		# Smoothly interpolate to upright orientation
		basis = basis.slerp(upright_basis, delta * 10.0)  # Adjust the 10.0 for faster/slower correction
	
	update_coyote_time(delta)
	
	# Update wall jump cooldown
	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta
	
	# Check for nearby gears to collect
	check_for_nearby_gears()
	
	# Check for rail grinding opportunity
	check_for_rail_grinding()
	
	# Check for wall jump opportunity
	check_for_wall_jump()
	
	# Reset double jump on the floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
		
		
	update_jump_shadow()
	
	$CameraController.follow_character(position, velocity)

func update_jump_shadow():
	"""Update the jump shadow position and appearance"""
	if not jump_shadow or not shadow_raycast:
		return
	if not is_inside_tree() or not jump_shadow.is_inside_tree():
		return
	
	# Cast ray from slightly above the player to avoid self-collision
	var ray_start = global_position + Vector3(0, 0.1, 0)
	shadow_raycast.global_position = ray_start
	shadow_raycast.force_raycast_update()
	
	var ground_position: Vector3
	var ground_normal: Vector3 = Vector3.UP
	var distance_to_ground: float
	var found_ground: bool = false
	
	if shadow_raycast.is_colliding():
		# Raycast hit something
		ground_position = shadow_raycast.get_collision_point()
		ground_normal = shadow_raycast.get_collision_normal()
		distance_to_ground = global_position.distance_to(ground_position)
		found_ground = true
	elif is_on_floor():
		# Player is grounded but raycast missed - use player position as fallback
		ground_position = global_position - Vector3(0, 1.0, 0)  # Assume 1 unit below player
		ground_normal = Vector3.UP
		distance_to_ground = 1.0
		found_ground = true
	else:
		# No ground found and player not grounded
		jump_shadow.visible = false
		return
	
	if found_ground:
		# Position shadow slightly above the ground to prevent z-fighting
		var shadow_offset = 0.02  # Increased offset to ensure it's above ground
		jump_shadow.global_position = ground_position + ground_normal * shadow_offset
		
		# Scale based on distance - closer = larger shadow
		var scale_factor = 1.0
		if distance_to_ground <= 0.2:
			scale_factor = 1.0
		else:
			scale_factor = max(0.3, 1.0 - (distance_to_ground - 0.2) / 20.0)
		
		jump_shadow.scale = Vector3(scale_factor, 1.0, scale_factor)
		
		# Fade shadow based on distance
		var alpha = 0.6
		if distance_to_ground > shadow_fade_start:
			alpha = max(0.2, 0.6 - (distance_to_ground - shadow_fade_start) / 25.0)
		
		# Update material alpha
		if jump_shadow.material_override:
			var material = jump_shadow.material_override as StandardMaterial3D
			var current_color = material.albedo_color
			current_color.a = alpha
			material.albedo_color = current_color
		
		# Align shadow to ground normal
		var up_vector = ground_normal
		var forward_vector = Vector3.FORWARD
		
		# Handle edge cases for surface orientation
		if abs(up_vector.y) < 0.1:  # Very steep surface
			up_vector = Vector3.UP
		if abs(up_vector.dot(forward_vector)) > 0.9:
			forward_vector = Vector3.RIGHT
		
		var right_vector = forward_vector.cross(up_vector).normalized()
		forward_vector = up_vector.cross(right_vector).normalized()
		jump_shadow.basis = Basis(right_vector, up_vector, forward_vector)
		
		jump_shadow.visible = true
	else:
		jump_shadow.visible = false

func update_simple_shadow():
	if not jump_shadow:
		# Create shadow if it doesn't exist
		jump_shadow = MeshInstance3D.new()
		var mesh = CylinderMesh.new()
		mesh.top_radius = 0.5
		mesh.bottom_radius = 0.5
		mesh.height = 0.05
		mesh.radial_segments = 32
		jump_shadow.mesh = mesh
		
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0, 0, 0, 0.6)
		mat.flags_transparent = true
		mat.flags_unshaded = true
		jump_shadow.material_override = mat
		
		add_child(jump_shadow)
	
	if is_on_floor():
		jump_shadow.visible = true
		# Position it just above the ground
		jump_shadow.global_position = global_position + Vector3.DOWN * 0.95
		jump_shadow.scale = Vector3(1.2, 1.0, 1.2)
	else:
		jump_shadow.visible = false
		

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
	else:
		# Fallback - mark as collected and remove
		if gear.has_method("set"):
			gear.set("collected", true)
		if game_manager:
			game_manager.add_gear(1)
		gear.queue_free()

func _on_gear_body_entered(body: Node3D):
	"""Handle when a gear body enters collection area"""
	if body.is_in_group("Gear"):
		collect_gear(body)

func _on_gear_area_entered(area: Area3D):
	"""Handle when a gear area enters collection area"""
	if area.is_in_group("Gear"):
		var gear_node = area.get_parent()
		if gear_node and gear_node.is_in_group("Gear"):
			collect_gear(gear_node)
		else:
			collect_gear(area)

# === RAIL DETECTION SIGNAL HANDLERS ===

func _on_rail_body_entered(body: Node3D):
	"""Handle when a rail body enters detection area"""
	if body.is_in_group("rail_follower"):
		if body not in detected_rail_nodes:
			detected_rail_nodes.append(body)

func _on_rail_body_exited(body: Node3D):
	"""Handle when a rail body exits detection area"""
	if body in detected_rail_nodes:
		detected_rail_nodes.erase(body)

func _on_rail_area_entered(area: Area3D):
	"""Handle when a rail area enters detection area"""
	if area.is_in_group("rail_follower"):
		if area not in detected_rail_nodes:
			detected_rail_nodes.append(area)
	# Check if the area's parent is a rail follower
	elif area.get_parent() and area.get_parent().is_in_group("rail_follower"):
		var rail_node = area.get_parent()
		if rail_node not in detected_rail_nodes:
			detected_rail_nodes.append(rail_node)

func _on_rail_area_exited(area: Area3D):
	"""Handle when a rail area exits detection area"""
	if area.is_in_group("rail_follower"):
		if area in detected_rail_nodes:
			detected_rail_nodes.erase(area)
	# Check if the area's parent is a rail follower
	elif area.get_parent() and area.get_parent().is_in_group("rail_follower"):
		var rail_node = area.get_parent()
		if rail_node in detected_rail_nodes:
			detected_rail_nodes.erase(rail_node)

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
			var closest_rail_node = get_closest_rail_node()
			if closest_rail_node:
				state_machine.change_state("RailGrindingState")
				rail_grinding_state.setup_grinding_with_node(closest_rail_node)

func get_closest_rail_node():
	"""Get the closest rail follower node from detected nodes"""
	if detected_rail_nodes.is_empty():
		return null
	
	var closest_node = null
	var min_distance = INF
	
	for rail_node in detected_rail_nodes:
		if not is_instance_valid(rail_node):
			continue
		
		var distance = global_position.distance_to(rail_node.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_node = rail_node
	
	return closest_node

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
