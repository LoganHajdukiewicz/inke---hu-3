@tool
class_name EnemySpawner
extends Node3D

## Spawns enemies on demand. Call spawn() - typically wired to a
## PressableButton (set the button's spawner_path to this node), but any
## script/signal can trigger it.
##
## Visual: a hatch-door pod. On spawn the door flips open, the enemy pops
## out with a launch arc toward spawn_direction, and the door shuts.

signal enemy_spawned(enemy: Node)

@export var enemy_scene: PackedScene
## Cosmetic name shown over the spawner (and usable on button labels).
@export var enemy_label: String = "":
	set(value):
		enemy_label = value
		if is_inside_tree():
			_rebuild()
## How many enemies each spawn() call produces.
@export var spawn_count: int = 1
## Max simultaneous alive enemies from this spawner (0 = unlimited).
@export var max_alive: int = 3
## Local direction the enemy is launched toward when spawned.
@export var spawn_direction: Vector3 = Vector3(0, 0, 2.5)
## Seconds between spawns when a single spawn() call spawns several.
@export var spawn_interval: float = 0.4
## Optional: quest hook - spawned enemies get this enemy_id.
@export var spawned_enemy_id: String = ""

var _alive: Array[Node] = []
var _door_pivot: Node3D
var _spawning: bool = false


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group("EnemySpawner")


## The button calls this (also answers to activate()).
func spawn() -> void:
	if Engine.is_editor_hint() or _spawning:
		return
	if not enemy_scene:
		push_warning("EnemySpawner '%s' has no enemy_scene" % name)
		return
	_spawning = true
	_do_spawn_batch()


func activate() -> void:
	spawn()


func alive_count() -> int:
	_alive = _alive.filter(func(e): return is_instance_valid(e))
	return _alive.size()


func _do_spawn_batch() -> void:
	for i in range(maxi(1, spawn_count)):
		if max_alive > 0 and alive_count() >= max_alive:
			break
		_spawn_one()
		if i < spawn_count - 1:
			await get_tree().create_timer(spawn_interval).timeout
			if not is_inside_tree():
				return
	_spawning = false


func _spawn_one() -> void:
	var enemy = enemy_scene.instantiate()
	var container = get_parent() if get_parent() else get_tree().current_scene
	container.add_child(enemy)
	
	var start = global_position + Vector3(0, 0.6, 0)
	if enemy is Node3D:
		enemy.global_position = start
	if "spawn_position" in enemy:
		enemy.spawn_position = start
	if spawned_enemy_id != "" and "enemy_id" in enemy:
		enemy.enemy_id = spawned_enemy_id
	
	_alive.append(enemy)
	
	# Hatch flip + launch arc
	_animate_door()
	var launch_target = global_position + global_transform.basis * spawn_direction
	launch_target.y = global_position.y
	if enemy is Node3D:
		var t = create_tween()
		t.set_parallel(true)
		t.tween_property(enemy, "global_position:x", launch_target.x, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(enemy, "global_position:z", launch_target.z, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var up = create_tween()
		up.tween_property(enemy, "global_position:y", start.y + 1.6, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		up.tween_property(enemy, "global_position:y", launch_target.y + 0.3, 0.23).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	enemy_spawned.emit(enemy)


func _animate_door() -> void:
	if not _door_pivot or not is_instance_valid(_door_pivot):
		return
	var t = create_tween()
	t.tween_property(_door_pivot, "rotation_degrees:x", -110.0, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.5)
	t.tween_property(_door_pivot, "rotation_degrees:x", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# =========================================================================
# GEOMETRY
# =========================================================================

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	
	var shell_mat = StandardMaterial3D.new()
	shell_mat.albedo_color = Color(0.3, 0.32, 0.38)
	shell_mat.metallic = 0.7
	shell_mat.roughness = 0.35
	
	var trim_mat = StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.9, 0.5, 0.1)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.9, 0.5, 0.1)
	trim_mat.emission_energy_multiplier = 0.7
	
	# Pod shell (open-topped box)
	var shell = MeshInstance3D.new()
	var shell_mesh = BoxMesh.new()
	shell_mesh.size = Vector3(2.0, 1.6, 2.0)
	shell.mesh = shell_mesh
	shell.material_override = shell_mat
	shell.position.y = 0.8
	add_child(shell)
	
	# Warning stripe ring
	var stripe = MeshInstance3D.new()
	var stripe_mesh = BoxMesh.new()
	stripe_mesh.size = Vector3(2.06, 0.22, 2.06)
	stripe.mesh = stripe_mesh
	stripe.material_override = trim_mat
	stripe.position.y = 1.35
	add_child(stripe)
	
	# Hatch door on top (hinged at the back edge via pivot offset)
	_door_pivot = Node3D.new()
	_door_pivot.position = Vector3(0, 1.62, -1.0)
	add_child(_door_pivot)
	var door = MeshInstance3D.new()
	var door_mesh = BoxMesh.new()
	door_mesh.size = Vector3(1.9, 0.1, 1.9)
	door.mesh = door_mesh
	door.material_override = trim_mat
	door.position.z = 0.95
	_door_pivot.add_child(door)
	
	# Solid body so it blocks movement
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2.0, 1.6, 2.0)
	col.shape = box
	col.position.y = 0.8
	body.add_child(col)
	add_child(body)
	
	# Label
	if enemy_label != "":
		var lbl = Label3D.new()
		lbl.text = enemy_label
		lbl.font_size = 40
		lbl.outline_size = 12
		lbl.pixel_size = 0.01
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position.y = 2.4
		add_child(lbl)
