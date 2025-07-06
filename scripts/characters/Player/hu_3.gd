extends CharacterBody3D

# HU-3 Companion robot that follows the player and collects gears

# References
@onready var player: CharacterBody3D = null
@onready var area_3d: Area3D = $Area3D
@onready var health_indicator: MeshInstance3D = $Mesh/HealthIndicator

# Following behavior
var follow_distance: float = 2.0
var follow_speed: float = 8.0
var hover_height: float = 1.5
var hover_amplitude: float = 0.3
var hover_frequency: float = 2.0
var side_offset: float = 1.5  # Offset to the right of player
var forward_offset: float = 1.0  # Slight forward offset

# Gear collection
var gear_collection_distance: float = 5.0
var gear_collection_speed: float = 12.0
var collected_gears: Array[Node] = []

# Internal state
var hover_time: float = 0.0
var is_collecting_gear: bool = false
var target_gear: Node = null

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
	
	# Calculate movement direction
	var direction = (follow_pos - global_position).normalized()
	var distance = global_position.distance_to(follow_pos)
	
	# Only move if we're too far from follow position
	if distance > follow_distance * 0.5:
		velocity = direction * follow_speed
		
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
		if gear in collected_gears:
			continue
			
		var distance = global_position.distance_to(gear.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_gear = gear
	
	if nearest_gear:
		target_gear = nearest_gear
		is_collecting_gear = true
		print("HU-3: Targeting gear: ", target_gear.name)

func move_to_gear(delta: float):
	if not target_gear or not is_instance_valid(target_gear):
		is_collecting_gear = false
		target_gear = null
		return
	
	# Move towards the gear
	var direction = (target_gear.global_position - global_position).normalized()
	velocity = direction * gear_collection_speed
	
	# Check if we're close enough to collect
	var distance = global_position.distance_to(target_gear.global_position)
	if distance < 1.0:
		collect_gear(target_gear)

func collect_gear(gear: Node):
	if gear and is_instance_valid(gear):
		# Add to player's gear count
		if player.has_method("add_gear_count"):
			player.add_gear_count(1)
		elif player.has_property("gear_count"):
			player.gear_count += 1
		
		# Mark as collected and remove from scene
		collected_gears.append(gear)
		gear.queue_free()
		
		print("HU-3: Collected gear! Player gear count: ", player.gear_count)
		
		# Reset collection state
		is_collecting_gear = false
		target_gear = null

func _on_gear_entered(body: Node3D):
	if body.is_in_group("Gear"):
		print("HU-3: Gear detected: ", body.name)

func _on_gear_exited(body: Node3D):
	if body.is_in_group("Gear"):
		print("HU-3: Gear left detection range: ", body.name)

func _on_gear_area_entered(area: Area3D):
	if area.is_in_group("Gear"):
		print("HU-3: Gear area detected: ", area.name)

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
