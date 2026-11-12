@tool
extends StaticBody3D
class_name CredGate
## A glowing barrier that blocks a path until the player's lifetime CRED
## reaches cred_needed (CRED is only CHECKED, never spent). When it opens
## it plays an optional dialogue and fades away. Size it in the Inspector.

@export var cred_needed: int = 45
@export var size: Vector3 = Vector3(10, 6, 0.6):
	set(v): size = v; _rebuild()
@export var color: Color = Color(1.0, 0.25, 0.6, 0.55):
	set(v): color = v; _rebuild()
## Dialogue file (res://dialogue/<scene>/<name>.json) played when it opens.
@export var open_dialogue: String = ""
## Message shown when you touch it while locked.
@export var locked_text: String = "Need {cred} CRED"

var _mesh: MeshInstance3D
var _col: CollisionShape3D
var _label: Label3D
var _area: Area3D
var _open := false


func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.has_signal("cred_collected"):
		gm.cred_collected.connect(func(_a, _t): _check())
	_check.call_deferred()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _open or _label == null:
		return
	var gm = get_node_or_null("/root/GameManager")
	var have: int = gm.get_CRED_count() if gm else 0
	_label.text = "CRED  %d / %d" % [mini(have, cred_needed), cred_needed]


func _check() -> void:
	if _open:
		return
	var gm = get_node_or_null("/root/GameManager")
	if gm and gm.get_CRED_count() >= cred_needed:
		open_gate()


func open_gate() -> void:
	if _open:
		return
	_open = true
	if _col:
		_col.set_deferred("disabled", true)
	if open_dialogue != "" and DialogueManager:
		DialogueManager.start_dialogue(open_dialogue, null, true)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _on_touch(body: Node3D) -> void:
	if _open or not body.is_in_group("Player"):
		return
	var qm = get_node_or_null("/root/QuestManager")
	if qm and qm.has_method("show_notification"):
		qm.show_notification(locked_text.replace("{cred}", str(cred_needed)), Color(1, 0.5, 0.8))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new(); _mesh.name = "_Mesh"; add_child(_mesh)
		_col = CollisionShape3D.new(); _col.name = "_Col"; add_child(_col)
		_label = Label3D.new(); _label.name = "_Label"; add_child(_label)
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 96
		_label.outline_size = 18
		_area = Area3D.new(); _area.name = "_Touch"; add_child(_area)
		var ac := CollisionShape3D.new(); _area.add_child(ac)
		if not Engine.is_editor_hint():
			_area.body_entered.connect(_on_touch)
	var bm := BoxMesh.new(); bm.size = size
	_mesh.mesh = bm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = Color(color.r, color.g, color.b)
	m.emission_energy_multiplier = 1.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	var bs := BoxShape3D.new(); bs.size = size
	_col.shape = bs
	_col.position = Vector3.ZERO
	var as_ := BoxShape3D.new(); as_.size = size + Vector3(1.5, 0, 1.5)
	(_area.get_child(0) as CollisionShape3D).shape = as_
	_label.position = Vector3(0, size.y * 0.5 + 1.0, 0)
	_label.text = "CRED  0 / %d" % cred_needed
	_label.modulate = Color(1, 0.85, 0.95)
