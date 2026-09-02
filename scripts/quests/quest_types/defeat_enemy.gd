extends QuestTypeHandler

## DEFEAT ENEMY: "elects" enemies rather than spawning them. Configure on
## the Quest resource:
##   target_enemy_scene - which enemy TYPE counts (empty = any type)
##   require_boss       - only enemies with is_boss tick count
##   target_id          - optional specific enemy_id hunt
##   target_count       - how many kills
## "Kill this boss" = require_boss + count 1.
## "Kill 15 regular enemies" = enemy.tscn + count 15.

func type_id() -> String:
	return "defeat_enemy"

func type_description() -> String:
	return "Defeat N enemies of a chosen type (or bosses)."

func notify_enemy_defeated(entry: Dictionary, enemy: Node) -> void:
	if _counts(enemy):
		progress(entry)

func _counts(enemy: Node) -> bool:
	if enemy == null:
		return false
	if quest.require_boss and not (enemy.get("is_boss") == true):
		return false
	if quest.target_id != "":
		return enemy.get("enemy_id") == quest.target_id
	if quest.target_enemy_scene != null:
		return enemy.scene_file_path == quest.target_enemy_scene.resource_path
	return true

func describe_progress(entry: Dictionary) -> String:
	return "defeated %d/%d" % [entry.progress, quest.goal_count()]

func describe_reminder(entry: Dictionary) -> String:
	return "Defeated: %d of %d." % [entry.progress, quest.goal_count()]
