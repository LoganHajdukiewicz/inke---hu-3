class_name SlidingFloor
extends FloorTypeHandler

## Mario 64-style slide surface. Any player who lands on it is forced into
## SlidingState, which accelerates them downhill along the slope with limited
## steering. Use this both as a "you can't climb up here" barrier and for
## dedicated slide sections.
##
## Tuning lives on the Floor node: slide_max_speed, slide_acceleration,
## slide_steering_strength.

# States that must not be interrupted by the slide capture
const AIRBORNE_STATES := [
	"JumpingState", "DoubleJumpState", "FallingState", "WallJumpingState",
	"GrappleHookState", "DodgeDashState", "SpinAttackState",
]


func setup() -> void:
	var material = owner_floor.create_textured_material(Color(0.9, 0.9, 0.4, 1))
	material.metallic = 0.2
	material.roughness = 0.8
	material.emission_enabled = true
	material.emission = Color(0.9, 0.9, 0.5)
	material.emission_energy = 0.1
	
	owner_floor.mesh_instance.set_surface_override_material(0, material)
	
	# Zero friction so nothing can grip the slide
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = 0.0
	physics_mat.bounce = 0.0
	owner_floor.physics_material_override = physics_mat
	
	enable_detection_area()


func process(_delta: float) -> void:
	for player in owner_floor.players_on_floor:
		if not player or not is_instance_valid(player):
			continue
		
		var state_machine = player.get_node_or_null("StateMachine")
		if not state_machine or not state_machine.current_state:
			continue
		
		var current_state_name = state_machine.current_state.get_script().get_global_name()
		
		# Let airborne states play out - we re-capture the player on landing
		if current_state_name in AIRBORNE_STATES:
			continue
		
		# Only capture when actually standing on THIS slide (the detection area
		# is a bit bigger than the floor, so double-check what's underfoot).
		# Without this, a player who crossed the seam onto an adjacent floor
		# kept being yanked back into SlidingState and froze at the seam.
		if not player.is_on_floor():
			continue
		if not _is_standing_on_slide(player):
			continue
		
		if current_state_name != "SlidingState":
			state_machine.change_state("SlidingState")


func _is_standing_on_slide(player) -> bool:
	"""Ray-check that the surface directly under the player is actually a
	SLIDING floor (not just inside our oversized detection area)."""
	var space_state = player.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3(0, 0.1, 0),
		player.global_position + Vector3(0, -1.2, 0)
	)
	query.collision_mask = 1
	query.exclude = [player]
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		return collider is Floor and collider.has_floor_type(Floor.FloorType.SLIDING)
	return false
