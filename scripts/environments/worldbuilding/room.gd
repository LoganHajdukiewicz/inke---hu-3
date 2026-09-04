@tool
extends Node3D
class_name Room
## Instant building interior - urban/office style, not dungeons.
## One node = floor + four walls + optional ceiling, built with CSG so
## Doorway children literally CARVE openings out of the walls wherever
## you drag them (doors, windows, storefront glass holes...).
##
## HOW TO USE:
##   1. Add a Room node (or instance room.tscn), set interior_size
##   2. Add a Doorway child, drag it INTO a wall - the opening is cut
##      right there, live. Raise sill_height to make it a window.
##   3. Butt Rooms up against each other and put a Doorway through the
##      shared wall of each to connect them into a building.
##
## has_floor/has_ceiling let rooms sit on Terrain/Floor or stack into
## storeys. All geometry is runtime-generated CSG with collision - the
## scene file stays tiny.

@export_group("Shape")
## Interior space: width (X), wall height (Y), depth (Z).
@export var interior_size: Vector3 = Vector3(10, 4, 8):
	set(v): interior_size = v; _request_rebuild()
@export var wall_thickness: float = 0.3:
	set(v): wall_thickness = v; _request_rebuild()
@export var floor_thickness: float = 0.3:
	set(v): floor_thickness = v; _request_rebuild()
@export var has_ceiling: bool = true:
	set(v): has_ceiling = v; _request_rebuild()
## Skip the floor slab (room sits on Terrain or a Floor).
@export var has_floor: bool = true:
	set(v): has_floor = v; _request_rebuild()

@export_group("Colors")
@export var wall_color: Color = Color(0.75, 0.7, 0.62):
	set(v): wall_color = v; _request_rebuild()
@export var floor_color: Color = Color(0.45, 0.36, 0.28):
	set(v): floor_color = v; _request_rebuild()
@export var ceiling_color: Color = Color(0.85, 0.83, 0.78):
	set(v): ceiling_color = v; _request_rebuild()

var _csg: CSGCombiner3D
var _rebuild_queued := false


func _ready():
	_rebuild()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _csg and is_instance_valid(_csg):
		_csg.free()
	_csg = CSGCombiner3D.new()
	_csg.use_collision = true
	add_child(_csg)
	
	var w := interior_size.x
	var h := interior_size.y
	var d := interior_size.z
	var t := wall_thickness
	
	# Solid parts (union)
	if has_floor:
		_box(Vector3(w + 2 * t, floor_thickness, d + 2 * t), Vector3(0, -floor_thickness * 0.5, 0), floor_color)
	if has_ceiling:
		_box(Vector3(w + 2 * t, t, d + 2 * t), Vector3(0, h + t * 0.5, 0), ceiling_color)
	# Walls: N/S span full width incl. corners, E/W fit between them
	_box(Vector3(w + 2 * t, h, t), Vector3(0, h * 0.5, -(d + t) * 0.5), wall_color)
	_box(Vector3(w + 2 * t, h, t), Vector3(0, h * 0.5, (d + t) * 0.5), wall_color)
	_box(Vector3(t, h, d), Vector3(-(w + t) * 0.5, h * 0.5, 0), wall_color)
	_box(Vector3(t, h, d), Vector3((w + t) * 0.5, h * 0.5, 0), wall_color)
	
	# Doorway children carve openings (subtraction)
	for c in get_children():
		if c is Doorway:
			var cut := CSGBox3D.new()
			cut.operation = CSGShape3D.OPERATION_SUBTRACTION
			var depth: float = maxf(c.cut_depth, t * 2.0)
			# Auto-orient the cut toward the nearest wall (E/W walls need
			# the box rotated 90deg) unless the user rotated the Doorway
			# themselves - then their rotation wins.
			var rot: float = c.rotation.y
			if absf(rot) < 0.01:
				var dist_x = absf(absf(c.position.x) - w * 0.5)
				var dist_z = absf(absf(c.position.z) - d * 0.5)
				if dist_x < dist_z:
					rot = PI * 0.5
			cut.size = Vector3(c.width, c.height, depth)
			cut.position = Vector3(c.position.x, c.sill_height + c.height * 0.5, c.position.z)
			cut.rotation.y = rot
			_csg.add_child(cut)


func _box(size: Vector3, pos: Vector3, color: Color) -> void:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	b.material = m
	_csg.add_child(b)
