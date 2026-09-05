extends Enemy
class_name ChargerEnemy

## BULL CHARGER: locks onto you, paws the ground (telegraph), then CHARGES
## in a dead-straight line at high speed. It can't steer mid-charge - dodge
## sideways and it slams into whatever's behind you and STUNS itself
## (that's your punish window). Repositions and tries again.

@export_group("Charge")
@export var charge_speed: float = 22.0
@export var windup_time: float = 0.8       # Pawing telegraph before launch
@export var charge_max_time: float = 2.0   # Gives up if it hits nothing
@export var stun_time: float = 2.2         # Punish window after wall slam
@export var charge_range: float = 16.0     # Starts a charge inside this
@export var charge_damage: int = 2

enum CPhase { ROAM, WINDUP, CHARGING, STUNNED, RECOVER }
var _phase: CPhase = CPhase.ROAM
var _phase_left: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _base_color: Color
var _mat: StandardMaterial3D

func _ready():
	super._ready()
	if mesh:
		if mesh.material_override:
			_mat = mesh.material_override.duplicate()
		else:
			_mat = StandardMaterial3D.new()
			_mat.albedo_color = Color(0.75, 0.25, 0.15)
		mesh.material_override = _mat
		_base_color = _mat.albedo_color

func _physics_process(delta: float) -> void:
	if damage_cooldown > 0:
		damage_cooldown -= delta
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	match _phase:
		CPhase.ROAM:
			# Default enemy AI handles wander/chase until in charge range
			if player and is_instance_valid(player) and can_see_player():
				var d = global_position.distance_to(player.global_position)
				if d < charge_range and d > 3.0:
					_phase = CPhase.WINDUP
					_phase_left = windup_time
					velocity.x = 0; velocity.z = 0
					# Aim NOW - the charge goes where you were at windup start
					var to_p = player.global_position - global_position
					_charge_dir = Vector3(to_p.x, 0, to_p.z).normalized()
					_look_along(_charge_dir)
					move_and_slide()
					return
			super._physics_process(delta)
			return
		CPhase.WINDUP:
			_phase_left -= delta
			# Pawing: rock back and flash
			var t = 1.0 - _phase_left / windup_time
			if _mat:
				_mat.albedo_color = _base_color.lerp(Color(1, 0.3, 0.1), sin(t * 20.0) * 0.5 + 0.5)
			velocity.x = -_charge_dir.x * 1.5
			velocity.z = -_charge_dir.z * 1.5
			if _phase_left <= 0.0:
				_phase = CPhase.CHARGING
				_phase_left = charge_max_time
				if _mat: _mat.albedo_color = Color(1, 0.25, 0.05)
		CPhase.CHARGING:
			_phase_left -= delta
			velocity.x = _charge_dir.x * charge_speed
			velocity.z = _charge_dir.z * charge_speed
			_look_along(_charge_dir)
			# Hit the player?
			if player and is_instance_valid(player):
				if global_position.distance_to(player.global_position) < 1.6:
					if player.has_method("take_damage"):
						player.take_damage(charge_damage, _charge_dir * 14.0 + Vector3.UP * 6.0)
					_enter_stun(0.8)   # Brief self-stagger on connect
			# Slammed a wall?
			if is_on_wall():
				_enter_stun(stun_time)
				# Impact feedback
				Sfx.play_3d(self, Sfx.slam_boom(), global_position, -4.0, 1.4)
			elif _phase_left <= 0.0:
				_phase = CPhase.RECOVER
				_phase_left = 1.0
		CPhase.STUNNED:
			_phase_left -= delta
			velocity.x = 0; velocity.z = 0
			# Wobble while dazed
			rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.12
			if _phase_left <= 0.0:
				rotation.z = 0.0
				if _mat: _mat.albedo_color = _base_color
				_phase = CPhase.RECOVER
				_phase_left = 0.6
		CPhase.RECOVER:
			_phase_left -= delta
			velocity.x = 0; velocity.z = 0
			if _phase_left <= 0.0:
				_phase = CPhase.ROAM
	
	if damage_cooldown > 0:
		pass
	move_and_slide()

func _enter_stun(duration: float) -> void:
	_phase = CPhase.STUNNED
	_phase_left = duration
	velocity = Vector3.ZERO
	if _mat: _mat.albedo_color = Color(0.9, 0.8, 0.2)

func _look_along(dir: Vector3) -> void:
	if dir.length() > 0.1:
		rotation.y = atan2(-dir.x, -dir.z)

func take_damage(amount: int, knockback_velocity: Vector3 = Vector3.ZERO):
	# Double damage while stunned (the whole point of dodging the charge)
	if _phase == CPhase.STUNNED:
		super.take_damage(amount * 2, knockback_velocity)
	else:
		super.take_damage(amount, knockback_velocity)
