extends Path3D

@export var rail_follower = preload("res://scenes/items/Rails/rail_follow_node.tscn")
@export var point_total: int = 50

var hasSpawnedPoints = false
var pointCount: float = 0.0
 
 
@onready var path_3d = $"."
@onready var path_curve = curve

func _ready():
	populate_rail()
	
func _process(_delta):
	pass
 
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
