extends CharacterBody3D

# UI elements
var interaction_label: Label
var purchase_panel: Panel
var gear_count_label: Label
var purchase_button: Button
var close_button: Button

# Purchase system
@export var double_jump_cost: int = 3
var player_in_range: bool = false
var current_player: CharacterBody3D = null

# Double jump upgrade tracking
static var double_jump_purchased: bool = false

func _ready():
	# Set up UI
	setup_ui()
	
	# Connect area signals
	$Area3D.body_entered.connect(_on_area_3d_body_entered)
	$Area3D.body_exited.connect(_on_area_3d_body_exited)

func setup_ui():
	# Create UI elements as children of the merchant
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	# Interaction prompt
	interaction_label = Label.new()
	interaction_label.text = "Press E to interact"
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.position = Vector2(50, 50)
	interaction_label.visible = false
	canvas_layer.add_child(interaction_label)
	
	# Purchase panel
	purchase_panel = Panel.new()
	purchase_panel.size = Vector2(400, 300)
	purchase_panel.position = Vector2(400, 200)
	purchase_panel.visible = false
	canvas_layer.add_child(purchase_panel)
	
	# Panel contents
	var panel_label = Label.new()
	panel_label.text = "Merchant Shop"
	panel_label.add_theme_font_size_override("font_size", 28)
	panel_label.position = Vector2(20, 20)
	purchase_panel.add_child(panel_label)
	
	var item_label = Label.new()
	item_label.text = "Double Jump Upgrade"
	item_label.add_theme_font_size_override("font_size", 20)
	item_label.position = Vector2(20, 70)
	purchase_panel.add_child(item_label)
	
	var cost_label = Label.new()
	cost_label.text = "Cost: " + str(double_jump_cost) + " gears"
	cost_label.add_theme_font_size_override("font_size", 18)
	cost_label.position = Vector2(20, 100)
	purchase_panel.add_child(cost_label)
	
	# Gear count display
	gear_count_label = Label.new()
	gear_count_label.add_theme_font_size_override("font_size", 18)
	gear_count_label.position = Vector2(20, 130)
	purchase_panel.add_child(gear_count_label)
	
	# Purchase button
	purchase_button = Button.new()
	purchase_button.text = "Purchase"
	purchase_button.size = Vector2(100, 40)
	purchase_button.position = Vector2(20, 180)
	purchase_button.pressed.connect(_on_purchase_pressed)
	purchase_panel.add_child(purchase_button)
	
	# Close button
	close_button = Button.new()
	close_button.text = "Close"
	close_button.size = Vector2(100, 40)
	close_button.position = Vector2(140, 180)
	close_button.pressed.connect(_on_close_pressed)
	purchase_panel.add_child(close_button)

func _process(delta):
	if player_in_range and Input.is_action_just_pressed("interact"):
		open_shop()

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		current_player = body
		interaction_label.visible = true

func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		current_player = null
		interaction_label.visible = false
		close_shop()

func open_shop():
	if not current_player:
		return
		
	##########################################################################################################
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Update gear count display
	var player_gears = get_player_gear_count()
	gear_count_label.text = "Your gears: " + str(player_gears)
	
	# Update purchase button state
	if double_jump_purchased:
		purchase_button.text = "Already Purchased"
		purchase_button.disabled = true
	elif player_gears >= double_jump_cost:
		purchase_button.text = "Purchase"
		purchase_button.disabled = false
	else:
		purchase_button.text = "Not enough gears"
		purchase_button.disabled = true
	
	purchase_panel.visible = true
	# Pause the game or capture input
	get_tree().paused = true

func close_shop():
	purchase_panel.visible = false
	get_tree().paused = false

func _on_purchase_pressed():
	if not current_player or double_jump_purchased:
		return
	
	var player_gears = get_player_gear_count()
	if player_gears >= double_jump_cost:
		# Deduct gears
		spend_player_gears(double_jump_cost)
		
		# Grant double jump ability
		double_jump_purchased = true
		
		# Update player's double jump ability
		if current_player.has_method("unlock_double_jump"):
			current_player.unlock_double_jump()
		
		print("Double jump purchased!")
		
		# Update UI
		purchase_button.text = "Already Purchased"
		purchase_button.disabled = true
		
		# Update gear count display
		gear_count_label.text = "Your gears: " + str(get_player_gear_count())
		
		close_shop()

func _on_close_pressed():
	close_shop()

func get_player_gear_count() -> int:
	# Get gear count from the gears script
	var gears_script = load("res://items/gears.gd")
	if gears_script:
		return gears_script.gear_count
	return 0

func spend_player_gears(amount: int):
	# Spend gears from the gears script
	var gears_script = load("res://items/gears.gd")
	if gears_script:
		gears_script.gear_count = max(0, gears_script.gear_count - amount)
