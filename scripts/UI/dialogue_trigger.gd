extends Area3D
class_name DialogueTrigger

enum TriggerType {
	PROXIMITY_BOX,  # Square trigger that requires ui_accept press
	WALL_TRIGGER    # Wall that auto-triggers on pass-through
}

@export var dialogue_file: String = ""  # e.g. "Example" (without .json extension)
@export var trigger_type: TriggerType = TriggerType.PROXIMITY_BOX
@export var box_size: Vector3 = Vector3(2.0, 2.0, 2.0)  # Size of the proximity box
@export var show_prompt: bool = true  # Only applies to PROXIMITY_BOX
@export var trigger_once: bool = false  # Only trigger dialogue once
@export var pause_game: bool = true  # Pause game during dialogue (only for PROXIMITY_BOX)

var player_nearby: bool = false
var has_been_triggered: bool = false
var collision_shape: CollisionShape3D

@onready var interaction_prompt = $InteractionPrompt if has_node("InteractionPrompt") else null

signal interaction_available(trigger: DialogueTrigger)
signal interaction_unavailable

func _ready() -> void:
	# Create collision shape based on trigger type
	setup_collision_shape()
	
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

func _on_body_entered(body: Node3D) -> void:
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
	if not body.is_in_group("Player"):
		return
	
	if trigger_type == TriggerType.PROXIMITY_BOX:
		player_nearby = false
		
		if interaction_prompt:
			interaction_prompt.visible = false
		
		interaction_unavailable.emit()

func _unhandled_input(event: InputEvent) -> void:
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
	# This is called by DialogueManager when dialogue ends
	# Show prompt again if player still nearby (unless trigger_once is true)
	if player_nearby and show_prompt and interaction_prompt and not (trigger_once and has_been_triggered):
		interaction_prompt.visible = true

func reset_trigger() -> void:
	"""Manually reset the trigger (useful for debugging or specific game logic)"""
	has_been_triggered = false

# Called when inspector values change
func _set(property: StringName, value: Variant) -> bool:
	if property == "trigger_type" or property == "box_size":
		if is_inside_tree():
			# Defer the update to avoid issues during scene loading
			call_deferred("setup_collision_shape")
	return false