extends Node

## QuestManager (autoload)
##
## Owns everything quest-related:
##  - active quest tracking + progress (gears, kills, flags, fetch items)
##  - LOCATION FLAGS: a persistent "the player has been here" set. LocationFlag
##    areas call set_location_flag(); anything can query has_location_flag().
##    Works with or without a quest attached.
##  - quest completion -> a CRED (worth the quest's cred_reward) pops into
##    existence in front of the player
##  - HUD: active-quest tracker (top right), notification banner, and the
##    CRED bar that appears for a moment whenever CRED changes. When the bar
##    is full, boss_fight_ready fires (boss fight itself comes later).

signal quest_accepted(quest: Quest)
signal quest_progressed(quest: Quest, current: int, goal: int)
signal quest_completed(quest: Quest)
signal quest_failed(quest: Quest)
signal location_flag_set(flag_id: String)
signal boss_fight_ready

## CRED needed to unlock the boss fight (fills the HUD bar).
var cred_needed_for_boss: int = 50
var boss_ready: bool = false

var cred_scene: PackedScene = preload("res://scenes/items/Collectibles/cred.tscn")

# Active quest entries: { quest: Quest, progress: int, gear_baseline: int,
#                         time_left: float, item_held: bool }
var active_quests: Array[Dictionary] = []
var completed_quest_ids: PackedStringArray = []
var failed_quest_ids: PackedStringArray = []   # failed at least once, not yet completed
var location_flags: Dictionary = {}   # flag_id -> true
var carried_items: Dictionary = {}    # item_id -> true (fetch quest items in hand)

# --- HUD ---
var hud: CanvasLayer
var tracker_panel: PanelContainer
var tracker_label: Label
var notify_label: Label
var cred_panel: PanelContainer
var cred_bar: ProgressBar
var cred_label: Label
var _cred_hide_timer: float = 0.0
var _notify_tween: Tween


func _ready() -> void:
	_build_hud()
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.gear_collected.connect(_on_gear_collected)
		gm.cred_collected.connect(_on_cred_collected)


func _process(delta: float) -> void:
	# Time limits
	var failed: Array[Dictionary] = []
	for entry in active_quests:
		var q: Quest = entry.quest
		if q.has_time_limit:
			entry.time_left -= delta
			if entry.time_left <= 0.0:
				failed.append(entry)
	for entry in failed:
		_fail_quest(entry)
	
	_update_tracker()
	
	# CRED bar auto-hide
	if _cred_hide_timer > 0.0:
		_cred_hide_timer -= delta
		if _cred_hide_timer <= 0.0 and not boss_ready:
			var t = create_tween()
			t.tween_property(cred_panel, "modulate:a", 0.0, 0.4)


# =========================================================================
# PUBLIC API
# =========================================================================

func accept_quest(quest: Quest, _giver: Node = null) -> bool:
	if quest == null or quest.quest_id == "":
		push_warning("QuestManager: quest needs a quest_id")
		return false
	if is_quest_active(quest.quest_id):
		return false
	if is_quest_completed(quest.quest_id) and not quest.repeatable:
		return false
	
	var gm = get_node_or_null("/root/GameManager")
	var entry := {
		"quest": quest,
		"progress": 0,
		"gear_baseline": gm.gear_count if gm else 0,
		"time_left": quest.time_limit_seconds,
		"item_held": false,
	}
	active_quests.append(entry)
	
	# Retaking a previously failed quest
	var fail_idx = failed_quest_ids.find(quest.quest_id)
	if fail_idx != -1:
		failed_quest_ids.remove_at(fail_idx)
	
	match quest.quest_type:
		Quest.QuestType.REACH_LOCATION:
			# Already been there? Complete right away.
			if location_flags.has(quest.target_id):
				call_deferred("_complete_quest", entry)
		Quest.QuestType.FETCH_ITEM:
			# Already holding it? Just needs the return trip.
			if carried_items.has(quest.target_id):
				entry.item_held = true
	
	quest_accepted.emit(quest)
	show_notification("NEW QUEST: " + quest.title, Color(0.4, 0.85, 1.0))
	return true


func is_quest_active(quest_id: String) -> bool:
	for entry in active_quests:
		if entry.quest.quest_id == quest_id:
			return true
	return false


func is_quest_completed(quest_id: String) -> bool:
	return completed_quest_ids.has(quest_id)


func has_quest_failed(quest_id: String) -> bool:
	return failed_quest_ids.has(quest_id)


func get_active_entry(quest_id: String) -> Dictionary:
	for entry in active_quests:
		if entry.quest.quest_id == quest_id:
			return entry
	return {}


## FETCH quests: the giver calls this when the player talks to them.
## Returns true (and completes the quest) if the item is in hand.
func try_turn_in(quest_id: String) -> bool:
	var entry = get_active_entry(quest_id)
	if entry.is_empty():
		return false
	var q: Quest = entry.quest
	if q.quest_type != Quest.QuestType.FETCH_ITEM:
		return false
	if not entry.item_held:
		return false
	carried_items.erase(q.target_id)
	_complete_quest(entry)
	return true


# --- Location flags ("the player has been here") ---

func set_location_flag(flag_id: String) -> void:
	if flag_id == "" or location_flags.has(flag_id):
		return
	location_flags[flag_id] = true
	location_flag_set.emit(flag_id)
	
	for entry in active_quests.duplicate():
		var q: Quest = entry.quest
		if q.quest_type == Quest.QuestType.REACH_LOCATION and q.target_id == flag_id:
			_complete_quest(entry)


func has_location_flag(flag_id: String) -> bool:
	return location_flags.has(flag_id)


# --- Event hooks (called by enemies / items / GameManager signals) ---

func notify_enemy_defeated(enemy: Node) -> void:
	"""Called by every dying enemy. DEFEAT_ENEMY quests 'elect' their targets:
	each quest checks whether this particular kill matches its configured
	enemy type / boss flag / enemy_id and counts it if so."""
	if enemy == null:
		return
	for entry in active_quests.duplicate():
		var q: Quest = entry.quest
		if q.enemy_counts_for_quest(enemy):
			entry.progress += 1
			quest_progressed.emit(q, entry.progress, q.goal_count())
			if entry.progress >= q.goal_count():
				_complete_quest(entry)


func notify_item_grabbed(item_id: String) -> void:
	if item_id == "":
		return
	carried_items[item_id] = true
	for entry in active_quests:
		var q: Quest = entry.quest
		if q.quest_type == Quest.QuestType.FETCH_ITEM and q.target_id == item_id and not entry.item_held:
			entry.item_held = true
			quest_progressed.emit(q, 1, 1)
			show_notification("Got it! Return to the quest giver.", Color(1.0, 0.9, 0.3))


func _on_gear_collected(total_gears: int) -> void:
	for entry in active_quests.duplicate():
		var q: Quest = entry.quest
		if q.quest_type != Quest.QuestType.COLLECT_GEARS:
			continue
		var collected = total_gears - entry.gear_baseline
		var new_progress = clampi(collected, 0, q.goal_count())
		if new_progress != entry.progress:
			entry.progress = new_progress
			quest_progressed.emit(q, entry.progress, q.goal_count())
			if entry.progress >= q.goal_count():
				_complete_quest(entry)


# =========================================================================
# COMPLETION / FAILURE
# =========================================================================

func _complete_quest(entry: Dictionary) -> void:
	if not active_quests.has(entry):
		return
	active_quests.erase(entry)
	var q: Quest = entry.quest
	if not completed_quest_ids.has(q.quest_id):
		completed_quest_ids.append(q.quest_id)
	
	var fail_idx = failed_quest_ids.find(q.quest_id)
	if fail_idx != -1:
		failed_quest_ids.remove_at(fail_idx)
	
	quest_completed.emit(q)
	show_notification("QUEST COMPLETE: " + q.title, Color(0.4, 1.0, 0.5))
	_spawn_reward_cred(q.cred_reward)


func _fail_quest(entry: Dictionary) -> void:
	if not active_quests.has(entry):
		return
	active_quests.erase(entry)
	var q: Quest = entry.quest
	if not failed_quest_ids.has(q.quest_id):
		failed_quest_ids.append(q.quest_id)
	# Failed fetch: the item stays in hand only if they grabbed it; keep it -
	# retaking the quest picks up where they left off.
	quest_failed.emit(q)
	show_notification("QUEST FAILED: " + q.title, Color(1.0, 0.35, 0.3))


func _spawn_reward_cred(reward: int) -> void:
	"""The reward CRED appears right in front of the player."""
	var gm = get_node_or_null("/root/GameManager")
	var player = gm.player if gm else null
	if not player or not is_instance_valid(player) or not player.is_inside_tree():
		# No player? Bank it directly so the reward is never lost.
		if gm:
			gm.add_CRED(reward)
		return
	
	var cred = cred_scene.instantiate()
	cred.cred_value = reward
	player.get_parent().add_child(cred)
	
	var forward = -player.global_transform.basis.z.normalized()
	cred.global_position = player.global_position + forward * 3.0 + Vector3(0, 1.0, 0)
	
	cred.scale = Vector3(0.05, 0.05, 0.05)
	var tween = cred.create_tween()
	tween.tween_property(cred, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)



# =========================================================================
# HUD
# =========================================================================

func _on_cred_collected(_amount: int, total_cred: int) -> void:
	_show_cred_bar(total_cred)
	if total_cred >= cred_needed_for_boss and not boss_ready:
		boss_ready = true
		boss_fight_ready.emit()
		show_notification("CRED BAR FULL - BOSS FIGHT UNLOCKED!", Color(1.0, 0.55, 1.0))


func _show_cred_bar(total_cred: int) -> void:
	cred_panel.modulate.a = 1.0
	_cred_hide_timer = 3.5
	cred_label.text = "CRED  %d / %d" % [mini(total_cred, cred_needed_for_boss), cred_needed_for_boss]
	if boss_ready:
		cred_label.text = "CRED FULL - BOSS READY"
	var t = create_tween()
	t.tween_property(cred_bar, "value", clampf(float(total_cred) / float(cred_needed_for_boss) * 100.0, 0.0, 100.0), 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func show_notification(text: String, color: Color = Color.WHITE) -> void:
	notify_label.text = text
	notify_label.modulate = color
	notify_label.modulate.a = 0.0
	if _notify_tween:
		_notify_tween.kill()
	_notify_tween = create_tween()
	_notify_tween.tween_property(notify_label, "modulate:a", 1.0, 0.25)
	_notify_tween.tween_interval(2.5)
	_notify_tween.tween_property(notify_label, "modulate:a", 0.0, 0.6)


func _update_tracker() -> void:
	if active_quests.is_empty():
		tracker_panel.visible = false
		return
	tracker_panel.visible = true
	var lines: Array[String] = []
	for entry in active_quests:
		var q: Quest = entry.quest
		var line = q.title
		match q.quest_type:
			Quest.QuestType.COLLECT_GEARS:
				line += "  —  gears %d/%d" % [entry.progress, q.goal_count()]
			Quest.QuestType.DEFEAT_ENEMY:
				line += "  —  defeated %d/%d" % [entry.progress, q.goal_count()]
			Quest.QuestType.REACH_LOCATION:
				line += "  —  reach the spot"
			Quest.QuestType.FETCH_ITEM:
				line += "  —  " + ("return to giver!" if entry.item_held else "find the item")
		if q.has_time_limit:
			line += "   [%d:%02d]" % [int(entry.time_left) / 60, int(entry.time_left) % 60]
		lines.append(line)
	tracker_label.text = "\n".join(lines)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 40
	add_child(hud)
	
	# --- Quest tracker (top right) ---
	tracker_panel = PanelContainer.new()
	tracker_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tracker_panel.offset_left = -420
	tracker_panel.offset_right = -16
	tracker_panel.offset_top = 16
	tracker_panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.75)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	tracker_panel.add_theme_stylebox_override("panel", style)
	hud.add_child(tracker_panel)
	
	var vbox = VBoxContainer.new()
	tracker_panel.add_child(vbox)
	var header = Label.new()
	header.text = "QUESTS"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	vbox.add_child(header)
	tracker_label = Label.new()
	tracker_label.add_theme_font_size_override("font_size", 16)
	tracker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tracker_label)
	
	# --- Notification banner (upper middle) ---
	notify_label = Label.new()
	notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notify_label.offset_top = 90
	notify_label.offset_bottom = 140
	notify_label.offset_left = -400
	notify_label.offset_right = 400
	notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify_label.add_theme_font_size_override("font_size", 30)
	notify_label.add_theme_constant_override("outline_size", 10)
	notify_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	notify_label.modulate.a = 0.0
	hud.add_child(notify_label)
	
	# --- CRED bar (bottom center, appears for a moment) ---
	cred_panel = PanelContainer.new()
	cred_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cred_panel.offset_left = -220
	cred_panel.offset_right = 220
	cred_panel.offset_top = -90
	cred_panel.offset_bottom = -34
	var cstyle = StyleBoxFlat.new()
	cstyle.bg_color = Color(0.06, 0.06, 0.1, 0.8)
	cstyle.corner_radius_top_left = 10
	cstyle.corner_radius_top_right = 10
	cstyle.corner_radius_bottom_left = 10
	cstyle.corner_radius_bottom_right = 10
	cstyle.content_margin_left = 14
	cstyle.content_margin_right = 14
	cstyle.content_margin_top = 6
	cstyle.content_margin_bottom = 8
	cred_panel.add_theme_stylebox_override("panel", cstyle)
	cred_panel.modulate.a = 0.0
	hud.add_child(cred_panel)
	
	var cvbox = VBoxContainer.new()
	cred_panel.add_child(cvbox)
	cred_label = Label.new()
	cred_label.text = "CRED"
	cred_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cred_label.add_theme_font_size_override("font_size", 15)
	cred_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	cvbox.add_child(cred_label)
	cred_bar = ProgressBar.new()
	cred_bar.min_value = 0
	cred_bar.max_value = 100
	cred_bar.value = 0
	cred_bar.show_percentage = false
	cred_bar.custom_minimum_size = Vector2(0, 14)
	var fill = StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.75, 0.2)
	fill.corner_radius_top_left = 6
	fill.corner_radius_top_right = 6
	fill.corner_radius_bottom_left = 6
	fill.corner_radius_bottom_right = 6
	cred_bar.add_theme_stylebox_override("fill", fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	bg.corner_radius_top_left = 6
	bg.corner_radius_top_right = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	cred_bar.add_theme_stylebox_override("background", bg)
	cvbox.add_child(cred_bar)
