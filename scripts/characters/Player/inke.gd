@tool
extends CharacterBody3D
class_name Inke
# @tool + class_name so "Inke" shows up in the editor's Add Node dialog.
# A bare Inke node added that way instantly swaps itself for the full
# inke.tscn scene (see _enter_tree) - no more dragging from the FileSystem.

# ══════════════════════════════════════════════════════════════════════════
# MOVEMENT TUNING — every core movement number, editable on Inke's Inspector.
# States read these values from the player, so changes apply live.
# (State-specific extras like dash distance or wall-jump timing live as
# exports on the corresponding StateMachine child node.)
# ══════════════════════════════════════════════════════════════════════════

@export_group("Ground Movement")
@export var walk_speed: float = 10.0          # WalkingState speed
@export var walk_rotation_speed: float = 10.0 # How fast Inke turns while walking
@export var run_speed: float = 20.0           # RunningState speed
@export var run_rotation_speed: float = 12.0  # How fast Inke turns while running
@export var idle_deceleration: float = 100.0  # How quickly Inke stops when idle

@export_group("Jumping & Air")
@export var jump_velocity: float = 5.0        # Base upward velocity (double jump etc.)
@export var coyote_time_duration: float = 0.15  # Grace period to jump after leaving a ledge
@export var terminal_velocity: float = 30.0   # Max fall speed
@export var falling_air_control: float = 0.25  # 0 = no air control while falling, 1 = full
@export var long_jump_window: float = 0.3     # Time window after dash to trigger long jump

@export_group("Ice Movement")
@export var ice_acceleration: float = 14.0      # units/sec^2 gained while holding a direction
@export var ice_deceleration: float = 3.0       # units/sec^2 lost while no input (glide!)
@export var ice_turn_rate: float = 1.8          # how quickly velocity direction bends toward input
@export var ice_max_speed_multiplier: float = 1.15  # can slightly exceed run speed when sliding
@export var ice_friction_multiplier: float = 0.01   # legacy control multiplier on ice

@export_group("Damage & Death")
@export var invulnerability_duration: float = 1.5
@export var death_y_threshold: float = -50.0   # Fall death threshold

@export_group("Wall Climbing")
@export var climb_grab_distance: float = 0.9   # How close to a climbable wall to grab it
@export var climb_regrab_delay: float = 0.35   # Cooldown after leaving a wall before regrabbing

@export_group("Balance Beam")
@export var beam_speed_multiplier: float = 0.8  # Walk speed on a balance beam (-20%)

@export_group("Landing Feedback")
@export var land_puff_enabled: bool = true
@export var land_puff_min_fall_speed: float = 9.0  # Minimum |fall speed| to puff on landing

# Player state variables
var running: bool = false
var gravity: float = 9.8
var gravity_default: float = 9.8
var is_being_sprung: bool = false
var ignore_next_jump: bool = false
var controls_disabled: bool = false

# Double jump variables
var has_double_jumped: bool = false
var can_double_jump: bool = false

# Air dash variables (NEW - similar to double jump)
var has_air_dashed: bool = false
var can_air_dash: bool = false

# Long jump variables (NEW)
var can_long_jump: bool = false
var long_jump_timer: float = 0.0

# Dash jump momentum storage (NEW)
var stored_dash_momentum: Vector3 = Vector3.ZERO

# Coyote time variables
var coyote_time_counter: float = 0.0
var was_on_floor: bool = false

# Wall jump variables (exposed for state compatibility)
var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0

# Damage and death variables
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var is_dead: bool = false
var should_flash: bool = false 

# NEW: Ice floor detection
var is_on_ice: bool = false

# Balance beam detection
var is_on_balance_beam: bool = false

# SLIDING floor detection (kept in sync each physics frame)
var is_on_slide_floor: bool = false
var slide_floor_downhill: Vector3 = Vector3.ZERO  # Flat downhill direction of the slide

# Wall climb regrab cooldown
var climb_regrab_timer: float = 0.0

# Slide-jump anti-climb: while this timer runs, air control cannot add
# velocity in the blocked (uphill) direction. Set when jumping off a
# SLIDING floor so players can't spam jump to scale slide slopes.
var slide_uphill_block: Vector3 = Vector3.ZERO
var slide_uphill_block_timer: float = 0.0

# Landing puff tracking
var _puff_was_airborne: bool = false
var _air_min_vy: float = 0.0

# ── Debug Upgrades ─────────────────────────────────────────────────────────────
# Toggle these in Inke's Inspector to grant/revoke upgrades without a merchant.
# Changes take effect immediately during play.

@export_group("Debug Upgrades")

@export var debug_double_jump: bool = false:
	set(value):
		debug_double_jump = value
		_apply_debug_upgrade("double_jump_purchased", value)

@export var debug_wall_jump: bool = false:
	set(value):
		debug_wall_jump = value
		_apply_debug_upgrade("wall_jump_purchased", value)

@export var debug_dash: bool = false:
	set(value):
		debug_dash = value
		_apply_debug_upgrade("dash_purchased", value)

@export var debug_speed_upgrade: bool = false:
	set(value):
		debug_speed_upgrade = value
		_apply_debug_upgrade("speed_upgrade_purchased", value)

@export var debug_health_upgrade: bool = false:
	set(value):
		debug_health_upgrade = value
		_apply_debug_upgrade("health_upgrade_purchased", value)

@export var debug_damage_upgrade: bool = false:
	set(value):
		debug_damage_upgrade = value
		_apply_debug_upgrade("damage_upgrade_purchased", value)

@export var debug_grant_all: bool = false:
	set(value):
		debug_grant_all = value
		if value:
			debug_double_jump   = true
			debug_wall_jump     = true
			debug_dash          = true
			debug_speed_upgrade = true
			debug_health_upgrade = true
			debug_damage_upgrade = true
		else:
			debug_double_jump   = false
			debug_wall_jump     = false
			debug_dash          = false
			debug_speed_upgrade = false
			debug_health_upgrade = false
			debug_damage_upgrade = false

func _apply_debug_upgrade(property: String, value: bool) -> void:
	"""Write directly to GameManager's purchased boolean."""
	if not is_inside_tree():
		return  # _ready() will apply all values once we're in the tree
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.set(property, value)

# ── End Debug Upgrades ─────────────────────────────────────────────────────────

# Component references (now managed by separate managers)
var jump_shadow_manager: JumpShadowManager
var gear_collection_manager: GearCollectionManager
var rail_detection_manager: RailDetectionManager
var wall_jump_detector: WallJumpDetector
var speed_effects_manager: SpeedEffectsManager

# References
@onready var player = self
@onready var state_machine: StateMachine = get_node_or_null("StateMachine")
var game_manager 
var checkpoint_manager
var paint_manager

# Export for scene setup
@export var wall_jump_rays: Node3D
@export var rail_grind_area: Area3D 

const INKE_SCENE_PATH := "res://scenes/characters/Player/inke.tscn"

func _enter_tree():
	# A "bare" Inke (added from the Add Node dialog: script but no children)
	# replaces itself with the real player scene, in editor AND at runtime.
	if not has_node("StateMachine"):
		call_deferred("_swap_to_full_scene")

func _swap_to_full_scene():
	if has_node("StateMachine") or not is_inside_tree():
		return
	var parent = get_parent()
	if parent == null:
		return
	var packed = load(INKE_SCENE_PATH)
	if packed == null:
		return
	var wanted_name := String(name)
	name = wanted_name + "_replacing"
	var inst = packed.instantiate()
	inst.name = wanted_name
	inst.transform = transform
	parent.add_child(inst)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		inst.owner = get_tree().edited_scene_root
	queue_free()

func _ready():
	if Engine.is_editor_hint():
		return
	if not has_node("StateMachine"):
		return   # Bare node - _swap_to_full_scene is about to replace it
	# FIX: Get autoload references in _ready instead of @onready
	game_manager = get_node("/root/GameManager")
	checkpoint_manager = get_node("/root/CheckpointManager")
	paint_manager = get_node("/root/PaintManager")
	
	# Inke casts NO regular shadow - her only shadow is the round jump
	# shadow decal under her (JumpShadowManager), which reads much better.
	_disable_mesh_shadows(self)
	
	$CameraController.initialize_camera()
	if DialogueManager:
		DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	
	# Get GameManager reference
	if game_manager:
		game_manager.register_player(self)
		# Connect to health changed signal
		if not game_manager.health_changed.is_connected(_on_health_changed):
			game_manager.health_changed.connect(_on_health_changed)
	else:
		print("Player: GameManager not found!")
	
	# Get CheckpointManager reference
	if not checkpoint_manager:
		print("Player: CheckpointManager not found!")
	
	# Register with PaintManager
	if paint_manager:
		paint_manager.register_player(self)
		# Connect to paint signals
		if paint_manager.has_signal("paint_changed"):
			paint_manager.paint_changed.connect(_on_paint_changed)
		if paint_manager.has_signal("paint_used"):
			paint_manager.paint_used.connect(_on_paint_used)
	else:
		print("Player: PaintManager not found!")
	
	# Apply any debug upgrades that were set in the inspector before _ready ran
	_apply_all_debug_upgrades()
	
	# Initialize modular components
	initialize_components()
	
	# Setup damage detection area
	setup_damage_area()

func _apply_all_debug_upgrades() -> void:
	"""Re-apply all debug toggles after GameManager is available."""
	_apply_debug_upgrade("double_jump_purchased",  debug_double_jump)
	_apply_debug_upgrade("wall_jump_purchased",     debug_wall_jump)
	_apply_debug_upgrade("dash_purchased",          debug_dash)
	_apply_debug_upgrade("speed_upgrade_purchased", debug_speed_upgrade)
	_apply_debug_upgrade("health_upgrade_purchased",debug_health_upgrade)
	_apply_debug_upgrade("damage_upgrade_purchased",debug_damage_upgrade)

func _on_dialogue_ended():
	"""Called when dialogue ends - ignore the next jump input"""
	ignore_next_jump = true
	# Clear the flag after a short delay
	await get_tree().create_timer(0.01).timeout
	ignore_next_jump = false

func initialize_components():
	"""Initialize all modular component managers"""
	# Jump shadow
	jump_shadow_manager = JumpShadowManager.new()
	jump_shadow_manager.name = "JumpShadowManager"
	add_child(jump_shadow_manager)
	
	# Gear collection
	gear_collection_manager = GearCollectionManager.new()
	gear_collection_manager.name = "GearCollectionManager"
	add_child(gear_collection_manager)
	
	# Rail detection
	rail_detection_manager = RailDetectionManager.new()
	rail_detection_manager.name = "RailDetectionManager"
	add_child(rail_detection_manager)
	
	# Ledge detection 
	var ledge_detection_manager = LedgeDetectionManager.new()
	ledge_detection_manager.name = "LedgeDetectionManager"
	add_child(ledge_detection_manager)
	
	# Wall jump detection
	wall_jump_detector = WallJumpDetector.new()
	wall_jump_detector.name = "WallJumpDetector"
	add_child(wall_jump_detector)
	
	# Attack system
	var attack_manager = AttackManager.new()
	attack_manager.name = "AttackManager"
	add_child(attack_manager)
	
	# Speed effects (motion lines/blur/sonic boom)
	speed_effects_manager = SpeedEffectsManager.new()
	speed_effects_manager.name = "SpeedEffectsManager"
	add_child(speed_effects_manager)
	
	# Grapple aiming reticle / target lock-on
	var grapple_target_manager = GrappleTargetManager.new()
	grapple_target_manager.name = "GrappleTargetManager"
	add_child(grapple_target_manager)

func setup_damage_area():
	"""Setup Area3D for detecting damage sources"""
	var damage_area = Area3D.new()
	damage_area.name = "DamageDetectionArea"
	add_child(damage_area)
	
	# Copy collision shape from player's main collision
	var collision_shape = CollisionShape3D.new()
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.height = 1.5
	capsule_shape.radius = 0.5
	collision_shape.shape = capsule_shape
	collision_shape.position = Vector3(0, 0.849, 0)
	damage_area.add_child(collision_shape)
	
	# Connect signals
	damage_area.body_entered.connect(_on_damage_body_entered)
	damage_area.area_entered.connect(_on_damage_area_entered)

func _disable_mesh_shadows(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_mesh_shadows(child)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or state_machine == null:
		return   # Editor preview or bare node awaiting scene swap
	if is_dead:
		return
	
	$CameraController.handle_camera_input(delta)

	var current_state_name = state_machine.current_state.get_script().get_global_name()
	
	# Disable shadow while rail grinding
	if jump_shadow_manager:
		jump_shadow_manager.set_enabled(current_state_name != "RailGrindingState")
	
	if current_state_name != "RailGrindingState":
		# Smoothly return character to upright orientation
		var upright_basis = Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
		upright_basis = upright_basis.rotated(Vector3.UP, rotation.y)
		# Normalize basis before slerp to avoid quaternion conversion errors
		var normalized_basis = basis.orthonormalized()
		basis = normalized_basis.slerp(upright_basis, delta * 10.0).orthonormalized()
	
	update_coyote_time(delta)
	update_invulnerability(delta)
	update_long_jump_timer(delta)
	update_dash_cooldown(delta)
	update_ice_detection()  # NEW: Check for ice floor using get_last_slide_collision
	update_balance_beam_detection()
	update_slide_uphill_block(delta)
	update_landing_puff()
	update_climb_grab(delta, current_state_name)
	check_fall_death()
	
	# Sync wall jump cooldown from detector to player (for state compatibility)
	if wall_jump_detector:
		wall_jump_cooldown = wall_jump_detector.wall_jump_cooldown
	
	# Reset double jump and air dash on the floor
	if is_on_floor():
		has_double_jumped = false
		can_double_jump = true
		has_air_dashed = false
		can_air_dash = true
	
	$CameraController.follow_character(position, velocity)

func update_ice_detection():
	"""Check what special floor the player is standing on (FROZEN / SLIDING)"""
	is_on_ice = false
	is_on_slide_floor = false
	
	if not is_on_floor():
		return
	
	# Use get_slide_collision to check what we're standing on
	# This is more reliable than raycasting
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is Floor:
			# Multi-type aware: a MOVING floor with FROZEN as an extra type is ice too
			if collider.has_floor_type(Floor.FloorType.FROZEN):
				is_on_ice = true
			if collider.has_floor_type(Floor.FloorType.SLIDING):
				is_on_slide_floor = true
				# Downhill = gravity projected on the surface, flattened
				var n = collision.get_normal()
				var downhill = Vector3.DOWN - n * Vector3.DOWN.dot(n)
				downhill.y = 0
				slide_floor_downhill = downhill.normalized() if downhill.length() > 0.01 else Vector3.ZERO
		elif collider and collider.has_method("get"):
			var floor_type = collider.get("floor_type")
			if floor_type != null and floor_type == 6:  # FloorType.FROZEN
				is_on_ice = true

func arm_slide_uphill_block(duration: float = 0.9):
	"""Called when jumping off a SLIDING floor: air control can't push the
	player uphill for `duration` seconds, so jump-spamming can't climb slides."""
	if slide_floor_downhill != Vector3.ZERO:
		slide_uphill_block = -slide_floor_downhill  # Uphill direction
		slide_uphill_block_timer = duration

func update_balance_beam_detection():
	"""Check if the player is standing on a balance beam and point the camera
	behind the player while they are."""
	is_on_balance_beam = false
	if is_on_floor():
		for i in range(get_slide_collision_count()):
			var collider = get_slide_collision(i).get_collider()
			if collider and collider.is_in_group("BalanceBeam"):
				is_on_balance_beam = true
				break
	var cam = get_node_or_null("CameraController")
	if cam and "auto_behind" in cam:
		cam.auto_behind = is_on_balance_beam

func trip_off_beam():
	"""Running on a balance beam = you lose your footing and fall off the side."""
	var side = global_transform.basis.x.normalized()
	if randf() < 0.5:
		side = -side
	velocity = side * 4.0 + (-global_transform.basis.z) * 2.0
	velocity.y = 2.0
	# Little stumble wobble
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(1.15, 0.85, 1.15), 0.08)
	tween.tween_property(self, "scale", Vector3.ONE, 0.15)

func update_slide_uphill_block(delta: float):
	if slide_uphill_block_timer > 0.0:
		# While AIRBORNE the block does not expire - otherwise double jumps /
		# jump dashes could outlast the timer and still climb the slide.
		# It ticks down (and clears) only once the player is back on a floor.
		if is_on_floor():
			slide_uphill_block_timer -= delta * 4.0  # Clears quickly after landing
			if slide_uphill_block_timer <= 0.0:
				slide_uphill_block = Vector3.ZERO

func apply_slide_uphill_block():
	"""Strip any uphill velocity component while the slide-jump block is active.
	Called by air states after their air-control step so jump-spamming can't
	climb a SLIDING floor."""
	if slide_uphill_block_timer <= 0.0 or slide_uphill_block == Vector3.ZERO:
		return
	var h = Vector3(velocity.x, 0, velocity.z)
	var uphill_amount = h.dot(slide_uphill_block)
	if uphill_amount > 0.0:
		h -= slide_uphill_block * uphill_amount
		velocity.x = h.x
		velocity.z = h.z

# === WALL CLIMBING ===

func update_climb_grab(delta: float, current_state_name: String):
	"""Grab climbable walls when the player pushes toward one."""
	if climb_regrab_timer > 0.0:
		climb_regrab_timer -= delta
		return
	if controls_disabled or is_dead:
		return
	if not current_state_name in ["WalkingState", "RunningState", "JumpingState", "FallingState", "DoubleJumpState", "WallSlidingState"]:
		return
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() < 0.2:
		return
	
	var wall = find_climbable_wall()
	if wall.is_empty():
		return
	
	# Require the input to push INTO the wall
	var camera_basis = $CameraController.transform.basis
	var wish: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if wish.dot(-wall.normal) < 0.35:
		return
	
	var climb_state = state_machine.states.get("wallclimbingstate")
	if climb_state:
		climb_state.setup(wall.normal, wall.point)
		state_machine.change_state("WallClimbingState")

func find_climbable_wall() -> Dictionary:
	"""Raycast forward at two heights for a wall in the ClimbableWall group."""
	var space_state = get_world_3d().direct_space_state
	var forward = -global_transform.basis.z.normalized()
	for height in [0.5, 1.2]:
		var from = global_position + Vector3(0, height, 0)
		var to = from + forward * climb_grab_distance
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		query.exclude = [self]
		var result = space_state.intersect_ray(query)
		if result and result.collider and result.collider.is_in_group("ClimbableWall"):
			# Only near-vertical surfaces
			if abs(result.normal.y) < 0.3:
				return {"point": result.position, "normal": result.normal, "collider": result.collider}
	return {}

# === LANDING PUFF ===

func update_landing_puff():
	"""Spawn a dust puff when landing from a decent height."""
	if not is_on_floor():
		_puff_was_airborne = true
		_air_min_vy = min(_air_min_vy, velocity.y)
	elif _puff_was_airborne:
		if land_puff_enabled and _air_min_vy < -land_puff_min_fall_speed:
			spawn_land_puff(clampf(-_air_min_vy / 25.0, 0.5, 1.4))
		_puff_was_airborne = false
		_air_min_vy = 0.0

func reset_landing_puff_tracker():
	"""Used by ground slam so its own puff isn't doubled by the landing detector."""
	_puff_was_airborne = false
	_air_min_vy = 0.0

func spawn_land_puff(strength: float = 1.0):
	"""Little ring of dust balls that scatter outward and fade."""
	var parent = get_parent()
	if not parent:
		return
	var count = int(round(6 * strength)) + 2
	for i in range(count):
		var puff = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		var size = randf_range(0.12, 0.24) * strength
		sphere.radius = size
		sphere.height = size * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		puff.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.88, 0.82, 0.75)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = mat
		parent.add_child(puff)
		
		var angle = (TAU / count) * i + randf_range(-0.3, 0.3)
		var dir = Vector3(cos(angle), 0, sin(angle))
		puff.global_position = global_position + dir * 0.3 + Vector3(0, 0.12, 0)
		var target = puff.global_position + dir * randf_range(0.7, 1.3) * strength + Vector3(0, randf_range(0.1, 0.35), 0)
		
		var tween = puff.create_tween()
		tween.set_parallel(true)
		tween.tween_property(puff, "global_position", target, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(puff, "scale", Vector3(0.1, 0.1, 0.1), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
		tween.chain().tween_callback(puff.queue_free)

func get_ice_friction_multiplier() -> float:
	"""Get the friction multiplier based on whether we're on ice"""
	return ice_friction_multiplier if is_on_ice else 1.0

func apply_ice_movement(delta: float, input_direction: Vector3, target_speed: float) -> void:
	"""Classic 3D-platformer ice movement.
	Call from ground states while is_on_ice. input_direction may be ZERO
	(no input = keep gliding). Modifies velocity.x/z only."""
	var vel := Vector2(velocity.x, velocity.z)
	var speed := vel.length()
	var max_speed := target_speed * ice_max_speed_multiplier
	
	if input_direction.length() > 0.1:
		var wish := Vector2(input_direction.x, input_direction.z).normalized()
		
		if speed < 0.5:
			# From standstill: just accelerate in the wished direction
			vel += wish * ice_acceleration * delta
		else:
			var current_dir := vel / speed
			var alignment := current_dir.dot(wish)  # 1 = same way, -1 = braking
			
			if alignment < -0.2:
				# Trying to reverse: brake harder than glide, but still slippery
				speed = max(speed - ice_acceleration * 0.8 * delta, 0.0)
				vel = current_dir * speed
				# A little push the new way so reversing eventually works
				vel += wish * ice_acceleration * 0.5 * delta
			else:
				# Skid-turn: bend current momentum toward the wished direction
				# without losing speed (this is the "drifty" ice feel)
				var bend := clampf(ice_turn_rate * delta, 0.0, 1.0)
				var new_dir := current_dir.slerp(wish, bend).normalized()
				# Accelerate along the (new) direction while under max speed
				if speed < max_speed:
					speed = min(speed + ice_acceleration * delta, max_speed)
				vel = new_dir * speed
	else:
		# No input: glide, losing speed very slowly
		speed = max(speed - ice_deceleration * delta, 0.0)
		if speed > 0.01:
			vel = vel.normalized() * speed
		else:
			vel = Vector2.ZERO
	
	velocity.x = vel.x
	velocity.z = vel.y
	
	# Face the direction we're actually sliding (not the stick direction) --
	# feels like the character is surfing their own momentum
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length() > 1.0:
		var face := Vector3(horizontal.x, 0, horizontal.y).normalized()
		var target_rotation := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 6.0 * delta)

func update_dash_cooldown(delta: float):
	"""Tick the dodge dash cooldown centrally so it progresses in every state.
	Previously this was copy-pasted into individual states, so the cooldown
	only advanced while in states that happened to have the copy."""
	var dodge_dash_state = state_machine.states.get("dodgedashstate")
	if dodge_dash_state and state_machine.current_state != dodge_dash_state:
		if not dodge_dash_state.can_dash and dodge_dash_state.cooldown_timer > 0:
			dodge_dash_state.cooldown_timer -= delta
			if dodge_dash_state.cooldown_timer <= 0:
				dodge_dash_state.can_dash = true
				dodge_dash_state.cooldown_timer = 0.0

func update_long_jump_timer(delta: float):
	"""Update the long jump window timer"""
	if long_jump_timer > 0.0:
		long_jump_timer -= delta
		if long_jump_timer <= 0.0:
			can_long_jump = false
			# Clear stored dash momentum when long jump window expires
			stored_dash_momentum = Vector3.ZERO

func enable_long_jump():
	"""Enable long jump window after a dash"""
	can_long_jump = true
	long_jump_timer = long_jump_window

func is_long_jump_available() -> bool:
	"""Check if player can perform a long jump"""
	return can_long_jump and long_jump_timer > 0.0

func update_invulnerability(delta: float):
	"""Update invulnerability timer and CONDITIONAL visual feedback"""
	if is_invulnerable:
		invulnerability_timer -= delta
		
		# Only flash if should_flash is true (when hurt, not when stomping)
		if should_flash:
			var flash_speed = 10.0
			@warning_ignore("shadowed_variable_base_class")
			var is_visible = int(invulnerability_timer * flash_speed) % 2 == 0
			visible = is_visible
		
		if invulnerability_timer <= 0:
			is_invulnerable = false
			should_flash = false
			visible = true  # Ensure player is visible when invulnerability ends

func check_fall_death():
	"""Check if player has fallen below death threshold"""
	if global_position.y < death_y_threshold:
		die()

func update_coyote_time(delta: float):
	"""Update coyote time counter"""
	var currently_on_floor = is_on_floor()
	
	if was_on_floor and not currently_on_floor:
		coyote_time_counter = coyote_time_duration
	
	if currently_on_floor:
		coyote_time_counter = 0.0
	
	if not currently_on_floor and coyote_time_counter > 0:
		coyote_time_counter -= delta
	
	was_on_floor = currently_on_floor

func can_coyote_jump() -> bool:
	"""Check if player can perform a coyote time jump"""
	return coyote_time_counter > 0.0 and not is_on_floor()

func consume_coyote_time():
	"""Consume coyote time when jumping"""
	coyote_time_counter = 0.0

func _process(_delta):
	pass

func get_player_speed():
	return state_machine.current_state.get_speed()

# === ABILITY CHECK METHODS (Using GameManager) ===

func can_perform_double_jump() -> bool:
	"""Check if the player can perform a double jump"""
	var can_double_jump_ability = game_manager.can_double_jump() if game_manager else false
	return can_double_jump_ability and not has_double_jumped and can_double_jump and not is_on_floor()

func perform_double_jump():
	"""Execute the double jump"""
	if can_perform_double_jump():
		velocity.y = jump_velocity
		has_double_jumped = true
		can_double_jump = false
		return true
	return false

func can_perform_wall_jump() -> bool:
	"""Check if the player can perform a wall jump (delegates to WallJumpDetector)"""
	return wall_jump_detector.can_perform_wall_jump() if wall_jump_detector else false

func get_wall_jump_direction() -> Vector3:
	"""Get the direction to wall jump (delegates to WallJumpDetector)"""
	return wall_jump_detector.get_wall_jump_direction() if wall_jump_detector else Vector3.ZERO

# === DAMAGE AND DEATH METHODS ===

func take_damage(amount: int, knockback_dir: Vector3 = Vector3.ZERO):
	"""Player takes damage with optional knockback direction"""
	if is_dead or is_invulnerable:
		return
	
	if game_manager:
		game_manager.damage_player(amount)
	
	# Apply knockback with provided direction
	apply_damage_knockback(knockback_dir)
	
	# Start invulnerability WITH flashing
	is_invulnerable = true
	should_flash = true  # Enable flashing when hurt
	invulnerability_timer = invulnerability_duration
	
	# Check if dead
	if game_manager and game_manager.get_player_health() <= 0:
		die()

func set_invulnerable_without_flash(duration: float):
	"""Set invulnerability without visual flash (for head stomps)"""
	is_invulnerable = true
	should_flash = false  # No flashing for stomps
	invulnerability_timer = duration
	visible = true  # Stay visible

func apply_damage_knockback(knockback_dir: Vector3 = Vector3.ZERO):
	"""Apply knockback when taking damage"""
	# Upward component
	velocity.y = 8.0
	
	# Horizontal knockback
	if knockback_dir.length() > 0:
		# Use provided direction (away from enemy)
		var horizontal_knockback = knockback_dir.normalized()
		velocity.x = horizontal_knockback.x * 10.0
		velocity.z = horizontal_knockback.z * 10.0
	else:
		# Fallback: push backward from player facing
		var knockback_direction = -global_transform.basis.z
		velocity.x = knockback_direction.x * 8.0
		velocity.z = knockback_direction.z * 8.0

func die():
	"""Handle player death"""
	if is_dead:
		return
	
	is_dead = true
	visible = true  # Make sure player is visible during death animation
	
	# Disable controls
	set_physics_process(false)
	
	# Play death animation/effect
	play_death_effect()
	
	# Wait a moment before respawning
	await get_tree().create_timer(1.5).timeout
	
	respawn()

func play_death_effect():
	"""Visual/audio feedback for death"""
	
	# Spin and fall
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:y", rotation.y + TAU * 2, 1.0)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 1.0)

func respawn():
	"""Respawn the player at checkpoint or reload level"""
	# Reset death state
	is_dead = false
	is_invulnerable = false
	should_flash = false
	scale = Vector3.ONE
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	visible = true
	
	# Check for checkpoint
	if checkpoint_manager and checkpoint_manager.has_active_checkpoint():
		# Respawn at checkpoint
		global_position = checkpoint_manager.get_checkpoint_position()
		rotation.y = checkpoint_manager.get_checkpoint_rotation().y
		
		# Restore health
		if game_manager:
			game_manager.set_player_health(game_manager.get_player_max_health())
		
		
		# Re-enable controls
		set_physics_process(true)
		
		# Brief invulnerability after respawn
		set_invulnerable_without_flash(2.0)
	else:
		# No checkpoint - reload the level
		reload_level()

func reload_level():
	"""Reload the current level"""
	# Reset game state
	if game_manager:
		game_manager.set_player_health(game_manager.get_player_max_health())
	
	# Reload the current scene
	get_tree().reload_current_scene()

func _on_health_changed(_new_health: int, _max_health: int):
	"""Called when health changes from GameManager"""
	
	# You can add UI updates here or visual feedback

func _on_damage_body_entered(body: Node3D):
	"""Handle collision with damage-dealing bodies"""
	if is_dead or is_invulnerable:
		return
	
	# Check if it's an enemy
	if body.is_in_group("Enemy"):
		var enemy = body as Enemy
		if enemy:
			# Calculate knockback direction away from enemy
			var knockback_dir = (global_position - enemy.global_position).normalized()
			knockback_dir.y = 0  # Keep horizontal
			take_damage(enemy.damage_to_player, knockback_dir)
	
	# Check for hazards ("Hazards" is the global group defined in project settings;
	# "Hazard"/"KillPlane" kept for backwards compatibility)
	if body.is_in_group("Hazards") or body.is_in_group("Hazard") or body.is_in_group("KillPlane"):
		die()

func _on_damage_area_entered(area: Area3D):
	"""Handle collision with damage-dealing areas"""
	if is_dead or is_invulnerable:
		return
	
	# Check for hazard areas ("Hazards" is the global group defined in project settings)
	if area.is_in_group("Hazards") or area.is_in_group("Hazard") or area.is_in_group("KillPlane"):
		die()
	
	# Check for damage zones
	if area.is_in_group("DamageZone"):
		var damage_amount = 1
		if area.has_method("get_damage"):
			damage_amount = area.get_damage()
		take_damage(damage_amount)

# === HEALTH METHODS ===

func set_health(_new_health: int):
	"""Set player health (called by GameManager)"""

func heal(amount: int):
	"""Player heals"""
	if game_manager:
		game_manager.heal_player(amount)

func get_health() -> int:
	"""Get current health from GameManager"""
	return game_manager.get_player_health() if game_manager else 3

# === GEAR/CURRENCY METHODS ===

func add_gear_count(amount: int):
	"""Called when gears are collected (forwards to GameManager)"""
	if game_manager:
		game_manager.add_gear(amount)

func get_gear_count() -> int:
	"""Get total gear count from GameManager"""
	return game_manager.get_gear_count() if game_manager else 0

func get_CRED_count() -> int:
	"""Get CRED count from GameManager"""
	return game_manager.get_CRED_count() if game_manager else 0

func _on_paint_changed(_new_paint, _previous_paint):
	"""Called when player switches paint type"""
	# You can add additional logic here, such as:
	# - Update UI
	# - Change visual effects
	# - Enable/disable certain abilities

func _on_paint_used(_paint_type):
	"""Called when player uses their current paint"""
	# Additional logic can be added here if needed
