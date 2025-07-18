extends Node

var current_checkpoint_position: Vector3 = Vector3.ZERO
var current_checkpoint_rotation: Vector3 = Vector3.ZERO
var has_checkpoint: bool = false

signal checkpoint_activated(position: Vector3)

func set_checkpoint(position: Vector3, rotation: Vector3 = Vector3.ZERO):
	current_checkpoint_position = position
	current_checkpoint_rotation = rotation
	has_checkpoint = true
	checkpoint_activated.emit(position)
	print("Checkpoint set at: ", position)

func get_checkpoint_position() -> Vector3:
	return current_checkpoint_position

func get_checkpoint_rotation() -> Vector3:
	return current_checkpoint_rotation

func has_active_checkpoint() -> bool:
	return has_checkpoint

func reset_checkpoints():
	has_checkpoint = false
	current_checkpoint_position = Vector3.ZERO
	current_checkpoint_rotation = Vector3.ZERO
