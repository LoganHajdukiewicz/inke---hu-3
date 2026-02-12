extends Node
class_name LedgeDetectionManager

# Ledge detection configuration
@export var ledge_check_distance: float = 0.8  # How far forward to check for wall
@export var ledge_check_height: float = 1.3  # How high above player center to check
@export var ledge_top_check_distance: float = 1.0  # How far to check for ledge top
@export var min_ledge_height: float = 0.5  # Minimum height difference for valid ledge (increased from 0.3)
@export var max_ledge_height: float = 2.0  # Maximum height difference for valid ledge
@export var enable_debug_draw: bool = false  # Draw debug lines showing raycasts (disabled by default)
@export var velocity_check_threshold: float = -5.0  # Only check when falling at this speed or faster
@export var allowed_ledge_scenes: Array[String] = ["wall", "floor"]  # Scenes that can be grabbed

var player: CharacterBody3D
var state_machine: StateMachine
var game_manager

var ledge_grab_cooldown: float = 0.0
var cooldown_duration: float = 0.5

var debug_draw_node: Node3D
var debug_material: StandardMaterial3D

func _ready():
	player = get_parent() as CharacterBody3D
	state_machine = player.get_node("StateMachine")
	game_manager = get_node("/root/GameManager")
	setup_debug_draw()

func setup_debug_draw():
	if not enable_debug_draw:
		return
	
	debug_draw_node = Node3D.new()
	debug_draw_node.name = "LedgeDebugDraw"
	player.add_child(debug_draw_node)
	debug_material = StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.albedo_color = Color.CYAN

func _physics_process(delta):
	if ledge_grab_cooldown > 0:
		ledge_grab_cooldown -= delta
	
	check_for_ledge_grab()

func check_for_ledge_grab():
	if ledge_grab_cooldown > 0:
		return

# Only check when falling or jumping
	var current_state = state_machine.current_state
	if not current_state:
		return

	var current_state_name = current_state.get_script().get_global_name()
	
	# Don't check if already hanging/vaulting or in certain states
	if current_state_name in ["LedgeHangingState", "LedgeJumpState", "IdleState", "WalkingState", "RunningState", "DodgeDashState", "RailGrindingState", "WallJumpingState"]:
		return

	# Check if there's a ledge to grab
	var ledge_data = detect_ledge()
	if ledge_data.has_ledge:
	# Set cooldown to prevent immediate re-grabs
		ledge_grab_cooldown = cooldown_duration

	# Determine which state to use based on ledge height relative to player
	var height_difference = ledge_data.height_difference
	var capsule_height = 1.5  # Default
	var collision_shape = player.get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		capsule_height = collision_shape.shape.height
	
	var midpoint_threshold = capsule_height / 2.0	
	if height_difference <= midpoint_threshold:
	# Low ledge — auto-vault
	print("=== LOW LEDGE DETECTED (", height_difference, " <= ", midpoint_threshold, ")! Vaulting ===")
		var jump_state = state_machine.states.get("ledgejumpstate")
		if jump_state:
			jump_state.setup_ledge_hang(ledge_data.ledge_position, ledge_data.wall_normal)
			state_machine.change_state("LedgeJumpState")
		else:
			print("ERROR: LedgeJumpState not found in state machine!")
			print("Available states: ", state_machine.states.keys())
	else:
	
	# High ledge — hang and shimmy
		print("=== HIGH LEDGE DETECTED (", height_difference, " > ", midpoint_threshold, ")! Hanging ===")
		var ledge_state = state_machine.states.get("ledgehangingstate")
		if ledge_state:
			ledge_state.setup_ledge_hang(ledge_data.ledge_position, ledge_data.wall_normal)
			state_machine.change_state("LedgeHangingState")
		else:
			print("ERROR: LedgeHangingState not found in state machine!")
			print("Available states: ", state_machine.states.keys())

func is_allowed_ledge_object(collider: Object) -> bool:
	if not collider:
		return false

	# Get the scene file path
	var scene_path = collider.scene_file_path
	
	if scene_path == "":
		if enable_debug_draw:
			print("  Object has no scene_file_path: ", collider.name)
			return false

	# Extract filename from path (e.g., "res://scenes/wall.tscn" -> "wall.tscn")
	var filename = scene_path.get_file()
	
	# Remove extension (e.g., "wall.tscn" -> "wall")
	var scene_name = filename.get_basename()

	if enable_debug_draw:
		print("  Checking object: ", collider.name)
		print("  Scene path: ", scene_path)
		print("  Scene name: ", scene_name)
		print("  Is allowed: ", scene_name in allowed_ledge_scenes)

	# Check if this scene name is in our allowed list
	return scene_name in allowed_ledge_scenes

func detect_ledge() -> Dictionary:
	"""Detect if there's a valid ledge in front of the player using direct raycasts"""
	var result = {
		"has_ledge": false,
		"ledge_position": Vector3.ZERO,
		"wall_normal": Vector3.ZERO,
		"height_difference": 0.0
		}
	
	var space_state = player.get_world_3d().direct_space_state
	
	# Get player's forward direction
	var forward = -player.global_transform.basis.z.normalized()
	if enable_debug_draw:
		print("\n=== LEDGE DETECTION CHECK ===")
		print("Player position: ", player.global_position)
		print("Player forward: ", forward)
		print("Player velocity.y: ", player.velocity.y)

	# Check for wall in front at chest height
	var wall_check_start = player.global_position + Vector3(0, 0.5, 0)
	var wall_check_end = wall_check_start + forward * ledge_check_distance
	var wall_query = PhysicsRayQueryParameters3D.create(wall_check_start, wall_check_end)
	wall_query.collision_mask = 1
	wall_query.exclude = [player]
	var wall_result = space_state.intersect_ray(wall_query)
	if enable_debug_draw:
		print("Wall check: ", "HIT" if wall_result else "MISS")
		draw_debug_line(wall_check_start, wall_check_end, Color.RED if not wall_result else Color.GREEN)
	if not wall_result:
		return result

	var wall_collider = wall_result.collider
	if not is_allowed_ledge_object(wall_collider):
		if enable_debug_draw:
			print("  REJECTED: Wall is not an allowed ledge object")
		return result
		
	var wall_point = wall_result.position
	var wall_normal = wall_result.normal
		
	if enable_debug_draw:
		print("  Wall point: ", wall_point)
		print("  Wall normal: ", wall_normal)
		print("  Wall is ALLOWED for ledge grab!")


	# Check for ledge top - cast DOWN from above the wall
	var ledge_check_start = wall_point + Vector3(0, ledge_check_height, 0) + wall_normal * -0.2
	var ledge_check_end = ledge_check_start + Vector3(0, -ledge_top_check_distance, 0)
	var ledge_query = PhysicsRayQueryParameters3D.create(ledge_check_start, ledge_check_end)
	ledge_query.collision_mask = 1
	ledge_query.exclude = [player]
	var ledge_result = space_state.intersect_ray(ledge_query)
	
	if enable_debug_draw:
		print("Ledge top check: ", "HIT" if ledge_result else "MISS")
		draw_debug_line(ledge_check_start, ledge_check_end, Color.BLUE if not ledge_result else Color.YELLOW)
	
	if not ledge_result:
		return result
	
	# NEW: Check if the ledge top is an allowed object
	var ledge_collider = ledge_result.collider
	if not is_allowed_ledge_object(ledge_collider):
		if enable_debug_draw:
			print("  REJECTED: Ledge top is not an allowed ledge object")
		return result
	
	var ledge_point = ledge_result.position
	var ledge_normal = ledge_result.normal

	if enable_debug_draw:
		print("  Ledge point: ", ledge_point)
		print("  Ledge normal: ", ledge_normal)
		print("  Ledge normal dot UP: ", ledge_normal.dot(Vector3.UP))
		print("  Ledge is ALLOWED for ledge grab!")

	# Verify ledge normal points upward (is a floor/platform)
	if ledge_normal.dot(Vector3.UP) < 0.7:
		if enable_debug_draw:
			print("  REJECTED: Ledge normal not pointing up enough")
		return result

	# Check if there's enough space above the ledge for player to climb
	var space_check_start = ledge_point + Vector3(0, 0.1, 0)
	var space_check_end = space_check_start + Vector3(0, 1.8, 0)
	var space_query = PhysicsRayQueryParameters3D.create(space_check_start, space_check_end)
	space_query.collision_mask = 1
	space_query.exclude = [player]
	var space_result = space_state.intersect_ray(space_query)
	if enable_debug_draw:
		print("Space check: ", "BLOCKED" if space_result else "CLEAR")
		draw_debug_line(space_check_start, space_check_end, Color.RED if space_result else Color.CYAN)
	
	if space_result:
		if enable_debug_draw:
			print("  REJECTED: Not enough space to climb up")
		return result
	
	
	# Verify the ledge is at appropriate height
	var height_difference = ledge_point.y - player.global_position.y
	if enable_debug_draw:
		print("Height difference: ", height_difference, " (min: ", min_ledge_height, ", max: ", max_ledge_height, ")")

	if height_difference < min_ledge_height or height_difference > max_ledge_height:
	if enable_debug_draw:
		print("  REJECTED: Height out of range")
	return result
	
	# All checks passed - valid ledge found!
	if enable_debug_draw:
		print("✓ VALID LEDGE FOUND!")
	
	result.has_ledge = true
	result.ledge_position = ledge_point
	result.wall_normal = wall_normal
	result.height_difference = height_difference
	return result

func draw_debug_line(start: Vector3, end: Vector3, color: Color):
	if not enable_debug_draw or not debug_draw_node:
		return

	# Clear old debug lines
	for child in debug_draw_node.get_children():
		child.queue_free()

	var immediate_mesh = ImmediateMesh.new()
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = immediate_mesh
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(start)
	immediate_mesh.surface_add_vertex(end)
	immediate_mesh.surface_end()
	player.get_parent().add_child(mesh_instance)
	
	# Auto-delete after a short time
	await player.get_tree().create_timer(0.1).timeout

	if is_instance_valid(mesh_instance):
    	mesh_instance.queue_free()

func can_grab_ledge() -> bool:
	var ledge_data = detect_ledge()
	return ledge_data.has_ledge