extends StaticBody3D
class_name BalanceBeam

## A narrow beam the player must carefully WALK across.
## Standing on it slows the player 20% and swings the camera behind them.
## Running on it makes them lose their footing.

@export var beam_length: float = 10.0:
	set(value):
		beam_length = value
		if is_inside_tree():
			_rebuild()
@export var beam_width: float = 0.4
@export var beam_height: float = 0.25
@export var beam_color: Color = Color(0.55, 0.4, 0.22)

func _ready():
	add_to_group("BalanceBeam")
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(beam_width, beam_height, beam_length)
	collision.shape = box
	add_child(collision)
	
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(beam_width, beam_height, beam_length)
	mesh_instance.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = beam_color
	mat.roughness = 0.85
	mesh_instance.material_override = mat
	add_child(mesh_instance)
	
	# End caps so the mounting points read clearly
	for z_side in [1.0, -1.0]:
		var cap = MeshInstance3D.new()
		var cap_mesh = BoxMesh.new()
		cap_mesh.size = Vector3(beam_width * 2.0, beam_height * 1.2, 0.35)
		cap.mesh = cap_mesh
		var cap_mat = StandardMaterial3D.new()
		cap_mat.albedo_color = beam_color.darkened(0.3)
		cap.material_override = cap_mat
		cap.position = Vector3(0, 0, z_side * (beam_length * 0.5 - 0.175))
		add_child(cap)
