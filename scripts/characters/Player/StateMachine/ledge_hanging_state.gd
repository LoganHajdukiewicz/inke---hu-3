extends State
class_name LedgeHangingState

## Proper ledge hang:
##  - Grabbing smoothly pulls you into a HANG below the lip (no teleport to top)
##  - Left/right shimmies along the edge (with end-of-ledge checks)
##  - Jump or forward = pull yourself up (two-stage animated climb)
##  - Crouch or back = drop off
## The player's ORIGIN is at their feet, so hanging means origin sits
## ~hang_depth below the ledge surface.

@export var shimmy_speed: float = 2.5
@export var climb_up_duration: float = 0.45
@export var hang_depth: float = 1.35      # Feet this far below the ledge lip while hanging
@export var hang_offset: float = 0.45     # Body this far off the wall face
@export var grab_settle_time: float = 0.12  # Smooth pull-in instead of a snap
@export var input_grace: float = 0.15     # Ignore climb/drop inputs right after grabbing

var ledge_position: Vector3 = Vector3.ZERO  # Point on TOP of the ledge at the lip
var ledge_normal: Vector3 = Vector3.ZERO    # Wall normal (points away from the wall)
var is_climbing: bool = false
var is_settling: bool = false
var grace_timer: float = 0.0
var shimmy_direction: float = 0.0

func setup_ledge_hang(ledge_pos: Vector3, wall_normal: Vector3):
	ledge_position = ledge_pos
	ledge_normal = Vector3(wall_normal.x, 0, wall_normal.z).normalized()

func enter():
	is_climbing = false
	grace_timer = input_grace
	player.velocity = Vector3.ZERO
	player.set("gravity", 0.0)
	
	if ledge_position == Vector3.ZERO or ledge_normal == Vector3.ZERO:
		change_to("FallingState")
		return
	
	# Face the wall
	player.rotation.y = atan2(ledge_normal.x, ledge_normal.z)
	
	# Smoothly pull into the hang position (no snap/teleport)
	is_settling = true
	var hang_pos = _hang_position_for(ledge_position)
	var tween = create_tween()
	tween.tween_property(player, "global_position", hang_pos, grab_settle_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): is_settling = false)
	
	# Grab feedback - little stretch as the arms catch
	var fx = create_tween()
	fx.tween_property(player, "scale", Vector3(0.9, 1.12, 0.9), 0.1)
	fx.tween_property(player, "scale", Vector3.ONE, 0.12)

func _hang_position_for(lip_point: Vector3) -> Vector3:
	"""Where the player's origin (feet) goes for a hang at this lip point."""
	var pos = lip_point
	pos.y = lip_point.y - hang_depth
	pos += ledge_normal * hang_offset
	return pos

func physics_update(delta: float):
	if is_climbing or is_settling:
		return
	
	player.velocity = Vector3.ZERO
	
	if grace_timer > 0.0:
		grace_timer -= delta
		return
	
	# --- INPUTS ---
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	
	# Pull up: jump or push toward the wall (stick forward)
	if Input.is_action_just_pressed("jump") or input_dir.y < -0.6:
		climb_up_ledge()
		return
	
	# Drop: crouch or pull away from the wall (stick back)
	if Input.is_action_just_pressed("crouch") or input_dir.y > 0.6:
		drop_from_ledge()
		return
	
	# Shimmy left/right along the lip
	if abs(input_dir.x) > 0.15:
		shimmy_along_ledge(input_dir.x, delta)
	else:
		shimmy_direction = 0.0

func shimmy_along_ledge(direction: float, delta: float):
	"""Slide sideways along the ledge, staying attached to the lip."""
	shimmy_direction = direction
	
	# Sideways axis along the wall face ("right" when facing the wall)
	var side_axis = Vector3.UP.cross(ledge_normal).normalized()
	var step = side_axis * -direction * shimmy_speed * delta
	var candidate_lip = ledge_position + step
	
	# Is there still a ledge (wall + top surface) at the candidate position?
	var probe = _probe_ledge_at(candidate_lip)
	if probe.is_empty():
		shimmy_direction = 0.0
		return
	
	# Follow the actual geometry (handles slight curves/steps in the lip)
	ledge_position = probe.lip
	ledge_normal = probe.normal
	player.global_position = _hang_position_for(ledge_position)
	player.rotation.y = lerp_angle(player.rotation.y, atan2(ledge_normal.x, ledge_normal.z), 10.0 * delta)
	
	# Shimmy wobble - alternate lean
	var lean = sin(Time.get_ticks_msec() * 0.02) * 0.04
	player.rotation.z = lean

func _probe_ledge_at(lip_point: Vector3) -> Dictionary:
	"""Check for a grabbable lip near lip_point.
	Returns { lip: Vector3, normal: Vector3 } or {}."""
	var space_state = player.get_world_3d().direct_space_state
	
	# 1) Wall must exist just below the lip, in front of the hang position
	var wall_from = lip_point + ledge_normal * (hang_offset + 0.4)
	wall_from.y = lip_point.y - 0.35
	var wall_to = wall_from - ledge_normal * (hang_offset + 0.9)
	var wall_query = PhysicsRayQueryParameters3D.create(wall_from, wall_to)
	wall_query.collision_mask = 1
	wall_query.exclude = [player]
	var wall_hit = space_state.intersect_ray(wall_query)
	if not wall_hit:
		return {}
	var new_normal = Vector3(wall_hit.normal.x, 0, wall_hit.normal.z)
	if new_normal.length() < 0.5:
		return {}
	new_normal = new_normal.normalized()
	
	# 2) Top surface must exist just behind the lip
	var top_from = wall_hit.position - new_normal * 0.25
	top_from.y = lip_point.y + 0.6
	var top_to = top_from + Vector3(0, -1.2, 0)
	var top_query = PhysicsRayQueryParameters3D.create(top_from, top_to)
	top_query.collision_mask = 1
	top_query.exclude = [player]
	var top_hit = space_state.intersect_ray(top_query)
	if not top_hit or top_hit.normal.dot(Vector3.UP) < 0.7:
		return {}
	
	var lip = top_hit.position
	# Keep the lip point exactly at the wall face
	var wall_face = wall_hit.position
	lip.x = wall_face.x
	lip.z = wall_face.z
	
	return {"lip": lip, "normal": new_normal}

func climb_up_ledge():
	"""Two-stage pull up: rise until the body clears the lip, then move
	forward onto the surface."""
	if is_climbing:
		return
	is_climbing = true
	
	var up_target = player.global_position
	up_target.y = ledge_position.y + 0.05
	
	var forward_target = up_target - ledge_normal * (hang_offset + 0.55)
	
	var tween = create_tween()
	# Stage 1: pull the body straight up
	tween.tween_property(player, "global_position", up_target, climb_up_duration * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# Stage 2: move forward over the lip
	tween.tween_property(player, "global_position", forward_target, climb_up_duration * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Effort squash-and-stretch
	var fx = create_tween()
	fx.tween_property(player, "scale", Vector3(0.88, 1.15, 0.88), climb_up_duration * 0.5)
	fx.tween_property(player, "scale", Vector3.ONE, climb_up_duration * 0.5)
	
	await tween.finished
	
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
		change_to("IdleState")

func drop_from_ledge():
	"""Let go and fall, drifting slightly away from the wall."""
	player.velocity = ledge_normal * 2.0
	player.velocity.y = -1.0
	change_to("FallingState")

func exit():
	is_climbing = false
	is_settling = false
	player.scale = Vector3.ONE
	player.rotation.z = 0.0
	
	# Restore gravity
	var default_gravity = player.get("gravity_default")
	if default_gravity != null:
		player.set("gravity", default_gravity)
