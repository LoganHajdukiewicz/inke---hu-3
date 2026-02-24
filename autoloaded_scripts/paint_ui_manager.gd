extends CanvasLayer
class_name PaintUIManager

# UI References
var paint_meter_container: Control
var paint_fill_rect: ColorRect
var paint_background_rect: ColorRect
var paint_name_label: Label

# Paint colors matching PaintManager
var paint_colors: Dictionary = {
	0: Color(0.0, 0.8, 1.0),      # SAVE - Cyan
	1: Color(0.0, 1.0, 0.0),      # HEAL - Green
	2: Color(1.0, 0.8, 0.0),       # FLY - Gold/Yellow
	3: Color(1.0, 0.2, 0.0)        # COMBAT - Red/Orange
}

# Paint names matching PaintManager
var paint_names: Dictionary = {
	0: "SAVE",
	1: "HEAL",
	2: "FLY",
	3: "COMBAT"
}

# UI Configuration
var meter_width: float = 60.0
var meter_height: float = 300.0
var meter_margin_left: float = 40.0
var meter_margin_bottom: float = 100.0
var label_margin_bottom: float = 20.0

# Visibility state
var _gameplay_visible: bool = false

func _ready():
	# Set process mode to always so UI works even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	setup_paint_ui()

	# Hide immediately — show only once a Player is confirmed in the scene
	_set_gameplay_visible(false)

	# Connect to PaintManager signals
	var paint_manager = get_node_or_null("/root/PaintManager")
	if paint_manager:
		if paint_manager.has_signal("paint_changed"):
			paint_manager.paint_changed.connect(_on_paint_changed)
		if paint_manager.has_signal("paint_amount_changed"):
			paint_manager.paint_amount_changed.connect(_on_paint_amount_changed)
		if paint_manager.has_signal("paint_used"):
			paint_manager.paint_used.connect(_on_paint_used)

		# Initialize UI with current paint state
		update_paint_display(paint_manager.current_paint)
		update_paint_fill(paint_manager.current_paint_amount, paint_manager.max_paint_amount)
	else:
		print("PaintUIManager: Warning - PaintManager not found!")

	# Connect to GameManager signals to track player spawning/scene changes
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("player_spawned"):
			game_manager.player_spawned.connect(_on_player_spawned)

	# Connect to CutsceneManager signals if it exposes them
	var cutscene_manager = get_node_or_null("/root/CutsceneManager")
	if cutscene_manager:
		if cutscene_manager.has_signal("cutscene_started"):
			cutscene_manager.cutscene_started.connect(_on_cutscene_started)
		if cutscene_manager.has_signal("cutscene_ended"):
			cutscene_manager.cutscene_ended.connect(_on_cutscene_ended)

	# Connect to scene-change notification so we can re-evaluate on every load
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)

	# Run an initial check in case we're already in a gameplay scene
	_evaluate_visibility()

# ---------------------------------------------------------------------------
# Visibility helpers
# ---------------------------------------------------------------------------

func _set_gameplay_visible(visible: bool) -> void:
	"""Show or hide the entire paint UI layer."""
	_gameplay_visible = visible
	if paint_meter_container:
		paint_meter_container.visible = visible

func _evaluate_visibility() -> void:
	"""Show the UI only when a Player node exists in the current scene."""
	var players = get_tree().get_nodes_in_group("Player")
	var has_player = players.size() > 0 and is_instance_valid(players[0])
	_set_gameplay_visible(has_player)

# ---------------------------------------------------------------------------
# Signal callbacks for player / scene / cutscene events
# ---------------------------------------------------------------------------

func _on_player_spawned(_player: CharacterBody3D) -> void:
	"""GameManager signals that a player just entered the scene."""
	_set_gameplay_visible(true)

func _on_node_added(node: Node) -> void:
	"""A node was added to the tree — check if it is the player."""
	if node.is_in_group("Player"):
		_set_gameplay_visible(true)

func _on_node_removed(node: Node) -> void:
	"""A node was removed from the tree — hide UI if the player left."""
	if node.is_in_group("Player"):
		# Defer so the group is fully updated before we check
		call_deferred("_evaluate_visibility")

func _on_cutscene_started() -> void:
	"""Hide the paint UI while a cutscene plays."""
	_set_gameplay_visible(false)

func _on_cutscene_ended() -> void:
	"""Restore the paint UI after the cutscene, only if a player is present."""
	_evaluate_visibility()

# ---------------------------------------------------------------------------
# UI setup (unchanged)
# ---------------------------------------------------------------------------

func setup_paint_ui():
	"""Create the paint meter UI on the left side of the screen"""

	# Container for the entire paint meter system
	paint_meter_container = Control.new()
	paint_meter_container.name = "PaintMeterContainer"
	paint_meter_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	paint_meter_container.position = Vector2(meter_margin_left, -meter_margin_bottom - meter_height)
	paint_meter_container.size = Vector2(meter_width, meter_height + 60)  # Extra space for label
	add_child(paint_meter_container)

	# Paint type name label (above meter)
	paint_name_label = Label.new()
	paint_name_label.name = "PaintNameLabel"
	paint_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paint_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	paint_name_label.add_theme_font_size_override("font_size", 24)
	paint_name_label.add_theme_color_override("font_color", Color.WHITE)
	paint_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	paint_name_label.add_theme_constant_override("outline_size", 4)
	paint_name_label.text = "HEAL"
	paint_name_label.position = Vector2(0, -label_margin_bottom)
	paint_name_label.size = Vector2(meter_width, 30)
	paint_meter_container.add_child(paint_name_label)

	# Background for paint meter (dark/empty state)
	paint_background_rect = ColorRect.new()
	paint_background_rect.name = "PaintBackground"
	paint_background_rect.color = Color(0.1, 0.1, 0.1, 0.8)
	paint_background_rect.position = Vector2(0, 10)
	paint_background_rect.size = Vector2(meter_width, meter_height)
	paint_meter_container.add_child(paint_background_rect)

	# Border for paint meter
	var border = ColorRect.new()
	border.name = "PaintBorder"
	border.color = Color(1.0, 1.0, 1.0, 0.3)
	border.position = Vector2(-2, 8)
	border.size = Vector2(meter_width + 4, meter_height + 4)
	border.z_index = -1
	paint_meter_container.add_child(border)

	# Fill rect (this is what changes size and color)
	paint_fill_rect = ColorRect.new()
	paint_fill_rect.name = "PaintFill"
	paint_fill_rect.color = Color(0.0, 1.0, 0.0, 1.0)  # Default green (HEAL)
	paint_fill_rect.position = Vector2(0, 10)
	paint_fill_rect.size = Vector2(meter_width, meter_height)
	paint_meter_container.add_child(paint_fill_rect)

	print("Paint UI created successfully!")

# ---------------------------------------------------------------------------
# Display update methods (unchanged)
# ---------------------------------------------------------------------------

func update_paint_display(paint_type: int):
	"""Update the paint meter color and name when paint type changes"""
	if not paint_fill_rect or not paint_name_label:
		return

	var color = paint_colors.get(paint_type, Color.WHITE)

	paint_fill_rect.color = color

	paint_name_label.text = paint_names.get(paint_type, "UNKNOWN")
	paint_name_label.add_theme_color_override("font_color", color)

	create_switch_effect()

func update_paint_fill(current: int, maximum: int):
	"""Update the fill level of the paint meter"""
	if not paint_fill_rect:
		return

	var fill_percentage = clamp(float(current) / float(maximum), 0.0, 1.0)

	var new_height = meter_height * fill_percentage
	paint_fill_rect.size.y = new_height
	paint_fill_rect.position.y = 10 + (meter_height - new_height)

func create_switch_effect():
	"""Visual effect when switching paint types"""
	if not paint_meter_container:
		return

	var original_scale = paint_meter_container.scale
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(paint_meter_container, "scale", original_scale * 1.2, 0.15)
	tween.tween_property(paint_meter_container, "scale", original_scale, 0.15)

func create_use_effect():
	"""Visual effect when using paint"""
	if not paint_fill_rect:
		return

	var original_color = paint_fill_rect.color
	var flash_color = Color(original_color.r + 0.3, original_color.g + 0.3, original_color.b + 0.3, 1.0)

	var tween = create_tween()
	tween.tween_property(paint_fill_rect, "color", flash_color, 0.05)
	tween.tween_property(paint_fill_rect, "color", original_color, 0.2)

# ---------------------------------------------------------------------------
# Signal handlers
# ---------------------------------------------------------------------------

func _on_paint_changed(new_paint: int, _previous_paint: int):
	update_paint_display(new_paint)

func _on_paint_amount_changed(current: int, maximum: int):
	update_paint_fill(current, maximum)

func _on_paint_used(paint_type: int):
	create_use_effect()
	update_paint_display(paint_type)
