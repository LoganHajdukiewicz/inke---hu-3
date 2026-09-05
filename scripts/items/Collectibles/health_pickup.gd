@tool
extends Area3D
class_name HealthPickup
## A floating heart that restores health on touch. Skipped (not consumed)
## if the player is already at full health - walk back over it later.

@export var heal_amount: int = 1
@export var heart_color: Color = Color(0.95, 0.2, 0.35):
	set(v):
		heart_color = v
		if _model: _build_model()
@export var bob_height: float = 0.25
@export var spin_speed: float = 2.0

var _model: Node3D
var _base_y: float = 0.0
var _time: float = 0.0
var collected := false

func _ready():
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	shape.shape = sphere
	add_child(shape)
	_build_model()
	_base_y = _model.position.y
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func _build_model():
	if _model and is_instance_valid(_model):
		_model.free()
	_model = Node3D.new()
	_model.name = "HeartModel"
	add_child(_model)
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = heart_color
	mat.emission_enabled = true
	mat.emission = heart_color
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.35
	
	# Heart = two spheres + a rotated box point
	for s in [-1.0, 1.0]:
		var lobe := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		lobe.mesh = sm
		lobe.material_override = mat
		lobe.position = Vector3(s * 0.16, 0.12, 0)
		_model.add_child(lobe)
	var point := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.44, 0.44, 0.32)
	point.mesh = bm
	point.material_override = mat
	point.rotation.z = PI / 4.0
	point.position = Vector3(0, -0.02, 0)
	_model.add_child(point)
	
	# Soft glow
	var light := OmniLight3D.new()
	light.light_color = heart_color
	light.light_energy = 0.7
	light.omni_range = 2.5
	light.shadow_enabled = false
	_model.add_child(light)

func _process(delta: float):
	if not _model:
		return
	_time += delta
	_model.rotation.y += spin_speed * delta
	_model.position.y = _base_y + sin(_time * 2.0) * bob_height

func _on_body_entered(body: Node3D):
	if collected or not body.is_in_group("Player"):
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return
	# Full HP? Leave the heart for later.
	if gm.get_player_health() >= gm.get_player_max_health():
		return
	collected = true
	gm.heal_player(heal_amount)
	Sfx.play_3d(self, Sfx.stomp_bounce(), global_position, -8.0, 1.6)
	# Pop: scale up + rise + fade the light, then free.
	# (Never scale to ZERO - singular transform = det==0 renderer errors.)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_model, "scale", Vector3.ONE * 1.5, 0.12)
	tw.tween_property(_model, "position:y", _model.position.y + 1.2, 0.3)
	tw.chain().tween_property(_model, "scale", Vector3.ONE * 0.05, 0.15)
	tw.chain().tween_callback(func(): _model.visible = false)
	tw.chain().tween_callback(queue_free)
