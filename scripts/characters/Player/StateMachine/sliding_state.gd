extends State
class_name SlidingState

## Two sliding behaviors share this state:
## 1. SLIDING floors (Mario 64 style): forced downhill slide along the slope.
##    You accelerate downhill, can steer left/right, and can't walk back up.
## 2. FROZEN floors: legacy momentum slide (kept for compatibility when the
##    player enters this state on ice).

const BASE_SLIDE_SPEED: float = 10.0
const SLIDE_FRICTION: float = 0.98
const MIN_SLIDE_SPEED: float = 0.5
const ROTATION_SPEED: float = 8.0
const SLIDE_CONTROL_STRENGTH: float = 0.5
const MAX_SLIDE_SPEED: float = 70.0  # Absolute safety cap

# Downhill slide defaults (used if the floor doesn't provide tuning)
const DEFAULT_DOWNHILL_MAX_SPEED: float = 30.0
const DEFAULT_DOWNHILL_ACCEL: float = 25.0
const DEFAULT_STEERING: float = 6.0

var slide_velocity: Vector3 = Vector3.ZERO
var slide_direction: Vector3 = Vector3.ZERO
var initial_slide_speed: float = 10.0
var was_on_sliding_floor: bool = false
var _air_grace: float = 0.0            # Seconds tolerated off the ground
var _saved_snap_length: float = 0.1

func enter():
	was_on_sliding_floor = false
	_air_grace = 0.0
	# GROUND LOCK: long floor snap glues the player over bumps/seams so
	# sliding down never pops her airborne without a jump.
	_saved_snap_length = player.floor_snap_length
	player.floor_snap_length = 1.5
	# Get the player's current horizontal velocity
	var current_horizontal_velocity = Vector3(player.velocity.x, 0, player.velocity.z)
	var current_speed = current_horizontal_velocity.length()
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if current_speed > 0.0:
		slide_direction = current_horizontal_velocity.normalized()
		initial_slide_speed = current_speed
	elif input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		slide_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		initial_slide_speed = BASE_SLIDE_SPEED
	else:
		# Standing still: on a sliding floor gravity will take over via the
		# downhill physics; otherwise exit.
		if _get_sliding_floor() == null:
			call_deferred("change_to", "IdleState")
			return
		slide_direction = Vector3.ZERO
		initial_slide_speed = 0.0
	
	slide_velocity = slide_direction * initial_slide_speed
	
	# On a SLIDING floor, strip any uphill component IMMEDIATELY - previously
	# the seeded velocity could point uphill for one frame (the turnaround
	# exploit frame) before the per-frame strip kicked in.
	if player.is_on_slide_floor and player.slide_floor_downhill != Vector3.ZERO:
		var uphill = -player.slide_floor_downhill
		var uphill_amount = slide_velocity.dot(uphill)
		if uphill_amount > 0.0:
			slide_velocity -= uphill * uphill_amount
			slide_direction = slide_velocity.normalized() if slide_velocity.length() > 0.1 else Vector3.ZERO
	
	player.velocity.x = slide_velocity.x
	player.velocity.z = slide_velocity.z

func physics_update(delta: float):
	# Allow grapple hook exit
	if Input.is_action_just_pressed("yoyo"):
		change_to("GrappleHookState")
		return
	
	# Allow dash exit - but you can NOT dash your way up the slide. Arm the
	# uphill block first so the dash (which strips uphill velocity every
	# frame via apply_slide_uphill_block) can only go sideways/downhill.
	if Input.is_action_just_pressed("dash"):
		var dodge_dash_state = player.state_machine.states.get("dodgedashstate")
		if dodge_dash_state and dodge_dash_state.can_perform_dash():
			player.arm_slide_uphill_block(0.9)
			change_to("DodgeDashState")
			return
	
	# Leaving the ground: GRACE window instead of instant exit. Bumps and
	# floor seams used to pop the player airborne mid-slide - now we shove
	# her back onto the slope for up to 0.25s; only a real drop-off exits.
	# (Jumping exits through the jump branch below, never through here.)
	if not player.is_on_floor():
		_air_grace += delta
		if _air_grace > 0.25:
			player.velocity += player.get_gravity() * delta
			change_to("FallingState")
			return
		# Hard downward shove + snap to re-stick on the slope
		player.velocity.y = minf(player.velocity.y, -8.0)
		player.move_and_slide()
		player.apply_floor_snap()
		return
	_air_grace = 0.0
	
	# Allow jump exit. Jumping off a SLIDING floor arms the anti-climb block:
	# for a short window, air control cannot add uphill velocity, so spamming
	# jump can no longer walk you up a slide slope.
	if Input.is_action_just_pressed("jump") and not player.ignore_next_jump:
		if _get_sliding_floor() != null:
			player.arm_slide_uphill_block()
		change_to("JumpingState")
		return
	
	# ---- Mario 64 style downhill slide on SLIDING floors -------------------
	var sliding_floor = _get_sliding_floor()
	if sliding_floor != null:
		was_on_sliding_floor = true
		_apply_downhill_slide(delta, sliding_floor)
		player.move_and_slide()
		player.apply_floor_snap()   # Glued to the slope (ground lock)
		return
	
	# ---- EJECT: the slide ended (crossed onto a normal floor) --------------
	# Leave the state immediately, KEEPING the slide momentum, so the player
	# runs out of the slide instead of freezing at the seam between floors.
	if was_on_sliding_floor and not _is_on_frozen_floor():
		var exit_speed = Vector2(player.velocity.x, player.velocity.z).length()
		if exit_speed > MIN_SLIDE_SPEED:
			change_to("RunningState")
		else:
			change_to("IdleState")
		return
	
	# ---- Legacy momentum slide (frozen floors etc.) -------------------------
	var on_frozen = _is_on_frozen_floor()
	
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	if input_dir.length() > 0.1:
		var camera_basis = player.get_node("CameraController").transform.basis
		var input_direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		slide_direction = slide_direction.lerp(input_direction, SLIDE_CONTROL_STRENGTH * delta).normalized()
	
	var current_horizontal = Vector2(player.velocity.x, player.velocity.z)
	var current_speed = current_horizontal.length()
	
	current_speed = max(current_speed - SLIDE_FRICTION * delta, 0.0)
	
	if current_speed > MAX_SLIDE_SPEED:
		current_speed = MAX_SLIDE_SPEED
	
	# Stop sliding if speed gets too low AND we're not on frozen floor
	if current_speed < MIN_SLIDE_SPEED and not on_frozen:
		var stop_input_dir = Input.get_vector("left", "right", "forward", "back")
		if stop_input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
		else:
			change_to("IdleState")
		return
	
	# Transition check for non-frozen floors
	if not on_frozen and current_speed > MIN_SLIDE_SPEED:
		var exit_input_dir = Input.get_vector("left", "right", "forward", "back")
		if exit_input_dir.length() > 0.1:
			if Input.is_action_pressed("run"):
				change_to("RunningState")
			else:
				change_to("WalkingState")
			return
	
	slide_velocity = slide_direction * current_speed
	
	if slide_direction.length() > 0.1:
		var target_rotation = atan2(-slide_direction.x, -slide_direction.z)
		var rotation_factor = ROTATION_SPEED * (1.0 + current_speed / MAX_SLIDE_SPEED)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, rotation_factor * delta)
	
	player.velocity.x = slide_velocity.x
	player.velocity.z = slide_velocity.z
	
	player.move_and_slide()

func _apply_downhill_slide(delta: float, floor_node) -> void:
	"""Mario 64 slide: accelerate down the slope, steer sideways, never climb."""
	# Tuning from the floor (with fallbacks)
	var max_speed: float = DEFAULT_DOWNHILL_MAX_SPEED
	var accel: float = DEFAULT_DOWNHILL_ACCEL
	var steering: float = DEFAULT_STEERING
	if floor_node.get("slide_max_speed") != null:
		max_speed = floor_node.slide_max_speed
	if floor_node.get("slide_acceleration") != null:
		accel = floor_node.slide_acceleration
	if floor_node.get("slide_steering_strength") != null:
		steering = floor_node.slide_steering_strength
	
	# Downhill direction from the surface normal:
	# project gravity onto the slope plane.
	var normal: Vector3 = player.get_floor_normal()
	var downhill: Vector3 = (Vector3.DOWN - normal * Vector3.DOWN.dot(normal))
	var is_flat := downhill.length() < 0.01
	if not is_flat:
		downhill = downhill.normalized()
	
	var vel := Vector3(player.velocity.x, 0, player.velocity.z)
	
	if is_flat:
		# Flat section of a slide (e.g. runout at the bottom): keep momentum,
		# bleed speed gently so the player can eventually exit.
		var speed := vel.length()
		speed = max(speed - accel * 0.5 * delta, 0.0)
		if speed < MIN_SLIDE_SPEED:
			var end_input := Input.get_vector("left", "right", "forward", "back")
			if end_input.length() > 0.1:
				change_to("WalkingState")
			else:
				change_to("IdleState")
			return
		vel = vel.normalized() * speed
	else:
		# Accelerate downhill
		vel += Vector3(downhill.x, 0, downhill.z).normalized() * accel * delta
		
		# Steering: only the component of input PERPENDICULAR to downhill is
		# applied. Input against the slope is ignored -> you can't climb back up.
		var input_dir := Input.get_vector("left", "right", "forward", "back")
		if input_dir.length() > 0.1:
			var camera_basis = player.get_node("CameraController").transform.basis
			var wish: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
			var downhill_flat := Vector3(downhill.x, 0, downhill.z).normalized()
			var side_axis := downhill_flat.cross(Vector3.UP).normalized()
			var side_amount := wish.dot(side_axis)
			vel += side_axis * side_amount * steering * delta * 4.0
		
		# Clamp to the slide's max speed
		if vel.length() > max_speed:
			vel = vel.normalized() * max_speed
		
		# ANTI-EXPLOIT: strip ANY uphill velocity component every single frame.
		# Previously the turnaround left one frame where stale velocity could
		# point uphill, letting frame-perfect inputs inch up the slope.
		var downhill_flat2 := Vector3(downhill.x, 0, downhill.z).normalized()
		var uphill_amount := vel.dot(-downhill_flat2)
		if uphill_amount > 0.0:
			vel -= -downhill_flat2 * uphill_amount
	
	player.velocity.x = vel.x
	player.velocity.z = vel.z
	
	# Keep the player glued to the slope while descending
	if player.velocity.y > 0:
		player.velocity.y = 0
	player.velocity.y -= 20.0 * delta
	
	# Face the slide direction - and NEVER face uphill. Clamping only the
	# lerp TARGET still let the CURRENT rotation point uphill while the
	# lerp caught up (the 'single frame turn'). Now the actual rotation is
	# HARD-clamped to downhill +/- 85 degrees every frame after the lerp -
	# there is no frame where the player faces up the slide.
	if not is_flat:
		var downhill_face := Vector3(downhill.x, 0, downhill.z).normalized()
		var downhill_rotation := atan2(-downhill_face.x, -downhill_face.z)
		var max_off := deg_to_rad(85.0)
		if vel.length() > 1.0:
			var face := vel.normalized()
			var target_rotation := atan2(-face.x, -face.z)
			var off_downhill := angle_difference(downhill_rotation, target_rotation)
			target_rotation = downhill_rotation + clampf(off_downhill, -max_off, max_off)
			player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
		# HARD clamp the actual rotation (not just the target)
		var cur_off := angle_difference(downhill_rotation, player.rotation.y)
		if absf(cur_off) > max_off:
			player.rotation.y = downhill_rotation + clampf(cur_off, -max_off, max_off)
	elif vel.length() > 1.0:
		var face := vel.normalized()
		var target_rotation := atan2(-face.x, -face.z)
		player.rotation.y = lerp_angle(player.rotation.y, target_rotation, ROTATION_SPEED * delta)
	
	slide_velocity = vel

func _get_sliding_floor():
	"""Return the SLIDING floor under the player, or null"""
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3(0, 0.1, 0),
		player.global_position + Vector3(0, -1.2, 0)
	)
	query.collision_mask = 1
	query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider is Floor and collider.has_floor_type(Floor.FloorType.SLIDING):
			return collider
		# CurvedFloor: the body's PARENT owns the floor type (duck-typed)
		var parent = collider.get_parent() if collider else null
		if parent and parent.has_method("has_floor_type") and parent.has_floor_type(Floor.FloorType.SLIDING):
			return parent
	return null

func _is_on_frozen_floor() -> bool:
	"""Check if the player is currently on a frozen floor"""
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position,
		player.global_position + Vector3(0, -1.1, 0)
	)
	query.collision_mask = 1
	query.exclude = [player]
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider is Floor:
			return collider.has_floor_type(Floor.FloorType.FROZEN)
		var parent = collider.get_parent() if collider else null
		if parent and parent.has_method("has_floor_type"):
			return parent.has_floor_type(Floor.FloorType.FROZEN)
	return false

func get_speed() -> float:
	return slide_velocity.length()

func exit():
	# Restore normal floor snapping (ground lock off)
	player.floor_snap_length = _saved_snap_length
	# DON'T clear slide velocity - preserve momentum!
