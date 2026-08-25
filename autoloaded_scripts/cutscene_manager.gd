extends Node

## Minimal cutscene coordinator.
## Other systems (e.g. PaintUIManager) listen to these signals to hide/show
## gameplay UI. Call start_cutscene()/end_cutscene() from cutscene logic.

signal cutscene_started
signal cutscene_ended

var is_cutscene_active: bool = false

func start_cutscene() -> void:
	if is_cutscene_active:
		return
	is_cutscene_active = true
	cutscene_started.emit()

func end_cutscene() -> void:
	if not is_cutscene_active:
		return
	is_cutscene_active = false
	cutscene_ended.emit()
