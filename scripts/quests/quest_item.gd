class_name QuestItem
extends Area3D

## A grab-and-return item for FETCH_ITEM quests. Touch it and it goes into
## Inke's "hands" (QuestManager.carried_items) - then return to the quest
## giver to turn it in.
## Set item_id to match the quest's target_id.

@export var item_id: String = ""
@export var item_color: Color = Color(1.0, 0.4, 0.75)
@export var float_amplitude: float = 0.18
@export var float_speed: float = 2.0
@export var spin_speed: float = 1.5
## If true the item only becomes visible/grabbable while its fetch quest is
## active. If false it can be grabbed early (quest completes on turn-in).
@export var only_during_quest: bool = false

var _time: float = 0.0
var _base_y: float = 0.0
var _grabbed: bool = false
var _mesh_root: Node3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	set_deferred("monitorable", false)
	add_to_group("QuestItem")
	body_entered.connect(_on_body_entered)
	_base_y = global_position.y
	_build_visual()
	
	if only_during_quest:
		visible = false
		set_deferred("monitoring", false)
		var qm = get_node_or_null("/root/QuestManager")
		if qm:
			qm.quest_accepted.connect(_on_quest_accepted)


func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	
	# A glowing gem (prism) with a ring base so it reads as "special pickup"
	var gem = MeshInstance3D.new()
	var prism = PrismMesh.new()
	prism.size = Vector3(0.55, 0.7, 0.55)
	gem.mesh = prism
	var mat = StandardMaterial3D.new()
	mat.albedo_color = item_color
	mat.emission_enabled = true
	mat.emission = item_color
	mat.emission_energy_multiplier = 1.2
	mat.metallic = 0.6
	mat.roughness = 0.2
	gem.material_override = mat
	gem.position.y = 0.55
	_mesh_root.add_child(gem)
	
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.35
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.material_override = mat
	ring.position.y = 0.1
	_mesh_root.add_child(ring)
	
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 0.9
	col.shape = sph
	col.position.y = 0.5
	add_child(col)


func _process(delta: float) -> void:
	if _grabbed:
		return
	_time += delta
	global_position.y = _base_y + sin(_time * float_speed) * float_amplitude
	if _mesh_root:
		_mesh_root.rotation.y += spin_speed * delta


func _on_quest_accepted(quest: Quest) -> void:
	if quest.quest_type == "fetch_item" and quest.target_id == item_id:
		visible = true
		set_deferred("monitoring", true)


func _on_body_entered(body: Node3D) -> void:
	if _grabbed or not body.is_in_group("Player"):
		return
	if item_id == "":
		push_warning("QuestItem at %s has no item_id" % str(global_position))
		return
	_grabbed = true
	
	var qm = get_node_or_null("/root/QuestManager")
	if qm:
		qm.notify_item_grabbed(item_id)
	
	# Zip up into the player's "hands" and vanish
	set_deferred("monitoring", false)
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(self, "global_position", body.global_position + Vector3(0, 1.5, 0), 0.3).set_ease(Tween.EASE_IN)
	t.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.3).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(queue_free)
