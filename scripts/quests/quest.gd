class_name Quest
extends Resource

## A single quest definition. Create these in the Inspector on a QuestGiver
## (or save as .tres files to reuse across levels).
##
## Quest types:
##   COLLECT_GEARS  - collect target_count GEARs (counted from quest start)
##   DEFEAT_ENEMY   - "ELECTS" enemies rather than spawning them: pick an
##                    enemy TYPE (target_enemy_scene) and a COUNT
##                    (target_count) in the Inspector, and any kill of a
##                    matching enemy already in the level counts.
##                    "Kill this boss" = require_boss on, count 1.
##                    "Kill 15 regular enemies" = enemy.tscn, count 15.
##   REACH_LOCATION - touch the LocationFlag whose flag_id == target_id
##   FETCH_ITEM     - grab the QuestItem whose item_id == target_id, then
##                    return to the quest giver and talk to them
##
## Completion reward: cred_reward worth of CRED appears in front of the player.

enum QuestType {
	COLLECT_GEARS,
	DEFEAT_ENEMY,
	REACH_LOCATION,
	FETCH_ITEM,
}

@export var quest_id: String = ""
@export var title: String = "Quest"
@export_multiline var description: String = ""
@export var quest_type: QuestType = QuestType.COLLECT_GEARS

## COLLECT_GEARS: how many gears. DEFEAT_ENEMY: how many kills. Others: ignored.
@export var target_count: int = 1
## REACH_LOCATION: flag_id. FETCH_ITEM: item_id.
## DEFEAT_ENEMY: optional specific enemy_id to hunt (leave empty when using
## target_enemy_scene type matching instead).
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
## Default: no time limit.
@export var has_time_limit: bool = false
@export var time_limit_seconds: float = 60.0

@export_group("Reward")
## CRED that appears in front of the player when the quest completes.
@export var cred_reward: int = 10
## Can the quest be taken again after completing it?
@export var repeatable: bool = false


func enemy_counts_for_quest(enemy: Node) -> bool:
	"""Does killing this enemy progress this DEFEAT_ENEMY quest?"""
	if quest_type != QuestType.DEFEAT_ENEMY or enemy == null:
		return false
	# Boss requirement
	if require_boss and not (enemy.get("is_boss") == true):
		return false
	# Specific enemy_id (old-style targeted hunt)
	if target_id != "":
		return enemy.get("enemy_id") == target_id
	# Type matching by scene
	if target_enemy_scene != null:
		return enemy.scene_file_path == target_enemy_scene.resource_path
	# No filters at all: any enemy counts
	return true


func goal_count() -> int:
	match quest_type:
		QuestType.COLLECT_GEARS, QuestType.DEFEAT_ENEMY:
			return maxi(1, target_count)
		_:
			return 1
