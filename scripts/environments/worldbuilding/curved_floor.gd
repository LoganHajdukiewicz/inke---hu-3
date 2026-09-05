@tool
extends Path3D
class_name CurvedFloor
## A floor that FOLLOWS A PATH - draw a curve, get a ribbon of floor bent
## along it. Built for slides: set floor_type to SLIDING, drop points that
## descend, and you have a fun swooping slide in seconds. Works for any
## floor type though (NORMAL for curvy walkways, FROZEN for ice chutes...).
##
## HOW TO USE
##   1. Add a CurvedFloor node (it's a Path3D with presets).
##   2. Pick a curve_preset (Straight/S-Curve/Spiral/Helix Drop) or select
##      the node and edit the curve points by hand in the viewport - the
##      floor rebuilds live either way.
##   3. Tune width / thickness / banking, pick the floor_type.
##
## The mesh is extruded along the curve with smooth normals; collision is
## a series of convex slabs (one per segment) so physics matches the bend.
## SLIDING behavior: players on it are captured into SlidingState exactly
## like a SLIDING Floor - downhill comes from the local surface tilt, so
## the slide follows your curve.

enum FloorKind { NORMAL, SLIDING, FROZEN }
enum CurvePreset { CUSTOM, STRAIGHT, S_CURVE, SPIRAL_DOWN, BIG_DROP }

## What standing on this floor does. SLIDING = forced slide (the fun one).
@export var floor_kind: FloorKind = FloorKind.SLIDING:
	set(v): floor_kind = v; _request_rebuild()

## Generate a starter curve. Switch to CUSTOM (or just drag points) to
## hand-shape it - presets only stamp the points once when selected.
@export var curve_preset: CurvePreset = CurvePreset.CUSTOM:
	set(v):
		curve_preset = v
		if v != CurvePreset.CUSTOM:
			_stamp_preset(v)
		_request_rebuild()

@export_group("Shape")
## Width of the floor ribbon.
@export var width: float = 4.0:
	set(v): width = v; _request_rebuild()
@export var thickness: float = 0.5:
	set(v): thickness = v; _request_rebuild()
## Raised side lips (great for slides - keeps players in the chute).
@export var lip_height: float = 0.6:
	set(v): lip_height = v; _request_rebuild()
## Bank (tilt) into turns, like a bobsled track. 0 = flat, 1 = strong.
@export_range(0.0, 1.0) var banking: float = 0.4:
	set(v): banking = v; _request_rebuild()
## Segments per meter of curve (higher = smoother, heavier).
@export_range(0.5, 8.0) var resolution: float = 2.0:
	set(v): resolution = v; _request_rebuild()

@export_group("Slide Tuning")
@export var slide_max_speed: float = 30.0
@export var slide_acceleration: float = 25.0
@export var slide_steering_strength: float = 6.0

@export_group("Colors")
@export var floor_color: Color = Color(0.9, 0.9, 0.4):
	set(v): floor_color = v; _request_rebuild()
@export var lip_color: Color = Color(0.75, 0.72, 0.3):
	set(v): lip_color = v; _request_rebuild()

var _body: StaticBody3D
var _mesh: MeshInstance3D
var _rebuild_queued := false
var _capture_timer := 0.0

# States the slide capture must not interrupt (matches SlidingFloor)
const AIRBORNE_STATES := [
	"JumpingState", "DoubleJumpState", "FallingState", "WallJumpingState",
	"GrappleHookState", "DodgeDashState", "SpinAttackState",
]


func _ready():
	if curve == null or curve.point_count < 2:
		_stamp_preset(CurvePreset.STRAIGHT)
	curve_changed.connect(_request_rebuild)
	_request_rebuild()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or floor_kind != FloorKind.SLIDING:
		return
	# Capture players standing on this slide into SlidingState (10x/s poll)
	_capture_timer -= delta
	if _capture_timer > 0.0:
		return
	_capture_timer = 0.1
	for p in get_tree().get_nodes_in_group("Player"):
		if not p.is_on_floor():
			continue
		var sm = p.get_node_or_null("StateMachine")
		if sm == null or sm.current_state == null:
			continue
		var st: String = sm.current_state.get_script().get_global_name()
		if st in AIRBORNE_STATES or st == "SlidingState":
			continue
		if _is_standing_on_me(p):
			sm.change_state("SlidingState")


func _is_standing_on_me(p) -> bool:
	var space = p.get_world_3d().direct_space_state
	var q = PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 0.1, 0), p.global_position + Vector3(0, -1.2, 0))
	q.collision_mask = 1
	q.exclude = [p]
	var hit = space.intersect_ray(q)
	return hit and hit.collider == _body


## Duck-typing shims so SlidingState/Inke treat us like a SLIDING Floor.
func has_floor_type(t: int) -> bool:
	match floor_kind:
		FloorKind.SLIDING: return t == 7    # Floor.FloorType.SLIDING
		FloorKind.FROZEN:  return t == 6    # Floor.FloorType.FROZEN
		_:                 return t == 0


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------
func _stamp_preset(preset: CurvePreset) -> void:
	var c := Curve3D.new()
	match preset:
		CurvePreset.STRAIGHT:
			c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 5))
			c.add_point(Vector3(0, -6, 30), Vector3(0, 0, -5), Vector3.ZERO)
		CurvePreset.S_CURVE:
			c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, 0, 6))
			c.add_point(Vector3(10, -5, 15), Vector3(-6, 0, -3), Vector3(6, 0, 3))
			c.add_point(Vector3(-8, -10, 30), Vector3(6, 0, -3), Vector3(-6, 0, 3))
			c.add_point(Vector3(0, -14, 42), Vector3(0, 0, -5), Vector3.ZERO)
		CurvePreset.SPIRAL_DOWN:
			var turns := 2.0
			var pts := 9
			for i in range(pts):
				var t := float(i) / (pts - 1)
				var ang := t * TAU * turns
				var r := 10.0
				var pos := Vector3(cos(ang) * r, -t * 16.0, sin(ang) * r)
				var tangent := Vector3(-sin(ang), -16.0 / (TAU * turns * r), cos(ang)).normalized() * 4.0
				c.add_point(pos, -tangent, tangent)
		CurvePreset.BIG_DROP:
			c.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(0, -1, 6))
			c.add_point(Vector3(0, -12, 16), Vector3(0, 4, -5), Vector3(0, -4, 5))
			c.add_point(Vector3(0, -15, 34), Vector3(0, 0, -7), Vector3.ZERO)
	curve = c


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree() or curve == null or curve.point_count < 2:
		return
	if _body and is_instance_valid(_body):
		_body.free()
	_body = null
	
	var length := curve.get_baked_length()
	if length < 0.5:
		return
	var steps: int = maxi(int(length * resolution), 2)
	
	# Sample frames along the curve: position + banked basis
	var frames: Array = []
	for i in range(steps + 1):
		var d := (float(i) / steps) * length
		var pos := curve.sample_baked(d)
		var ahead := curve.sample_baked(minf(d + 0.3, length))
		var behind := curve.sample_baked(maxf(d - 0.3, 0.0))
		var fwd := (ahead - behind)
		if fwd.length() < 0.001:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		# Banking: tilt the side axis toward the turn (compare fwd ahead/behind)
		var up := side.cross(fwd).normalized()
		if banking > 0.01 and i > 0 and i < steps:
			var d2 := minf(d + 1.5, length)
			var fwd2 := (curve.sample_baked(minf(d2 + 0.3, length)) - curve.sample_baked(maxf(d2 - 0.3, 0.0))).normalized()
			var turn := fwd.cross(fwd2).y   # + = turning left
			var bank_angle: float = clampf(turn * 3.0, -1.0, 1.0) * banking * 0.6
			side = side.rotated(fwd, bank_angle)
			up = side.cross(fwd).normalized()
		frames.append({"pos": pos, "fwd": fwd, "side": side, "up": up})
	
	_body = StaticBody3D.new()
	_body.name = "CurvedFloorBody"
	add_child(_body)
	
	# --- Visual mesh: deck ribbon + lips, smooth normals ---
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	for i in range(steps):
		var a: Dictionary = frames[i]
		var b: Dictionary = frames[i + 1]
		# Deck top
		_quad(st, a.pos - a.side * hw, a.pos + a.side * hw, b.pos + b.side * hw, b.pos - b.side * hw)
		# Deck bottom
		var ao: Vector3 = a.up * -thickness
		var bo: Vector3 = b.up * -thickness
		_quad(st, a.pos + a.side * hw + ao, a.pos - a.side * hw + ao, b.pos - b.side * hw + bo, b.pos + b.side * hw + bo)
		# Deck sides
		_quad(st, a.pos - a.side * hw + ao, a.pos - a.side * hw, b.pos - b.side * hw, b.pos - b.side * hw + bo)
		_quad(st, a.pos + a.side * hw, a.pos + a.side * hw + ao, b.pos + b.side * hw + bo, b.pos + b.side * hw)
	st.generate_normals()
	var deck_mesh := st.commit()
	
	_mesh = MeshInstance3D.new()
	_mesh.mesh = deck_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = floor_color
	m.roughness = 0.8
	if floor_kind == FloorKind.SLIDING:
		m.emission_enabled = true
		m.emission = floor_color * 0.5
		m.emission_energy_multiplier = 0.15
	elif floor_kind == FloorKind.FROZEN:
		m.albedo_color = Color(0.7, 0.85, 1.0)
		m.roughness = 0.1
		m.metallic = 0.3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	_body.add_child(_mesh)
	
	# Lips (separate mesh so they can have their own color)
	if lip_height > 0.01:
		var lst := SurfaceTool.new()
		lst.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(steps):
			var a: Dictionary = frames[i]
			var b: Dictionary = frames[i + 1]
			for s in [-1.0, 1.0]:
				var ae: Vector3 = a.pos + a.side * hw * s
				var be: Vector3 = b.pos + b.side * hw * s
				var au: Vector3 = ae + a.up * lip_height
				var bu: Vector3 = be + b.up * lip_height
				_quad(lst, ae, au, bu, be)
				_quad(lst, au, ae, be, bu)   # double-sided
		lst.generate_normals()
		var lips := MeshInstance3D.new()
		lips.mesh = lst.commit()
		var lm := StandardMaterial3D.new()
		lm.albedo_color = lip_color
		lm.roughness = 0.9
		lm.cull_mode = BaseMaterial3D.CULL_DISABLED
		lips.material_override = lm
		_body.add_child(lips)
	
	# --- Collision: one convex slab per segment (follows the bend) ---
	for i in range(steps):
		var a: Dictionary = frames[i]
		var b: Dictionary = frames[i + 1]
		var pts := PackedVector3Array([
			a.pos - a.side * hw, a.pos + a.side * hw,
			b.pos - b.side * hw, b.pos + b.side * hw,
			a.pos - a.side * hw - a.up * thickness, a.pos + a.side * hw - a.up * thickness,
			b.pos - b.side * hw - b.up * thickness, b.pos + b.side * hw - b.up * thickness,
		])
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_body.add_child(cs)
		# Lip collision (thin walls)
		if lip_height > 0.01:
			for s in [-1.0, 1.0]:
				var lpts := PackedVector3Array([
					a.pos + a.side * hw * s, a.pos + a.side * hw * s + a.up * lip_height,
					b.pos + b.side * hw * s, b.pos + b.side * hw * s + b.up * lip_height,
					a.pos + a.side * (hw - 0.15) * s, a.pos + a.side * (hw - 0.15) * s + a.up * lip_height,
					b.pos + b.side * (hw - 0.15) * s, b.pos + b.side * (hw - 0.15) * s + b.up * lip_height,
				])
				var lshape := ConvexPolygonShape3D.new()
				lshape.points = lpts
				var lcs := CollisionShape3D.new()
				lcs.shape = lshape
				_body.add_child(lcs)


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	# Two triangles, clockwise winding
	st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
	st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
