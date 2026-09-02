extends QuestTypeHandler

## REACH LOCATION: touch the LocationFlag whose flag_id == target_id.
## If the player has ALREADY been there, the quest completes instantly
## on accept (location flags persist for the whole session).

func type_id() -> String:
	return "reach_location"

func type_description() -> String:
	return "Reach a LocationFlag area (target_id = flag_id)."

func on_accepted(entry: Dictionary) -> void:
	if manager.has_location_flag(quest.target_id):
		manager.call_deferred("complete_entry", entry)

func notify_location_flag(entry: Dictionary, flag_id: String) -> void:
	if flag_id == quest.target_id:
		complete(entry)

func describe_progress(_entry: Dictionary) -> String:
	return "reach the spot"

func describe_reminder(_entry: Dictionary) -> String:
	return "You still haven't made it to the spot. It's out there somewhere!"
