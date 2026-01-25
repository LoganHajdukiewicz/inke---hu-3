extends Node

# FIXED: Updated path to match your actual dialogue location
const DIALOGUE_PATH = "res://dialogue/movement_demo_active_development/"

var current_dialogue: Array = []
var current_index: int = 0
var dialogue_ui: Control = null
var current_trigger: DialogueTrigger = null

signal dialogue_started
signal dialogue_line_changed(speaker: String, text: String, portrait: String)
signal dialogue_ended

func _ready() -> void:
	# The UI will register itself when ready
	pass

func register_ui(ui: Control) -> void:
	dialogue_ui = ui
	print("DialogueManager: UI registered")

func start_dialogue(dialogue_name: String, trigger: DialogueTrigger = null) -> void:
	current_trigger = trigger
	var dialogue_data = load_dialogue(dialogue_name)
	
	if dialogue_data.is_empty():
		print("DialogueManager: Failed to load dialogue: ", dialogue_name)
		return
	
	current_dialogue = dialogue_data
	current_index = 0
	
	if dialogue_ui:
		dialogue_ui.show_dialogue()
		show_current_line()
		dialogue_started.emit()
	else:
		print("DialogueManager: No UI registered!")

func load_dialogue(dialogue_name: String) -> Array:
	# FIXED: Handle both with and without .json extension
	var file_path = DIALOGUE_PATH + dialogue_name
	if not file_path.ends_with(".json"):
		file_path += ".json"
	
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