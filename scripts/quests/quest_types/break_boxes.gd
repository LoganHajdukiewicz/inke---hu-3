extends QuestTypeHandler

## BREAK BOXES: smash N breakables (crates, explosive barrels - anything
## whose script calls QuestManager.notify_breakable_destroyed on death).
## Configure on the Quest resource:
##   target_count - how many to smash
##   target_id    - optional filter: only breakables whose scene file name
##                  contains this string count (e.g. "barrel" = only
##                  explosive barrels; empty = any breakable)

func type_id() -> String:
	return "break_boxes"

func type_description() -> String:
	return "Destroy N breakable boxes/barrels."

func notify_breakable_destroyed(entry: Dictionary, breakable: Node) -> void:
	if breakable == null:
		return
	if quest.target_id != "":
		var scene_name = breakable.scene_file_path.get_file().to_lower()
		if not scene_name.contains(quest.target_id.to_lower()):
			return
	progress(entry)

func describe_progress(entry: Dictionary) -> String:
	return "smashed %d/%d" % [entry.progress, quest.goal_count()]

func describe_reminder(entry: Dictionary) -> String:
	return "Smashed: %d of %d. Keep breaking!" % [entry.progress, quest.goal_count()]
