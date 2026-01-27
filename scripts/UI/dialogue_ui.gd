extends CanvasLayer

const PORTRAITS_PATH = "res://assets/portraits/"

@onready var dialogue_container = $DialogueContainer
@onready var speaker_label = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/SpeakerName
@onready var text_label = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/DialogueText
@onready var portrait_texture = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/PortraitSection/Portrait
@onready var continue_indicator = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/ContinueIndicator

# Wall trigger UI elements
@onready var wall_dialogue_container = $WallDialogueContainer
@onready var wall_text_label = $WallDialogueContainer/WallDialogueBox/MarginContainer/VBoxContainer/DialogueText
@onready var wall_speaker_label = $WallDialogueContainer/WallDialogueBox/MarginContainer/VBoxContainer/SpeakerName
@export var wall_display_duration: float = 1.5  # Time to show wall dialogue

var is_typing: bool = false
var current_text: String = ""
var displayed_text: String = ""
var char_index: int = 0
var is_wall_trigger: bool = false
var wall_timer: float = 0.0
var waiting_for_release: bool = false  # Wait for space to be released before accepting new input

@export var text_speed: float = 0.01  # Time between each character
var typing_timer: float = 0.0

func _ready() -> void:
	# Start hidden
	dialogue_container.visible = false
	if wall_dialogue_container:
		wall_dialogue_container.visible = false
	
	# IMPORTANT: Allow this UI to process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	DialogueManager.register_ui(self)
	DialogueManager.dialogue_line_changed.connect(_on_dialogue_line_changed)
	
	# Make continue indicator blink
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.5)
	tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.5)
	
	print("DialogueUI: Ready and registered")


func _unhandled_input(event: InputEvent) -> void:
	# ADDED: If waiting for release, consume jump/ui_accept inputs
	if waiting_for_release:
		if event.is_action("ui_accept") or event.is_action("jump"):
			get_viewport().set_input_as_handled()
			# Only clear the flag on release
			if event.is_action_released("ui_accept") or event.is_action_released("jump"):
				waiting_for_release = false
		return
	
	# Only process input for regular dialogue (not wall triggers)
	if not dialogue_container.visible or is_wall_trigger:
		return
	
	if event.is_action_pressed("ui_accept"):
		if is_typing:
			finish_typing()
		else:
			DialogueManager.next_line()
		get_viewport().set_input_as_handled()

func hide_dialogue() -> void:
	dialogue_container.visible = false
	if wall_dialogue_container:
		wall_dialogue_container.visible = false
	print("DialogueUI: Hiding dialogue")
	
	# Set flag to wait for button release ONLY for proximity box triggers (not wall triggers)
	if not is_wall_trigger:
		waiting_for_release = true
	
	get_tree().paused = false
	is_wall_trigger = false
	wall_timer = 0.0
	
func _process(delta: float) -> void:
	if is_typing:
		typing_timer += delta
		
		if typing_timer >= text_speed:
			typing_timer = 0.0
			display_next_character()
	
	# Handle wall trigger auto-dismiss
	if is_wall_trigger and wall_dialogue_container and wall_dialogue_container.visible:
		wall_timer += delta
		if wall_timer >= wall_display_duration:
			if is_typing:
				finish_typing()
				wall_timer = 0.0  # Reset to show completed text briefly
			else:
				DialogueManager.next_line()
				wall_timer = 0.0

func show_dialogue(should_pause: bool = true) -> void:
	# Determine if this is a wall trigger based on pause state
	is_wall_trigger = not should_pause
	
	if is_wall_trigger:
		# Show wall trigger UI (right side, compact)
		if wall_dialogue_container:
			wall_dialogue_container.visible = true
			dialogue_container.visible = false
		wall_timer = 0.0
		print("DialogueUI: Showing wall trigger dialogue")
	else:
		# Show regular dialogue UI
		dialogue_container.visible = true
		if wall_dialogue_container:
			wall_dialogue_container.visible = false
		print("DialogueUI: Showing regular dialogue")
		# Pause game if requested
		get_tree().paused = true


func _on_dialogue_line_changed(speaker: String, text: String, portrait: String) -> void:
	print("DialogueUI: Displaying line - Speaker: ", speaker, " Text: ", text)
	
	current_text = text
	
	if is_wall_trigger:
		# Update wall trigger UI
		if wall_speaker_label:
			wall_speaker_label.text = speaker
		wall_timer = 0.0
	else:
		# Update regular UI
		speaker_label.text = speaker
		load_portrait(portrait)
	
	start_typing()

func load_portrait(portrait_name: String) -> void:
	if portrait_name.is_empty():
		portrait_texture.texture = null
		return
	
	var portrait_path = PORTRAITS_PATH + portrait_name + ".png"
	
	if ResourceLoader.exists(portrait_path):
		portrait_texture.texture = load(portrait_path)
	else:
		print("DialogueUI: Portrait not found: ", portrait_path)
		portrait_texture.texture = null

func start_typing() -> void:
	is_typing = true
	char_index = 0
	displayed_text = ""
	typing_timer = 0.0
	continue_indicator.visible = false
	
	if is_wall_trigger:
		if wall_text_label:
			wall_text_label.text = ""
	else:
		text_label.text = ""

func display_next_character() -> void:
	if char_index < current_text.length():
		displayed_text += current_text[char_index]
		
		if is_wall_trigger:
			if wall_text_label:
				wall_text_label.text = displayed_text
		else:
			text_label.text = displayed_text
		
		char_index += 1
	else:
		finish_typing()

func finish_typing() -> void:
	is_typing = false
	displayed_text = current_text
	char_index = current_text.length()
	
	if is_wall_trigger:
		if wall_text_label:
			wall_text_label.text = current_text
	else:
		text_label.text = current_text
		continue_indicator.visible = true
