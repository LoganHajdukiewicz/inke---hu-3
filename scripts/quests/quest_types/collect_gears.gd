extends QuestTypeHandler

## COLLECT GEARS: gather target_count gears, counted from quest start
## (a baseline of the player's gear total is snapshotted on accept).

func type_id() -> String:
	return "collect_gears"

func type_description() -> String:
	return "Collect N gears (counted from quest start)."

func on_accepted(entry: Dictionary) -> void:
	var gm = manager.get_node_or_null("/root/GameManager")
	entry.data["gear_baseline"] = gm.gear_count if gm else 0

func notify_gears_changed(entry: Dictionary, total_gears: int) -> void:
	set_progress(entry, total_gears - entry.data.get("gear_baseline", 0))

func describe_progress(entry: Dictionary) -> String:
	return "gears %d/%d" % [entry.progress, quest.goal_count()]

func describe_reminder(entry: Dictionary) -> String:
	return "Gears so far: %d of %d." % [entry.progress, quest.goal_count()]
