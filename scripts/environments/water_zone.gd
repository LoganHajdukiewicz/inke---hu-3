@tool
extends Area3D
class_name WaterZone
## WATER. Not a gameplay focus - it's the soft edge of the world. Swim on
## the surface, dive under (oxygen drains, drown at zero), and don't stray
## too far from land: past the buoy line a shark comes for you.
##
## HOW TO USE:
##   1. Add a WaterZone where the world should end (beach, harbor, docks).
##      The node's Y is the water surface height.
##   2. Size the water with water_size / water_depth.
##   3. The zone scans for LAND around it (terrain, floors, platforms -
##      any physics body that sticks up above the surface) and floats the
##      buoy line boundary_distance meters (default 20) out from the
##      nearest land edge. Swim past the buoys and after a short hidden
##      grace period the shark charges. Make it back inside the line (or
##      onto land) before it reaches you and it breaks off the attack.
##      Jumping does NOT save you - the shark tracks you horizontally and
##      lunges when it's under you. Land or safe water only.
##
## The player is detected automatically (Area3D). SwimmingState handles
## the actual swimming; this node owns water visuals, buoys, the boundary
## and the shark.

const SHORE_CELL := 2.0   # Meters per cell of the land-distance scan grid

@export_group("Water")
## Water rectangle in meters (X by Z). The node's origin is the center.
@export var water_size: Vector2 = Vector2(200, 200):
	set(v): water_size = v; _request_rebuild()
## How deep the water volume reaches below the surface.
@export var water_depth: float = 10.0:
	set(v): water_depth = maxf(v, 1.0); _request_rebuild()
@export var water_color: Color = Color(0.08, 0.32, 0.45, 0.6):
	set(v): water_color = v; _request_rebuild()

@export_group("Boundary")
## Shark territory starts this many meters out from the EDGE OF LAND
## (terrain, floors - anything solid above the surface). The buoy line
## floats here. If no land borders the water, falls back to a ring this
## far from the node's origin.
@export var boundary_distance: float = 20.0:
	set(v): boundary_distance = maxf(v, 3.0); _request_rebuild()
## Hidden grace period (seconds) past the buoys before the shark charges.
@export var warning_time: float = 2.0
## Shark charge speed in m/s.
@export var shark_speed: float = 18.1
## Meters between buoys along the line.
@export var buoy_spacing: float = 4.0:
	set(v): buoy_spacing = maxf(v, 1.0); _request_rebuild()
@export var boundary_enabled: bool = true:
	set(v): boundary_enabled = v; _request_rebuild()

@export_group("Diving")
## Seconds of air when fully submerged. Refills fast at the surface.
@export var oxygen_seconds: float = 12.0

var _visuals: Node3D = null
var _buoys: Array = []          # [MeshInstance3D, phase]
var _col: CollisionShape3D = null
var _player: CharacterBody3D = null
var _player_inside := false
var _warn_timer := 0.0
var _time := 0.0

# Land-distance field (built from a raycast scan of the water rectangle)
var _shore_dirty := true
var _shore_nx := 0
var _shore_nz := 0
var _shore_dist: PackedFloat32Array = []   # Meters to nearest land, per cell
var _shore_has_land := false
var _shore_ready := false      # Boundary is enforced only after a scan
var _shore_ox := 0.0           # Local-space origin of the fine scan grid
var _shore_oz := 0.0
var _shore_cell := SHORE_CELL  # Cell size of the fine grid (meters)
var _scan_wait := 3            # Physics frames to wait before scanning
var _scan_attempts := 0        # Retries while terrain collision builds

# Shark
enum SharkPhase { NONE, CHARGE, LEAVE }
var _shark: Node3D = null
var _shark_phase := SharkPhase.NONE
var _shark_leave_dir := Vector3.FORWARD
var _shark_leave_t := 0.0


func _ready():
	add_to_group("WaterZone")
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 1
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_rebuild()


func _request_rebuild():
	if is_inside_tree():
		_rebuild()


func _rebuild():
	if _visuals and is_instance_valid(_visuals):
		_visuals.free()
	_visuals = Node3D.new()
	add_child(_visuals)
	_buoys.clear()
	# Buoys spawn after the next land scan. Terrain builds its collision
	# deferred, so wait a few physics frames and retry if no land turns up.
	_shore_dirty = true
	_shore_ready = false
	_scan_wait = 3
	_scan_attempts = 0
	
	# --- Detection volume (surface down to depth) --------------------------
	if _col == null or not is_instance_valid(_col):
		_col = CollisionShape3D.new()
		add_child(_col)
	var box := BoxShape3D.new()
	box.size = Vector3(water_size.x, water_depth, water_size.y)
	_col.shape = box
	_col.position = Vector3(0, -water_depth * 0.5, 0)
	
	# --- Surface ------------------------------------------------------------
	var surf := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = water_size
	surf.mesh = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = water_color
	m.metallic = 0.4
	m.roughness = 0.15
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	surf.material_override = m
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visuals.add_child(surf)
	
	# Murk: a darker translucent slab filling the volume so depths look deep
	var murk := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(water_size.x, water_depth - 0.2, water_size.y)
	murk.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(water_color.r * 0.4, water_color.g * 0.45, water_color.b * 0.55, 0.5)
	mm.cull_mode = BaseMaterial3D.CULL_FRONT   # Visible from inside
	murk.material_override = mm
	murk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	murk.position.y = -water_depth * 0.5
	_visuals.add_child(murk)


# --- Land scan -----------------------------------------------------------
# Raycast a grid over the water rectangle to find LAND: any physics body
# whose surface pokes up to (or above) the water level. Terrain, floors,
# docks - anything solid counts. Then a distance transform gives "meters
# to nearest land" for every cell, which drives buoys and shark territory.

func _physics_process(_delta: float):
	if not _shore_dirty or not is_inside_tree():
		return
	if _scan_wait > 0:
		_scan_wait -= 1   # Give Terrain etc. time to build their collision
		return
	_shore_dirty = false
	_scan_shore()
	if not _shore_has_land and _scan_attempts < 20:
		# No land found - probably still building. Retry shortly.
		_scan_attempts += 1
		_shore_dirty = true
		_scan_wait = 10
		return
	_shore_ready = true
	if boundary_enabled:
		_spawn_buoys()


func _scan_shore():
	_shore_has_land = false
	_shore_dist = PackedFloat32Array()
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	
	# Don't let the player (or the shark) register as land
	var exclude: Array[RID] = []
	if not Engine.is_editor_hint():
		var p := get_tree().get_first_node_in_group("Player")
		if p is CollisionObject3D:
			exclude.append(p.get_rid())
	
	var surface_y := global_position.y
	var big := 1e9
	
	# PASS 1 - coarse: find land anywhere in the water rectangle and its
	# bounding box. Coarse cells keep huge oceans cheap (<=128 per side).
	var cc := maxf(SHORE_CELL, maxf(water_size.x, water_size.y) / 128.0)
	var cnx := int(ceilf(water_size.x / cc)) + 1
	var cnz := int(ceilf(water_size.y / cc)) + 1
	var bb_min := Vector2(1e9, 1e9)
	var bb_max := Vector2(-1e9, -1e9)
	for iz in range(cnz):
		for ix in range(cnx):
			var lx := -water_size.x * 0.5 + ix * cc
			var lz := -water_size.y * 0.5 + iz * cc
			if _ray_is_land(space, exclude, lx, lz, surface_y):
				_shore_has_land = true
				bb_min = Vector2(minf(bb_min.x, lx), minf(bb_min.y, lz))
				bb_max = Vector2(maxf(bb_max.x, lx), maxf(bb_max.y, lz))
	
	if not _shore_has_land:
		return
	
	# PASS 2 - fine: scan only around the land (bbox + boundary + margin)
	# at high resolution. Everything outside this region is farther from
	# land than the boundary by construction.
	var margin := boundary_distance + cc + SHORE_CELL * 2.0
	var x0 := maxf(bb_min.x - margin, -water_size.x * 0.5)
	var z0 := maxf(bb_min.y - margin, -water_size.y * 0.5)
	var x1 := minf(bb_max.x + margin, water_size.x * 0.5)
	var z1 := minf(bb_max.y + margin, water_size.y * 0.5)
	_shore_cell = maxf(SHORE_CELL, maxf(x1 - x0, z1 - z0) / 400.0)
	_shore_ox = x0
	_shore_oz = z0
	_shore_nx = int(ceilf((x1 - x0) / _shore_cell)) + 1
	_shore_nz = int(ceilf((z1 - z0) / _shore_cell)) + 1
	_shore_dist.resize(_shore_nx * _shore_nz)
	for iz in range(_shore_nz):
		for ix in range(_shore_nx):
			var lx := x0 + ix * _shore_cell
			var lz := z0 + iz * _shore_cell
			_shore_dist[iz * _shore_nx + ix] = 0.0 if _ray_is_land(space, exclude, lx, lz, surface_y) else big
	
	# Two-pass chamfer distance transform (with diagonals)
	var d1 := _shore_cell
	var d2 := _shore_cell * 1.41421
	for iz in range(_shore_nz):
		for ix in range(_shore_nx):
			var i := iz * _shore_nx + ix
			var d := _shore_dist[i]
			if ix > 0: d = minf(d, _shore_dist[i - 1] + d1)
			if iz > 0: d = minf(d, _shore_dist[i - _shore_nx] + d1)
			if ix > 0 and iz > 0: d = minf(d, _shore_dist[i - _shore_nx - 1] + d2)
			if ix < _shore_nx - 1 and iz > 0: d = minf(d, _shore_dist[i - _shore_nx + 1] + d2)
			_shore_dist[i] = d
	for iz in range(_shore_nz - 1, -1, -1):
		for ix in range(_shore_nx - 1, -1, -1):
			var i := iz * _shore_nx + ix
			var d := _shore_dist[i]
			if ix < _shore_nx - 1: d = minf(d, _shore_dist[i + 1] + d1)
			if iz < _shore_nz - 1: d = minf(d, _shore_dist[i + _shore_nx] + d1)
			if ix < _shore_nx - 1 and iz < _shore_nz - 1: d = minf(d, _shore_dist[i + _shore_nx + 1] + d2)
			if ix > 0 and iz < _shore_nz - 1: d = minf(d, _shore_dist[i + _shore_nx - 1] + d2)
			_shore_dist[i] = d


func _ray_is_land(space: PhysicsDirectSpaceState3D, exclude: Array[RID], lx: float, lz: float, surface_y: float) -> bool:
	"""True if anything solid pokes up to the water surface at this local XZ."""
	var wp := to_global(Vector3(lx, 0, lz))
	var params := PhysicsRayQueryParameters3D.create(
		Vector3(wp.x, surface_y + 60.0, wp.z),
		Vector3(wp.x, surface_y - 0.6, wp.z))
	params.exclude = exclude
	var hit := space.intersect_ray(params)
	return not hit.is_empty() and hit.position.y >= surface_y - 0.35


func _shore_distance(world_pos: Vector3) -> float:
	"""Meters from world_pos to the nearest land edge. Positions outside the
	fine scan region are farther than the boundary by construction. Falls
	back to radial distance from the node origin when no land exists."""
	if not _shore_has_land or _shore_dist.is_empty():
		return Vector2(world_pos.x - global_position.x,
				world_pos.z - global_position.z).length()
	var local := to_local(world_pos)
	var gx := (local.x - _shore_ox) / _shore_cell
	var gz := (local.z - _shore_oz) / _shore_cell
	if gx < 0.0 or gz < 0.0 or gx > _shore_nx - 1 or gz > _shore_nz - 1:
		return 1e9   # Outside the scan region = deep shark territory
	var fx := clampf(gx, 0.0, _shore_nx - 1.001)
	var fz := clampf(gz, 0.0, _shore_nz - 1.001)
	var ix := int(fx); var iz := int(fz)
	var tx := fx - ix; var tz := fz - iz
	var i := iz * _shore_nx + ix
	return lerpf(
		lerpf(_shore_dist[i], _shore_dist[i + 1], tx),
		lerpf(_shore_dist[i + _shore_nx], _shore_dist[i + _shore_nx + 1], tx), tz)


# --- Buoys -----------------------------------------------------------------

func _spawn_buoys():
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	red.emission_enabled = true
	red.emission = Color(0.85, 0.1, 0.1)
	red.emission_energy_multiplier = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	
	# Buoy positions: the boundary_distance iso-line of the land-distance
	# field, thinned to roughly buoy_spacing apart. Fallback: radial ring.
	var points: Array[Vector2] = []
	if _shore_has_land and not _shore_dist.is_empty():
		var band := _shore_cell * 0.8
		var candidates: Array[Vector2] = []
		for iz in range(_shore_nz):
			for ix in range(_shore_nx):
				if absf(_shore_dist[iz * _shore_nx + ix] - boundary_distance) <= band:
					candidates.append(Vector2(
						_shore_ox + ix * _shore_cell,
						_shore_oz + iz * _shore_cell))
		for c in candidates:
			var ok := true
			for p in points:
				if c.distance_to(p) < buoy_spacing:
					ok = false
					break
			if ok:
				points.append(c)
	else:
		var r := boundary_distance
		var n := maxi(int(TAU * r / buoy_spacing), 8)
		for i in n:
			var ang := TAU * float(i) / n
			var lx := cos(ang) * r
			var lz := sin(ang) * r
			if absf(lx) > water_size.x * 0.5 or absf(lz) > water_size.y * 0.5:
				continue
			points.append(Vector2(lx, lz))
	
	for pt in points:
		var buoy := MeshInstance3D.new()
		# Low-poly buoy: red cone bottom + white band + red tip
		var body := CylinderMesh.new()
		body.top_radius = 0.18
		body.bottom_radius = 0.32
		body.height = 0.5
		body.radial_segments = 6
		buoy.mesh = body
		buoy.material_override = red
		var band_mi := MeshInstance3D.new()
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = 0.14
		band_mesh.bottom_radius = 0.18
		band_mesh.height = 0.22
		band_mesh.radial_segments = 6
		band_mi.mesh = band_mesh
		band_mi.material_override = white
		band_mi.position.y = 0.36
		buoy.add_child(band_mi)
		var tip := MeshInstance3D.new()
		var tip_mesh := CylinderMesh.new()
		tip_mesh.top_radius = 0.0
		tip_mesh.bottom_radius = 0.12
		tip_mesh.height = 0.25
		tip_mesh.radial_segments = 6
		tip.mesh = tip_mesh
		tip.material_override = red
		tip.position.y = 0.58
		buoy.add_child(tip)
		buoy.scale = Vector3.ONE * 1.2   # Chunky enough to read from shore
		buoy.position = Vector3(pt.x, 0.05, pt.y)
		_visuals.add_child(buoy)
		_buoys.append([buoy, randf() * TAU])


func _process(delta: float):
	_time += delta
	# Buoys bob on the surface
	for b in _buoys:
		if is_instance_valid(b[0]):
			b[0].position.y = 0.05 + sin(_time * 1.6 + b[1]) * 0.12
			b[0].rotation.z = sin(_time * 1.2 + b[1]) * 0.08
	
	if Engine.is_editor_hint():
		return
	
	# --- Shark update -------------------------------------------------------
	if _shark_phase != SharkPhase.NONE:
		_update_shark(delta)
		return
	
	# --- Boundary enforcement ----------------------------------------------
	if not boundary_enabled or not _shore_ready:
		return
	if _player == null or not is_instance_valid(_player):
		_warn_timer = 0.0
		return
	# Danger is judged HORIZONTALLY over the water: jumping out of the
	# water volume doesn't pause or reset the clock. Anywhere outside the
	# buoy line the timer runs - land or safe water are the only outs.
	if _player_in_danger():
		# Hidden grace period - no countdown on screen, the buoys ARE the
		# warning. Outstay it and the shark charges.
		_warn_timer += delta
		if _warn_timer >= warning_time:
			_warn_timer = 0.0
			_start_shark_charge()
	else:
		_warn_timer = 0.0


func _player_in_danger() -> bool:
	"""True when the player is past the buoy line, horizontally over this
	water - swimming, diving OR airborne above it. Jumping does not pause
	the timer. Land and water inside the line are safe. (Bridges/platforms
	above the surface register as land in the shore scan, so standing on
	them is safe through the shore-distance check, not a height check.)"""
	if _player == null or not is_instance_valid(_player):
		return false
	var local := to_local(_player.global_position)
	if absf(local.x) > water_size.x * 0.5 or absf(local.z) > water_size.y * 0.5:
		return false   # Not over this water at all
	return _shore_distance(_player.global_position) > boundary_distance


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player = body
		_player_inside = true
		if "current_water" in body:
			body.current_water = self


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_inside = false
		if "current_water" in body and body.current_water == self:
			body.current_water = null
		# NOTE: the warn timer is NOT reset here - hopping out of the water
		# volume (jump spam) must not shake the shark. The timer only resets
		# when _player_in_danger() goes false (back inside the line / on land).


# --- The shark ---------------------------------------------------------------

func _start_shark_charge():
	if _player == null or not is_instance_valid(_player):
		return
	_shark = _build_shark()
	add_child(_shark)
	
	# Start 14m past the player, directly away from land, fin up
	var out_dir := Vector3(_player.global_position.x - global_position.x, 0,
			_player.global_position.z - global_position.z).normalized()
	if out_dir.length() < 0.5:
		out_dir = Vector3.FORWARD
	var surface_y := global_position.y
	_shark.global_position = _player.global_position + out_dir * 14.0
	_shark.global_position.y = surface_y - 0.55
	_shark_phase = SharkPhase.CHARGE


func _update_shark(delta: float):
	if _shark == null or not is_instance_valid(_shark):
		_shark_phase = SharkPhase.NONE
		return
	var surface_y := global_position.y
	
	if _shark_phase == SharkPhase.CHARGE:
		if _player == null or not is_instance_valid(_player):
			_shark_break_off()
			return
		# MERCY RULE: make it back over the line (which includes standing on
		# land - land is distance 0) before the shark touches you and it
		# breaks off. Jumping over unsafe water does NOT count as safe.
		if not _player_in_danger():
			_shark_break_off()
			return
		var target := _player.global_position
		target.y = surface_y - 0.4
		var to_target := target - _shark.global_position
		# Horizontal chase/chomp: jumping doesn't help, the shark lunges up
		var dist := Vector2(_player.global_position.x - _shark.global_position.x,
				_player.global_position.z - _shark.global_position.z).length()
		if dist < 1.3:
			# CHOMP
			_player.velocity = Vector3.ZERO
			if _player.has_method("die"):
				_player.die()
			var dm = get_node_or_null("/root/DialogueManager")
			if dm and dm.has_method("bark"):
				dm.bark("HU3", "Told you. Sharks.", 2.5)
			_shark_leave_dir = to_target.normalized() if dist > 0.01 else Vector3.FORWARD
			_shark_phase = SharkPhase.LEAVE
			_shark_leave_t = 0.0
			return
		var step := to_target.normalized() * shark_speed * delta
		_shark.global_position += step
		_shark.look_at(target, Vector3.UP)
	
	elif _shark_phase == SharkPhase.LEAVE:
		# Dive away (with or without the meal)
		_shark_leave_t += delta
		_shark.global_position += _shark_leave_dir * shark_speed * 0.5 * delta
		_shark.global_position.y -= water_depth * 0.6 * delta
		if _shark_leave_t >= 1.4:
			_shark.queue_free()
			_shark = null
			_shark_phase = SharkPhase.NONE


func _shark_break_off():
	if _shark and is_instance_valid(_shark):
		_shark_leave_dir = -_shark.global_transform.basis.z
		_shark_leave_dir.y = 0.0
		if _shark_leave_dir.length() < 0.1:
			_shark_leave_dir = Vector3.FORWARD
		_shark_leave_dir = _shark_leave_dir.normalized()
		_shark_phase = SharkPhase.LEAVE
		_shark_leave_t = 0.0
	else:
		_shark_phase = SharkPhase.NONE


func _build_shark() -> Node3D:
	"""Low-poly shark: grey prism body, dorsal fin, tail fin."""
	var root := Node3D.new()
	root.name = "Shark"
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.35, 0.38, 0.42)
	grey.roughness = 0.7
	var belly := StandardMaterial3D.new()
	belly.albedo_color = Color(0.8, 0.8, 0.78)
	
	var body := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.45
	bm.height = 3.2
	bm.radial_segments = 8
	bm.rings = 4
	body.mesh = bm
	body.material_override = grey
	body.rotation_degrees.x = 90.0   # Long axis along -Z (forward)
	root.add_child(body)
	
	var fin := MeshInstance3D.new()
	var fm := PrismMesh.new()
	fm.size = Vector3(0.12, 0.75, 0.9)
	fin.mesh = fm
	fin.material_override = grey
	fin.position = Vector3(0, 0.75, 0.2)
	root.add_child(fin)
	
	var tail := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.1, 1.0, 0.6)
	tail.mesh = tm
	tail.material_override = grey
	tail.position = Vector3(0, 0.25, 1.7)
	root.add_child(tail)
	
	var jaw := MeshInstance3D.new()
	var jm := BoxMesh.new()
	jm.size = Vector3(0.5, 0.25, 0.5)
	jaw.mesh = jm
	jaw.material_override = belly
	jaw.position = Vector3(0, -0.25, -1.5)
	root.add_child(jaw)
	return root


func get_surface_height() -> float:
	return global_position.y
