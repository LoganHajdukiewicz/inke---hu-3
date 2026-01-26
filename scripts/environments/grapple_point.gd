extends Node3D
class_name GrapplePoint

# Visual configuration
@export var glow_color: Color = Color(0.0, 1.0, 0.8, 1.0)
@export var highlight_on_aim: bool = true
@export var detection_radius: float = 0.5

# Visual components
var visual_sphere: MeshInstance3D
var glow_material: StandardMaterial3D
var base_emission_energy: float = 2.0
var highlight_emission_energy: float = 4.0

func _ready():
	# Add to grapple point group
	add_to_group("GrapplePoint")
	
	# Create visual representation
	create_visual()
	
	# Setup detection area for highlighting
	if highlight_on_aim:
		setup_detection_area()

func create_visual():
	"""Create a glowing sphere to indicate grapple point"""
	visual_sphere = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.3
	sphere_mesh.height = 0.6
	visual_sphere.mesh = sphere_mesh
	
	# Create glowing material
	glow_material = StandardMaterial3D.new()
	glow_material.albedo_color = glow_color
	glow_material.emission_enabled = true
	glow_material.emission = glow_color
	glow_material.emission_energy_multiplier = base_emission_energy
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	visual_sphere.material_override = glow_material
	add_child(visual_sphere)
	
	# Add subtle rotation animation
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(visual_sphere, "rotation:y", TAU, 3.0)

func setup_detection_area():
	"""Setup area for detecting when player is aiming at this point"""
	var detection_area = Area3D.new()
	detection_area.name = "DetectionArea"
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = detection_radius
	collision_shape.shape = sphere_shape
	
	detection_area.add_child(collision_shape)
	add_child(detection_area)

func highlight():
	"""Highlight this grapple point when player aims at it"""
	if glow_material:
		glow_material.emission_energy_multiplier = highlight_emission_energy

func unhighlight():
	"""Remove highlight"""
	if glow_material:
		glow_material.emission_energy_multiplier = base_emission_energy

func get_grapple_position() -> Vector3:
	"""Return the exact position to grapple to"""
	return global_position
