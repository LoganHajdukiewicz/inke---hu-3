class_name DamageFloor
extends FloorTypeHandler

## Damaging surface (lava, electric...). Ticks damage + knockback on players
## standing on it at damage_interval.

var damage_timers: Dictionary = {}  # player -> time until next tick


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(1.0, 0.4, 0.0, 1))
	material.metallic = 0.3
	material.roughness = 0.2
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.0)
	material.emission_energy = 0.5
	
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	enable_detection_area()


func process(delta: float) -> void:
	for player in owner_floor.players_on_floor:
		if not player or not is_instance_valid(player):
			continue
		
		# Skip if player is dead or invulnerable
		if player.get("is_dead") or player.get("is_invulnerable"):
			continue
		
		if not damage_timers.has(player):
			damage_timers[player] = 0.0
		
		damage_timers[player] -= delta
		
		if damage_timers[player] <= 0.0:
			apply_damage_to_player(player)
			damage_timers[player] = owner_floor.damage_interval


func on_player_exited(player: CharacterBody3D) -> void:
	damage_timers.erase(player)


func apply_damage_to_player(player: CharacterBody3D) -> void:
	if not player or not is_instance_valid(player):
		return
	
	# Knockback away from floor center, upward
	var knockback_direction = (player.global_position - owner_floor.global_position).normalized()
	knockback_direction.y = 0
	
	if knockback_direction.length() < 0.1:
		knockback_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	
	var knockback_velocity = knockback_direction * owner_floor.damage_knockback_force
	knockback_velocity.y = owner_floor.damage_knockback_upward
	
	if player.has_method("take_damage"):
		player.take_damage(owner_floor.damage_amount, knockback_velocity)
