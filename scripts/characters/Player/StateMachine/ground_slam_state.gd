extends State
class_name GroundSlamState

## Ground slam: press crouch in the air to hang for a beat, then rocket
## straight down. On impact: AOE damage/knockback to enemies, breaks boxes,
## camera shake and a squash-and-stretch landing.

@export var hang_duration: float = 0.12       # Anticipation pause at the top
@export var slam_speed: float = 45.0           # Downward speed during the slam
@export var impact_radius: float = 4.0         # AOE radius on landing
@export var impact_damage: int = 2             # Damage dealt to enemies in radius
@export var impact_knockback: float = 14.0     # Knockback force on enemies
@export var impact_bounce: float = 4.0         # Small pop back up after landing
@export var camera_shake_intensity: float = 0.35
@export var camera_shake_duration: float = 0.25

var slam_phase: String = "hang"   # "hang" -> "fall" -> done
var hang_timer: float = 0.0

func enter():
	slam_phase = "hang"
	hang_timer = 0.0
	
	# Freeze in the air for a beat (anticipation)
	player.velocity = Vector3.ZERO
	
	# Wind-up: stretch upward slightly
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(0.8, 1.25, 0.8), hang_duration)

func physics_update(delta: float):
	match slam_phase:
		"hang":
			player.velocity = Vector3.ZERO
			hang_timer += delta
			if hang_timer >= hang_duration:
				slam_phase = "fall"
				player.velocity.y = -slam_speed
				# Dive shape
				var tween = create_tween()
				tween.tween_property(player, "scale", Vector3(0.7, 1.35, 0.7), 0.08)
		"fall":
			# Keep slamming straight down (no horizontal drift)
			player.velocity.x = 0.0
			player.velocity.z = 0.0
			player.velocity.y = -slam_speed
			
			if player.is_on_floor():
				_impact()
				return
	
	player.move_and_slide()
	
	# Landed during move_and_slide this frame
	if slam_phase == "fall" and player.is_on_floor():
		_impact()

func _impact():
	"""Landing: AOE damage, screen shake, squash effect"""
	# Squash!
	var tween = create_tween()
	tween.tween_property(player, "scale", Vector3(1.4, 0.55, 1.4), 0.06)
	tween.tween_property(player, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Camera shake
	var camera_controller = player.get_node_or_null("CameraController")
	if camera_controller and camera_controller.has_method("shake"):
		camera_controller.shake(camera_shake_intensity, camera_shake_duration)
	
	# Shockwave ring visual
	_spawn_shockwave_ring()
	
	# AOE: damage enemies and break boxes within radius
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not (enemy is Node3D) or not is_instance_valid(enemy):
			continue
		# HitBox areas are also in the "Enemy" group - only want the bodies
		if not enemy is CharacterBody3D:
			continue
		var to_enemy = enemy.global_position - player.global_position
		if to_enemy.length() > impact_radius:
			continue
		if enemy.has_method("take_damage"):
			var knock_dir = to_enemy.normalized()
			knock_dir.y = 0.4
			enemy.take_damage(impact_damage, knock_dir.normalized() * impact_knockback + Vector3(0, 5, 0))
	
	for box in get_tree().get_nodes_in_group("Breakables"):
		if box is Node3D and is_instance_valid(box):
			if box.global_position.distance_to(player.global_position) <= impact_radius:
				if box.has_method("take_damage"):
					box.take_damage(99)
	
	# Little bounce off the ground
	player.velocity.y = impact_bounce
	
	# Slam refreshes air options (feels great in a platformer)
	player.has_double_jumped = false
	player.can_double_jump = true
	player.has_air_dashed = false
	player.can_air_dash = true
	
	change_to("FallingState")

func _spawn_shockwave_ring():
	"""Expanding ring on the ground to sell the impact"""
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.55
	ring.mesh = torus
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	
	player.get_parent().add_child(ring)
	ring.global_position = player.global_position + Vector3(0, 0.1, 0)
	
	var tween = ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(impact_radius * 1.8, 1.0, impact_radius * 1.8), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(ring.queue_free)

func exit():
	player.scale = Vector3.ONE
