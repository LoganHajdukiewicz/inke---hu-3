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
		# Gentle push-in while a shot holds
		_cam.global_position += _drift_dir * DRIFT_SPEED * delta
		_to_pose.origin = _cam.global_position


# ---------------------------------------------------------------------------
# Auto shot computation
# ---------------------------------------------------------------------------
func _speaker_head() -> Vector3:
	return _focus.global_position + Vector3(0, 1.6, 0) if _focus and is_instance_valid(_focus) else Vector3.ZERO


func _player_head() -> Vector3:
	return _player.global_position + Vector3(0, 1.4, 0) if _player and is_instance_valid(_player) else Vector3.ZERO


func _compute_shot(index: int) -> Dictionary:
	"""Film-style rotation: over-the-shoulder on the speaker, reverse OTS on
	the player, close-up, wide two-shot - repeating with side variation."""
	var s := _speaker_head()
	var p := _player_head()
	var to_speaker := (s - p)
	var dist := maxf(to_speaker.length(), 0.5)
	var fwd := to_speaker / dist
	var side := fwd.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	# Alternate which side of the "line" we favor every 4 shots
	var flip: float = 1.0 if (index / 4) % 2 == 0 else -1.0
	var kind := index % 4
	var pos: Vector3
	var look: Vector3
	var fov := 55.0
	match kind:
		0:   # Over the player's shoulder, framing the speaker
			pos = p - fwd * 0.9 + side * flip * 0.7 + Vector3(0, 0.35, 0)
			look = s
			fov = 50.0
		1:   # Reverse: over the speaker's shoulder, framing the player
			pos = s + fwd * 0.9 - side * flip * 0.7 + Vector3(0, 0.35, 0)
			look = p
			fov = 50.0
		2:   # Speaker close-up, slightly low and to the side
			pos = s - fwd * 1.6 + side * flip * 1.1 + Vector3(0, 0.15, 0)
			look = s
			fov = 42.0
		_:   # Wide two-shot from the side
			var mid := (s + p) * 0.5
			pos = mid + side * flip * (dist * 0.9 + 2.5) + Vector3(0, 0.6, 0)
			look = mid
			fov = 60.0
	var pose := Transform3D(Basis.looking_at((look - pos).normalized(), Vector3.UP), pos)
	return {"pose": pose, "fov": fov}
