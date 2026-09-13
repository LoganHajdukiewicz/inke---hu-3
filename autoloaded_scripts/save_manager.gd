extends Node

## SaveManager (autoload) - AUTOSAVE + SAVE SLOTS.
##
## SLOTS: max_slots save slots (default 3 - configurable via the
## "game/saves/max_slots" project setting, or edit the fallback below).
## One slot is ACTIVE at a time; autosaves write into it. The pause menu
## (SAVES tab) offers manual SAVE / LOAD / DELETE per slot.
##
## AUTOSAVE fires at the moments that matter:
##   - CRED is gained (GameManager.cred_collected)
##   - a non-returning collectable is picked up (spray cans, via
##     GameManager.wisp_collected_signal)
## Whenever a save happens, HU3's face fades in at the upper right corner
## for a moment - he IS the save icon.
##
## Saves go to user://save_slot_N.json. Rapid pickups are debounced: at
## most one disk write per second, but nothing is ever lost (a dirty flag
## keeps the last state until it's flushed).

const SLOT_PATH := "user://save_slot_%d.json"
const LEGACY_PATH := "user://save.json"   # pre-slot autosaves migrate to slot 1
const SAVE_DEBOUNCE := 1.0   # Min seconds between disk writes

## Number of save slots. Change the project setting "game/saves/max_slots"
## (or this fallback) to add more.
var max_slots: int = 3
## The slot autosaves write into (1-based). Manual save/load switches it.
var active_slot: int = 1

var _icon_layer: CanvasLayer = null
var _icon: TextureRect = null
var _icon_tween: Tween = null
var _save_cooldown := 0.0
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	max_slots = int(ProjectSettings.get_setting("game/saves/max_slots", 3))
	_migrate_legacy()
	_build_icon()
	# Deferred: make sure the other autoloads finished _ready
	call_deferred("_connect_triggers")


func _migrate_legacy() -> void:
	if FileAccess.file_exists(LEGACY_PATH) and not FileAccess.file_exists(SLOT_PATH % 1):
		var f = FileAccess.open(LEGACY_PATH, FileAccess.READ)
		if f:
			var data := f.get_as_text()
			f.close()
			var out = FileAccess.open(SLOT_PATH % 1, FileAccess.WRITE)
			if out:
				out.store_string(data)
				out.close()
		DirAccess.remove_absolute(LEGACY_PATH)


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
		_write_save(active_slot)


# =========================================================================
# PUBLIC API
# =========================================================================

func request_save() -> void:
	"""Ask for an autosave into the active slot. Debounced - spamming
	pickups won't hammer the disk, but the newest state always lands."""
	if _save_cooldown > 0.0:
		_save_pending = true
		return
	_write_save(active_slot)


func save_to_slot(slot: int) -> bool:
	"""MANUAL SAVE into a specific slot (also makes it the active slot)."""
	if slot < 1 or slot > max_slots:
		return false
	active_slot = slot
	_write_save(slot)
	return true


func delete_slot(slot: int) -> bool:
	"""Delete a slot's save file."""
	var path := SLOT_PATH % slot
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	return true


func has_save(slot: int = -1) -> bool:
	if slot < 1:
		slot = active_slot
	return FileAccess.file_exists(SLOT_PATH % slot)


func get_slot_info(slot: int) -> Dictionary:
	"""For save-menu rows: {exists, timestamp, cred, gears, scene}."""
	var out := {"exists": false, "timestamp": 0, "cred": 0, "gears": 0, "scene": ""}
	var data := _read_slot(slot)
	if data.is_empty():
		return out
	out.exists = true
	out.timestamp = int(data.get("timestamp", 0))
	out.scene = str(data.get("scene", ""))
	var g: Dictionary = data.get("game", {})
	out.cred = int(g.get("CRED", 0))
	out.gears = int(g.get("gear_count", 0))
	return out


func load_slot(slot: int, travel: bool = true) -> bool:
	"""Restore a slot into the managers (and make it active). When travel
	is true, also changes to the saved scene."""
	var data := _read_slot(slot)
	if data.is_empty():
		return false
	active_slot = slot
	
	var gm = get_node_or_null("/root/GameManager")
	if gm and data.has("game"):
		gm.load_game_state(data["game"])
	var qm = get_node_or_null("/root/QuestManager")
	if qm and data.has("quests"):
		var qdata: Dictionary = data["quests"]
		qm.completed_quest_ids = PackedStringArray(qdata.get("completed", []))
		qm.location_flags = qdata.get("location_flags", {})
		# In-hand fetch items: quest items never respawn, so a mid-fetch
		# save must restore the item to Inke's hands
		qm.carried_items = qdata.get("carried", {})
	
	if travel:
		var scene_path := str(data.get("scene", ""))
		var cur = get_tree().current_scene
		if scene_path != "" and ResourceLoader.exists(scene_path) \
				and (cur == null or cur.scene_file_path != scene_path):
			get_tree().change_scene_to_file(scene_path)
	return true


func get_saved_scene_path(slot: int = -1) -> String:
	if slot < 1:
		slot = active_slot
	return str(_read_slot(slot).get("scene", ""))


# =========================================================================
# INTERNALS
# =========================================================================

func _read_slot(slot: int) -> Dictionary:
	if slot < 1 or slot > max_slots:
		return {}
	var path := SLOT_PATH % slot
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _write_save(slot: int) -> void:
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
			"carried": qm.carried_items,
		}
	
	var f = FileAccess.open(SLOT_PATH % slot, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: couldn't write " + SLOT_PATH % slot)
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
