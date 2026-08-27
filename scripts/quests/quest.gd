class_name Quest
extends Resource

## A single quest definition. Create these in the Inspector on a QuestGiver
## (or save as .tres files to reuse across levels).
##
## Quest types:
##   COLLECT_GEARS  - collect target_count GEARs (counted from quest start)
##   DEFEAT_ENEMY   - defeat target_count enemies whose enemy_id == target_id
##                    (optionally spawn the target when the quest is accepted)
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
## DEFEAT_ENEMY: enemy_id to hunt. REACH_LOCATION: flag_id. FETCH_ITEM: item_id.
@export var target_id: String = ""

@export_group("Time Limit")
## Default: no time limit.
@export var has_time_limit: bool = false
@export var time_limit_seconds: float = 60.0

@export_group("Reward")
## CRED that appears in front of the player when the quest completes.
@export var cred_reward: int = 10
## Can the quest be taken again after completing it?
@export var repeatable: bool = false

@export_group("Defeat Quest Spawning")
## Optional: spawn this enemy scene when the quest is accepted (its enemy_id
## is set to target_id automatically). Leave empty to hunt a pre-placed enemy.
@export var spawn_target_enemy: PackedScene
@export var target_enemy_spawn_position: Vector3 = Vector3.ZERO


func goal_count() -> int:
	match quest_type:
		QuestType.COLLECT_GEARS, QuestType.DEFEAT_ENEMY:
			return maxi(1, target_count)
		_:
			return 1
