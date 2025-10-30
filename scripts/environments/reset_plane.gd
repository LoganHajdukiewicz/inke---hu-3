extends Node3D

@onready var area_3d = $Area3D

func _ready():
	area_3d.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player") or body.name == "Inke":
		respawn_player(body)

func respawn_player(player):

	# Check if we have an active checkpoint
	if CheckpointManager.has_active_checkpoint():
		# Respawn at checkpoint
		var checkpoint_pos = CheckpointManager.get_checkpoint_position()
		var checkpoint_rot = CheckpointManager.get_checkpoint_rotation()
		
		player.global_position = checkpoint_pos
		player.global_rotation = checkpoint_rot
		
		# Reset player velocity
		if player.has_method("set_velocity"):
			player.set_velocity(Vector3.ZERO)
	else:
		call_deferred("get_tree().reload_current_scene()")
