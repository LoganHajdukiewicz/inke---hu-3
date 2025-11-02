extends Node
class_name JumpShadowManager

# Shadow variables
var jump_shadow: MeshInstance3D
var shadow_raycasts: Array[RayCast3D] = []
var shadow_max_distance: float = 50.0
var shadow_base_size: float = 1.2
var shadow_fade_start: float = 5.0

# Multi-raycast variables
var raycast_count: int = 12
var raycast_radius: float = 0.5

var player: CharacterBody3D
var is_enabled: bool = true

func _ready():
	player = get_parent() as CharacterBody3D
	call_deferred("setup_jump_shadow")

func setup_jump_shadow():
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
	jump_shadow.visible = false
	
	# Setup multiple raycasts
	setup_raycasts()
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(jump_shadow)
		print("Jump shadow setup complete!")
	else:
		print("Could not add shadow to scene - no current scene found")

func setup_raycasts():
	"""Create multiple raycasts arranged in a circle"""
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
	if jump_shadow:
		jump_shadow.visible = enabled and is_enabled

func update_jump_shadow():
	"""Update the jump shadow position and appearance"""
	if not jump_shadow or not is_enabled:
		if jump_shadow:
			jump_shadow.visible = false
		return
	
	if not is_inside_tree() or not jump_shadow.is_inside_tree():
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
		var shadow_offset = 0.02
		jump_shadow.global_position = closest_point + closest_normal * shadow_offset
		
		var scale_factor = 1.0
		if closest_distance <= 0.2:
			scale_factor = 1.0
		else:
			scale_factor = max(0.3, 1.0 - (closest_distance - 0.2) / 20.0)
		
		jump_shadow.scale = Vector3(scale_factor, 1.0, scale_factor)
		
		var alpha = 0.6
		if closest_distance > shadow_fade_start:
			alpha = max(0.2, 0.6 - (closest_distance - shadow_fade_start) / 25.0)
		
		if jump_shadow.material_override:
			var material = jump_shadow.material_override as StandardMaterial3D
			var current_color = material.albedo_color
			current_color.a = alpha
			material.albedo_color = current_color
		
		var up_vector = closest_normal
		var forward_vector = Vector3.FORWARD
		
		if abs(up_vector.y) < 0.1:
			up_vector = Vector3.UP
		if abs(up_vector.dot(forward_vector)) > 0.9:
			forward_vector = Vector3.RIGHT
		
		var right_vector = forward_vector.cross(up_vector).normalized()
		forward_vector = up_vector.cross(right_vector).normalized()
		jump_shadow.basis = Basis(right_vector, up_vector, forward_vector)
		
		jump_shadow.visible = true
	else:
		jump_shadow.visible = false
