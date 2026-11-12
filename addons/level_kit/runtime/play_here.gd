extends Node
## LEVEL KIT - "Play From Here" runtime half.
## The editor writes user://level_kit_play_here.json (scene path + spawn
## transform) right before launching the scene. On load, this autoload
## moves Inke to that spot and deletes the file, so the very next normal
## play starts where the level designer intended. No file = no-op, so it
## is completely inert in real playthroughs and exported builds.

const PATH := "user://level_kit_play_here.json"


var _pending: Dictionary = {}


func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f else null
	if f:
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if not (data is Dictionary):
		return
	# Expires after 2 minutes so a stale file can never hijack a later session
	if Time.get_unix_time_from_system() - float(data.get("time", 0)) > 120.0:
		return
	_pending = data
	set_process(true)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	# Only apply to the scene it was meant for
	if scene.scene_file_path != str(_pending.get("scene", "")):
		_pending = {}
		return
	var players := get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return
	var p := players[0] as Node3D
	if not p.is_node_ready():
		return
	var data := _pending
	_pending = {}
	set_process(false)
	var pos := Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0))
	p.global_position = pos
	p.rotation.y = float(data.get("yaw", 0.0))
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	# Respawns (falls/resets) come back here too while testing
	var cm = get_node_or_null("/root/CheckpointManager")
	if cm and cm.has_method("set_checkpoint"):
		cm.set_checkpoint(pos, Vector3(0, p.rotation.y, 0))
	# Grant every movement upgrade so any section can be tested immediately
	if bool(data.get("all_upgrades", false)) and "debug_grant_all" in p:
		p.set("debug_grant_all", true)
	print("LevelKit: Play From Here -> ", pos)
