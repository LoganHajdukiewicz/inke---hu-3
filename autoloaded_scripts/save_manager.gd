extends Node

## SaveManager (autoload) - AUTOSAVE.
##
## The game saves itself at the moments that matter:
##   - CRED is gained (GameManager.cred_collected)
##   - a non-returning collectable is picked up (spray cans, via
##     GameManager.wisp_collected_signal)
## Whenever a save happens, HU3's face fades in at the upper right corner
## for a moment - he IS the save icon.
##
## Saves go to user://save.json. Rapid pickups are debounced: at most one
## disk write per second, but nothing is ever lost (a dirty flag keeps the
## last state until it's flushed).

const SAVE_PATH := "user://save.json"
const SAVE_DEBOUNCE := 1.0   # Min seconds between disk writes

var _icon_layer: CanvasLayer = null
var _icon: TextureRect = null
var _icon_tween: Tween = null
var _save_cooldown := 0.0
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_icon()
	# Deferred: make sure the other autoloads finished _ready
	call_deferred("_connect_triggers")


func _connect_triggers() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		# AUTOSAVE TRIGGER 1: CRED gained
		if gm.has_signal("cred_collected"):
			gm.cred_collected.connect(func(_a, _t): request_save())
		# AUTOSAVE TRIGGER 2: spray can (non-returning collectable) collected
		if gm.has_signal("wisp_collected_signal"):
			gm.wisp_collected_signal.connect(func(_c, _t): request_save())


func _process(delta: float) -> void:
	if _save_cooldown > 0.0:
		_save_cooldown -= delta
	if _save_pending and _save_cooldown <= 0.0:
		_save_pending = false
		_write_save()


# =========================================================================
# PUBLIC API
# =========================================================================

func request_save() -> void:
	"""Ask for an autosave. Debounced - spamming pickups won't hammer the
	disk, but the newest state always ends up saved."""
	if _save_cooldown > 0.0:
		_save_pending = true
		return
	_write_save()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_last_save() -> bool:
	"""Restore the last autosave into the managers (does NOT change scene -
	callers decide whether to also travel to the saved scene)."""
	if not has_save():
		return false
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return false
	
	var gm = get_node_or_null("/root/GameManager")
	if gm and parsed.has("game"):
		gm.load_game_state(parsed["game"])
	var qm = get_node_or_null("/root/QuestManager")
	if qm and parsed.has("quests"):
		var qdata: Dictionary = parsed["quests"]
		qm.completed_quest_ids = PackedStringArray(qdata.get("completed", []))
		qm.location_flags = qdata.get("location_flags", {})
	return true


func get_saved_scene_path() -> String:
	if not has_save():
		return ""
	var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed.get("scene", "") if parsed is Dictionary else ""


# =========================================================================
# INTERNALS
# =========================================================================

func _write_save() -> void:
	_save_cooldown = SAVE_DEBOUNCE
	var data := {"version": 1, "timestamp": Time.get_unix_time_from_system()}
	
	var scene = get_tree().current_scene
	if scene and scene.scene_file_path != "":
		data["scene"] = scene.scene_file_path
	
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		data["game"] = gm.save_game_state()
	var qm = get_node_or_null("/root/QuestManager")
	if qm:
		data["quests"] = {
			"completed": Array(qm.completed_quest_ids),
			"location_flags": qm.location_flags,
		}
	
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: couldn't write " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	_flash_icon()


func _build_icon() -> void:
	"""HU3's face, upper right corner - the autosave indicator."""
	_icon_layer = CanvasLayer.new()
	_icon_layer.layer = 95
	add_child(_icon_layer)
	
	_icon = TextureRect.new()
	var tex = load("res://assets/UI/hu3_face.svg")
	if tex:
		_icon.texture = tex
	_icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_icon.custom_minimum_size = Vector2(44, 44)
	_icon.offset_left = -60
	_icon.offset_right = -16
	_icon.offset_top = 16
	_icon.offset_bottom = 60
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.modulate.a = 0.0
	_icon.pivot_offset = Vector2(22, 22)
	_icon_layer.add_child(_icon)


func _flash_icon() -> void:
	"""Fade HU3 in, tiny bounce, hold, fade out."""
	if _icon == null:
		return
	if _icon_tween and _icon_tween.is_valid():
		_icon_tween.kill()
	_icon.modulate.a = 0.0
	_icon.scale = Vector2(0.6, 0.6)
	_icon_tween = create_tween()
	_icon_tween.set_parallel(true)
	_icon_tween.tween_property(_icon, "modulate:a", 1.0, 0.25)
	_icon_tween.tween_property(_icon, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_icon_tween.set_parallel(false)
	_icon_tween.tween_interval(1.1)
	_icon_tween.tween_property(_icon, "modulate:a", 0.0, 0.5)
