extends Enemy
class_name TurretEnemy

## Stationary turret: doesn't chase - it plants itself and LOBS slow arcing
## shots at the player from range. Easy to dodge, dangerous to ignore.
## Its barrel visibly tracks you and glows before each shot, and it can't
## hit anything close up (minimum range) - rushing it is the counter.

@export_group("Turret")
@export var fire_range: float = 18.0        # Starts shooting inside this
@export var min_range: float = 3.0          # Can't shoot closer than this (rush it!)
@export var shot_interval: float = 2.2      # Seconds between shots
@export var shot_speed: float = 10.0        # Projectile launch speed
@export var shot_arc: float = 4.0           # Extra upward lob
@export var shot_damage: int = 1
@export var windup_time: float = 0.55       # Barrel glow before firing
@export var shot_color: Color = Color(1.0, 0.4, 0.9)

var _barrel: MeshInstance3D
var _barrel_mat: StandardMaterial3D
var _shot_timer: float = 1.0
var _winding_up: float = 0.0

func _ready():
	super._ready()
	_build_barrel()

func _build_barrel():
	_barrel = MeshInstance3D.new()
	var m = CylinderMesh.new()
	m.top_radius = 0.12
	m.bottom_radius = 0.18
	m.height = 0.9
	_barrel.mesh = m
	_barrel_mat = StandardMaterial3D.new()
	_barrel_mat.albedo_color = Color(0.3, 0.3, 0.35)
	_barrel_mat.metallic = 0.6
	_barrel.material_override = _barrel_mat
	_barrel.position = Vector3(0, 1.0, -0.4)
	_barrel.rotation_degrees.x = -80.0   # Tilted up-forward like a mortar
	add_child(_barrel)

func _physics_process(delta: float) -> void:
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	# Turrets NEVER move: no chase/wander AI, just gravity so they sit on
	# the ground. They aim and shoot instead.
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.x = 0
		velocity.z = 0
	move_and_slide()
	
	if not player or not is_instance_valid(player):
		return
	
	var to_player = player.global_position - global_position
	var dist = to_player.length()
	
	# Track the player with the whole body (barrel points where we face)
	if dist < fire_range * 1.3:
		var flat = Vector3(to_player.x, 0, to_player.z)
		if flat.length() > 0.1:
			var target_yaw = atan2(-flat.x, -flat.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 6.0 * delta)
	
	# Fire cycle
	var can_fire = dist <= fire_range and dist >= min_range and can_see_player()
	if _winding_up > 0.0:
		_winding_up -= delta
		# Glow builds as the shot charges
		var t = 1.0 - clampf(_winding_up / windup_time, 0.0, 1.0)
		_barrel_mat.emission_enabled = true
		_barrel_mat.emission = shot_color * t
		_barrel_mat.emission_energy_multiplier = t * 2.0
		if _winding_up <= 0.0:
			_fire()
			_barrel_mat.emission_enabled = false
	elif can_fire:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_timer = shot_interval
			_winding_up = windup_time
	else:
		_shot_timer = minf(_shot_timer, 0.5)   # Quick first shot when re-acquired

func _fire():
	if not player or not is_instance_valid(player):
		return
	var proj = _make_projectile()
	get_parent().add_child(proj)
	proj.global_position = _barrel.global_position + Vector3(0, 0.3, 0)
	# Lob toward the player: flat aim + upward arc
	var to_player = player.global_position - proj.global_position
	var flat = Vector3(to_player.x, 0, to_player.z)
	var vel = flat.normalized() * shot_speed + Vector3(0, shot_arc, 0)
	proj.set_meta("vel", vel)
	# Recoil kick
	var tween = create_tween()
	tween.tween_property(_barrel, "position:z", -0.55, 0.05)
	tween.tween_property(_barrel, "position:z", -0.4, 0.2)

func _make_projectile() -> Area3D:
	var proj := Area3D.new()
	proj.collision_layer = 0
	proj.collision_mask = 1
	var mi = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	mi.mesh = s
	var mat = StandardMaterial3D.new()
	mat.albedo_color = shot_color
	mat.emission_enabled = true
	mat.emission = shot_color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	proj.add_child(mi)
	var cs = CollisionShape3D.new()
	var sh = SphereShape3D.new()
	sh.radius = 0.25
	cs.shape = sh
	proj.add_child(cs)
	# Simple ballistic flight via script-less physics: integrate in a tween-like loop
	var dmg = shot_damage
	proj.body_entered.connect(func(body: Node3D):
		if body.is_in_group("Player") and body.has_method("take_damage"):
			var kb = (body.global_position - proj.global_position).normalized() * 5.0 + Vector3.UP * 3.0
			body.take_damage(dmg, kb)
		if not body.is_in_group("Enemy"):
			proj.queue_free()
	)
	# Ballistic flight + lifetime handled by a small mover child
	proj.add_child(_ProjMover.new())
	return proj

class _ProjMover extends Node:
	## Moves the parent Area3D along its "vel" meta with gravity, 6s lifetime.
	var _life := 0.0
	func _physics_process(delta: float):
		var p = get_parent() as Area3D
		if p == null:
			return
		var vel: Vector3 = p.get_meta("vel", Vector3.ZERO)
		vel += Vector3(0, -12.0, 0) * delta
		p.set_meta("vel", vel)
		p.global_position += vel * delta
		_life += delta
		if _life > 6.0 or p.global_position.y < -50.0:
			p.queue_free()
