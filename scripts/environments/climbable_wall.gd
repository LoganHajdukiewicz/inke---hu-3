@tool
extends StaticBody3D
class_name ClimbableWall

## A wall the player can free-climb (up / down / left / right).
## Just being in the "ClimbableWall" group is what makes it climbable -
## this script only handles sizing and the lattice visual.
## @tool: the wall builds its mesh + collision in the EDITOR too, so you
## can see and place it like any other prop. Resize via wall_size.

@export var wall_size: Vector3 = Vector3(8, 6, 0.5):
	set(value):
		wall_size = value
		if is_inside_tree():
			_rebuild()

@export var wall_color: Color = Color(0.45, 0.33, 0.2)     # Wooden lattice brown
@export var rung_color: Color = Color(0.55, 0.42, 0.28)    # Lighter cross-slats
@export var rung_spacing: float = 0.75                     # Visual grip lines

func _ready():
	add_to_group("ClimbableWall")
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	# Collision
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = wall_size
	collision.shape = box
	add_child(collision)
	
	# Main slab
	var slab = MeshInstance3D.new()
	var slab_mesh = BoxMesh.new()
	slab_mesh.size = wall_size
	slab.mesh = slab_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = wall_color
	mat.roughness = 0.9
	slab.material_override = mat
	add_child(slab)
	
	# Horizontal grip slats on both faces so it reads as "climbable"
	var rung_mat = StandardMaterial3D.new()
	rung_mat.albedo_color = rung_color
	rung_mat.roughness = 0.8
	
	var rung_count = int(wall_size.y / rung_spacing)
	for i in range(rung_count):
		var y = -wall_size.y * 0.5 + rung_spacing * (i + 0.5)
		for side in [1.0, -1.0]:
			var rung = MeshInstance3D.new()
			var rung_mesh = BoxMesh.new()
			rung_mesh.size = Vector3(wall_size.x * 0.96, 0.1, 0.08)
			rung.mesh = rung_mesh
			rung.material_override = rung_mat
			rung.position = Vector3(0, y, side * (wall_size.z * 0.5 + 0.04))
			add_child(rung)
	
	# Vertical rails at the edges
	for x_side in [1.0, -1.0]:
		for z_side in [1.0, -1.0]:
			var rail = MeshInstance3D.new()
			var rail_mesh = BoxMesh.new()
			rail_mesh.size = Vector3(0.12, wall_size.y, 0.08)
			rail.mesh = rail_mesh
			rail.material_override = rung_mat
			rail.position = Vector3(x_side * wall_size.x * 0.47, 0, z_side * (wall_size.z * 0.5 + 0.04))
			add_child(rail)
