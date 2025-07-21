extends Node3D

@export var checkpoint_id: String = ""
@export var respawn_offset: Vector3 = Vector3(0, 1, 0)  # Offset above the checkpoint
@export var one_time_use: bool = false

@onready var area_3d = $Area3D


var activated: bool = false

func _ready():
	# Make sure this checkpoint is in the "checkpoint" group
	add_to_group("checkpoint")
	
	# Connect the area signal
	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
	


func _on_body_entered(body):
	# Check if the body that entered is the player
	if body.is_in_group("player") or body.name == "Inke":
		activate_checkpoint(body)

func activate_checkpoint(_player):
	if one_time_use and activated:
		return
	
	activated = true
	
	# Calculate respawn position
	var respawn_position = global_position + respawn_offset
	var respawn_rotation = global_rotation
	
	# Set this as the active checkpoint
	CheckpointManager.set_checkpoint(respawn_position, respawn_rotation)
	print("Checkpoint '", checkpoint_id, "' activated!")
