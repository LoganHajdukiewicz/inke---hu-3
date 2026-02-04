extends CharacterBody3D

# ==========================================
# UPGRADE CONFIGURATION
# ==========================================

# Powerup types enum
enum PowerupType {
	DOUBLE_JUMP,
	WALL_JUMP, 
	DASH, 
	SPEED_UPGRADE,
	HEALTH_UPGRADE, 
	DAMAGE_UPGRADE
}

# Inspector-configurable upgrades
@export_group("Available Upgrades")
@export var available_upgrades: Array[PowerupType] = [
	PowerupType.DOUBLE_JUMP,
	PowerupType.WALL_JUMP,
	PowerupType.DASH
]

@export_group("Merchant Settings")
@export var merchant_name: String = "Merchant"
@export var greeting_text: String = "Welcome to my shop!"

# ==========================================
# STATE VARIABLES
# ==========================================

var player_in_range: bool = false
var current_player: CharacterBody3D = null
var shop_open: bool = false

# Current selection
var current_upgrade_index: int = 0
var upgrade_data: Array = []  # Will store upgrade info dictionaries

# UI references
var canvas_layer: CanvasLayer
var interaction_label: Label
var shop_panel: Panel
var title_label: Label
var gear_count_label: Label
var upgrade_name_label: Label
var upgrade_description_label: Label
var upgrade_cost_label: Label
var status_label: Label
var navigation_hint_label: Label
var controls_hint_label: Label

# Selection indicator
var selection_indicators: Array = []

# UI Colors
var COLOR_PURCHASED = Color(0.3, 0.8, 0.3)
var COLOR_AFFORDABLE = Color(0.9, 0.9, 0.2)
var COLOR_EXPENSIVE = Color(0.8, 0.3, 0.3)
var COLOR_SELECTED = Color(0.2, 0.6, 1.0)
var COLOR_UNSELECTED = Color(0.4, 0.4, 0.4)

# Input cooldown - FIXED: Increased to prevent accidental input
var input_cooldown: float = 0.0
var input_cooldown_time: float = 0.2  # Base cooldown time

# ==========================================
# INITIALIZATION
# ==========================================

func _ready():
	setup_upgrade_data()
	setup_ui()
	
	# Make sure merchant can process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect Area3D signals safely
	if has_node("Area3D"):
		$Area3D.body_entered.connect(_on_area_3d_body_entered)
		$Area3D.body_exited.connect(_on_area_3d_body_exited)
	else:
		print("WARNING: Merchant needs an Area3D child node!")

func setup_upgrade_data():
	"""Build upgrade data array from available_upgrades"""
	upgrade_data.clear()
	
	for powerup_type in available_upgrades:
		var upgrade_key = get_upgrade_key(powerup_type)
		if upgrade_key != "":
			var data = {
				"type": powerup_type,
				"key": upgrade_key,
				"name": GameManager.get_upgrade_name(upgrade_key),
				"description": GameManager.get_upgrade_description(upgrade_key),
				"cost": GameManager.get_upgrade_cost(upgrade_key)
			}
			upgrade_data.append(data)
	
	print("Merchant loaded ", upgrade_data.size(), " upgrades")

func get_upgrade_key(powerup_type: PowerupType) -> String:
	"""Convert PowerupType enum to string key for GameManager"""
	match powerup_type:
		PowerupType.DOUBLE_JUMP:
			return "double_jump"
		PowerupType.WALL_JUMP:
			return "wall_jump"
		PowerupType.DASH:
			return "dash"
		PowerupType.SPEED_UPGRADE:
			return "speed_upgrade"
		PowerupType.HEALTH_UPGRADE:
			return "health_upgrade"
		PowerupType.DAMAGE_UPGRADE:
			return "damage_upgrade"
		_:
			return ""

# ==========================================
# UI SETUP
# ==========================================

func setup_ui():
	"""Create a polished, controller-friendly shop UI"""
	canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	# CRITICAL: Make sure UI processes even when game is paused
	canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Interaction prompt (visible when near merchant)
	interaction_label = Label.new()
	interaction_label.text = "[SPACE] or [A] Talk to " + merchant_name
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_label.position = Vector2(860, 900)
	interaction_label.size = Vector2(200, 50)
	interaction_label.visible = false
	canvas_layer.add_child(interaction_label)
	
	# Main shop panel
	shop_panel = Panel.new()
	shop_panel.size = Vector2(1200, 700)
	shop_panel.position = Vector2(360, 190)
	shop_panel.visible = false
	
	# Create a semi-transparent dark background
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	panel_style.border_color = Color(0.4, 0.6, 0.8, 1.0)
	panel_style.border_width_left = 4
	panel_style.border_width_right = 4
	panel_style.border_width_top = 4
	panel_style.border_width_bottom = 4
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	shop_panel.add_theme_stylebox_override("panel", panel_style)
	
	canvas_layer.add_child(shop_panel)
	
	# Title
	title_label = Label.new()
	title_label.text = merchant_name + "'s Shop"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.position = Vector2(0, 20)
	title_label.size = Vector2(1200, 60)
	shop_panel.add_child(title_label)
	
	# Greeting
	var greeting_label = Label.new()
	greeting_label.text = greeting_text
	greeting_label.add_theme_font_size_override("font_size", 20)
	greeting_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	greeting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	greeting_label.position = Vector2(0, 80)
	greeting_label.size = Vector2(1200, 30)
	shop_panel.add_child(greeting_label)
	
	# Gear count
	gear_count_label = Label.new()
	gear_count_label.add_theme_font_size_override("font_size", 28)
	gear_count_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	gear_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gear_count_label.position = Vector2(0, 120)
	gear_count_label.size = Vector2(1200, 40)
	shop_panel.add_child(gear_count_label)
	
	# Upgrades list container
	var upgrades_container_y = 180
	setup_upgrade_list(upgrades_container_y)
	
	# Selected upgrade details panel
	var details_y = 180
	setup_details_panel(details_y)
	
	# Navigation hints
	navigation_hint_label = Label.new()
	navigation_hint_label.text = "◀ D-Pad Left/Right ▶  Navigate"
	navigation_hint_label.add_theme_font_size_override("font_size", 22)
	navigation_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	navigation_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation_hint_label.position = Vector2(0, 600)
	navigation_hint_label.size = Vector2(1200, 30)
	shop_panel.add_child(navigation_hint_label)
	
	# Controls hint
	controls_hint_label = Label.new()
	controls_hint_label.text = "[A] or [SPACE] Purchase  |  [B] or [X] Close"
	controls_hint_label.add_theme_font_size_override("font_size", 22)
	controls_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	controls_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_hint_label.position = Vector2(0, 640)
	controls_hint_label.size = Vector2(1200, 30)
	shop_panel.add_child(controls_hint_label)

func setup_upgrade_list(start_y: int):
	"""Create horizontal upgrade selection list"""
	var container_width = 1160
	var container_x = 20
	var item_width = 160
	var item_height = 200
	var spacing = 20
	
	# Calculate total width needed and starting position
	var total_items = upgrade_data.size()
	var total_width = (item_width * total_items) + (spacing * (total_items - 1))
	var start_x : float = container_x + (container_width - total_width) / 2
	
	for i in range(upgrade_data.size()):
		var upgrade = upgrade_data[i]
		var x_pos = start_x + (i * (item_width + spacing))
		
		# Create upgrade item panel
		var item_panel = Panel.new()
		item_panel.size = Vector2(item_width, item_height)
		item_panel.position = Vector2(x_pos, start_y)
		
		var item_style = StyleBoxFlat.new()
		item_style.bg_color = COLOR_UNSELECTED
		item_style.border_color = Color(0.3, 0.3, 0.4)
		item_style.border_width_left = 2
		item_style.border_width_right = 2
		item_style.border_width_top = 2
		item_style.border_width_bottom = 2
		item_style.corner_radius_top_left = 8
		item_style.corner_radius_top_right = 8
		item_style.corner_radius_bottom_left = 8
		item_style.corner_radius_bottom_right = 8
		item_panel.add_theme_stylebox_override("panel", item_style)
		
		shop_panel.add_child(item_panel)
		selection_indicators.append(item_panel)
		
		# Upgrade icon/name
		var name_label = Label.new()
		name_label.text = upgrade.name
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		name_label.position = Vector2(5, 10)
		name_label.size = Vector2(item_width - 10, 60)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_panel.add_child(name_label)
		
		# Cost
		var cost_label = Label.new()
		cost_label.text = str(upgrade.cost) + " ⚙"
		cost_label.add_theme_font_size_override("font_size", 24)
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.position = Vector2(0, 120)
		cost_label.size = Vector2(item_width, 30)
		item_panel.add_child(cost_label)
		
		# Status indicator
		var status = Label.new()
		status.add_theme_font_size_override("font_size", 16)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status.position = Vector2(0, 160)
		status.size = Vector2(item_width, 30)
		item_panel.add_child(status)

func setup_details_panel(start_y: int):
	"""Create detailed info panel for selected upgrade"""
	var details_panel = Panel.new()
	details_panel.size = Vector2(1160, 380)
	details_panel.position = Vector2(20, start_y)
	
	var details_style = StyleBoxFlat.new()
	details_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	details_style.border_color = Color(0.3, 0.5, 0.7)
	details_style.border_width_left = 2
	details_style.border_width_right = 2
	details_style.border_width_top = 2
	details_style.border_width_bottom = 2
	details_style.corner_radius_top_left = 8
	details_style.corner_radius_top_right = 8
	details_style.corner_radius_bottom_left = 8
	details_style.corner_radius_bottom_right = 8
	details_panel.add_theme_stylebox_override("panel", details_style)
	
	shop_panel.add_child(details_panel)
	
	# Selected upgrade name
	upgrade_name_label = Label.new()
	upgrade_name_label.add_theme_font_size_override("font_size", 36)
	upgrade_name_label.add_theme_color_override("font_color", COLOR_SELECTED)
	upgrade_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_name_label.position = Vector2(20, 20)
	upgrade_name_label.size = Vector2(1120, 50)
	details_panel.add_child(upgrade_name_label)
	
	# Description
	upgrade_description_label = Label.new()
	upgrade_description_label.add_theme_font_size_override("font_size", 24)
	upgrade_description_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	upgrade_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	upgrade_description_label.position = Vector2(40, 90)
	upgrade_description_label.size = Vector2(1080, 120)
	upgrade_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_panel.add_child(upgrade_description_label)
	
	# Cost display
	upgrade_cost_label = Label.new()
	upgrade_cost_label.add_theme_font_size_override("font_size", 32)
	upgrade_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_cost_label.position = Vector2(20, 230)
	upgrade_cost_label.size = Vector2(1120, 50)
	details_panel.add_child(upgrade_cost_label)
	
	# Status message
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 28)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.position = Vector2(20, 300)
	status_label.size = Vector2(1120, 50)
	details_panel.add_child(status_label)

# ==========================================
# GAME LOOP
# ==========================================

func _process(delta):
	# Update input cooldown
	if input_cooldown > 0:
		input_cooldown -= delta
	
	# FIXED: Only check for interaction when shop is NOT open
	if player_in_range and not shop_open:
		# Only check for ui_accept if cooldown has passed
		if input_cooldown <= 0 and Input.is_action_just_pressed("ui_accept"):
			open_shop()
	
	# FIXED: Only handle shop input when shop is actually open AND cooldown expired
	if shop_open and input_cooldown <= 0:
		handle_shop_input()

func handle_shop_input():
	"""Handle controller/keyboard input for shop navigation"""
	# SAFETY CHECK: Don't process if cooldown is active
	if input_cooldown > 0:
		return
	
	# Navigate left
	if Input.is_action_just_pressed("left") or Input.is_action_just_pressed("d_pad_left"):
		current_upgrade_index = max(0, current_upgrade_index - 1)
		update_selection()
		input_cooldown = input_cooldown_time
	
	# Navigate right
	if Input.is_action_just_pressed("right") or Input.is_action_just_pressed("d_pad_right"):
		current_upgrade_index = min(upgrade_data.size() - 1, current_upgrade_index + 1)
		update_selection()
		input_cooldown = input_cooldown_time
	
	# Purchase (A button / Space / ui_accept)
	if Input.is_action_just_pressed("ui_accept"):
		attempt_purchase()
		input_cooldown = input_cooldown_time
	
	# Close shop (B button, X button, dash, heavy_attack, or ui_cancel)
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("heavy_attack"):
		close_shop()
		input_cooldown = input_cooldown_time

# ==========================================
# SHOP MANAGEMENT
# ==========================================

func open_shop():
	if not current_player or upgrade_data.is_empty():
		print("Cannot open shop - no player or no upgrades")
		return
	
	if shop_open:
		print("Shop already open!")
		return
	
	print("Opening shop...")
	
	# FIX 1: Always set ignore_next_jump with guaranteed cleanup
	if current_player.has_method("set"):
		current_player.set("ignore_next_jump", true)
		print("Set ignore_next_jump = true")
	
	# FIX 2: Disable player physics processing to prevent movement behind menu
	if current_player.has_method("set_physics_process"):
		current_player.set_physics_process(false)
		print("Disabled player physics processing")
	
	shop_open = true
	current_upgrade_index = 0
	
	# Pause the game
	get_tree().paused = true
	
	# Show UI
	shop_panel.visible = true
	
	# Update selection to show current state
	update_selection()
	
	# FIXED: Longer initial cooldown to prevent any inputs from bleeding through
	input_cooldown = 0.5
	
	print(merchant_name + "'s shop opened - Game paused: ", get_tree().paused)

func close_shop():
	if not shop_open:
		return
	
	print("Closing shop...")
	shop_open = false
	shop_panel.visible = false
	
	# Unpause the game
	get_tree().paused = false
	
	# FIX 1: ALWAYS clear ignore_next_jump flag when closing
	ensure_player_can_jump()
	
	# FIX 2: Re-enable player physics processing
	if current_player and is_instance_valid(current_player):
		if current_player.has_method("set_physics_process"):
			current_player.set_physics_process(true)
			print("Re-enabled player physics processing")
	
	# FIXED: Longer cooldown to prevent immediate re-opening or accidental jumps
	input_cooldown = 0.5
	
	print(merchant_name + "'s shop closed - Game paused: ", get_tree().paused)

func ensure_player_can_jump():
	"""Ensures the ignore_next_jump flag is cleared so player can jump"""
	if not current_player or not is_instance_valid(current_player):
		return
	
	if current_player.has_method("set"):
		current_player.set("ignore_next_jump", false)
		print("Cleared ignore_next_jump = false")
	
	# Double-check with a short delay as extra safety
	get_tree().create_timer(0.1, false, false, true).timeout.connect(func():
		if is_instance_valid(current_player) and current_player.has_method("set"):
			current_player.set("ignore_next_jump", false)
			print("Double-checked: ignore_next_jump = false")
	)

func update_selection():
	"""Update UI to reflect current selection"""
	if upgrade_data.is_empty():
		return
	
	var player_gears = GameManager.get_gear_count()
	gear_count_label.text = "Your Gears: " + str(player_gears) + " ⚙"
	
	var selected_upgrade = upgrade_data[current_upgrade_index]
	
	var is_purchased = GameManager.is_upgrade_purchased(selected_upgrade.key)
	var can_afford = player_gears >= selected_upgrade.cost
	
	# Update selection indicators
	for i in range(selection_indicators.size()):
		var panel = selection_indicators[i]
		var style = panel.get_theme_stylebox("panel") as StyleBoxFlat
		
		if i == current_upgrade_index:
			# Selected item
			style.bg_color = COLOR_SELECTED
			style.border_color = Color(0.5, 0.8, 1.0)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
		else:
			# Unselected item
			style.bg_color = COLOR_UNSELECTED
			style.border_color = Color(0.3, 0.3, 0.4)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		
		# Update status text for this upgrade
		var upgrade = upgrade_data[i]
		var status_label_node = panel.get_child(2)  # Third child is status label
		if GameManager.is_upgrade_purchased(upgrade.key):
			status_label_node.text = "✓ OWNED"
			status_label_node.add_theme_color_override("font_color", COLOR_PURCHASED)
		elif player_gears >= upgrade.cost:
			status_label_node.text = "Available"
			status_label_node.add_theme_color_override("font_color", COLOR_AFFORDABLE)
		else:
			status_label_node.text = "Not enough"
			status_label_node.add_theme_color_override("font_color", COLOR_EXPENSIVE)
	
	# Update details panel
	upgrade_name_label.text = selected_upgrade.name
	upgrade_description_label.text = selected_upgrade.description
	upgrade_cost_label.text = "Cost: " + str(selected_upgrade.cost) + " ⚙"
	
	if is_purchased:
		upgrade_cost_label.add_theme_color_override("font_color", COLOR_PURCHASED)
		status_label.text = "✓ Already Purchased!"
		status_label.add_theme_color_override("font_color", COLOR_PURCHASED)
	elif can_afford:
		upgrade_cost_label.add_theme_color_override("font_color", COLOR_AFFORDABLE)
		status_label.text = "Press [A] or [SPACE] to Purchase"
		status_label.add_theme_color_override("font_color", COLOR_AFFORDABLE)
	else:
		upgrade_cost_label.add_theme_color_override("font_color", COLOR_EXPENSIVE)
		var needed = selected_upgrade.cost - player_gears
		status_label.text = "Need " + str(needed) + " more gears"
		status_label.add_theme_color_override("font_color", COLOR_EXPENSIVE)

func attempt_purchase():
	"""Try to purchase the currently selected upgrade"""
	if upgrade_data.is_empty():
		return
	
	var selected_upgrade = upgrade_data[current_upgrade_index]
	
	# Check if already purchased
	if GameManager.is_upgrade_purchased(selected_upgrade.key):
		print("Upgrade already purchased!")
		return
	
	# Attempt purchase through GameManager
	if GameManager.purchase_upgrade(selected_upgrade.key):
		print(selected_upgrade.name + " purchased successfully!")
		
		# Show purchase success feedback
		status_label.text = "✓ Purchase Successful!"
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		
		# Update UI
		update_selection()
	else:
		print("Not enough gears to purchase " + selected_upgrade.name)
		
		# Show error feedback
		status_label.text = "✗ Not Enough Gears!"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

# ==========================================
# AREA DETECTION
# ==========================================

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		current_player = body
		interaction_label.visible = true
		print("Player entered merchant range")

func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		
		# FIX 1: If shop is open when player leaves, close it AND clean up flag
		if shop_open:
			print("Player left while shop open - force closing with cleanup")
			close_shop()
		else:
			# FIX 1: Even if shop wasn't open, ensure flag is clean
			ensure_player_can_jump()
		
		current_player = null
		interaction_label.visible = false
		
		print("Player left merchant range")
