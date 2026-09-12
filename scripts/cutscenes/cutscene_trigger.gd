@tool
extends Area3D
class_name CutsceneTrigger

## IN-WORLD CUTSCENE TRIGGER - walk into the box, a cutscene plays.
## Full walkthrough: scripts/cutscenes/CUTSCENE_WALKTHROUGH.md
##
## Configure everything in the Inspector - no code needed for the common
## cases. The trigger runs these STEPS in order when the player enters:
##   1. Freeze the player (take_control)
##   2. Play the camera: a recorded .camrec take, OR activate a
##      CutsceneCamera node (with its optional marker path), OR neither
##      (keep gameplay cam)
##   3. Optionally walk actors to markers (actor_moves pairs)
##   4. Optionally fly HU3 to a marker
##   5. Optionally play a dialogue file mid-scene
##   6. Unfreeze (release_control)
##
## For anything fancier, leave these empty and write your own script
## calling the CutsceneManager API - this node is the 80% case.

## Fire only the first time (almost always what you want).
@export var trigger_once: bool = true
## Size of the trigger volume.
@export var box_size: Vector3 = Vector3(4, 3, 4):
	set(v):
		box_size = v
		_update_shape()

@export_group("Camera")
## Path to a recorded camera take (fly with F10, press R to record).
@export_file("*.camrec") var camera_recording: String = ""
## OR: a CutsceneCamera in this scene to activate() for the duration.
@export var cutscene_camera: CutsceneCamera = null
## Seconds to hold on the CutsceneCamera (ignored for recordings - they
## have their own length).
@export var camera_hold: float = 3.0

@export_group("Actors")
## Pairs: [actor NodePath, destination marker NodePath, actor, marker...]
## Each pair = walk that actor to that marker (in order, one at a time).
@export var actor_moves: Array[NodePath] = []
## Walk speed for actor_moves.
@export var actor_speed: float = 3.0
## Fly HU3 to this marker during the scene (empty = leave HU3 alone).
@export var hu3_destination: NodePath = ""

@export_group("Dialogue")
## Dialogue file to play mid-cutscene (same files DialogueTrigger uses,
## from res://dialogue/{scene}/). Empty = no dialogue.
@export var dialogue_file: String = ""

var _fired := false
var _col: CollisionShape3D = null


func _ready() -> void:
	_update_shape()
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _update_shape() -> void:
	if _col == null or not is_instance_valid(_col):
		_col = get_node_or_null("CollisionShape3D")
		if _col == null:
			_col = CollisionShape3D.new()
			_col.name = "CollisionShape3D"
			add_child(_col)
	var box := BoxShape3D.new()
	box.size = box_size
	_col.shape = box


func _on_body_entered(body: Node3D) -> void:
	if _fired and trigger_once:
		return
	if not body.is_in_group("Player"):
		return
	var cm = get_node_or_null("/root/CutsceneManager")
	if cm == null or cm.is_cutscene_active:
		return
	_fired = true
	_run_cutscene(cm)


func _run_cutscene(cm) -> void:
	cm.take_control()
	
	# --- Camera --------------------------------------------------------------
	var used_cutscene_cam := false
	if camera_recording != "" and FileAccess.file_exists(camera_recording):
		# Recorded take: actors move DURING it (fire and forget the moves)
		_run_moves(cm)
		await cm.play_camera_recording(camera_recording)
	else:
		if cutscene_camera and is_instance_valid(cutscene_camera):
			cutscene_camera.fly_enabled = false
			cutscene_camera.activate()
			used_cutscene_cam = true
		await _run_moves_awaited(cm)
		if used_cutscene_cam:
			await cm.wait(camera_hold)
	
	# --- Dialogue -------------------------------------------------------------
	if dialogue_file != "":
		var dm = get_node_or_null("/root/DialogueManager")
		if dm:
			dm.start_dialogue(dialogue_file)
			await dm.dialogue_ended
	
	if used_cutscene_cam and cutscene_camera and is_instance_valid(cutscene_camera):
		cutscene_camera.deactivate()
	
	cm.release_control()


func _run_moves(cm) -> void:
	"""Fire-and-forget actor moves (parallel with a camera recording)."""
	for i in range(0, actor_moves.size() - 1, 2):
		var actor := get_node_or_null(actor_moves[i]) as Node3D
		var marker := get_node_or_null(actor_moves[i + 1]) as Node3D
		if actor and marker:
			cm.move_actor(actor, marker.global_position, actor_speed)
	if hu3_destination != NodePath(""):
		var m := get_node_or_null(hu3_destination) as Node3D
		if m:
			cm.hu3_goto(m.global_position)


func _run_moves_awaited(cm) -> void:
	"""Sequential actor moves (used with a static CutsceneCamera)."""
	for i in range(0, actor_moves.size() - 1, 2):
		var actor := get_node_or_null(actor_moves[i]) as Node3D
		var marker := get_node_or_null(actor_moves[i + 1]) as Node3D
		if actor and marker:
			await cm.move_actor(actor, marker.global_position, actor_speed)
	if hu3_destination != NodePath(""):
		var m := get_node_or_null(hu3_destination) as Node3D
		if m:
			await cm.hu3_goto(m.global_position)
