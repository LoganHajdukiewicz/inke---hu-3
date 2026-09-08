@tool
extends Area3D
class_name WaterZone
## WATER. Not a gameplay focus - it's the soft edge of the world. Swim on
## the surface, dive under (oxygen drains, drown at zero), and DON'T cross
## the buoy line: past the boundary you get warning_time seconds to turn
## back before a shark eats you.
##
## HOW TO USE:
##   1. Add a WaterZone where the world should end (beach, harbor, docks).
##      The node's Y is the water surface height.
##   2. Size the water with water_size / water_depth.
##   3. boundary_distance (default 20m out from the node) is where the
##      line of buoys floats. All configurable, all live in the editor.
##
## The player is detected automatically (Area3D). SwimmingState handles
## the actual swimming; this node owns water visuals, buoys, the boundary
## countdown and the shark.

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
## Swimmers past this distance (meters, from this node's origin) are in
## shark territory. Marked by the buoy line.
@export var boundary_distance: float = 20.0:
	set(v): boundary_distance = maxf(v, 3.0); _request_rebuild()
## Seconds past the buoys before the shark takes you.
@export var warning_time: float = 2.0
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
var _warning_active := false
var _shark_busy := false
var _warn_ui: CanvasLayer = null
var _warn_label: Label = null
var _time := 0.0


func _ready():
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
	
	# --- Buoy line ----------------------------------------------------------
	if boundary_enabled:
		_spawn_buoys()


func _spawn_buoys():
	var r := boundary_distance
	var n := maxi(int(TAU * r / buoy_spacing), 8)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.1, 0.1)
	red.emission_enabled = true
	red.emission = Color(0.85, 0.1, 0.1)
	red.emission_energy_multiplier = 0.35
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.92, 0.92, 0.9)
	for i in n:
		var ang := TAU * float(i) / n
		var lx := cos(ang) * r
		var lz := sin(ang) * r
		# Only where there's water
		if absf(lx) > water_size.x * 0.5 or absf(lz) > water_size.y * 0.5:
			continue
		var buoy := MeshInstance3D.new()
		# Low-poly buoy: red cone bottom + white band + red tip
		var body := CylinderMesh.new()
		body.top_radius = 0.18
		body.bottom_radius = 0.32
		body.height = 0.5
		body.radial_segments = 6
		buoy.mesh = body
		buoy.material_override = red
		var band := MeshInstance3D.new()
		var band_mesh := CylinderMesh.new()
		band_mesh.top_radius = 0.14
		band_mesh.bottom_radius = 0.18
		band_mesh.height = 0.22
		band_mesh.radial_segments = 6
		band.mesh = band_mesh
		band.material_override = white
		band.position.y = 0.36
		buoy.add_child(band)
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
		buoy.position = Vector3(lx, 0.05, lz)
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
	
	# --- Boundary enforcement ----------------------------------------------
	if not boundary_enabled or _shark_busy:
		return
	if not _player_inside or _player == null or not is_instance_valid(_player):
		_cancel_warning()
		return
	var d := Vector2(_player.global_position.x - global_position.x,
			_player.global_position.z - global_position.z).length()
	if d > boundary_distance:
		if not _warning_active:
			_warning_active = true
			_warn_timer = warning_time
			_show_warning()
			var dm = get_node_or_null("/root/DialogueManager")
			if dm and dm.has_method("bark"):
				dm.bark("HU3", "TURN BACK! Shark territory!", warning_time)
		_warn_timer -= delta
		if _warn_label:
			_warn_label.text = "TURN BACK!  %.1f" % maxf(_warn_timer, 0.0)
			_warn_label.visible = fmod(_time, 0.4) < 0.28
		if _warn_timer <= 0.0:
			_cancel_warning()
			_shark_attack()
	else:
		_cancel_warning()


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
		_cancel_warning()


# --- Warning UI --------------------------------------------------------------

func _show_warning():
	if _warn_ui and is_instance_valid(_warn_ui):
		_warn_ui.visible = true
		return
	_warn_ui = CanvasLayer.new()
	_warn_ui.layer = 90
	_warn_label = Label.new()
	_warn_label.text = "TURN BACK!"
	_warn_label.add_theme_font_size_override("font_size", 52)
	_warn_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.1))
	_warn_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_warn_label.add_theme_constant_override("shadow_offset_x", 4)
	_warn_label.add_theme_constant_override("shadow_offset_y", 4)
	_warn_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_warn_label.position.y = 90
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_ui.add_child(_warn_label)
	add_child(_warn_ui)


func _cancel_warning():
	_warning_active = false
	if _warn_ui and is_instance_valid(_warn_ui):
		_warn_ui.visible = false


# --- The shark ---------------------------------------------------------------

func _shark_attack():
	if _shark_busy or _player == null or not is_instance_valid(_player):
		return
	_shark_busy = true
	var shark := _build_shark()
	add_child(shark)
	
	# Start 14m past the player, directly away from the island, fin up
	var out_dir := Vector3(_player.global_position.x - global_position.x, 0,
			_player.global_position.z - global_position.z).normalized()
	if out_dir.length() < 0.5:
		out_dir = Vector3.FORWARD
	var surface_y := global_position.y
	shark.global_position = _player.global_position + out_dir * 14.0
	shark.global_position.y = surface_y - 0.55
	shark.look_at(Vector3(_player.global_position.x, surface_y - 0.55, _player.global_position.z), Vector3.UP)
	
	var tw := create_tween()
	# Race in
	var target := _player.global_position
	target.y = surface_y - 0.4
	tw.tween_property(shark, "global_position", target, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		# CHOMP
		if _player and is_instance_valid(_player):
			_player.velocity = Vector3.ZERO
			if _player.has_method("die"):
				_player.die()
		var dm = get_node_or_null("/root/DialogueManager")
		if dm and dm.has_method("bark"):
			dm.bark("HU3", "Told you. Sharks.", 2.5)
	)
	# Dive away with the meal
	tw.tween_property(shark, "global_position", target + out_dir * 8.0 + Vector3(0, -water_depth * 0.7, 0), 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		if is_instance_valid(shark):
			shark.queue_free()
		_shark_busy = false
	)


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
