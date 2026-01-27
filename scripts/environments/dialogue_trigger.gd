@tool
extends Area3D
class_name DialogueTrigger

enum TriggerType {
	PROXIMITY_BOX,  # Square trigger that requires ui_accept press
	WALL_TRIGGER    # Wall that auto-triggers on pass-through
}

@export var dialogue_file: String = ""  # e.g. "Example" (without .json extension)

@export var trigger_type: TriggerType = TriggerType.PROXIMITY_BOX:
	set(value):
		trigger_type = value
		if is_inside_tree():
			setup_collision_shape()
			update_debug_visualization()

@export var box_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		box_size = value
		if is_inside_tree():
			setup_collision_shape()
			update_debug_visualization()

@export var show_prompt: bool = true  # Only applies to PROXIMITY_BOX
@export var trigger_once: bool = false  # Only trigger dialogue once
@export var pause_game: bool = true  # Pause game during dialogue (only for PROXIMITY_BOX)

@export var show_debug_visualization: bool = false:
	set(value):
		show_debug_visualization = value
		if is_inside_tree():
			update_debug_visualization()

@export var debug_plane_size: Vector2 = Vector2(100.0, 100.0):
	set(value):
		debug_plane_size = value
		if is_inside_tree():
			update_debug_visualization()

var player_nearby: bool = false
var has_been_triggered: bool = false
var collision_shape: CollisionShape3D
var debug_mesh: MeshInstance3D

@onready var interaction_prompt = $InteractionPrompt if has_node("InteractionPrompt") else null

signal interaction_available(trigger: DialogueTrigger)
signal interaction_unavailable

func _ready() -> void:
	# Create collision shape based on trigger type
	setup_collision_shape()
	
	# Setup debug visualization
	update_debug_visualization()
	
	# Only connect gameplay signals when not in editor
	if not Engine.is_editor_hint():
		# Connect signals
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
		
		# Hide prompt initially
		if interaction_prompt:
			interaction_prompt.visible = false
		
		# Add to dialogue triggers group
		add_to_group("dialogue_triggers")

func setup_collision_shape() -> void:
	# Remove any existing collision shapes
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	
	# Create new collision shape
	collision_shape = CollisionShape3D.new()
	add_child(collision_shape)
	
	if Engine.is_editor_hint():
		collision_shape.owner = get_tree().edited_scene_root
	else:
		collision_shape.owner = self
	
	if trigger_type == TriggerType.PROXIMITY_BOX:
		# Create box shape centered on the trigger
		var box_shape = BoxShape3D.new()
		box_shape.size = box_size
		collision_shape.shape = box_shape
		print("DialogueTrigger: Created proximity box with size ", box_size)
	else:  # WALL_TRIGGER
		# Create world boundary (infinite plane)
		var plane_shape = WorldBoundaryShape3D.new()
		plane_shape.plane = Plane(0, 0, 1, 0)  # Facing forward (Z-axis)
		collision_shape.shape = plane_shape
		print("DialogueTrigger: Created wall trigger")

func update_debug_visualization() -> void:
	# Remove existing debug mesh if it exists
	if debug_mesh:
		debug_mesh.queue_free()
		debug_mesh = null
	
	if not show_debug_visualization:
		return
	
	# Create debug mesh
	debug_mesh = MeshInstance3D.new()
	add_child(debug_mesh)
	
	# Rotate 90 degrees around X axis to make it vertical (matching the world boundary)
	debug_mesh.rotation_degrees.x = 90
	
	if Engine.is_editor_hint():
		debug_mesh.owner = get_tree().edited_scene_root
	else:
		debug_mesh.owner = self
	
	if trigger_type == TriggerType.PROXIMITY_BOX:
		# Create box mesh for proximity box
		var box_mesh = BoxMesh.new()
		box_mesh.size = box_size
		debug_mesh.mesh = box_mesh
		
		# Create semi-transparent green material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.0, 1.0, 0.0, 0.3)  # Light green with transparency
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
		debug_mesh.material_override = material
		
	else:  # WALL_TRIGGER
		# Create plane mesh for wall trigger
		var plane_mesh = PlaneMesh.new()
		plane_mesh.size = debug_plane_size
		debug_mesh.mesh = plane_mesh
		
		# Create semi-transparent light green material
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(0.5, 1.0, 0.5, 0.4)  # Light green with transparency
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
		debug_mesh.material_override = material
	
	print("DialogueTrigger: Debug visualization ", "enabled" if show_debug_visualization else "disabled")

func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
		
	if not body.is_in_group("Player"):
		return
	
	if trigger_once and has_been_triggered:
		return
	
	if trigger_type == TriggerType.PROXIMITY_BOX:
		# Proximity box requires player to press button
		player_nearby = true
		
		if show_prompt and interaction_prompt:
			interaction_prompt.visible = true
		
		interaction_available.emit(self)
	else:  # WALL_TRIGGER
		# Wall trigger auto-starts dialogue
		start_dialogue()

func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
		
	if not body.is_in_group("Player"):
		return
	
	if trigger_type == TriggerType.PROXIMITY_BOX:
		player_nearby = false
		
		if interaction_prompt:
			interaction_prompt.visible = false
		
		interaction_unavailable.emit()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
		
	# Only proximity boxes use button input
	if trigger_type != TriggerType.PROXIMITY_BOX:
		return
	
	# Only respond when player is nearby and no dialogue is active
	if not player_nearby or DialogueManager.is_dialogue_active():
		return
	
	if trigger_once and has_been_triggered:
		return
	
	if event.is_action_pressed("ui_accept"):
		start_dialogue()
		get_viewport().set_input_as_handled()

func start_dialogue() -> void:
	if Engine.is_editor_hint():
		return
		
	if dialogue_file.is_empty():
		print("DialogueTrigger: No dialogue file assigned!")
		return
	
	has_been_triggered = true
	
	if interaction_prompt:
		interaction_prompt.visible = false
	
	print("DialogueTrigger: Starting dialogue: ", dialogue_file)
	
	# Set pause state based on trigger type and setting
	var should_pause = (trigger_type == TriggerType.PROXIMITY_BOX) and pause_game
	DialogueManager.start_dialogue(dialogue_file, self, should_pause)

func end_dialogue() -> void:
	if Engine.is_editor_hint():
		return
		
	# This is called by DialogueManager when dialogue ends
	# Show prompt again if player still nearby (unless trigger_once is true)
	if player_nearby and show_prompt and interaction_prompt and not (trigger_once and has_been_triggered):
		interaction_prompt.visible = true

func reset_trigger() -> void:
	"""Manually reset the trigger (useful for debugging or specific game logic)"""
	has_been_triggered = false
