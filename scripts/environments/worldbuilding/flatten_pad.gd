@tool
extends Marker3D
class_name FlattenPad
## Child of a Terrain node: flattens the ground beneath it to the pad's
## own height - perfect for building sites, arenas or spawn clearings.
## Move it around in the editor and the terrain updates live.

## Fully-flat radius around the pad.
@export var radius: float = 8.0:
	set(v): radius = v; _poke_terrain()
## Extra distance over which the flat area blends back into the hills.
@export var blend: float = 5.0:
	set(v): blend = v; _poke_terrain()


func _ready():
	set_notify_transform(true)
	_poke_terrain()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_poke_terrain()


func _poke_terrain() -> void:
	var p = get_parent()
	if p is Terrain:
		p._request_rebuild()
