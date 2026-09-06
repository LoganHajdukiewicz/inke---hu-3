extends Area3D

# Rotation speed in degrees per second
@export var rotation_speed: float = 45.0

@export var enable_bobbing: bool = true
@export var bob_height: float = 0.2
@export var bob_speed: float = 2.0
@export var ground_offset: float = 0.3  # How high above ground to float

# Gear Magnet upgrade (merchant): gears inside this radius fly to the player
@export var magnet_radius: float = 6.0
@export var magnet_speed: float = 14.0
var _magnet_active: bool = false

var initial_position: Vector3
var ground_level: float = 0.0
var time_passed: float = 0.0
var collected: bool = false  # Prevent double collection
var is_scattering: bool = false  # Suppress bobbing while scatter tween runs
var pickup_locked: bool = false  # Can't be collected (by player OR HU3) while true
var hu3_locked: bool = false     # HU3 specifically must keep ignoring it

func lock_pickup(duration: float) -> void:
	"""Make the gear uncollectable for a moment (used when it explodes out of
	a ground pound area / box so the player actually SEES the loot fly)."""
	pickup_locked = true
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			pickup_locked = false
	)

func lock_hu3_pickup(duration: float) -> void:
	"""Keep HU3 away for longer than the player lock - so the buddy robot
	doesn't vacuum up ground-pound loot before the player gets a chance."""
	hu3_locked = true
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func():
		if is_instance_valid(self):
			hu3_locked = false
	)

func scatter_arc(target: Vector3, duration: float, arc_height: float = 2.0) -> void:
	"""Explode outward in a big visible ARC: fly up and out, then fall to the
	target. Much more readable than the flat scatter."""
	is_scattering = true
	var start = global_position
	var peak = (start + target) * 0.5 + Vector3(0, arc_height, 0)
	var tween = create_tween()
	# Up-and-out half (ease out = decelerating rise)
	tween.tween_property(self, "global_position", peak, duration * 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Falling half (ease in = accelerating fall)
	tween.tween_property(self, "global_position", target, duration * 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		is_scattering = false
		find_ground_level()
	)

func scatter_to(target: Vector3, duration: float) -> void:
	"""Animate this gear from its current position to target (used by
	breaking boxes / dying enemies). Cheap tween instead of physics.
	Suppresses bobbing until the scatter lands, then re-anchors to ground."""
	is_scattering = true
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target, duration)
	tween.tween_callback(func():
		is_scattering = false
		find_ground_level()
	)

func _ready():
	# Add to groups
	add_to_group("Gear")
	add_to_group("Collectible")
	
	# CRITICAL: Set collision properties to NOT affect player
	collision_layer = 0  # Don't exist on any physics layer
	collision_mask = 1   # Only detect player on layer 1
	set_deferred("monitorable", false)  # Other things can't detect us
	monitoring = true    # We can detect others
	
	# Find ground level and position above it
	call_deferred("find_ground_level")
	
func find_ground_level():
	"""Raycast down to find ground and position above it"""
	# Wait one frame to ensure we're in the tree
	await get_tree().process_frame
	
	# Don't fight the scatter tween; it re-calls us when it finishes
	if is_scattering or collected or not is_inside_tree():
		return
	
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
	else:
		# No ground found, use current position
		ground_level = global_position.y
		initial_position = global_position

func _process(delta):
	# Don't update if already collected
	if collected:
		return
	
	# Rotate the gear around the Y axis
	rotation_degrees.y += rotation_speed * delta
	
	# GEAR MAGNET upgrade: fly to the player once they're in range
	if not is_scattering and not pickup_locked:
		var gm = get_node_or_null("/root/GameManager")
		if gm and gm.gear_magnet_purchased and gm.player and is_instance_valid(gm.player):
			var to_p: Vector3 = gm.player.global_position + Vector3.UP * 0.8 - global_position
			var d := to_p.length()
			if _magnet_active or d < magnet_radius:
				_magnet_active = true   # Once latched, never lets go
				# Accelerating pull - snappier the closer it gets
				var pull := magnet_speed * clampf(2.5 - d / magnet_radius, 1.0, 2.5)
				global_position += to_p.normalized() * minf(pull * delta, d)
				return   # Skip bobbing while being pulled
	
	# Bobbing motion (stays above ground) - not while scattering out of a box
	if enable_bobbing and not is_scattering:
		time_passed += delta
		# Bob up and down from the ground level
		var bob_offset = sin(time_passed * bob_speed) * bob_height
		global_position.y = ground_level + bob_offset

func _on_body_entered(body):
	# Check if the player collected this gear
	if body.is_in_group("Player") and not collected and not pickup_locked:
		collect_gear()

func collect_gear():
	"""Called when any entity collects the gear"""
	if collected or pickup_locked:
		return
		
	collected = true
	
	# Get GameManager reference and add gear
	var game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.add_gear(1)
	else:
		print("Warning: GameManager not found!")
	
	# Remove the gear from the scene
	queue_free()

# Legacy method for compatibility
func collect_gear_by_player():
	"""Called when player collects the gear - same as regular collection"""
	collect_gear()
