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
##      cheap math) and creates ONE child Path3D called "BuoyLine": a
##      closed circle around the island, boundary_distance meters past
##      the land edge. Buoy meshes are placed automatically along the
##      curve every buoy_spacing meters - they are pure visuals, never
##      saved into your scene.
##   3. THE BUOYLINE IS THE BOUNDARY. INSIDE the loop = safe. OUTSIDE =
##      shark territory. Edit the BuoyLine like any Path3D: drag its
##      curve points to grow/shrink/reshape the circle, add points for
##      odd shapes. Buoys follow the curve instantly. It's only
##      regenerated if the BuoyLine child is missing, so your edits are
##      never overwritten (regenerate_buoys resets it).
##   4. Swim outside the loop and after a hidden grace period the shark
##      charges. Get back inside the loop (or onto land) before it
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
## DEFAULT distance of the generated buoy circle from the edge of land.
## Only used when generating the BuoyLine (no BuoyLine child yet).
@export var boundary_distance: float = 20.0
## Hidden grace period (seconds) past the buoys before the shark charges.
@export var warning_time: float = 2.0
## Shark charge speed in m/s.
@export var shark_speed: float = 18.1
## Meters between buoy visuals along the line.
@export var buoy_spacing: float = 4.0:
	set(v): buoy_spacing = maxf(v, 1.0); _queue_buoy_refresh()
@export var boundary_enabled: bool = true
## Tick to DELETE the BuoyLine and regenerate the default circle
## (throws away your edits).
@export var regenerate_buoys: bool = false:
	set(_v):
		regenerate_buoys = false
		if _buoy_line and is_instance_valid(_buoy_line):
			_buoy_line.free()
		_buoy_line = null
		_line_ready = false
		_line_dirty = true
		_scan_wait = 2
		_scan_attempts = 0

@export_group("Diving")
## Seconds of air when fully submerged. Refills fast at the surface.
@export var oxygen_seconds: float = 12.0

var _visuals: Node3D = null
var _buoy_holder: Node3D = null
var _buoys: Array[Node3D] = []
var _buoy_phases: PackedFloat32Array = PackedFloat32Array()
var _col: CollisionShape3D = null
var _player: CharacterBody3D = null
var _player_inside := false
var _warn_timer := 0.0
var _time := 0.0

# Boundary state
var _buoy_line: Path3D = null
var _line_ready := false
var _buoy_refresh_queued := false
var _ring_cache: PackedVector2Array = PackedVector2Array()   # Local XZ loop
var _ring_cache_frame := -1

# Land scan (generation only - runtime checks are analytic/polygon)
var _line_dirty := true
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
	_buoy_holder = null
	_buoys.clear()
	
	# Adopt an existing BuoyLine (user-edited) or schedule generation
	_buoy_line = get_node_or_null("BuoyLine") as Path3D
	_line_ready = _buoy_line != null and _buoy_line.curve != null \
			and _buoy_line.curve.point_count >= 3
	if _line_ready:
		_watch_curve()
		_spawn_buoy_visuals()
	else:
		_line_dirty = true
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


# --- Land detection --------------------------------------------------------
# CHEAP-FIRST: Terrain nodes answer "is there land here?" with pure math
# (height grid sampling). Raycasts are a fallback for non-Terrain solids
# and only run during BuoyLine GENERATION on a coarse grid - runtime
# boundary checks never raycast at all.

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
	if not _line_dirty or not is_inside_tree() or _line_ready:
		return
	if _scan_wait > 0:
		_scan_wait -= 1   # Give Terrain time to build its height grid
		return
	_line_dirty = false
	if _generate_buoy_line():
		_line_ready = true
	elif _scan_attempts < 20:
		_scan_attempts += 1
		_line_dirty = true
		_scan_wait = 10


func _generate_buoy_line() -> bool:
	"""Create the default BuoyLine: ONE Path3D child with a closed CIRCLE
	curve around the island - centered on the land centroid, radius = the
	farthest land point + boundary_distance. Inside the circle is safe;
	outside is shark territory. Edit the curve points to reshape it."""
	# Coarse land scan (analytic terrain sampling; raycasts only if no Terrain)
	var world := get_world_3d()
	if world == null:
		return false
	var use_ray := get_tree().get_nodes_in_group("Terrain").is_empty()
	var space := world.direct_space_state if use_ray else null
	var cell := maxf(3.0, maxf(water_size.x, water_size.y) / 64.0)
	var nx := int(ceilf(water_size.x / cell)) + 1
	var nz := int(ceilf(water_size.y / cell)) + 1
	var centroid := Vector2.ZERO
	var land_pts: Array[Vector2] = []
	for iz in range(nz):
		for ix in range(nx):
			var lx := -water_size.x * 0.5 + ix * cell
			var lz := -water_size.y * 0.5 + iz * cell
			if _is_land(to_global(Vector3(lx, 0, lz)), space):
				var p := Vector2(lx, lz)
				land_pts.append(p)
				centroid += p
	if land_pts.is_empty():
		return false
	centroid /= land_pts.size()
	var radius := 0.0
	for p in land_pts:
		radius = maxf(radius, centroid.distance_to(p))
	radius += boundary_distance
	# Keep the circle inside the water rect (with a small margin)
	var max_r: float = minf(
		minf(water_size.x * 0.5 - absf(centroid.x), water_size.x * 0.5 + absf(centroid.x)),
		minf(water_size.y * 0.5 - absf(centroid.y), water_size.y * 0.5 + absf(centroid.y))) - 2.0
	if max_r > 8.0:
		radius = minf(radius, max_r)
	
	# Build the closed circle curve: 8 points with bezier handles
	var curve := Curve3D.new()
	var n := 8
	var handle := (4.0 / 3.0) * tan(PI / (2.0 * n)) * radius
	for i in range(n):
		var a := TAU * i / n
		var pos := Vector3(centroid.x + cos(a) * radius, 0, centroid.y + sin(a) * radius)
		var tangent := Vector3(-sin(a), 0, cos(a)) * handle
		curve.add_point(pos, -tangent, tangent)
	curve.closed = true
	
	_buoy_line = Path3D.new()
	_buoy_line.name = "BuoyLine"
	_buoy_line.curve = curve
	add_child(_buoy_line)
	if Engine.is_editor_hint() and get_tree().edited_scene_root:
		_buoy_line.owner = get_tree().edited_scene_root   # ONE saved node
	_watch_curve()
	_spawn_buoy_visuals()
	return true


func _watch_curve():
	"""Refresh buoy visuals live while the curve is edited."""
	if _buoy_line and _buoy_line.curve \
			and not _buoy_line.curve.changed.is_connected(_queue_buoy_refresh):
		_buoy_line.curve.changed.connect(_queue_buoy_refresh)


func _queue_buoy_refresh():
	if _buoy_refresh_queued or not is_inside_tree():
		return
	_buoy_refresh_queued = true
	call_deferred("_do_buoy_refresh")


func _do_buoy_refresh():
	_buoy_refresh_queued = false
	if _line_ready:
		_spawn_buoy_visuals()


func _spawn_buoy_visuals():
	"""Place buoy meshes along the BuoyLine every buoy_spacing meters.
	Pure visuals under _visuals - NEVER saved to the scene, so they can't
	duplicate. Buoys sit on the water surface (this node's Y)."""
	if _buoy_holder and is_instance_valid(_buoy_holder):
		_buoy_holder.free()
	_buoys.clear()
	_buoy_phases = PackedFloat32Array()
	if _visuals == null or not is_instance_valid(_visuals) \
			or _buoy_line == null or not is_instance_valid(_buoy_line) \
			or _buoy_line.curve == null:
		return
	_buoy_holder = Node3D.new()
	_visuals.add_child(_buoy_holder)
	var curve := _buoy_line.curve
	var length := curve.get_baked_length()
	if length < 1.0:
		return
	var count := maxi(int(length / buoy_spacing), 3)
	for i in range(count):
		var p := curve.sample_baked(length * float(i) / count, true)
		p = _buoy_line.transform * p   # BuoyLine local -> WaterZone local
		var buoy := _build_buoy_mesh()
		_buoy_holder.add_child(buoy)
		buoy.position = Vector3(p.x, 0.0, p.z)   # Always on the surface
		_buoys.append(buoy)
		_buoy_phases.append(randf() * TAU)


func _build_buoy_mesh() -> Node3D:
	var root := Node3D.new()
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	red.emission_enabled = true
	red.emission = Color(0.85, 0.1, 0.1)
	red.emission_energy_multiplier = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.18
	bm.bottom_radius = 0.32
	bm.height = 0.5
	bm.radial_segments = 6
	body.mesh = bm
	body.material_override = red
	root.add_child(body)
	
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.14
	band_mesh.bottom_radius = 0.18
	band_mesh.height = 0.22
	band_mesh.radial_segments = 6
	band.mesh = band_mesh
	band.material_override = white
	band.position.y = 0.36
	root.add_child(band)
	
	var tip := MeshInstance3D.new()
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = 0.12
	tip_mesh.height = 0.25
	tip_mesh.radial_segments = 6
	tip.mesh = tip_mesh
	tip.material_override = red
	tip.position.y = 0.58
	root.add_child(tip)
	
	root.scale = Vector3.ONE * 1.2
	return root


# --- Boundary: the BuoyLine loop is the safe zone ---------------------------

func _buoy_ring() -> PackedVector2Array:
	"""Local-space XZ polygon sampled from the BuoyLine curve.
	Cached per frame - editing the curve updates it live."""
	var frame := Engine.get_process_frames()
	if frame == _ring_cache_frame:
		return _ring_cache
	_ring_cache_frame = frame
	var pts := PackedVector2Array()
	if _buoy_line and is_instance_valid(_buoy_line) and _buoy_line.curve:
		var curve := _buoy_line.curve
		var length := curve.get_baked_length()
		if length > 1.0:
			var n := clampi(int(length / 2.0), 12, 256)
			for i in range(n):
				var p := curve.sample_baked(length * float(i) / n, true)
				p = _buoy_line.transform * p
				pts.append(Vector2(p.x, p.z))
	_ring_cache = pts
	return pts


func _inside_ring(world_pos: Vector3) -> bool:
	var ring := _buoy_ring()
	if ring.size() < 3:
		return true   # No usable loop: everything is safe
	var local := to_local(world_pos)
	return Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), ring)


func _player_in_danger() -> bool:
	"""True when the player is outside the BuoyLine loop, horizontally over
	this water - swimming, diving OR airborne above it. Jumping does not
	pause the timer. Inside the loop or on land = safe."""
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
	# Buoy bobbing
	for i in range(_buoys.size()):
		var b := _buoys[i]
		if is_instance_valid(b):
			b.position.y = 0.05 + sin(_time * 1.6 + _buoy_phases[i]) * 0.12
			b.rotation.z = sin(_time * 1.2 + _buoy_phases[i]) * 0.08
	if Engine.is_editor_hint():
		return
	
	# --- Shark update -------------------------------------------------------
	if _shark_phase != SharkPhase.NONE:
		_update_shark(delta)
		return
	
	# --- Boundary enforcement ----------------------------------------------
	if not boundary_enabled or not _line_ready:
		return
	if _player == null or not is_instance_valid(_player):
		_warn_timer = 0.0
		return
	# Danger is judged HORIZONTALLY over the water: jumping out of the
	# water volume doesn't pause or reset the clock. Anywhere outside the
	# buoy loop the timer runs - land or safe water are the only outs.
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
		# when _player_in_danger() goes false (back inside the loop/on land).


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
		# MERCY RULE: make it back inside the loop (or onto land) before the
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
