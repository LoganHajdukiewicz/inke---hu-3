extends Node

## CutsceneManager (autoload) - the cutscene toolkit.
## Full authoring walkthrough: scripts/cutscenes/CUTSCENE_WALKTHROUGH.md
##
## SIGNALS: other systems (e.g. PaintUIManager) listen to
## cutscene_started/cutscene_ended to hide/show gameplay UI.
##
## DIRECTING API (all awaitable where it matters):
##   take_control() / release_control()  - freeze/unfreeze the player
##   await move_actor(node, to, speed)   - walk any character somewhere
##   face_actor(node, target)            - turn a character toward a point
##   await hu3_goto(pos, speed)          - fly HU3 somewhere (he stops
##                                         following); hu3_release() after
##   await play_camera_recording(path)   - replay a recorded camera take
##   await wait(seconds)                 - beat/pause helper
##
## CAMERA RECORDING: fly with F10/F6, press R to start/stop recording the
## flight. Saved to res://cinematic_shots/*.camrec - play back with
## play_camera_recording(). See the walkthrough for the whole flow.

signal cutscene_started
signal cutscene_ended

var is_cutscene_active: bool = false

const RECORDING_FPS := 20.0


func start_cutscene() -> void:
	if is_cutscene_active:
		return
	is_cutscene_active = true
	cutscene_started.emit()


func end_cutscene() -> void:
	if not is_cutscene_active:
		return
	is_cutscene_active = false
	cutscene_ended.emit()


# =========================================================================
# PLAYER / ACTOR CONTROL
# =========================================================================

func _player() -> CharacterBody3D:
	var gm = get_node_or_null("/root/GameManager")
	return gm.player if gm and gm.player and is_instance_valid(gm.player) else null


func take_control() -> void:
	"""Begin a scripted sequence: cutscene mode ON (gameplay UI hides),
	player input OFF, player stopped. Pair with release_control()."""
	start_cutscene()
	var p := _player()
	if p:
		p.velocity = Vector3.ZERO
		if "controls_disabled" in p:
			p.controls_disabled = true


func release_control() -> void:
	"""End the sequence: player input back, cutscene mode OFF."""
	var p := _player()
	if p and "controls_disabled" in p:
		p.controls_disabled = false
	hu3_release()
	end_cutscene()


func move_actor(actor: Node3D, target: Vector3, speed: float = 3.0,
		face_travel: bool = true) -> void:
	"""Walk/glide an actor (player, NPC, prop - any Node3D) to a world
	position at speed m/s, facing its direction of travel. AWAIT IT:
	    await CutsceneManager.move_actor($NPC, marker.global_position, 2.5)
	CharacterBody3Ds get their physics paused for the ride so states/
	gravity don't fight the motion."""
	if actor == null or not is_instance_valid(actor):
		return
	var from := actor.global_position
	var dist := from.distance_to(target)
	if dist < 0.01:
		return
	var dur := dist / maxf(speed, 0.1)
	
	var was_mode := actor.process_mode
	if actor is CharacterBody3D:
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	
	if face_travel:
		var flat := Vector3(target.x - from.x, 0, target.z - from.z)
		if flat.length() > 0.05:
			var yaw := atan2(-flat.x, -flat.z)
			var tw_rot := create_tween()
			tw_rot.tween_property(actor, "rotation:y", yaw, minf(0.3, dur))
	
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(actor, "global_position", target, dur)
	await tw.finished
	
	if actor is CharacterBody3D and is_instance_valid(actor):
		actor.process_mode = was_mode


func face_actor(actor: Node3D, target: Vector3, duration: float = 0.35) -> void:
	"""Turn an actor to face a world point (Y-axis only)."""
	if actor == null or not is_instance_valid(actor):
		return
	var flat := Vector3(target.x - actor.global_position.x, 0, target.z - actor.global_position.z)
	if flat.length() < 0.05:
		return
	var yaw := atan2(-flat.x, -flat.z)
	var tw := create_tween()
	tw.tween_property(actor, "rotation:y", yaw, duration)


func teleport_actor(actor: Node3D, target: Vector3, yaw_degrees: float = NAN) -> void:
	"""Instantly place an actor (for setting the stage before a shot)."""
	if actor == null or not is_instance_valid(actor):
		return
	actor.global_position = target
	if not is_nan(yaw_degrees):
		actor.rotation_degrees.y = yaw_degrees


# =========================================================================
# HU3 CONTROL
# =========================================================================

func _hu3() -> CharacterBody3D:
	var gm = get_node_or_null("/root/GameManager")
	return gm.hu3_companion if gm and gm.hu3_companion and is_instance_valid(gm.hu3_companion) else null


func hu3_goto(target: Vector3, speed: float = 6.0) -> void:
	"""Fly HU3 to a world position. He stops following the player until
	hu3_release() (release_control() calls it for you).
	    await CutsceneManager.hu3_goto($DoorMarker.global_position)"""
	var h := _hu3()
	if h == null:
		return
	if "cutscene_override" in h:
		h.cutscene_override = true
	var dist: float = h.global_position.distance_to(target)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(h, "global_position", target, dist / maxf(speed, 0.1))
	await tw.finished


func hu3_face(target: Vector3, duration: float = 0.3) -> void:
	"""Turn HU3 toward a world point."""
	var h := _hu3()
	if h:
		face_actor(h, target, duration)


func hu3_release() -> void:
	"""HU3 goes back to following the player."""
	var h := _hu3()
	if h and "cutscene_override" in h:
		h.cutscene_override = false


# =========================================================================
# CAMERA RECORDING PLAYBACK
# =========================================================================

func play_camera_recording(path: String, blend_in: float = 0.8,
		blend_out: float = 0.8) -> void:
	"""Replay a .camrec camera take (recorded with R during F10 fly mode).
	Glides from the gameplay camera into the take, plays it, glides back.
	AWAIT IT - it returns when the take is over:
	    await CutsceneManager.play_camera_recording(
	        "res://cinematic_shots/rec_island_1.camrec")"""
	var frames := _load_recording(path)
	if frames.is_empty():
		push_warning("CutsceneManager: no camera recording at " + path)
		return
	var scene = get_tree().current_scene
	if scene == null:
		return
	
	start_cutscene()
	var prev_cam := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "RecordingPlaybackCam"
	scene.add_child(cam)
	
	var first: Dictionary = frames[0]
	cam.global_transform = first.pose
	cam.fov = first.fov
	
	# Blend in from the gameplay camera
	if prev_cam and blend_in > 0.05:
		var from_pose: Transform3D = prev_cam.global_transform
		var from_fov: float = prev_cam.fov
		cam.global_transform = from_pose
		cam.fov = from_fov
		cam.make_current()
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw.tween_method(func(t: float):
			cam.global_transform = from_pose.interpolate_with(first.pose, t)
			cam.fov = lerpf(from_fov, first.fov, t)
		, 0.0, 1.0, blend_in)
		await tw.finished
	else:
		cam.make_current()
	
	# Step through the take
	var frame_time := 1.0 / RECORDING_FPS
	var t := 0.0
	var total := (frames.size() - 1) * frame_time
	while t < total:
		if not is_instance_valid(cam):
			break
		var idx := int(t / frame_time)
		var frac := (t - idx * frame_time) / frame_time
		var a: Dictionary = frames[mini(idx, frames.size() - 1)]
		var b: Dictionary = frames[mini(idx + 1, frames.size() - 1)]
		cam.global_transform = (a.pose as Transform3D).interpolate_with(b.pose, frac)
		cam.fov = lerpf(a.fov, b.fov, frac)
		await get_tree().process_frame
		t += get_process_delta_time()
	
	# Blend back out
	if prev_cam and is_instance_valid(prev_cam) and blend_out > 0.05 and is_instance_valid(cam):
		var pose: Transform3D = cam.global_transform
		var f: float = cam.fov
		var tw2 := create_tween()
		tw2.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tw2.tween_method(func(t2: float):
			if is_instance_valid(prev_cam) and is_instance_valid(cam):
				cam.global_transform = pose.interpolate_with(prev_cam.global_transform, t2)
				cam.fov = lerpf(f, prev_cam.fov, t2)
		, 0.0, 1.0, blend_out)
		await tw2.finished
	if prev_cam and is_instance_valid(prev_cam):
		prev_cam.make_current()
	if is_instance_valid(cam):
		cam.queue_free()
	end_cutscene()


func _load_recording(path: String) -> Array:
	"""Parse a .camrec file -> [{pose: Transform3D, fov: float}, ...]"""
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or not parsed.has("frames"):
		return out
	for fr in parsed.frames:
		if fr.size() < 7:
			continue
		var basis := Basis.from_euler(Vector3(fr[3], fr[4], fr[5]))
		out.append({
			"pose": Transform3D(basis, Vector3(fr[0], fr[1], fr[2])),
			"fov": float(fr[6]),
		})
	return out


# =========================================================================
# MISC HELPERS
# =========================================================================

func wait(seconds: float) -> void:
	"""Beat helper: await CutsceneManager.wait(1.5)"""
	await get_tree().create_timer(seconds).timeout
