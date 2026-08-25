class_name NormalFloor
extends FloorTypeHandler

## Plain static floor. No special behavior.


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(0.8, 1.0, 0.8, 1))
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	
	if owner_floor.spring_area:
		owner_floor.spring_area.monitoring = false
		owner_floor.spring_area.visible = false
