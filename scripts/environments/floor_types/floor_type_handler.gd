class_name FloorTypeHandler
extends RefCounted

## Base class for per-floor-type behavior.
## Each floor type (spring, falling, frozen, ...) lives in its own small file
## instead of one giant floor.gd. The Floor node owns exactly one handler,
## created in Floor.setup_floor_type() based on its floor_type export.
##
## Handlers read their configuration (forces, durations, colors...) from the
## owning Floor's exported properties so scene overrides keep working.

var owner_floor: Floor


func _init(floor_node: Floor) -> void:
	owner_floor = floor_node


## Called once at runtime after the floor's geometry has been built.
func setup() -> void:
	pass


## Called every frame from Floor._process().
func process(_delta: float) -> void:
	pass


## Called when a player enters the floor's detection area.
func on_player_entered(_player: CharacterBody3D) -> void:
	pass


## Called when a player exits the floor's detection area.
func on_player_exited(_player: CharacterBody3D) -> void:
	pass


## Shared helper: standard spring/detection area sizing used by most types.
func enable_detection_area() -> void:
	var spring_area = owner_floor.spring_area
	if not spring_area:
		return
	spring_area.monitoring = true
	spring_area.visible = true
	
	var floor_shape_obj = owner_floor.collision_shape.shape as BoxShape3D
	var spring_collision = owner_floor.spring_collision
	if floor_shape_obj and spring_collision:
		var spring_shape = spring_collision.shape as BoxShape3D
		if spring_shape:
			spring_shape.size = Vector3(floor_shape_obj.size.x, floor_shape_obj.size.y + 0.5, floor_shape_obj.size.z)
			spring_collision.position.y = floor_shape_obj.size.y * 0.25
