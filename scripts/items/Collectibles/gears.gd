extends Area3D

# Rotation speed in degrees per second
@export var rotation_speed: float = 45.0

@export var enable_bobbing: bool = true
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.0
@export var ground_offset: float = 0.3  # How high above ground to float

var initial_position: Vector3
var ground_level: float = 0.0
var time_passed: float = 0.0
var collected: bool = false  # Prevent double collection

func _ready():
	# Add to groups
	add_to_group("Gear")
	add_to_group("Collectible")
	
	# CRITICAL: Set collision properties to NOT affect player
	collision_layer = 0  # Don't exist on any physics layer
	collision_mask = 1   # Only detect player on layer 1
	monitorable = false  # Other things can't detect us
	monitoring = true    # We can detect others
	
	# Find ground level and position above it
	call_deferred("find_ground_level")
	
func find_ground_level():
	"""Raycast down to find ground and position above it"""
	# Wait one frame to ensure we're in the tree
	await get_tree().process_frame
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -100, 0)
	)
	query.collision_mask = 1  # Check ground layer
	
	var result = space_state.intersect_ray(query)
	if result:
		# Position the gear above the ground
		ground_level = result.position.y + ground_offset
		global_position.y = ground_level
		initial_position = global_position
		print("Gear positioned at ground level: ", ground_level)
	else:
		# No ground found, use current position
		ground_level = global_position.y
		initial_position = global_position
		print("Gear: No ground found, using current position: ", ground_level)

func _process(delta):
	# Don't update if already collected
	if collected:
		return
	
	# Rotate the gear around the Y axis
	rotation_degrees.y += rotation_speed * delta
	
	# Bobbing motion (stays above ground)
	if enable_bobbing:
		time_passed += delta
		# Bob up and down from the ground level
		var bob_offset = sin(time_passed * bob_speed) * bob_height
		global_position.y = ground_level + bob_offset

func _on_body_entered(body):
	# Check if the player collected this gear
	if body.is_in_group("Player") and not collected:
		collect_gear()

func collect_gear():
	"""Called when any entity collects the gear"""
	if collected:
		return
		
	collected = true
	
	# Get GameManager reference and add gear
	var game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.add_gear(1)
		print("Gear collected! Added to total count.")
	else:
		print("Warning: GameManager not found!")
	
	# Remove the gear from the scene
	queue_free()

# Legacy method for compatibility
func collect_gear_by_player():
	"""Called when player collects the gear - same as regular collection"""
	collect_gear()
