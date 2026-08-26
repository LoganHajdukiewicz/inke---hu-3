extends Enemy
class_name LaserEnemy

## Ranged enemy: locks on with a harmless red laser SIGHT for aim_duration
## (2s), then FIRES a thick beam that damages the player. The sight tracks
## the player while aiming, but the fired beam is locked to where the sight
## ended - so you dodge by moving during/after the telegraph.

@export_group("Laser")
@export var laser_range: float = 18.0          # Max beam length
@export var aim_duration: float = 2.0          # Harmless laser-sight telegraph time
@export var fire_duration: float = 0.35        # How long the damaging beam stays on
@export var laser_damage: int = 1              # Damage if the beam hits you
@export var laser_cooldown: float = 2.5        # Time between shots
@export var aim_turn_speed: float = 3.0        # How fast the sight tracks the player
@export var preferred_shoot_range: float = 14.0  # Tries to shoot from this far away
@export var sight_color: Color = Color(1.0, 0.15, 0.15, 0.55)
@export var beam_color: Color = Color(1.0, 0.35, 0.1, 0.95)

var laser_visual: MeshInstance3D = null
var laser_material: StandardMaterial3D = null
var muzzle_height: float = 0.75

func _ready():
	super._ready()
	# Laser enemies engage from range
	attack_cooldown = laser_cooldown
	_create_laser_visual()

func get_attack_state_name() -> String:
	return "ailaserstate"

func get_preferred_attack_range() -> float:
	return preferred_shoot_range

func _register_extra_states(extra_states: Dictionary) -> void:
	var laser_state = AILaserState.new()
	extra_states["ailaserstate"] = laser_state

func _create_laser_visual():
	laser_visual = MeshInstance3D.new()
	laser_visual.name = "LaserBeam"
	var box = BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 1.0)  # Scaled along Z at runtime
	laser_visual.mesh = box
	
	laser_material = StandardMaterial3D.new()
	laser_material.albedo_color = sight_color
	laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_material.emission_enabled = true
	laser_material.emission = Color(1, 0.1, 0.1)
	laser_material.emission_energy_multiplier = 2.0
	laser_visual.material_override = laser_material
	laser_visual.visible = false
	# top_level so beam coordinates are world-space, unaffected by body tilt
	laser_visual.top_level = true
	add_child(laser_visual)

func show_laser(from: Vector3, to: Vector3, is_firing: bool):
	"""Stretch the beam box between two world points."""
	if not laser_visual:
		return
	laser_visual.visible = true
	var mid = (from + to) * 0.5
	var length = from.distance_to(to)
	laser_visual.global_position = mid
	if length > 0.01:
		laser_visual.look_at(to, Vector3.UP)
	laser_visual.scale = Vector3(3.0 if is_firing else 1.0, 3.0 if is_firing else 1.0, length)
	laser_material.albedo_color = beam_color if is_firing else sight_color

func hide_laser():
	if laser_visual:
		laser_visual.visible = false

func cast_laser(direction: Vector3) -> Dictionary:
	"""Raycast the beam. Returns { end: Vector3, hit_player: bool }."""
	var from = global_position + Vector3(0, muzzle_height, 0)
	var to = from + direction.normalized() * laser_range
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [self]
	# Don't let our own areas block the ray
	query.collide_with_areas = false
	var result = space_state.intersect_ray(query)
	if result:
		var hit_player = result.collider != null and result.collider.is_in_group("Player")
		return {"from": from, "end": result.position, "hit_player": hit_player, "collider": result.collider}
	return {"from": from, "end": to, "hit_player": false, "collider": null}


# ============================================
# AI LASER STATE: aim (2s, harmless) -> fire (damaging) -> cooldown
# ============================================

class AILaserState extends EnemyState:
	var phase: String = "aim"
	var timer: float = 0.0
	var aim_direction: Vector3 = Vector3.FORWARD
	var has_dealt_damage: bool = false
	
	func enter():
		phase = "aim"
		timer = 0.0
		has_dealt_damage = false
		enemy.velocity.x = 0
		enemy.velocity.z = 0
		# Start aiming straight at the player
		if enemy.player:
			var to_player = _aim_point() - _muzzle()
			if to_player.length() > 0.1:
				aim_direction = to_player.normalized()
	
	func _muzzle() -> Vector3:
		return enemy.global_position + Vector3(0, enemy.muzzle_height, 0)
	
	func _aim_point() -> Vector3:
		# Aim at the player's chest
		return enemy.player.global_position + Vector3(0, 0.75, 0)
	
	func update(delta: float):
		var laser_enemy := enemy as LaserEnemy
		if not enemy.player or not enemy.player.is_inside_tree():
			laser_enemy.hide_laser()
			enemy.state_machine.change_state("aiidlestate")
			return
		
		timer += delta
		enemy.velocity.x = 0
		enemy.velocity.z = 0
		
		match phase:
			"aim":
				# Laser SIGHT: tracks the player, deals NO damage
				var to_player = _aim_point() - _muzzle()
				if to_player.length() > 0.1:
					var desired = to_player.normalized()
					aim_direction = aim_direction.slerp(desired, clampf(laser_enemy.aim_turn_speed * delta, 0.0, 1.0)).normalized()
				
				# Face along the aim
				var flat = Vector3(aim_direction.x, 0, aim_direction.z)
				if flat.length() > 0.1:
					flat = flat.normalized()
					enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(-flat.x, -flat.z), delta * 6.0)
				
				var cast = laser_enemy.cast_laser(aim_direction)
				# Blink the sight faster as firing approaches
				var blink_rate = lerpf(6.0, 20.0, timer / laser_enemy.aim_duration)
				var visible_now = fmod(timer * blink_rate, 2.0) < 1.4
				if visible_now:
					laser_enemy.show_laser(cast.from, cast.end, false)
				else:
					laser_enemy.hide_laser()
				
				if timer >= laser_enemy.aim_duration:
					phase = "fire"
					timer = 0.0
			"fire":
				# Beam is LOCKED to the final aim direction - dodge it!
				var cast = laser_enemy.cast_laser(aim_direction)
				laser_enemy.show_laser(cast.from, cast.end, true)
				
				if cast.hit_player and not has_dealt_damage:
					has_dealt_damage = true
					var target = cast.collider
					if target and target.has_method("take_damage"):
						var knock = (target.global_position - enemy.global_position)
						knock.y = 0
						target.take_damage(laser_enemy.laser_damage, knock.normalized())
				
				if timer >= laser_enemy.fire_duration:
					laser_enemy.hide_laser()
					enemy.attack_cooldown_timer = laser_enemy.laser_cooldown
					enemy.state_machine.change_state("aichasestate")
	
	func exit():
		var laser_enemy := enemy as LaserEnemy
		if laser_enemy:
			laser_enemy.hide_laser()
