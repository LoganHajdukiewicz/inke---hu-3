extends CharacterBody3D

@onready var player: CharacterBody3D = null
@onready var area_3d: Area3D = $Area3D
@onready var health_indicator: MeshInstance3D = $Mesh/HealthIndicator

# Following behavior
var follow_distance: float = 2.0
var base_follow_speed: float = 9.0  # Base speed when player is idle/walking
var follow_speed_multiplier: float = 1.2  # Multiplier for player speed (20% faster to catch up)
var max_follow_speed: float = 40.0  # Maximum speed cap
var hover_height: float = 1.5
var hover_amplitude: float = 0.3
var hover_frequency: float = 2.0
var side_offset: float = 1.5  # Offset to the right of player
var forward_offset: float = 1.0  # Slight forward offset
var catchup_distance: float = 5.0  # Distance at which HU-3 goes into "catchup mode"
var catchup_speed_multiplier: float = 2.5  # Speed multiplier when catching up

# Gear collection
var gear_collection_distance: float = 8.0  # Increased detection range
var gear_collection_speed: float = 15.0  # Increased collection speed
var collected_gears: Array[Node] = []

# Internal state
var hover_time: float = 0.0
var is_collecting_gear: bool = false
var target_gear: Node = null
var collection_timer: float = 0.0
var collection_timeout: float = 5.0  # Give up after 5 seconds

# Health/status
var health: int = 100
var max_health: int = 100

func _ready():
	# Find the player in the scene
	find_player()
	
	# Connect area signals for gear detection
	if area_3d:
		area_3d.body_entered.connect(_on_gear_entered)
		area_3d.body_exited.connect(_on_gear_exited)
		area_3d.area_entered.connect(_on_gear_area_entered)
		area_3d.area_exited.connect(_on_gear_area_exited)
	
	# Set initial health indicator
	update_health_indicator()

func find_player():
	# Look for player in the scene
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
		print("HU-3: Found player: ", player.name)
	else:
		print("HU-3: No player found in scene!")

func _physics_process(delta: float):
	if not player:
		find_player()
		return
	
	# Update hover animation
	hover_time += delta
	
	# Update collection timer
	if is_collecting_gear:
		collection_timer += delta
		if collection_timer > collection_timeout:
			# Give up on current gear and find another
			print("HU-3: Timeout collecting gear, finding new target")
			reset_collection_state()
	
	# Check for nearby gears to collect
	if not is_collecting_gear:
		find_nearest_gear()
	
	# Handle movement
	if is_collecting_gear and target_gear and is_instance_valid(target_gear):
		move_to_gear(delta)
	else:
		follow_player(delta)
	
	# Apply movement
	move_and_slide()

func get_dynamic_follow_speed(distance_to_target: float) -> float:
	"""Calculate HU-3's speed based on player's current speed and distance"""
	var player_speed = base_follow_speed
	
	# Get player's current speed from their state machine
	if player and player.has_method("get_player_speed"):
		player_speed = player.get_player_speed()
	
	# Base speed is slightly faster than player to catch up
	var target_speed = player_speed * follow_speed_multiplier
	
	# If we're too far behind, activate catchup mode
	if distance_to_target > catchup_distance:
		target_speed = player_speed * catchup_speed_multiplier
		print("HU-3: Catchup mode activated - Distance: ", distance_to_target)
	
	# Cap the maximum speed
	target_speed = min(target_speed, max_follow_speed)
	
	# Ensure minimum speed
	target_speed = max(target_speed, base_follow_speed)
	
	return target_speed

func follow_player(delta: float):
	if not player:
		return
	
	# Get player's transform to follow their facing direction
	var player_pos = player.global_position
	var player_basis = player.global_transform.basis
	
	# Calculate follow position (slightly up, to the right, and a bit forward)
	var right_offset = player_basis.x * side_offset  # Player's right direction
	var forward_offset_vec = player_basis.z * -forward_offset  # Player's forward direction (negative z)
	var follow_pos = player_pos + Vector3(0, hover_height, 0) + right_offset + forward_offset_vec
	
	# Add subtle hovering motion
	follow_pos.y += sin(hover_time * hover_frequency) * hover_amplitude
	
	# Calculate movement direction and distance
	var direction = (follow_pos - global_position).normalized()
	var distance = global_position.distance_to(follow_pos)
	
	# Get dynamic speed based on distance and player speed
	var dynamic_speed = get_dynamic_follow_speed(distance)
	
	# Only move if we're too far from follow position
	if distance > follow_distance * 0.5:
		velocity = direction * dynamic_speed
		
		# Smoothly rotate to face movement direction
		if velocity.length() > 0.1:
			var target_transform = global_transform.looking_at(global_position + velocity.normalized(), Vector3.UP)
			global_transform = global_transform.interpolate_with(target_transform, delta * 3.0)
	else:
		velocity = velocity.lerp(Vector3.ZERO, delta * 5.0)

func find_nearest_gear():
	var gears = get_tree().get_nodes_in_group("Gear")
	var nearest_gear = null
	var nearest_distance = gear_collection_distance
	
	for gear in gears:
		# Skip if already collected or invalid
		if not is_instance_valid(gear) or gear in collected_gears:
			continue
		
		# Skip if gear is already collected (check gear's collected flag)
		if gear.has_method("get") and gear.get("collected"):
			continue
			
		var distance = global_position.distance_to(gear.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_gear = gear
	
	if nearest_gear:
		target_gear = nearest_gear
		is_collecting_gear = true
		collection_timer = 0.0
		print("HU-3: Targeting gear: ", target_gear.name, " at distance: ", nearest_distance)

func move_to_gear(delta: float):
	if not target_gear or not is_instance_valid(target_gear):
		reset_collection_state()
		return
	
	# Check if gear was collected by someone else
	if target_gear.has_method("get") and target_gear.get("collected"):
		reset_collection_state()
		return
	
	# Move towards the gear
	var direction = (target_gear.global_position - global_position).normalized()
	velocity = direction * gear_collection_speed
	
	# Smoothly rotate to face the gear
	if velocity.length() > 0.1:
		var target_transform = global_transform.looking_at(global_position + velocity.normalized(), Vector3.UP)
		global_transform = global_transform.interpolate_with(target_transform, delta * 5.0)
	
	# Check if we're close enough to collect
	var distance = global_position.distance_to(target_gear.global_position)
	if distance < 1.5:  # Increased collection radius
		collect_gear(target_gear)

func collect_gear(gear: Node):
	if not gear or not is_instance_valid(gear):
		reset_collection_state()
		return
	
	# Check if gear has already been collected
	if gear.has_method("get") and gear.get("collected"):
		reset_collection_state()
		return
	
	# Collect the gear
	if gear.has_method("collect_gear_by_hu3"):
		gear.collect_gear_by_hu3()
	else:
		# Fallback - mark as collected and remove
		gear.queue_free()
	
	# Update player's gear count
	if player and player.has_method("add_gear_count"):
		player.add_gear_count(1)
	
	# Mark as collected
	collected_gears.append(gear)
	
	print("HU-3: Collected gear! Total collected by HU-3: ", collected_gears.size())
	
	# Reset collection state
	reset_collection_state()

func reset_collection_state():
	is_collecting_gear = false
	target_gear = null
	collection_timer = 0.0

func _on_gear_entered(body: Node3D):
	if body.is_in_group("Gear"):
		print("HU-3: Gear body detected: ", body.name)

func _on_gear_exited(body: Node3D):
	if body.is_in_group("Gear"):
		print("HU-3: Gear body left detection range: ", body.name)

func _on_gear_area_entered(area: Area3D):
	if area.is_in_group("Gear"):
		print("HU-3: Gear area detected: ", area.name)
		# Could trigger immediate collection if very close

func _on_gear_area_exited(area: Area3D):
	if area.is_in_group("Gear"):
		print("HU-3: Gear area left detection range: ", area.name)

func update_health_indicator():
	if not health_indicator:
		return
	
	# Update health indicator color based on health percentage
	var health_percentage = float(health) / float(max_health)
	var material = health_indicator.get_surface_override_material(0)
	
	if not material:
		material = StandardMaterial3D.new()
		health_indicator.set_surface_override_material(0, material)
	
	# Green to red gradient based on health
	if health_percentage > 0.5:
		material.albedo_color = Color.GREEN.lerp(Color.YELLOW, (1.0 - health_percentage) * 2.0)
	else:
		material.albedo_color = Color.YELLOW.lerp(Color.RED, (0.5 - health_percentage) * 2.0)

func take_damage(amount: int):
	health = max(0, health - amount)
	update_health_indicator()
	print("HU-3: Took ", amount, " damage. Health: ", health, "/", max_health)

func heal(amount: int):
	health = min(max_health, health + amount)
	update_health_indicator()
	print("HU-3: Healed ", amount, " health. Health: ", health, "/", max_health)

# Public interface for player interaction
func get_gear_count() -> int:
	return collected_gears.size()

func get_health_percentage() -> float:
	return float(health) / float(max_health)
