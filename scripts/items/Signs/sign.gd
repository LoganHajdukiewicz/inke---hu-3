extends StaticBody3D

@export var use_dialogic: bool = false
@export var dialogic_timeline: String = ""

# Export variable so you can set different text for each sign in the editor
@export_multiline var sign_text: String = "Welcome to the adventure!\nPress E to continue your journey."

# Reference to the player when they're in range
var player_in_range: bool = false
var player_reference: Node = null

# UI elements
var interaction_button: Control
var sign_ui: Control
var sign_label: Label
var background_panel: Panel

# 3D floating button variables
var floating_button: Node3D
var button_mesh: MeshInstance3D
var button_label: Label3D
var bob_tween: Tween

func _ready():
	# Connect the Area3D signals
	var area = $Area3D
	area.body_entered.connect(_on_area_3d_body_entered)
	area.body_exited.connect(_on_area_3d_body_exited)
	
	# Create floating 3D button
	create_floating_button()
	
	# Create UI elements only if not using Dialogic
	if not use_dialogic:
		create_ui()

func create_floating_button():
	# Create the floating button node
	floating_button = Node3D.new()
	floating_button.name = "FloatingButton"
	add_child(floating_button)
	
	# Position it above the sign
	floating_button.position = Vector3(0, 2.5, 0)
	
	# Remove the background quad mesh completely - we don't want it anymore
	
	# Create the 3D label for 'E' with bold white text and black outline
	button_label = Label3D.new()
	button_label.text = "E"
	button_label.font_size = 64
	button_label.modulate = Color.WHITE
	button_label.outline_size = 16  # Thicker black outline
	button_label.outline_modulate = Color.BLACK
	button_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	button_label.position = Vector3(0, 0, 0)  # Centered position
	
	floating_button.add_child(button_label)
	
	# Hide the button initially
	floating_button.visible = false

func create_ui():
	# Create canvas layer for UI
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
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

func start_bobbing_animation():
	# Kill any existing tween
	if bob_tween:
		bob_tween.kill()
	
	# Create new tween for bobbing animation
	bob_tween = create_tween()
	bob_tween.set_loops()
	
	# Animate the floating button up and down
	var start_pos = floating_button.position
	var bob_height = 0.3
	
	bob_tween.tween_property(floating_button, "position", start_pos + Vector3(0, bob_height, 0), 1.0)
	bob_tween.tween_property(floating_button, "position", start_pos - Vector3(0, bob_height, 0), 1.0)

func stop_bobbing_animation():
	if bob_tween:
		bob_tween.kill()
	
	# Reset position
	floating_button.position = Vector3(0, 2.5, 0)

func _process(_delta):
	# Check for E key press when player is in range
	if player_in_range and Input.is_action_just_pressed("interact"):
		if use_dialogic:
			start_dialogic_timeline()
		else:
			toggle_sign()

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		player_reference = body
		
		# Show floating button and start bobbing
		floating_button.visible = true
		start_bobbing_animation()
		
		print("Player entered sign area - press E to read")

func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		player_reference = null
		
		# Hide floating button and stop bobbing
		floating_button.visible = false
		stop_bobbing_animation()
		
		if not use_dialogic:
			hide_sign()
		
		print("Player left sign area")

# NEW: Function to start Dialogic timeline
func start_dialogic_timeline():
	if dialogic_timeline != "":
		Dialogic.start(dialogic_timeline)
		print("Started Dialogic timeline: " + dialogic_timeline)
	else:
		print("No Dialogic timeline set for this sign!")

# Original sign functions (for non-Dialogic mode)
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

# NEW: Function to set Dialogic timeline dynamically
func set_dialogic_timeline(timeline_name: String):
	dialogic_timeline = timeline_name
	use_dialogic = true

# NEW: Function to switch between modes
func set_use_dialogic(use_dialog: bool):
	use_dialogic = use_dialog
	if not use_dialogic and not sign_ui:
		create_ui()
		
# Function to get the current sign text (optional)
func get_sign_text() -> String:
	return sign_text
