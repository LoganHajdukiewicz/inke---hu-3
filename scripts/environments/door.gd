@tool
extends StaticBody3D
class_name Door
## An interactable door. Walk up and press INTERACT (E) to open/close it.
## Unlocked by default - tick `locked` in the Inspector to require a Key
## with a matching key_id. Doorway markers can spawn these automatically
## (Doorway.has_door), or drop door.tscn into any opening by hand.

## Requires the matching key before it will open.
@export var locked: bool = false:
	set(v):
		locked = v
		_update_hint()
## Which Key opens this door (only used when locked).
@export var key_id: String = "key"
## Spend the key when unlocking (false = master key, reusable).
@export var consume_key: bool = true
## Door panel size. Default fits the Rooms' auto doorways (2.0 x 2.8).
@export var door_size: Vector3 = Vector3(2.0, 2.8, 0.15):
	set(v): door_size = v; _rebuild()
@export var door_color: Color = Color(0.4, 0.26, 0.15):
	set(v): door_color = v; _rebuild()
## Lock/handle accent color - match the Key's color for readability.
@export var lock_color: Color = Color(1.0, 0.82, 0.25):
	set(v): lock_color = v; _rebuild()
## How the door opens.
@export_enum("Slide Up", "Slide Down", "Swing", "Vanish") var open_style: int = 2
## Can the door be closed again with another interact?
@export var reclosable: bool = true

var is_open := false
var _animating := false
var _player_near: Node3D = null
var _panel_pivot: Node3D
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
	box.size = door_size + Vector3(1.6, 0.4, 3.0)   # Generous interact zone
	cs.shape = box
	cs.position = Vector3(0, door_size.y * 0.5, 0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _rebuild():
	if not is_inside_tree():
		return
	for c in [_panel_pivot, _lock_bits, _collision, _hint]:
		if c and is_instance_valid(c):
			c.free()
	
	# Panel hangs off a hinge pivot at its edge so Swing mode rotates
	# around the jamb like a real door.
	_panel_pivot = Node3D.new()
	_panel_pivot.position = Vector3(-door_size.x * 0.5, 0, 0)
	add_child(_panel_pivot)
	
	_panel = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = door_size
	_panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = door_color
	mat.roughness = 0.85
	_panel.material_override = mat
	_panel.position = Vector3(door_size.x * 0.5, door_size.y * 0.5, 0)
	_panel_pivot.add_child(_panel)
	
	# Handle + (when locked) keyhole glow
	_lock_bits = Node3D.new()
	_panel_pivot.add_child(_lock_bits)
	var lock_mat := StandardMaterial3D.new()
	lock_mat.albedo_color = lock_color
	lock_mat.metallic = 0.6
	lock_mat.roughness = 0.35
	lock_mat.emission_enabled = true
	lock_mat.emission = lock_color * 0.6
	var handle := MeshInstance3D.new()
	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.12
	handle_mesh.bottom_radius = 0.12
	handle_mesh.height = door_size.z + 0.08
	handle.mesh = handle_mesh
	handle.material_override = lock_mat
	handle.rotation_degrees.x = 90.0
	handle.position = Vector3(door_size.x * 0.78, door_size.y * 0.5, 0)
	_lock_bits.add_child(handle)
	
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = door_size
	_collision.shape = shape
	_collision.position = Vector3(0, door_size.y * 0.5, 0)
	add_child(_collision)
	
	_hint = Label3D.new()
	_hint.font_size = 40
	_hint.outline_size = 10
	_hint.pixel_size = 0.005
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.position = Vector3(0, door_size.y + 0.35, 0)
	_hint.visible = false
	add_child(_hint)
	_update_hint()


func _update_hint():
	if _hint == null or not is_instance_valid(_hint):
		return
	if locked:
		_hint.text = "Locked"
		_hint.modulate = lock_color
	else:
		_hint.text = "[E] Open" if not is_open else "[E] Close"
		_hint.modulate = Color(0.9, 0.9, 0.9)


func _process(_delta):
	if Engine.is_editor_hint():
		return
	if _player_near and not _animating and Input.is_action_just_pressed("interact"):
		_try_use()


func _try_use():
	if is_open:
		if reclosable:
			_close()
		return
	if locked:
		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.has_method("has_key") and gm.has_key(key_id):
			if consume_key:
				gm.use_key(key_id)
			locked = false
			_open()
		else:
			_shake_hint()
	else:
		_open()


func _on_body_entered(body: Node3D):
	if body.is_in_group("Player"):
		_player_near = body
		_hint.visible = true
		_update_hint()


func _on_body_exited(body: Node3D):
	if body == _player_near:
		_player_near = null
		_hint.visible = false


func _open():
	is_open = true
	_animating = true
	_collision.set_deferred("disabled", true)
	var tween := create_tween()
	match open_style:
		0:   # Slide up
			tween.tween_property(_panel_pivot, "position:y", door_size.y + 0.15, 0.5)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		1:   # Slide down
			tween.tween_property(_panel_pivot, "position:y", -door_size.y - 0.05, 0.5)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		2:   # Swing on the hinge
			tween.tween_property(_panel_pivot, "rotation:y", deg_to_rad(105.0), 0.45)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		3:   # Vanish
			tween.tween_property(_panel_pivot, "scale", Vector3(1.0, 0.02, 1.0), 0.3)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		_animating = false
		if open_style == 3:
			_panel_pivot.visible = false
		_update_hint()
	)


func _close():
	is_open = false
	_animating = true
	_panel_pivot.visible = true
	var tween := create_tween()
	match open_style:
		0, 1:
			tween.tween_property(_panel_pivot, "position:y", 0.0, 0.4)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		2:
			tween.tween_property(_panel_pivot, "rotation:y", 0.0, 0.4)\
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		3:
			tween.tween_property(_panel_pivot, "scale", Vector3.ONE, 0.25)
	tween.tween_callback(func():
		_animating = false
		_collision.set_deferred("disabled", false)
		_update_hint()
	)


func _shake_hint():
	var tween := create_tween()
	for i in range(3):
		tween.tween_property(_hint, "position:x", 0.08, 0.05)
		tween.tween_property(_hint, "position:x", -0.08, 0.05)
	tween.tween_property(_hint, "position:x", 0.0, 0.05)
