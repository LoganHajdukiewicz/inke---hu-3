@tool
extends Path3D

## Grind rail. The Curve3D is editable by hand (select the Rail, use the
## Path3D point tools in the toolbar), but the EDITOR CURVE TOOLS below make
## curved rails one click:
##   1. Pick a Curve Preset (Arc, S-Curve, Spiral, Ramp...)
##   2. Tweak radius / length / angle / height
##   3. Tick "Generate Preset" - the curve (and the rail mesh) update instantly
## "Smooth Existing Points" rounds off a hand-placed set of points without
## replacing them.

@export var rail_follower = preload("res://scenes/items/Rails/rail_follow_node.tscn")

## TODO: Have a more elegant solution than to just stick a fuckton of nodes there. 
@export var point_total: int = 50

@export_group("Editor Curve Tools")
@export_enum("Straight", "Arc", "S-Curve", "Spiral", "Ramp") var curve_preset: int = 1
## Length of Straight / S-Curve / Ramp presets (meters)
@export var preset_length: float = 20.0
## Radius of Arc / Spiral presets; sideways amplitude of the S-Curve
@export var preset_radius: float = 8.0
## How far around the Arc / Spiral sweeps (Spiral can exceed 360)
@export_range(15.0, 1080.0, 5.0) var preset_angle_degrees: float = 90.0
## End height relative to the start (negative = downhill rail)
@export var preset_height_change: float = 0.0
## More segments = smoother curve (they're auto-smoothed either way)
@export_range(3, 64) var preset_segments: int = 12
## Tick this to (re)build the curve from the preset settings above
@export var generate_preset: bool = false : set = _set_generate_preset
## Tick this to round off the corners of hand-placed curve points
@export var smooth_existing_points: bool = false : set = _set_smooth_points

var hasSpawnedPoints = false
var pointCount: float = 0.0

@onready var path_3d = $"."
@onready var path_curve = curve

func _ready():
	if Engine.is_editor_hint():
		return
	populate_rail()

func populate_rail():
	var path_length = curve.get_baked_length()
	
	# Calculate the progress increment to distribute nodes evenly
	var progress_increment = path_length / float(point_total - 1)  # -1 to include both ends

	for i in range(point_total):
		var object_instance = rail_follower.instantiate()
		
		# Calculate progress based on distance along the curve
		var current_progress = i * progress_increment
		
		# Clamp to ensure we don't exceed the rail length
		current_progress = min(current_progress, path_length)
		
		object_instance.progress = current_progress
		add_child(object_instance)
		
		pointCount += 1.0

	
	hasSpawnedPoints = true

# ============================= EDITOR TOOLS ==============================

func _set_generate_preset(value: bool) -> void:
	generate_preset = false
	if value:
		_generate_preset_curve()

func _set_smooth_points(value: bool) -> void:
	smooth_existing_points = false
	if value and curve and curve.point_count >= 2:
		_smooth_all_points()

func _generate_preset_curve() -> void:
	if curve == null:
		curve = Curve3D.new()
	
	var pts: Array[Vector3] = []
	var n: int = max(preset_segments, 3)
	
	match curve_preset:
		0:  # Straight (with optional height change)
			for i in range(n + 1):
				var t := float(i) / n
				pts.append(Vector3(0, preset_height_change * t, -preset_length * t))
		1:  # Arc - curves to the right; use negative angle... no: flip radius sign for left
			var sweep := deg_to_rad(preset_angle_degrees)
			for i in range(n + 1):
				var t := float(i) / n
				var a := sweep * t
				pts.append(Vector3(
					preset_radius * (1.0 - cos(a)),
					preset_height_change * t,
					-preset_radius * sin(a)
				))
		2:  # S-Curve (slalom): swings right then left over preset_length
			for i in range(n + 1):
				var t := float(i) / n
				pts.append(Vector3(
					preset_radius * 0.5 * sin(TAU * t),
					preset_height_change * t,
					-preset_length * t
				))
		3:  # Spiral: like Arc but meant for full turns + height change
			var sweep := deg_to_rad(preset_angle_degrees)
			for i in range(n + 1):
				var t := float(i) / n
				var a := sweep * t
				pts.append(Vector3(
					preset_radius * (1.0 - cos(a)),
					preset_height_change * t,
					-preset_radius * sin(a)
				))
		4:  # Ramp: straight with a smooth (eased) rise/drop
			for i in range(n + 1):
				var t := float(i) / n
				var ease_t := t * t * (3.0 - 2.0 * t)  # smoothstep
				pts.append(Vector3(0, preset_height_change * ease_t, -preset_length * t))
	
	curve.clear_points()
	for p in pts:
		curve.add_point(p)
	_smooth_all_points()

func _smooth_all_points() -> void:
	"""Give every point catmull-rom style in/out handles so the whole rail
	flows smoothly through them."""
	if curve == null or curve.point_count < 2:
		return
	for i in range(curve.point_count):
		var prev := curve.get_point_position(maxi(i - 1, 0))
		var next := curve.get_point_position(mini(i + 1, curve.point_count - 1))
		var tangent := (next - prev) * 0.25
		curve.set_point_in(i, -tangent)
		curve.set_point_out(i, tangent)
