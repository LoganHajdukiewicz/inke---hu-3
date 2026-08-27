class_name QuestGiver
extends CharacterBody3D

## An NPC that offers quests. Walk up, press interact (E / gamepad X):
##  - no active quest -> quest offer panel (accept with E, decline with Esc)
##  - FETCH quest active + item in hand -> turn-in (completes the quest)
##  - quest active -> reminder of what's left
##  - quest done (non-repeatable) -> thanks
##
## Configure the "quests" array in the Inspector: the NPC offers them in
## order (skipping completed non-repeatable ones).

@export var npc_name: String = "Quest Giver"
@export var quests: Array[Quest] = []
@export var body_color: Color = Color(0.95, 0.75, 0.2)

@export_group("Dialogue Lines")
## Spoken one message at a time before the quest offer - each press of E
## points to the next message; after the last one the quest offer shows.
@export_multiline var intro_dialogue: Array[String] = []
@export_multiline var greeting: String = "Hey! I've got work if you want it."
@export_multiline var reminder: String = "How's that job coming along?"
@export_multiline var thanks: String = "That's everything I had. Thanks!"

var player_in_range: bool = false
var current_player: CharacterBody3D = null
var panel_open: bool = false
var offered_quest: Quest = null
var _input_cooldown: float = 0.0
var _dialogue_queue: Array[String] = []   # intro messages still to show
var _after_dialogue: Callable = Callable() # what to do when the chat ends

# UI
var canvas: CanvasLayer
var prompt_label: Label
var panel: PanelContainer
var panel_title: Label
var panel_body: Label
var panel_hint: Label

# Visual
var _mesh_root: Node3D
var _marker: Label3D
var _bob_time: float = 0.0


func _ready() -> void:
	add_to_group("QuestGiver")
	_build_visual()
	_build_ui()
	
	var area = Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var col = CollisionShape3D.new()
	var sph = SphereShape3D.new()
	sph.radius = 3.0
	col.shape = sph
	col.position.y = 1.0
	area.add_child(col)
	add_child(area)
	area.body_entered.connect(_on_area_entered)
	area.body_exited.connect(_on_area_exited)
	
	var qm = get_node_or_null("/root/QuestManager")
	if qm:
		qm.quest_completed.connect(func(_q): _update_marker())
		qm.quest_accepted.connect(func(_q): _update_marker())
	_update_marker()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	
	# Idle bob on the exclamation marker
	_bob_time += delta
	if _marker:
		_marker.position.y = 2.6 + sin(_bob_time * 2.5) * 0.1
	
	# Face the player when nearby
	if player_in_range and current_player and is_instance_valid(current_player):
		var to_p = current_player.global_position - global_position
		to_p.y = 0
		if to_p.length() > 0.3 and _mesh_root:
			var target = Basis.looking_at(to_p.normalized(), Vector3.UP)
			_mesh_root.global_transform.basis = _mesh_root.global_transform.basis.orthonormalized().slerp(target, delta * 8.0).orthonormalized()


func _process(delta: float) -> void:
	if _input_cooldown > 0.0:
		_input_cooldown -= delta
	
	if not player_in_range:
		return
	
	if panel_open:
		if _input_cooldown <= 0.0:
			if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
				_confirm_panel()
			elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("dash"):
				_close_panel()
	else:
		if _input_cooldown <= 0.0 and Input.is_action_just_pressed("interact"):
			_interact()


# =========================================================================
# INTERACTION FLOW
# =========================================================================

func _interact() -> void:
	var qm = get_node_or_null("/root/QuestManager")
	if not qm:
		return
	_input_cooldown = 0.25
	
	# 1. Turn-in ready fetch quests first
	for q in quests:
		if qm.is_quest_active(q.quest_id) and q.quest_type == Quest.QuestType.FETCH_ITEM:
			if qm.try_turn_in(q.quest_id):
				_open_panel(npc_name, "Ha, you actually found it! Here's your reward.", "[E] Close")
				offered_quest = null
				return
	
	# 2. Any of my quests still active? Remind.
	for q in quests:
		if qm.is_quest_active(q.quest_id):
			_open_panel(npc_name, reminder + "\n\n" + _progress_text(qm, q), "[E] Close")
			offered_quest = null
			return
	
	# 3. Offer the next available quest - after the intro conversation,
	# where each message points to the next (or straight to the offer)
	var next_quest = _next_available_quest(qm)
	if next_quest:
		if not intro_dialogue.is_empty():
			_dialogue_queue = intro_dialogue.duplicate()
			_after_dialogue = _offer_quest.bind(next_quest)
			_show_next_dialogue_message()
		else:
			_offer_quest(next_quest)
		return
	
	# 4. Nothing left
	_open_panel(npc_name, thanks, "[E] Close")
	offered_quest = null


func _show_next_dialogue_message() -> void:
	"""Pop the next message off the conversation queue and show it.
	Each message 'points to' the next; the last one hands off to
	_after_dialogue (usually the quest offer)."""
	_input_cooldown = 0.25
	var msg = _dialogue_queue.pop_front()
	var hint = "[E] Next" if not _dialogue_queue.is_empty() or _after_dialogue.is_valid() else "[E] Close"
	_open_panel(npc_name, msg, hint)


func _offer_quest(next_quest: Quest) -> void:
	offered_quest = next_quest
	var body_text = greeting + "\n\n%s\n%s" % [next_quest.title, next_quest.description]
	body_text += "\n\nReward: %d CRED" % next_quest.cred_reward
	if next_quest.has_time_limit:
		body_text += "   |   Time limit: %ds" % int(next_quest.time_limit_seconds)
	_open_panel(npc_name, body_text, "[E] Accept       [Esc] Not now")


func _confirm_panel() -> void:
	_input_cooldown = 0.25
	# Mid-conversation: this message points to the next one
	if not _dialogue_queue.is_empty():
		_show_next_dialogue_message()
		return
	# Conversation over: run whatever it was leading to (quest offer etc.)
	if _after_dialogue.is_valid():
		var follow_up = _after_dialogue
		_after_dialogue = Callable()
		follow_up.call()
		return
	if offered_quest:
		var qm = get_node_or_null("/root/QuestManager")
		if qm:
			qm.accept_quest(offered_quest, self)
		offered_quest = null
	_close_panel()


func _close_panel() -> void:
	panel_open = false
	panel.visible = false
	offered_quest = null
	_dialogue_queue.clear()
	_after_dialogue = Callable()
	_input_cooldown = 0.25
	if player_in_range:
		prompt_label.visible = true
	_update_marker()


func _open_panel(title: String, body_text: String, hint: String) -> void:
	panel_open = true
	panel.visible = true
	prompt_label.visible = false
	panel_title.text = title
	panel_body.text = body_text
	panel_hint.text = hint


func _next_available_quest(qm) -> Quest:
	for q in quests:
		if q == null or q.quest_id == "":
			continue
		if qm.is_quest_active(q.quest_id):
			continue
		if qm.is_quest_completed(q.quest_id) and not q.repeatable:
			continue
		return q
	return null


func _progress_text(qm, q: Quest) -> String:
	var entry = qm.get_active_entry(q.quest_id)
	if entry.is_empty():
		return ""
	match q.quest_type:
		Quest.QuestType.COLLECT_GEARS:
			return "Gears: %d / %d" % [entry.progress, q.goal_count()]
		Quest.QuestType.DEFEAT_ENEMY:
			return "Defeated: %d / %d" % [entry.progress, q.goal_count()]
		Quest.QuestType.REACH_LOCATION:
			return "You haven't reached the spot yet."
		Quest.QuestType.FETCH_ITEM:
			return "Bring me the item!" if not entry.item_held else "Hand it over!"
	return ""


func _update_marker() -> void:
	if not _marker:
		return
	var qm = get_node_or_null("/root/QuestManager")
	if not qm:
		return
	# "!" = quest available, "?" = quest in progress, none = all done
	var has_active := false
	for q in quests:
		if qm.is_quest_active(q.quest_id):
			has_active = true
			break
	if has_active:
		_marker.text = "?"
		_marker.modulate = Color(0.6, 0.85, 1.0)
	elif _next_available_quest(qm):
		_marker.text = "!"
		_marker.modulate = Color(1.0, 0.85, 0.2)
	else:
		_marker.text = ""


# =========================================================================
# AREA / UI PLUMBING
# =========================================================================

func _on_area_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_in_range = true
		current_player = body
		prompt_label.text = "[E] Talk to " + npc_name
		prompt_label.visible = true


func _on_area_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_in_range = false
		current_player = null
		prompt_label.visible = false
		if panel_open:
			_close_panel()


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
	
	# Eyes so you can tell which way it faces
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
	
	# Floating quest marker
	_marker = Label3D.new()
	_marker.text = "!"
	_marker.font_size = 140
	_marker.outline_size = 24
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.position.y = 2.6
	_marker.modulate = Color(1.0, 0.85, 0.2)
	add_child(_marker)
	
	# Name tag
	var tag = Label3D.new()
	tag.text = npc_name
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.008
	tag.position.y = 2.35
	add_child(tag)


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
	
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -160
	panel.offset_bottom = 160
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.11, 0.92)
	style.border_color = Color(1.0, 0.8, 0.3)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.visible = false
	canvas.add_child(panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	
	panel_title = Label.new()
	panel_title.add_theme_font_size_override("font_size", 26)
	panel_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(panel_title)
	
	panel_body = Label.new()
	panel_body.add_theme_font_size_override("font_size", 18)
	panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(panel_body)
	
	panel_hint = Label.new()
	panel_hint.add_theme_font_size_override("font_size", 16)
	panel_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	panel_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(panel_hint)
