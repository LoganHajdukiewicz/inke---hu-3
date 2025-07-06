extends Area3D

# Rotation speed in degrees per second
@export var rotation_speed: float = 45.0

@export var enable_bobbing: bool = true
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.0

##TODO: Turn this into a GameStateManager type Inventory system. 
static var gear_count: int = 0


var initial_position: Vector3
var time_passed: float = 0.0

func _ready():
	# Store the initial position for bobbing
	initial_position = position
	
func _process(delta):
	# Rotate the gear around the Y axis
	rotation_degrees.y += rotation_speed * delta
	
	# Optional bobbing motion
	if enable_bobbing:
		time_passed += delta
		position.y = initial_position.y + sin(time_passed * bob_speed) * bob_height

func _on_body_entered(body):
	# Check if the player collected this gear
	if body.is_in_group("Player"):
		collect_gear()

func collect_gear():
	# Add collection logic here (sound, particles, score, etc.)
	gear_count += 1
	print("Total number of Gears: " + str(gear_count))
	
	# Remove the gear from the scene
	queue_free()
