@tool
extends StaticBody3D
class_name GroundPoundMound

## A bumpy patch of ground that pops open when GROUND SLAMMED on top of it.
## The ground visibly warps upward in a small bump (something's buried!).
## Attach ANY collectable scene in the Inspector and set how many to spawn.
## Default: 5 gears.

@export_group("Loot")
@export var collectable_scene: PackedScene = preload("res://scenes/items/Collectibles/six_teeth_gear.tscn")
@export var collectable_count: int = 5
@export var scatter_radius: float = 3.2      # How far the loot explodes outward
@export var scatter_duration: float = 0.7
@export var pickup_lock_time: float = 1.0    # Loot can't be collected while flying out
## How long HU3 keeps IGNORING the popped loot (on top of the scatter
## time), so the buddy robot doesn't vacuum it up before you even see it.
@export var hu3_ignore_time: float = 0.75
@export var one_shot: bool = true            # Can it only be slammed open once?

@export_group("Appearance")
@export var patch_radius: float = 1.6        # Footprint of the patch
@export var bump_height: float = 0.3         # How tall the warped bump is (low = walkable)
@export var patch_color: Color = Color(0.5, 0.42, 0.3)   # Disturbed-dirt tint
@export var crack_color: Color = Color(0.32, 0.26, 0.18)

var used: bool = false
var bump_mesh: MeshInstance3D = null

func _ready():
	if not Engine.is_editor_hint():
		add_to_group("GroundPoundMound")
	_build_visual()

func _build_visual():
	# The warped bump: a LOW squashed dome rising gently out of the ground.
	# Kept flat enough that it reads as a patch of ground, not an obstacle.
	bump_mesh = MeshInstance3D.new()
	bump_mesh.name = "Bump"
	var sphere = SphereMesh.new()
	sphere.radius = patch_radius
	sphere.height = bump_height * 2.0    # Squashed dome
	sphere.is_hemisphere = true
	sphere.radial_segments = 24
	sphere.rings = 8
	bump_mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = patch_color
	mat.roughness = 1.0
	bump_mesh.material_override = mat
	add_child(bump_mesh)
	
	# Collision: convex hull of the SAME dome, so the player smoothly walks
	# up and over it like a patch of ground (no waist-high cylinder wall).
	var collision = CollisionShape3D.new()
	var hull = ConvexPolygonShape3D.new()
	hull.points = sphere.get_faces()
	collision.shape = hull
	add_child(collision)
	
	# Cracks radiating over the bump so it reads as "breakable"
	var crack_mat = StandardMaterial3D.new()
	crack_mat.albedo_color = crack_color
	crack_mat.roughness = 1.0
	for i in range(4):
		var crack = MeshInstance3D.new()
		var crack_mesh = BoxMesh.new()
		crack_mesh.size = Vector3(patch_radius * 1.4, 0.02, 0.07)
		crack.mesh = crack_mesh
		crack.material_override = crack_mat
		crack.position.y = bump_height * 0.7
		crack.rotation.y = (PI / 4.0) * i + randf_range(-0.15, 0.15)
		crack.rotation.z = randf_range(-0.06, 0.06)
		add_child(crack)
	
	# Gentle "breathing" pulse so the bump catches the eye (visual only -
	# the collision hull stays put so it never pushes the player around)
	if not Engine.is_editor_hint():
		var tween = create_tween()
		tween.set_loops()
		tween.tween_property(bump_mesh, "scale", Vector3(1.0, 1.08, 1.0), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(bump_mesh, "scale", Vector3.ONE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func on_ground_slammed(slammer: Node3D):
	"""Called by GroundSlamState when the player slams on/near this patch."""
	if used and one_shot:
		return
	used = true
	_burst_open(slammer)

func _burst_open(_slammer: Node3D):
	# Flatten the bump - the ground "deflates"
	if bump_mesh:
		var tween = create_tween()
		tween.tween_property(bump_mesh, "scale", Vector3(1.3, 0.08, 1.3), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Dirt burst
	_spawn_dirt_burst()
	
	# EXPLODE out the loot - big visible arcs, and the items can't be
	# vacuumed up until they've actually landed (pickup lock), so the
	# player SEES what they earned.
	if collectable_scene:
		var container = get_parent()
		for i in range(collectable_count):
			var item = collectable_scene.instantiate()
			container.add_child(item)
			var spawn_pos = global_position + Vector3(0, bump_height + 0.4, 0)
			item.global_position = spawn_pos
			
			# Lock pickup while the loot is airborne (supported by gears &
			# other collectables via lock_pickup; harmless otherwise)
			if item.has_method("lock_pickup"):
				item.lock_pickup(scatter_duration + pickup_lock_time)
			if item.has_method("lock_hu3_pickup"):
				item.lock_hu3_pickup(scatter_duration + hu3_ignore_time)
			
			var angle = (TAU / max(collectable_count, 1)) * i + randf_range(-0.3, 0.3)
			var radius = randf_range(scatter_radius * 0.6, scatter_radius)
			var target = spawn_pos + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			
			if item.has_method("scatter_arc"):
				item.scatter_arc(target, scatter_duration, randf_range(1.6, 2.6))
			elif item.has_method("scatter_to"):
				item.scatter_to(target, scatter_duration)
			else:
				var tween = item.create_tween()
				tween.set_trans(Tween.TRANS_QUAD)
				tween.set_ease(Tween.EASE_OUT)
				tween.tween_property(item, "global_position", target, scatter_duration)
	
	if one_shot:
		# The patch is spent: deflate, fade, and REMOVE it entirely so the
		# ground is flat again.
		# Collision goes away immediately so nothing stands on a ghost bump
		for child in get_children():
			if child is CollisionShape3D:
				child.queue_free()
		# The deflate tween (above) plays out, then the whole patch vanishes
		var fade = create_tween()
		fade.tween_interval(0.6)
		fade.tween_callback(queue_free)

func _spawn_dirt_burst():
	"""Chunks of dirt flying out when the patch pops."""
	var parent = get_parent()
	if not parent:
		return
	for i in range(10):
		var chunk = MeshInstance3D.new()
		var box = BoxMesh.new()
		var s = randf_range(0.08, 0.2)
		box.size = Vector3(s, s, s)
		chunk.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = crack_color
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		chunk.material_override = mat
		parent.add_child(chunk)
		chunk.global_position = global_position + Vector3(0, bump_height * 0.6, 0)
		
		var angle = randf() * TAU
		var target = chunk.global_position + Vector3(cos(angle) * randf_range(0.5, 1.8), randf_range(0.5, 1.5), sin(angle) * randf_range(0.5, 1.8))
		
		var tween = chunk.create_tween()
		tween.set_parallel(true)
		tween.tween_property(chunk, "global_position", target, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(chunk, "rotation", Vector3(randf() * TAU, randf() * TAU, randf() * TAU), 0.45)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(0.15)
		tween.chain().tween_callback(chunk.queue_free)
