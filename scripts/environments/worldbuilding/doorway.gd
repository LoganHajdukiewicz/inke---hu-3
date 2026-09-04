@tool
extends Marker3D
class_name Doorway
## Child of a Room node: cuts an opening in the nearest wall.
## Drag it around - it snaps to the closest wall and the Room rebuilds.
## sill_height = 0 makes a door; raise it to make a window.

## Opening width along the wall.
@export var width: float = 1.6:
	set(v): width = v; _poke_room()
## Opening height (from the sill up).
@export var height: float = 2.6:
	set(v): height = v; _poke_room()
## Bottom of the opening above the floor. 0 = door, e.g. 1.2 = window.
@export var sill_height: float = 0.0:
	set(v): sill_height = v; _poke_room()


func _ready():
	set_notify_transform(true)
	_poke_room()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_poke_room()


func _poke_room() -> void:
	var p = get_parent()
	if p is Room:
		p._request_rebuild()
