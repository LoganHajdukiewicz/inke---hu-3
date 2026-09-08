@tool
extends Marker3D
class_name BuoyPoint
## One buoy on a WaterZone's boundary line. DRAG THESE in the editor to
## shape shark territory however you want - the buoy ring IS the boundary.
## Child order around the WaterZone = ring order (generated buoys come
## pre-ordered; keep new ones between their neighbors in the scene tree).

var _vis: Node3D = null
var _phase := 0.0
var _time := 0.0


func _ready():
	_phase = randf() * TAU
	_build_visual()


func _build_visual():
	if _vis and is_instance_valid(_vis):
		_vis.queue_free()
	_vis = Node3D.new()
	add_child(_vis)
	
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	red.emission_enabled = true
	red.emission = Color(0.85, 0.1, 0.1)
	red.emission_energy_multiplier = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.18
	bm.bottom_radius = 0.32
	bm.height = 0.5
	bm.radial_segments = 6
	body.mesh = bm
	body.material_override = red
	_vis.add_child(body)
	
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.14
	band_mesh.bottom_radius = 0.18
	band_mesh.height = 0.22
	band_mesh.radial_segments = 6
	band.mesh = band_mesh
	band.material_override = white
	band.position.y = 0.36
	_vis.add_child(band)
	
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.12
	tip_mesh.height = 0.25
	tip_mesh.radial_segments = 6
	tip.mesh = tip_mesh
	tip.material_override = red
	tip.position.y = 0.58
	_vis.add_child(tip)
	
	_vis.scale = Vector3.ONE * 1.2   # Chunky enough to read from shore


func _process(delta: float):
	_time += delta
	if _vis and is_instance_valid(_vis):
		_vis.position.y = 0.05 + sin(_time * 1.6 + _phase) * 0.12
		_vis.rotation.z = sin(_time * 1.2 + _phase) * 0.08
