extends Enemy
class_name CowardEnemy

## Spyro egg-thief style: never attacks, RUNS AWAY along a track.
##
## Setup: make this a CHILD of a Path3D (the track), or point track_path at
## one. When the player gets close, the coward sprints along the track in
## whichever direction leads away from the player, taunting as it goes.
## Catch it (attack or stomp) and it drops its loot. On a closed loop it
## just keeps running; on an open path it turns around at the ends.
##
## If it has no track at all, it falls back to free-run fleeing.

@export_group("Coward")
@export var track_path: NodePath              # Path3D track to flee along (optional if parented to one)
@export var flee_speed: float = 9.5           # A touch faster than the player's walk
@export var scare_distance: float = 8.0       # Start fleeing when player is this close
@export var calm_distance: float = 14.0       # Stop fleeing when player is this far
@export var taunt_enabled: bool = true        # Cheeky hop while fleeing

var track: Path3D = null
var track_progress: float = 0.0
var track_is_loop: bool = false
var fleeing: bool = false
var taunt_timer: float = 0.0

func _ready():
	super._ready()
	# Cowards don't fight
	stomp_evade_enabled = false
	damage_to_player = 0
	
	# Find the track
	if track_path != NodePath(""):
		track = get_node_or_null(track_path) as Path3D
	if not track and get_parent() is Path3D:
		track = get_parent() as Path3D
	
	if track and track.curve:
		track_is_loop = track.curve.point_count > 2 \
			and track.curve.get_point_position(0).distance_to(
				track.curve.get_point_position(track.curve.point_count - 1)) < 1.0
		# Start at the closest point on the track
		var local = track.to_local(global_position)
		track_progress = track.curve.get_closest_offset(local)
		global_position = track.to_global(track.curve.sample_baked(track_progress))

func get_attack_state_name() -> String:
	# Cowards never attack; if the brain asks, just keep "chasing" (fleeing)
	return "aichasestate"

func _physics_process(delta: float) -> void:
	# Fully replace the AI: fear is the only state machine we need.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	var dist_to_player := INF
	if player and is_instance_valid(player) and player.is_inside_tree():
		dist_to_player = global_position.distance_to(player.global_position)
	
	if fleeing:
		if dist_to_player > calm_distance:
			fleeing = false
	else:
		if dist_to_player < scare_distance:
			fleeing = true
			_yelp()
	
	if fleeing:
		if track and track.curve:
			_flee_along_track(delta)
		else:
			_flee_freely(delta)
		# Cheeky taunt hop
		if taunt_enabled and is_on_floor():
			taunt_timer -= delta
			if taunt_timer <= 0.0:
				velocity.y = 3.5
				taunt_timer = randf_range(0.9, 1.6)
	else:
		# Idle: stand around glancing nervously
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		if player and is_instance_valid(player) and dist_to_player < scare_distance * 2.0:
			var to_p = player.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-to_p.x, -to_p.z), 4.0 * delta)
	
	move_and_slide()

func _flee_along_track(delta: float):
	"""Run along the Path3D in whichever direction increases distance from
	the player. Loops wrap around; open paths reverse at the ends."""
	var curve = track.curve
	var length = curve.get_baked_length()
	if length < 0.5:
		_flee_freely(delta)
		return
	
	# Which way along the track is AWAY from the player?
	var probe = 1.5
	var fwd_off = _wrap_offset(track_progress + probe, length)
	var back_off = _wrap_offset(track_progress - probe, length)
	var fwd_pos = track.to_global(curve.sample_baked(fwd_off))
	var back_pos = track.to_global(curve.sample_baked(back_off))
	var p = player.global_position if (player and is_instance_valid(player)) else global_position
	var direction: float = 1.0 if fwd_pos.distance_to(p) >= back_pos.distance_to(p) else -1.0
	
	track_progress += direction * flee_speed * delta
	if track_is_loop:
		track_progress = _wrap_offset(track_progress, length)
	else:
		track_progress = clampf(track_progress, 0.0, length)
	
	var target = track.to_global(curve.sample_baked(track_progress))
	var to_target = target - global_position
	to_target.y = 0
	
	if to_target.length() > 0.05:
		var dir = to_target.normalized()
		velocity.x = dir.x * flee_speed
		velocity.z = dir.z * flee_speed
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)
	else:
		velocity.x = 0
		velocity.z = 0

func _wrap_offset(offset: float, length: float) -> float:
	if track_is_loop:
		return fposmod(offset, length)
	return clampf(offset, 0.0, length)

func _flee_freely(delta: float):
	"""No track: just run directly away from the player."""
	if not player or not is_instance_valid(player):
		return
	var away = global_position - player.global_position
	away.y = 0
	if away.length() < 0.1:
		away = Vector3.FORWARD
	var dir = away.normalized()
	velocity.x = dir.x * flee_speed
	velocity.z = dir.z * flee_speed
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 10.0 * delta)

func _yelp():
	"""Startled feedback when the player gets close."""
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.85, 1.25, 0.85), 0.1)
	tween.tween_property(self, "scale", Vector3.ONE, 0.15)
