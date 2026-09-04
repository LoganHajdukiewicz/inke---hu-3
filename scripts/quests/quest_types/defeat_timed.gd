extends QuestTypeHandler

## DEFEAT TIMED: kill N enemies within a time window - but the clock only
## starts on your FIRST kill, so the player isn't punished for walking to
## the fight. Configure on the Quest resource:
##   target_count       - how many kills
##   time_limit_seconds - the window length (has_time_limit NOT needed;
##                        this type manages its own clock so accepting the
##                        quest doesn't start the timer, the first kill does)
##   target_enemy_scene / require_boss / target_id - same filters as
##                        defeat_enemy (empty = any enemy counts)
## If the window expires the streak RESETS to zero and re-arms - the quest
## is never failed outright, you just have to do it in one clean streak.

func type_id() -> String:
	return "defeat_timed"

func type_description() -> String:
	return "Defeat N enemies within a time window (clock starts on first kill)."

func on_accepted(entry: Dictionary) -> void:
	entry.data["window_left"] = 0.0
	entry.data["armed"] = false

func tick(entry: Dictionary, delta: float) -> void:
	if not entry.data.get("armed", false):
		return
	entry.data["window_left"] -= delta
	if entry.data["window_left"] <= 0.0:
		# Streak broken: reset, re-arm on the next kill
		entry.data["armed"] = false
		set_progress(entry, 0)
		manager.show_notification("Time's up - kill streak reset!", Color(1.0, 0.6, 0.3))

func notify_enemy_defeated(entry: Dictionary, enemy: Node) -> void:
	if not _counts(enemy):
		return
	if not entry.data.get("armed", false):
		# First kill starts the clock
		entry.data["armed"] = true
		entry.data["window_left"] = maxf(quest.time_limit_seconds, 1.0)
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
	if entry.data.get("armed", false):
		return "streak %d/%d  [%ds]" % [entry.progress, quest.goal_count(), int(entry.data["window_left"])]
	return "streak %d/%d  (clock starts on first kill)" % [entry.progress, quest.goal_count()]

func describe_reminder(entry: Dictionary) -> String:
	return "Defeat %d in one streak - you have %d seconds from the first kill." % [quest.goal_count(), int(quest.time_limit_seconds)]
