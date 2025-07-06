extends StaticBody3D

# Export variable so you can set different text for each sign in the editor
@export_multiline var sign_text: String = "Welcome to the adventure!\nPress E to continue your journey."

# Reference to the player when they're in range
var player_in_range: bool = false
var player_reference: Node = null

# UI elements
var interaction_label: Label
var sign_ui: Control
var sign_label: Label
var background_panel: Panel

func _ready():
	# Connect the Area3D signals
	var area = $Area3D
	area.body_entered.connect(_on_area_3d_body_entered)
	area.body_exited.connect(_on_area_3d_body_exited)
	
	# Create UI elements
	create_ui()

func create_ui():
	# Create canvas layer for UI
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	# Interaction prompt (similar to merchant)
	interaction_label = Label.new()
	interaction_label.text = "Press E to read sign"
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.position = Vector2(50, 50)
	interaction_label.visible = false
	canvas_layer.add_child(interaction_label)
	
	# Create the main sign UI container
	sign_ui = Control.new()
	sign_ui.name = "SignUI"
	sign_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sign_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign_ui.visible = false
	
	# Create background panel
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	background_panel.size = Vector2(600, 300)
	background_panel.position = Vector2(-300, -150)
	
	# Style the background panel
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.1, 0.1, 0.1, 0.9)  # Dark background with transparency
	style_box.border_width_left = 3
	style_box.border_width_right = 3
	style_box.border_width_top = 3
	style_box.border_width_bottom = 3
	style_box.border_color = Color(0.8, 0.6, 0.2, 1.0)  # Golden border
	style_box.corner_radius_top_left = 10
	style_box.corner_radius_top_right = 10
	style_box.corner_radius_bottom_left = 10
	style_box.corner_radius_bottom_right = 10
	background_panel.add_theme_stylebox_override("panel", style_box)
	
	# Create the text label
	sign_label = Label.new()
	sign_label.name = "SignLabel"
	sign_label.text = sign_text
	sign_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sign_label.add_theme_font_size_override("font_size", 18)
	sign_label.add_theme_color_override("font_color", Color.WHITE)
	sign_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	sign_label.add_theme_constant_override("shadow_offset_x", 2)
	sign_label.add_theme_constant_override("shadow_offset_y", 2)
	
	# Add margin to the label
	var margin_container = MarginContainer.new()
	margin_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 20)
	margin_container.add_theme_constant_override("margin_right", 20)
	margin_container.add_theme_constant_override("margin_top", 20)
	margin_container.add_theme_constant_override("margin_bottom", 20)
	
	# Build the UI hierarchy
	sign_ui.add_child(background_panel)
	background_panel.add_child(margin_container)
	margin_container.add_child(sign_label)
	
	# Add sign UI to the canvas layer
	canvas_layer.add_child(sign_ui)

func _process(delta):
	# Check for E key press when player is in range (similar to merchant)
	if player_in_range and Input.is_action_just_pressed("interact"):
		toggle_sign()

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		player_reference = body
		interaction_label.visible = true
		print("Player entered sign area - press E to read")

func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		player_reference = null
		interaction_label.visible = false
		hide_sign()
		print("Player left sign area")

func toggle_sign():
	if sign_ui.visible:
		hide_sign()
	else:
		show_sign()

func show_sign():
	if sign_ui:
		# Update the text in case it was changed in the editor
		sign_label.text = sign_text
		sign_ui.visible = true
		
		# Optional: Add a fade-in effect
		var tween = create_tween()
		sign_ui.modulate.a = 0.0
		tween.tween_property(sign_ui, "modulate:a", 1.0, 0.3)

func hide_sign():
	if sign_ui:
		# Optional: Add a fade-out effect
		var tween = create_tween()
		tween.tween_property(sign_ui, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func(): sign_ui.visible = false)

# Function to update sign text dynamically (optional)
func set_sign_text(new_text: String):
	sign_text = new_text
	if sign_label:
		sign_label.text = sign_text
		
# Function to get the current sign text (optional)
func get_sign_text() -> String:
	return sign_text
