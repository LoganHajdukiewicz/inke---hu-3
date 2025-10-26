@tool
extends Area3D

@export_file("*.tscn") var target_scene: String
@export var size: Vector3 = Vector3(2, 2, 2):
	set(value):
		size = value
		update_size()

func _ready():
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
	update_size()

func update_size():
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		if not collision_shape.shape or not collision_shape.shape is BoxShape3D:
			collision_shape.shape = BoxShape3D.new()
		
		# Make sure we have a unique shape resource
		if collision_shape.shape.resource_local_to_scene == false:
			collision_shape.shape = collision_shape.shape.duplicate()
		
		collision_shape.shape.size = size

func _on_body_entered(body: Node3D):
	# Check if the body that entered is the player
	if body.is_in_group("Player"):
		transition_to_scene()

func transition_to_scene():
	if target_scene == "":
		push_error("Scene Transitioner: No target scene specified!")
		return
	
	# Change to the target scene
	get_tree().change_scene_to_file(target_scene)
