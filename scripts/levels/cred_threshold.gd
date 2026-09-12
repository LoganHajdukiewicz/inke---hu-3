extends Node
class_name CredThreshold

## PER-LEVEL CRED threshold. Drop ONE of these anywhere in a level scene
## and set cred_needed in the Inspector: that's how much total CRED the
## player must have banked to unlock this level's boss fight / next event.
##
## CRED is a lifetime high score - never spent, never decreased, only
## CHECKED. So thresholds should climb level over level (e.g. 50 for the
## first boss, 120 for the second...) to keep pacing meaningful.
##
## Without this node a level falls back to QuestManager.cred_needed_for_boss.

## Total CRED required in THIS level to fill the bar / unlock the boss.
@export var cred_needed: int = 50


func _ready() -> void:
	var qm = get_node_or_null("/root/QuestManager")
	if qm and qm.has_method("register_cred_threshold"):
		qm.register_cred_threshold(cred_needed)
