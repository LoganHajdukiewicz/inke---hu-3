extends State
class_name RopeSwingState

## Hanging from a SwingRope:
##  - left/right/forward/back input pumps the swing (pendulum physics,
##    same feel as the grapple swing)
##  - forward/back while holding "run"... no: climbing is on separate axis -
##    UP/DOWN on the stick climbs the rope when barely swinging, and the
##    dedicated climb also works mid-swing with camera-relative up/down:
##    push toward the camera's up (forward) = climb, back = descend.
##  - jump: launch off in facing direction with swing momentum
##  - crouch: let go and just fall

@export var swing_control_strength: float = 9.0
@export var max_swing_speed: float = 22.0
@export var climb_speed: float 	= 2.8
@export var jump_off_up_speed: float = 7.0
@export var release_boost: float = 4.0
@export var max_swing_angle_degrees: float = 95.0  # Same auto-launch as grapple
@export var auto_launch_speed: float = 13.0

var rope: SwingRope = null
var hold_distance: float = 4.0   # Current distance from anchor (climbing changes it)

func setup(new_rope: SwingRope):
	rope = new_rope

func enter():
	if not rope or not is_instance_valid(rope):
		change_to("FallingState")
		return
	
	var anchor = rope.global_position
	hold_distance = clampf(player.global_position.distance_to(anchor), rope.min_grab_distance, rope.rope_length)
	rope.set_attached(player)
	
	# Damp the grab-on velocity a bit (catching the rope costs energy)
	player.velocity *= 0.75
	
	# Refresh air options - grabbing a rope resets the air state
	player.can_double_jump = true
	player.has_double_jumped = false
	player.can_air_dash = true
	player.has_air_dashed = false
	
	# Grab feedback
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.9, 1.1, 0.9), 0.08)
	tween.tween_property(player, "scale", Vector3.ONE, 0.1)

func physics_update(delta: float):
	if not rope or not is_instance_valid(rope):
		change_to("FallingState")
		return
	
	var anchor = rope.global_position
	
	# --- RELEASE INPUTS ---
	if Input.is_action_just_pressed("jump"):
		_launch_off()
		return
	if Input.is_action_just_pressed("crouch"):
		_let_go(Vector3.ZERO)
		return
	
	# --- CLIMB UP / DOWN THE ROPE ---
	# forward = climb up, back = slide down
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if abs(input_dir.y) > 0.4:
		var climb_delta = input_dir.y * climb_speed * delta  # forward is negative y
		hold_distance = clampf(hold_distance + climb_delta, rope.min_grab_distance, rope.rope_length)
	
	# Climbed off the bottom end? Let go.
	if hold_distance >= rope.rope_length - 0.01 and input_dir.y > 0.6:
		_let_go(Vector3.ZERO)
		return
	
	# --- PENDULUM PHYSICS (same model as grapple swing) ---
	player.velocity += player.get_gravity() * delta
	
	# Pump the swing with left/right (sideways relative to camera)
	if abs(input_dir.x) > 0.15:
		var camera_basis = player.get_node("CameraController").transform.basis
		var wish: Vector3 = (camera_basis * Vector3(input_dir.x, 0, 0)).normalized()
		var to_anchor = (anchor - player.global_position).normalized()
		var perpendicular = wish - to_anchor * wish.dot(to_anchor)
		player.velocity += perpendicular * swing_control_strength * delta
	
	# Rope constraint at hold_distance
	var to_anchor_vec = anchor - player.global_position
	var dist = to_anchor_vec.length()
	var dir_to_anchor = to_anchor_vec.normalized()
	
	if dist >= hold_distance:
		# Kill outward radial velocity (rope tension)
		var radial_velocity = player.velocity.dot(dir_to_anchor)
		if radial_velocity < 0:
			player.velocity -= dir_to_anchor * radial_velocity
		# POSITION-based overshoot correction (stable, no spring energy):
		# smoothly reel the player in toward hold_distance. This is also what
		# physically pulls you up the rope while climbing.
		var excess = dist - hold_distance
		if excess > 0.001:
			var correction = minf(excess, (climb_speed + 4.0) * delta)
			player.global_position += dir_to_anchor * correction
	
	# Auto-launch past the top of the arc (matches grapple behavior)
	var from_anchor = player.global_position - anchor
	var angle_from_down = rad_to_deg(Vector3.DOWN.angle_to(from_anchor.normalized()))
	if angle_from_down >= max_swing_angle_degrees:
		_launch_off(true)
		return
	
	# Speed cap
	if player.velocity.length() > max_swing_speed:
		player.velocity = player.velocity.normalized() * max_swing_speed
	
	# Face along horizontal velocity
	var h = Vector2(player.velocity.x, player.velocity.z)
	if h.length() > 1.5:
		var face = Vector3(h.x, 0, h.y).normalized()
		player.rotation.y = lerp_angle(player.rotation.y, atan2(-face.x, -face.z), 8.0 * delta)
	
	player.move_and_slide()
	
	# Landed on something while swinging low? Get off the rope.
	if player.is_on_floor():
		_let_go(Vector3.ZERO)

func _launch_off(auto: bool = false):
	"""Jump off the rope in the facing direction, keeping swing momentum."""
	var facing = -player.global_transform.basis.z
	facing.y = 0
	if facing.length() < 0.1:
		var h = Vector3(player.velocity.x, 0, player.velocity.z)
		facing = h.normalized() if h.length() > 0.1 else Vector3.FORWARD
	else:
		facing = facing.normalized()
	
	var speed = Vector3(player.velocity.x, 0, player.velocity.z).length()
	speed = maxf(speed + release_boost, auto_launch_speed if auto else speed + release_boost)
	speed = minf(speed, max_swing_speed + release_boost)
	
	player.velocity = facing * speed
	player.velocity.y = jump_off_up_speed
	
	_detach()
	change_to("FallingState")

func _let_go(extra_velocity: Vector3):
	player.velocity *= 0.5
	player.velocity += extra_velocity
	_detach()
	if player.is_on_floor():
		change_to("IdleState")
	else:
		change_to("FallingState")

func _detach():
	if rope and is_instance_valid(rope):
		rope.clear_attached(player)
	rope = null

func get_speed() -> float:
	return player.velocity.length() if player else 0.0

func exit():
	if rope and is_instance_valid(rope):
		rope.clear_attached(player)
	rope = null
	player.scale = Vector3.ONE
