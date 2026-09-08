@tool
extends Node3D
class_name Boat
## A wooden boat, usually parked at the end of a Dock. Two modes:
##
##   ACTIVE OFF (default): scenery. A motionless boat bobbing at its
##     mooring. You can stand on it, nothing happens.
##
##   ACTIVE ON: a FERRY between two hub worlds. Walk aboard and press
##     INTERACT: a mini-cutscene plays (the boat pulls away from shore),
##     then the destination scene loads. Destinations are configurable in
##     the Inspector: Area A and Area B (scene paths). Which one you sail
##     to is chosen by `sail_to` - so place one boat in each world, point
##     them at each other, and you have a two-way ferry line with NO
##     obvious loading screen: the sail-away cutscene IS the transition.
##
## Jak & Daxter rule: the player never sees a bare loading screen - the
## boat ride covers the load.

## OFF = motionless scenery boat. ON = ferry (interact to sail).
@export var active: bool = false:
	set(v):
		active = v
		_refresh_prompt_visibility()
## Destination Area A (scene file).
@export_file("*.tscn") var area_a: String = ""
## Destination Area B (scene file).
@export_file("*.tscn") var area_b: String = ""
## Which destination THIS boat sails to when used.
@export_enum("Area A", "Area B") var sail_to: int = 0
## Seconds of sail-away cutscene before the destination loads.
@export var cutscene_duration: float = 3.5
## Boat length in meters.
@export var boat_length: float = 6.0:
	set(v): boat_length = maxf(v, 3.0); _request_rebuild()
@export var hull_color: Color = Color(0.4, 0.28, 0.18):
	set(v): hull_color = v; _request_rebuild()
@export var trim_color: Color = Color(0.65, 0.5, 0.3):
	set(v): trim_color = v; _request_rebuild()

var _built: Node3D = null
var _body: AnimatableBody3D = null
var _area: Area3D = null
var _prompt: Label3D = null
var _rebuild_queued := false
var _player_aboard: CharacterBody3D = null
var _sailing := false
var _time := 0.0
var _home_pos: Vector3


func _ready():
	_home_pos = position
	_request_rebuild()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _built and is_instance_valid(_built):
		_built.free()
	_built = Node3D.new()
	add_child(_built)
	
	var hull_m := StandardMaterial3D.new()
	hull_m.albedo_color = hull_color
	hull_m.roughness = 0.85
	var trim_m := StandardMaterial3D.new()
	trim_m.albedo_color = trim_color
	trim_m.roughness = 0.8
	
	var L := boat_length
	var W := L * 0.42
	
	# Deck body (walkable) - AnimatableBody3D so the bob carries the player
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = true
	_built.add_child(_body)
	var deck_col := CollisionShape3D.new()
	var deck_shape := BoxShape3D.new()
	deck_shape.size = Vector3(W - 0.3, 0.25, L - 1.2)
	deck_col.shape = deck_shape
	deck_col.position = Vector3(0, 0.35, 0)
	_body.add_child(deck_col)
	
	# Hull: box + angled bow prism
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(W, 0.9, L - 1.4)
	hull.mesh = hm
	hull.material_override = hull_m
	hull.position = Vector3(0, 0.1, 0.2)
	_body.add_child(hull)
	var bow := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(W, 0.9, 1.6)
	bow.mesh = pm
	bow.material_override = hull_m
	bow.rotation_degrees.x = -90.0
	bow.position = Vector3(0, 0.1, -(L - 1.4) * 0.5 - 0.6)
	_body.add_child(bow)
	
	# Gunwale trim rails
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.14, 0.3, L - 1.2)
		rail.mesh = rm
		rail.material_override = trim_m
		rail.position = Vector3(side * (W * 0.5 - 0.07), 0.68, 0.15)
		_body.add_child(rail)
	# Stern bench
	var bench := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W - 0.5, 0.15, 0.6)
	bench.mesh = bm
	bench.material_override = trim_m
	bench.position = Vector3(0, 0.62, (L - 1.4) * 0.5 - 0.3)
	_body.add_child(bench)
	
	# Boarding detection
	_area = Area3D.new()
	_area.monitoring = true
	_area.monitorable = false
	_area.collision_layer = 0
	_area.collision_mask = 1
	var ac := CollisionShape3D.new()
	var ashape := BoxShape3D.new()
	ashape.size = Vector3(W + 0.6, 2.5, L)
	ac.shape = ashape
	ac.position = Vector3(0, 1.4, 0)
	_area.add_child(ac)
	_built.add_child(_area)
	if not Engine.is_editor_hint():
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	
	# Interact prompt
	_prompt = Label3D.new()
	_prompt.text = "[E] Set sail"
	_prompt.font_size = 64
	_prompt.pixel_size = 0.01
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.modulate = Color(1.0, 0.95, 0.7)
	_prompt.outline_size = 12
	_prompt.position = Vector3(0, 2.2, 0)
	_prompt.visible = false
	_built.add_child(_prompt)


func _refresh_prompt_visibility():
	if _prompt and is_instance_valid(_prompt):
		_prompt.visible = active and _player_aboard != null and not _sailing


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_aboard = body
		_refresh_prompt_visibility()


func _on_body_exited(body: Node) -> void:
	if body == _player_aboard:
		_player_aboard = null
		_refresh_prompt_visibility()


func _process(delta: float):
	_time += delta
	# Gentle mooring bob (scenery and ferry alike; paused while sailing)
	if not _sailing and _built and is_instance_valid(_built):
		_built.position.y = sin(_time * 1.1) * 0.06
		_built.rotation.z = sin(_time * 0.9) * 0.015
		_built.rotation.x = sin(_time * 0.7 + 1.3) * 0.01
	
	if Engine.is_editor_hint() or _sailing or not active:
		return
	if _player_aboard and is_instance_valid(_player_aboard) \
			and Input.is_action_just_pressed("interact"):
		_set_sail()


func _destination() -> String:
	return area_a if sail_to == 0 else area_b


func _set_sail():
	var dest := _destination()
	if dest == "":
		push_warning("Boat: no destination scene set for %s" % ("Area A" if sail_to == 0 else "Area B"))
		return
	_sailing = true
	_refresh_prompt_visibility()
	
	# Freeze gameplay: cutscene mode + player control off, ride the boat
	var cm = get_node_or_null("/root/CutsceneManager")
	if cm and cm.has_method("start_cutscene"):
		cm.start_cutscene()
	if _player_aboard and is_instance_valid(_player_aboard):
		_player_aboard.controls_disabled = true
		_player_aboard.velocity = Vector3.ZERO
	
	# SAIL-AWAY CUTSCENE: the boat pulls away from shore (out along -Z,
	# with a slow turn), the screen fades near the end, then the
	# destination hub loads. The ride IS the loading screen.
	var out := -global_transform.basis.z
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else Vector3.FORWARD
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "global_position",
			global_position + out * (cutscene_duration * 3.2), cutscene_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", rotation.y + 0.35, cutscene_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Keep the player glued to the deck during the ride
	tw.tween_method(_carry_player, 0.0, 1.0, cutscene_duration)
	tw.set_parallel(false)
	tw.tween_callback(func():
		var cm2 = get_node_or_null("/root/CutsceneManager")
		if cm2 and cm2.has_method("end_cutscene"):
			cm2.end_cutscene()
		get_tree().change_scene_to_file(dest)
	)
	_fade_out(cutscene_duration)


func _carry_player(_t: float) -> void:
	if _player_aboard and is_instance_valid(_player_aboard):
		var deck := global_position + Vector3(0, 0.6, 0)
		_player_aboard.global_position = _player_aboard.global_position.lerp(
			deck, 0.15)
		_player_aboard.velocity = Vector3.ZERO


func _fade_out(duration: float) -> void:
	"""Full-screen fade covering the last stretch of the sail."""
	var layer := CanvasLayer.new()
	layer.layer = 100
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	get_tree().root.add_child(layer)
	var tw := create_tween()
	tw.tween_interval(duration * 0.55)
	tw.tween_property(rect, "color:a", 1.0, duration * 0.4)
