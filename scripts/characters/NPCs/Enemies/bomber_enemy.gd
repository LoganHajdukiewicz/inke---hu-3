extends Enemy
class_name BomberEnemy

## Kamikaze bomber: waddles around until it sees you, then RUSHES you with
## a lit fuse and explodes. Kill it before it reaches you (it pops harmlessly
## for you and damages nearby enemies), stomp it, or just outrun the blast.
## Its whole body blinks faster and faster as the fuse burns down.

@export_group("Bomb")
@export var fuse_time: float = 1.6            # Seconds from spotting you to boom
@export var blast_radius: float = 3.5
@export var blast_damage: int = 2
@export var rush_speed: float = 11.0          # Faster than a normal chase
@export var blink_color: Color = Color(1.0, 0.25, 0.1)

var fuse_lit: bool = false
var fuse_left: float = 0.0
var _blink_time: float = 0.0
var _base_color: Color
var _mat: StandardMaterial3D

func _ready():
	super._ready()
	if mesh:
		if mesh.material_override:
			_mat = mesh.material_override.duplicate()
		else:
			_mat = StandardMaterial3D.new()
			_mat.albedo_color = Color(0.9, 0.5, 0.15)
		mesh.material_override = _mat
		_base_color = _mat.albedo_color

func _physics_process(delta: float) -> void:
	# Light the fuse the moment we can see the player
	if not fuse_lit and can_see_player() and not is_dead():
		fuse_lit = true
		fuse_left = fuse_time
		chase_speed = rush_speed   # RUSH!
	
	if fuse_lit:
		fuse_left -= delta
		# Blink faster as the fuse runs out
		_blink_time += delta * lerpf(6.0, 26.0, 1.0 - clampf(fuse_left / fuse_time, 0.0, 1.0))
		if _mat:
			var on = fmod(_blink_time, 1.0) < 0.5
			_mat.albedo_color = blink_color if on else _base_color
			_mat.emission_enabled = on
			_mat.emission = blink_color * 0.8
		# Swell up right before popping
		var t = 1.0 - clampf(fuse_left / fuse_time, 0.0, 1.0)
		scale = Vector3.ONE * (1.0 + t * 0.25)
		if fuse_left <= 0.0:
			_detonate()
			return
	
	super._physics_process(delta)

func is_dead() -> bool:
	return current_health <= 0

func _detonate():
	"""BOOM. Damages the player if in range (with knockback), then dies."""
	var blast_center = global_position
	# Visual: expanding flash sphere
	var flash = MeshInstance3D.new()
	var s = SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	flash.mesh = s
	var fm = StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.6, 0.15, 0.85)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.5, 0.1)
	fm.emission_energy_multiplier = 2.0
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = fm
	get_parent().add_child(flash)
	flash.global_position = blast_center
	var tween = flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * blast_radius * 2.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(fm, "albedo_color:a", 0.0, 0.35)
	tween.chain().tween_callback(flash.queue_free)
	
	# Boom sound (reuse the slam boom)
	Sfx.play_3d(self, Sfx.slam_boom(), blast_center, 2.0)
	
	# Damage the player if in range
	if player and is_instance_valid(player):
		var to_player = player.global_position - blast_center
		if to_player.length() <= blast_radius:
			var kb = (to_player.normalized() + Vector3.UP) * 9.0
			if player.has_method("take_damage"):
				player.take_damage(blast_damage, kb)
	
	# Damage other enemies caught in the blast (chain reactions!)
	for e in get_tree().get_nodes_in_group("Enemy"):
		if e == self or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(blast_center) <= blast_radius and e.has_method("take_damage"):
			e.take_damage(blast_damage)
	
	die()

func die():
	# Killed BEFORE detonating = safe pop, no player damage
	super.die()
