extends Node

@export var static_logo_duration: float = 3.0  # Duration to hold static logos (seconds)
@export var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"  # Path to main menu scene

var logos_node: Node
var current_logo_index: int = 0
var logo_children: Array = []
var display_timer: float = 0.0

func _ready() -> void:
	logos_node = get_node("Logos")
	
	if logos_node == null:
		push_error("Logos node not found!")
		return
	
	# Get all child nodes (logos)
	logo_children = logos_node.get_children()
	
	if logo_children.is_empty():
		push_error("No logos found in Logos node!")
		return
	
	# Hide all logos initially
	for logo in logo_children:
		logo.visible = false
	
	# Start with the first logo
	show_current_logo()

func _process(delta: float) -> void:
	if logo_children.is_empty():
		return
	
	display_timer -= delta
	
	if display_timer <= 0.0:
		advance_to_next_logo()

func _input(event: InputEvent) -> void:
	# Check if the start button is pressed
	if event.is_action_pressed("start"):
		# Skip directly to main menu
		go_to_main_menu()

func show_current_logo() -> void:
	if current_logo_index >= logo_children.size():
		go_to_main_menu()
		return
	
	# Hide all logos
	for logo in logo_children:
		logo.visible = false
	
	# Show current logo
	var current_logo = logo_children[current_logo_index]
	current_logo.visible = true
	
	# Check if the logo has an animation player
	var animation_player = find_animation_player(current_logo)
	
	if animation_player != null and animation_player.has_animation("default"):
		# Play animation and set timer to animation length
		animation_player.play("default")
		display_timer = animation_player.current_animation_length
	else:
		# Static logo - use default duration
		display_timer = static_logo_duration

func find_animation_player(node: Node) -> AnimationPlayer:
	# Check if the node itself is an AnimationPlayer
	if node is AnimationPlayer:
		return node
	
	# Check children for AnimationPlayer
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
	
	return null

func advance_to_next_logo() -> void:
	current_logo_index += 1
	
	if current_logo_index >= logo_children.size():
		go_to_main_menu()
	else:
		show_current_logo()

func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(main_menu_scene)
