@tool
class_name LocationFlag
extends Area3D

## "The player has been here" trigger. Drop one anywhere (mountain peak,
## secret cave, top of a tower...), pick a shape, set a flag_id.
## When the player enters, QuestManager.set_location_flag(flag_id) is called
## - permanently recorded, queryable from anywhere, and REACH_LOCATION
## quests targeting that id complete instantly.
##
## Shape is fully configurable in the Inspector:
##   SQUARE  - flat box region (walk over it)          -> size.x / size.z, thin
##   CIRCLE  - flat cylinder region                    -> radius, thin
##   CUBE    - full 3D box volume                      -> size
##   SPHERE  - full 3D sphere volume                   -> radius
##   WALL    - tall thin box (cross a doorway/plane)   -> size.x wide, size.y tall, thin
##   CUSTOM  - use your own CollisionShape3D children; nothing is generated

enum FlagShape { SQUARE, CIRCLE, CUBE, SPHERE, WALL, CUSTOM }

## Unique id recorded when the player enters (e.g. "mountain_peak").
@export var flag_id: String = ""

@export var shape: FlagShape = FlagShape.CUBE:
	set(value):
		shape = value
		if is_inside_tree():
			_rebuild()
## Box dimensions for SQUARE (x/z), CUBE (all), WALL (x wide, y tall).
@export var size: Vector3 = Vector3(4, 4, 4):
	set(value):
		size = value
		if is_inside_tree():
			_rebuild()
## Radius for CIRCLE and SPHERE.
@export var radius: float = 3.0:
	set(value):
		radius = value
		if is_inside_tree():
			_rebuild()

@export_group("Feedback")
## Show a translucent preview of the trigger volume in-game (off = invisible).
@export var visible_in_game: bool = false
## Notification text when first entered. Empty = no notification.
@export var discovery_text: String = ""
## One-shot sparkle burst when the flag is first earned.
@export var celebrate: bool = true

var _triggered_this_session: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1  # player layer
	monitoring = true
	set_deferred("monitorable", false)
	_rebuild()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		add_to_group("LocationFlag")


func _rebuild() -> void:
	# Clear previously generated children (keep user-authored ones in CUSTOM)
	for child in get_children():
		if child.has_meta("_flag_generated"):
			child.queue_free()
	if shape == FlagShape.CUSTOM:
		return
	
	var col = CollisionShape3D.new()
	col.set_meta("_flag_generated", true)
	var mesh_shape: Mesh = null
	
	match shape:
		FlagShape.SQUARE:
			var box = BoxShape3D.new()
			box.size = Vector3(size.x, 1.0, size.z)
			col.shape = box
			col.position.y = 0.5
			var bm = BoxMesh.new()
			bm.size = box.size
			mesh_shape = bm
		FlagShape.CUBE:
			var box = BoxShape3D.new()
			box.size = size
			col.shape = box
			col.position.y = size.y * 0.5
			var bm = BoxMesh.new()
			bm.size = size
			mesh_shape = bm
		FlagShape.WALL:
			var box = BoxShape3D.new()
			box.size = Vector3(size.x, size.y, 0.5)
			col.shape = box
			col.position.y = size.y * 0.5
			var bm = BoxMesh.new()
			bm.size = box.size
			mesh_shape = bm
		FlagShape.CIRCLE:
			var cyl = CylinderShape3D.new()
			cyl.radius = radius
			cyl.height = 1.0
			col.shape = cyl
			col.position.y = 0.5
			var cm = CylinderMesh.new()
			cm.top_radius = radius
			cm.bottom_radius = radius
			cm.height = 1.0
			mesh_shape = cm
		FlagShape.SPHERE:
			var sph = SphereShape3D.new()
			sph.radius = radius
			col.shape = sph
			col.position.y = radius * 0.5
			var sm = SphereMesh.new()
			sm.radius = radius
			sm.height = radius * 2.0
			mesh_shape = sm
	
	add_child(col)
	
	# Translucent preview: always in editor, optional in game
	if Engine.is_editor_hint() or visible_in_game:
		var mi = MeshInstance3D.new()
		mi.set_meta("_flag_generated", true)
		mi.mesh = mesh_shape
		mi.position = col.position
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.9, 1.0, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		add_child(mi)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
	if flag_id == "":
		push_warning("LocationFlag at %s has no flag_id" % str(global_position))
		return
	
	var qm = get_node_or_null("/root/QuestManager")
	var first_time = qm and not qm.has_location_flag(flag_id)
	
	if qm:
		qm.set_location_flag(flag_id)
	
	if first_time and not _triggered_this_session:
		_triggered_this_session = true
		if discovery_text != "" and qm:
			qm.show_notification(discovery_text, Color(0.5, 1.0, 0.9))
		if celebrate:
			_sparkle(body)


func _sparkle(player: Node3D) -> void:
	var parent = get_parent()
	if not parent:
		return
	for i in range(10):
		var spark = MeshInstance3D.new()
		var s = SphereMesh.new()
		s.radius = 0.07
		s.height = 0.14
		spark.mesh = s
		var m = StandardMaterial3D.new()
		var col = Color.from_hsv(randf(), 0.7, 1.0)
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = m
		parent.add_child(spark)
		var angle = TAU * i / 10.0
		spark.global_position = player.global_position + Vector3(cos(angle) * 0.8, 0.3, sin(angle) * 0.8)
		var t = spark.create_tween()
		t.set_parallel(true)
		t.tween_property(spark, "global_position:y", spark.global_position.y + 2.5, 0.7).set_ease(Tween.EASE_OUT)
		t.tween_property(m, "albedo_color:a", 0.0, 0.7)
		t.chain().tween_callback(spark.queue_free)
