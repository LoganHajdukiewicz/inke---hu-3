@tool
extends Area3D
class_name Key
## A collectable key. Place it ANYWHERE in the world - on a shelf, at the
## end of a platforming run, or as the loot of a GroundPoundMound (set the
## mound's collectable_scene to key.tscn). Opens locked Doors that share
## its key_id.

## Which locks this opens. A locked Door with the same id unlocks.
@export var key_id: String = "key"
## Key color (also tints the pickup flash). Match the door for readability.
@export var key_color: Color = Color(1.0, 0.82, 0.25):
	set(v):
		key_color = v
		_apply_color()
@export var bob_height: float = 0.15
@export var spin_speed: float = 2.0

var collected := false
var pickup_locked := false
var hu3_locked := true      # HU-3 never steals keys - they're for the player
var is_scattering := false
var _base_y := 0.0
var _time := 0.0
var _model: Node3D
var _mat: StandardMaterial3D


func _ready():
	_build_visual()
	if Engine.is_editor_hint():
		return
	add_to_group("Collectible")
	add_to_group("Key")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_base_y = position.y


func _build_visual():
	if _model and is_instance_valid(_model):
		_model.free()
	_model = Node3D.new()
	add_child(_model)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = key_color
	_mat.metallic = 0.7
	_mat.roughness = 0.3
	_mat.emission_enabled = true
	_mat.emission = key_color * 0.5
	_mat.emission_energy_multiplier = 0.8
	
	# Ring (bow) of the key
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.09
	torus.outer_radius = 0.17
	ring.mesh = torus
	ring.material_override = _mat
	ring.rotation_degrees.x = 90.0
	ring.position.y = 0.42
	_model.add_child(ring)
	
	# Shaft
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.035
	cyl.height = 0.5
	shaft.mesh = cyl
	shaft.material_override = _mat
	shaft.position.y = 0.13
	_model.add_child(shaft)
	
	# Teeth
	for i in range(2):
		var tooth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.14, 0.05, 0.05)
		tooth.mesh = box
		tooth.material_override = _mat
		tooth.position = Vector3(0.08, -0.05 + i * 0.11, 0)
		_model.add_child(tooth)


func _apply_color():
	if _mat:
		_mat.albedo_color = key_color
		_mat.emission = key_color * 0.5


func _process(delta: float):
	if Engine.is_editor_hint() or collected:
		return
	_time += delta
	_model.rotation.y += spin_speed * delta
	if not is_scattering:
		position.y = _base_y + sin(_time * 2.0) * bob_height


# --- Same loot API as gears, so GroundPoundMounds can pop keys out ------

func lock_pickup(duration: float) -> void:
	pickup_locked = true
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(self):
			pickup_locked = false
	)


func lock_hu3_pickup(_duration: float) -> void:
	pass   # hu3_locked stays true forever - keys are player-only


func scatter_arc(target: Vector3, duration: float, arc_height: float = 2.0) -> void:
	is_scattering = true
	var start := global_position
	var peak := (start + target) * 0.5 + Vector3(0, arc_height, 0)
	var tween := create_tween()
	tween.tween_property(self, "global_position", peak, duration * 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target, duration * 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		is_scattering = false
		_base_y = position.y
	)


func scatter_to(target: Vector3, duration: float) -> void:
	is_scattering = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target, duration)
	tween.tween_callback(func():
		is_scattering = false
		_base_y = position.y
	)


# --- Pickup --------------------------------------------------------------

func _on_body_entered(body: Node3D):
	if collected or pickup_locked:
		return
	if not body.is_in_group("Player"):
		return
	collected = true
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("collect_key"):
		gm.collect_key(key_id)
	# Pickup flash: scale pop + rise, then gone
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_model, "scale", Vector3.ONE * 1.6, 0.12)
	tween.tween_property(self, "position:y", position.y + 1.0, 0.3)
	tween.chain().tween_property(_model, "scale", Vector3.ZERO, 0.15)
	tween.chain().tween_callback(queue_free)
