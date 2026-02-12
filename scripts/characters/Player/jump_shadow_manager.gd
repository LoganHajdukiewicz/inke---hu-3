extends Node
class_name JumpShadowManager

# Shadow variables
var jump_shadow_decal: Decal
var shadow_raycasts: Array[RayCast3D] = []
var shadow_max_distance: float = 50.0
var shadow_base_size: float = 4.0
var shadow_fade_start: float = 5.0

# Multi-raycast variables for surface detection
var raycast_count: int = 12
var raycast_radius: float = 0.7

# Decal configuration
var shadow_texture: Texture2D
var decal_size: Vector3 = Vector3(1.2, 1.2, 1.0)  # Width, Height, Depth

var player: CharacterBody3D
var is_enabled: bool = true

func _ready():
	player = get_parent() as CharacterBody3D
	call_deferred("setup_jump_shadow")

func setup_jump_shadow():
	"""Set up the decal-based jump shadow system"""
	print("Setting up decal-based jump shadow...")
	
	await get_tree().process_frame
	
	if not is_inside_tree():
		print("Player not in tree yet, deferring shadow setup")
		call_deferred("setup_jump_shadow")
		return
	
	# Create decal node
	jump_shadow_decal = Decal.new()
	jump_shadow_decal.name = "JumpShadowDecal"
	
	# Create shadow texture programmatically
	shadow_texture = create_shadow_texture()
	
	# Configure decal
	jump_shadow_decal.texture_albedo = shadow_texture
	jump_shadow_decal.size = decal_size
	jump_shadow_decal.modulate = Color(0, 0, 0, 0.6)  # Black with transparency
	jump_shadow_decal.cull_mask = 1  # Only project on default layer
	jump_shadow_decal.emission_energy = 0.0
	jump_shadow_decal.albedo_mix = 1.0
	jump_shadow_decal.upper_fade = 0.1  # Smooth fade at edges
	jump_shadow_decal.lower_fade = 0.1
	jump_shadow_decal.visible = false
	
	# Setup raycasts for surface detection
	setup_raycasts()
	
	# Add decal to scene
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(jump_shadow_decal)
		print("Decal-based jump shadow setup complete!")
	else:
		print("Could not add shadow to scene - no current scene found")

func create_shadow_texture() -> Texture2D:
	"""Create a circular gradient shadow texture"""
	var size = 256
	var image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	
	var center = Vector2(size / 2.0, size / 2.0)
	var max_radius = size / 2.0
	
	for y in range(size):
		for x in range(size):
			var pos = Vector2(x, y)
			var dist = pos.distance_to(center)
			
			# Create soft circular gradient
			var alpha = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			alpha = pow(alpha, 2.0)  # Sharper falloff
			
			# Apply additional softening at edges
			if alpha < 0.1:
				alpha = 0.0
			
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	return ImageTexture.create_from_image(image)

func setup_raycasts():
	"""Create multiple raycasts arranged in a circle for surface detection"""
	shadow_raycasts.clear()
	
	for i in range(raycast_count):
		var angle = (i / float(raycast_count)) * TAU
		var raycast = RayCast3D.new()
		raycast.name = "ShadowRaycast_%d" % i
		raycast.target_position = Vector3(0, -shadow_max_distance, 0)
		raycast.collision_mask = 1
		raycast.enabled = true
		raycast.collide_with_areas = false
		raycast.collide_with_bodies = true
		raycast.exclude_parent = true
		
		var offset_x = cos(angle) * raycast_radius
		var offset_z = sin(angle) * raycast_radius
		raycast.position = Vector3(offset_x, 0, offset_z)
		
		player.add_child(raycast)
		shadow_raycasts.append(raycast)

func _physics_process(_delta):
	update_jump_shadow()

func set_enabled(enabled: bool):
	"""Enable or disable the shadow rendering"""
	is_enabled = enabled
	if jump_shadow_decal:
		jump_shadow_decal.visible = enabled and is_enabled

func update_jump_shadow():
	"""Update the decal shadow position and appearance based on raycasts"""
	if not jump_shadow_decal or not is_enabled:
		if jump_shadow_decal:
			jump_shadow_decal.visible = false
		return
	
	if not is_inside_tree() or not jump_shadow_decal.is_inside_tree():
		return
	
	var ray_start = player.global_position + Vector3(0, 0.1, 0)
	
	var closest_point = Vector3.ZERO
	var closest_distance = INF
	var closest_normal = Vector3.UP
	var found_ground = false
	
	# Find the closest collision point from all raycasts
	for raycast in shadow_raycasts:
		raycast.global_position = ray_start
		raycast.force_raycast_update()
		
		if raycast.is_colliding():
			var hit_point = raycast.get_collision_point()
			var distance = ray_start.distance_to(hit_point)
			
			if distance < closest_distance:
				closest_distance = distance
				closest_point = hit_point
				closest_normal = raycast.get_collision_normal()
				found_ground = true
	
	# Fallback to single raycast below if no circle raycasts hit
	if not found_ground and player.is_on_floor():
		closest_point = player.global_position - Vector3(0, 1.0, 0)
		closest_distance = 1.0
		closest_normal = Vector3.UP
		found_ground = true
	
	if found_ground:
		# Position decal slightly above surface to avoid z-fighting
		var shadow_offset = 0.05
		jump_shadow_decal.global_position = closest_point + closest_normal * shadow_offset
		
		# Calculate size based on distance
		var scale_factor = 1.0
		if closest_distance <= 0.2:
			scale_factor = 1.0
		else:
			scale_factor = max(0.3, 1.0 - (closest_distance - 0.2) / 20.0)
		
		# Update decal size (maintain aspect ratio)
		var size_multiplier = scale_factor * shadow_base_size
		jump_shadow_decal.size = Vector3(size_multiplier, size_multiplier, 1.0)
		
		# Calculate alpha based on distance
		var alpha = 0.6
		if closest_distance > shadow_fade_start:
			alpha = max(0.2, 0.6 - (closest_distance - shadow_fade_start) / 25.0)
		
		# Update decal modulate for alpha
		jump_shadow_decal.modulate = Color(0, 0, 0, alpha)
		
		# CRITICAL: Orient decal to match surface normal
		# Decals project along their -Z axis, so we need to align -Z with the surface normal
		var up_vector = closest_normal
		
		# Choose a reference vector that's not parallel to the normal
		var reference = Vector3.FORWARD
		if abs(up_vector.dot(reference)) > 0.9:
			reference = Vector3.RIGHT
		
		# Calculate right and forward vectors perpendicular to normal
		var right_vector = reference.cross(up_vector).normalized()
		var forward_vector = up_vector.cross(right_vector).normalized()
		
		# Create basis with -Z pointing along normal (for decal projection)
		# X = right, Y = up (normal), Z = -forward (projection direction)
		jump_shadow_decal.basis = Basis(right_vector, up_vector, -forward_vector)
		
		jump_shadow_decal.visible = true
	else:
		jump_shadow_decal.visible = false
