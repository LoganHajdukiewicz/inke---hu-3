@tool
extends Area3D
class_name WaterZone
## WATER. Not a gameplay focus - it's the soft edge of the world. Swim on
## the surface, dive under (oxygen drains, drowning damage at zero), and
## don't stray past the buoy line: a shark enforces it.
##
## HOW TO USE:
##   1. Add a WaterZone where the world should end. The node's Y is the
##      water surface height. Size with water_size / water_depth.
##   2. On first build the zone finds LAND (Terrain height sampling -
##      cheap math, no raycasts; other solid bodies via a coarse raycast
##      grid) and spawns a ring of BuoyPoint children boundary_distance
##      meters (default 20) out from the land edge.
##   3. THE BUOYS ARE THE BOUNDARY. Drag any BuoyPoint in the editor to
##      reshape shark territory however you want - block off a lagoon,
##      pull the line tight around a cliff, anything. Add/remove
##      BuoyPoints freely (keep ring order in the scene tree). Buoys are
##      only regenerated if the zone has NO BuoyPoint children, so your
##      dragged layout is never overwritten.
##   4. Swim outside the buoy ring and after a hidden grace period the
##      shark charges. Get back inside the ring (or onto land) before it
##      reaches you and it breaks off. Jumping doesn't save you.
##
## The player is detected automatically (Area3D). SwimmingState handles
## the actual swimming; this node owns water visuals, the boundary and
## the shark.

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
## DEFAULT distance of the generated buoy ring from the edge of land.
## Only used when generating buoys (zone has no BuoyPoint children yet).
@export var boundary_distance: float = 20.0
## Hidden grace period (seconds) past the buoys before the shark charges.
@export var warning_time: float = 2.0
## Shark charge speed in m/s.
@export var shark_speed: float = 18.1
## Meters between generated buoys along the ring.
@export var buoy_spacing: float = 4.0
@export var boundary_enabled: bool = true
## Tick to DELETE all BuoyPoint children and regenerate the default ring
## (throws away your dragged layout).
@export var regenerate_buoys: bool = false:
	set(_v):
		regenerate_buoys = false
		for c in get_children():
			if c is BuoyPoint:
				c.free()
		_buoys_built = false
		_shore_dirty = true
		_scan_wait = 2

@export_group("Diving")
## Seconds of air when fully submerged. Refills fast at the surface.
@export var oxygen_seconds: float = 12.0

var _visuals: Node3D = null
var _col: CollisionShape3D = null
var _player: CharacterBody3D = null
var _player_inside := false
var _warn_timer := 0.0
var _time := 0.0

# Boundary state
var _buoys_built := false
var _ring_cache: PackedVector2Array = PackedVector2Array()   # Local XZ ring
var _ring_cache_frame := -1

# Land scan (generation only - runtime checks are analytic/polygon)
var _shore_dirty := true
var _scan_wait := 3
var _scan_attempts := 0

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
	# Buoys: only (re)generated when there are none (dragged layouts kept)
	_buoys_built = _has_buoy_children()
	if not _buoys_built:
		_shore_dirty = true
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


func _has_buoy_children() -> bool:
	for c in get_children():
		if c is BuoyPoint:
			return true
	return false


# --- Land detection --------------------------------------------------------
# CHEAP-FIRST: Terrain nodes answer "is there land here?" with pure math
# (height grid sampling). Raycasts are a fallback for non-Terrain solids
# (docks, big platforms) and only run during buoy GENERATION on a coarse
# grid - runtime boundary checks never raycast at all.

func _is_land(world_pos: Vector3, space: PhysicsDirectSpaceState3D = null) -> bool:
	var surface_y := global_position.y
	for t in get_tree().get_nodes_in_group("Terrain"):
		if t.has_method("get_height") and t.contains_xz(world_pos):
			if t.get_height(world_pos) >= surface_y - 0.35:
				return true
	if space != null:
		var params := PhysicsRayQueryParameters3D.create(
			Vector3(world_pos.x, surface_y + 60.0, world_pos.z),
			Vector3(world_pos.x, surface_y - 0.6, world_pos.z))
		var hit := space.intersect_ray(params)
		return not hit.is_empty() and hit.position.y >= surface_y - 0.35
	return false


func _physics_process(_delta: float):
	if not _shore_dirty or not is_inside_tree() or _buoys_built:
		_shore_dirty = false if _buoys_built else _shore_dirty
		return
	if _scan_wait > 0:
		_scan_wait -= 1   # Give Terrain time to build its height grid
		return
	_shore_dirty = false
	if _generate_buoys():
		_buoys_built = true
	elif _scan_attempts < 20:
		_scan_attempts += 1
		_shore_dirty = true
		_scan_wait = 10


func _generate_buoys() -> bool:
	"""Build the DEFAULT buoy ring: a coarse land-distance field (analytic
	terrain sampling + coarse fallback raycasts), then the boundary_distance
	iso-line ordered by angle around the land centroid. Spawns BuoyPoint
	children - draggable, persistent, yours to reshape."""
	var world := get_world_3d()
	if world == null:
		return false
	var space := world.direct_space_state
	
	# Coarse scan: cell size scales with the water so huge oceans stay cheap
	var cell := maxf(3.0, maxf(water_size.x, water_size.y) / 96.0)
	var nx := int(ceilf(water_size.x / cell)) + 1
	var nz := int(ceilf(water_size.y / cell)) + 1
	var dist := PackedFloat32Array()
	dist.resize(nx * nz)
	var big := 1e9
	var found := false
	var centroid := Vector2.ZERO
	var land_n := 0
	var use_ray := get_tree().get_nodes_in_group("Terrain").is_empty()
	for iz in range(nz):
		for ix in range(nx):
			var lx := -water_size.x * 0.5 + ix * cell
			var lz := -water_size.y * 0.5 + iz * cell
			var wp := to_global(Vector3(lx, 0, lz))
			var land := _is_land(wp, space if use_ray else null)
			dist[iz * nx + ix] = 0.0 if land else big
			if land:
				found = true
				centroid += Vector2(lx, lz)
				land_n += 1
	if not found:
		return false
	centroid /= land_n
	
	# Chamfer distance transform
	var d1 := cell
	var d2 := cell * 1.41421
	for iz in range(nz):
		for ix in range(nx):
			var i := iz * nx + ix
			var d := dist[i]
			if ix > 0: d = minf(d, dist[i - 1] + d1)
			if iz > 0: d = minf(d, dist[i - nx] + d1)
			if ix > 0 and iz > 0: d = minf(d, dist[i - nx - 1] + d2)
			if ix < nx - 1 and iz > 0: d = minf(d, dist[i - nx + 1] + d2)
			dist[i] = d
	for iz in range(nz - 1, -1, -1):
		for ix in range(nx - 1, -1, -1):
			var i := iz * nx + ix
			var d := dist[i]
			if ix < nx - 1: d = minf(d, dist[i + 1] + d1)
			if iz < nz - 1: d = minf(d, dist[i + nx] + d1)
			if ix < nx - 1 and iz < nz - 1: d = minf(d, dist[i + nx + 1] + d2)
			if ix > 0 and iz < nz - 1: d = minf(d, dist[i + nx - 1] + d2)
			dist[i] = d
	
	# Iso-line candidates -> angle-sorted ring -> thin to buoy_spacing
	var candidates: Array = []   # [angle, Vector2]
	var band := cell * 0.75
	for iz in range(nz):
		for ix in range(nx):
			if absf(dist[iz * nx + ix] - boundary_distance) <= band:
				var p := Vector2(-water_size.x * 0.5 + ix * cell, -water_size.y * 0.5 + iz * cell)
				candidates.append([atan2(p.y - centroid.y, p.x - centroid.x), p])
	if candidates.is_empty():
		return false
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var ring: Array[Vector2] = []
	for c in candidates:
		var p: Vector2 = c[1]
		if ring.is_empty() or p.distance_to(ring[ring.size() - 1]) >= buoy_spacing:
			ring.append(p)
	if ring.size() >= 2 and ring[0].distance_to(ring[ring.size() - 1]) < buoy_spacing * 0.5:
		ring.remove_at(ring.size() - 1)
	if ring.size() < 3:
		return false
	
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var idx := 0
	for p in ring:
		var buoy := BuoyPoint.new()
		buoy.name = "BuoyPoint%d" % idx
		add_child(buoy)
		buoy.position = Vector3(p.x, 0.0, p.y)
		if scene_root:
			buoy.owner = scene_root   # Saves with the scene = draggable forever
		idx += 1
	return true


# --- Boundary: the buoy ring is a polygon --------------------------------

func _buoy_ring() -> PackedVector2Array:
	"""Local-space XZ polygon from BuoyPoint children (scene tree order).
	Cached per frame - dragging buoys updates it live."""
	var frame := Engine.get_process_frames()
	if frame == _ring_cache_frame:
		return _ring_cache
	_ring_cache_frame = frame
	var pts := PackedVector2Array()
	for c in get_children():
		if c is BuoyPoint:
			pts.append(Vector2(c.position.x, c.position.z))
	_ring_cache = pts
	return pts


func _inside_ring(world_pos: Vector3) -> bool:
	var ring := _buoy_ring()
	if ring.size() < 3:
		return true   # No usable ring: everything is safe
	var local := to_local(world_pos)
	return Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), ring)


func _player_in_danger() -> bool:
	"""True when the player is outside the buoy ring, horizontally over
	this water - swimming, diving OR airborne above it. Jumping does not
	pause the timer. Inside the ring or on land = safe."""
	if _player == null or not is_instance_valid(_player):
		return false
	var local := to_local(_player.global_position)
	if absf(local.x) > water_size.x * 0.5 or absf(local.z) > water_size.y * 0.5:
		return false   # Not over this water at all
	if _inside_ring(_player.global_position):
		return false
	if _is_land(_player.global_position):
		return false
	return true


func _process(delta: float):
	_time += delta
	if Engine.is_editor_hint():
		return
	
	# --- Shark update -------------------------------------------------------
	if _shark_phase != SharkPhase.NONE:
		_update_shark(delta)
		return
	
	# --- Boundary enforcement ----------------------------------------------
	if not boundary_enabled or not _buoys_built:
		return
	if _player == null or not is_instance_valid(_player):
		_warn_timer = 0.0
		return
	# Danger is judged HORIZONTALLY over the water: jumping out of the
	# water volume doesn't pause or reset the clock. Anywhere outside the
	# buoy ring the timer runs - land or safe water are the only outs.
	if _player_in_danger():
		# Hidden grace period - no countdown on screen, the buoys ARE the
		# warning. Outstay it and the shark charges.
		_warn_timer += delta
		if _warn_timer >= warning_time:
			_warn_timer = 0.0
			_start_shark_charge()
	else:
		_warn_timer = 0.0


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
		# when _player_in_danger() goes false (back inside the ring/on land).


# --- The shark ---------------------------------------------------------------

func _start_shark_charge():
	if _player == null or not is_instance_valid(_player):
		return
	_shark = _build_shark()
	add_child(_shark)
	
	# Start 14m past the player, directly away from the zone center, fin up
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
		# MERCY RULE: make it back inside the ring (or onto land) before the
		# shark touches you and it breaks off. Jumping over unsafe water
		# does NOT count as safe.
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
			_shark_leave_dir = to_target.normalized() if to_target.length() > 0.01 else Vector3.FORWARD
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
