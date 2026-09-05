extends Enemy
class_name HopperEnemy

## HOPPER: a springy inkling that bounds toward you in big arcing leaps and
## tries to land ON you. It's a rhythm enemy - it can't steer mid-air, so
## sidestep the landing and smack it during its crouch. Landing leaves a
## small ink splat shockwave, so don't stand right at the impact point.

@export_group("Hopping")
@export var hop_forward_speed: float = 9.0
@export var hop_up_speed: float = 11.0
@export var hop_interval: float = 1.1      # Crouch time between hops
@export var hop_range: float = 20.0        # Starts hopping toward you inside this
@export var splat_radius: float = 2.2      # Landing shockwave radius
@export var splat_damage: int = 1

var _crouch_left: float = 0.5
var _was_airborne: bool = false
var _squash: float = 0.0

func _ready():
	super._ready()
	if mesh and mesh.material_override == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.8, 0.4)
		mesh.material_override = m

func _physics_process(delta: float) -> void:
	if damage_cooldown > 0:
		damage_cooldown -= delta
	
	if not is_on_floor():
		velocity.y -= gravity * delta
		_was_airborne = true
		# Stretch in the air
		_squash = lerpf(_squash, -0.25, 8.0 * delta)
	else:
		if _was_airborne:
			_was_airborne = false
			_land_splat()
			_squash = 0.35   # Squash on landing
			_crouch_left = hop_interval
		velocity.x = 0
		velocity.z = 0
		_squash = lerpf(_squash, 0.0, 6.0 * delta)
		_crouch_left -= delta
		if _crouch_left <= 0.0 and player and is_instance_valid(player) and can_see_player():
			var d = global_position.distance_to(player.global_position)
			if d < hop_range:
				_hop_at_player()
	
	# Apply squash/stretch to the mesh
	if mesh:
		mesh.scale = Vector3(1.0 + _squash, 1.0 - _squash, 1.0 + _squash)
	
	move_and_slide()

func _hop_at_player() -> void:
	# Aim at where the player IS (not leading) - dodgeable by moving
	var to_p = player.global_position - global_position
	var flat = Vector3(to_p.x, 0, to_p.z)
	var dist = flat.length()
	if dist < 0.5:
		flat = -global_transform.basis.z
	var dir = flat.normalized()
	# Scale forward speed so short hops don't overshoot
	var fwd = minf(hop_forward_speed, dist * 1.2)
	velocity = dir * fwd + Vector3(0, hop_up_speed, 0)
	rotation.y = atan2(-dir.x, -dir.z)

func _land_splat() -> void:
	"""Ink splat shockwave on landing: small AoE + visual ring."""
	# Damage the player if close
	if player and is_instance_valid(player):
		if global_position.distance_to(player.global_position) < splat_radius and player.is_on_floor():
			if player.has_method("take_damage"):
				var kb = (player.global_position - global_position).normalized() * 6.0 + Vector3.UP * 4.0
				player.take_damage(splat_damage, kb)
	# Visual ring
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.45
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.8, 0.4, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = m
	get_parent().add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.1, 0)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(splat_radius * 2.2, 1.0, splat_radius * 2.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(ring.queue_free)
