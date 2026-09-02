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
## How far from the wall's surface the body sits.
@export var surface_offset: float = 0.55
## Chase the player along the wall when they're climbing near us?
@export var guards_wall: bool = true
## Range (along the wall) to start guarding.
@export var guard_range: float = 7.0

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
	
	# Guard mode: if the player is close to our wall, slide toward them
	if guards_wall and player and is_instance_valid(player) and player.is_inside_tree():
		var rel = player.global_position - wall.global_position
		var px = rel.dot(_wall_right)
		var py = rel.dot(_wall_up)
		var off_wall = absf(rel.dot(_wall_normal))
		if off_wall < 3.0 and Vector2(px - _local_x, py - _local_y).length() < guard_range:
			target_dir = Vector2(px - _local_x, py - _local_y)
			if target_dir.length() > 0.3:
				target_dir = target_dir.normalized()
				speed = crawl_speed * 1.6
			else:
				target_dir = Vector2.ZERO
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
