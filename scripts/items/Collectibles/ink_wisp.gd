extends Area3D
class_name InkWisp

## Scout-fly style collectable (think Jak & Daxter).
## Collect EVERY wisp in a level and a CRED appears 10 feet in front of you.
## Registration/counting is handled by GameManager per level.

@export var bob_amplitude: float = 0.25
@export var bob_speed: float = 2.0
@export var spin_speed: float = 2.5
@export var glow_color: Color = Color(0.45, 0.75, 1.0)

var time_elapsed: float = 0.0
var start_position: Vector3
var collected: bool = false
var mesh_instance: MeshInstance3D = null
var light: OmniLight3D = null

signal wisp_collected(wisp: InkWisp)

func _ready():
	add_to_group("InkWisp")
	add_to_group("Collectible")
	
	# Don't push the player around
	collision_layer = 0
	collision_mask = 1
	monitorable = false
	monitoring = true
	
	start_position = global_position
	
	_build_visual()
	
	body_entered.connect(_on_body_entered)
	
	# Register with the level tracker
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("register_wisp"):
		gm.register_wisp(self)

func _build_visual():
	"""Little glowing ink blob with a light"""
	mesh_instance = get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		var sphere = SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		mesh_instance.mesh = sphere
		add_child(mesh_instance)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = glow_color
	mat.emission_enabled = true
	mat.emission = glow_color
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat
	
	# Ensure we have a collision shape even if scene didn't provide one
	if not get_node_or_null("CollisionShape3D"):
		var cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var shape = SphereShape3D.new()
		shape.radius = 0.8  # generous pickup radius
		cs.shape = shape
		add_child(cs)
	
	light = OmniLight3D.new()
	light.light_color = glow_color
	light.omni_range = 3.0
	light.light_energy = 1.2
	add_child(light)

func _process(delta: float):
	if collected:
		return
	time_elapsed += delta
	global_position.y = start_position.y + sin(time_elapsed * bob_speed) * bob_amplitude
	if mesh_instance:
		mesh_instance.rotation.y += spin_speed * delta

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
	"""Pop up, shrink, and vanish"""
	set_deferred("monitoring", false)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", global_position + Vector3(0, 1.2, 0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	if light:
		tween.tween_property(light, "light_energy", 4.0, 0.15)
	tween.chain().tween_callback(queue_free)
