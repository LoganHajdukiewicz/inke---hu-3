class_name FrozenFloor
extends FloorTypeHandler

## Icy floor. The visual shimmer lives here; the actual slippery movement is
## handled by the player's ice-momentum model (see inke.gd apply_ice_movement),
## which detects this floor via floor_type == FloorType.FROZEN.

var frozen_time: float = 0.0


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(0.7, 0.9, 1.0, 0.95))
	material.metallic = 0.4
	material.roughness = 0.1
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	if owner_floor.frozen_enable_visual_effects:
		material.emission_enabled = true
		material.emission = Color(0.6, 0.8, 1.0)
		material.emission_energy = 0.2
	
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	
	# Low-friction physics material (affects RigidBodies like dropped gears)
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = owner_floor.frozen_friction
	physics_mat.bounce = 0.0
	owner_floor.physics_material_override = physics_mat
	
	enable_detection_area()


func process(delta: float) -> void:
	if not owner_floor.frozen_enable_visual_effects:
		return
	
	frozen_time += delta
	
	var material = owner_floor.mesh_instance.get_surface_override_material(0)
	if material and material is StandardMaterial3D:
		var shimmer = sin(frozen_time * owner_floor.frozen_shimmer_speed) * owner_floor.frozen_shimmer_intensity
		material.emission_energy = 0.2 + shimmer
