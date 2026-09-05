extends Enemy
class_name SplitterEnemy

## SPLITTER: a big wobbly ink blob that SPLITS IN TWO when killed - each
## half is a smaller, faster blob. Halves split once more into minis.
## One becomes three fights: crowd control practice, and great gear piñata.

@export_group("Splitting")
## How many generations of splits remain (2 = big->half->mini, then done).
@export var split_generations: int = 2
## How many children each death spawns.
@export var split_count: int = 2
## Scale/health/speed multipliers per generation down.
@export var child_scale: float = 0.65
@export var child_health: int = 2

var _generation: int = 0   # 0 = the original big blob

func _ready():
	super._ready()
	if mesh and mesh.material_override == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.25, 0.75)
		mesh.material_override = m
	# Blob wobble
	if mesh:
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(mesh, "scale", Vector3(1.08, 0.92, 1.08), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(mesh, "scale", Vector3(0.94, 1.06, 0.94), 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func die():
	if split_generations > 0:
		_split()
	super.die()

func _split() -> void:
	"""Spawn split_count smaller copies that scatter outward."""
	var parent = get_parent()
	if parent == null:
		return
	for i in range(split_count):
		var child = duplicate() as SplitterEnemy
		# Configure the child BEFORE adding (its _ready reads these)
		child.split_generations = split_generations - 1
		child._generation = _generation + 1
		child.max_health = child_health
		child.current_health = child_health
		child.chase_speed = chase_speed * 1.35
		child.wander_speed = wander_speed * 1.2
		child.drops_gears_on_death = drops_gears_on_death and split_generations <= 1
		child.scale = scale * child_scale
		parent.add_child(child)
		var ang = TAU * i / split_count + randf_range(-0.4, 0.4)
		var dir = Vector3(cos(ang), 0, sin(ang))
		child.global_position = global_position + dir * 0.6 + Vector3(0, 0.3, 0)
		child.spawn_position = child.global_position
		# Scatter hop
		child.velocity = dir * 5.0 + Vector3(0, 6.0, 0)
		# Brief spawn immunity so one swing can't clear the whole split
		child.damage_cooldown = 0.5
