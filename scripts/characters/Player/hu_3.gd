extends CharacterBody3D

@onready var player: CharacterBody3D = null
@onready var area_3d: Area3D = $Area3D
@onready var health_indicator: MeshInstance3D = $Mesh/HealthIndicator
@onready var mouth: MeshInstance3D = $Mesh/Mouth

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
var collected_gears: Array[Node] = []  # This tracks gears HU-3 has collected for internal purposes

# Internal state
var hover_time: float = 0.0
var is_collecting_gear: bool = false
var target_gear: Node = null
var collection_timer: float = 0.0
var collection_timeout: float = 5.0  # Give up after 5 seconds

# Track player's previous position for detecting platform movement
var player_previous_position: Vector3 = Vector3.ZERO
var player_actual_velocity: Vector3 = Vector3.ZERO

# Health indicator
var game_manager

func _ready():
	# Find the player in the scene
	find_player()
	
	# Get GameManager reference
	game_manager = get_node("/root/GameManager")
	
	# Connect to GameManager's health_changed signal
	if game_manager and game_manager.has_signal("health_changed"):
		game_manager.health_changed.connect(_on_player_health_changed)
	
	# Initialize health indicator color
	update_health_indicator()
	
	# Setup mouth shader
	setup_mouth_shader()
	
	# Connect area signals for gear detection
	if area_3d:
		area_3d.body_entered.connect(_on_gear_entered)
		area_3d.body_exited.connect(_on_gear_exited)
		area_3d.area_entered.connect(_on_gear_area_entered)
		area_3d.area_exited.connect(_on_gear_area_exited)

func find_player():
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		player = players[0]
		player_previous_position = player.global_position
	else:
		print("HU-3: No player found in scene!")

func _physics_process(delta: float):
	if not player:
		find_player()
		return
	
	# Calculate player's actual velocity (including platform movement)
	if delta > 0:
		player_actual_velocity = (player.global_position - player_previous_position) / delta
		player_previous_position = player.global_position
	
	# Update hover animation
	hover_time += delta
	
	# Update collection timer
	if is_collecting_gear:
		collection_timer += delta
		if collection_timer > collection_timeout:
			# Give up on current gear and find another
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
	
	# Use actual velocity instead of state machine speed
	var player_horizontal_speed = Vector2(player_actual_velocity.x, player_actual_velocity.z).length()
	
	# If player is moving (either by input or platform), use that speed
	if player_horizontal_speed > 0.5:
		player_speed = player_horizontal_speed
	else:
		# Fallback to state machine speed if available
		if player and player.has_method("get_player_speed"):
			player_speed = player.get_player_speed()
	
	# Base speed is slightly faster than player to catch up
	var target_speed = player_speed * follow_speed_multiplier
	
	# If we're too far behind, activate catchup mode
	if distance_to_target > catchup_distance:
		target_speed = max(player_speed * catchup_speed_multiplier, base_follow_speed * 2.0)
	
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
	
	# Collect the gear using the unified method
	if gear.has_method("collect_gear"):
		gear.collect_gear()
	else:
		gear.queue_free()
	
	# Reset collection state
	reset_collection_state()

func reset_collection_state():
	is_collecting_gear = false
	target_gear = null
	collection_timer = 0.0

func update_health_indicator():
	"""Update the health indicator color based on player's exact health value"""
	if not health_indicator or not game_manager:
		return
	
	var current_health = game_manager.get_player_health()
	var new_color: Color
	
	# Determine color based on exact health value
	match current_health:
		4:
			# Blue (full health with upgrade)
			new_color = Color(0, 0.5, 1, 1)
		3:
			# Green (full base health)
			new_color = Color(0.254902, 1, 0, 1)
		2:
			# Yellow (wounded)
			new_color = Color(1, 1, 0, 1)
		1:
			# Red (critical)
			new_color = Color(1, 0, 0, 1)
		_:
			# Default to red for 0 or other values
			new_color = Color(1, 0, 0, 1)
	
	# Update the health indicator material
	var material = health_indicator.get_active_material(0)
	if material is StandardMaterial3D:
		material.albedo_color = new_color
	else:
		# Create new material if none exists
		var new_material = StandardMaterial3D.new()
		new_material.albedo_color = new_color
		health_indicator.set_surface_override_material(0, new_material)

func _on_player_health_changed(_new_health: int, _max_health: int):
	"""Called when player's health changes"""
	update_health_indicator()
	update_mouth_color()

func setup_mouth_shader():
	"""Setup wobbling line shader for HU-3's mouth"""
	if not mouth:
		return
	
	# Create shader material
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	
	# Oscilloscope line shader code
	shader.code = """
shader_type spatial;
render_mode unshaded;

uniform vec4 line_color : source_color = vec4(0.254902, 1.0, 0.0, 1.0);
uniform float activity_speed = 5.0;
uniform float activity_amount = 0.15;
uniform float line_thickness = 0.01;
uniform float wave_frequency = 200.0;

void fragment() {
	// Get UV coordinates
	vec2 uv = UV;
	
	// Create multiple wave layers for oscilloscope effect
	float wave1 = sin(TIME * activity_speed + uv.x * wave_frequency) * 1.0;
	float wave2 = sin(TIME * activity_speed * 1.5 + uv.x * wave_frequency * 0.8) * 0.5;
	float wave3 = sin(TIME * activity_speed * 0.7 + uv.x * wave_frequency * 1.3) * 0.3;
	
	// Combine waves for complex oscilloscope pattern
	float combined_wave = wave1 + wave2 + wave3;
	
	// Create steep envelope - stationary at edges, VERY intense in middle
	float edge_distance = abs(uv.x - 0.5) * 2.0;
	// Use higher power for more extreme middle intensity
	float envelope = pow(1.0 - edge_distance, 5.0);
	
	// Apply envelope to waves for vertical middle movement
	float activity = combined_wave * envelope * activity_amount;
	
	// Calculate distance from center line with oscilloscope activity
	float center_line = 0.5 + activity;
	float dist = abs(uv.y - center_line);
	
	// Create sharp line like oscilloscope trace
	float line = 1.0 - smoothstep(0.0, line_thickness, dist);
	
	// Add bright glow for oscilloscope CRT effect
	float glow = exp(-dist * 40.0) * 0.4;
	line = clamp(line + glow, 0.0, 1.0);
	
	// Make the rest transparent
	if (line < 0.05) {
		discard;
	}
	
	// Apply color
	ALBEDO = line_color.rgb;
	ALPHA = line;
}
"""
	
	shader_material.shader = shader
	mouth.material_override = shader_material
	
	# Set initial color
	update_mouth_color()

func update_mouth_color():
	"""Update the mouth shader color based on player's health"""
	if not mouth or not game_manager:
		return
	
	var material = mouth.material_override
	if material is ShaderMaterial:
		var current_health = game_manager.get_player_health()
		var new_color: Color
		
		# Same color logic as health indicator
		match current_health:
			4:
				new_color = Color(0, 0.5, 1, 1)  # Blue
			3:
				new_color = Color(0.254902, 1, 0, 1)  # Green
			2:
				new_color = Color(1, 1, 0, 1)  # Yellow
			1:
				new_color = Color(1, 0, 0, 1)  # Red
			_:
				new_color = Color(1, 0, 0, 1)  # Default red
		
		material.set_shader_parameter("line_color", new_color)
	
func _on_gear_entered(body: Node3D):
	if body.is_in_group("Gear"):
		pass

func _on_gear_exited(body: Node3D):
	if body.is_in_group("Gear"):
		pass

func _on_gear_area_entered(area: Area3D):
	if area.is_in_group("Gear"):
		pass

func _on_gear_area_exited(area: Area3D):
	if area.is_in_group("Gear"):
		pass

func get_gear_count() -> int:
	return collected_gears.size()
