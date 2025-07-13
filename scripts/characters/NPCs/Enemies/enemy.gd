extends CharacterBody3D

# Health system
var max_health = 3
var current_health = 3

# Detection and attack system
var detection_timer = 0.0
var detection_time_threshold = 5.0
var is_player_in_detection = false
var player_reference = null
var has_attacked = false

# Movement and navigation
var move_speed = 2.0
var gravity = 9.8
var is_chasing = false

# References to scene nodes
@onready var navigation_agent = $NavigationAgent3D
@onready var detection_area = $DetectionArea
@onready var health_node = $Health

func _ready():
	# Connect detection area signals
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)
	
	# Set up navigation agent
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.path_desired_distance = 0.5
	
	print("Enemy initialized with health: ", current_health)

func _physics_process(delta):
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Handle detection timer and attack
	if is_player_in_detection and player_reference and not has_attacked:
		detection_timer += delta
		
		if detection_timer >= detection_time_threshold:
			attack_player()
			has_attacked = true
			detection_timer = 0.0
	
	# Handle movement and chasing
	if is_chasing and player_reference:
		chase_player()
	
	# Apply movement
	move_and_slide()

func _on_detection_area_body_entered(body):
	if body.is_in_group("Player") or body.name == "Player":
		print("Player entered detection area")
		is_player_in_detection = true
		player_reference = body
		detection_timer = 0.0
		has_attacked = false
		is_chasing = true

func _on_detection_area_body_exited(body):
	if body.is_in_group("player") or body.name == "Player":
		print("Player exited detection area")
		is_player_in_detection = false
		player_reference = null
		detection_timer = 0.0
		has_attacked = false
		is_chasing = false
		
		# Stop moving when player leaves
		velocity.x = 0
		velocity.z = 0

func attack_player():
	if player_reference:
		print("Enemy attacking player!")
		
		# Deal damage to player if they have a take_damage method
		if player_reference.has_method("take_damage"):
			player_reference.take_damage(1)
		
		# Visual feedback - make enemy flash or change color temporarily
		flash_enemy()
		
		# Reset for next attack cycle
		detection_timer = 0.0
		has_attacked = false

func chase_player():
	if player_reference:
		# Set navigation target to player position
		navigation_agent.target_position = player_reference.global_position
		
		# Get next path position
		var next_path_position = navigation_agent.get_next_path_position()
		
		# Calculate direction to move
		var direction = (next_path_position - global_position).normalized()
		
		# Apply horizontal movement only
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		
		# Face the player
		if direction.length() > 0.1:
			look_at(player_reference.global_position, Vector3.UP)

func take_damage(damage_amount):
	current_health -= damage_amount
	print("Enemy took ", damage_amount, " damage. Health: ", current_health)
	
	# Visual feedback
	flash_enemy()
	
	# Check if dead
	if current_health <= 0:
		die()

func die():
	print("Enemy died!")
	# Add death effects here (particles, sound, etc.)
	
	# Remove from scene
	queue_free()

func flash_enemy():
	# Simple flash effect by changing the material color briefly
	var body_mesh = $Body
	if body_mesh and body_mesh.get_surface_override_material(0):
		var material = body_mesh.get_surface_override_material(0)
		
		# Flash white briefly
		var original_color = material.albedo_color
		material.albedo_color = Color.WHITE
		
		# Return to original color after a short delay
		await get_tree().create_timer(0.1).timeout
		material.albedo_color = original_color

func heal(heal_amount):
	current_health = min(current_health + heal_amount, max_health)
	print("Enemy healed for ", heal_amount, ". Health: ", current_health)

func reset_attack_state():
	"""Call this if you want to reset the attack timer manually"""
	detection_timer = 0.0
	has_attacked = false

func set_chase_speed(new_speed):
	"""Adjust enemy movement speed"""
	move_speed = new_speed

func get_health_percentage():
	"""Returns health as a percentage (0.0 to 1.0)"""
	return float(current_health) / float(max_health)

# Debug function to check enemy state
func debug_print_state():
	print("=== Enemy State ===")
	print("Health: ", current_health, "/", max_health)
	print("Player in detection: ", is_player_in_detection)
	print("Detection timer: ", detection_timer)
	print("Is chasing: ", is_chasing)
	print("Has attacked: ", has_attacked)
	print("===================")
