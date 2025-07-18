extends Node


@export var gear_count: int = 0
@export var CRED: int = 0
@export var health: int = 3

@export_group("Upgrades Purchased")
@export var double_jump_purchased: bool = false
@export var wall_jump_purchased: bool = false
@export var dash_purchased: bool = false
@export var speed_upgrade_purchased: bool = false
@export var health_upgrade_purchased: bool = false
@export var damage_upgrade_purchased: bool = false




func _ready():
	pass

func add_gear():
	gear_count += 1
	print("Gear collected! Total gears: ", gear_count)

func add_CRED(reward):
	CRED += reward
	print("CRED Received! CRED added: ", reward)
	print("Total CRED: ", CRED)

func get_gear_count() -> int:
	return gear_count
	
func get_CRED_count() -> int:
	return CRED
