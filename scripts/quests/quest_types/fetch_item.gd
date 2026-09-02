extends QuestTypeHandler

## FETCH ITEM: grab the QuestItem whose item_id == target_id, then RETURN
## to the quest giver and talk to them (the only type with a turn-in step).
## If the player is already holding the item on accept, only the return
## trip remains.

func type_id() -> String:
	return "fetch_item"

func type_description() -> String:
	return "Grab a QuestItem, then return to the giver (target_id = item_id)."

func on_accepted(entry: Dictionary) -> void:
	if manager.carried_items.has(quest.target_id):
		entry.data["item_held"] = true

func notify_item_grabbed(entry: Dictionary, item_id: String) -> void:
	if item_id == quest.target_id and not entry.data.get("item_held", false):
		entry.data["item_held"] = true
		manager.emit_progress(entry)
		manager.show_notification("Got it! Return to the quest giver.", Color(1.0, 0.9, 0.3))

func try_turn_in(entry: Dictionary) -> bool:
	if not entry.data.get("item_held", false):
		return false
	manager.carried_items.erase(quest.target_id)
	complete(entry)
	return true

func describe_progress(entry: Dictionary) -> String:
	return "return to giver!" if entry.data.get("item_held", false) else "find the item"

func describe_reminder(entry: Dictionary) -> String:
	return "You have it? Hand it over!" if entry.data.get("item_held", false) else "Still waiting on that item. Go grab it!"
