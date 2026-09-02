extends Box
class_name ExplosiveBarrel

## A breakable that EXPLODES when destroyed: damages the player and enemies
## in the blast radius, knocks the player back, chains to other explosives
## and breakables nearby, and pops with a proper fireball flash.
## Any hit (attack, projectile, ground pound bounce, another explosion)
## sets it off.

@export_group("Explosion")
@export var explosion_radius: float = 4.0
@export var explosion_damage: int = 1              # Damage to the player
@export var explosion_enemy_damage: int = 3        # Damage to enemies (they hate barrels)
@export var explosion_knockback: float = 12.0      # Knockback speed at the center
@export var chain_reaction: bool = true            # Set off other explosives in range
@export var chain_delay: float = 0.15              # Fuse delay between chained barrels
@export var fuse_time: float = 0.0                 # Optional delay after being hit before boom
## Explode the moment Inke TOUCHES the barrel (no attack needed). Walk
## into it, land on it, brush past it - boom. Fuse_time still applies.
@export var explode_on_player_contact: bool = false

@export_group("Warning Light")
## Subtle pulsating red glow - reads as "this thing is dangerous".
@export var warning_light_enabled: bool = true
@export var warning_light_color: Color = Color(1.0, 0.12, 0.05)
## Base glow strength (the pulse breathes around this).
@export var warning_light_energy: float = 0.55
## Pulses per second - keep it slow and ominous.
@export var warning_pulse_speed: float = 1.4

var exploding: bool = false
var _warn_light: OmniLight3D = null
var _warn_bulb: MeshInstance3D = null
var _warn_bulb_mat: StandardMaterial3D = null
var _pulse_time: float = 0.0

func _ready():
	super._ready()
	add_to_group("Explosive")
	# Barrels pop in one hit by default
	if max_health > 1:
		max_health = 1
		current_health = 1
	if warning_light_enabled:
		_create_warning_light()
	
	# Contact trigger: reuse the DamageDetection area that already watches
	# for the player - we just react to ANY touch instead of only attacks.
	if explode_on_player_contact and damage_area:
		damage_area.body_entered.connect(_on_contact_body_entered)

func _on_contact_body_entered(body: Node3D) -> void:
	if exploding or is_broken:
		return
	if body.is_in_group("Player"):
		break_crate()

func _create_warning_light():
	# Little bulb on the lid
	_warn_bulb = MeshInstance3D.new()
	var bulb = SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	_warn_bulb.mesh = bulb
	_warn_bulb_mat = StandardMaterial3D.new()
	_warn_bulb_mat.albedo_color = warning_light_color
	_warn_bulb_mat.emission_enabled = true
	_warn_bulb_mat.emission = warning_light_color
	_warn_bulb_mat.emission_energy_multiplier = 1.0
	_warn_bulb.material_override = _warn_bulb_mat
	_warn_bulb.position.y = 1.16
	add_child(_warn_bulb)
	
	# Soft red spill onto the barrel and nearby floor
	_warn_light = OmniLight3D.new()
	_warn_light.light_color = warning_light_color
	_warn_light.light_energy = warning_light_energy
	_warn_light.omni_range = 2.6
	_warn_light.omni_attenuation = 1.6
	_warn_light.shadow_enabled = false     # Cheap - many barrels, no shadows
	_warn_light.position.y = 1.2
	add_child(_warn_light)

func _process(delta: float) -> void:
	if not _warn_light or exploding:
		return
	_pulse_time += delta
	# Slow sine breathe with a soft "heartbeat" double-thump feel
	var s = sin(_pulse_time * TAU * warning_pulse_speed)
	var pulse = 0.5 + 0.5 * s
	pulse = pulse * pulse    # Bias toward dim - the bright peak feels like a blink
	_warn_light.light_energy = warning_light_energy * (0.45 + pulse * 1.1)
	if _warn_bulb_mat:
		_warn_bulb_mat.emission_energy_multiplier = 0.6 + pulse * 2.4

func break_crate():
	"""Overridden: instead of quietly breaking, BOOM."""
	if is_broken or exploding:
		return
	exploding = true
	
	if fuse_time > 0.0:
		# Fizzle warning: rapid flash while the fuse burns
		_fuse_flash()
		await get_tree().create_timer(fuse_time).timeout
		if not is_instance_valid(self):
			return
	
	is_broken = true
	explode()

func _fuse_flash():
	# Fuse burning: the warning light goes frantic
	if _warn_light:
		warning_pulse_speed = 8.0
		warning_light_energy = 1.6
	if not mesh or not is_instance_valid(mesh):
		return
	var material = mesh.get_active_material(0)
	if material is StandardMaterial3D:
		var tween = create_tween()
		tween.set_loops(int(max(fuse_time / 0.12, 1)))
		tween.tween_property(material, "albedo_color", Color(1, 0.3, 0.1), 0.06)
		tween.tween_property(material, "albedo_color", Color(1, 0.9, 0.4), 0.06)

func explode():
	var center = global_position
	
	# --- Damage & knockback everything in the radius ---
	# Player
	for p in get_tree().get_nodes_in_group("Player"):
		if not is_instance_valid(p):
			continue
		var d = p.global_position.distance_to(center)
		if d <= explosion_radius:
			var away = (p.global_position - center)
			away.y = 0
			away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
			if p.has_method("take_damage"):
				p.take_damage(explosion_damage, away)
			# Blast knockback (scaled down with distance)
			var falloff = 1.0 - (d / explosion_radius) * 0.6
			if "velocity" in p:
				p.velocity += away * explosion_knockback * falloff
				p.velocity.y = maxf(p.velocity.y, 6.0 * falloff)
	
	# Enemies
	for e in get_tree().get_nodes_in_group("Enemy"):
		if not (e is CharacterBody3D) or not is_instance_valid(e):
			continue
		var d = e.global_position.distance_to(center)
		if d <= explosion_radius and e.has_method("take_damage"):
			var away = (e.global_position - center)
			away.y = 0.3
			away = away.normalized() * explosion_knockback
			e.take_damage(explosion_enemy_damage, away)
	
	# Other breakables & chained explosives
	for b in get_tree().get_nodes_in_group("Breakables"):
		if b == self or not is_instance_valid(b):
			continue
		var d = b.global_position.distance_to(center)
		if d > explosion_radius:
			continue
		if chain_reaction and b is ExplosiveBarrel and not b.exploding:
			# Chain with a short fuse so barrel lines pop-pop-pop
			b.exploding = true
			get_tree().create_timer(chain_delay).timeout.connect(func():
				if is_instance_valid(b):
					b.exploding = false
					b.call_deferred("break_crate")
			)
		elif b.has_method("take_damage"):
			b.call_deferred("take_damage", 99)
	
	# --- Visuals ---
	_spawn_explosion_visual(center)
	
	# Loot + cleanup (reuse Box pipeline pieces)
	spawn_loot()
	if collision:
		collision.set_deferred("disabled", true)
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	if mesh:
		mesh.visible = false
	
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(self):
		queue_free()

func _spawn_explosion_visual(center: Vector3):
	"""Expanding fireball + smoke puffs + scorch flash. All cheap tweens."""
	var parent = get_parent()
	if not parent:
		return
	
	# Fireball: expanding, fading sphere
	var fireball = MeshInstance3D.new()
	var ball = SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	fireball.mesh = ball
	var fire_mat = StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.4, 0.05)
	fire_mat.emission_energy_multiplier = 3.0
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fireball.material_override = fire_mat
	parent.add_child(fireball)
	fireball.global_position = center
	
	var t = fireball.create_tween()
	t.set_parallel(true)
	t.tween_property(fireball, "scale", Vector3.ONE * explosion_radius * 1.6, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(fire_mat, "albedo_color:a", 0.0, 0.35).set_delay(0.08)
	t.chain().tween_callback(fireball.queue_free)
	
	# Smoke puffs
	for i in range(8):
		var puff = MeshInstance3D.new()
		var s = SphereMesh.new()
		var r = randf_range(0.2, 0.45)
		s.radius = r
		s.height = r * 2.0
		puff.mesh = s
		var smoke_mat = StandardMaterial3D.new()
		smoke_mat.albedo_color = Color(0.25, 0.22, 0.2, 0.7)
		smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = smoke_mat
		parent.add_child(puff)
		puff.global_position = center + Vector3(randf_range(-0.4, 0.4), randf_range(0, 0.5), randf_range(-0.4, 0.4))
		
		var angle = randf() * TAU
		var target = puff.global_position + Vector3(cos(angle) * randf_range(1.0, 2.5), randf_range(1.0, 2.8), sin(angle) * randf_range(1.0, 2.5))
		var pt = puff.create_tween()
		pt.set_parallel(true)
		pt.tween_property(puff, "global_position", target, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pt.tween_property(puff, "scale", Vector3.ONE * 2.2, 0.7)
		pt.tween_property(smoke_mat, "albedo_color:a", 0.0, 0.7).set_delay(0.15)
		pt.chain().tween_callback(puff.queue_free)
