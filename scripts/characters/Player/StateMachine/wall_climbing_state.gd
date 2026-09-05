extends State
class_name WallClimbingState

## Free climbing on walls in the "ClimbableWall" group.
## Up / down / left / right movement across the wall face.
## LADDERS ("Ladder" group) restrict movement to up/down only.
## Jump = leap off the wall (away from it). Crouch = let go and fall.
## Climbing over the top edge automatically vaults the player up.
## Climbing down past the bottom edge (or holding down while standing on
## the ground) detaches - no jump required.

@export var climb_speed: float = 4.0
@export var wall_offset: float = 0.55       # How far the player's center sits off the wall
@export var jump_off_speed: float = 8.0     # Push-off speed when jumping from the wall
@export var jump_off_up_speed: float = 6.0  # Upward speed when jumping from the wall
@export var vault_up_boost: float = 6.5     # Upward pop when climbing over the top edge
@export var hop_speed: float = 9.0          # Wall-hop burst speed (jump while climbing)
@export var hop_duration: float = 0.35      # How long a wall-hop burst lasts

var wall_normal: Vector3 = Vector3.ZERO
var wall_point: Vector3 = Vector3.ZERO
var is_ladder: bool = false            # "Ladder" group: up/down only
var _hop_vel: Vector3 = Vector3.ZERO   # Active wall-hop burst (decays)
var _hop_timer: float = 0.0

func setup(normal: Vector3, point: Vector3):
	wall_normal = Vector3(normal.x, 0, normal.z).normalized()
	wall_point = point

func enter():
	player.velocity = Vector3.ZERO
	_hop_vel = Vector3.ZERO
	_hop_timer = 0.0
	
	# Face into the wall
	var face = -wall_normal
	player.rotation.y = atan2(-face.x, -face.z)
	
	# Snap to the wall at the proper offset
	_snap_to_wall()
	
	# Ladder? Lock horizontal movement for this climb
	var probe = _probe_wall(player.global_position)
	is_ladder = not probe.is_empty() and probe.collider.is_in_group("Ladder")
	
	# Grab feedback
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.92, 1.08, 0.92), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func physics_update(delta: float):
	# JUMP on a climbable wall = WALL HOP: a quick burst ACROSS the wall in
	# the stick direction (up if neutral) to climb faster. Stick DOWN =
	# treated like a real jump: let go and drop off the wall.
	# Ladders keep the classic leap-away jump.
	if Input.is_action_just_pressed("jump"):
		var jump_input := Input.get_vector("left", "right", "forward", "back")
		if is_ladder:
			# Ladder: classic leap off, away from the wall
			player.velocity = wall_normal * jump_off_speed
			player.velocity.y = jump_off_up_speed
			player.climb_regrab_timer = player.climb_regrab_delay
			player.rotation.y = atan2(-wall_normal.x, -wall_normal.z) + PI
			change_to("JumpingState")
			return
		if jump_input.y > 0.4:
			# Stick DOWN + jump: drop off the wall like a jump
			player.velocity = wall_normal * jump_off_speed * 0.6
			player.velocity.y = 2.0
			player.climb_regrab_timer = player.climb_regrab_delay
			player.rotation.y = atan2(-wall_normal.x, -wall_normal.z) + PI
			# Eat the buffered press: without this, WallJumpDetector turns
			# the same press into a wall jump off the wall we just dropped.
			if player.wall_jump_detector:
				player.wall_jump_detector._jump_buffer = 0.0
				player.wall_jump_detector.wall_jump_cooldown = 0.35
			change_to("FallingState")
			return
		# Wall hop: burst in the stick direction on the wall plane (up if neutral)
		var side_ax := wall_normal.cross(Vector3.UP).normalized()
		var hop_dir: Vector3
		if jump_input.length() > 0.2:
			hop_dir = (side_ax * -jump_input.x + Vector3.UP * -jump_input.y).normalized()
		else:
			hop_dir = Vector3.UP
		_hop_vel = hop_dir * hop_speed
		_hop_timer = hop_duration
		# Hop feedback: little stretch
		var tw = create_tween()
		tw.tween_property(player, "scale", Vector3(0.9, 1.12, 0.9), 0.07)
		tw.tween_property(player, "scale", Vector3.ONE, 0.1)
		return
	
	# Crouch: let go and drop
	if Input.is_action_just_pressed("crouch"):
		player.velocity = wall_normal * 1.5
		player.velocity.y = 0.0
		player.climb_regrab_timer = player.climb_regrab_delay
		change_to("FallingState")
		return
	
	# ACTIVE WALL HOP: burst movement overrides normal climbing until it decays
	if _hop_timer > 0.0:
		_hop_timer -= delta
		var fade: float = clampf(_hop_timer / hop_duration, 0.0, 1.0)
		var hop_step: Vector3 = _hop_vel * (0.35 + 0.65 * fade)
		var next_hop_pos: Vector3 = player.global_position + hop_step * delta
		var hop_probe := _probe_wall(next_hop_pos)
		if not hop_probe.is_empty():
			wall_normal = Vector3(hop_probe.normal.x, 0, hop_probe.normal.z).normalized()
			var hface = -wall_normal
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-hface.x, -hface.z), 10.0 * delta)
			player.velocity = hop_step - wall_normal * 2.0
			player.move_and_slide()
			return
		elif hop_step.y > 0.5:
			# Hopped past the top edge -> vault over
			_vault_over_top()
			return
		else:
			# Hopped off a side/bottom edge: stop the burst, resume climbing
			_hop_timer = 0.0
			_hop_vel = Vector3.ZERO
	
	# Movement across the wall face:
	# left/right = along the wall, forward/back = up/down the wall
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if is_ladder:
		input_dir.x = 0.0  # Ladders: up/down only, no sideways shuffling
	var side_axis = wall_normal.cross(Vector3.UP).normalized()  # "left" along the wall
	var move = side_axis * -input_dir.x + Vector3.UP * -input_dir.y
	
	# BOTTOM DETACH: already standing on the ground and still pushing down?
	# Let go - no jump required to leave the wall.
	if move.y < -0.3 and player.is_on_floor():
		_detach_at_bottom()
		return
	
	if move.length() > 0.1:
		move = move.normalized()
		var next_pos = player.global_position + move * climb_speed * delta
		
		# Is there still climbable wall at the next position?
		var probe = _probe_wall(next_pos)
		if not probe.is_empty():
			# Track curved/angled walls: update the normal as we move
			wall_normal = Vector3(probe.normal.x, 0, probe.normal.z).normalized()
			var face = -wall_normal
			player.rotation.y = lerp_angle(player.rotation.y, atan2(-face.x, -face.z), 10.0 * delta)
			
			player.velocity = move * climb_speed
		elif move.y > 0.3 and _probe_wall(player.global_position).is_empty() == false:
			# Moving up but no wall above -> we've reached the top edge. Vault!
			_vault_over_top()
			return
		elif move.y < -0.3:
			# Moving down but no wall below -> bottom edge. Let go and drop.
			_detach_at_bottom()
			return
		else:
			# Side edge of the wall: stop
			player.velocity = Vector3.ZERO
	else:
		player.velocity = Vector3.ZERO
	
	# Gentle pull toward the wall keeps us glued on curved surfaces
	player.velocity += -wall_normal * 2.0
	
	player.move_and_slide()
	
	# Lost the wall entirely? (e.g. it moved or got freed)
	if _probe_wall(player.global_position).is_empty():
		# Check once more slightly up/down before giving up (edge jitter)
		if _probe_wall(player.global_position + Vector3(0, 0.3, 0)).is_empty() \
		and _probe_wall(player.global_position + Vector3(0, -0.3, 0)).is_empty():
			player.climb_regrab_timer = player.climb_regrab_delay
			change_to("FallingState")

func _detach_at_bottom():
	"""Reached the bottom of the wall while pressing down: release the grip.
	On the ground -> Idle; in the air -> gentle drop away from the wall."""
	player.climb_regrab_timer = player.climb_regrab_delay
	if player.is_on_floor():
		player.velocity = Vector3.ZERO
		change_to("IdleState")
	else:
		player.velocity = wall_normal * 1.5
		player.velocity.y = 0.0
		change_to("FallingState")

func _vault_over_top():
	"""Pop up and over the top edge of the wall."""
	player.velocity = Vector3.ZERO
	player.velocity.y = vault_up_boost
	player.velocity += -wall_normal * 3.0  # Push onto the ledge
	player.climb_regrab_timer = player.climb_regrab_delay
	change_to("JumpingState")

func _snap_to_wall():
	"""Position the player at wall_offset from the wall surface."""
	var probe = _probe_wall(player.global_position)
	if probe.is_empty():
		return
	var surface_point: Vector3 = probe.position
	var target = surface_point + wall_normal * wall_offset
	player.global_position.x = target.x
	player.global_position.z = target.z

func _probe_wall(at_position: Vector3) -> Dictionary:
	"""Raycast into the wall from a given position. Returns {} if no
	climbable wall is there."""
	var space_state = player.get_world_3d().direct_space_state
	var from = at_position + Vector3(0, 0.75, 0) + wall_normal * 0.4
	var to = from - wall_normal * (player.climb_grab_distance + 0.6)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [player]
	var result = space_state.intersect_ray(query)
	if result and result.collider and result.collider.is_in_group("ClimbableWall"):
		return result
	return {}

func get_speed() -> float:
	return climb_speed

func exit():
	player.scale = Vector3.ONE
