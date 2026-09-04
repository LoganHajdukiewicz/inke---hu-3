extends Node
class_name WallJumpDetector
## Detects walls and fires wall jumps.
##
## Two fixes live here (they were classic feel-killers):
##
## 1. "MY FIRST JUMP PRESS IS IGNORED / IT TAKES 2 PRESSES"
##    Cause A: the eligible-state list only allowed FallingState and
##    JumpingState. Between CLOSE walls you're usually still in
##    WallJumpingState (rising from the last jump) when you press jump at
##    the next wall - the press was silently rejected until you tipped
##    into FallingState. WallJumpingState is now eligible.
##    Cause B: is_action_just_pressed is a ONE-frame edge. If the press
##    lands on the exact frame a state transition happens, every consumer
##    misses it. Fixed with a jump INPUT BUFFER: any jump press arms a
##    short window (jump_buffer_time) during which the wall jump fires as
##    soon as it becomes legal.
##
## 2. "I'M NEAR THE WALL BUT NOT TOUCHING IT AND CAN'T WALL JUMP"
##    Cause: wall detection relied on 4 fixed RayCast3D nodes (WallJumpRays)
##    pointing exactly forward/back/left/right in PLAYER-LOCAL space, only
##    1.5m long from the body center. Any diagonal wall, or standing a
##    bit off, missed. Now backed by an 8-direction world-space scan at
##    two heights with a generous reach.

## How long a jump press stays buffered waiting to become a wall jump.
@export var jump_buffer_time: float = 0.18
## How far away a wall can be and still count for a wall jump.
@export var wall_reach: float = 1.5
## A surface only counts as a WALL if this many height-staggered rays hit
## it in the same direction (heights: 0.4 / 1.1 / 1.8). Buttons, crates
## and short ledges only intercept the low ray - so they no longer
## hijack jumps and fling the player away. 2 = needs ~1.1m of wall,
## 3 = needs head-height wall.
@export_range(1, 3) var min_ray_hits: int = 2
## Heights (above the feet) the wall-check rays are cast from.
const RAY_HEIGHTS: Array[float] = [0.4, 1.1, 1.8]

var wall_jump_cooldown: float = 0.0
var wall_jump_cooldown_time: float = 0.0
var _jump_buffer: float = 0.0

var player: CharacterBody3D
var state_machine: StateMachine
var game_manager
var wall_jump_rays: Node3D

func _ready():
	player = get_parent() as CharacterBody3D
	state_machine = player.get_node("StateMachine")
	game_manager = get_node("/root/GameManager")
	wall_jump_rays = player.get_node("WallJumpRays") if player.has_node("WallJumpRays") else null

func _physics_process(delta):
	if wall_jump_cooldown > 0:
		wall_jump_cooldown -= delta
	
	# Input buffer: remember the press, fire when legal (see header)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	elif _jump_buffer > 0.0:
		_jump_buffer -= delta
	
	check_for_wall_jump()

func can_perform_wall_jump() -> bool:
	"""Check if the player can perform a wall jump"""
	var current_state_name = state_machine.current_state.get_script().get_global_name()
	var can_wall_jump_ability = game_manager.can_wall_jump() if game_manager else false
	# WallJumpingState included: chaining between close walls means you're
	# often still rising from the last jump when you reach the next wall.
	# (WallSlidingState handles its own jump - excluded to avoid double-fire.)
	return (can_wall_jump_ability and 
			not player.is_on_floor() and 
			wall_jump_cooldown <= 0 and
			current_state_name in ["FallingState", "JumpingState", "DoubleJumpState", "WallJumpingState"])

func get_wall_jump_direction() -> Vector3:
	"""Get the wall normal to jump away from. The 8-direction multi-height
	scan is the single authority: a direction only counts when at least
	min_ray_hits height-staggered rays agree there's a wall there. The old
	WallJumpRays path is gone - a single low ray hitting a BUTTON or a
	knee-high ledge used to hijack the jump and fling the player away."""
	return _scan_for_wall()

func _scan_for_wall() -> Vector3:
	"""8 world-space directions x 3 heights. Per direction, count how many
	heights hit a near-vertical surface with AGREEING normals; only
	directions reaching min_ray_hits qualify. Returns the nearest
	qualifying wall's normal, or ZERO."""
	var space_state = player.get_world_3d().direct_space_state
	var dirs := [
		Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT,
		Vector3(1, 0, 1).normalized(), Vector3(1, 0, -1).normalized(),
		Vector3(-1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized(),
	]
	var best_normal := Vector3.ZERO
	var best_dist := INF
	for direction in dirs:
		var hits := 0
		var first_normal := Vector3.ZERO
		var nearest := INF
		for height in RAY_HEIGHTS:
			var ray_start = player.global_position + Vector3(0, height, 0)
			var query = PhysicsRayQueryParameters3D.create(ray_start, ray_start + direction * wall_reach)
			query.collision_mask = 1
			query.exclude = [player]
			var result = space_state.intersect_ray(query)
			if not result:
				continue
			if absf(result.normal.y) >= 0.35:
				continue   # Slope or ceiling, not a wall
			if first_normal == Vector3.ZERO:
				first_normal = result.normal
			elif first_normal.angle_to(result.normal) > 0.6:
				continue   # Different surface - doesn't stack up to a wall
			hits += 1
			nearest = minf(nearest, ray_start.distance_to(result.position))
		if hits >= min_ray_hits and nearest < best_dist:
			best_dist = nearest
			best_normal = first_normal
	return best_normal

func check_for_wall_jump():
	if _jump_buffer > 0.0 and can_perform_wall_jump():
		var wall_normal = get_wall_jump_direction()
		if wall_normal.length() > 0.1:
			# In WallJumpingState only allow jumping to a DIFFERENT wall
			# (same rule the state itself used) - otherwise a single wall
			# would be infinitely re-jumpable.
			var current_state_name = state_machine.current_state.get_script().get_global_name()
			if current_state_name == "WallJumpingState":
				var wjs = state_machine.states.get("walljumpingstate")
				if wjs and wjs.wall_direction.length() > 0 and wjs.wall_direction.angle_to(wall_normal) <= 0.5:
					return   # Same wall - keep the buffer, maybe another wall arrives
			_jump_buffer = 0.0
			var wall_jump_state = state_machine.states.get("walljumpingstate")
			if wall_jump_state:
				wall_jump_state.setup_wall_jump(wall_normal)
				if current_state_name == "WallJumpingState":
					# change_state no-ops on same-state: re-enter manually so
					# chained jumps re-run the launch
					wall_jump_state.enter()
				else:
					state_machine.change_state("WallJumpingState")
				wall_jump_cooldown = wall_jump_cooldown_time
