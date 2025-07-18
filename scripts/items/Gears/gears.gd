extends Area3D

# Rotation speed in degrees per second
@export var rotation_speed: float = 45.0

@export var enable_bobbing: bool = true
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.0

var initial_position: Vector3
var time_passed: float = 0.0
var collected: bool = false  # Prevent double collection

func _ready():
	# Store the initial position for bobbing
	initial_position = position
	
	# Add this gear to the "Gear" group so HU-3 can find it
	add_to_group("Gear")
	
	# Connect to GameManager if it exists
	if not GameManager:
		print("Warning: GameManager not found!")
	
func _process(delta):
	# Don't update if already collected
	if collected:
		return
		
	# Rotate the gear around the Y axis
	rotation_degrees.y += rotation_speed * delta
	
	# Optional bobbing motion
	if enable_bobbing:
		time_passed += delta
		position.y = initial_position.y + sin(time_passed * bob_speed) * bob_height

func _on_body_entered(body):
	# Check if the player collected this gear directly
	if body.is_in_group("Player") and not collected:
		collect_gear_by_player()

func collect_gear_by_player():
	"""Called when player directly collects the gear"""
	if collected:
		return
		
	collected = true
	
	# Add gear through GameManager
	GameManager.add_gear(1)
	
	print("Player collected gear directly!")
	
	# Remove the gear from the scene
	queue_free()

func collect_gear_by_hu3():
	"""Called when HU-3 collects the gear"""
	if collected:
		return
		
	collected = true
	
	# Add gear through GameManager specifically for HU-3
	GameManager.add_hu3_gear()
	
	print("HU-3 collected gear!")
	
	# Remove the gear from the scene
	queue_free()

# Legacy method for compatibility
func collect_gear():
	collect_gear_by_player()
