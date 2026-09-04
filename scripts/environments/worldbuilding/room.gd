@tool
extends Node3D
class_name Room
## Urban room builder. One node = a room; drag rooms around to compose
## whole buildings. No modes - what you do with the drag decides:
##
##   NEAR another room: it snaps flush against it. If both rooms have
##     auto_doorway on (default), a doorway is cut through the shared wall.
##   DEEP OVERLAP (pushed clearly past flush): the rooms MERGE into one
##     irregular open space (L-shapes, T-shapes...). Shared walls vanish.
##
## Doorway children still carve custom doors/windows anywhere.
## Structure is CSG: outer shell minus interior minus openings, so any
## overlapping merged rooms automatically become one clean space.

## Cut a doorway automatically through walls shared with snapped neighbors
## (both rooms need this on). Off = solid shared wall.
@export var auto_doorway: bool = true:
	set(v):
		auto_doorway = v
		_request_rebuild()
		_poke_sibling_rooms()

@export_group("Shape")
## Interior space: width (X), wall height (Y), depth (Z).
@export var interior_size: Vector3 = Vector3(50, 30, 50):
	set(v): interior_size = v; _request_rebuild(); _poke_sibling_rooms()
@export var wall_thickness: float = 0.3:
	set(v): wall_thickness = v; _request_rebuild()
@export var floor_thickness: float = 0.3:
	set(v): floor_thickness = v; _request_rebuild()
@export var has_ceiling: bool = true:
	set(v): has_ceiling = v; _request_rebuild()
## Skip the floor slab (room sits on Terrain or a Floor).
@export var has_floor: bool = true:
	set(v): has_floor = v; _request_rebuild()

@export_group("Auto Doorways")
## Width of the doorway cut into a shared wall when rooms snap together.
@export var auto_doorway_width: float = 2.0:
	set(v): auto_doorway_width = v; _request_rebuild(); _poke_sibling_rooms()
## Height of that doorway.
@export var auto_doorway_height: float = 2.8:
	set(v): auto_doorway_height = v; _request_rebuild(); _poke_sibling_rooms()
## How close (in meters) a dragged room has to get before it snaps flush.
@export var snap_distance: float = 3.0
## Push a room deeper than this (in meters) past flush into another room
## and they MERGE into one space instead of snapping. Kept SMALL so a
## slight push inside is enough - you shouldn't have to stack rooms on
## top of each other. The overlapping wall sections vanish and you can
## walk between the rooms; the rest of both rooms stays intact.
@export var merge_overlap: float = 0.3

@export_group("Colors")
@export var wall_color: Color = Color(0.75, 0.7, 0.62):
	set(v): wall_color = v; _request_rebuild()
@export var floor_color: Color = Color(0.45, 0.36, 0.28):
	set(v): floor_color = v; _request_rebuild()
@export var ceiling_color: Color = Color(0.85, 0.83, 0.78):
	set(v): ceiling_color = v; _request_rebuild()

@export_group("Lights")
## Spawn ceiling lights automatically. Drag them anywhere afterwards -
## they keep their position (only NEW lights get auto-placed).
@export var has_lights: bool = true:
	set(v): has_lights = v; _refresh_lights()
## How many auto lights to keep in this room.
@export_range(1, 24, 1) var light_count: int = 2:
	set(v): light_count = v; _refresh_lights()
@export var light_color: Color = Color(1.0, 0.95, 0.85):
	set(v):
		light_color = v
		for l in _auto_lights():
			l.light_color = v
@export var light_energy: float = 1.6:
	set(v):
		light_energy = v
		for l in _auto_lights():
			l.light_energy = v

var _csg: CSGCombiner3D
var _rebuild_queued := false
var _snapping := false   # Re-entry guard while we move ourselves


func _ready():
	set_notify_transform(true)
	_rebuild()
	_refresh_lights()
	# Existing rooms must re-cut their side of shared doorways / merges
	_poke_sibling_rooms()


# ---------------------------------------------------------------------------
# Ceiling lights
# ---------------------------------------------------------------------------

func _auto_lights() -> Array:
	var out: Array = []
	for c in get_children():
		if c is RoomLight and c.has_meta("auto_light"):
			out.append(c)
	return out


func _refresh_lights() -> void:
	if not is_inside_tree():
		return
	var lights := _auto_lights()
	var wanted: int = light_count if has_lights else 0
	# Too many: remove from the end (hand-added RoomLights are never touched)
	while lights.size() > wanted:
		var l = lights.pop_back()
		l.queue_free()
	# Too few: spawn new ones spread across the ceiling in a grid. Existing
	# lights are NEVER repositioned - wherever you dragged them, they stay.
	if lights.size() < wanted:
		var cols := int(ceilf(sqrt(float(wanted))))
		var rows := int(ceilf(float(wanted) / cols))
		for i in range(lights.size(), wanted):
			var l := RoomLight.new()
			l.name = "RoomLight%d" % (i + 1)
			l.set_meta("auto_light", true)
			l.light_color = light_color
			l.light_energy = light_energy
			var col := i % cols
			var row := i / cols
			var fx := (col + 1.0) / (cols + 1.0) - 0.5
			var fz := (row + 1.0) / (rows + 1.0) - 0.5
			l.position = Vector3(fx * interior_size.x, interior_size.y - 0.05, fz * interior_size.z)
			add_child(l)
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				l.owner = get_tree().edited_scene_root


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and not _snapping:
		_try_snap()
		_request_rebuild()
		_poke_sibling_rooms()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _poke_sibling_rooms():
	# Neighbors need to re-cut their side of shared doorways / merges
	if not is_inside_tree() or get_parent() == null:
		return
	for c in get_parent().get_children():
		if c is Room and c != self:
			c._request_rebuild()


# ---------------------------------------------------------------------------
# Snapping (editor drag)
# ---------------------------------------------------------------------------

func _try_snap() -> void:
	# Pushed deep inside another room? That's a merge - don't snap at all.
	if _find_deep_overlap() != null:
		return
	var best_room: Room = null
	var best_gap := snap_distance
	var best_axis := 0      # 0 = x, 1 = z
	var best_dir := 1.0
	for c in get_parent().get_children():
		if not (c is Room) or c == self:
			continue
		if _overlap_depth(self, c) > merge_overlap:
			continue   # merged with this one - not a snap target
		var other: Room = c
		# Candidate: butt against other's +x / -x / +z / -z exterior
		var my_half := Vector2(interior_size.x * 0.5 + wall_thickness, interior_size.z * 0.5 + wall_thickness)
		var ot_half := Vector2(other.interior_size.x * 0.5 + other.wall_thickness, other.interior_size.z * 0.5 + other.wall_thickness)
		var dx = global_position.x - other.global_position.x
		var dz = global_position.z - other.global_position.z
		# Gap along each axis if we butt on that side (needs overlap on the other axis)
		var gap_x = absf(absf(dx) - (my_half.x + ot_half.x))
		var gap_z = absf(absf(dz) - (my_half.y + ot_half.y))
		var overlap_z = (my_half.y + ot_half.y) - absf(dz)
		var overlap_x = (my_half.x + ot_half.x) - absf(dx)
		if gap_x < best_gap and overlap_z > 1.0:
			best_gap = gap_x; best_room = other; best_axis = 0; best_dir = signf(dx) if dx != 0 else 1.0
		if gap_z < best_gap and overlap_x > 1.0:
			best_gap = gap_z; best_room = other; best_axis = 1; best_dir = signf(dz) if dz != 0 else 1.0
	if best_room == null:
		return
	_snapping = true
	var my_half := Vector2(interior_size.x * 0.5 + wall_thickness, interior_size.z * 0.5 + wall_thickness)
	var ot_half := Vector2(best_room.interior_size.x * 0.5 + best_room.wall_thickness, best_room.interior_size.z * 0.5 + best_room.wall_thickness)
	if best_axis == 0:
		global_position.x = best_room.global_position.x + best_dir * (my_half.x + ot_half.x)
	else:
		global_position.z = best_room.global_position.z + best_dir * (my_half.y + ot_half.y)
	global_position.y = best_room.global_position.y   # Same storey
	_snapping = false


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _csg and is_instance_valid(_csg):
		_csg.free()
	_csg = null
	
	# Merged rooms don't build - the group host's CSG includes them.
	# Host = the merged room that comes FIRST in the scene tree.
	if _merge_group_host() != self:
		return
	
	_csg = CSGCombiner3D.new()
	_csg.use_collision = true
	add_child(_csg)
	
	# Collect this room + every room deep-overlapping it (transitively)
	var group: Array = _merge_group()
	
	# CSG order matters: all SHELLS (union) first, then all interior +
	# opening SUBTRACTIONS - so interiors carve through shared walls and
	# merged rooms become one open space.
	for r in group:
		_add_shell(r)
	for r in group:
		_add_interior_cut(r)
	for r in group:
		_add_doorway_cuts(r)
	for r in group:
		_add_auto_doorways(r, group)
	# Merge passages: blow open the overlap zone between every merged pair
	# so the shared wall sections vanish and you can WALK between rooms
	# (interior cuts alone leave a slab standing on shallow overlaps).
	for i in range(group.size()):
		for j in range(i + 1, group.size()):
			if _overlap_depth(group[i], group[j]) > minf(group[i].merge_overlap, group[j].merge_overlap):
				_add_merge_passage(group[i], group[j])
	# Colored floor/ceiling faces go in LAST so no cut erases them
	for r in group:
		_add_interior_liners(r)


func _overlap_depth(a: Room, b: Room) -> float:
	"""How far a's exterior footprint penetrates b's, in meters (the SMALLER
	of the two axis penetrations - i.e. how far past flush the rooms sit).
	<= 0 means not overlapping."""
	var ah := Vector2(a.interior_size.x * 0.5 + a.wall_thickness, a.interior_size.z * 0.5 + a.wall_thickness)
	var bh := Vector2(b.interior_size.x * 0.5 + b.wall_thickness, b.interior_size.z * 0.5 + b.wall_thickness)
	var d := Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z)
	var pen_x := (ah.x + bh.x) - absf(d.x)
	var pen_z := (ah.y + bh.y) - absf(d.y)
	return minf(pen_x, pen_z)


func _find_deep_overlap() -> Room:
	"""First sibling room we overlap deeply enough to count as a merge."""
	if get_parent() == null:
		return null
	for c in get_parent().get_children():
		if c is Room and c != self and _overlap_depth(self, c) > merge_overlap:
			return c
	return null


func _merge_group() -> Array:
	"""This room + every room connected to it through deep overlaps
	(transitive), in scene-tree order starting from self."""
	var group: Array = [self]
	if get_parent():
		var changed := true
		while changed:
			changed = false
			for c in get_parent().get_children():
				if c is Room and not group.has(c):
					for g in group:
						if _overlap_depth(c, g) > merge_overlap:
							group.append(c)
							changed = true
							break
	return group


func _merge_group_host() -> Room:
	"""The room in our merge group that builds the shared CSG: the one
	earliest in the scene tree. Alone = ourselves."""
	var host: Room = self
	for r in _merge_group():
		if r.get_index() < host.get_index():
			host = r
	return host


func _room_offset(r: Room) -> Vector3:
	# Other rooms' geometry expressed in OUR local space
	return r.global_position - global_position


func _add_shell(r: Room) -> void:
	var w: float = r.interior_size.x; var h: float = r.interior_size.y; var d: float = r.interior_size.z
	var t: float = r.wall_thickness
	var off := _room_offset(r)
	var bottom: float = -r.floor_thickness if r.has_floor else 0.0
	var top: float = h + (t if r.has_ceiling else 0.0)
	var shell := CSGBox3D.new()
	shell.size = Vector3(w + 2 * t, top - bottom, d + 2 * t)
	shell.position = off + Vector3(0, (top + bottom) * 0.5, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = r.wall_color
	m.roughness = 0.95
	shell.material = m
	_csg.add_child(shell)


func _add_interior_cut(r: Room) -> void:
	var w: float = r.interior_size.x; var h: float = r.interior_size.y; var d: float = r.interior_size.z
	var off := _room_offset(r)
	var cut := CSGBox3D.new()
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	# If no ceiling, cut extends up past the shell top; if no floor, down
	var top: float = h if r.has_ceiling else h + r.wall_thickness + 1.0
	var bottom: float = 0.0 if r.has_floor else -r.floor_thickness - 1.0
	cut.size = Vector3(w, top - bottom, d)
	cut.position = off + Vector3(0, (top + bottom) * 0.5, 0)
	# CSG rule: faces exposed by a subtraction take the SUBTRACTING brush's
	# material - leaving this unset is why interiors rendered plain grey.
	cut.material = _mat(r.wall_color)
	_csg.add_child(cut)


func _add_interior_liners(r: Room) -> void:
	"""Thin colored panels laid over the interior floor and under the
	ceiling so floor_color / ceiling_color show INSIDE the room (the
	interior cut paints everything wall_color otherwise). Added after all
	subtractions so they survive them."""
	var w: float = r.interior_size.x; var h: float = r.interior_size.y; var d: float = r.interior_size.z
	var off := _room_offset(r)
	if r.has_floor:
		var fl := CSGBox3D.new()
		fl.size = Vector3(w, 0.04, d)
		fl.position = off + Vector3(0, 0.02, 0)
		fl.material = _mat(r.floor_color)
		_csg.add_child(fl)
	if r.has_ceiling:
		var cl := CSGBox3D.new()
		cl.size = Vector3(w, 0.04, d)
		cl.position = off + Vector3(0, h - 0.02, 0)
		cl.material = _mat(r.ceiling_color)
		_csg.add_child(cl)


func _add_merge_passage(a: Room, b: Room) -> void:
	"""Subtract the overlap zone between two merged rooms so the wall
	sections inside it are GONE and the rooms become one traversable
	space. The cut spans the exterior overlap along the penetration axis
	(punching through BOTH wall slabs) but only the interiors' shared
	range on the transverse axis, so outer corners stay sealed."""
	# Exterior + interior half-extents (XZ)
	var aeh := Vector2(a.interior_size.x * 0.5 + a.wall_thickness, a.interior_size.z * 0.5 + a.wall_thickness)
	var beh := Vector2(b.interior_size.x * 0.5 + b.wall_thickness, b.interior_size.z * 0.5 + b.wall_thickness)
	var aih := Vector2(a.interior_size.x * 0.5, a.interior_size.z * 0.5)
	var bih := Vector2(b.interior_size.x * 0.5, b.interior_size.z * 0.5)
	var ap := Vector2(a.global_position.x, a.global_position.z)
	var bp := Vector2(b.global_position.x, b.global_position.z)
	# Exterior overlap ranges
	var ox_lo := maxf(ap.x - aeh.x, bp.x - beh.x); var ox_hi := minf(ap.x + aeh.x, bp.x + beh.x)
	var oz_lo := maxf(ap.y - aeh.y, bp.y - beh.y); var oz_hi := minf(ap.y + aeh.y, bp.y + beh.y)
	if ox_hi <= ox_lo or oz_hi <= oz_lo:
		return
	# Interior overlap ranges (transverse limits)
	var ix_lo := maxf(ap.x - aih.x, bp.x - bih.x); var ix_hi := minf(ap.x + aih.x, bp.x + bih.x)
	var iz_lo := maxf(ap.y - aih.y, bp.y - bih.y); var iz_hi := minf(ap.y + aih.y, bp.y + bih.y)
	# Penetration axis = the thinner exterior overlap; transverse uses the
	# interiors' shared range so side walls/corners survive.
	var x_lo: float; var x_hi: float; var z_lo: float; var z_hi: float
	if (ox_hi - ox_lo) <= (oz_hi - oz_lo):
		x_lo = ox_lo - 0.05; x_hi = ox_hi + 0.05
		z_lo = iz_lo; z_hi = iz_hi
	else:
		x_lo = ix_lo; x_hi = ix_hi
		z_lo = oz_lo - 0.05; z_hi = oz_hi + 0.05
	if x_hi - x_lo < 0.05 or z_hi - z_lo < 0.05:
		return   # Corner-touch only, no walkable passage
	# Vertical: shared interior height band
	var y_lo := maxf(a.global_position.y, b.global_position.y)
	var y_hi := minf(a.global_position.y + a.interior_size.y, b.global_position.y + b.interior_size.y)
	if y_hi - y_lo < 0.5:
		return
	var cut := CSGBox3D.new()
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	cut.size = Vector3(x_hi - x_lo, y_hi - y_lo, z_hi - z_lo)
	cut.position = Vector3((x_lo + x_hi) * 0.5, (y_lo + y_hi) * 0.5, (z_lo + z_hi) * 0.5) - global_position
	cut.material = _mat(wall_color)
	_csg.add_child(cut)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


func _add_doorway_cuts(r: Room) -> void:
	var off := _room_offset(r)
	for c in r.get_children():
		if c is Doorway:
			var cut := CSGBox3D.new()
			cut.operation = CSGShape3D.OPERATION_SUBTRACTION
			var depth: float = maxf(c.cut_depth, r.wall_thickness * 2.0)
			var rot: float = c.rotation.y
			if absf(rot) < 0.01:
				var dist_x = absf(absf(c.position.x) - r.interior_size.x * 0.5)
				var dist_z = absf(absf(c.position.z) - r.interior_size.z * 0.5)
				if dist_x < dist_z:
					rot = PI * 0.5
			cut.size = Vector3(c.width, c.height, depth)
			cut.position = off + Vector3(c.position.x, c.sill_height + c.height * 0.5, c.position.z)
			cut.rotation.y = rot
			cut.material = _mat(r.wall_color)   # Colored jambs, not grey
			_csg.add_child(cut)


func _add_auto_doorways(r: Room, group: Array) -> void:
	"""Cut a doorway through every wall r shares with a snapped neighbor
	(both rooms need auto_doorway on)."""
	if not r.auto_doorway or get_parent() == null:
		return
	for c in get_parent().get_children():
		if not (c is Room) or c == r or group.has(c):
			continue
		if not c.auto_doorway:
			continue
		var n: Room = c
		var rh := Vector2(r.interior_size.x * 0.5 + r.wall_thickness, r.interior_size.z * 0.5 + r.wall_thickness)
		var nh := Vector2(n.interior_size.x * 0.5 + n.wall_thickness, n.interior_size.z * 0.5 + n.wall_thickness)
		var dx: float = n.global_position.x - r.global_position.x
		var dz: float = n.global_position.z - r.global_position.z
		var w := maxf(r.auto_doorway_width, 0.5)
		var hgt := minf(maxf(r.auto_doorway_height, 1.0), minf(r.interior_size.y, n.interior_size.y))
		var cut: CSGBox3D = null
		# Shared wall along X (neighbor to the east/west)
		if absf(absf(dx) - (rh.x + nh.x)) < 0.1:
			var lo = maxf(-rh.y, dz - nh.y); var hi = minf(rh.y, dz + nh.y)
			if hi - lo > w * 0.75:
				var center_z = clampf((lo + hi) * 0.5, lo + w * 0.5, hi - w * 0.5)
				cut = CSGBox3D.new()
				cut.size = Vector3((r.wall_thickness + n.wall_thickness) * 2.5, hgt, w)
				cut.position = Vector3(signf(dx) * rh.x, hgt * 0.5, center_z)
		# Shared wall along Z (neighbor to the north/south)
		elif absf(absf(dz) - (rh.y + nh.y)) < 0.1:
			var lo = maxf(-rh.x, dx - nh.x); var hi = minf(rh.x, dx + nh.x)
			if hi - lo > w * 0.75:
				var center_x = clampf((lo + hi) * 0.5, lo + w * 0.5, hi - w * 0.5)
				cut = CSGBox3D.new()
				cut.size = Vector3(w, hgt, (r.wall_thickness + n.wall_thickness) * 2.5)
				cut.position = Vector3(center_x, hgt * 0.5, signf(dz) * rh.y)
		if cut:
			cut.operation = CSGShape3D.OPERATION_SUBTRACTION
			cut.position += _room_offset(r)
			cut.material = _mat(r.wall_color)   # Colored jambs, not grey
			_csg.add_child(cut)
