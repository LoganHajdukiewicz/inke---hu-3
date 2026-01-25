extends CanvasLayer

const PORTRAITS_PATH = "res://assets/portraits/"

@onready var dialogue_container = $DialogueContainer
@onready var speaker_label = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/SpeakerName
@onready var text_label = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/DialogueText
@onready var portrait_texture = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/PortraitSection/Portrait
@onready var continue_indicator = $DialogueContainer/DialogueBox/MarginContainer/HBoxContainer/TextSection/ContinueIndicator

var is_typing: bool = false
var current_text: String = ""
var displayed_text: String = ""
var char_index: int = 0

@export var text_speed: float = 0.03  # Time between each character
var typing_timer: float = 0.0

func _ready() -> void:
	hide_dialogue()
	DialogueManager.register_ui(self)
	DialogueManager.dialogue_line_changed.connect(_on_dialogue_line_changed)
	
	# Make continue indicator blink
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.5)
	tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.5)

func _input(event: InputEvent) -> void:
	if not dialogue_container.visible:
		return
	
	if event.is_action_pressed("dialogic_default_action"):
		if is_typing:
			# Skip typing animation
			finish_typing()
		else:
			# Go to next line
			DialogueManager.next_line()

func _process(delta: float) -> void:
	if is_typing:
		typing_timer += delta
		
		if typing_timer >= text_speed:
			typing_timer = 0.0
			display_next_character()

func show_dialogue() -> void:
	dialogue_container.visible = true
	get_tree().paused = false  # Change to true if you want to pause game during dialogue

func hide_dialogue() -> void:
	dialogue_container.visible = false
	get_tree().paused = false

func _on_dialogue_line_changed(speaker: String, text: String, portrait: String) -> void:
	speaker_label.text = speaker
	current_text = text
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
	text_label.text = ""
	typing_timer = 0.0
	continue_indicator.visible = false

func display_next_character() -> void:
	if char_index < current_text.length():
		displayed_text += current_text[char_index]
		text_label.text = displayed_text
		char_index += 1
	else:
		finish_typing()

func finish_typing() -> void:
	is_typing = false
	text_label.text = current_text
	displayed_text = current_text
	char_index = current_text.length()
	continue_indicator.visible = true