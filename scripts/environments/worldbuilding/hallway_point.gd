@tool
extends Marker3D
class_name HallwayPoint
## A draggable waypoint inside a Hallway. The corridor threads through
## HallwayPoint children in child order. Drag one to a different HEIGHT
## and the segments touching it become stairways automatically.

func _ready():
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var h = get_parent()
		if h is Hallway:
			h._request_rebuild()
