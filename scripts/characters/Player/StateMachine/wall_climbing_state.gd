extends State
class_name WallClimbingState

## Free climbing on walls in the "ClimbableWall" group.
## Up / down / left / right movement across the wall face.
## Jump = leap off the wall (away from it). Crouch = let go and fall.
## Climbing over the top edge automatically vaults the player up.

@export var climb_speed: float = 4.0
@export var wall_offset: float = 0.55       # How far the player's center sits off the wall
@export var jump_off_speed: float = 8.0     # Push-off speed when jumping from the wall
@export var jump_off_up_speed: float = 6.0  # Upward speed when jumping from the wall
@export var vault_up_boost: float = 6.5     # Upward pop when climbing over the top edge

var wall_normal: Vector3 = Vector3.ZERO
var wall_point: Vector3 = Vector3.ZERO

func setup(normal: Vector3, point: Vector3):
	wall_normal = Vector3(normal.x, 0, normal.z).normalized()
	wall_point = point

func enter():
	player.velocity = Vector3.ZERO
	
	# Face into the wall
	var face = -wall_normal
	player.rotation.y = atan2(-face.x, -face.z)
	
	# Snap to the wall at the proper offset
	_snap_to_wall()
	
	# Grab feedback
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.92, 1.08, 0.92), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func physics_update(delta: float):
	# Jump: leap off the wall, away from it
	if Input.is_action_just_pressed("jump"):
		player.velocity = wall_normal * jump_off_speed
		player.velocity.y = jump_off_up_speed
		player.climb_regrab_timer = player.climb_regrab_delay
		# Face away from the wall for the leap
		player.rotation.y = atan2(-wall_normal.x, -wall_normal.z) + PI
		change_to("JumpingState")
		return
	
	# Crouch: let go and drop
	if Input.is_action_just_pressed("crouch"):
		player.velocity = wall_normal * 1.5
		player.velocity.y = 0.0
		player.climb_regrab_timer = player.climb_regrab_delay
		change_to("FallingState")
		return
	
	# Movement across the wall face:
	# left/right = along the wall, forward/back = up/down the wall
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	var side_axis = wall_normal.cross(Vector3.UP).normalized()  # "left" along the wall
	var move = side_axis * -input_dir.x + Vector3.UP * -input_dir.y
	
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
		else:
			# Edge of the wall (side or bottom): stop
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
