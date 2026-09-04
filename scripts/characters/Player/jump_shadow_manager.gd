extends Node
class_name JumpShadowManager

# Shadow variables
var jump_shadow_decal: Decal
var shadow_raycasts: Array[RayCast3D] = []
var shadow_max_distance: float = 50.0
var shadow_base_size: float = 1.2
var shadow_fade_start: float = 5.0
# Shadow darkness: 1.0 = fully opaque black at the center. Kept high so the
# landing marker is reliably visible on any surface/lighting.
# (0.95 -> 0.98: transparency halved again per feedback)
var shadow_opacity: float = 0.98
var shadow_min_opacity: float = 0.8    # Never fades below this while visible

# Smoothing: the decal used to snap instantly between raycast hits, which
# looked jittery on uneven ground. Position/size/alpha now ease toward
# their targets.
var position_smooth_speed: float = 25.0
var size_smooth_speed: float = 12.0
var _smoothed_size: float = 1.2
var _smoothed_alpha: float = 0.98
var _has_valid_pose: bool = false

# Multi-raycast variables for surface detection
var raycast_count: int = 12
var raycast_radius: float = 0.5

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
	
	await get_tree().process_frame
	
	if not is_inside_tree():
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
	jump_shadow_decal.modulate = Color(0, 0, 0, shadow_opacity)  # Near-solid black
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
			
			# Solid dark core with a silky feathered rim: smoothstep over the
			# outer 45% of the radius. No hard alpha cutoff (the old < 0.1
			# clamp created a visible ring at the edge).
			var t = 1.0 - clamp(dist / max_radius, 0.0, 1.0)
			var alpha = smoothstep(0.0, 0.45, t)
			
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	
	return ImageTexture.create_from_image(image)

func setup_raycasts():
	"""Create multiple raycasts arranged in a circle for surface detection"""
	shadow_raycasts.clear()
	
	for i in range(raycast_count):
		var angle = (i / float(raycast_count)) * TAU
		var raycast = RayCast3D.new()
		raycast.name = "ShadowRaycast_%d" % i
		# TOP LEVEL: the ray's transform is WORLD space - it never inherits
		# the player's rotation/scale. Two bugs die here:
		#  - tilted player (swing bars) can't tilt the rays
		#  - assigning global_transform to a child needs the PARENT's inverse;
		#    when a scale-punch tween makes the player's scale 0 for a frame,
		#    that inverse is impossible -> 'invert: det == 0' error spam.
		raycast.top_level = true
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

func _physics_process(delta):
	update_jump_shadow(delta)

func set_enabled(enabled: bool):
	"""Enable or disable the shadow rendering"""
	is_enabled = enabled
	if jump_shadow_decal:
		jump_shadow_decal.visible = enabled and is_enabled

func update_jump_shadow(delta: float = 1.0 / 60.0):
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
	
	# The rays are top_level (world-space): identity basis = straight down
	# regardless of how the player is tilted (swing bars). Ring rays help
	# catch ledge edges, but only their VERTICAL drop competes for closest -
	# comparing full 3D distance made the winner hop between ring points
	# 0.5m apart as you moved (shadow jitter).
	var i := 0
	for raycast in shadow_raycasts:
		var angle = (i / float(raycast_count)) * TAU
		var ring_offset := Vector3(cos(angle) * raycast_radius, 0, sin(angle) * raycast_radius)
		raycast.global_transform = Transform3D(Basis.IDENTITY, ray_start + ring_offset)
		raycast.force_raycast_update()
		i += 1
		
		if raycast.is_colliding():
			var hit_point = raycast.get_collision_point()
			var drop = ray_start.y - hit_point.y   # vertical only (see above)
			
			if drop < closest_distance:
				closest_distance = drop
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
		# Position decal slightly above surface to avoid z-fighting.
		# XZ is pinned to the PLAYER (the shadow marks where SHE lands) -
		# only the height comes from the winning ray. Using the ray's own
		# XZ made the shadow jump between ring points (jitter).
		var shadow_offset = 0.05
		var target_pos = Vector3(player.global_position.x, closest_point.y, player.global_position.z) + closest_normal * shadow_offset
		
		# Calculate size based on distance
		var scale_factor = 1.0
		if closest_distance <= 0.2:
			scale_factor = 1.0
		else:
			scale_factor = max(0.3, 1.0 - (closest_distance - 0.2) / 20.0)
		var target_size = scale_factor * shadow_base_size
		
		# Calculate alpha based on distance (stays dark - it's a gameplay aid)
		var target_alpha = shadow_opacity
		if closest_distance > shadow_fade_start:
			target_alpha = max(shadow_min_opacity, shadow_opacity - (closest_distance - shadow_fade_start) / 25.0)
		
		# SMOOTHING: ease toward the new pose instead of snapping. Horizontal
		# tracking is snappy (must stay under the player), but height/size/
		# alpha changes ease in so ledge transitions don't pop.
		if not _has_valid_pose or not jump_shadow_decal.visible:
			# First frame after being hidden: snap everything
			jump_shadow_decal.global_position = target_pos
			_smoothed_size = target_size
			_smoothed_alpha = target_alpha
			_has_valid_pose = true
		else:
			var pos_w = clampf(position_smooth_speed * delta, 0.0, 1.0)
			var cur = jump_shadow_decal.global_position
			# XZ follows tightly, Y eases (that's where the popping happened)
			jump_shadow_decal.global_position = Vector3(
				lerpf(cur.x, target_pos.x, minf(pos_w * 2.0, 1.0)),
				lerpf(cur.y, target_pos.y, pos_w),
				lerpf(cur.z, target_pos.z, minf(pos_w * 2.0, 1.0)))
			var size_w = clampf(size_smooth_speed * delta, 0.0, 1.0)
			_smoothed_size = lerpf(_smoothed_size, target_size, size_w)
			_smoothed_alpha = lerpf(_smoothed_alpha, target_alpha, size_w)
		
		jump_shadow_decal.size = Vector3(_smoothed_size, _smoothed_size, 1.0)
		jump_shadow_decal.modulate = Color(0, 0, 0, _smoothed_alpha)
		
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
		_has_valid_pose = false
