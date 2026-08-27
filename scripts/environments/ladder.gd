extends ClimbableWall
class_name Ladder

## A ClimbableWall that only allows UP / DOWN movement - no left/right.
## The climbing state checks for the "Ladder" group and locks the
## horizontal axis. Visually built like an actual ladder: two side
## rails + rungs instead of a lattice slab.

func _ready():
	add_to_group("ClimbableWall")
	add_to_group("Ladder")
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	# Collision: thin box the size of the ladder
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = wall_size
	collision.shape = box
	add_child(collision)
	
	var rail_mat = StandardMaterial3D.new()
	rail_mat.albedo_color = wall_color
	rail_mat.roughness = 0.9
	
	var rung_mat = StandardMaterial3D.new()
	rung_mat.albedo_color = rung_color
	rung_mat.roughness = 0.8
	
	# Two vertical side rails
	for x_side in [1.0, -1.0]:
		var rail = MeshInstance3D.new()
		var rail_mesh = BoxMesh.new()
		rail_mesh.size = Vector3(0.14, wall_size.y, maxf(wall_size.z, 0.12))
		rail.mesh = rail_mesh
		rail.material_override = rail_mat
		rail.position = Vector3(x_side * (wall_size.x * 0.5 - 0.07), 0, 0)
		add_child(rail)
	
	# Rungs between the rails
	var rung_count = int(wall_size.y / rung_spacing)
	for i in range(rung_count):
		var y = -wall_size.y * 0.5 + rung_spacing * (i + 0.5)
		var rung = MeshInstance3D.new()
		var rung_mesh = CylinderMesh.new()
		rung_mesh.top_radius = 0.05
		rung_mesh.bottom_radius = 0.05
		rung_mesh.height = wall_size.x - 0.14
		rung.mesh = rung_mesh
		rung.material_override = rung_mat
		rung.rotation.z = PI / 2.0
		rung.position = Vector3(0, y, 0)
		add_child(rung)
