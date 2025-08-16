extends PathFollow3D

@onready var path_follow_3d = $"."
@onready var path_3d = $".."
var grinding = false
var local_starting_progress = 0.0

@onready var origin_point = null

@onready var chosen = false
@onready var forward = true
@onready var direction_selected = false
@onready var detach = false


# Detection area for player interaction
var detection_area: Area3D = null

@export var grind_speed = 30.0  # This is the speed you move across the rail grind.
@export var detection_radius = 1.5  # How close player needs to be to detect this rail node

func _ready():
	origin_point = path_follow_3d.progress
	setup_detection_area()

func setup_detection_area():
	"""Set up Area3D for player detection"""
	detection_area = Area3D.new()
	detection_area.name = "RailDetectionArea"
	add_child(detection_area)
	
	# Create CollisionShape3D for the Area3D
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = detection_radius
	collision_shape.shape = sphere_shape
	detection_area.add_child(collision_shape)
	
	# Set up collision layers/masks if needed
	# detection_area.collision_layer = 0  # This area doesn't need to be detected by others
	# detection_area.collision_mask = 1   # Detect objects on layer 1 (usually player layer)

func _process(delta):
	# Only move if we're actively being used for grinding
	if grinding and chosen:
		if forward:
			path_follow_3d.progress += grind_speed * delta
		elif !forward:
			path_follow_3d.progress -= grind_speed * delta

		# Get the total path length
		var path_length = path_3d.curve.get_baked_length()
		
		# Check if we've reached the end of the rail using actual progress
		# Only check for detachment if we're actually moving in that direction
		if forward and path_follow_3d.progress >= path_length - 1.0:  # 1 unit before end
			detach = true
			grinding = false
			direction_selected = false
		
		if not forward and path_follow_3d.progress <= 1.0:  # 1 unit from start
			detach = true
			grinding = false
			direction_selected = false
	else:
		# Reset to origin when not grinding
		if not chosen:
			path_follow_3d.progress = origin_point
			direction_selected = false
			detach = false