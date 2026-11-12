extends Node
class_name DialogueCameraDirector
## Cinematic camera angles during dialogue.
##
## When a dialogue starts (and the source has dynamic_camera on), this
## blends FROM the current gameplay camera INTO a cinematic shot framing
## the speaker and the player, then cuts/glides to a fresh angle on every
## line - alternating over-the-shoulder shots with the occasional close-up
## and wide two-shot, like a film conversation. When the dialogue ends it
## glides back to exactly where the gameplay camera was.
##
## PICKING YOUR OWN ANGLES
##   Don't like the auto shots? Give the DialogueTrigger / QuestGiver /
##   Merchant some POSED NODES in custom_camera_angles (empty Node3Ds or
##   CutsceneCameras - pose them with F10 free roam + P!). The director
##   then cycles through YOUR poses, one per line, instead of computing
##   its own. FOV comes from the node if it's a Camera3D.
##
## Runs while the tree is paused (dialogue pauses the game), so all
## motion is manual lerp in _process with PROCESS_MODE_ALWAYS.

const SHOT_BLEND_TIME := 0.7        # ease into the first shot / back out
const ANGLE_GLIDE_TIME := 0.45      # glide between angles mid-conversation
const DRIFT_SPEED := 0.12           # slow push-in per shot (cinematic drift)

var active: bool = false
var _cam: Camera3D = null           # our own camera
var _prev_cam: Camera3D = null      # gameplay camera to restore
var _focus: Node3D = null           # the speaker (NPC / trigger)
var _player: Node3D = null
var _custom_angles: Array = []      # user-posed Node3Ds (optional)
var _shot_index: int = 0

## Safety rules for every auto shot:
##   PERSON_CLEARANCE - camera stays at least this far from any character's
##     capsule (speaker, Inke, HU3, bystanders, enemies) so it never clips
##     into a face or a hat.
##   Line of sight to BOTH heads must be clear (no wall between).
##   Side walls: the camera can't cross the left/right limit planes set on
##     the speaker (wall_left/wall_right + wall_distance) or any
##     DialogueCameraBounds node in the scene.
const PERSON_CLEARANCE := 0.9
const WORLD_CLEARANCE := 0.35
var _left_limit: float = INF     # metres to the left of the conversation line
var _right_limit: float = INF    # metres to the right
var _bounds_nodes: Array = []

# Motion state (manual tween - works while paused)
var _from_pose: Transform3D
var _to_pose: Transform3D
var _from_fov: float = 75.0
var _to_fov: float = 75.0
var _blend_t: float = 1.0
var _blend_dur: float = 0.5
var _drift_dir: Vector3 = Vector3.ZERO


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


# ---------------------------------------------------------------------------
# Lifecycle (called by DialogueManager)
# ---------------------------------------------------------------------------
func begin(focus: Node3D, custom_angles: Array = []) -> void:
	"""Start directing. focus = the speaker node (NPC, trigger...)."""
	if active:
		finish(true)
	_focus = focus
	_custom_angles = []
	for a in custom_angles:
		if a is Node3D and is_instance_valid(a):
			_custom_angles.append(a)
	var players = get_tree().get_nodes_in_group("Player")
	_player = players[0] if players.size() > 0 else null
	if _focus == null or _player == null:
		return
	_prev_cam = get_viewport().get_camera_3d()
	if _prev_cam == null:
		return
	# Side walls the camera may not pass (per speaker, Inspector-controlled)
	_left_limit = INF
	_right_limit = INF
	if "camera_wall_left" in _focus and bool(_focus.get("camera_walls_enabled")):
		_left_limit = float(_focus.get("camera_wall_left"))
		_right_limit = float(_focus.get("camera_wall_right"))
	_bounds_nodes = get_tree().get_nodes_in_group("DialogueCameraBounds")
	
	_cam = Camera3D.new()
	_cam.name = "DialogueCamera"
	get_tree().current_scene.add_child(_cam)
	_cam.global_transform = _prev_cam.global_transform
	_cam.fov = _prev_cam.fov
	_cam.make_current()
	
	active = true
	_shot_index = 0
	next_shot(true)   # blend from gameplay view into the first shot
	set_process(true)


func next_shot(first: bool = false) -> void:
	"""Move to the next cinematic angle (called on every dialogue line)."""
	if not active or _cam == null:
		return
	var pose: Transform3D
	var fov := 62.0
	if _custom_angles.size() > 0:
		var node: Node3D = _custom_angles[_shot_index % _custom_angles.size()]
		pose = node.global_transform
		if node is Camera3D:
			fov = node.fov
	else:
		var shot := _compute_shot(_shot_index)
		pose = shot.pose
		fov = shot.fov
	_shot_index += 1
	
	_from_pose = _cam.global_transform
	_from_fov = _cam.fov
	_to_pose = pose
	_to_fov = fov
	_blend_dur = SHOT_BLEND_TIME if first else ANGLE_GLIDE_TIME
	_blend_t = 0.0
	# Slow push toward the midpoint for living-camera drift
	var mid := (_speaker_head() + _player_head()) * 0.5
	_drift_dir = (mid - pose.origin).normalized()


func finish(instant: bool = false) -> void:
	"""Dialogue over: glide back to the gameplay camera."""
	if not active:
		return
	active = false
	if _prev_cam and is_instance_valid(_prev_cam):
		if instant or _cam == null or not is_instance_valid(_cam):
			_prev_cam.make_current()
			_cleanup()
		else:
			# Glide home, then hand back
			_from_pose = _cam.global_transform
			_from_fov = _cam.fov
			_to_pose = _prev_cam.global_transform
			_to_fov = _prev_cam.fov
			_blend_dur = SHOT_BLEND_TIME
			_blend_t = 0.0
			_drift_dir = Vector3.ZERO
			set_process(true)
			return
	else:
		_cleanup()


func _cleanup() -> void:
	set_process(false)
	if _cam and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	_prev_cam = null
	_focus = null


func _process(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cleanup()
		return
	if _blend_t < 1.0:
		_blend_t = minf(_blend_t + delta / maxf(_blend_dur, 0.01), 1.0)
		var t := _blend_t * _blend_t * (3.0 - 2.0 * _blend_t)   # smoothstep
		_cam.global_transform = _from_pose.interpolate_with(_to_pose, t)
		_cam.fov = lerpf(_from_fov, _to_fov, t)
		if _blend_t >= 1.0 and not active:
			# Finished the glide home
			if _prev_cam and is_instance_valid(_prev_cam):
				_prev_cam.make_current()
			_cleanup()
	elif active and _drift_dir != Vector3.ZERO:
		# Gentle push-in while a shot holds - but never into a person/wall
		var next := _cam.global_position + _drift_dir * DRIFT_SPEED * delta
		if _too_close_to_people(next) or _inside_world(next):
			_drift_dir = Vector3.ZERO
		else:
			_cam.global_position = next
			_to_pose.origin = next


# ---------------------------------------------------------------------------
# Auto shot computation
# ---------------------------------------------------------------------------
func _speaker_head() -> Vector3:
	return _focus.global_position + Vector3(0, 1.6, 0) if _focus and is_instance_valid(_focus) else Vector3.ZERO


func _player_head() -> Vector3:
	return _player.global_position + Vector3(0, 1.4, 0) if _player and is_instance_valid(_player) else Vector3.ZERO


func _compute_shot(index: int) -> Dictionary:
	"""Film-style rotation (OTS speaker, reverse OTS, close-up, wide two-shot)
	with SAFETY: every candidate is checked against characters, walls and the
	side limits, and nudged/replaced until it's clean. Falls back to a safe
	wide shot if nothing passes."""
	var s := _speaker_head()
	var p := _player_head()
	var to_speaker := (s - p)
	to_speaker.y = 0.0
	var dist := maxf(to_speaker.length(), 0.5)
	var fwd := to_speaker / dist
	var side := fwd.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var flip: float = 1.0 if (index / 4) % 2 == 0 else -1.0
	var kind := index % 4
	# Try the preferred shot, then its mirror, then the other kinds.
	var order := [kind, kind, (kind + 1) % 4, (kind + 2) % 4, (kind + 3) % 4, 3]
	for attempt in range(order.size()):
		var k: int = order[attempt]
		var f: float = flip if attempt != 1 else -flip
		var shot := _shot_pose(k, f, s, p, fwd, side, dist)
		var fixed = _make_safe(shot.pos, shot.look, s, p, side)
		if fixed != null:
			var pos: Vector3 = fixed
			return {"pose": Transform3D(Basis.looking_at((shot.look - pos).normalized(), Vector3.UP), pos), "fov": shot.fov}
	# Last resort: pull straight up and back along the gameplay side
	var mid := (s + p) * 0.5
	var back := _clamp_to_limits(mid - fwd * (dist + 3.0) + Vector3(0, 2.0, 0), s, p, side)
	return {"pose": Transform3D(Basis.looking_at((mid - back).normalized(), Vector3.UP), back), "fov": 60.0}


func _shot_pose(kind: int, flip: float, s: Vector3, p: Vector3, fwd: Vector3, side: Vector3, dist: float) -> Dictionary:
	var pos: Vector3
	var look: Vector3
	var fov := 55.0
	match kind:
		0:   # Over the player's shoulder, framing the speaker
			pos = p - fwd * 1.4 + side * flip * 0.95 + Vector3(0, 0.45, 0)
			look = s
			fov = 50.0
		1:   # Reverse: over the speaker's shoulder, framing the player
			pos = s + fwd * 1.4 - side * flip * 0.95 + Vector3(0, 0.45, 0)
			look = p
			fov = 50.0
		2:   # Speaker close-up, slightly low and to the side
			pos = s - fwd * 2.0 + side * flip * 1.3 + Vector3(0, 0.15, 0)
			look = s
			fov = 42.0
		_:   # Wide two-shot from the side
			var mid := (s + p) * 0.5
			pos = mid + side * flip * (dist * 0.9 + 2.5) + Vector3(0, 0.6, 0)
			look = mid
			fov = 60.0
	return {"pos": pos, "look": look, "fov": fov}


func _make_safe(pos: Vector3, look: Vector3, s: Vector3, p: Vector3, side: Vector3):
	"""Return a corrected camera position, or null if this shot can't be made
	safe. Steps: clamp to side walls -> push out of characters -> pull in
	front of walls -> require clear sight of both heads."""
	pos = _clamp_to_limits(pos, s, p, side)
	for _i in range(4):
		pos = _push_out_of_people(pos, look)
	pos = _pull_in_front_of_walls(look, pos)
	if _too_close_to_people(pos) or _inside_world(pos):
		return null
	if not _clear_line(pos, s) or not _clear_line(pos, p):
		return null
	if not _within_limits(pos, s, p, side):
		return null
	return pos


func _people() -> Array:
	var out := []
	for g in ["Player", "NPC", "Enemy", "HU3", "Characters"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and not out.has(n):
				out.append(n)
	if _focus and not out.has(_focus):
		out.append(_focus)
	# Any CharacterBody3D near the conversation also counts (HU3, bystanders)
	var mid := (_speaker_head() + _player_head()) * 0.5
	for n in get_tree().current_scene.find_children("*", "CharacterBody3D", true, false):
		if n is Node3D and not out.has(n) and (n as Node3D).global_position.distance_to(mid) < 15.0:
			out.append(n)
	return out


func _capsule_dist(pos: Vector3, person: Node3D) -> float:
	"""Distance from pos to a person's body (vertical capsule, feet->2m)."""
	var base := person.global_position
	var y := clampf(pos.y, base.y + 0.3, base.y + 1.9)
	return pos.distance_to(Vector3(base.x, y, base.z)) - 0.45


func _too_close_to_people(pos: Vector3) -> bool:
	for person in _people():
		if _capsule_dist(pos, person) < PERSON_CLEARANCE:
			return true
	return false


func _push_out_of_people(pos: Vector3, look: Vector3) -> Vector3:
	for person in _people():
		var d := _capsule_dist(pos, person)
		if d < PERSON_CLEARANCE:
			var c: Vector3 = person.global_position
			var away := Vector3(pos.x - c.x, 0, pos.z - c.z)
			if away.length() < 0.01:
				away = (pos - look).normalized()
				away.y = 0
			pos += away.normalized() * (PERSON_CLEARANCE - d + 0.05)
	return pos


func _space() -> PhysicsDirectSpaceState3D:
	return get_tree().current_scene.get_world_3d().direct_space_state


func _char_rids() -> Array:
	var r := []
	for person in _people():
		if person is CollisionObject3D:
			r.append((person as CollisionObject3D).get_rid())
	return r


func _pull_in_front_of_walls(target: Vector3, pos: Vector3) -> Vector3:
	"""If world geometry sits between the subject and the camera, slide the
	camera toward the subject until it's in front of it."""
	var sh := SphereShape3D.new()
	sh.radius = WORLD_CLEARANCE
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), target)
	q.motion = pos - target
	q.exclude = _char_rids()
	var res := _space().cast_motion(q)
	if res.size() == 2 and res[0] < 1.0:
		return target + (pos - target) * maxf(res[0] - 0.05, 0.0)
	return pos


func _inside_world(pos: Vector3) -> bool:
	var sh := SphereShape3D.new()
	sh.radius = WORLD_CLEARANCE * 0.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis(), pos)
	q.exclude = _char_rids()
	return not _space().intersect_shape(q, 1).is_empty()


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = _char_rids()
	return _space().intersect_ray(q).is_empty()


func _lateral(pos: Vector3, s: Vector3, p: Vector3, side: Vector3) -> float:
	"""Signed distance of pos from the conversation line (+ = right side)."""
	var mid := (s + p) * 0.5
	return (pos - mid).dot(side)


func _within_limits(pos: Vector3, s: Vector3, p: Vector3, side: Vector3) -> bool:
	var l := _lateral(pos, s, p, side)
	if l > _right_limit + 0.01 or -l > _left_limit + 0.01:
		return false
	for b in _bounds_nodes:
		if b.has_method("contains") and not b.contains(pos):
			return false
	return true


func _clamp_to_limits(pos: Vector3, s: Vector3, p: Vector3, side: Vector3) -> Vector3:
	var l := _lateral(pos, s, p, side)
	if l > _right_limit:
		pos -= side * (l - _right_limit)
	elif -l > _left_limit:
		pos += side * (-l - _left_limit)
	for b in _bounds_nodes:
		if b.has_method("clamp_point"):
			pos = b.clamp_point(pos)
	return pos


## Test hook (used by the headless camera tests only).
func _compute_shot_for_test(index: int, focus: Node3D, player: Node3D, walls: bool) -> Dictionary:
	_focus = focus
	_player = player
	_left_limit = 1.5 if walls else INF
	_right_limit = 1.5 if walls else INF
	_bounds_nodes = get_tree().get_nodes_in_group("DialogueCameraBounds")
	return _compute_shot(index)
