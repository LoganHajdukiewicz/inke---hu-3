extends Area3D
class_name DialogueTrigger

@export var dialogue_file: String = ""  # e.g. "Example" (without .json extension)
@export var show_prompt: bool = true
@export var trigger_once: bool = false  # Only trigger dialogue once

var player_nearby: bool = false
var dialogue_active: bool = false
var has_been_triggered: bool = false

@onready var interaction_prompt = $InteractionPrompt if has_node("InteractionPrompt") else null

signal interaction_available(trigger: DialogueTrigger)
signal interaction_unavailable

func _ready() -> void:
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Hide prompt initially
	if interaction_prompt:
		interaction_prompt.visible = false
	
	# Add to dialogue triggers group
	add_to_group("dialogue_triggers")
	
	# FIXED: Connect to DialogueManager signals
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		if trigger_once and has_been_triggered:
			return
			
		player_nearby = true
		
		if show_prompt and interaction_prompt:
			interaction_prompt.visible = true
		
		interaction_available.emit(self)

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("Player"):
		player_nearby = false
		
		if interaction_prompt:
			interaction_prompt.visible = false
		
		interaction_unavailable.emit()

# FIXED: Changed from _input to _unhandled_input and added proper checks
func _unhandled_input(event: InputEvent) -> void:
	if not player_nearby or dialogue_active or DialogueManager.is_dialogue_active():
		return
	
	if trigger_once and has_been_triggered:
		return
	
	if event.is_action_pressed("ui_accept"):
		start_dialogue()
		get_viewport().set_input_as_handled()

func _on_dialogue_started() -> void:
	dialogue_active = true

func _on_dialogue_ended() -> void:
	dialogue_active = false
	
	# Show prompt again if player still nearby (unless trigger_once is true)
	if player_nearby and show_prompt and interaction_prompt and not (trigger_once and has_been_triggered):
		interaction_prompt.visible = true

func start_dialogue() -> void:
	if dialogue_file.is_empty():
		print("DialogueTrigger: No dialogue file assigned!")
		return
	
	has_been_triggered = true
	
	if interaction_prompt:
		interaction_prompt.visible = false
	
	DialogueManager.start_dialogue(dialogue_file, self)

func end_dialogue() -> void:
	# This is called by DialogueManager when dialogue ends
	pass

func reset_trigger() -> void:
	"""Manually reset the trigger (useful for debugging or specific game logic)"""
	has_been_triggered = false
