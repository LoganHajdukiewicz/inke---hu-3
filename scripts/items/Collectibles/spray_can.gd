extends Area3D
class_name SprayCan

## SPRAY CAN - scout-fly style collectable (think Jak & Daxter), formerly
## "Ink Wisp". A real object now: a spray paint can with a colored cap,
## label band and nozzle, slowly spinning with a soft glow.
## Collect EVERY can in a level and a CRED appears in front of you.
## Registration/counting is handled by GameManager per level.

@export var bob_amplitude: float = 0.25
@export var bob_speed: float = 2.0
@export var spin_speed: float = 2.5
## Cap + label + glow color (the paint color inside the can).
@export var paint_color: Color = Color(0.45, 0.75, 1.0)
## Metal body color.
@export var body_color: Color = Color(0.82, 0.84, 0.88)

var time_elapsed: float = 0.0
var start_position: Vector3
var collected: bool = false
var model: Node3D = null
var light: OmniLight3D = null

signal wisp_collected(wisp: SprayCan)

func _ready():
	add_to_group("SprayCan")
	add_to_group("InkWisp")        # legacy group, kept for old lookups
	add_to_group("Collectible")
	
	# Don't push the player around
	collision_layer = 0
	collision_mask = 1
	set_deferred("monitorable", false)  # Deferred: avoids flushing-queries errors
	monitoring = true
	
	start_position = global_position
	
	_build_visual()
	
	body_entered.connect(_on_body_entered)
	
	# Register with the level tracker
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("register_wisp"):
		gm.register_wisp(self)

func _build_visual():
	"""Build the spray can model: body, cap, label band, rim, nozzle."""
	# Drop any old placeholder mesh from the scene file
	var old = get_node_or_null("MeshInstance3D")
	if old:
		old.queue_free()
	
	model = Node3D.new()
	model.name = "CanModel"
	add_child(model)
	
	var metal := StandardMaterial3D.new()
	metal.albedo_color = body_color
	metal.metallic = 0.85
	metal.roughness = 0.35
	
	var paint := StandardMaterial3D.new()
	paint.albedo_color = paint_color
	paint.emission_enabled = true
	paint.emission = paint_color
	paint.emission_energy_multiplier = 0.9
	
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.18, 0.18, 0.2)
	dark.roughness = 0.6
	
	# Body: metal cylinder
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.13
	body_mesh.bottom_radius = 0.13
	body_mesh.height = 0.42
	body.mesh = body_mesh
	body.material_override = metal
	body.position = Vector3(0, 0.21, 0)
	model.add_child(body)
	
	# Label band: paint-colored wrap around the middle
	var label := MeshInstance3D.new()
	var label_mesh := CylinderMesh.new()
	label_mesh.top_radius = 0.132
	label_mesh.bottom_radius = 0.132
	label_mesh.height = 0.16
	label.mesh = label_mesh
	label.material_override = paint
	label.position = Vector3(0, 0.20, 0)
	model.add_child(label)
	
	# Shoulder rim (top taper)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.085
	rim_mesh.bottom_radius = 0.13
	rim_mesh.height = 0.06
	rim.mesh = rim_mesh
	rim.material_override = metal
	rim.position = Vector3(0, 0.45, 0)
	model.add_child(rim)
	
	# Cap: paint-colored dome
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.08
	cap_mesh.bottom_radius = 0.085
	cap_mesh.height = 0.10
	cap.mesh = cap_mesh
	cap.material_override = paint
	cap.position = Vector3(0, 0.53, 0)
	model.add_child(cap)
	
	# Nozzle: little dark button with a tilt
	var nozzle := MeshInstance3D.new()
	var noz_mesh := CylinderMesh.new()
	noz_mesh.top_radius = 0.025
	noz_mesh.bottom_radius = 0.03
	noz_mesh.height = 0.05
	nozzle.mesh = noz_mesh
	nozzle.material_override = dark
	nozzle.position = Vector3(0, 0.605, 0)
	model.add_child(nozzle)
	
	# Bottom rim
	var foot := MeshInstance3D.new()
	var foot_mesh := CylinderMesh.new()
	foot_mesh.top_radius = 0.13
	foot_mesh.bottom_radius = 0.12
	foot_mesh.height = 0.03
	foot.mesh = foot_mesh
	foot.material_override = dark
	foot.position = Vector3(0, -0.005, 0)
	model.add_child(foot)
	
	# Slight jaunty tilt so it reads as floating loot, not a standing can
	model.rotation_degrees = Vector3(8, 0, -10)
	
	# Ensure we have a collision shape even if scene didn't provide one
	if not get_node_or_null("CollisionShape3D"):
		var cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var shape = SphereShape3D.new()
		shape.radius = 0.8  # generous pickup radius
		cs.shape = shape
		add_child(cs)
	
	light = OmniLight3D.new()
	light.light_color = paint_color
	light.omni_range = 3.0
	light.light_energy = 1.0
	light.position = Vector3(0, 0.3, 0)
	add_child(light)

func _process(delta: float):
	if collected:
		return
	time_elapsed += delta
	global_position.y = start_position.y + sin(time_elapsed * bob_speed) * bob_amplitude
	if model:
		model.rotation.y += spin_speed * delta

func _on_body_entered(body: Node3D):
	if collected or not body.is_in_group("Player"):
		return
	collected = true
	wisp_collected.emit(self)
	
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("collect_wisp"):
		gm.collect_wisp(self)
	
	_play_collect_effect()

func _play_collect_effect():
	"""Pop up with a paint-burst, shrink, and vanish"""
	set_deferred("monitoring", false)
	# Quick spray burst: a few paint-colored particles
	var burst := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color = paint_color
	burst.process_material = pm
	var bm := SphereMesh.new()
	bm.radius = 0.045
	bm.height = 0.09
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = paint_color
	bmat.emission_enabled = true
	bmat.emission = paint_color
	bm.material = bmat
	burst.draw_pass_1 = bm
	burst.amount = 24
	burst.lifetime = 0.5
	burst.one_shot = true
	burst.emitting = true
	add_child(burst)
	burst.position = Vector3(0, 0.5, 0)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", global_position + Vector3(0, 1.2, 0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if model:
		tween.tween_property(model, "scale", Vector3(0.05, 0.05, 0.05), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if light:
		tween.tween_property(light, "light_energy", 4.0, 0.15)
	tween.chain().tween_interval(0.4)
	tween.chain().tween_callback(queue_free)
