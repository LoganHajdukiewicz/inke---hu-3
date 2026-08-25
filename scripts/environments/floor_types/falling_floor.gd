class_name FallingFloor
extends FloorTypeHandler

## Shakes as a warning, then falls away when a player stands on it,
## and respawns after a delay.

var is_falling: bool = false
var has_fallen: bool = false
var fall_triggered: bool = false
var fall_tween: Tween


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(1.0, 0.6, 0.6, 1))
	material.metallic = 0.1
	material.roughness = 0.4
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()


func process(_delta: float) -> void:
	if is_falling or has_fallen or fall_triggered:
		return
	if owner_floor.players_on_floor.size() > 0:
		fall_triggered = true
		start_falling()


func start_falling() -> void:
	if is_falling or has_fallen:
		return
	
	is_falling = true
	create_warning_shake()
	
	await owner_floor.get_tree().create_timer(owner_floor.shake_duration).timeout
	if not is_instance_valid(owner_floor):
		return
	
	owner_floor.collision_shape.disabled = true
	if owner_floor.spring_area:
		owner_floor.spring_area.monitoring = false
	
	fall_tween = owner_floor.create_tween()
	fall_tween.tween_property(owner_floor, "global_position",
		owner_floor.original_position + Vector3(0, -20, 0), owner_floor.fall_duration)
	fall_tween.tween_callback(func(): _on_fall_complete())


func create_warning_shake() -> void:
	var shake_tween = owner_floor.create_tween()
	var shake_loops = int(owner_floor.shake_duration / 0.1)
	var offset_x = 0.44
	var offset_z = 0.45
	shake_tween.set_loops(shake_loops)
	
	shake_tween.tween_property(owner_floor, "global_position",
		owner_floor.original_position + Vector3(offset_x, 0, offset_z), 0.05)
	shake_tween.tween_property(owner_floor, "global_position", owner_floor.original_position, 0.05)


func _on_fall_complete() -> void:
	has_fallen = true
	is_falling = false
	
	var material = owner_floor.mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 0.3
	
	await owner_floor.get_tree().create_timer(owner_floor.respawn_delay).timeout
	if is_instance_valid(owner_floor):
		respawn_floor()


func respawn_floor() -> void:
	owner_floor.global_position = owner_floor.original_position
	
	owner_floor.collision_shape.disabled = false
	if owner_floor.spring_area:
		owner_floor.spring_area.monitoring = true
	
	var material = owner_floor.mesh_instance.get_surface_override_material(0)
	if material:
		material.albedo_color.a = 1.0
	
	is_falling = false
	has_fallen = false
	fall_triggered = false
	owner_floor.players_on_floor.clear()
	
	create_respawn_effect()


func create_respawn_effect() -> void:
	var respawn_tween = owner_floor.create_tween()
	respawn_tween.set_parallel(true)
	
	var original_scale = owner_floor.scale
	owner_floor.scale = Vector3(0.1, 0.1, 0.1)
	respawn_tween.tween_property(owner_floor, "scale", original_scale, 0.5)
	respawn_tween.tween_property(owner_floor, "scale", original_scale, 0.5).set_trans(Tween.TRANS_BOUNCE)
	
	var material = owner_floor.mesh_instance.get_surface_override_material(0)
	if material:
		var original_color = material.albedo_color
		material.albedo_color = Color.WHITE
		respawn_tween.tween_property(material, "albedo_color", original_color, 0.3)
