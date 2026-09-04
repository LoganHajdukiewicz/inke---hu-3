@tool
extends Node3D
class_name Hallway
## Connects TWO DOORWAYS with a corridor. Flat segments become hallways;
## any segment whose two ends sit at different heights becomes a STAIRWAY
## automatically - so one Hallway can be hall -> stairs -> hall if you
## shape the points that way.
##
## HOW TO USE
##   1. Put a Doorway on each of the two rooms you want to connect.
##   2. Add a Hallway node anywhere and set door_a / door_b to those
##      Doorways. The corridor builds itself between them (it always
##      leaves each door straight out of its wall).
##   3. Want corners or a specific route? Add HallwayPoint children
##      (Add Node > HallwayPoint) and drag them around - the corridor
##      threads through them in child order. Give a point a different
##      height and the segments touching it turn into stairs.
##
## Same look/feel exports as Room: thicknesses, colors, ceiling, lights.
## Stairs get real visible steps plus an invisible smooth ramp at the
## step noses so walking up/down is buttery.

@export var door_a: Doorway:
	set(v): door_a = v; _request_rebuild()
@export var door_b: Doorway:
	set(v): door_b = v; _request_rebuild()

@export_group("Shape")
## Interior width of the corridor.
@export var width: float = 2.4:
	set(v): width = v; _request_rebuild()
## Interior height of the corridor.
@export var height: float = 3.0:
	set(v): height = v; _request_rebuild()
@export var wall_thickness: float = 0.3:
	set(v): wall_thickness = v; _request_rebuild()
@export var floor_thickness: float = 0.3:
	set(v): floor_thickness = v; _request_rebuild()
@export var has_ceiling: bool = true:
	set(v): has_ceiling = v; _request_rebuild()
## How far the corridor runs straight out of each door before turning.
@export var stub_length: float = 1.5:
	set(v): stub_length = v; _request_rebuild()

@export_group("Stairs")
## Height of each step riser. Segment rise is split into equal steps.
@export var step_height: float = 0.22:
	set(v): step_height = v; _request_rebuild()

@export_group("Colors")
@export var wall_color: Color = Color(0.75, 0.7, 0.62):
	set(v): wall_color = v; _request_rebuild()
@export var floor_color: Color = Color(0.45, 0.36, 0.28):
	set(v): floor_color = v; _request_rebuild()
@export var ceiling_color: Color = Color(0.85, 0.83, 0.78):
	set(v): ceiling_color = v; _request_rebuild()

@export_group("Lights")
@export var has_lights: bool = true:
	set(v): has_lights = v; _request_rebuild()
@export var light_color: Color = Color(1.0, 0.95, 0.85):
	set(v): light_color = v; _request_rebuild()
@export var light_energy: float = 1.2:
	set(v): light_energy = v; _request_rebuild()

var _csg: CSGCombiner3D
var _rebuild_queued := false
var _anchor_cache := []   # doorway/room pose cache for cheap editor polling
var _poll_accum := 0.0


func _ready():
	set_notify_transform(true)
	_request_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_request_rebuild()


func _process(delta: float) -> void:
	# Editor-only: rebuild when a connected door/room moves (they don't
	# know about us, so we poll their poses a few times a second).
	if not Engine.is_editor_hint():
		set_process(false)
		return
	_poll_accum += delta
	if _poll_accum < 0.25:
		return
	_poll_accum = 0.0
	var sig := []
	for dw in [door_a, door_b]:
		if dw and is_instance_valid(dw):
			sig.append(dw.global_position)
			var r = dw.get_parent()
			if r is Room:
				sig.append(r.global_position)
				sig.append(r.interior_size)
	if sig != _anchor_cache:
		_anchor_cache = sig
		_request_rebuild()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


# ---------------------------------------------------------------------------
# Path assembly
# ---------------------------------------------------------------------------
func _door_anchor(dw: Doorway) -> Dictionary:
	"""Global floor-center point on the OUTSIDE face of the doorway's wall,
	plus the outward direction. Hallways always leave a door straight out."""
	var r = dw.get_parent()
	if not (r is Room):
		# Doorway not on a Room: use the marker itself, -Z as outward.
		return {"pos": dw.global_position, "out": -dw.global_transform.basis.z.normalized()}
	var d: Vector3 = dw.global_position - r.global_position
	var half_x: float = r.interior_size.x * 0.5
	var half_z: float = r.interior_size.z * 0.5
	var out: Vector3
	var pos: Vector3
	# Nearest wall = the axis whose face the marker sits closest to
	if absf(absf(d.x) - half_x) < absf(absf(d.z) - half_z):
		out = Vector3(signf(d.x) if d.x != 0 else 1.0, 0, 0)
		pos = r.global_position + out * (half_x + r.wall_thickness) + Vector3(0, 0, clampf(d.z, -half_z + width * 0.5, half_z - width * 0.5))
	else:
		out = Vector3(0, 0, signf(d.z) if d.z != 0 else 1.0)
		pos = r.global_position + out * (half_z + r.wall_thickness) + Vector3(clampf(d.x, -half_x + width * 0.5, half_x - width * 0.5), 0, 0)
	pos.y = r.global_position.y   # room floor level
	return {"pos": pos, "out": out}


func _waypoints() -> Array:
	"""Global path: doorA anchor -> stubA -> HallwayPoint children (child
	order) -> stubB -> doorB anchor."""
	if door_a == null or door_b == null or not is_instance_valid(door_a) or not is_instance_valid(door_b):
		return []
	var a := _door_anchor(door_a)
	var b := _door_anchor(door_b)
	var pts: Array = []
	pts.append(a.pos)
	pts.append(a.pos + a.out * maxf(stub_length, 0.2))
	for c in get_children():
		if c is HallwayPoint:
			pts.append(c.global_position)
	pts.append(b.pos + b.out * maxf(stub_length, 0.2))
	pts.append(b.pos)
	return pts


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
	for c in get_children():
		if c.has_meta("hall_extra"):
			c.free()
	
	var pts := _waypoints()
	if pts.size() < 2:
		return
	# Work in local space
	var lp: Array = []
	for p in pts:
		lp.append(to_local(p))
	
	_csg = CSGCombiner3D.new()
	_csg.use_collision = true
	add_child(_csg)
	
	# 1) All shells (union)
	for i in range(lp.size() - 1):
		_add_segment_shell(lp[i], lp[i + 1])
	for i in range(1, lp.size() - 1):
		_add_elbow(lp[i], false)
	# 2) All interior cuts (subtraction)
	for i in range(lp.size() - 1):
		_add_segment_cut(lp[i], lp[i + 1], i == 0, i == lp.size() - 2)
	for i in range(1, lp.size() - 1):
		_add_elbow(lp[i], true)
	# 3) Steps + floor/ceiling liners (added last so cuts don't erase them)
	for i in range(lp.size() - 1):
		_add_segment_dressing(lp[i], lp[i + 1])
	for i in range(1, lp.size() - 1):
		_add_elbow_liner(lp[i])
	# 4) Lights
	if has_lights:
		for i in range(lp.size() - 1):
			_add_light((lp[i] + lp[i + 1]) * 0.5, maxf(lp[i].y, lp[i + 1].y))


func _seg_info(p0: Vector3, p1: Vector3) -> Dictionary:
	var flat := Vector2(p1.x - p0.x, p1.z - p0.z)
	var l := flat.length()
	var rise := p1.y - p0.y
	return {
		"len": l,
		"rise": rise,
		"is_stairs": absf(rise) > 0.05 and l > 0.1,
		"dir": Vector3(flat.x, 0, flat.y) / l if l > 0.001 else Vector3.FORWARD,
	}


func _yaw_basis(dir: Vector3) -> Basis:
	return Basis.looking_at(dir, Vector3.UP)


func _slope_basis(p0: Vector3, p1: Vector3) -> Basis:
	var v := (p1 - p0)
	if v.length() < 0.001:
		return Basis.IDENTITY
	return Basis.looking_at(v.normalized(), Vector3.UP)


func _add_segment_shell(p0: Vector3, p1: Vector3) -> void:
	var s := _seg_info(p0, p1)
	if s.len < 0.05:
		return
	var t := wall_thickness
	var mid := (p0 + p1) * 0.5
	var box := CSGBox3D.new()
	box.material = _mat(wall_color)
	if s.is_stairs:
		var sb := _slope_basis(p0 if p0.y <= p1.y else p1, p1 if p0.y <= p1.y else p0)
		var slen: float = p0.distance_to(p1)
		box.size = Vector3(width + 2 * t, height + 2 * t + step_height * 2.0, slen + 0.05)
		box.transform = Transform3D(sb, mid + sb.y * (height * 0.5) - Vector3.UP * step_height * 0.5)
	else:
		var top: float = p0.y + height + (t if has_ceiling else 0.0)
		var bottom: float = p0.y - floor_thickness
		box.size = Vector3(width + 2 * t, top - bottom, s.len + 0.05)
		box.transform = Transform3D(_yaw_basis(s.dir), Vector3(mid.x, (top + bottom) * 0.5, mid.z))
	_csg.add_child(box)


func _add_segment_cut(p0: Vector3, p1: Vector3, open_start: bool, open_end: bool) -> void:
	var s := _seg_info(p0, p1)
	if s.len < 0.05:
		return
	var mid := (p0 + p1) * 0.5
	var cut := CSGBox3D.new()
	cut.operation = CSGShape3D.OPERATION_SUBTRACTION
	cut.material = _mat(wall_color)
	# Extend past open ends so the end faces punch open (against the door
	# walls the room's own Doorway provides the opening).
	var ext_a: float = 0.6 if open_start else 0.3
	var ext_b: float = 0.6 if open_end else 0.3
	if s.is_stairs:
		var lo := p0 if p0.y <= p1.y else p1
		var hi := p1 if p0.y <= p1.y else p0
		var sb := _slope_basis(lo, hi)
		var slen: float = p0.distance_to(p1)
		var n: int = maxi(1, int(ceilf(absf(s.rise) / maxf(step_height, 0.05))))
		var sh: float = absf(s.rise) / n
		# Floor plane sits ONE RISER below the step noses so the visible
		# steps poke through it; the invisible ramp walks the nose line.
		cut.size = Vector3(width, height, slen + ext_a + ext_b)
		cut.transform = Transform3D(sb, mid + sb.y * (height * 0.5) - Vector3.UP * sh)
	else:
		var top: float = p0.y + height + (0.0 if has_ceiling else wall_thickness + 1.0)
		var bottom: float = p0.y
		cut.size = Vector3(width, top - bottom, s.len + ext_a + ext_b)
		cut.transform = Transform3D(_yaw_basis(s.dir), Vector3(mid.x, (top + bottom) * 0.5, mid.z))
	_csg.add_child(cut)


func _add_segment_dressing(p0: Vector3, p1: Vector3) -> void:
	var s := _seg_info(p0, p1)
	if s.len < 0.05:
		return
	if s.is_stairs:
		_add_stairs(p0, p1)
		return
	# Flat: floor liner + ceiling liner
	var mid := (p0 + p1) * 0.5
	var fl := CSGBox3D.new()
	fl.size = Vector3(width - 0.02, 0.04, s.len)
	fl.transform = Transform3D(_yaw_basis(s.dir), Vector3(mid.x, p0.y + 0.02, mid.z))
	fl.material = _mat(floor_color)
	_csg.add_child(fl)
	if has_ceiling:
		var cl := CSGBox3D.new()
		cl.size = Vector3(width - 0.02, 0.04, s.len)
		cl.transform = Transform3D(_yaw_basis(s.dir), Vector3(mid.x, p0.y + height - 0.02, mid.z))
		cl.material = _mat(ceiling_color)
		_csg.add_child(cl)


func _add_stairs(p0: Vector3, p1: Vector3) -> void:
	"""Visible steps (CSG, floor_color) + an invisible smooth ramp along the
	step noses so characters walk up without stuttering on risers."""
	var lo := p0 if p0.y <= p1.y else p1
	var hi := p1 if p0.y <= p1.y else p0
	var s := _seg_info(lo, hi)
	var n: int = maxi(1, int(ceilf(s.rise / maxf(step_height, 0.05))))
	var sh: float = s.rise / n
	var tread: float = s.len / n
	var dir: Vector3 = s.dir
	var yaw := _yaw_basis(dir)
	var bottom: float = lo.y - floor_thickness - sh
	for i in range(n):
		var top: float = lo.y + i * sh
		var center := lo + dir * ((i + 0.5) * tread)
		var box := CSGBox3D.new()
		box.size = Vector3(width - 0.02, maxf(top - bottom, 0.05), tread + 0.02)
		box.transform = Transform3D(yaw, Vector3(center.x, (top + bottom) * 0.5, center.z))
		box.material = _mat(floor_color)
		_csg.add_child(box)
	# Invisible nose ramp (separate body, not part of the CSG)
	var ramp := StaticBody3D.new()
	ramp.name = "StairRamp"
	ramp.set_meta("hall_extra", true)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var slen: float = lo.distance_to(hi)
	shape.size = Vector3(width, 0.4, slen + 0.1)
	cs.shape = shape
	var sb := _slope_basis(lo, hi)
	add_child(ramp)
	ramp.add_child(cs)
	ramp.transform = Transform3D(sb, (lo + hi) * 0.5 - sb.y * 0.2)
	if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
		pass   # runtime-built, never owned - rebuilt from exports each load


func _add_elbow(p: Vector3, is_cut: bool) -> void:
	var t := wall_thickness
	var box := CSGBox3D.new()
	box.material = _mat(wall_color)
	if is_cut:
		box.operation = CSGShape3D.OPERATION_SUBTRACTION
		box.size = Vector3(width, height, width)
		box.position = p + Vector3(0, height * 0.5, 0)
	else:
		var top: float = height + (t if has_ceiling else 0.0)
		box.size = Vector3(width + 2 * t, top + floor_thickness, width + 2 * t)
		box.position = p + Vector3(0, (top - floor_thickness) * 0.5, 0)
	_csg.add_child(box)


func _add_elbow_liner(p: Vector3) -> void:
	var fl := CSGBox3D.new()
	fl.size = Vector3(width - 0.02, 0.04, width - 0.02)
	fl.position = p + Vector3(0, 0.02, 0)
	fl.material = _mat(floor_color)
	_csg.add_child(fl)
	if has_ceiling:
		var cl := CSGBox3D.new()
		cl.size = Vector3(width - 0.02, 0.04, width - 0.02)
		cl.position = p + Vector3(0, height - 0.02, 0)
		cl.material = _mat(ceiling_color)
		_csg.add_child(cl)


func _add_light(mid: Vector3, floor_y: float) -> void:
	var l := RoomLight.new()
	l.set_meta("hall_extra", true)
	l.light_color = light_color
	l.light_energy = light_energy
	l.light_range = maxf(width, 6.0)
	add_child(l)
	l.position = Vector3(mid.x, floor_y + height - 0.05, mid.z)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m
