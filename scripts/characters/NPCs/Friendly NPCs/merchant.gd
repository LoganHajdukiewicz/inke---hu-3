extends CharacterBody3D
class_name Merchant

## The Merchant - heavily inspired by a certain Resident Evil 4 gentleman.
## Talk to him and he plays his intro line(s) through the real dialogue box
## (editable in the Inspector), then THROWS OPEN HIS COAT to reveal the
## goods hanging inside, and the shop menu appears.
##
## "Whaddya buyin'?"

# ==========================================
# UPGRADE CONFIGURATION
# ==========================================

enum PowerupType {
	DOUBLE_JUMP,
	WALL_JUMP,
	DASH,
	SPEED_UPGRADE,
	HEALTH_UPGRADE,
	DAMAGE_UPGRADE
}

@export_group("Available Upgrades")
@export var available_upgrades: Array[PowerupType] = [
	PowerupType.DOUBLE_JUMP,
	PowerupType.WALL_JUMP,
	PowerupType.DASH
]

@export_group("Merchant Settings")
@export var merchant_name: String = "Merchant"
## Shown at the top of the shop menu.
@export var greeting_text: String = "Whaddya buyin'?"
## Portrait name for the dialogue box (assets/portraits/{name}.png), optional.
@export var portrait: String = ""

@export_group("Intro Dialogue")
## Played through the dialogue box BEFORE the coat opens, one message per
## entry. Edit freely in the Inspector.
@export_multiline var intro_lines: Array[String] = [
	"Ahh... I'll buy it at a high price. Heh heh heh...",
	"Got some rare things on sale, stranger.",
]
## Play the intro every single time (off = only the first visit).
@export var intro_every_time: bool = false

@export_group("Coat")
@export var coat_color: Color = Color(0.16, 0.13, 0.11)     # Grimy long coat
@export var coat_open_time: float = 0.45                     # How fast the reveal is
@export var eye_color: Color = Color(1.0, 0.45, 0.1)         # Glowing eyes under the hood

# ==========================================
# STATE
# ==========================================

var player_in_range: bool = false
var current_player: CharacterBody3D = null
var shop_open: bool = false
var _busy: bool = false            # Mid-intro-dialogue or mid-coat-animation
var _intro_played: bool = false
var _coat_is_open: bool = false

var current_upgrade_index: int = 0
var upgrade_data: Array = []

# UI references
var canvas_layer: CanvasLayer
var interaction_label: Label
var dim_rect: ColorRect
var shop_panel: Panel
var title_label: Label
var greeting_label: Label
var gear_count_label: Label
var upgrade_description_label: Label
var status_label: Label
var item_cards: Array = []         # [{panel, name_label, cost_label, status_label}]

# Model references
var _model: Node3D
var _coat_pivot: Node3D    # Single hinge at the shoulder - one flap, one hand
var _wares_root: Node3D

# UI Colors
const COLOR_PURCHASED := Color(0.35, 0.85, 0.4)
const COLOR_AFFORDABLE := Color(0.95, 0.85, 0.3)
const COLOR_EXPENSIVE := Color(0.85, 0.35, 0.3)
const COLOR_SELECTED_BG := Color(0.16, 0.22, 0.32, 1.0)
const COLOR_UNSELECTED_BG := Color(0.1, 0.11, 0.14, 1.0)

var input_cooldown: float = 0.0
var input_cooldown_time: float = 0.18

# ==========================================
# INITIALIZATION
# ==========================================

func _ready():
	add_to_group("NPCs")
	setup_upgrade_data()
	_build_model()
	setup_ui()
	
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if has_node("Area3D"):
		$Area3D.body_entered.connect(_on_area_3d_body_entered)
		$Area3D.body_exited.connect(_on_area_3d_body_exited)
	else:
		print("WARNING: Merchant needs an Area3D child node!")
	
	_ensure_dialogue_ui()


func _ensure_dialogue_ui() -> void:
	"""Levels without a DialogueUI instance (like the greybox) still need the
	dialogue box for the intro lines - instance it on demand, exactly once.
	(Same pattern as QuestGiver - without this the intro dies with
	'DialogueManager: No UI registered!')"""
	var dm = get_node_or_null("/root/DialogueManager")
	if not dm:
		return
	if dm.dialogue_ui and is_instance_valid(dm.dialogue_ui):
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


func setup_upgrade_data():
	upgrade_data.clear()
	for powerup_type in available_upgrades:
		var upgrade_key = get_upgrade_key(powerup_type)
		if upgrade_key != "":
			upgrade_data.append({
				"type": powerup_type,
				"key": upgrade_key,
				"name": GameManager.get_upgrade_name(upgrade_key),
				"description": GameManager.get_upgrade_description(upgrade_key),
				"cost": GameManager.get_upgrade_cost(upgrade_key),
			})


func get_upgrade_key(powerup_type: PowerupType) -> String:
	match powerup_type:
		PowerupType.DOUBLE_JUMP: return "double_jump"
		PowerupType.WALL_JUMP: return "wall_jump"
		PowerupType.DASH: return "dash"
		PowerupType.SPEED_UPGRADE: return "speed_upgrade"
		PowerupType.HEALTH_UPGRADE: return "health_upgrade"
		PowerupType.DAMAGE_UPGRADE: return "damage_upgrade"
		_: return ""


# ==========================================
# MODEL - long coat, hood, glowing eyes, and the famous coat reveal
# ==========================================

func _build_model():
	# Hide any placeholder mesh from the scene file
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = false
	
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	
	var coat_mat = StandardMaterial3D.new()
	coat_mat.albedo_color = coat_color
	coat_mat.roughness = 0.95
	
	var lining_mat = StandardMaterial3D.new()
	lining_mat.albedo_color = Color(0.3, 0.08, 0.08)   # Deep red coat lining
	lining_mat.roughness = 0.9
	
	# --- Body: long tapered coat (wider at the bottom, like a robe) -------
	var body = MeshInstance3D.new()
	var body_mesh = CylinderMesh.new()
	body_mesh.top_radius = 0.38
	body_mesh.bottom_radius = 0.55
	body_mesh.height = 1.7
	body.mesh = body_mesh
	body.material_override = coat_mat
	body.position.y = 0.85
	_model.add_child(body)
	
	# --- Head: a proper HOOD, not a bald sphere ---------------------------
	# Tapered cone-ish hood rising to a soft point, with a wide draped brim
	# that overhangs the face opening.
	var hood = MeshInstance3D.new()
	var hood_mesh = CylinderMesh.new()
	hood_mesh.top_radius = 0.06        # Nearly a point at the top
	hood_mesh.bottom_radius = 0.38     # Drapes wide over the shoulders
	hood_mesh.height = 0.75
	hood.mesh = hood_mesh
	hood.material_override = coat_mat
	hood.position.y = 2.0
	hood.rotation_degrees.x = 8.0      # Slight forward slouch
	_model.add_child(hood)
	
	# Drooping hood TIP flopped forward (the classic bent point)
	var hood_tip = MeshInstance3D.new()
	var tip_mesh = CylinderMesh.new()
	tip_mesh.top_radius = 0.015
	tip_mesh.bottom_radius = 0.07
	tip_mesh.height = 0.3
	hood_tip.mesh = tip_mesh
	hood_tip.material_override = coat_mat
	hood_tip.position = Vector3(0, 2.38, -0.1)
	hood_tip.rotation_degrees.x = -55.0   # Flops forward over the face
	_model.add_child(hood_tip)
	
	# Hood brim: a squashed torus-ish ring framing the face opening
	var brim = MeshInstance3D.new()
	var brim_mesh = TorusMesh.new()
	brim_mesh.inner_radius = 0.2
	brim_mesh.outer_radius = 0.3
	brim.mesh = brim_mesh
	brim.material_override = coat_mat
	brim.position = Vector3(0, 1.95, -0.16)
	brim.rotation_degrees.x = 78.0     # Facing forward, slightly tilted down
	brim.scale = Vector3(1.0, 1.0, 0.7)
	_model.add_child(brim)
	
	# Dark face void under the hood
	var face = MeshInstance3D.new()
	var face_mesh = SphereMesh.new()
	face_mesh.radius = 0.26
	face_mesh.height = 0.52
	face.mesh = face_mesh
	var face_mat = StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.03, 0.03, 0.04)
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.material_override = face_mat
	face.position = Vector3(0, 1.93, -0.12)
	_model.add_child(face)
	
	# Glowing eyes
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = eye_color
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_color
	eye_mat.emission_energy_multiplier = 2.5
	for ex in [-0.09, 0.09]:
		var eye = MeshInstance3D.new()
		var es = SphereMesh.new()
		es.radius = 0.035
		es.height = 0.07
		eye.mesh = es
		eye.material_override = eye_mat
		eye.position = Vector3(ex, 1.96, -0.33)
		_model.add_child(eye)
	
	# --- THE COAT: ONE full-width flap hinged at his shoulder -------------
	# The RE4 move: he grabs one side of the coat and holds it open. The
	# hinge sits at the +X shoulder and the flap extends across the chest;
	# opening rotates it OUT and FORWARD, away from the body, so it can
	# never sweep through the torso (that's what read as "wings" before).
	_coat_pivot = Node3D.new()
	_coat_pivot.position = Vector3(0.4, 1.15, -0.28)   # Shoulder, in FRONT of the body
	_model.add_child(_coat_pivot)
	
	# The flap: spans the whole chest, extends inward (-X) from the hinge
	var panel = MeshInstance3D.new()
	var panel_mesh = BoxMesh.new()
	panel_mesh.size = Vector3(0.85, 1.4, 0.05)
	panel.mesh = panel_mesh
	panel.material_override = coat_mat
	panel.position = Vector3(-0.42, -0.28, -0.06)
	_coat_pivot.add_child(panel)
	
	# Red lining on the inside face - THE reveal when the coat opens
	var lining = MeshInstance3D.new()
	var lining_mesh = BoxMesh.new()
	lining_mesh.size = Vector3(0.8, 1.34, 0.015)
	lining.mesh = lining_mesh
	lining.material_override = lining_mat
	lining.position = Vector3(-0.42, -0.28, -0.09)
	_coat_pivot.add_child(lining)
	
	# His ARM holding the flap's outer edge (sells "he's holding it open")
	var arm = MeshInstance3D.new()
	var arm_mesh = CapsuleMesh.new()
	arm_mesh.radius = 0.07
	arm_mesh.height = 0.55
	arm.mesh = arm_mesh
	arm.material_override = coat_mat
	arm.position = Vector3(-0.8, 0.05, -0.06)
	arm.rotation_degrees.z = 65.0
	_coat_pivot.add_child(arm)
	
	var hand = MeshInstance3D.new()
	var hand_mesh = SphereMesh.new()
	hand_mesh.radius = 0.085
	hand_mesh.height = 0.17
	hand.mesh = hand_mesh
	var hand_mat = StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.45, 0.38, 0.3)   # Grubby glove
	hand_mat.roughness = 0.9
	hand.material_override = hand_mat
	hand.position = Vector3(-0.86, 0.18, -0.06)
	_coat_pivot.add_child(hand)
	
	# Kept as an (empty) anchor so open/close code stays simple; if wares
	# ever come back they go here.
	_wares_root = Node3D.new()
	_model.add_child(_wares_root)
	_wares_root.visible = false
	
	# Name tag
	var tag = Label3D.new()
	tag.text = merchant_name
	tag.font_size = 40
	tag.outline_size = 10
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.008
	tag.position.y = 2.5
	tag.modulate = Color(0.9, 0.75, 0.4)
	_model.add_child(tag)
	
	_set_coat(false, true)


func _set_coat(open: bool, instant: bool = false):
	"""ONE flap, hinged at the shoulder. Closed: draped across the chest.
	Open: swung out to his side and forward - a clean single-arm hold-open,
	never through the body. Slight outer-edge lift = raised holding arm."""
	_coat_is_open = open
	# rotation.y negative swings the (-X extending) flap out toward the
	# front on his hinge side; rotation.z lifts the outer edge (raised arm)
	var yaw_target = deg_to_rad(-100.0) if open else 0.0
	var lift_target = deg_to_rad(-14.0) if open else 0.0
	
	if instant:
		_coat_pivot.rotation.y = yaw_target
		_coat_pivot.rotation.z = lift_target
		_wares_root.visible = open
		return
	
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # Animates even when paused
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_coat_pivot, "rotation:y", yaw_target, coat_open_time)
	tween.tween_property(_coat_pivot, "rotation:z", lift_target, coat_open_time)
	if open:
		_wares_root.visible = true
	else:
		tween.chain().tween_callback(func(): _wares_root.visible = false)


func on_hit() -> void:
	"""NPC hit reaction: clutch the coat shut and glare."""
	if _busy or shop_open:
		return
	var tween = create_tween()
	tween.tween_property(_model, "scale", Vector3(1.08, 0.9, 1.08), 0.06)
	tween.tween_property(_model, "scale", Vector3.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ==========================================
# UI - centered, anchored, controller-friendly
# ==========================================

func setup_ui():
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 44
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas_layer)
	
	# Interaction prompt (anchored bottom-center - works on any resolution)
	interaction_label = Label.new()
	interaction_label.text = "[E] Talk to " + merchant_name
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.add_theme_constant_override("outline_size", 8)
	interaction_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interaction_label.offset_top = -130
	interaction_label.offset_bottom = -95
	interaction_label.offset_left = -300
	interaction_label.offset_right = 300
	interaction_label.visible = false
	canvas_layer.add_child(interaction_label)
	
	# Full-screen dim behind the shop
	dim_rect = ColorRect.new()
	dim_rect.color = Color(0, 0, 0, 0.55)
	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.visible = false
	canvas_layer.add_child(dim_rect)
	
	# Main shop panel - centered
	shop_panel = Panel.new()
	shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	shop_panel.offset_left = -480
	shop_panel.offset_right = 480
	shop_panel.offset_top = -300
	shop_panel.offset_bottom = 300
	shop_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.11, 0.97)
	panel_style.border_color = Color(0.75, 0.6, 0.3)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_size = 24
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	canvas_layer.add_child(shop_panel)
	
	# Title
	title_label = Label.new()
	title_label.text = merchant_name.to_upper()
	title_label.add_theme_font_size_override("font_size", 40)
	title_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 18)
	title_label.size = Vector2(960, 48)
	shop_panel.add_child(title_label)
	
	# Greeting ("Whaddya buyin'?")
	greeting_label = Label.new()
	greeting_label.text = "\"" + greeting_text + "\""
	greeting_label.add_theme_font_size_override("font_size", 20)
	greeting_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	greeting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting_label.position = Vector2(0, 66)
	greeting_label.size = Vector2(960, 28)
	shop_panel.add_child(greeting_label)
	
	# Gear count - top right corner chip
	gear_count_label = Label.new()
	gear_count_label.add_theme_font_size_override("font_size", 26)
	gear_count_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	gear_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gear_count_label.position = Vector2(660, 24)
	gear_count_label.size = Vector2(270, 36)
	shop_panel.add_child(gear_count_label)
	
	_build_item_cards()
	
	# Description strip under the cards
	upgrade_description_label = Label.new()
	upgrade_description_label.add_theme_font_size_override("font_size", 21)
	upgrade_description_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	upgrade_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	upgrade_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	upgrade_description_label.position = Vector2(60, 420)
	upgrade_description_label.size = Vector2(840, 70)
	shop_panel.add_child(upgrade_description_label)
	
	# Status / purchase prompt
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 26)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(0, 495)
	status_label.size = Vector2(960, 40)
	shop_panel.add_child(status_label)
	
	# Controls hint
	var controls = Label.new()
	controls.text = "◀ ▶ Browse      [SPACE/X] Buy      [ESC/C] Leave"
	controls.add_theme_font_size_override("font_size", 18)
	controls.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.position = Vector2(0, 555)
	controls.size = Vector2(960, 28)
	shop_panel.add_child(controls)


func _build_item_cards():
	item_cards.clear()
	var count = upgrade_data.size()
	if count == 0:
		return
	
	var card_w = 200
	var card_h = 240
	var spacing = 24
	var total_w = card_w * count + spacing * (count - 1)
	var start_x = (960 - total_w) / 2.0
	var y = 115
	
	for i in range(count):
		var upgrade = upgrade_data[i]
		
		var card = Panel.new()
		card.position = Vector2(start_x + i * (card_w + spacing), y)
		card.size = Vector2(card_w, card_h)
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_UNSELECTED_BG
		style.border_color = Color(0.3, 0.3, 0.38)
		style.set_border_width_all(2)
		style.set_corner_radius_all(10)
		card.add_theme_stylebox_override("panel", style)
		shop_panel.add_child(card)
		
		var name_label = Label.new()
		name_label.text = upgrade.name
		name_label.add_theme_font_size_override("font_size", 21)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.position = Vector2(8, 14)
		name_label.size = Vector2(card_w - 16, 64)
		card.add_child(name_label)
		
		var cost_label = Label.new()
		cost_label.text = str(upgrade.cost) + " ⚙"
		cost_label.add_theme_font_size_override("font_size", 30)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.position = Vector2(0, 130)
		cost_label.size = Vector2(card_w, 40)
		card.add_child(cost_label)
		
		var st = Label.new()
		st.add_theme_font_size_override("font_size", 17)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st.position = Vector2(0, 195)
		st.size = Vector2(card_w, 28)
		card.add_child(st)
		
		item_cards.append({"panel": card, "name": name_label, "cost": cost_label, "status": st})


# ==========================================
# GAME LOOP
# ==========================================

func _process(delta):
	if input_cooldown > 0:
		input_cooldown -= delta
	
	if player_in_range and not shop_open and not _busy:
		if input_cooldown <= 0 and (Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept")):
			_start_interaction()
	
	if shop_open and input_cooldown <= 0:
		handle_shop_input()


func handle_shop_input():
	if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("d_pad_left"):
		current_upgrade_index = maxi(0, current_upgrade_index - 1)
		update_selection()
		input_cooldown = input_cooldown_time
	
	if Input.is_action_just_pressed("right") or Input.is_action_just_pressed("d_pad_right"):
		current_upgrade_index = mini(upgrade_data.size() - 1, current_upgrade_index + 1)
		update_selection()
		input_cooldown = input_cooldown_time
	
	if Input.is_action_just_pressed("ui_accept"):
		attempt_purchase()
		input_cooldown = input_cooldown_time
	
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("heavy_attack"):
		close_shop()
		input_cooldown = input_cooldown_time


# ==========================================
# INTERACTION FLOW: intro dialogue -> coat opens -> shop
# ==========================================

func _start_interaction():
	input_cooldown = 0.4
	
	# Face the player
	if current_player and is_instance_valid(current_player) and _model:
		var to_p = current_player.global_position - global_position
		to_p.y = 0
		if to_p.length() > 0.1:
			_model.rotation.y = atan2(-to_p.x, -to_p.z) - rotation.y
	
	var dm = get_node_or_null("/root/DialogueManager")
	var wants_intro = intro_lines.size() > 0 and (intro_every_time or not _intro_played)
	
	# Belt and braces: if the UI never registered (scene loaded oddly, UI got
	# freed on a scene change...), skip the intro instead of soft-locking.
	if dm and (not dm.dialogue_ui or not is_instance_valid(dm.dialogue_ui)):
		_ensure_dialogue_ui()
		wants_intro = false
	
	if wants_intro and dm:
		_busy = true
		_intro_played = true
		var lines: Array = []
		for text in intro_lines:
			lines.append({"speaker": merchant_name, "text": text, "portrait": portrait})
		if not dm.dialogue_ended.is_connected(_on_intro_ended):
			dm.dialogue_ended.connect(_on_intro_ended, CONNECT_ONE_SHOT)
		dm.start_dialogue_lines(lines)
	else:
		_open_coat_then_shop()


func _on_intro_ended():
	if not _busy:
		return
	_open_coat_then_shop()


func _open_coat_then_shop():
	"""The RE4 moment: coat flies open, THEN the menu appears."""
	_busy = true
	
	# Lock the player down for the reveal
	if current_player and is_instance_valid(current_player):
		set_player_ignore_jump(true)
		current_player.controls_disabled = true
		current_player.velocity = Vector3.ZERO
		var sm = current_player.get_node_or_null("StateMachine")
		if sm and sm.has_method("change_state"):
			sm.change_state("IdleState")
	
	_set_coat(true)
	
	# Let the coat swing finish before the menu drops in
	await get_tree().create_timer(coat_open_time + 0.15, true, false, true).timeout
	if not is_instance_valid(self):
		return
	_busy = false
	open_shop()


# ==========================================
# SHOP MANAGEMENT
# ==========================================

func open_shop():
	if not current_player or upgrade_data.is_empty() or shop_open:
		return
	
	shop_open = true
	current_upgrade_index = 0
	get_tree().paused = true
	
	dim_rect.visible = true
	shop_panel.visible = true
	# Menu pop-in
	shop_panel.scale = Vector2(0.9, 0.9)
	shop_panel.pivot_offset = shop_panel.size / 2.0
	var tween = create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(shop_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	update_selection()
	input_cooldown = 0.45


func close_shop():
	if not shop_open:
		return
	
	shop_open = false
	shop_panel.visible = false
	dim_rect.visible = false
	get_tree().paused = false
	
	_set_coat(false)
	
	set_player_ignore_jump(true)
	if current_player and is_instance_valid(current_player):
		current_player.velocity = Vector3.ZERO
		_reenable_controls_after_grace(current_player)
	
	input_cooldown = 0.5


func _reenable_controls_after_grace(p: CharacterBody3D):
	"""Re-enable player controls a few frames after the shop closes so the
	close-button press can't trigger jump/dash on the unpause frame."""
	await get_tree().create_timer(0.15, true, false, true).timeout
	if is_instance_valid(p) and not shop_open:
		p.controls_disabled = false


# ==========================================
# IGNORE JUMP HELPERS (same pattern as dialogue_trigger.gd)
# ==========================================

func set_player_ignore_jump(should_ignore: bool):
	if not current_player or not is_instance_valid(current_player):
		return
	current_player.set("ignore_next_jump", should_ignore)
	if should_ignore:
		clear_ignore_jump_after_delay()


func clear_ignore_jump_after_delay():
	await get_tree().create_timer(0.01, false, false, true).timeout
	if is_instance_valid(current_player):
		current_player.set("ignore_next_jump", false)


# ==========================================
# SELECTION AND PURCHASE
# ==========================================

func update_selection():
	if upgrade_data.is_empty():
		return
	
	var player_gears = GameManager.get_gear_count()
	gear_count_label.text = str(player_gears) + " ⚙"
	
	for i in range(item_cards.size()):
		var card = item_cards[i]
		var style = card.panel.get_theme_stylebox("panel") as StyleBoxFlat
		var upgrade = upgrade_data[i]
		var owned = GameManager.is_upgrade_purchased(upgrade.key)
		
		if i == current_upgrade_index:
			style.bg_color = COLOR_SELECTED_BG
			style.border_color = Color(0.95, 0.8, 0.45)
			style.set_border_width_all(3)
		else:
			style.bg_color = COLOR_UNSELECTED_BG
			style.border_color = Color(0.3, 0.3, 0.38)
			style.set_border_width_all(2)
		
		if owned:
			card.status.text = "✓ OWNED"
			card.status.add_theme_color_override("font_color", COLOR_PURCHASED)
			card.cost.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		elif player_gears >= upgrade.cost:
			card.status.text = "Available"
			card.status.add_theme_color_override("font_color", COLOR_AFFORDABLE)
			card.cost.add_theme_color_override("font_color", COLOR_AFFORDABLE)
		else:
			card.status.text = "Too pricey"
			card.status.add_theme_color_override("font_color", COLOR_EXPENSIVE)
			card.cost.add_theme_color_override("font_color", COLOR_EXPENSIVE)
	
	var selected = upgrade_data[current_upgrade_index]
	upgrade_description_label.text = selected.description
	
	if GameManager.is_upgrade_purchased(selected.key):
		status_label.text = "✓ Already yours, stranger."
		status_label.add_theme_color_override("font_color", COLOR_PURCHASED)
	elif player_gears >= selected.cost:
		status_label.text = "[SPACE/X]  Buy for " + str(selected.cost) + " ⚙"
		status_label.add_theme_color_override("font_color", COLOR_AFFORDABLE)
	else:
		status_label.text = "Not enough gears... come back later. (" + str(selected.cost - player_gears) + " short)"
		status_label.add_theme_color_override("font_color", COLOR_EXPENSIVE)


func attempt_purchase():
	if upgrade_data.is_empty():
		return
	
	var selected = upgrade_data[current_upgrade_index]
	if GameManager.is_upgrade_purchased(selected.key):
		return
	
	if GameManager.purchase_upgrade(selected.key):
		status_label.text = "\"Heh heh heh... thank you!\""
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		# Purchase flash on the card
		var card = item_cards[current_upgrade_index]
		var style = card.panel.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = Color(0.2, 0.4, 0.2)
		await get_tree().create_timer(0.15, true, false, true).timeout
		update_selection()
	else:
		status_label.text = "\"Not enough cash... stranger.\""
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


# ==========================================
# AREA DETECTION
# ==========================================

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		current_player = body
		interaction_label.visible = true


func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		if shop_open:
			close_shop()
		else:
			set_player_ignore_jump(false)
			if _coat_is_open:
				_set_coat(false)
		current_player = null
		interaction_label.visible = false
