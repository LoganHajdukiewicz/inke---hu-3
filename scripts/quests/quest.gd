@tool
class_name Quest
extends Resource

## A single quest definition. Create these in the Inspector on a QuestGiver
## or save as .tres files in res://quests/ to reuse across levels.
##
## QUEST TYPES ARE FILES, NOT AN ENUM: the quest_type dropdown below is
## built by scanning scripts/quests/quest_types/ - every handler script in
## that folder is a type. To add a new type, copy _template.gd there and
## fill in the hooks (see the README.md next to it). It appears in this
## dropdown automatically.
##
## Built-in types:
##   collect_gears  - collect target_count GEARs (counted from quest start)
##   defeat_enemy   - "ELECTS" enemies: pick a type (target_enemy_scene),
##                    a boss requirement (require_boss) and a count.
##   reach_location - touch the LocationFlag whose flag_id == target_id
##   fetch_item     - grab the QuestItem (item_id == target_id), then
##                    return to the quest giver and talk to them
##
## Completion reward: cred_reward worth of CRED appears in front of the player.

const TYPES_DIR := "res://scripts/quests/quest_types"

@export var quest_id: String = ""
@export var title: String = "Quest"
@export_multiline var description: String = ""

## Which quest type file handles this quest. Dropdown lists everything in
## scripts/quests/quest_types/ (via _get_property_list below).
var quest_type: String = "collect_gears"

## How many (gears, kills, seconds... whatever the type counts).
@export var target_count: int = 1
## Free-form target id: reach_location = flag_id, fetch_item = item_id,
## defeat_enemy = optional specific enemy_id.
@export var target_id: String = ""

@export_group("Defeat Quest Target")
## WHICH TYPE of enemy counts. Drop any enemy scene here (enemy.tscn,
## laser_enemy.tscn, shield_enemy.tscn...) - every kill of that type
## progresses the quest. Leave empty to match ANY enemy type.
@export var target_enemy_scene: PackedScene = null
## Only BOSSES count (enemies with is_boss ticked). Combine with
## target_enemy_scene for "this specific kind of boss", or leave the scene
## empty for "any boss".
@export var require_boss: bool = false

@export_group("Time Limit")
## Default: no time limit. When on, the QuestManager ticks the clock and
## FAILS the quest automatically at zero.
@export var has_time_limit: bool = false
@export var time_limit_seconds: float = 60.0

@export_group("Reward")
## CRED that appears in front of the player when the quest completes.
@export var cred_reward: int = 10
## Can the quest be taken again after completing it?
@export var repeatable: bool = false


func goal_count() -> int:
	return maxi(1, target_count)


# =========================================================================
# quest_type dropdown: scan the quest_types folder for handler scripts
# =========================================================================

static var _type_ids_cache: PackedStringArray = []

static func available_types() -> PackedStringArray:
	"""Every quest type in the quest_types folder, by type_id()."""
	if not _type_ids_cache.is_empty():
		return _type_ids_cache
	var ids := PackedStringArray()
	var dir = DirAccess.open(TYPES_DIR)
	if dir:
		for f in dir.get_files():
			var fname = f.trim_suffix(".remap")   # Exported builds remap .gd
			if not fname.ends_with(".gd"):
				continue
			if fname == "quest_type.gd" or fname.begins_with("_"):
				continue
			var script = load(TYPES_DIR + "/" + fname)
			if script is GDScript:
				var inst = script.new()
				if inst is QuestTypeHandler:
					ids.append(inst.type_id())
	ids.sort()
	_type_ids_cache = ids
	return ids

static func create_handler(type: String) -> QuestTypeHandler:
	"""Instance the handler script whose type_id() matches."""
	var dir = DirAccess.open(TYPES_DIR)
	if dir:
		for f in dir.get_files():
			var fname = f.trim_suffix(".remap")
			if not fname.ends_with(".gd"):
				continue
			if fname == "quest_type.gd" or fname.begins_with("_"):
				continue
			var script = load(TYPES_DIR + "/" + fname)
			if script is GDScript:
				var inst = script.new()
				if inst is QuestTypeHandler and inst.type_id() == type:
					return inst
	push_warning("Quest: unknown quest_type '%s' (no handler in %s)" % [type, TYPES_DIR])
	return null


func _get_property_list() -> Array:
	# Expose quest_type as an enum-style dropdown fed by the folder scan
	var options = ",".join(available_types())
	return [{
		"name": "quest_type",
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM_SUGGESTION,
		"hint_string": options,
		"usage": PROPERTY_USAGE_DEFAULT,
	}]
