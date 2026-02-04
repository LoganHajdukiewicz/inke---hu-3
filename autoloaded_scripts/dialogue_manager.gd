extends Node

# Base dialogue path - will be combined with scene-specific paths
const DIALOGUE_BASE_PATH = "res://dialogue/"

var current_dialogue: Array = []
var current_index: int = 0
var dialogue_ui: CanvasLayer = null
var current_trigger: DialogueTrigger = null
var current_scene_name: String = ""
var input_block_timer: float = 0.0
var input_block_duration: float = 0.2

signal dialogue_started
signal dialogue_line_changed(speaker: String, text: String, portrait: String)
signal dialogue_ended

func _ready() -> void:
	# The UI will register itself when ready
	# Get the current scene name
	update_scene_name()
	# Set to always process so timer runs and input is processed
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if input_block_timer > 0:
		input_block_timer -= delta

func _input(_event: InputEvent) -> void:
	# Block ALL inputs during the timer - this runs FIRST before any other input handling
	if input_block_timer > 0:
		get_viewport().set_input_as_handled()
	
func update_scene_name() -> void:
	var root = get_tree().current_scene
	if root:
		current_scene_name = root.name
		print("DialogueManager: Current scene is ", current_scene_name)

func register_ui(ui: CanvasLayer) -> void:
	dialogue_ui = ui
	print("DialogueManager: UI registered")

func start_dialogue(dialogue_name: String, trigger: DialogueTrigger = null, should_pause: bool = true) -> void:
	# Update scene name in case we changed scenes
	update_scene_name()
	
	current_trigger = trigger
	var dialogue_data = load_dialogue(dialogue_name)
	
	if dialogue_data.is_empty():
		print("DialogueManager: Failed to load dialogue: ", dialogue_name)
		return
	
	current_dialogue = dialogue_data
	current_index = 0
	
	if dialogue_ui:
		dialogue_ui.show_dialogue(should_pause)
		show_current_line()
		dialogue_started.emit()
	else:
		print("DialogueManager: No UI registered!")

func load_dialogue(dialogue_name: String) -> Array:
	# Build path: res://dialogue/SCENE_NAME/dialogue_name.json
	var file_path = DIALOGUE_BASE_PATH + current_scene_name + "/"
	
	# Handle both with and without .json extension
	if dialogue_name.ends_with(".json"):
		file_path += dialogue_name
	else:
		file_path += dialogue_name + ".json"
	
	print("DialogueManager: Attempting to load: ", file_path)
	
	if not FileAccess.file_exists(file_path):
		print("DialogueManager: Dialogue file not found: ", file_path)
		return []
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		print("DialogueManager: Failed to open file: ", file_path)
		return []
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("DialogueManager: JSON parse error in ", file_path)
		return []
	
	var data = json.get_data()
	
	if data.has("dialogue") and data["dialogue"] is Array:
		print("DialogueManager: Successfully loaded ", data["dialogue"].size(), " dialogue lines")
		return data["dialogue"]
	
	return []

func show_current_line() -> void:
	if current_index >= current_dialogue.size():
		end_dialogue()
		return
	
	var line = current_dialogue[current_index]
	var speaker = line.get("speaker", "")
	var text = line.get("text", "")
	var portrait = line.get("portrait", "")
	
	dialogue_line_changed.emit(speaker, text, portrait)

func next_line() -> void:
	current_index += 1
	
	if current_index >= current_dialogue.size():
		end_dialogue()
	else:
		show_current_line()

func end_dialogue() -> void:
	if dialogue_ui:
		dialogue_ui.hide_dialogue()
	
	if current_trigger:
		current_trigger.end_dialogue()
		current_trigger = null
	
	current_dialogue.clear()
	current_index = 0
	dialogue_ended.emit()

func is_dialogue_active() -> bool:
	return not current_dialogue.is_empty()
