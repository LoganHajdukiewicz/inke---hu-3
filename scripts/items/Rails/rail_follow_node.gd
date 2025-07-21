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

@export var grind_speed = 30.0  # Doubled from 15.0 to 30.0, now exported for easy adjustment

# Called when the node enters the scene tree for the first time.
func _ready():
	origin_point = path_follow_3d.progress

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
