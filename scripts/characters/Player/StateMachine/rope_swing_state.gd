extends State
class_name RopeSwingState

## Hanging from a SwingRope:
##  - ALL stick / WASD input pumps the swing (pendulum physics, same feel
##    as the grapple swing). W/S swing you forward-back, A/D side to side.
##  - heavy_attack (Triangle / X key) = climb UP the rope
##  - crouch (L2 / Z key) = climb DOWN - slide past the end to let go
##  - jump (Cross / Space) = launch off in facing direction with momentum

@export var swing_control_strength: float = 9.0
@export var max_swing_speed: float = 22.0
@export var climb_speed: float 	= 2.8
@export var jump_off_up_speed: float = 7.0
@export var release_boost: float = 4.0
@export var max_swing_angle_degrees: float = 95.0  # Same auto-launch as grapple
@export var auto_launch_speed: float = 13.0

@export_category("Exit Momentum")
## How much swing momentum survives LETTING GO (crouch-off / sliding off the
## end / touching ground). 1.0 = keep everything, 0.5 was the old hardcoded
## value that felt over-damped.
@export_range(0.0, 1.0) var let_go_momentum_keep: float = 0.9
## Extra cap applied to the jump-off launch. Raise it if big swings should
## throw you further.
@export var max_launch_speed: float = 26.0

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
	
	# --- CLIMB UP / DOWN THE ROPE ---
	# heavy_attack (Triangle / X key) climbs up, crouch (L2 / Z key) climbs down
	if Input.is_action_pressed("heavy_attack"):
		hold_distance = clampf(hold_distance - climb_speed * delta, rope.min_grab_distance, rope.rope_length)
	if Input.is_action_pressed("crouch"):
		hold_distance = hold_distance + climb_speed * delta
		# Slid off the bottom end of the rope? Let go.
		if hold_distance >= rope.rope_length + 0.15:
			_let_go(Vector3.ZERO)
			return
		hold_distance = minf(hold_distance, rope.rope_length + 0.2)
	
	# --- PENDULUM PHYSICS (same model as grapple swing) ---
	player.velocity += player.get_gravity() * delta
	
	# Pump the swing with the FULL stick / WASD: W/S = forward-back swing,
	# A/D = sideways swing (all camera-relative, projected onto the swing plane)
	var input_dir = Input.get_vector("left", "right", "forward", "back")
	if input_dir.length() > 0.15:
		var camera_basis = player.get_node("CameraController").transform.basis
		var wish: Vector3 = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
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
	
	# Preserve the FULL earned swing speed (horizontal + a share of vertical
	# rise), then add the boost. The old version dropped all vertical energy.
	var h_speed = Vector3(player.velocity.x, 0, player.velocity.z).length()
	var rising = maxf(player.velocity.y, 0.0)
	var speed = h_speed + rising * 0.5 + release_boost
	if auto:
		speed = maxf(speed, auto_launch_speed)
	speed = minf(speed, max_launch_speed)
	
	player.velocity = facing * speed
	player.velocity.y = maxf(jump_off_up_speed, rising * 0.6 + 4.0)
	
	_detach()
	change_to("FallingState")

func _let_go(extra_velocity: Vector3):
	# Inspector-tunable momentum preservation (was a hardcoded 0.5 damp)
	player.velocity *= let_go_momentum_keep
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
