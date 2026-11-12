extends Node3D
## Third-person camera rig - v3 (smooth + clip-proof).
##
## FRAMING matches the Unity build exactly (same on-screen size of Inke):
##   Unity: 8.5m arm, 1.8m pivot, 32.6deg down, 70deg FOV for a 1.5m capsule
##   Godot Inke is ~1.72m tall, so distance/pivot scale by 1.72/1.5:
##   9.75m arm, 2.06m pivot, 32.6deg down, 70deg FOV.
##   Inke's height = 9.3% of the screen, feet at 38.6% from the bottom -
##   identical to Unity (verified with the projection math in docs).
##
## Node structure (rebuilt in _ready, reusing the scene's Camera3D):
##   CameraController  (top_level - smoothed follow position + YAW)
##     CameraTarget    (pivot at head height - PITCH)
##       Camera3D      (placed by code along the arm - no SpringArm)
##
## WHY NO SpringArm3D: the arm only updates in physics ticks, so on a 144Hz
## screen the camera stepped at 60Hz (judder) and its single sphere cast
## let thin walls/corners poke into the near plane. This rig:
##   - sweeps a sphere AND checks the near-plane rectangle every RENDER frame
##   - pulls in instantly, eases back out (never yanks, never shows a wall)
##   - follows a physics-interpolated target so motion is smooth at any FPS
##   - never puts the camera inside geometry after a teleport/respawn
##
## External API kept: handle_camera_input(delta), follow_character(pos, vel),
## initialize_camera(), get_camera_forward()/get_camera_right(),
## shake(), start_zoom_effect(), auto_behind, lock-on API, transform.basis
## (yaw-only - movement code reads this).

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
@export_group("Look")
@export var mouse_sensitivity: float = 0.002
## Right-stick turn speed (radians/sec at full deflection).
@export var controller_sensitivity: float = 2.4
@export var invert_y: bool = false
## Right-stick response curve: >1 = finer aim near centre, fast at the edge.
@export_range(1.0, 3.0, 0.1) var stick_curve: float = 1.6
## Stick input is eased in/out over this time so turning starts/stops smoothly.
@export_range(0.0, 0.3, 0.01) var stick_smoothing: float = 0.08
## Lowest the camera can look (degrees, negative = down).
@export var pitch_min_degrees: float = -65.0
## Highest the camera can look (degrees).
@export var pitch_max_degrees: float = 45.0

@export_group("Framing (matches Unity)")
## Distance behind the player. 9.75 = Unity's 8.5m framing at Godot scale.
@export var camera_distance: float = 9.75
## Pivot height above the player's feet.
@export var pivot_height: float = 2.06
## Default downward look angle (degrees, negative = looking down).
@export var default_pitch_degrees: float = -32.6
## Base field of view (Unity uses 70).
@export var base_fov: float = 70.0

@export_group("Follow")
## How quickly the rig catches up to the player (higher = snappier).
@export var follow_speed: float = 10.0
## Extra catch-up at high speed so fast movement never outruns the camera.
@export var follow_speed_fast: float = 16.0
@export var fast_speed_threshold: float = 12.0
## Vertical follow is softer, so jumps don't bob the whole screen.
@export_range(0.1, 1.0, 0.05) var vertical_follow_ratio: float = 0.55
## Max distance the rig may lag behind before it snaps (teleports, respawns).
@export var snap_distance: float = 25.0

@export_group("Collision")
## Physics layers the camera collides with (world geometry).
@export_flags_3d_physics var collision_mask: int = 1
## Radius of the swept sphere (keeps the near plane out of walls/corners).
@export var collision_radius: float = 0.35
## Extra gap kept between the camera and what it hit.
@export var collision_margin: float = 0.15
## Closest the camera may get to the pivot.
@export var min_distance: float = 1.2
## How fast the camera eases back OUT after an obstruction clears (m/s-ish).
@export var reexpand_speed: float = 5.0
## Small things (fences, poles, NPCs) can't yank the camera in: obstructions
## must stay for this long before the camera moves for them. Walls behind
## the camera always pull in instantly regardless.
@export_range(0.0, 0.5, 0.01) var thin_obstruction_grace: float = 0.12

@export_group("Speed FOV")
@export var fov_kick_enabled: bool = true
@export var max_fov: float = 86.0
@export var fov_kick_start_speed: float = 12.0
@export var fov_max_speed: float = 40.0
@export var fov_lerp_speed: float = 4.0

@export_group("Lock On")
@export var lock_on_range: float = 30.0
@export var lock_on_turn_speed: float = 8.0
@export var lock_on_switch_cooldown: float = 0.3

const AUTO_BEHIND_SPEED := 5.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var twist_input: float = 0.0          # yaw (radians)
var pitch_input: float = 0.0          # pitch (radians)
var mouse_captured: bool = false

var lock_on_active: bool = false
var locked_target: Node3D = null
var lock_on_switch_timer: float = 0.0

## Set by the player while on a balance beam: camera swings behind.
var auto_behind: bool = false

var character: Node3D = null
var camera_target: Node3D = null      # pitch pivot
var camera_3d: Camera3D = null
## Back-compat: some scenes/tools reference spring_arm; it's always null now.
var spring_arm: SpringArm3D = null

var _rad_pitch_min: float
var _rad_pitch_max: float
var _current_distance: float = 0.0
var _blocked_time: float = 0.0
var _stick_smoothed := Vector2.ZERO
var _follow_target := Vector3.ZERO
var _follow_velocity := Vector3.ZERO
var _prev_target := Vector3.ZERO
var _target_time := 0.0

var shake_time_left: float = 0.0
var shake_strength: float = 0.0
var shake_offset: Vector3 = Vector3.ZERO
var _zoom_fov_offset: float = 0.0


func _ready():
	_rad_pitch_min = deg_to_rad(pitch_min_degrees)
	_rad_pitch_max = deg_to_rad(pitch_max_degrees)
	pitch_input = deg_to_rad(default_pitch_degrees)
	if get_parent() is CharacterBody3D:
		character = get_parent()
	_build_rig()
	if character:
		global_position = character.global_position
		_follow_target = global_position
		_prev_target = global_position
		rotation.y = character.rotation.y
		twist_input = character.rotation.y
	_current_distance = camera_distance
	# Render-rate update: run after the player's physics so we read its
	# latest position, and every frame so the camera never judders.
	process_priority = 100


func _build_rig() -> void:
	camera_target = get_node_or_null("CameraTarget")
	if camera_target == null:
		camera_target = Node3D.new()
		camera_target.name = "CameraTarget"
		add_child(camera_target)
	camera_target.transform = Transform3D.IDENTITY
	camera_target.position = Vector3(0, pivot_height, 0)
	camera_3d = _find_camera(self)
	if camera_3d == null:
		camera_3d = Camera3D.new()
		camera_3d.name = "Camera3D"
		camera_3d.current = true
	if camera_3d.get_parent() != camera_target:
		if camera_3d.get_parent():
			camera_3d.get_parent().remove_child(camera_3d)
		camera_target.add_child(camera_3d)
	camera_3d.transform = Transform3D(Basis(), Vector3(0, 0, camera_distance))
	camera_3d.fov = base_fov
	camera_3d.near = 0.05


func _find_camera(node: Node) -> Camera3D:
	for c in node.get_children():
		if c is Camera3D:
			return c
		var found := _find_camera(c)
		if found:
			return found
	return null


func initialize_camera():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mouse_captured = true


# ---------------------------------------------------------------------------
# Per-frame driving
# ---------------------------------------------------------------------------
func _process(delta: float):
	_update_shake(delta)
	if lock_on_switch_timer > 0.0:
		lock_on_switch_timer -= delta
	if Input.is_action_just_pressed("lock_on"):
		toggle_lock_on()
	if lock_on_active and lock_on_switch_timer <= 0.0:
		_check_lock_on_switch()
	_update_look(delta)
	_update_follow(delta)
	_update_arm(delta)


## Kept for the player's physics loop. Look input now runs per render
## frame in _process (smoother), so this only updates the FOV kick.
func handle_camera_input(delta: float):
	_update_fov_kick(delta)


func _update_look(delta: float) -> void:
	if lock_on_active and is_instance_valid(locked_target):
		_handle_lock_on_camera(delta)
	elif auto_behind:
		_handle_auto_behind_camera(delta)
	else:
		_handle_free_camera(delta)


func _handle_free_camera(delta: float):
	var raw := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	# Response curve (precise near centre, fast at full tilt)
	var mag := raw.length()
	if mag > 0.0:
		raw = raw / mag * pow(minf(mag, 1.0), stick_curve)
	# Ease the stick so turning starts and stops without a hard edge
	var k := 1.0 if stick_smoothing <= 0.0 else 1.0 - exp(-delta / stick_smoothing)
	_stick_smoothed = _stick_smoothed.lerp(raw, k)
	if _stick_smoothed.length_squared() > 0.000001:
		twist_input -= _stick_smoothed.x * controller_sensitivity * delta
		var y := _stick_smoothed.y * controller_sensitivity * 0.75 * delta
		pitch_input += y if invert_y else -y
	_apply_rotation()


func _handle_auto_behind_camera(delta: float):
	if not character:
		_handle_free_camera(delta)
		return
	twist_input = lerp_angle(twist_input, character.rotation.y, 1.0 - exp(-AUTO_BEHIND_SPEED * delta))
	_apply_rotation()


func _handle_lock_on_camera(delta: float):
	if not is_instance_valid(locked_target):
		disable_lock_on()
		return
	var char_pos: Vector3 = character.global_position if character else global_position
	var to_target: Vector3 = locked_target.global_position - char_pos
	var distance := to_target.length()
	if distance > lock_on_range:
		disable_lock_on()
		return
	var target_yaw := atan2(-to_target.x, -to_target.z)
	var target_pitch := clampf(asin(clampf(to_target.y / maxf(distance, 0.001), -1.0, 1.0)) - 0.35, _rad_pitch_min, _rad_pitch_max)
	var k := 1.0 - exp(-lock_on_turn_speed * delta)
	twist_input = lerp_angle(twist_input, target_yaw, k)
	pitch_input = lerp_angle(pitch_input, target_pitch, k)
	_apply_rotation()


func _apply_rotation():
	pitch_input = clampf(pitch_input, _rad_pitch_min, _rad_pitch_max)
	rotation.y = twist_input
	if camera_target:
		camera_target.rotation.x = pitch_input


## Called from the player's physics tick with its new position. We store
## it as a target and interpolate per render frame between physics ticks.
func follow_character(character_position: Vector3, character_velocity: Vector3 = Vector3.ZERO):
	_prev_target = _follow_target
	_follow_target = character_position
	_follow_velocity = character_velocity
	_target_time = 0.0


func _update_follow(delta: float) -> void:
	if character == null:
		return
	# Interpolate the target between physics ticks (render-rate smoothness)
	_target_time += delta
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	var target := _prev_target.lerp(_follow_target, clampf(_target_time / tick, 0.0, 1.0))
	# Teleport / respawn: snap instead of flying across the map
	if global_position.distance_to(target) > snap_distance:
		global_position = target
		_current_distance = _safe_distance(camera_distance)
		return
	var h_speed := Vector2(_follow_velocity.x, _follow_velocity.z).length()
	var speed := follow_speed
	if h_speed > fast_speed_threshold:
		speed = lerpf(follow_speed, follow_speed_fast, clampf((h_speed - fast_speed_threshold) * 0.1, 0.0, 1.0))
	var a := 1.0 - exp(-speed * delta)
	var av := 1.0 - exp(-speed * vertical_follow_ratio * delta)
	var p := global_position
	p.x = lerpf(p.x, target.x, a)
	p.z = lerpf(p.z, target.z, a)
	p.y = lerpf(p.y, target.y, av)
	# Never let the camera lag so far vertically that Inke leaves the frame
	p.y = clampf(p.y, target.y - 2.5, target.y + 2.5)
	global_position = p


# ---------------------------------------------------------------------------
# Collision: sphere sweep + near-plane corner rays, every render frame
# ---------------------------------------------------------------------------
func _update_arm(delta: float):
	if camera_3d == null or camera_target == null:
		return
	var safe := _safe_distance(camera_distance)
	if safe < _current_distance - 0.01:
		# Obstructed. Big walls pull in instantly; tiny/brief blockers get a
		# short grace so a passing pole doesn't punch the camera in.
		_blocked_time += delta
		var drop := _current_distance - safe
		var here_clear := not _sphere_overlaps(camera_3d.global_position - shake_offset, collision_radius)
		if drop > 1.5 or _blocked_time >= thin_obstruction_grace or not here_clear:
			_current_distance = safe
	else:
		_blocked_time = 0.0
		# Clear: ease back out, but never further than is currently safe
		_current_distance = minf(lerpf(_current_distance, safe, 1.0 - exp(-reexpand_speed * delta)), safe)
	camera_3d.position = Vector3(0, 0, maxf(_current_distance, 0.0)) + shake_offset


func _safe_distance(wanted: float) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return wanted
	var pivot := camera_target.global_position
	var back := camera_target.global_transform.basis.z.normalized()
	var exclude := []
	if character is CollisionObject3D:
		exclude.append((character as CollisionObject3D).get_rid())
	# 1) Sphere sweep from the pivot along the arm
	var shape := SphereShape3D.new()
	shape.radius = collision_radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pivot)
	q.motion = back * wanted
	q.collision_mask = collision_mask
	q.exclude = exclude
	var res := space.cast_motion(q)
	var dist := wanted
	if res.size() == 2 and res[0] < 1.0:
		dist = wanted * res[0] - collision_margin
	# 2) Near-plane corners: the sphere can slip past a corner the camera's
	#    view rectangle would still cut through. Ray to each corner too.
	if camera_3d:
		var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(16, 9)
		var aspect := vp.x / maxf(vp.y, 1.0)
		# Generous rectangle: the near plane at 0.05m is tiny, so pad it to a
		# 'camera body' of ~collision_radius so edges never touch walls.
		var half_h := maxf(tan(deg_to_rad(camera_3d.fov) * 0.5) * camera_3d.near, collision_radius * 0.75)
		var half_w := half_h * aspect
		var right := camera_target.global_transform.basis.x.normalized()
		var up := camera_target.global_transform.basis.y.normalized()
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, 0)]:
			var off: Vector3 = right * c.x * half_w + up * c.y * half_h
			var from := pivot + off
			# start from the pivot, not the offset point, so a corner can't
			# hide the wall between pivot and the offset ray origin
			var rq0 := PhysicsRayQueryParameters3D.create(pivot, from)
			rq0.collision_mask = collision_mask
			rq0.exclude = exclude
			if not space.intersect_ray(rq0).is_empty():
				continue
			var rq := PhysicsRayQueryParameters3D.create(from, from + back * (dist + collision_margin))
			rq.collision_mask = collision_mask
			rq.exclude = exclude
			var hit := space.intersect_ray(rq)
			if not hit.is_empty():
				dist = minf(dist, (hit.position - from).length() - collision_margin)
	return maxf(dist, minf(min_distance, wanted))


func _sphere_overlaps(p: Vector3, r: float) -> bool:
	var space := get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = r
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), p)
	q.collision_mask = collision_mask
	if character is CollisionObject3D:
		q.exclude = [(character as CollisionObject3D).get_rid()]
	return not space.intersect_shape(q, 1).is_empty()


func _point_inside_geometry(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsPointQueryParameters3D.new()
	q.position = p
	q.collision_mask = collision_mask
	if character is CollisionObject3D:
		q.exclude = [(character as CollisionObject3D).get_rid()]
	return not space.intersect_point(q, 1).is_empty()


func _update_fov_kick(delta: float):
	if not camera_3d or not character:
		return
	var target_fov := base_fov
	if fov_kick_enabled and "velocity" in character:
		var v: Vector3 = character.velocity
		var h_speed := Vector2(v.x, v.z).length()
		var t := clampf((h_speed - fov_kick_start_speed) / maxf(fov_max_speed - fov_kick_start_speed, 0.01), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		target_fov = lerpf(base_fov, max_fov, t)
	target_fov += _zoom_fov_offset
	camera_3d.fov = lerpf(camera_3d.fov, target_fov, 1.0 - exp(-fov_lerp_speed * delta))


# ---------------------------------------------------------------------------
# Shake / zoom effects
# ---------------------------------------------------------------------------
func shake(intensity: float = 0.3, duration: float = 0.25):
	shake_strength = maxf(shake_strength, intensity)
	shake_time_left = maxf(shake_time_left, duration)


func _update_shake(delta: float):
	if shake_time_left > 0.0:
		shake_time_left -= delta
		var amount: float = shake_strength * clampf(shake_time_left / 0.25, 0.0, 1.0)
		shake_offset = Vector3(randf_range(-amount, amount), randf_range(-amount, amount), 0.0)
		if shake_time_left <= 0.0:
			shake_strength = 0.0
			shake_offset = Vector3.ZERO
	else:
		shake_offset = Vector3.ZERO


func start_zoom_effect(strength: float = 0.3, duration: float = 0.6):
	"""Brief FOV punch-in (cred pickups etc.)."""
	var tween := create_tween()
	tween.tween_property(self, "_zoom_fov_offset", -base_fov * clampf(strength, 0.0, 0.8), duration * 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_zoom_fov_offset", 0.0, duration * 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Lock-on
# ---------------------------------------------------------------------------
func toggle_lock_on():
	if lock_on_active:
		disable_lock_on()
	else:
		enable_lock_on()


func enable_lock_on():
	var nearest := _find_nearest_enemy()
	if nearest:
		lock_on_active = true
		locked_target = nearest


func disable_lock_on():
	lock_on_active = false
	locked_target = null


func _find_nearest_enemy() -> Node3D:
	var nearest: Node3D = null
	var nearest_sq := lock_on_range * lock_on_range
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		if d < nearest_sq:
			nearest_sq = d
			nearest = enemy
	return nearest


func _check_lock_on_switch():
	var camera_input := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if camera_input.length_squared() < 0.5:
		return
	var switch_direction := Vector3(camera_input.x, 0, camera_input.y).normalized()
	var new_target := _find_target_in_direction(switch_direction)
	if new_target and new_target != locked_target:
		locked_target = new_target
		lock_on_switch_timer = lock_on_switch_cooldown


func _find_target_in_direction(direction: Vector3) -> Node3D:
	var best_target: Node3D = null
	var best_score: float = -1.0
	var world_direction := global_transform.basis * direction
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy) or not enemy is Node3D or enemy == locked_target:
			continue
		var to_enemy: Vector3 = enemy.global_position - global_position
		var distance := to_enemy.length()
		if distance > lock_on_range:
			continue
		var score := to_enemy.normalized().dot(world_direction) / (distance * 0.1 + 1.0)
		if score > best_score:
			best_score = score
			best_target = enemy
	return best_target


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured and not lock_on_active:
		twist_input -= event.relative.x * mouse_sensitivity
		var y: float = event.relative.y * mouse_sensitivity
		pitch_input += y if invert_y else -y
	# Keyboard Esc frees the mouse. (Pad OPTIONS is the pause menu's.)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		mouse_captured = !mouse_captured
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if mouse_captured else Input.MOUSE_MODE_VISIBLE)
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func get_camera_forward() -> Vector3:
	return -camera_target.global_transform.basis.z


func get_camera_right() -> Vector3:
	return camera_target.global_transform.basis.x


func is_locked_on() -> bool:
	return lock_on_active


func get_locked_target() -> Node3D:
	return locked_target if lock_on_active else null
