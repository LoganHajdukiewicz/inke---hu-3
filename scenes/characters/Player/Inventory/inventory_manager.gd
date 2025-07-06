extends Node

@export var gear_count: int = 0

func _ready():
	pass

func add_gear():
	gear_count += 1
	print("Gear collected! Total gears: ", gear_count)


func get_gear_count() -> int:
	return gear_count
