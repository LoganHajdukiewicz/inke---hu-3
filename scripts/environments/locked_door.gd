@tool
extends StaticBody3D
class_name LockedDoor
## A door that blocks a doorway until the player brings the right Key.
## Drop it into any opening (Room doorways, corridors...). When the player
## touches it while holding the matching key, it unlocks and slides open.
## Without the key it stays shut and shows a hint.

## Must match the key_id of the Key that opens this door.
@export var key_id: String = "key"
## Spend the key when opening (false = master key, reusable).
@export var consume_key: bool = true
## Door panel size. Default fits the Rooms' auto doorways (2.0 x 2.8).
@export var door_size: Vector3 = Vector3(2.0, 2.8, 0.15):
	set(v): door_size = v; _rebuild()
@export var door_color: Color = Color(0.4, 0.26, 0.15):
	set(v): door_color = v; _rebuild()
## Lock/keyhole accent color - match the Key's color for readability.
@export var lock_color: Color = Color(1.0, 0.82, 0.25):
	set(v): lock_color = v; _rebuild()
## How the door opens once unlocked.
@export_enum("Slide Up", "Slide Down", "Vanish") var open_style: int = 0

var locked := true
var _panel: MeshInstance3D
var _lock_bits: Node3D
var _collision: CollisionShape3D
var _hint: Label3D


func _ready():
	_rebuild()
	if Engine.is_editor_hint():
		return
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = door_size + Vector3(1.0, 0.4, 2.0)   # Generous touch zone
	cs.shape = box
	cs.position = Vector3(0, door_size.y * 0.5, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_near)


func _rebuild():
	if not is_inside_tree():
		return
	for c in [_panel, _lock_bits, _collision, _hint]:
		if c and is_instance_valid(c):
			c.free()
	
	_panel = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = door_size
	_panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = door_color
	mat.roughness = 0.85
	_panel.material_override = mat
	_panel.position = Vector3(0, door_size.y * 0.5, 0)
	add_child(_panel)
	
	# Lock plate + keyhole glow
	_lock_bits = Node3D.new()
	add_child(_lock_bits)
	var lock_mat := StandardMaterial3D.new()
	lock_mat.albedo_color = lock_color
	lock_mat.metallic = 0.6
	lock_mat.roughness = 0.35
	lock_mat.emission_enabled = true
	lock_mat.emission = lock_color * 0.6
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.16
	plate_mesh.bottom_radius = 0.16
	plate_mesh.height = door_size.z + 0.04
	plate.mesh = plate_mesh
	plate.material_override = lock_mat
	plate.rotation_degrees.x = 90.0
	plate.position = Vector3(door_size.x * 0.28, door_size.y * 0.5, 0)
	_lock_bits.add_child(plate)
	
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = door_size
	_collision.shape = shape
	_collision.position = Vector3(0, door_size.y * 0.5, 0)
	add_child(_collision)
	
	_hint = Label3D.new()
	_hint.text = "Locked"
	_hint.font_size = 40
	_hint.outline_size = 10
	_hint.pixel_size = 0.005
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.modulate = lock_color
	_hint.position = Vector3(0, door_size.y + 0.35, 0)
	add_child(_hint)


func _on_body_near(body: Node3D):
	if not locked or Engine.is_editor_hint():
		return
	if not body.is_in_group("Player"):
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm == null or not gm.has_method("has_key"):
		return
	if gm.has_key(key_id):
		if consume_key:
			gm.use_key(key_id)
		_open()
	else:
		_shake_hint()


func _open():
	locked = false
	_hint.text = "Unlocked!"
	_collision.set_deferred("disabled", true)
	var tween := create_tween()
	match open_style:
		0:   # Slide up
			tween.tween_property(_panel, "position:y", door_size.y * 1.5 + 0.2, 0.6)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(_lock_bits, "position:y", door_size.y + 0.2, 0.6)
		1:   # Slide down
			tween.tween_property(_panel, "position:y", -door_size.y * 0.55, 0.6)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(_lock_bits, "position:y", -door_size.y * 0.9, 0.6)
		2:   # Vanish
			tween.tween_property(_panel, "scale", Vector3(1.0, 0.02, 1.0), 0.35)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(_lock_bits, "scale", Vector3.ZERO, 0.3)
	tween.tween_callback(func():
		if open_style == 2:
			_panel.visible = false
			_lock_bits.visible = false
	)
	var fade := create_tween()
	fade.tween_interval(1.2)
	fade.tween_property(_hint, "modulate:a", 0.0, 0.8)


func _shake_hint():
	var tween := create_tween()
	for i in range(3):
		tween.tween_property(_hint, "position:x", 0.08, 0.05)
		tween.tween_property(_hint, "position:x", -0.08, 0.05)
	tween.tween_property(_hint, "position:x", 0.0, 0.05)
