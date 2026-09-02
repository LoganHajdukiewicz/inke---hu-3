extends Node

# Will be combined with scene-specific paths
const DIALOGUE_BASE_PATH = "res://dialogue/"

## VOICED LINES
## Any dialogue line can set "voiced": true in its JSON to play a voice
## recording alongside the text box. The audio file is looked up at:
##   res://audio/voiced-lines/{scene-we're-in}/{speaker}/{first-five-words-of-the-text}.{ext}
## Words are lowercased and joined with dashes; punctuation is stripped.
## Example: scene Movement_Demo_02_24_2026, speaker S-1GN,
##   text "Oh hey! Wow, you actually stopped..."
##   -> res://audio/voiced-lines/Movement_Demo_02_24_2026/S-1GN/oh-hey-wow-you-actually.ogg
## Supported extensions (tried in order): .ogg, .wav, .mp3
const VOICED_LINES_BASE_PATH = "res://audio/voiced-lines/"
const VOICE_EXTENSIONS = [".ogg", ".wav", ".mp3"]

var voice_player: AudioStreamPlayer = null

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
## Fired when the player answers a choice line (X = accepted, O = denied).
signal choice_made(accepted: bool)

## True while the current line is a choice ("choice": true). The dialogue UI
## switches from "advance on accept" to "X = yes / O = no" handling.
var awaiting_choice: bool = false

func _ready() -> void:
	update_scene_name()
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Dedicated player for voiced dialogue lines (works while tree is paused)
	voice_player = AudioStreamPlayer.new()
	voice_player.name = "VoiceLinePlayer"
	voice_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(voice_player)

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

func register_ui(ui: CanvasLayer) -> void:
	dialogue_ui = ui

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

func start_dialogue_lines(lines: Array, should_pause: bool = true) -> void:
	"""Start a dialogue from an in-memory array of line dictionaries instead
	of a JSON file. Same line format ({speaker, text, portrait, next, id,
	choice}). Used by quest givers and other dynamic speakers."""
	update_scene_name()
	current_trigger = null
	
	if lines.is_empty():
		return
	
	current_dialogue = lines
	current_index = 0
	
	if dialogue_ui:
		dialogue_ui.show_dialogue(should_pause)
		show_current_line()
		dialogue_started.emit()
	else:
		print("DialogueManager: No UI registered!")

func resolve_choice(accepted: bool) -> void:
	"""The UI calls this when the player answers a choice line with X or O.
	Emits choice_made, then ends the conversation."""
	if not awaiting_choice:
		return
	awaiting_choice = false
	choice_made.emit(accepted)
	end_dialogue()

func load_dialogue(dialogue_name: String) -> Array:
	# Build path: res://dialogue/SCENE_NAME/dialogue_name.json
	var file_path = DIALOGUE_BASE_PATH + current_scene_name + "/"
	
	# Handle both with and without .json extension
	if dialogue_name.ends_with(".json"):
		file_path += dialogue_name
	else:
		file_path += dialogue_name + ".json"
	
	
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
	var voiced = line.get("voiced", false)
	awaiting_choice = bool(line.get("choice", false))
	
	# Stop any previous voice line, then play this one if it's voiced
	if voice_player and voice_player.playing:
		voice_player.stop()
	if voiced:
		play_voice_line(speaker, text)
	
	dialogue_line_changed.emit(speaker, text, portrait)

func play_voice_line(speaker: String, text: String) -> void:
	"""Play the voice recording for this line, looked up from
	audio/voiced-lines/{scene}/{speaker}/{first-five-words}.{ext}"""
	var file_base = VOICED_LINES_BASE_PATH + current_scene_name + "/" + speaker + "/" + voice_file_name_for(text)
	for ext in VOICE_EXTENSIONS:
		var path = file_base + ext
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStream:
				voice_player.stream = stream
				voice_player.play()
				return
	print("DialogueManager: voiced line audio not found: ", file_base, " (.ogg/.wav/.mp3)")

static func voice_file_name_for(text: String) -> String:
	"""First five words of the line, lowercased, punctuation stripped,
	joined with dashes. 'Oh hey! Wow, you actually stopped' ->
	'oh-hey-wow-you-actually'"""
	var cleaned = ""
	for c in text.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == " " or c == "'":
			cleaned += c if c != "'" else ""
		else:
			cleaned += " "  # Punctuation acts as a word break
	var words = cleaned.split(" ", false)
	var first_five = []
	for w in words:
		first_five.append(w)
		if first_five.size() >= 5:
			break
	return "-".join(first_five)

func next_line() -> void:
	# Optional branching: a line may carry "next": "<id>" pointing at another
	# line's "id", or "next": "end" to stop the conversation right there.
	# Without "next", flow falls through to the following line in the array
	# (the default, fully backward-compatible behavior).
	if current_index < current_dialogue.size():
		var line = current_dialogue[current_index]
		var jump = str(line.get("next", ""))
		if jump == "end":
			end_dialogue()
			return
		elif jump != "":
			var idx = _find_line_by_id(jump)
			if idx >= 0:
				current_index = idx
				show_current_line()
				return
			push_warning("DialogueManager: 'next' id not found: " + jump)
	
	current_index += 1
	
	if current_index >= current_dialogue.size():
		end_dialogue()
	else:
		show_current_line()

func _find_line_by_id(line_id: String) -> int:
	"""Index of the dialogue line whose \"id\" matches, or -1."""
	for i in range(current_dialogue.size()):
		if str(current_dialogue[i].get("id", "")) == line_id:
			return i
	return -1

func end_dialogue() -> void:
	awaiting_choice = false
	if voice_player and voice_player.playing:
		voice_player.stop()
	if dialogue_ui:
		dialogue_ui.hide_dialogue()
	
	if current_trigger:
		current_trigger.end_dialogue()
		current_trigger = null
	
	current_dialogue.clear()
	current_index = 0
	
	# Briefly swallow all input so the button press that closed the dialogue
	# doesn't leak into gameplay (e.g. making the player jump)
	input_block_timer = input_block_duration
	
	dialogue_ended.emit()

func is_dialogue_active() -> bool:
	return not current_dialogue.is_empty()
