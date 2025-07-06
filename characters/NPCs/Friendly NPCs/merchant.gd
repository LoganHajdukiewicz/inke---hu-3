extends CharacterBody3D

# UI elements
var interaction_label: Label
var purchase_panel: Panel
var gear_count_label: Label
var purchase_button: Button
var close_button: Button

# Powerup types
enum PowerupType {
	DOUBLE_JUMP,
	WALL_JUMP
}

# Merchant configuration
@export var powerup_type: PowerupType = PowerupType.DOUBLE_JUMP
@export var powerup_name: String = "Double Jump Upgrade"
@export var powerup_description: String = "Allows you to jump again while in mid-air"
@export var powerup_cost: int = 3

var player_in_range: bool = false
var current_player: CharacterBody3D = null

# Global upgrade tracking
static var double_jump_purchased: bool = false
static var wall_jump_purchased: bool = false

func _ready():
	# Set default values based on powerup type
	setup_powerup_defaults()
	
	# Set up UI
	setup_ui()
	
	# Connect area signals
	$Area3D.body_entered.connect(_on_area_3d_body_entered)
	$Area3D.body_exited.connect(_on_area_3d_body_exited)

func setup_powerup_defaults():
	match powerup_type:
		PowerupType.DOUBLE_JUMP:
			if powerup_name == "Double Jump Upgrade":  # Only set if not manually configured
				powerup_name = "Double Jump Upgrade"
				powerup_description = "Allows you to jump again while in mid-air"
				powerup_cost = 3
		PowerupType.WALL_JUMP:
			if powerup_name == "Double Jump Upgrade":  # Only set if not manually configured
				powerup_name = "Wall Jump Upgrade"
				powerup_description = "Allows you to jump between close walls"
				powerup_cost = 4
	
func setup_ui():
	# Create UI elements as children of the merchant
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	
	# Set the canvas layer to process during pause
	canvas_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Interaction prompt
	interaction_label = Label.new()
	interaction_label.text = "Press E to interact"
	interaction_label.add_theme_font_size_override("font_size", 24)
	interaction_label.position = Vector2(50, 50)
	interaction_label.visible = false
	canvas_layer.add_child(interaction_label)
	
	# Purchase panel
	purchase_panel = Panel.new()
	purchase_panel.size = Vector2(450, 350)
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
	item_label.text = powerup_name
	item_label.add_theme_font_size_override("font_size", 20)
	item_label.position = Vector2(20, 70)
	purchase_panel.add_child(item_label)
	
	var description_label = Label.new()
	description_label.text = powerup_description
	description_label.add_theme_font_size_override("font_size", 16)
	description_label.position = Vector2(20, 100)
	description_label.size = Vector2(400, 40)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	purchase_panel.add_child(description_label)
	
	var cost_label = Label.new()
	cost_label.text = "Cost: " + str(powerup_cost) + " gears"
	cost_label.add_theme_font_size_override("font_size", 18)
	cost_label.position = Vector2(20, 150)
	purchase_panel.add_child(cost_label)
	
	# Gear count display
	gear_count_label = Label.new()
	gear_count_label.add_theme_font_size_override("font_size", 18)
	gear_count_label.position = Vector2(20, 180)
	purchase_panel.add_child(gear_count_label)
	
	# Purchase button
	purchase_button = Button.new()
	purchase_button.text = "Purchase"
	purchase_button.size = Vector2(120, 40)
	purchase_button.position = Vector2(20, 230)
	purchase_button.pressed.connect(_on_purchase_pressed)
	purchase_panel.add_child(purchase_button)
	
	# Close button
	close_button = Button.new()
	close_button.text = "Close"
	close_button.size = Vector2(100, 40)
	close_button.position = Vector2(160, 230)
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
		
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Update gear count display
	var player_gears = get_player_gear_count()
	gear_count_label.text = "Your gears: " + str(player_gears)
	
	# Update purchase button state based on powerup type
	var is_purchased = is_powerup_purchased()
	
	if is_purchased:
		purchase_button.text = "Already Purchased"
		purchase_button.disabled = true
	elif player_gears >= powerup_cost:
		purchase_button.text = "Purchase"
		purchase_button.disabled = false
	else:
		purchase_button.text = "Not enough gears"
		purchase_button.disabled = true
	
	purchase_panel.visible = true
	get_tree().paused = true

func close_shop():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	purchase_panel.visible = false
	get_tree().paused = false

func is_powerup_purchased() -> bool:
	match powerup_type:
		PowerupType.DOUBLE_JUMP:
			return double_jump_purchased
		PowerupType.WALL_JUMP:
			return wall_jump_purchased
		_:
			return false

func _on_purchase_pressed():
	if not current_player or is_powerup_purchased():
		return
	
	var player_gears = get_player_gear_count()
	if player_gears >= powerup_cost:
		# Deduct gears
		spend_player_gears(powerup_cost)
		
		# Grant the appropriate ability
		match powerup_type:
			PowerupType.DOUBLE_JUMP:
				double_jump_purchased = true
				if current_player.has_method("unlock_double_jump"):
					current_player.unlock_double_jump()
				print("Double jump purchased!")
			PowerupType.WALL_JUMP:
				wall_jump_purchased = true
				if current_player.has_method("unlock_wall_jump"):
					current_player.unlock_wall_jump()
				print("Wall jump purchased!")
		
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
	var gears_script = load("res://items/Gears/gears.gd")
	if gears_script:
		return gears_script.gear_count
	return 0

func spend_player_gears(amount: int):
	# Spend gears from the gears script
	var gears_script = load("res://items/Gears/gears.gd")
	if gears_script:
		gears_script.gear_count = max(0, gears_script.gear_count - amount)
