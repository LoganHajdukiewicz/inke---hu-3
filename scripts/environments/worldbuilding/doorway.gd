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
	set(v): width = v; _poke_room()
## Opening height (from the sill up).
@export var height: float = 2.6:
	set(v): height = v; _poke_room()
## Bottom of the opening above the floor. 0 = door, e.g. 1.2 = window.
@export var sill_height: float = 0.0:
	set(v): sill_height = v; _poke_room()
## How deep the cut goes (leave default unless walls are very thick).
@export var cut_depth: float = 1.5:
	set(v): cut_depth = v; _poke_room()


func _ready():
	set_notify_transform(true)
	_poke_room()


func _exit_tree():
	_poke_room()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_poke_room()


func _poke_room() -> void:
	var p = get_parent()
	if p is Room:
		p._request_rebuild()
