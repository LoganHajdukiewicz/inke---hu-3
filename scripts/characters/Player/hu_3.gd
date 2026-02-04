extends CharacterBody3D

@onready var player: CharacterBody3D = null
@onready var area_3d: Area3D = $Area3D
@onready var health_indicator: MeshInstance3D = $Mesh/HealthIndicator
@onready var mouth: MeshInstance3D = $Mesh/Mouth

# Following behavior
var follow_distance: float = 2.0
var base_follow_speed: float = 20.0
var max_follow_speed: float = 50.0
var hover_height: float = 1.5
var hover_amplitude: float = 0.2
var hover_frequency: float = 1.5
var side_offset: float = 1.5
var forward_offset: float = 1.0
var catchup_threshold: float = 5.0
var catchup_speed_boost: float = 5.0

# NEW: Completely rewritten smooth following system
var smooth_follow_position: Vector3 = Vector3.ZERO
var smooth_follow_velocity: Vector3 = Vector3.ZERO
var follow_acceleration: float = 25.0  # How fast to accelerate towards target
var follow_max_speed: float = 35.0  # Maximum speed when following
var follow_damping: float = 0.92  # Velocity damping (0.0 = instant stop, 1.0 = no damping)

# Gear collection
var gear_collection_distance: float = 8.0
var gear_collection_speed: float = 15.0
var collected_gears: Array[Node] = []

# Internal state
var hover_time: float = 0.0
var is_collecting_gear: bool = false
var target_gear: Node = null
var collection_timer: float = 0.0
var collection_timeout: float = 5.0

# Health indicator
var game_manager

func _ready():
	# Initialize smooth follow position before anything else
	smooth_follow_position = global_position
	smooth_follow_velocity = Vector3.ZERO
	
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
		# Initialize smooth follow position to current position
		if smooth_follow_position == Vector3.ZERO:
			smooth_follow_position = global_position
			smooth_follow_velocity = Vector3.ZERO
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
			reset_collection_state()
	
	# Check for nearby gears to collect
	if not is_collecting_gear:
		find_nearest_gear()
	
	# Handle movement
	if is_collecting_gear and target_gear and is_instance_valid(target_gear):
		move_to_gear(delta)
	else:
		follow_player_smooth(delta)
	
	# Apply movement
	move_and_slide()

func follow_player_smooth(delta: float):
	"""
	Completely rewritten following system using physics-based smooth following.
	This eliminates ALL bobbing by using acceleration/velocity instead of lerping position.
	"""
	if not player or not is_instance_valid(player):
		return
	
	# Safety check: ensure smooth_follow_position is initialized
	if smooth_follow_position == null or smooth_follow_position == Vector3.ZERO:
		smooth_follow_position = global_position
		smooth_follow_velocity = Vector3.ZERO
	
	# Check if player is rail grinding for speed boost
	var is_player_grinding = is_player_rail_grinding()
	var speed_multiplier = 2.0 if is_player_grinding else 1.0
	
	# Calculate the ideal target position in PURE WORLD SPACE
	# Step 1: Start with player's world position
	var target_pos = player.global_position
	
	# Step 2: Calculate offsets using player's CURRENT world orientation
	# Get player's facing direction in world space
	var player_basis = player.global_transform.basis.orthonormalized()
	var player_right = player_basis.x
	var player_forward = -player_basis.z
	
	# Apply horizontal offsets (right and forward)
	target_pos += player_right * side_offset
	target_pos += player_forward * forward_offset
	
	# Step 3: Add base hover height in WORLD Y AXIS ONLY
	target_pos.y += hover_height
	
	# Step 4: Add subtle hover animation ONLY in world Y
	var hover_wave = sin(hover_time * hover_frequency) * hover_amplitude
	target_pos.y += hover_wave
	
	# NOW: Use smooth_follow_position instead of directly moving to target
	# This position smoothly accelerates towards target_pos
	
	# Calculate direction and distance to target
	var to_target = target_pos - smooth_follow_position
	var distance = to_target.length()
	
	# Calculate desired velocity towards target
	var desired_velocity = Vector3.ZERO
	if distance > 0.1:
		var direction = to_target.normalized()
		
		# Speed scales with distance for smoother arrival
		var speed_factor = min(distance / follow_distance, 1.0)
		
		# Check if we need catchup boost
		var target_speed = base_follow_speed * speed_multiplier  # Apply rail grinding multiplier
		if distance > catchup_threshold:
			target_speed = base_follow_speed * catchup_speed_boost * speed_multiplier
		
		desired_velocity = direction * target_speed * speed_factor
		
		# Cap maximum speed (with multiplier for rail grinding)
		var max_vel = follow_max_speed * speed_multiplier
		if desired_velocity.length() > max_vel:
			desired_velocity = desired_velocity.normalized() * max_vel
	
	# Accelerate smooth_follow_velocity towards desired_velocity
	var velocity_diff = desired_velocity - smooth_follow_velocity
	smooth_follow_velocity += velocity_diff * follow_acceleration * delta
	
	# Apply damping to prevent oscillation
	smooth_follow_velocity *= follow_damping
	
	# Update smooth follow position using velocity
	smooth_follow_position += smooth_follow_velocity * delta
	
	# Set HU-3's actual velocity to move towards smooth_follow_position
	var to_smooth_pos = smooth_follow_position - global_position
	var distance_to_smooth = to_smooth_pos.length()
	
	if distance_to_smooth > 0.1:
		# Move towards the smoothed position (with speed multiplier)
		var max_move_speed = follow_max_speed * speed_multiplier
		velocity = to_smooth_pos.normalized() * min(distance_to_smooth / delta, max_move_speed)
	else:
		# We're close enough, maintain position
		velocity = smooth_follow_velocity
	
	# Smooth rotation towards movement direction (not player direction)
	if velocity.length() > 0.5:
		var look_direction = velocity.normalized()
		
		# FIXED: Check if look direction is too vertical (colinear with UP)
		# If the direction is nearly straight up or down, skip rotation to avoid errors
		var up_dot = abs(look_direction.dot(Vector3.UP))
		if up_dot < 0.98:  # Only rotate if not too vertical (98% aligned with up)
			var target_basis = Basis.looking_at(look_direction, Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_basis, delta * 4.0)

func is_player_rail_grinding() -> bool:
	"""Check if the player is currently rail grinding"""
	if not player or not player.has_node("StateMachine"):
		return false
	
	var state_machine = player.get_node("StateMachine")
	if not state_machine or not state_machine.current_state:
		return false
	
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	return current_state_name == "RailGrindingState"

func find_nearest_gear():
	var gears = get_tree().get_nodes_in_group("Gear")
	var nearest_gear = null
	var nearest_distance = gear_collection_distance
	
	for gear in gears:
		if not is_instance_valid(gear) or gear in collected_gears:
			continue
		
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
		# Reset smooth following when switching to gear collection
		smooth_follow_position = global_position
		smooth_follow_velocity = Vector3.ZERO

func move_to_gear(delta: float):
	if not target_gear or not is_instance_valid(target_gear):
		reset_collection_state()
		return
	
	if target_gear.has_method("get") and target_gear.get("collected"):
		reset_collection_state()
		return
	
	# Direct movement towards gear
	var direction = (target_gear.global_position - global_position).normalized()
	velocity = direction * gear_collection_speed
	
	# Rotate to face gear
	if velocity.length() > 0.1:
		var target_basis = Basis.looking_at(velocity.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(target_basis, delta * 5.0)
	
	# Check if close enough to collect
	var distance = global_position.distance_to(target_gear.global_position)
	if distance < 1.5:
		collect_gear(target_gear)

func collect_gear(gear: Node):
	if not gear or not is_instance_valid(gear):
		reset_collection_state()
		return
	
	if gear.has_method("get") and gear.get("collected"):
		reset_collection_state()
		return
	
	if gear.has_method("collect_gear"):
		gear.collect_gear()
	else:
		gear.queue_free()
	
	reset_collection_state()

func reset_collection_state():
	is_collecting_gear = false
	target_gear = null
	collection_timer = 0.0
	# Reinitialize smooth following from current position
	smooth_follow_position = global_position
	smooth_follow_velocity = Vector3.ZERO

func update_health_indicator():
	"""Update the health indicator color based on player's exact health value"""
	if not health_indicator or not game_manager:
		return
	
	var current_health = game_manager.get_player_health()
	var new_color: Color
	
	if current_health >= 4:
		new_color = Color(0.0, 0.5, 1.0, 1.0)
	elif current_health == 3:
		new_color = Color(0.254902, 1.0, 0.0, 1.0)
	elif current_health == 2:
		new_color = Color(1.0, 1.0, 0.0, 1.0)
	elif current_health == 1:
		new_color = Color(1.0, 0.0, 0.0, 1.0)
	else:
		new_color = Color(1.0, 0.0, 0.0, 1.0)
	
	var material = health_indicator.get_active_material(0)
	if material is StandardMaterial3D:
		material.albedo_color = new_color
	else:
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
	
	var shader_material = ShaderMaterial.new()
	var shader = Shader.new()
	
	shader.code = """
shader_type spatial;
render_mode unshaded;

uniform vec4 line_color : source_color = vec4(0.254902, 1.0, 0.0, 1.0);
uniform float activity_speed = 5.0;
uniform float activity_amount = 0.15;
uniform float line_thickness = 0.01;
uniform float wave_frequency = 200.0;

void fragment() {
	vec2 uv = UV;
	
	float wave1 = sin(TIME * activity_speed + uv.x * wave_frequency) * 1.0;
	float wave2 = sin(TIME * activity_speed * 1.5 + uv.x * wave_frequency * 0.8) * 0.5;
	float wave3 = sin(TIME * activity_speed * 0.7 + uv.x * wave_frequency * 1.3) * 0.3;
	
	float combined_wave = wave1 + wave2 + wave3;
	
	float edge_distance = abs(uv.x - 0.5) * 2.0;
	float envelope = pow(1.0 - edge_distance, 5.0);
	
	float activity = combined_wave * envelope * activity_amount;
	
	float center_line = 0.5 + activity;
	float dist = abs(uv.y - center_line);
	
	float line = 1.0 - smoothstep(0.0, line_thickness, dist);
	
	float glow = exp(-dist * 40.0) * 0.4;
	line = clamp(line + glow, 0.0, 1.0);
	
	if (line < 0.05) {
		discard;
	}
	
	ALBEDO = line_color.rgb;
	ALPHA = line;
}
"""
	
	shader_material.shader = shader
	mouth.material_override = shader_material
	
	update_mouth_color()

func update_mouth_color():
	"""Update the mouth shader color based on player's health"""
	if not mouth or not game_manager:
		return
	
	var material = mouth.material_override
	if material is ShaderMaterial:
		var current_health = game_manager.get_player_health()
		var new_color: Color
		
		if current_health >= 4:
			new_color = Color(0.0, 0.5, 1.0, 1.0)
		elif current_health == 3:
			new_color = Color(0.254902, 1.0, 0.0, 1.0)
		elif current_health == 2:
			new_color = Color(1.0, 1.0, 0.0, 1.0)
		elif current_health == 1:
			new_color = Color(1.0, 0.0, 0.0, 1.0)
		else:
			new_color = Color(1.0, 0.0, 0.0, 1.0)
		
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
