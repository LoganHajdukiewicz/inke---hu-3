extends Node
class_name RailDetectionManager

var detected_rail_nodes: Array = []
var rail_grind_area: Area3D

var player: CharacterBody3D
var state_machine: StateMachine

func _ready():
	player = get_parent() as CharacterBody3D
	rail_grind_area = player.get_node("RailGrindArea")
	state_machine = player.get_node("StateMachine")
	setup_rail_detection()

func setup_rail_detection():
	"""Connect signals for the existing RailGrindArea"""
	if not rail_grind_area:
		print("Warning: RailGrindArea not found!")
		return
	
	if not rail_grind_area.body_entered.is_connected(_on_rail_body_entered):
		rail_grind_area.body_entered.connect(_on_rail_body_entered)
	if not rail_grind_area.body_exited.is_connected(_on_rail_body_exited):
		rail_grind_area.body_exited.connect(_on_rail_body_exited)
	if not rail_grind_area.area_entered.is_connected(_on_rail_area_entered):
		rail_grind_area.area_entered.connect(_on_rail_area_entered)
	if not rail_grind_area.area_exited.is_connected(_on_rail_area_exited):
		rail_grind_area.area_exited.connect(_on_rail_area_exited)
	
	print("Rail detection setup complete with RailGrindArea")

func _physics_process(_delta):
	check_for_rail_grinding()

func check_for_rail_grinding():
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	
	if current_state_name != "RailGrindingState":
		var rail_grinding_state = state_machine.states.get("railgrindingstate")
		
		if rail_grinding_state and rail_grinding_state.grind_timer_complete:
			var closest_rail_node = get_closest_rail_node()
			if closest_rail_node:
				state_machine.change_state("RailGrindingState")
				rail_grinding_state.setup_grinding_with_node(closest_rail_node)

func get_closest_rail_node():
	"""Get the closest rail follower node from detected nodes"""
	if detected_rail_nodes.is_empty():
		return null
	
	var closest_node = null
	var min_distance = INF
	
	for rail_node in detected_rail_nodes:
		if not is_instance_valid(rail_node):
			continue
		
		var distance = player.global_position.distance_to(rail_node.global_position)
		if distance < min_distance:
			min_distance = distance
			closest_node = rail_node
	
	return closest_node

func _on_rail_body_entered(body: Node3D):
	"""Handle when a rail body enters detection area"""
	if body.is_in_group("rail_follower"):
		if body not in detected_rail_nodes:
			detected_rail_nodes.append(body)

func _on_rail_body_exited(body: Node3D):
	"""Handle when a rail body exits detection area"""
	if body in detected_rail_nodes:
		detected_rail_nodes.erase(body)

func _on_rail_area_entered(area: Area3D):
	"""Handle when a rail area enters detection area"""
	if area.is_in_group("rail_follower"):
		if area not in detected_rail_nodes:
			detected_rail_nodes.append(area)
	elif area.get_parent() and area.get_parent().is_in_group("rail_follower"):
		var rail_node = area.get_parent()
		if rail_node not in detected_rail_nodes:
			detected_rail_nodes.append(rail_node)

func _on_rail_area_exited(area: Area3D):
	"""Handle when a rail area exits detection area"""
	if area.is_in_group("rail_follower"):
		if area in detected_rail_nodes:
			detected_rail_nodes.erase(area)
	elif area.get_parent() and area.get_parent().is_in_group("rail_follower"):
		var rail_node = area.get_parent()
		if rail_node in detected_rail_nodes:
			detected_rail_nodes.erase(rail_node)
