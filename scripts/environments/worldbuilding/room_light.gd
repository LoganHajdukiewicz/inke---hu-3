@tool
extends Marker3D
class_name RoomLight
## A ceiling light inside a Room. Rooms spawn these automatically
## (Room.has_lights / Room.light_count) - drag them anywhere in the
## editor, they stay where you put them. You can also add extras by
## hand as children of any Room.

@export var light_color: Color = Color(1.0, 0.95, 0.85):
	set(v):
		light_color = v
		_apply()
@export var light_energy: float = 1.6:
	set(v):
		light_energy = v
		_apply()
@export var light_range: float = 24.0:
	set(v):
		light_range = v
		_apply()
## Cast shadows from this light (off = cheaper, usually fine indoors).
@export var light_shadows: bool = false:
	set(v):
		light_shadows = v
		_apply()

var _light: OmniLight3D
var _bulb_mat: StandardMaterial3D


func _ready():
	_build()


func _build():
	if _light and is_instance_valid(_light):
		return
	# Fixture: small base + glowing bulb hanging just below
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.16
	base_mesh.bottom_radius = 0.22
	base_mesh.height = 0.1
	base.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.25, 0.25, 0.28)
	base_mat.metallic = 0.5
	base.material_override = base_mat
	add_child(base)
	
	var bulb := MeshInstance3D.new()
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.14
	bulb_mesh.height = 0.28
	bulb.mesh = bulb_mesh
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb.material_override = _bulb_mat
	bulb.position.y = -0.16
	add_child(bulb)
	
	_light = OmniLight3D.new()
	_light.position.y = -0.3
	add_child(_light)
	_apply()


func _apply():
	if _light and is_instance_valid(_light):
		_light.light_color = light_color
		_light.light_energy = light_energy
		_light.omni_range = light_range
		_light.shadow_enabled = light_shadows
	if _bulb_mat:
		_bulb_mat.albedo_color = light_color
