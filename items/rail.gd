extends Path3D
#Adjust these to your prject:
@export var rail_follower = preload("res://items/rail_follow_node.tscn")
@export var point_total: int = 20
 
 
@onready var path_3d = $"."
var hasSpawnedPoints = false
var pointCount: float = 0
@onready var path_curve = curve
 
 
# Called when the node enters the scene tree for the first time.
func _ready():
	populate_rail()
	
func _process(delta):
	pass
 
func populate_rail():
	var path_length = curve.get_baked_length()
	var spacing = path_length / 19
	var current_distance = 0
	var staring_progress = 0.001
	for i in range(point_total):
		var object_instance = rail_follower.instantiate()
		object_instance.progress = staring_progress
		add_child(object_instance)
		staring_progress += 5
		current_distance += spacing
		pointCount += 1.0
		if i == point_total:
			hasSpawnedPoints = true
 
