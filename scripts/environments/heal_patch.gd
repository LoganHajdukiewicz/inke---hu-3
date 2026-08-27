@tool
extends Area3D
class_name HealPatch

## A glowing patch of ground that instantly restores EVERYTHING the moment
## you step on it: health to max and the paint meter to full. Re-triggers
## every heal_cooldown seconds while you stand on it, so it doubles as a
## "regen zone" for testing.

@export var patch_size: Vector2 = Vector2(4, 4):
	set(value):
		patch_size = value
		if is_inside_tree():
			_rebuild()
@export var heal_cooldown: float = 0.5      # Re-heal interval while standing on it
@export var patch_color: Color = Color(0.2, 1.0, 0.45)

var _cooldown: float = 0.0
var _pulse_time: float = 0.0
var _glow_mesh: MeshInstance3D

func _ready():
	_rebuild()
	if not Engine.is_editor_hint():
		monitoring = true
		set_deferred("monitorable", false)

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(patch_size.x, 1.2, patch_size.y)
	collision.shape = box
	collision.position.y = 0.6
	add_child(collision)
	
	# Glowing pad
	_glow_mesh = MeshInstance3D.new()
	var pad = CylinderMesh.new()
	pad.top_radius = minf(patch_size.x, patch_size.y) * 0.5
	pad.bottom_radius = pad.top_radius
	pad.height = 0.12
	_glow_mesh.mesh = pad
	var mat = StandardMaterial3D.new()
	mat.albedo_color = patch_color
	mat.emission_enabled = true
	mat.emission = patch_color
	mat.emission_energy_multiplier = 1.4
	_glow_mesh.material_override = mat
	_glow_mesh.position.y = 0.06
	add_child(_glow_mesh)
	
	# A little plus-sign made of two bars so it reads as "healing"
	var bar_mat = StandardMaterial3D.new()
	bar_mat.albedo_color = Color(1, 1, 1)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(1, 1, 1)
	bar_mat.emission_energy_multiplier = 1.2
	for horizontal in [true, false]:
		var bar = MeshInstance3D.new()
		var bm = BoxMesh.new()
		var l = minf(patch_size.x, patch_size.y) * 0.5
		bm.size = Vector3(l, 0.05, l * 0.28) if horizontal else Vector3(l * 0.28, 0.05, l)
		bar.mesh = bm
		bar.material_override = bar_mat
		bar.position.y = 0.15
		add_child(bar)

func _process(delta: float):
	if Engine.is_editor_hint():
		return
	_pulse_time += delta
	if _glow_mesh and _glow_mesh.material_override:
		_glow_mesh.material_override.emission_energy_multiplier = 1.4 + sin(_pulse_time * 3.0) * 0.6
	
	if _cooldown > 0.0:
		_cooldown -= delta
		return
	
	for body in get_overlapping_bodies():
		if body.is_in_group("Player"):
			_heal_everything(body)
			_cooldown = heal_cooldown
			break

func _heal_everything(player: Node):
	var game_manager = get_node_or_null("/root/GameManager")
	var paint_manager = get_node_or_null("/root/PaintManager")
	
	var healed := false
	if game_manager:
		if game_manager.player_health < game_manager.player_max_health:
			game_manager.set_player_health(game_manager.player_max_health)
			healed = true
	if paint_manager:
		if paint_manager.current_paint_amount < paint_manager.max_paint_amount:
			paint_manager.add_paint(paint_manager.max_paint_amount)
			healed = true
	
	if healed:
		_burst_feedback(player)

func _burst_feedback(player: Node):
	"""Rising sparkle ring when a heal actually happens."""
	var parent = get_parent()
	if not parent:
		return
	for i in range(6):
		var spark = MeshInstance3D.new()
		var s = SphereMesh.new()
		s.radius = 0.08
		s.height = 0.16
		spark.mesh = s
		var m = StandardMaterial3D.new()
		m.albedo_color = patch_color
		m.emission_enabled = true
		m.emission = patch_color
		m.emission_energy_multiplier = 2.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = m
		parent.add_child(spark)
		var angle = TAU * i / 6.0
		spark.global_position = player.global_position + Vector3(cos(angle) * 0.7, 0.2, sin(angle) * 0.7)
		var t = spark.create_tween()
		t.set_parallel(true)
		t.tween_property(spark, "global_position:y", spark.global_position.y + 2.0, 0.6).set_ease(Tween.EASE_OUT)
		t.tween_property(m, "albedo_color:a", 0.0, 0.6)
		t.chain().tween_callback(spark.queue_free)
