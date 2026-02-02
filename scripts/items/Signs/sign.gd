extends StaticBody3D

# The sign is now just a visual object that holds a DialogueTrigger child
# All interaction logic is handled by the DialogueTrigger node

func _ready():
	# Optional: Add any visual effects or animations for the sign itself here
	pass

# Optional helper functions if you want to configure the dialogue trigger from the sign

func set_dialogue_file(dialogue_name: String):
	"""Helper to set the dialogue file on the child DialogueTrigger"""
	var dialogue_trigger = get_node_or_null("DialogueTrigger")
	if dialogue_trigger:
		dialogue_trigger.dialogue_file = dialogue_name

func set_trigger_type(type: int):
	"""Helper to set the trigger type on the child DialogueTrigger"""
	var dialogue_trigger = get_node_or_null("DialogueTrigger")
	if dialogue_trigger:
		dialogue_trigger.trigger_type = type
