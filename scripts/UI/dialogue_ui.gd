extends CanvasLayer

const PORTRAITS_PATH = "res://assets/portraits/"

## RIPPED PAPER LOOK: the textbox is drawn as a sheet of paper someone
## tore a hole out of - jagged random edges, a torn-through dark gap
## behind, and a drop shadow. Uncheck for the plain rounded panel.
@export var ripped_paper_look: bool = true:
	set(v):
		ripped_paper_look = v
		if is_inside_tree():
			_apply_ripped_look()
## Paper color used by the ripped look.
@export var paper_color: Color = Color(0.918, 0.894, 0.839)
## How deep the tears cut into the edge (pixels).
@export var tear_depth: float = 14.0
## Average length of each tear segment (pixels). Smaller = busier edge.
@export var tear_segment: float = 34.0

var _torn_main: Control = null
var _torn_wall: Control = null
var _plain_style_main: StyleBox = null
var _plain_style_wall: StyleBox = null

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
	
	# Remember the plain panel styles so the checkbox can restore them
	var main_box = dialogue_container.get_node_or_null("DialogueBox")
	if main_box:
		_plain_style_main = main_box.get_theme_stylebox("panel")
	var wall_box = wall_dialogue_container.get_node_or_null("WallDialogueBox") if wall_dialogue_container else null
	if wall_box:
		_plain_style_wall = wall_box.get_theme_stylebox("panel")
	_apply_ripped_look()
	
	DialogueManager.register_ui(self)
	DialogueManager.dialogue_line_changed.connect(_on_dialogue_line_changed)
	
	# Make continue indicator blink
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.5)
	tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.5)


# ---------------------------------------------------------------------------
# Ripped paper look
# ---------------------------------------------------------------------------
func _apply_ripped_look() -> void:
	var main_box = dialogue_container.get_node_or_null("DialogueBox") if dialogue_container else null
	var wall_box = wall_dialogue_container.get_node_or_null("WallDialogueBox") if wall_dialogue_container else null
	if ripped_paper_look:
		# Hide the flat panel styles; draw torn paper behind the content.
		var empty := StyleBoxEmpty.new()
		if main_box:
			main_box.add_theme_stylebox_override("panel", empty)
			if _torn_main == null or not is_instance_valid(_torn_main):
				_torn_main = TornPaper.new(self)
				main_box.add_child(_torn_main)
				main_box.move_child(_torn_main, 0)
		if wall_box:
			wall_box.add_theme_stylebox_override("panel", empty)
			if _torn_wall == null or not is_instance_valid(_torn_wall):
				_torn_wall = TornPaper.new(self)
				wall_box.add_child(_torn_wall)
				wall_box.move_child(_torn_wall, 0)
	else:
		if main_box and _plain_style_main:
			main_box.add_theme_stylebox_override("panel", _plain_style_main)
		if wall_box and _plain_style_wall:
			wall_box.add_theme_stylebox_override("panel", _plain_style_wall)
		if _torn_main and is_instance_valid(_torn_main):
			_torn_main.queue_free(); _torn_main = null
		if _torn_wall and is_instance_valid(_torn_wall):
			_torn_wall.queue_free(); _torn_wall = null


class TornPaper extends Control:
	## Draws a sheet of paper with ripped edges: someone tore a hole out of
	## a page and the text lives in it. Three layers - drop shadow, a darker
	## 'torn through' back sheet peeking out, and the paper itself - each
	## with its own jagged outline so the tears look layered and hand-made.
	var ui
	var _pts_shadow: PackedVector2Array
	var _pts_back: PackedVector2Array
	var _pts_paper: PackedVector2Array
	var _built_for := Vector2.ZERO
	
	func _init(owner_ui):
		ui = owner_ui
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true
	
	func _notification(what):
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
	
	func _rip_outline(rect: Rect2, depth: float, seg: float, seed_val: int) -> PackedVector2Array:
		# Walk the rect's border, jittering each step inward by a random
		# amount - a torn edge. Deterministic per seed so it doesn't flicker.
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val
		var pts := PackedVector2Array()
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in range(4):
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			var edge_len := a.distance_to(b)
			var steps := maxi(int(edge_len / maxf(seg, 8.0)), 2)
			var inward := (rect.get_center() - (a + b) * 0.5).normalized()
			for s in range(steps):
				var t := float(s) / steps
				var p := a.lerp(b, t)
				if s > 0:   # keep corners sharp-ish
					p += inward * rng.randf_range(0.0, depth)
					# slight along-edge wobble so tears aren't evenly spaced
					p += (b - a).normalized() * rng.randf_range(-seg * 0.2, seg * 0.2)
				pts.append(p)
		return pts
	
	func _rebuild(sz: Vector2):
		_built_for = sz
		var depth: float = ui.tear_depth
		var seg: float = ui.tear_segment
		_pts_shadow = _rip_outline(Rect2(Vector2(6, 8), sz - Vector2(2, 4)), depth, seg, 1111)
		_pts_back = _rip_outline(Rect2(Vector2(-4, -4), sz + Vector2(8, 8)), depth * 0.8, seg * 1.3, 2222)
		_pts_paper = _rip_outline(Rect2(Vector2.ZERO, sz), depth, seg, 3333)
	
	func _draw():
		var sz := size
		if sz.x < 4 or sz.y < 4:
			return
		if _built_for != sz:
			_rebuild(sz)
		var paper: Color = ui.paper_color
		# Drop shadow of the sheet
		draw_colored_polygon(_pts_shadow, Color(0, 0, 0, 0.35))
		# Darker 'torn through' backing sheet peeking around the edges
		draw_colored_polygon(_pts_back, paper.darkened(0.55))
		# The paper itself
		draw_colored_polygon(_pts_paper, paper)
		# Soft edge shading so the tear reads as fibrous depth
		var outline := _pts_paper.duplicate()
		outline.append(outline[0])
		draw_polyline(outline, paper.darkened(0.25), 2.0, true)


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
	
	# Choice lines: X (jump/Cross) accepts, O (dash/Circle) denies
	if DialogueManager.awaiting_choice:
		if is_typing and (event.is_action_pressed("ui_accept") or event.is_action_pressed("jump")):
			finish_typing()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
			DialogueManager.resolve_choice(true)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("dash") or event.is_action_pressed("ui_cancel"):
			DialogueManager.resolve_choice(false)
			get_viewport().set_input_as_handled()
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
	else:
		# Show regular dialogue UI
		dialogue_container.visible = true
		if wall_dialogue_container:
			wall_dialogue_container.visible = false
		# Pause game if requested
		get_tree().paused = true


func _on_dialogue_line_changed(speaker: String, text: String, portrait: String) -> void:
	
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
		# Choice lines show the X/O prompt instead of the continue arrow
		if DialogueManager.awaiting_choice:
			continue_indicator.visible = false
			text_label.text = current_text + "\n\n[X] Accept        [O] Not now"
