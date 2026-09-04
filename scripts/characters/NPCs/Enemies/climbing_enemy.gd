extends Enemy
class_name ClimbingEnemy

## A wall-crawler: place it on (or near) a ClimbableWall and it STAYS on the
## wall, skittering around the surface like a spider. It never falls off,
## never chases across the ground - it's a hazard you meet while climbing.
## Fully attackable: punches, spins, grapple strikes and slams all work.
##
## Setup: drop the scene next to a ClimbableWall (or point wall_path at
## one) - it snaps itself onto the surface on ready.

@export_group("Climbing")
## The wall to live on. Leave empty to auto-grab the nearest ClimbableWall.
@export var wall_path: NodePath
## Crawl speed along the wall surface.
@export var crawl_speed: float = 2.5
## Seconds between picking a new crawl direction.
@export var crawl_interval: float = 2.0

@export_group("Patrol Path")
## Waypoints (in WALL-SURFACE space: x = along the wall, y = up the wall)
## relative to where the crawler starts. Edit freely in the Inspector.
## Default: 10 units left, then 10 right - a classic sentry sweep.
@export var patrol_points: Array[Vector2] = [Vector2(-10, 0), Vector2(10, 0)]
## Follow patrol_points instead of wandering randomly.
@export var use_patrol: bool = true
## Pause at each waypoint for this long.
@export var patrol_wait: float = 0.4

var _patrol_index: int = 0
var _patrol_wait_left: float = 0.0
var _patrol_origin: Vector2 = Vector2.ZERO
## How far from the wall's surface the body sits.
@export var surface_offset: float = 0.55

var wall: Node3D = null
var _wall_normal: Vector3 = Vector3.FORWARD
var _wall_right: Vector3 = Vector3.RIGHT
var _wall_up: Vector3 = Vector3.UP
var _half_w: float = 3.5
var _half_h: float = 2.5
var _local_x: float = 0.0    # Position on the wall face
var _local_y: float = 0.0
var _crawl_dir: Vector2 = Vector2.RIGHT
var _crawl_timer: float = 0.0

func _ready():
	super._ready()
	stomp_evade_enabled = false
	_find_wall()
	_snap_to_wall()

func _find_wall():
	if wall_path != NodePath(""):
		wall = get_node_or_null(wall_path)
	if wall == null:
		var best_d := INF
		for w in get_tree().get_nodes_in_group("ClimbableWall"):
			if w is Node3D:
				var d = w.global_position.distance_to(global_position)
				if d < best_d:
					best_d = d
					wall = w

func _snap_to_wall():
	if wall == null:
		return
	var basis = wall.global_transform.basis
	_wall_right = basis.x.normalized()
	_wall_up = basis.y.normalized()
	_wall_normal = basis.z.normalized()
	# Face the side of the wall we spawned on
	if _wall_normal.dot(global_position - wall.global_position) < 0.0:
		_wall_normal = -_wall_normal
	
	var size = wall.get("wall_size")
	if size is Vector3:
		_half_w = size.x * 0.5 - 0.6
		_half_h = size.y * 0.5 - 0.6
	
	var rel = global_position - wall.global_position
	_local_x = clampf(rel.dot(_wall_right), -_half_w, _half_w)
	_local_y = clampf(rel.dot(_wall_up), -_half_h, _half_h)
	_patrol_origin = Vector2(_local_x, _local_y)   # Patrol is relative to spawn
	_apply_wall_position()

func _apply_wall_position():
	global_position = wall.global_position \
		+ _wall_right * _local_x + _wall_up * _local_y \
		+ _wall_normal * surface_offset
	# Back against the wall, facing out along the normal
	var fwd = _wall_normal
	rotation.y = atan2(-(-fwd).x, -(-fwd).z)

func _physics_process(delta: float) -> void:
	# Wall-crawlers OWN their movement: no gravity, no ground AI, no
	# move_and_slide - just skitter across the wall face.
	if damage_cooldown > 0:
		damage_cooldown -= delta
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta
	
	if wall == null or not is_instance_valid(wall):
		# Wall's gone - fall back to normal enemy behavior
		super._physics_process(delta)
		return
	
	var speed = crawl_speed
	var target_dir := _crawl_dir
	
	# NO TRACKING WHATSOEVER (user-mandated): wall crawlers never chase,
	# never guard, never react to the player's position. They walk their
	# patrol path. That is it. They're moving hazards, not hunters.
	if use_patrol and patrol_points.size() > 0:
		# PATROL: walk the waypoint loop (wall-surface space, relative to
		# the spawn point). Ping-pongs A->B->...->A forever.
		if _patrol_wait_left > 0.0:
			_patrol_wait_left -= delta
			target_dir = Vector2.ZERO
		else:
			var goal = _patrol_origin + patrol_points[_patrol_index]
			# Clamp to the wall face so waypoints bigger than the wall still
			# work (the crawler patrols to the edge instead of pinning there)
			goal.x = clampf(goal.x, -_half_w, _half_w)
			goal.y = clampf(goal.y, -_half_h, _half_h)
			var to_goal = goal - Vector2(_local_x, _local_y)
			if to_goal.length() < 0.25:
				_patrol_index = (_patrol_index + 1) % patrol_points.size()
				_patrol_wait_left = patrol_wait
				target_dir = Vector2.ZERO
			else:
				target_dir = to_goal.normalized()
				_crawl_dir = target_dir
	else:
		_crawl_timer -= delta
		if _crawl_timer <= 0.0:
			_crawl_timer = crawl_interval
			var a = randf() * TAU
			_crawl_dir = Vector2(cos(a), sin(a))
			target_dir = _crawl_dir
	
	_local_x += target_dir.x * speed * delta
	_local_y += target_dir.y * speed * delta
	
	# Bounce off the wall edges
	if absf(_local_x) > _half_w:
		_local_x = clampf(_local_x, -_half_w, _half_w)
		_crawl_dir.x = -_crawl_dir.x
	if absf(_local_y) > _half_h:
		_local_y = clampf(_local_y, -_half_h, _half_h)
		_crawl_dir.y = -_crawl_dir.y
	
	_apply_wall_position()
	velocity = Vector3.ZERO

func take_damage(amount: int, _knockback_velocity: Vector3 = Vector3.ZERO):
	# No knockback state for wall-crawlers - they grip the wall. Damage,
	# flash and death all still work.
	if damage_cooldown > 0:
		return
	current_health -= amount
	damage_cooldown = damage_cooldown_time
	flash_color()
	if current_health > 0 and drops_paint_on_hit:
		spawn_paint_droplets()
	if current_health <= 0:
		die()
