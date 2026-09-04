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
var anchor_max_drift: float = 1.5  # Virtual follow anchor can never be further than this from the body

# Gear collection
var gear_collection_distance: float = 8.0
var gear_collection_speed: float = 15.0
var collected_gears: Array[Node] = []

# === NAVIGATION / ANTI-STUCK (HU-3 is a FLYING robot - act like one) ===
var avoid_probe_distance: float = 2.2      # How far ahead to look for obstacles
var avoid_lift_speed: float = 8.0          # Climb rate when something is in the way
var stuck_time: float = 0.0                # How long we've been blocked while trying to move
var stuck_teleport_after: float = 1.5      # Blocked this long -> teleport to the player
var teleport_distance: float = 22.0        # Too far behind -> teleport to the player
var los_blocked_time: float = 0.0          # How long line-of-sight to player has been blocked

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
	
	# NAVIGATION LAYER: steer around/over obstacles, and bail out of any
	# situation the steering can't fix (teleport catch-up)
	_apply_obstacle_avoidance(delta)
	
	# Apply movement
	move_and_slide()
	
	# MOMENTUM SYNC - see the README in _apply_obstacle_avoidance.
	# smooth_follow_position is a VIRTUAL anchor that integrates momentum
	# with no collision. When a wall stops the body, the anchor keeps
	# going PAST it; velocity = (anchor - body)/delta then rams the wall
	# at full speed forever (and vibrates against the climb boost). So:
	# after every slide, (a) kill anchor momentum along any surface we
	# actually hit, and (b) leash the anchor to the body.
	for i in range(get_slide_collision_count()):
		var n = get_slide_collision(i).get_normal()
		var into = smooth_follow_velocity.dot(-n)
		if into > 0.0:
			smooth_follow_velocity += n * into   # Wall absorbed this momentum
	var drift = smooth_follow_position - global_position
	if drift.length() > anchor_max_drift:
		smooth_follow_position = global_position + drift.normalized() * anchor_max_drift
	
	_update_stuck_recovery(delta)

func _apply_obstacle_avoidance(_delta: float):
	"""HU-3 flies - when the path ahead is blocked, climb over it and slide
	along the wall instead of face-planting into it.
	
	IMPORTANT: the whisker only probes HORIZONTALLY. Probing along the full
	velocity meant that diving toward a gear on the ground "detected" the
	floor as an obstacle and fired the climb boost - HU-3 would shake above
	the gear forever and could never collect anything below head height.
	Floors are not obstacles for a descending flyer; walls are."""
	if velocity.length() < 0.5:
		return
	
	# ============================= README =================================
	# THE WALL-SLIDE VIBRATION BUG (and how it was fixed)
	#
	# SYMPTOM: while the player wall slides (or climbs/hangs), HU-3
	# vibrates violently up and down next to the wall.
	#
	# ROOT CAUSE - RUNAWAY MOMENTUM ON A VIRTUAL ANCHOR:
	# HU-3 doesn't steer at the player directly; it chases a virtual point
	# (smooth_follow_position) that integrates its own momentum
	# (smooth_follow_velocity) with NO collision detection. The body is
	# moved by move_and_slide, which walls DO stop. So next to a wall:
	#   1. The wall stops the MESH, but the anchor's momentum carries it
	#      past where we see - into/through/below the wall.
	#   2. velocity = (anchor - body) / delta now points at the wall at
	#      max speed, every frame, forever - the body pins and grinds.
	#   3. The obstacle whisker sees the wall and fires the climb boost
	#      (velocity.y = +8); steering yanks back down toward the runaway
	#      anchor; boost fires again... up 8 / down 10 = the vibration.
	#   A jump only "fixed" it because the anchor finally re-converged on
	#   the body once it left the wall.
	#
	# THE FIX (two layers, both required):
	#   a) MOMENTUM SYNC (in _physics_process, right after move_and_slide):
	#      for every surface the body actually collided with, delete the
	#      anchor-velocity component pointing into it (the wall absorbed
	#      that momentum - the anchor doesn't get to keep it), and leash
	#      the anchor to within anchor_max_drift of the real body so it
	#      can never run away again.
	#   b) This whisker is SKIPPED while the player is wall-attached
	#      (_is_player_wall_attached: slide/climb/hang) - those states
	#      already park HU-3 at a calm anchor 1.6m off the wall, and the
	#      wall itself must not count as an obstacle to climb.
	#
	# RULE OF THUMB for any future vertical jitter: it's almost always two
	# systems writing velocity.y with opposite signs on alternating frames,
	# usually because some proxy target diverged from the physical body.
	# Don't tune the numbers - find the second writer / the diverged proxy.
	# ======================================================================
	if _is_player_wall_attached():
		return
	
	# Only the horizontal component matters for wall avoidance
	var flat_vel = Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length() < 0.5:
		return  # Moving (almost) straight up/down: no walls to avoid
	
	var space_state = get_world_3d().direct_space_state
	var move_dir = flat_vel.normalized()
	var probe_len = maxf(avoid_probe_distance, flat_vel.length() * 0.25)
	
	# Main whisker: straight along our horizontal travel
	var query = PhysicsRayQueryParameters3D.create(global_position, global_position + move_dir * probe_len)
	query.collision_mask = 1
	query.exclude = [self]
	if player:
		query.exclude.append(player)
	var hit = space_state.intersect_ray(query)
	if not hit:
		return
	
	# Ignore floor-ish surfaces entirely (ramps read as walkable, not walls)
	if hit.normal.y > 0.55:
		return
	
	# Never fight a deliberate descent toward a pickup
	if is_collecting_gear and target_gear and is_instance_valid(target_gear) \
		and target_gear.global_position.y < global_position.y:
		return
	
	# Something's in the way. Is there clear air above it? (flying robot!)
	var over_from = global_position + Vector3(0, 1.6, 0)
	var over_query = PhysicsRayQueryParameters3D.create(over_from, over_from + move_dir * probe_len)
	over_query.collision_mask = 1
	over_query.exclude = query.exclude
	var over_hit = space_state.intersect_ray(over_query)
	
	if not over_hit:
		# Climb over the obstacle while keeping some forward motion
		velocity.y = maxf(velocity.y, avoid_lift_speed)
	else:
		# Can't go over: deflect sideways along the wall (slide, don't push)
		var wall_normal: Vector3 = hit.normal
		var into_wall = velocity.dot(-wall_normal)
		if into_wall > 0:
			velocity += wall_normal * into_wall  # Remove the into-wall component
			# Pick the sideways direction that leads toward the target
			var side = wall_normal.cross(Vector3.UP).normalized()
			var to_target = smooth_follow_position - global_position
			if to_target.dot(side) < 0:
				side = -side
			velocity += side * minf(into_wall, 6.0)

func _update_stuck_recovery(delta: float):
	"""Last-resort recovery: if steering couldn't unstick us, or we've fallen
	absurdly far behind, TELEPORT next to the player. A companion robot that's
	stuck behind a fence is worse than one that briefly blinks forward."""
	if not player or not is_instance_valid(player):
		return
	
	var dist_to_player = global_position.distance_to(player.global_position)
	
	# Stuck = trying to move but going nowhere
	var wants_to_move = velocity.length() > 2.0
	var actually_moving = get_real_velocity().length() > 0.8
	if wants_to_move and not actually_moving:
		stuck_time += delta
	else:
		stuck_time = maxf(stuck_time - delta * 2.0, 0.0)
	
	# Line of sight to the player
	var space_state = get_world_3d().direct_space_state
	var los_query = PhysicsRayQueryParameters3D.create(global_position, player.global_position + Vector3(0, 1.0, 0))
	los_query.collision_mask = 1
	los_query.exclude = [self, player]
	if space_state.intersect_ray(los_query):
		los_blocked_time += delta
	else:
		los_blocked_time = 0.0
	
	var should_teleport = dist_to_player > teleport_distance \
		or stuck_time > stuck_teleport_after \
		or (los_blocked_time > 3.0 and dist_to_player > 8.0)
	
	if should_teleport:
		_teleport_to_player()

func _teleport_to_player():
	"""Blink to the player's side (with a little pop so it reads as intended)."""
	if not player or not is_instance_valid(player):
		return
	var yaw = player.rotation.y
	var behind = Vector3(sin(yaw), 0, cos(yaw))  # Player's back direction
	global_position = player.global_position + behind * 1.5 + Vector3(0, hover_height + 0.5, 0)
	smooth_follow_position = global_position
	smooth_follow_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	stuck_time = 0.0
	los_blocked_time = 0.0
	reset_collection_state()
	# Blink feedback. IMPORTANT: scale the MESH, not the body - tweening the
	# body's scale bakes scale into its Basis, and Basis.slerp() then throws
	# "must be normalized to be casted to a Quaternion" every frame.
	var mesh_node = get_node_or_null("Mesh")
	if mesh_node:
		mesh_node.scale = Vector3(0.3, 0.3, 0.3)
		var tween = create_tween()
		tween.tween_property(mesh_node, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	
	# Step 2: Calculate offsets using player's CURRENT world orientation.
	# YAW ONLY: ignore the player's roll/pitch (shimmy wobble, climb lean,
	# swing tilt...) - otherwise HU-3 jitters when the player's body tilts.
	var yaw: float = player.rotation.y
	var player_right = Vector3(cos(yaw), 0, -sin(yaw))
	var player_forward = Vector3(-sin(yaw), 0, -cos(yaw))
	
	# While hanging/climbing the player is glued to a wall and repositioned
	# directly every frame - park HU-3 OFF the wall (behind the player's back)
	# instead of chasing the twitchy side offset into the geometry.
	if _is_player_wall_attached():
		target_pos = player.global_position - player_forward * 1.6
		target_pos.y += hover_height
		target_pos.y += sin(hover_time * hover_frequency) * hover_amplitude
		_steer_toward(target_pos, delta)
		return
	
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
			# orthonormalized() on BOTH sides: any residual scale/drift in the
			# basis makes slerp -> Quaternion casting error-spam
			global_transform.basis = global_transform.basis.orthonormalized().slerp(target_basis, delta * 4.0).orthonormalized()

func _is_player_wall_attached() -> bool:
	"""True while the player is glued to geometry (ledge hang / wall climb):
	these states reposition the player directly, so HU-3 uses a calmer
	follow anchor to avoid jitter and wall clipping."""
	if not player or not player.has_node("StateMachine"):
		return false
	var state_machine = player.get_node("StateMachine")
	if not state_machine or not state_machine.current_state:
		return false
	var state_name = state_machine.current_state.get_script().get_global_name()
	return state_name in ["LedgeHangingState", "WallClimbingState", "WallSlidingState"]

func _steer_toward(target_pos: Vector3, delta: float) -> void:
	"""Shared smooth-follow steering toward a target point (same accel/damping
	model as the main follow path)."""
	var to_target = target_pos - smooth_follow_position
	var distance = to_target.length()
	var desired_velocity = Vector3.ZERO
	if distance > 0.1:
		var direction = to_target.normalized()
		var speed_factor = min(distance / follow_distance, 1.0)
		var target_speed = base_follow_speed
		if distance > catchup_threshold:
			target_speed = base_follow_speed * catchup_speed_boost
		desired_velocity = direction * target_speed * speed_factor
		if desired_velocity.length() > follow_max_speed:
			desired_velocity = desired_velocity.normalized() * follow_max_speed
	
	var velocity_diff = desired_velocity - smooth_follow_velocity
	smooth_follow_velocity += velocity_diff * follow_acceleration * delta
	smooth_follow_velocity *= follow_damping
	smooth_follow_position += smooth_follow_velocity * delta
	
	var to_smooth_pos = smooth_follow_position - global_position
	var distance_to_smooth = to_smooth_pos.length()
	if distance_to_smooth > 0.1:
		velocity = to_smooth_pos.normalized() * min(distance_to_smooth / delta, follow_max_speed)
	else:
		velocity = smooth_follow_velocity
	
	# Face the player while they climb/hang (HU-3 watches, doesn't spin)
	var to_player = player.global_position - global_position
	to_player.y = 0
	if to_player.length() > 0.5:
		var target_basis = Basis.looking_at(to_player.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.orthonormalized().slerp(target_basis, delta * 4.0).orthonormalized()

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
		
		# Loot that just exploded out of a patch/box is locked - let the player
		# SEE it before HU-3 vacuums it up. hu3_locked is the longer, separate
		# HU-3-only timer (Inspector: GroundPoundMound.hu3_ignore_time).
		if gear.get("pickup_locked") or gear.get("hu3_locked"):
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
	
	# Rotate to face gear.
	# COLINEAR GUARD: when the gear is almost straight above/below, the look
	# direction is parallel to UP and Basis.looking_at() spams warnings and
	# can spin wildly around Z. Only yaw toward the flat component, and skip
	# rotation entirely when the flat component is negligible.
	var flat_dir = Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length() > 0.15:
		var target_basis = Basis.looking_at(flat_dir.normalized(), Vector3.UP)
		global_transform.basis = global_transform.basis.orthonormalized().slerp(target_basis, delta * 5.0).orthonormalized()
	
	# Check if close enough to collect. HU-3's body physically can't reach
	# ground-level gear centers (its collider keeps its center ~0.5m up), so
	# be generous vertically: close horizontally + within grabbing reach
	# vertically counts as collected.
	var to_gear = target_gear.global_position - global_position
	var flat_dist = Vector2(to_gear.x, to_gear.z).length()
	if to_gear.length() < 1.5 or (flat_dist < 1.0 and absf(to_gear.y) < 2.0):
		collect_gear(target_gear)

func collect_gear(gear: Node):
	if not gear or not is_instance_valid(gear):
		reset_collection_state()
		return
	
	if gear.has_method("get") and (gear.get("collected") or gear.get("pickup_locked") or gear.get("hu3_locked")):
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
