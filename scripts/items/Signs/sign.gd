extends StaticBody3D

@export var use_dialogic: bool = true
@export var dialogic_timeline: String = ""

# Reference to the player when they're in range
var player_in_range: bool = false
var player_reference: Node = null

# 3D floating button variables
var floating_button: Node3D
var button_mesh: MeshInstance3D
var button_label: Label3D
var bob_tween: Tween

func _ready():
	var area = $Area3D
	area.body_entered.connect(_on_area_3d_body_entered)
	area.body_exited.connect(_on_area_3d_body_exited)

	create_floating_button()

func create_floating_button():
	# Create the floating button node
	floating_button = Node3D.new()
	floating_button.name = "FloatingButton"
	add_child(floating_button)
	
	# Position it above the sign
	floating_button.position = Vector3(0, 2.5, 0)
	
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
	if player_in_range and Input.is_action_just_pressed("interact"):
		start_dialogic_timeline()

func _on_area_3d_body_entered(body):
	if body.is_in_group("Player"):
		player_in_range = true
		player_reference = body
		
		# Show floating button and start bobbing
		floating_button.visible = true
		start_bobbing_animation()


func _on_area_3d_body_exited(body):
	if body.is_in_group("Player"):
		player_in_range = false
		player_reference = null
		
		# Hide floating button and stop bobbing
		floating_button.visible = false
		stop_bobbing_animation()


# Function to start Dialogic timeline
func start_dialogic_timeline():
	if dialogic_timeline != "":
		Dialogic.start(dialogic_timeline)
	else:
		print("No Dialogic timeline set for this sign!")

# Function to set Dialogic timeline dynamically
func set_dialogic_timeline(timeline_name: String):
	dialogic_timeline = timeline_name
	use_dialogic = true

# Function to switch between modes
func set_use_dialogic(use_dialog: bool):
	use_dialogic = use_dialog
