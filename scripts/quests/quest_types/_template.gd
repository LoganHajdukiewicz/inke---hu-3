extends QuestTypeHandler

## ============================================================================
## QUEST TYPE TEMPLATE - copy this file to make a new quest type!
## ============================================================================
##
## HOW TO USE:
##   1. Duplicate this file in scripts/quests/quest_types/
##   2. Rename it to your type (e.g. break_boxes.gd - the filename doesn't
##      matter mechanically, but keep it matching type_id() for sanity)
##   3. Change type_id() to a unique snake_case name
##   4. Fill in the hooks you need, delete the ones you don't
##   5. Done - it AUTOMATICALLY appears in the quest_type dropdown on every
##      Quest resource. No enum edits, no registration anywhere.
##
## (Files starting with "_" and quest_type.gd itself are skipped by the
## scanner, so this template never shows up in the dropdown.)
##
## This example implements "SURVIVE N SECONDS" as a demonstration since it
## exercises the most machinery: per-quest state in entry.data, time
## tracking, and custom progress text.

func type_id() -> String:
	# UNIQUE name - this string is what gets saved into quest .tres files,
	# so changing it later breaks existing quest files that use it.
	return "_template_survive"

func type_description() -> String:
	return "TEMPLATE: survive for target_count seconds."


# ---------------------------------------------------------------------------
# STATE: every active quest gets its own `entry` Dictionary:
#   entry.quest     - the Quest resource (also available as `self.quest`)
#   entry.progress  - int, drives the goal_count() completion check
#   entry.data      - Dictionary that is ALL YOURS. Stash timers, baselines,
#                     seen-ids, whatever your type needs. It lives exactly
#                     as long as the quest is active.
#   entry.time_left - only used when quest.has_time_limit is on
# ---------------------------------------------------------------------------

func on_accepted(entry: Dictionary) -> void:
	# Runs once, right after the player takes the quest.
	#
	# COMMON PATTERNS:
	# - Snapshot a baseline (see collect_gears.gd):
	#     var gm = manager.get_node_or_null("/root/GameManager")
	#     entry.data["gear_baseline"] = gm.gear_count if gm else 0
	#
	# - Complete instantly if already satisfied (see reach_location.gd):
	#     if manager.has_location_flag(quest.target_id):
	#         manager.call_deferred("complete_entry", entry)   # deferred! accept isn't finished yet
	#
	# - Start a timer (this template): record the start time.
	entry.data["start_ms"] = Time.get_ticks_msec()


# ---------------------------------------------------------------------------
# EVENT HOOKS: the QuestManager forwards game events to every active quest.
# Override only the ones your type cares about. From inside them, call:
#   progress(entry)          - +1 progress, auto-completes at goal_count()
#   progress(entry, 5)       - +5 at once
#   set_progress(entry, n)   - absolute value (good for baseline counting)
#   complete(entry)          - finish right now, regardless of progress
# ---------------------------------------------------------------------------

func notify_enemy_defeated(entry: Dictionary, enemy: Node) -> void:
	# An enemy died anywhere in the level. `enemy` is the actual node, so
	# you can filter on anything:
	#   enemy.get("is_boss") == true               - bosses only
	#   enemy.scene_file_path == "res://...tscn"   - a specific type
	#   enemy.get("enemy_id") == quest.target_id   - a named target
	#   enemy.global_position.distance_to(...)     - kills in an area!
	#
	# This template doesn't care about kills - but a "survive" quest COULD
	# use this to reset the timer on each kill, for example.
	pass


func notify_gears_changed(entry: Dictionary, total_gears: int) -> void:
	# The player's gear total changed (pickup by player OR HU3).
	# collect_gears.gd does: set_progress(entry, total_gears - baseline)
	#
	# For this survive template we hijack the event as a cheap tick to
	# check the clock (see the NOTE below for a better way):
	_check_time(entry)


func notify_location_flag(entry: Dictionary, flag_id: String) -> void:
	# A LocationFlag was touched. reach_location.gd does:
	#   if flag_id == quest.target_id: complete(entry)
	pass


func notify_item_grabbed(entry: Dictionary, item_id: String) -> void:
	# A QuestItem was picked up. fetch_item.gd stores it in entry.data and
	# waits for try_turn_in().
	pass


func try_turn_in(entry: Dictionary) -> bool:
	# The player talked to the giver while this quest is active. Return
	# true if the talk completes the quest (fetch-style). Most types just
	# leave this returning false.
	#
	# For the survive template: talking to the giver checks the clock too.
	return _check_time(entry)


# NOTE: quest types are RefCounted, not Nodes - they get no _process().
# For real time-based quests either use quest.has_time_limit (the manager
# ticks entry.time_left down and FAILS the quest at 0 automatically), or
# check the clock inside whichever notify_*/describe_* calls you receive -
# describe_progress() runs every frame while the tracker is visible, which
# is what this template leans on:

func _check_time(entry: Dictionary) -> bool:
	var elapsed = (Time.get_ticks_msec() - entry.data.get("start_ms", 0)) / 1000.0
	if elapsed >= quest.goal_count():
		complete(entry)
		return true
	return false


# ---------------------------------------------------------------------------
# UI TEXT: shown in the HUD tracker (describe_progress) and by the quest
# giver while the quest runs (describe_reminder).
# ---------------------------------------------------------------------------

func describe_progress(entry: Dictionary) -> String:
	_check_time(entry)   # doubles as our per-frame clock check
	var elapsed = int((Time.get_ticks_msec() - entry.data.get("start_ms", 0)) / 1000.0)
	return "survived %d/%ds" % [mini(elapsed, quest.goal_count()), quest.goal_count()]


func describe_reminder(entry: Dictionary) -> String:
	return "Still alive? Keep it up a little longer."
