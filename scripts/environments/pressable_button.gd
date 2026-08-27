@tool
class_name PressableButton
extends StaticBody3D

## A physical button, placeable two ways (mount_mode):
##   GROUND - lies flat on the floor; pressed by landing/standing on it
##            (a jump onto it presses it).
##   WALL   - mounted on a wall; pressed by ANY player hit (punch, heavy
##            attack, dash strike... anything that deals damage).
##
## Wire "pressed" in the Inspector, or point it at an EnemySpawner with
## spawner_path for zero-code setups. label_text is printed on/above the
## button so players know what it does.

signal pressed
signal released   # GROUND only: fires when everyone steps off a non-latching button

enum MountMode { GROUND, WALL }

@export var mount_mode: MountMode = MountMode.GROUND:
	set(value):
		mount_mode = value
		if is_inside_tree():
			_rebuild()
## Stays pressed forever after the first press. Off = re-pressable
## (GROUND: pops back up when you step off; WALL: after press_cooldown).
@export var latching: bool = false
## Minimum time between presses for non-latching buttons.
@export var press_cooldown: float = 1.0
## Written on the button so players know what it does.
@export var label_text: String = "":
	set(value):
		label_text = value
		if is_inside_tree():
			_rebuild()
@export var button_color: Color = Color(0.9, 0.2, 0.2):
	set(value):
		button_color = value
		if is_inside_tree():
			_rebuild()
@export var button_radius: float = 0.8:
	set(value):
		button_radius = value
		if is_inside_tree():
			_rebuild()

@export_group("Connections")
## Optional: an EnemySpawner (or anything with a spawn()/activate() method)
## triggered automatically on press.
@export var spawner_path: NodePath

var is_pressed: bool = false
var _cooldown: float = 0.0
var _bodies_on_top: int = 0

var _cap_mesh: MeshInstance3D
var _cap_rest_pos: Vector3
var _press_area: Area3D
var _label: Label3D


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group("PressableButton")
		if mount_mode == MountMode.WALL:
			# Any player hit presses it: the attack manager damages things
			# in the "Breakables" group via take_damage()
			add_to_group("Breakables")


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0 and not latching and mount_mode == MountMode.WALL:
			_pop_out()


# =========================================================================
# PRESS PATHS
# =========================================================================

## WALL: called by attack_manager / slam on anything in "Breakables".
func take_damage(_amount: int = 1, _knockback: Vector3 = Vector3.ZERO) -> void:
	if mount_mode != MountMode.WALL:
		return
	_try_press()


func _on_press_area_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	_bodies_on_top += 1
	if mount_mode == MountMode.GROUND:
		_try_press()


func _on_press_area_body_exited(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	_bodies_on_top = maxi(0, _bodies_on_top - 1)
	if mount_mode == MountMode.GROUND and _bodies_on_top == 0 and is_pressed and not latching:
		_pop_out()
		released.emit()


func _try_press() -> void:
	if is_pressed and latching:
		return
	if _cooldown > 0.0:
		return
	if is_pressed and mount_mode == MountMode.GROUND:
		return
	
	is_pressed = true
	_cooldown = press_cooldown
	_animate_press()
	pressed.emit()
	
	# Auto-fire a connected spawner
	if spawner_path != NodePath(""):
		var spawner = get_node_or_null(spawner_path)
		if spawner:
			if spawner.has_method("spawn"):
				spawner.spawn()
			elif spawner.has_method("activate"):
				spawner.activate()


func _pop_out() -> void:
	if not is_pressed:
		return
	is_pressed = false
	if _cap_mesh:
		var t = create_tween()
		t.tween_property(_cap_mesh, "position", _cap_rest_pos, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _animate_press() -> void:
	if not _cap_mesh:
		return
	var pressed_pos = _cap_rest_pos
	if mount_mode == MountMode.GROUND:
		pressed_pos.y = _cap_rest_pos.y - 0.12
	else:
		pressed_pos.z = _cap_rest_pos.z + 0.14
	var t = create_tween()
	t.tween_property(_cap_mesh, "position", pressed_pos, 0.06)
	# Flash
	if _cap_mesh.material_override is StandardMaterial3D:
		var m: StandardMaterial3D = _cap_mesh.material_override
		m.emission_energy_multiplier = 2.2
		t.parallel().tween_property(m, "emission_energy_multiplier", 0.6, 0.5)


# =========================================================================
# GEOMETRY
# =========================================================================

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	
	var base_mat = StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.35, 0.35, 0.4)
	base_mat.metallic = 0.6
	base_mat.roughness = 0.4
	
	var cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = button_color
	cap_mat.emission_enabled = true
	cap_mat.emission = button_color
	cap_mat.emission_energy_multiplier = 0.6
	
	if mount_mode == MountMode.GROUND:
		# Base plate
		var base = MeshInstance3D.new()
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = button_radius * 1.3
		base_mesh.bottom_radius = button_radius * 1.3
		base_mesh.height = 0.15
		base.mesh = base_mesh
		base.material_override = base_mat
		base.position.y = 0.075
		add_child(base)
		
		# Pressable cap
		_cap_mesh = MeshInstance3D.new()
		var cap = CylinderMesh.new()
		cap.top_radius = button_radius
		cap.bottom_radius = button_radius
		cap.height = 0.22
		_cap_mesh.mesh = cap
		_cap_mesh.material_override = cap_mat
		_cap_mesh.position.y = 0.24
		_cap_rest_pos = _cap_mesh.position
		add_child(_cap_mesh)
		
		# Solid collision (stand on it)
		var col = CollisionShape3D.new()
		var cyl = CylinderShape3D.new()
		cyl.radius = button_radius * 1.3
		cyl.height = 0.35
		col.shape = cyl
		col.position.y = 0.175
		add_child(col)
		
		# Detection area just above the cap
		_press_area = Area3D.new()
		_press_area.collision_layer = 0
		_press_area.collision_mask = 1
		var acol = CollisionShape3D.new()
		var acyl = CylinderShape3D.new()
		acyl.radius = button_radius
		acyl.height = 0.8
		acol.shape = acyl
		acol.position.y = 0.6
		_press_area.add_child(acol)
		add_child(_press_area)
		if not Engine.is_editor_hint():
			_press_area.body_entered.connect(_on_press_area_body_entered)
			_press_area.body_exited.connect(_on_press_area_body_exited)
	else:
		# WALL: back plate + protruding cap facing +Z (rotate node to aim)
		var base = MeshInstance3D.new()
		var plate = BoxMesh.new()
		plate.size = Vector3(button_radius * 2.6, button_radius * 2.6, 0.15)
		base.mesh = plate
		base.material_override = base_mat
		base.position.z = 0.075
		add_child(base)
		
		_cap_mesh = MeshInstance3D.new()
		var cap = CylinderMesh.new()
		cap.top_radius = button_radius
		cap.bottom_radius = button_radius
		cap.height = 0.25
		_cap_mesh.mesh = cap
		_cap_mesh.material_override = cap_mat
		_cap_mesh.rotation_degrees.x = 90
		_cap_mesh.position.z = 0.27
		_cap_rest_pos = _cap_mesh.position
		add_child(_cap_mesh)
		
		var col = CollisionShape3D.new()
		var box = BoxShape3D.new()
		box.size = Vector3(button_radius * 2.6, button_radius * 2.6, 0.55)
		col.shape = box
		col.position.z = 0.27
		add_child(col)
	
	# Label
	if label_text != "":
		_label = Label3D.new()
		_label.text = label_text
		_label.font_size = 40
		_label.outline_size = 12
		_label.pixel_size = 0.01
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		if mount_mode == MountMode.GROUND:
			_label.position.y = 1.4
		else:
			_label.position = Vector3(0, button_radius * 1.9, 0.3)
		add_child(_label)
