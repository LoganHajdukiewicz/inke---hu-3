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

func _ready():
	# Set process mode to always so UI works even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	setup_paint_ui()
	
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

func update_paint_display(paint_type: int):
	"""Update the paint meter color and name when paint type changes"""
	if not paint_fill_rect or not paint_name_label:
		return
	
	# Get color for this paint type
	var color = paint_colors.get(paint_type, Color.WHITE)
	
	# Update fill color
	paint_fill_rect.color = color
	
	# Update name label
	paint_name_label.text = paint_names.get(paint_type, "UNKNOWN")
	paint_name_label.add_theme_color_override("font_color", color)
	
	# Create a quick pulse effect on paint type change
	create_switch_effect()

func update_paint_fill(current: int, maximum: int):
	"""Update the fill level of the paint meter"""
	if not paint_fill_rect:
		return
	
	# Calculate fill percentage
	var fill_percentage = clamp(float(current) / float(maximum), 0.0, 1.0)
	
	# Update fill rect size (fills from bottom up)
	var new_height = meter_height * fill_percentage
	paint_fill_rect.size.y = new_height
	paint_fill_rect.position.y = 10 + (meter_height - new_height)

func create_switch_effect():
	"""Visual effect when switching paint types"""
	if not paint_meter_container:
		return
	
	# Scale pulse
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
	
	# Quick flash
	var original_color = paint_fill_rect.color
	var flash_color = Color(original_color.r + 0.3, original_color.g + 0.3, original_color.b + 0.3, 1.0)
	
	var tween = create_tween()
	tween.tween_property(paint_fill_rect, "color", flash_color, 0.05)
	tween.tween_property(paint_fill_rect, "color", original_color, 0.2)

# Signal handlers
func _on_paint_changed(new_paint: int, _previous_paint: int):
	"""Called when player switches paint type"""
	update_paint_display(new_paint)

func _on_paint_amount_changed(current: int, maximum: int):
	"""Called when paint amount changes"""
	update_paint_fill(current, maximum)

func _on_paint_used(paint_type: int):
	"""Called when player uses paint"""
	create_use_effect()
	# Update display in case it changed
	update_paint_display(paint_type)
