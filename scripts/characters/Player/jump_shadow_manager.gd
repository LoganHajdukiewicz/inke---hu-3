extends Node
class_name JumpShadowManager

# Shadow variables
var jump_shadow: MeshInstance3D
var shadow_raycast: RayCast3D
var shadow_max_distance: float = 50.0
var shadow_base_size: float = 1.2
var shadow_fade_start: float = 5.0

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
	
	shadow_raycast = RayCast3D.new()
	shadow_raycast.name = "ShadowRaycast"
	shadow_raycast.target_position = Vector3(0, -shadow_max_distance, 0)
	shadow_raycast.collision_mask = 1
	shadow_raycast.enabled = true
	shadow_raycast.collide_with_areas = false
	shadow_raycast.collide_with_bodies = true
	shadow_raycast.exclude_parent = true
	
	player.add_child(shadow_raycast)
	
	if get_tree() and get_tree().current_scene:
		get_tree().current_scene.add_child(jump_shadow)
		print("Jump shadow setup complete!")
	else:
		print("Could not add shadow to scene - no current scene found")

func _physics_process(_delta):
	update_jump_shadow()

func set_enabled(enabled: bool):
	"""Enable or disable the shadow rendering"""
	is_enabled = enabled
	if jump_shadow:
		jump_shadow.visible = enabled and is_enabled

func update_jump_shadow():
	"""Update the jump shadow position and appearance"""
	if not jump_shadow or not shadow_raycast or not is_enabled:
		if jump_shadow:
			jump_shadow.visible = false
		return
	
	if not is_inside_tree() or not jump_shadow.is_inside_tree():
		return
	
	# Cast ray from slightly above the player to avoid self-collision
	var ray_start = player.global_position + Vector3(0, 0.1, 0)
	shadow_raycast.global_position = ray_start
	shadow_raycast.force_raycast_update()
	
	var ground_position: Vector3
	var ground_normal: Vector3 = Vector3.UP
	var distance_to_ground: float
	var found_ground: bool = false
	
	if shadow_raycast.is_colliding():
		ground_position = shadow_raycast.get_collision_point()
		ground_normal = shadow_raycast.get_collision_normal()
		distance_to_ground = player.global_position.distance_to(ground_position)
		found_ground = true
	elif player.is_on_floor():
		ground_position = player.global_position - Vector3(0, 1.0, 0)
		ground_normal = Vector3.UP
		distance_to_ground = 1.0
		found_ground = true
	else:
		jump_shadow.visible = false
		return
	
	if found_ground:
		var shadow_offset = 0.02
		jump_shadow.global_position = ground_position + ground_normal * shadow_offset
		
		var scale_factor = 1.0
		if distance_to_ground <= 0.2:
			scale_factor = 1.0
		else:
			scale_factor = max(0.3, 1.0 - (distance_to_ground - 0.2) / 20.0)
		
		jump_shadow.scale = Vector3(scale_factor, 1.0, scale_factor)
		
		var alpha = 0.6
		if distance_to_ground > shadow_fade_start:
			alpha = max(0.2, 0.6 - (distance_to_ground - shadow_fade_start) / 25.0)
		
		if jump_shadow.material_override:
			var material = jump_shadow.material_override as StandardMaterial3D
			var current_color = material.albedo_color
			current_color.a = alpha
			material.albedo_color = current_color
		
		var up_vector = ground_normal
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
