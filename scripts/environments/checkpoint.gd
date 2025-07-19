extends Node3D

@export var checkpoint_id: String = ""
@export var respawn_offset: Vector3 = Vector3(0, 1, 0)  # Offset above the checkpoint
@export var one_time_use: bool = false
@export var visual_feedback: bool = true

@onready var area_3d = $Area3D
@onready var mesh_instance = $MeshInstance3D  # Optional: for visual feedback

var activated: bool = false

func _ready():
	# Make sure this checkpoint is in the "checkpoint" group
	add_to_group("checkpoint")
	
	# Connect the area signal
	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
	
	# Set up visual feedback if enabled
	if visual_feedback and mesh_instance:
		setup_visual_feedback()

func _on_body_entered(body):
	# Check if the body that entered is the player
	if body.is_in_group("player") or body.name == "Inke":
		activate_checkpoint(body)

func activate_checkpoint(player):
	# Don't activate if it's one-time use and already activated
	if one_time_use and activated:
		return
	
	activated = true
	
	# Calculate respawn position
	var respawn_position = global_position + respawn_offset
	var respawn_rotation = global_rotation
	
	# Set this as the active checkpoint
	CheckpointManager.set_checkpoint(respawn_position, respawn_rotation)
	
	# Visual/audio feedback
	if visual_feedback:
		play_activation_effect()
	
	print("Checkpoint '", checkpoint_id, "' activated!")

func setup_visual_feedback():
	# Create a simple pulsing effect for the checkpoint
	if mesh_instance and mesh_instance.get_surface_override_material(0):
		var material = mesh_instance.get_surface_override_material(0)
		if material:
			# You can customize this based on your visual style
			var tween = create_tween()
			tween.set_loops()
			tween.tween_property(material, "albedo_color:a", 0.3, 1.0)
			tween.tween_property(material, "albedo_color:a", 1.0, 1.0)

func play_activation_effect():
	# Visual effect when checkpoint is activated
	if mesh_instance:
		var tween = create_tween()
		tween.tween_property(mesh_instance, "scale", Vector3(1.2, 1.2, 1.2), 0.2)
		tween.tween_property(mesh_instance, "scale", Vector3(1.0, 1.0, 1.0), 0.2)
	
