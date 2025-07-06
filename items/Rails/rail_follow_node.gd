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

@export var move_speed = 12.0

# Called when the node enters the scene tree for the first time.
func _ready():
	origin_point = path_follow_3d.progress

func _process(delta):
	# Only move if we're actively being used for grinding
	if grinding and chosen:
		if forward:
			path_follow_3d.progress += move_speed * delta
		elif !forward:
			path_follow_3d.progress -= move_speed * delta

		# Check if we've reached the end of the rail
		if path_follow_3d.get_progress_ratio() >= 0.99:
			detach = true
			grinding = false
			direction_selected = false
		
		if path_follow_3d.get_progress_ratio() <= 0.002:
			detach = true
			grinding = false
			direction_selected = false
	else:
		# Reset to origin when not grinding
		if not chosen:
			path_follow_3d.progress = origin_point
			direction_selected = false
			detach = false
