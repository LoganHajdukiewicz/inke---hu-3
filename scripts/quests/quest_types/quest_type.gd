class_name QuestTypeHandler
extends RefCounted

## Base class for QUEST TYPES. Every file in scripts/quests/quest_types/
## (except this one and _template.gd) IS a quest type: drop a new script in
## the folder and it automatically appears in the Quest resource's
## quest_type dropdown in the Inspector. No enum edits, no registration.
##
## See _template.gd for a heavily commented starter and README.md in the
## same folder for the full how-to.
##
## Lifecycle of a handler:
##   - One handler instance is created per ACTIVE quest (not shared).
##   - on_accepted() runs right after the player takes the quest.
##   - The QuestManager forwards game events to the matching notify_*()
##     methods. Call progress(entry, n) / complete(entry) from them.
##   - describe_progress() feeds the HUD tracker and quest giver reminders.

# Set by the QuestManager when the handler is created:
var quest: Quest = null
var manager: Node = null   # The QuestManager autoload


# =========================================================================
# IDENTITY - override these two in every quest type
# =========================================================================

## The name shown in the Inspector dropdown and stored in quest files.
## MUST be unique across the quest_types folder. Convention: snake_case.
func type_id() -> String:
	return "base"


## One-liner shown to the developer (and usable in UIs).
func type_description() -> String:
	return "Base quest type - never used directly."


# =========================================================================
# LIFECYCLE HOOKS - override the ones your quest type needs
# =========================================================================

## Called immediately after the quest is accepted. Good place to check
## "already satisfied?" (e.g. player already visited the location) or to
## snapshot a baseline (e.g. current gear count).
## entry is the live tracking Dictionary: { quest, progress, data, ... }.
## entry.data is a Dictionary that's all yours - stash anything in it.
func on_accepted(_entry: Dictionary) -> void:
	pass


## An enemy died. Call progress()/complete() if your quest cares.
func notify_enemy_defeated(_entry: Dictionary, _enemy: Node) -> void:
	pass


## The player's total gear count changed.
func notify_gears_changed(_entry: Dictionary, _total_gears: int) -> void:
	pass


## A location flag was just set (LocationFlag areas set these).
func notify_location_flag(_entry: Dictionary, _flag_id: String) -> void:
	pass


## The player grabbed a QuestItem.
func notify_item_grabbed(_entry: Dictionary, _item_id: String) -> void:
	pass


## The player talked to the quest giver while this quest is active.
## Return true if that TALK completed the quest (fetch-style turn-ins).
func try_turn_in(_entry: Dictionary) -> bool:
	return false


# =========================================================================
# UI TEXT
# =========================================================================

## Short progress line for the HUD tracker, e.g. "gears 3/5".
func describe_progress(entry: Dictionary) -> String:
	return "%d/%d" % [entry.progress, quest.goal_count()]


## What the quest giver says while the quest is running.
func describe_reminder(entry: Dictionary) -> String:
	return "Progress: %d of %d." % [entry.progress, quest.goal_count()]


# =========================================================================
# HELPERS - call these from your notify_* overrides
# =========================================================================

## Add progress; auto-completes when goal_count is reached.
func progress(entry: Dictionary, amount: int = 1) -> void:
	entry.progress += amount
	manager.emit_progress(entry)
	if entry.progress >= quest.goal_count():
		complete(entry)


## Set progress to an absolute value; auto-completes at goal_count.
func set_progress(entry: Dictionary, value: int) -> void:
	var clamped = clampi(value, 0, quest.goal_count())
	if clamped == entry.progress:
		return
	entry.progress = clamped
	manager.emit_progress(entry)
	if entry.progress >= quest.goal_count():
		complete(entry)


## Complete the quest right now (reward spawns, tracker clears).
func complete(entry: Dictionary) -> void:
	manager.complete_entry(entry)
