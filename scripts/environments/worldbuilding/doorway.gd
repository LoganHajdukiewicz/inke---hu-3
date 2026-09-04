@tool
extends Marker3D
class_name Doorway
## Child of a Room: carves an opening out of whatever wall it overlaps.
## Drag it into a wall in the editor and watch the hole appear - no
## snapping, no rules. sill_height 0 = door; raise it for a window.
## The cut auto-rotates toward the nearest wall; rotate the node
## yourself to override.

## Opening width along the wall.
@export var width: float = 1.6:
	set(v):
		width = v
		_poke_room()
		if _door and is_instance_valid(_door):
			_door.door_size = Vector3(width, height, 0.15)
## Opening height (from the sill up).
@export var height: float = 2.6:
	set(v):
		height = v
		_poke_room()
		if _door and is_instance_valid(_door):
			_door.door_size = Vector3(width, height, 0.15)
## Bottom of the opening above the floor. 0 = door, e.g. 1.2 = window.
@export var sill_height: float = 0.0:
	set(v):
		sill_height = v
		_poke_room()
		_refresh_door()
## How deep the cut goes (leave default unless walls are very thick).
@export var cut_depth: float = 1.5:
	set(v): cut_depth = v; _poke_room()

@export_group("Door")
## Put an interactable Door in this opening (press E to open/close).
## Untick for an open archway. Windows (sill_height > 0) never get doors.
@export var has_door: bool = true:
	set(v): has_door = v; _refresh_door()
## Door starts locked (needs a Key with door_key_id). Default unlocked.
@export var door_locked: bool = false:
	set(v):
		door_locked = v
		if _door and is_instance_valid(_door):
			_door.locked = v
## Key id used when door_locked is on.
@export var door_key_id: String = "key":
	set(v):
		door_key_id = v
		if _door and is_instance_valid(_door):
			_door.key_id = v

var _door: Door = null


func _ready():
	set_notify_transform(true)
	_poke_room()
	_refresh_door()


func _refresh_door() -> void:
	if not is_inside_tree():
		return
	var wants: bool = has_door and sill_height <= 0.01
	if not wants:
		if _door and is_instance_valid(_door):
			_door.queue_free()
		_door = null
		return
	if _door and is_instance_valid(_door):
		return
	_door = Door.new()
	_door.door_size = Vector3(width, height, 0.15)
	_door.locked = door_locked
	_door.key_id = door_key_id
	add_child(_door)
	_align_door_to_wall()


func _align_door_to_wall() -> void:
	"""Doors must lie ALONG the wall, not across it. The panel spans local
	X, so on a +/-X wall (which runs along Z) it needs a 90-degree yaw.
	This must run when the door is CREATED, not just when the doorway is
	dragged - un-yawed fresh doors were sitting perpendicular to walls."""
	if _door == null or not is_instance_valid(_door):
		return
	# The marker's own rotation wins (user aimed it, e.g. diagonal walls)
	if absf(rotation.y) > 0.01:
		_door.rotation.y = 0.0
		return
	if get_parent() is Room:
		var r: Room = get_parent()
		var dist_x = absf(absf(position.x) - r.interior_size.x * 0.5)
		var dist_z = absf(absf(position.z) - r.interior_size.z * 0.5)
		_door.rotation.y = (PI * 0.5) if dist_x < dist_z else 0.0


func _exit_tree():
	_poke_room()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_poke_room()
		_align_door_to_wall()


func _poke_room() -> void:
	var p = get_parent()
	if p is Room:
		p._request_rebuild()
