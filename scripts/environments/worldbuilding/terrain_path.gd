@tool
extends Path3D
class_name TerrainPath
## Child of a Terrain node: carves a FLAT WALKABLE PATH along its curve.
## The ground is pulled to the curve's height inside width/2 and blends
## back into the hills over `blend` meters - so a path drawn over rough
## hills becomes a smooth ramped road you can just walk.
##
## HOW TO USE:
##   1. Add a TerrainPath as a CHILD of a Terrain
##   2. Select it and draw/edit the curve with the Path3D toolbar tools
##      (or tick one of the quick shapes below)
##   3. The terrain flattens + colors the strip live as you edit
##
## Curve point HEIGHTS matter: a point dragged uphill makes the road climb
## smoothly to it. Keep point-to-point slopes gentle and the whole route
## is guaranteed walkable.

## Walkable flat width of the path surface.
@export var width: float = 4.0:
	set(v): width = maxf(v, 0.5); _poke_terrain()
## Distance over which the path edge blends back into the hills.
@export var blend: float = 3.0:
	set(v): blend = maxf(v, 0.0); _poke_terrain()
## Surface color painted on the strip (dirt road default).
@export var path_color: Color = Color(0.52, 0.42, 0.3):
	set(v): path_color = v; _poke_terrain()

@export_group("Quick Shapes")
## Tick to replace the curve with a straight line of `shape_length` meters.
@export var make_straight: bool = false:
	set(v):
		if v: _make_straight()
## Tick to replace the curve with a gentle S-bend.
@export var make_s_curve: bool = false:
	set(v):
		if v: _make_s()
@export var shape_length: float = 40.0


func _ready():
	set_notify_transform(true)
	if curve == null or curve.point_count == 0:
		curve = Curve3D.new()
		curve.add_point(Vector3(-10, 0, 0))
		curve.add_point(Vector3(10, 0, 0))
	if not curve_changed.is_connected(_poke_terrain):
		curve_changed.connect(_poke_terrain)
	_poke_terrain()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_poke_terrain()


func _poke_terrain() -> void:
	var p = get_parent()
	if p is Terrain:
		p._request_rebuild()


func _make_straight() -> void:
	curve = Curve3D.new()
	curve.add_point(Vector3(-shape_length * 0.5, 0, 0))
	curve.add_point(Vector3(shape_length * 0.5, 0, 0))
	if not curve_changed.is_connected(_poke_terrain):
		curve_changed.connect(_poke_terrain)
	_poke_terrain()


func _make_s() -> void:
	curve = Curve3D.new()
	var l := shape_length
	curve.add_point(Vector3(-l * 0.5, 0, 0), Vector3.ZERO, Vector3(l * 0.2, 0, 0))
	curve.add_point(Vector3(0, 0, l * 0.25), Vector3(-l * 0.15, 0, 0), Vector3(l * 0.15, 0, 0))
	curve.add_point(Vector3(l * 0.5, 0, 0), Vector3(-l * 0.2, 0, 0), Vector3.ZERO)
	if not curve_changed.is_connected(_poke_terrain):
		curve_changed.connect(_poke_terrain)
	_poke_terrain()
