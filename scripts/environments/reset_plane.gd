extends Node3D

@onready var area_3d = $Area3D

func _ready():
	area_3d.body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	# Check if the body that entered is the player
	if body.is_in_group("player") or body.name == "Inke":
		respawn_player(body)

func respawn_player(player):
	print("Player fell through reset plane")
	
	# Check if we have an active checkpoint
	if CheckpointManager.has_active_checkpoint():
		# Respawn at checkpoint
		var checkpoint_pos = CheckpointManager.get_checkpoint_position()
		var checkpoint_rot = CheckpointManager.get_checkpoint_rotation()
		
		player.global_position = checkpoint_pos
		player.global_rotation = checkpoint_rot
		
		# Reset player velocity if they have a RigidBody3D or CharacterBody3D
		if player.has_method("set_velocity"):
			player.set_velocity(Vector3.ZERO)
		elif player is RigidBody3D:
			player.linear_velocity = Vector3.ZERO
			player.angular_velocity = Vector3.ZERO
		
		print("Respawned player at checkpoint: ", checkpoint_pos)
	else:
		# No checkpoint, reload scene as before
		print("No checkpoint found - reloading scene")
		get_tree().reload_current_scene()
