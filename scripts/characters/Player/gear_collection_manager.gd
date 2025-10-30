extends Node
class_name GearCollectionManager

var gear_collection_area: Area3D = null
var gear_collection_distance: float = 0.5

var player: CharacterBody3D
var game_manager

func _ready():
	player = get_parent() as CharacterBody3D
	game_manager = get_node("/root/GameManager")
	setup_gear_collection()

func setup_gear_collection():
	"""Set up Area3D for gear collection"""
	gear_collection_area = Area3D.new()
	gear_collection_area.name = "GearCollectionArea"
	player.add_child(gear_collection_area)
	
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = gear_collection_distance
	collision_shape.shape = sphere_shape
	gear_collection_area.add_child(collision_shape)
	
	gear_collection_area.body_entered.connect(_on_gear_body_entered)
	gear_collection_area.area_entered.connect(_on_gear_area_entered)

func _physics_process(_delta):
	check_for_nearby_gears()

func check_for_nearby_gears():
	"""Check for gears within collection distance and collect them"""
	var gears = get_tree().get_nodes_in_group("Gear")
	
	for gear in gears:
		if not is_instance_valid(gear):
			continue
		
		if gear.has_method("get") and gear.get("collected"):
			continue
		
		var distance = player.global_position.distance_to(gear.global_position)
		if distance <= gear_collection_distance:
			collect_gear(gear)

func collect_gear(gear: Node):
	"""Collect a gear as Inke"""
	if not gear or not is_instance_valid(gear):
		return
	
	if gear.has_method("get") and gear.get("collected"):
		return
	
	if gear.has_method("collect_gear"):
		gear.collect_gear()
	else:
		if gear.has_method("set"):
			gear.set("collected", true)
		if game_manager:
			game_manager.add_gear(1)
		gear.queue_free()

func _on_gear_body_entered(body: Node3D):
	"""Handle when a gear body enters collection area"""
	if body.is_in_group("Gear"):
		collect_gear(body)

func _on_gear_area_entered(area: Area3D):
	"""Handle when a gear area enters collection area"""
	if area.is_in_group("Gear"):
		var gear_node = area.get_parent()
		if gear_node and gear_node.is_in_group("Gear"):
			collect_gear(gear_node)
		else:
			collect_gear(area)
