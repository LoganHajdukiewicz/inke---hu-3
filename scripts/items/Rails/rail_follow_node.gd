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
	# PERFORMANCE: idle followers do nothing - only process while the
	# player is actually grinding on this node (rail_grinding_state sets
	# grinding/chosen). 200+ followers per level used to tick every frame.
	set_process(false)


func _set_active(on: bool) -> void:
	set_process(on)

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
	
	# PERFORMANCE: live ONLY on the Grindable layer (2) and watch nothing.
	# On the default layer/mask every follower overlapped its neighbours,
	# the rail and the world: ~1,450 permanent collision pairs per level
	# (2/3 of all physics pairs). Inke's RailGrindArea scans layer 2.
	detection_area.collision_layer = 1 << 1   # layer 2 "Grindable Layer"
	detection_area.collision_mask = 0
	detection_area.monitoring = false
	detection_area.monitorable = true

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
		# Reset to origin when not grinding, then go back to sleep
		if not chosen:
			path_follow_3d.progress = origin_point
			direction_selected = false
			detach = false
			set_process(false)
