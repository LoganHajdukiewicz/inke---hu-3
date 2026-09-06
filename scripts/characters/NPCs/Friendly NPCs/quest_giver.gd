@tool
class_name QuestGiver
extends CharacterBody3D

## An NPC that offers quests through the DialogueManager (the real dialogue
## box, typewriter text and all). Press E to talk.
##
## The giver always knows which of FOUR states it's in for its quest:
##   FIRST_OFFER - never accepted before: small talk first, then the ask.
##                 X (jump/Cross) accepts, O (dash/Circle) declines.
##   WAITING     - quest is running: reminds the player what's left.
##   RETRY       - the quest was failed: "dust yourself off" line, then
##                 offers it again (X/O choice).
##   DONE        - quest completed: thankful, conversation over. Does NOT
##                 re-offer (unless the quest is marked repeatable).

enum GiverState { FIRST_OFFER, WAITING, RETRY, DONE }

@export var npc_name: String = "Quest Giver"

## THE quest this giver hands out - exactly ONE per person. Exposed to the
## Inspector as a dropdown via _get_property_list: it lists every quest
## file in res://quests/ (add .tres files there and they show up
## automatically). Duplicate a default file to make your own.
var quest_file: String = "":
	set(value):
		quest_file = value
		_quest_cache = null

## Alternative: assign a Quest resource directly (overrides quest_file).
## Handy for one-off inline quests.
@export var quest_override: Quest = null:
	set(value):
		quest_override = value
		_quest_cache = null

var _quest_cache: Quest = null

const QUESTS_DIR := "res://quests"


func _get_property_list() -> Array:
	# Turn quest_file into a dropdown of every quest file in res://quests/
	var options := ""
	var dir = DirAccess.open(QUESTS_DIR)
	if dir:
		for f in dir.get_files():
			if f.ends_with(".tres") or f.ends_with(".res"):
				options += ("," if options != "" else "") + f
	return [{
		"name": "quest_file",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM_SUGGESTION,
		"hint_string": options,
		"usage": PROPERTY_USAGE_DEFAULT,
	}]


func get_quest() -> Quest:
	"""The single quest this giver offers (override > file > null)."""
	if quest_override:
		return quest_override
	if _quest_cache:
		return _quest_cache
	if quest_file != "":
		var path = quest_file if quest_file.begins_with("res://") else QUESTS_DIR + "/" + quest_file
		if ResourceLoader.exists(path):
			_quest_cache = load(path)
	return _quest_cache
@export var body_color: Color = Color(0.95, 0.75, 0.2)
## Portrait name (assets/portraits/{name}.png), optional.
@export var portrait: String = ""

@export_group("Dynamic Camera")
## Cut between cinematic camera angles while talking to this NPC.
@export var dynamic_camera: bool = true
## Optional posed Node3Ds/CutsceneCameras to use instead of auto shots
## (one per line, cycling). Pose with F10 free roam + P.
@export var custom_camera_angles: Array[Node3D] = []

@export_group("Dialogue Lines")
## Small talk before the first-time quest ask, one message per entry.
@export_multiline var small_talk: Array[String] = [
	"Oh! A visitor. Don't get many of those out here.",
	"You look like someone who gets things done.",
]
## The ask itself (X/O choice is appended automatically).
@export_multiline var quest_ask: String = "So - think you could help me out?"
## While the quest runs.
@export_multiline var reminder: String = "How's that job coming along? Here's what I remember:"
## After a failure, before re-offering.
@export_multiline var retry_line: String = "Hey, don't sweat it. Dust yourself off - want another shot?"
## After completion.
@export_multiline var thanks: String = "You really came through. Thank you!"
## If the player declines the offer.
@export_multiline var decline_response: String = "No worries. I'll be here if you change your mind."

var player_in_range: bool = false
var current_player: CharacterBody3D = null
var _input_cooldown: float = 0.0
var _pending_offer: Quest = null
var _in_conversation: bool = false

# UI (interaction prompt only - dialogue itself is the DialogueManager's box)
var canvas: CanvasLayer
var prompt_label: Label

# Visual
var _mesh_root: Node3D
var _marker: Label3D
var _bob_time: float = 0.0
var _settled: bool = false
var _settled_position: Vector3
var _flashing: bool = false
var _flash_mats: Array = []   # [material, original_color] pairs, collected once


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("QuestGiver")
		add_to_group("NPCs")   # Hittable-but-not-hurtable: attacks make us flash
	
	_build_visual()
	_build_interaction_area()
	
	if Engine.is_editor_hint():
		_build_debug_area_mesh()
		return  # Skip gameplay setup in editor
	
	_build_ui()
	_ensure_dialogue_ui()
	
	var qm = get_node_or_null("/root/QuestManager")
	if qm:
		qm.quest_completed.connect(func(_q): _update_marker())
		qm.quest_accepted.connect(func(_q): _update_marker())
		qm.quest_failed.connect(func(_q): _update_marker())
	_update_marker()


func _build_interaction_area() -> void:
	"""Create the Area3D for player detection (used in both editor and runtime)."""
	var area = Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 0
	area.collision_mask = 1
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 3.0
	col.shape = sph
	col.position.y = 1.0
	area.add_child(col)
	add_child(area)
	
	if not Engine.is_editor_hint():
		area.body_entered.connect(_on_area_entered)
		area.body_exited.connect(_on_area_exited)


func _build_debug_area_mesh() -> void:
	"""Create a semi-transparent sphere mesh to visualize interaction area in editor."""
	var debug_mesh_instance = MeshInstance3D.new()
	debug_mesh_instance.name = "DebugInteractionArea"
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 3.0
	sphere_mesh.height = 6.0
	debug_mesh_instance.mesh = sphere_mesh
	debug_mesh_instance.position.y = 1.0
	
	# Semi-transparent green material for visibility
	var debug_mat = StandardMaterial3D.new()
	debug_mat.albedo_color = Color(0.0, 1.0, 0.5, 0.15)
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.no_depth_test = false
	debug_mesh_instance.set_surface_override_material(0, debug_mat)
	
	add_child(debug_mesh_instance)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return  # No physics in editor
	
	# Settle onto the floor once, then FREEZE. Always call move_and_slide()
	# to maintain collision with the player, but reset position to prevent
	# being pushed around by walk-into forces.
	if _settled:
		if global_position != _settled_position:
			global_position = _settled_position   # paranoia: undo any nudge
		velocity = Vector3.ZERO
	else:
		if not is_on_floor():
			velocity.y -= 25.0 * delta
		else:
			velocity.y = 0.0
			_settled = true
			_settled_position = global_position
		velocity.x = 0.0
		velocity.z = 0.0
	
	move_and_slide()


func _process(delta: float) -> void:
	_bob_time += delta
	if _marker:
		_marker.position.y = 2.6 + sin(_bob_time * 2.5) * 0.1
	
	if Engine.is_editor_hint():
		return  # Skip gameplay logic in editor
	
	# Face the player (visual only - the body itself never moves)
	if player_in_range and current_player and is_instance_valid(current_player) and _mesh_root:
		var to_p = current_player.global_position - global_position
		to_p.y = 0
		if to_p.length() > 0.3:
			var target = Basis.looking_at(to_p.normalized(), Vector3.UP)
			_mesh_root.global_transform.basis = _mesh_root.global_transform.basis.orthonormalized().slerp(target, delta * 8.0).orthonormalized()
	
	if _input_cooldown > 0.0:
		_input_cooldown -= delta
	
	if not player_in_range or _in_conversation:
		return
	if DialogueManager.is_dialogue_active():
		return
	
	if _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact"):
		_interact()


func _ensure_dialogue_ui() -> void:
	"""Levels without a DialogueUI instance (like the greybox) still need the
	dialogue box - instance it on demand, exactly once."""
	if DialogueManager.dialogue_ui and is_instance_valid(DialogueManager.dialogue_ui):
		return
	var scene_root = get_tree().current_scene
	if not scene_root:
		return
	if scene_root.find_child("DialogueUi", false, false) or scene_root.find_child("DialogueUI", false, false):
		return
	var ui_scene = load("res://scenes/UI/dialogue_ui.tscn")
	if ui_scene:
		var ui = ui_scene.instantiate()
		ui.name = "DialogueUI"
		scene_root.add_child.call_deferred(ui)


# =========================================================================
# STATE
# =========================================================================

## The quest this giver currently cares about, and the state it's in.
func get_state() -> GiverState:
	var qm = get_node_or_null("/root/QuestManager")
	if not qm:
		return GiverState.DONE
	
	var q = _current_quest(qm)
	if q == null:
		return GiverState.DONE
	if qm.is_quest_active(q.quest_id):
		return GiverState.WAITING
	if qm.has_quest_failed(q.quest_id):
		return GiverState.RETRY
	return GiverState.FIRST_OFFER


func _current_quest(qm) -> Quest:
	"""This giver's ONE quest, if it's still relevant to the player."""
	var q = get_quest()
	if q == null or q.quest_id == "":
		return null
	if qm.is_quest_active(q.quest_id):
		return q
	if qm.has_quest_failed(q.quest_id):
		return q
	if not qm.is_quest_completed(q.quest_id) or q.repeatable:
		return q
	return null


# =========================================================================
# CONVERSATION (through DialogueManager)
# =========================================================================

func _interact() -> void:
	var qm = get_node_or_null("/root/QuestManager")
	if not qm:
		return
	_input_cooldown = 0.4
	
	var lines: Array = []
	_pending_offer = null
	var q = _current_quest(qm)
	
	# Turn-in beats everything: the quest TYPE decides if talking completes
	# it (fetch-style quests return true here once the item is in hand)
	if q and qm.is_quest_active(q.quest_id):
		if qm.try_turn_in(q.quest_id):
			lines = [_line("You found it! Incredible. Here - you've earned this.")]
			_speak(lines)
			return
	
	match get_state():
		GiverState.FIRST_OFFER:
			# Small talk first, then the ask as an X/O choice
			for talk in small_talk:
				lines.append(_line(talk))
			lines.append(_line(quest_ask))
			lines.append(_quest_offer_line(q))
			_pending_offer = q
		
		GiverState.WAITING:
			lines = [_line(reminder), _line(_progress_text(qm, q))]
		
		GiverState.RETRY:
			# Encourage, then re-offer (no small talk the second time around)
			lines.append(_line(retry_line))
			lines.append(_quest_offer_line(q))
			_pending_offer = q
		
		GiverState.DONE:
			lines = [_line(thanks)]
	
	_speak(lines)


func _speak(lines: Array) -> void:
	_in_conversation = true
	prompt_label.visible = false
	if dynamic_camera:
		DialogueManager.request_dynamic_camera(self, custom_camera_angles)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)
	if _pending_offer:
		DialogueManager.choice_made.connect(_on_choice_made, CONNECT_ONE_SHOT)
	DialogueManager.start_dialogue_lines(lines, true)


func _line(text: String) -> Dictionary:
	return {"speaker": npc_name, "text": text, "portrait": portrait}


func _quest_offer_line(q: Quest) -> Dictionary:
	var text = "%s\n%s\n\nReward: %d CRED" % [q.title, q.description, q.cred_reward]
	if q.has_time_limit:
		text += "   |   Time limit: %ds" % int(q.time_limit_seconds)
	return {"speaker": npc_name, "text": text, "portrait": portrait, "choice": true}


func _on_choice_made(accepted: bool) -> void:
	var offer = _pending_offer
	_pending_offer = null
	if not offer:
		return
	var qm = get_node_or_null("/root/QuestManager")
	if accepted and qm:
		qm.accept_quest(offer, self)
	elif not accepted:
		# A brief "no worries" after the box closes
		call_deferred("_speak_decline")


func _speak_decline() -> void:
	await get_tree().create_timer(0.05).timeout
	_in_conversation = true
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)
	DialogueManager.start_dialogue_lines([_line(decline_response)], true)


func _on_dialogue_ended() -> void:
	_in_conversation = false
	_input_cooldown = 0.4
	# If the conversation ended without answering the choice (shouldn't
	# happen, but don't leak the pending offer)
	if _pending_offer and DialogueManager.choice_made.is_connected(_on_choice_made):
		DialogueManager.choice_made.disconnect(_on_choice_made)
	_pending_offer = null
	if player_in_range:
		prompt_label.visible = true
	_update_marker()


func _progress_text(qm, q: Quest) -> String:
	var entry = qm.get_active_entry(q.quest_id)
	if entry.is_empty():
		return ""
	var text: String = entry.handler.describe_reminder(entry)
	if q.has_time_limit and entry.has("time_left"):
		text += " You've got %d seconds left." % int(entry.time_left)
	return text


func _update_marker() -> void:
	if not _marker:
		return
	match get_state():
		GiverState.FIRST_OFFER:
			_marker.text = "!"
			_marker.modulate = Color(1.0, 0.85, 0.2)
		GiverState.WAITING:
			_marker.text = "?"
			_marker.modulate = Color(0.6, 0.85, 1.0)
		GiverState.RETRY:
			_marker.text = "!"
			_marker.modulate = Color(1.0, 0.45, 0.3)
		GiverState.DONE:
			_marker.text = ""


# =========================================================================
# AREA / UI PLUMBING
# =========================================================================

func _on_area_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true
		current_player = body
		var im = get_node_or_null("/root/InputManager")
		prompt_label.text = (im.prompt("interact") if im else "[E]") + " Talk to " + npc_name
		if not DialogueManager.is_dialogue_active():
			prompt_label.visible = true


func _on_area_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
		current_player = null
		prompt_label.visible = false


func _build_visual() -> void:
	_mesh_root = Node3D.new()
	add_child(_mesh_root)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = body_color
	
	var torso = MeshInstance3D.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.45
	cap.height = 1.6
	torso.mesh = cap
	torso.material_override = mat
	torso.position.y = 0.8
	_mesh_root.add_child(torso)
	
	var head = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 0.32
	sph.height = 0.64
	head.mesh = sph
	head.material_override = mat
	head.position.y = 1.9
	_mesh_root.add_child(head)
	
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.1, 0.1, 0.15)
	for ex in [-0.12, 0.12]:
		var eye = MeshInstance3D.new()
		var es = SphereMesh.new()
		es.radius = 0.05
		es.height = 0.1
		eye.mesh = es
		eye.material_override = eye_mat
		eye.position = Vector3(ex, 1.95, -0.28)
		_mesh_root.add_child(eye)
	
	var col = CollisionShape3D.new()
	var cshape = CapsuleShape3D.new()
	cshape.radius = 0.45
	cshape.height = 1.6
	col.shape = cshape
	col.position.y = 0.8
	add_child(col)
	
	_marker = Label3D.new()
	_marker.text = "!"
	_marker.font_size = 140
	_marker.outline_size = 24
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = 2.6
	_marker.modulate = Color(1.0, 0.85, 0.2)
	add_child(_marker)
	
	var tag = Label3D.new()
	tag.text = npc_name
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.008
	tag.position.y = 2.35
	add_child(tag)


# === HIT REACTION ============================================================
# NPCs can't be damaged or moved, but they DO notice. For now: a white
# flash + a little indignant squash. Once the NPCs are modeled, swap the
# squash for a proper hurt animation here.

func on_hit() -> void:
	"""Called by the player's attacks (they scan the \"NPCs\" group)."""
	if Engine.is_editor_hint() or _flashing or not _mesh_root:
		return
	_flashing = true
	
	# Collect flashable materials once (torso, head, eyes)
	if _flash_mats.is_empty():
		for child in _mesh_root.get_children():
			if child is MeshInstance3D and child.material_override is StandardMaterial3D:
				_flash_mats.append([child.material_override, child.material_override.albedo_color])
	
	for pair in _flash_mats:
		pair[0].albedo_color = Color.WHITE
	
	# Indignant flinch (visual only - the body never moves from its spot)
	var tween = create_tween()
	tween.tween_property(_mesh_root, "scale", Vector3(1.12, 0.85, 1.12), 0.06)
	tween.tween_property(_mesh_root, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	await get_tree().create_timer(0.12).timeout
	if not is_instance_valid(self):
		return
	for pair in _flash_mats:
		pair[0].albedo_color = pair[1]
	_flashing = false


func _build_ui() -> void:
	canvas = CanvasLayer.new()
	canvas.layer = 45
	add_child(canvas)
	
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_top = -140
	prompt_label.offset_bottom = -100
	prompt_label.offset_left = -300
	prompt_label.offset_right = 300
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 22)
	prompt_label.add_theme_constant_override("outline_size", 8)
	prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt_label.visible = false
	canvas.add_child(prompt_label)
