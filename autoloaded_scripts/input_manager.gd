extends Node

## INPUT MANAGER (autoload)
## ---------------------------------------------------------------------------
## One place for everything input:
##  1. DEVICE DETECTION - tracks whether the player last touched keyboard/mouse
##     or a controller, and broadcasts `device_changed` so every prompt in the
##     game can swap between "[E]" and "[□]" live.
##  2. PROMPT GLYPHS - `prompt("interact")` returns the right label for the
##     active device (DualShock 4 glyphs on pad, key names on keyboard).
##  3. REBINDING - `apply_rebind(action, event)` swaps a binding (keyboard
##     events replace keyboard bindings, pad events replace pad bindings),
##     persists to user://input_bindings.cfg and restores it on boot.
##
## See docs/INPUT_MAP.md for the full DualShock 4 layout.

signal device_changed(device: String)      # "keyboard" | "joypad"
signal bindings_changed                    # After any rebind / reset

const SAVE_PATH := "user://input_bindings.cfg"

var active_device: String = "keyboard"

## Actions the player is allowed to rebind, with display names.
## (Movement stick axes and ui_* navigation stay fixed so you can never
## soft-lock yourself out of the menus.)
const REBINDABLE := {
	"jump":         "Jump",
	"dash":         "Dash / Dodge",
	"attack":       "Attack",
	"heavy_attack": "Heavy Attack",
	"yoyo":         "Yo-yo / Grapple",
	"crouch":       "Crouch / Slam",
	"run":          "Run",
	"interact":     "Interact / Talk",
	"spray":        "Spray Paint",
	"lock_on":      "Lock-On",
	"start":        "Pause",
}

## DualShock 4 button names by Godot joy button index.
const DS4_BUTTONS := {
	0: "X",           # Cross
	1: "O",           # Circle
	2: "□",           # Square
	3: "TRI",         # Triangle
	4: "SHARE",
	5: "PS",
	6: "OPTIONS",
	7: "L3",
	8: "R3",
	9: "L1",
	10: "R1",
	11: "D-PAD ↑",
	12: "D-PAD ↓",
	13: "D-PAD ←",
	14: "D-PAD →",
	15: "TOUCHPAD",
}

## DualShock 4 axis names (positive direction unless noted).
const DS4_AXES := {
	0: "L-STICK ↔",
	1: "L-STICK ↕",
	2: "R-STICK ↔",
	3: "R-STICK ↕",
	4: "L2",
	5: "R2",
}

var _defaults: Dictionary = {}   # action -> Array[InputEvent] (project defaults)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Snapshot project defaults BEFORE loading user overrides
	for action in InputMap.get_actions():
		_defaults[action] = InputMap.action_get_events(action).duplicate()
	_load_bindings()
	# If a pad is already plugged in, assume they'll use it
	if Input.get_connected_joypads().size() > 0:
		active_device = "joypad"

func _input(event: InputEvent):
	if event is InputEventJoypadButton:
		_set_device("joypad")
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		_set_device("joypad")
	elif event is InputEventKey and event.pressed:
		_set_device("keyboard")
	elif event is InputEventMouseButton and event.pressed:
		_set_device("keyboard")

func _set_device(dev: String):
	if active_device == dev:
		return
	active_device = dev
	device_changed.emit(dev)

func is_using_controller() -> bool:
	return active_device == "joypad"

# ============================================================================
# PROMPT GLYPHS
# ============================================================================

## The label for an action on the ACTIVE device, e.g. "E" or "□".
func button_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if is_using_controller():
		for ev in events:
			if ev is InputEventJoypadButton:
				return DS4_BUTTONS.get(ev.button_index, "BTN %d" % ev.button_index)
			if ev is InputEventJoypadMotion:
				return DS4_AXES.get(ev.axis, "AXIS %d" % ev.axis)
		# No pad binding at all - fall through to keyboard label
	for ev in events:
		if ev is InputEventKey:
			return _key_name(ev)
		if ev is InputEventMouseButton:
			return _mouse_name(ev.button_index)
	return "?"

## "[E]" / "[□]" - the standard bracketed prompt chip.
func prompt(action: String) -> String:
	return "[" + button_label(action) + "]"

## Label for one specific event (used by the rebind menu lists).
func event_label(ev: InputEvent) -> String:
	if ev is InputEventJoypadButton:
		return DS4_BUTTONS.get(ev.button_index, "BTN %d" % ev.button_index)
	if ev is InputEventJoypadMotion:
		var n: String = DS4_AXES.get(ev.axis, "AXIS %d" % ev.axis)
		if ev.axis <= 3:
			n += "+" if ev.axis_value > 0 else "-"
		return n
	if ev is InputEventKey:
		return _key_name(ev)
	if ev is InputEventMouseButton:
		return _mouse_name(ev.button_index)
	return "?"

## Keyboard + pad labels for an action, e.g. {"kb": "E", "pad": "□"}
func binding_labels(action: String) -> Dictionary:
	var kb := "—"
	var pad := "—"
	for ev in InputMap.action_get_events(action):
		if (ev is InputEventKey or ev is InputEventMouseButton) and kb == "—":
			kb = event_label(ev)
		elif (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and pad == "—":
			pad = event_label(ev)
	return {"kb": kb, "pad": pad}

func _key_name(ev: InputEventKey) -> String:
	var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
	var name: String
	if ev.physical_keycode != KEY_NONE:
		name = OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(ev.physical_keycode))
	else:
		name = OS.get_keycode_string(ev.keycode)
	if name.is_empty():
		name = OS.get_keycode_string(code)
	match name:
		" ": return "SPACE"
		"": return "?"
	return name.to_upper()

func _mouse_name(idx: int) -> String:
	match idx:
		MOUSE_BUTTON_LEFT: return "LMB"
		MOUSE_BUTTON_RIGHT: return "RMB"
		MOUSE_BUTTON_MIDDLE: return "MMB"
		_: return "MOUSE %d" % idx

# ============================================================================
# REBINDING
# ============================================================================

## Replace the binding of `action` that matches the DEVICE of `event`:
## a key/mouse event replaces the keyboard binding, a pad event replaces the
## pad binding. The other device's binding is untouched.
func apply_rebind(action: String, event: InputEvent) -> bool:
	if not REBINDABLE.has(action):
		return false
	if not (event is InputEventKey or event is InputEventMouseButton \
			or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		return false
	# Triggers/sticks: normalize the axis value to a clean ±1
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) < 0.5:
			return false   # Noise, not a deliberate press
		event = event.duplicate()
		event.axis_value = signf(event.axis_value)
	
	var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	var kept: Array[InputEvent] = []
	for ev in InputMap.action_get_events(action):
		var ev_is_pad = ev is InputEventJoypadButton or ev is InputEventJoypadMotion
		if ev_is_pad != is_pad:
			kept.append(ev)
	InputMap.action_erase_events(action)
	for ev in kept:
		InputMap.action_add_event(action, ev)
	InputMap.action_add_event(action, event)
	_save_bindings()
	bindings_changed.emit()
	return true

## Restore every rebindable action to the project defaults.
func reset_to_defaults():
	for action in REBINDABLE:
		if not _defaults.has(action):
			continue
		InputMap.action_erase_events(action)
		for ev in _defaults[action]:
			InputMap.action_add_event(action, ev)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	bindings_changed.emit()

# ============================================================================
# PERSISTENCE
# ============================================================================

func _save_bindings():
	var cfg := ConfigFile.new()
	for action in REBINDABLE:
		var serialized: Array = []
		for ev in InputMap.action_get_events(action):
			var d := _event_to_dict(ev)
			if not d.is_empty():
				serialized.append(d)
		cfg.set_value("bindings", action, serialized)
	cfg.save(SAVE_PATH)

func _load_bindings():
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for action in REBINDABLE:
		if not cfg.has_section_key("bindings", action):
			continue
		var serialized: Array = cfg.get_value("bindings", action, [])
		if serialized.is_empty():
			continue
		InputMap.action_erase_events(action)
		for d in serialized:
			var ev := _dict_to_event(d)
			if ev:
				InputMap.action_add_event(action, ev)

func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"kind": "key", "physical": ev.physical_keycode, "keycode": ev.keycode}
	if ev is InputEventMouseButton:
		return {"kind": "mouse", "index": ev.button_index}
	if ev is InputEventJoypadButton:
		return {"kind": "joy_button", "index": ev.button_index}
	if ev is InputEventJoypadMotion:
		return {"kind": "joy_axis", "axis": ev.axis, "value": ev.axis_value}
	return {}

func _dict_to_event(d: Dictionary) -> InputEvent:
	match d.get("kind", ""):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("physical", 0))
			k.keycode = int(d.get("keycode", 0))
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(d.get("index", 1))
			return m
		"joy_button":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(d.get("index", 0))
			return jb
		"joy_axis":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(d.get("axis", 0))
			jm.axis_value = float(d.get("value", 1.0))
			return jm
	return null
