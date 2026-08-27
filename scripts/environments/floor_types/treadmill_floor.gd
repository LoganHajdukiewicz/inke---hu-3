class_name TreadmillFloor
extends FloorTypeHandler

## Conveyor belt / treadmill. The ground itself NEVER moves - anything
## standing on it gets pushed in treadmill_direction at treadmill_speed.
## The push only applies while you're on the belt (the floor's detection
## area is the boundary), so stepping off ends it instantly - just like a
## real treadmill.
##
## Speed:      owner_floor.treadmill_speed      (default 15)
## Direction:  owner_floor.treadmill_direction  (floor-local; rotate the
##             floor node to aim the belt)

var _scroll_time: float = 0.0
var _material: StandardMaterial3D


func setup() -> void:
	_material = owner_floor.create_textured_material(Color(0.3, 0.3, 0.36, 1))
	_material.metallic = 0.55
	_material.roughness = 0.45
	owner_floor.mesh_instance.set_surface_override_material(0, _material)
	
	# Belt stripes: emissive chevron-ish tint so the direction reads even
	# without a custom texture
	_material.emission_enabled = true
	_material.emission = Color(0.9, 0.6, 0.1)
	_material.emission_energy = 0.15
	
	enable_detection_area()
	_build_direction_arrows()


func process(delta: float) -> void:
	var world_dir = _world_belt_direction()
	
	# Push every player currently on the belt
	for player in owner_floor.players_on_floor:
		if not player or not is_instance_valid(player):
			continue
		# Only push while actually standing on it (not while jumping over)
		if not player.is_on_floor():
			continue
		# Direct position shift, like a real belt carrying you: doesn't
		# fight the player's own velocity, and stops the instant you leave
		# the detection boundary.
		player.global_position += world_dir * owner_floor.treadmill_speed * delta
	
	# Scroll the texture so the belt visibly "runs"
	if owner_floor.treadmill_visual_scroll and _material:
		_scroll_time += delta
		var scroll = _scroll_time * owner_floor.treadmill_speed * 0.05
		_material.uv1_offset = Vector3(-scroll, 0, 0)


func _world_belt_direction() -> Vector3:
	var local_dir = owner_floor.treadmill_direction
	if local_dir.length() < 0.01:
		local_dir = Vector3(1, 0, 0)
	var world = owner_floor.global_transform.basis * local_dir
	world.y = 0
	return world.normalized() if world.length() > 0.01 else Vector3(1, 0, 0)


func _build_direction_arrows() -> void:
	"""A few flat arrow chevrons on the surface showing belt direction."""
	var size: Vector3
	if owner_floor.collision_shape and owner_floor.collision_shape.shape is BoxShape3D:
		size = (owner_floor.collision_shape.shape as BoxShape3D).size
	else:
		size = Vector3(10, 0.5, 10)
	
	var local_dir = owner_floor.treadmill_direction
	if local_dir.length() < 0.01:
		local_dir = Vector3(1, 0, 0)
	local_dir = local_dir.normalized()
	
	var arrow_mat = StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(1.0, 0.75, 0.1)
	arrow_mat.emission_enabled = true
	arrow_mat.emission = Color(1.0, 0.7, 0.1)
	arrow_mat.emission_energy = 0.6
	
	var along = size.length() * 0.5
	var arrow_count = clampi(int(along / 2.0), 2, 6)
	for i in range(arrow_count):
		var t = (i + 0.5) / float(arrow_count) - 0.5   # -0.5..0.5 along the belt
		var arrow = MeshInstance3D.new()
		var prism = PrismMesh.new()
		prism.size = Vector3(0.7, 0.06, 0.7)
		arrow.mesh = prism
		arrow.material_override = arrow_mat
		owner_floor.add_child(arrow)
		# PrismMesh points +Y at its ridge; lay it flat pointing along the belt
		arrow.rotation_degrees = Vector3(-90, 0, 0)
		var yaw = atan2(-local_dir.x, -local_dir.z)
		arrow.rotation.y = yaw + PI
		arrow.position = local_dir * (t * along * 1.6) + Vector3(0, size.y * 0.5 + 0.04, 0)
