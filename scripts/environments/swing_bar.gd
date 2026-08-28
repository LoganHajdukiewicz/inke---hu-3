@tool
extends Node3D
class_name SwingBar

## A horizontal swing bar, Jak & Daxter style. Fly into it in the air and
## you grab on and start swinging automatically; jump releases along the
## arc. The bar runs along this node's local X axis.
##
## Looks: DEFAULT is a plain metal bar on two posts. Tick `tree_disguise`
## and it becomes a horizontal branch sticking out of a tree trunk.

@export var bar_length: float = 3.0:
	set(value):
		bar_length = maxf(value, 0.5)
		if is_inside_tree():
			_rebuild()

@export var bar_radius: float = 0.08
@export var bar_color: Color = Color(0.75, 0.7, 0.35)   # Brass-ish
## Posts holding the bar up (ignored when tree_disguise is on).
@export var show_posts: bool = true:
	set(value):
		show_posts = value
		if is_inside_tree():
			_rebuild()
@export var post_height: float = 4.0:
	set(value):
		post_height = maxf(value, 0.5)
		if is_inside_tree():
			_rebuild()

@export_group("Tree Disguise")
## Render as a branch coming off a tree trunk instead of a bar on posts.
@export var tree_disguise: bool = false:
	set(value):
		tree_disguise = value
		if is_inside_tree():
			_rebuild()
@export var trunk_color: Color = Color(0.38, 0.26, 0.16)
@export var leaf_color: Color = Color(0.25, 0.5, 0.22)

var _grab_area: Area3D

func _ready():
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	if tree_disguise:
		_build_tree_visual()
	else:
		_build_bar_visual()
	
	# Grab zone around the bar (game only - no point in the editor)
	if Engine.is_editor_hint():
		return
	
	_grab_area = Area3D.new()
	_grab_area.collision_layer = 0
	_grab_area.collision_mask = 1
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(bar_length, 1.4, 1.4)
	col.shape = shape
	_grab_area.add_child(col)
	add_child(_grab_area)
	_grab_area.body_entered.connect(_on_body_entered)

func _build_bar_visual():
	var bar_mat = StandardMaterial3D.new()
	bar_mat.albedo_color = bar_color
	bar_mat.metallic = 0.7
	bar_mat.roughness = 0.35
	
	var bar_mesh_i = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = bar_radius
	cyl.bottom_radius = bar_radius
	cyl.height = bar_length
	bar_mesh_i.mesh = cyl
	bar_mesh_i.material_override = bar_mat
	bar_mesh_i.rotation.z = PI * 0.5   # Lay along local X
	add_child(bar_mesh_i)
	
	if not show_posts:
		return
	
	var post_mat = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.45, 0.45, 0.5)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.5
	
	for x_side in [1.0, -1.0]:
		var post = MeshInstance3D.new()
		var pcyl = CylinderMesh.new()
		pcyl.top_radius = bar_radius * 1.4
		pcyl.bottom_radius = bar_radius * 1.8
		pcyl.height = post_height
		post.mesh = pcyl
		post.material_override = post_mat
		post.position = Vector3(x_side * bar_length * 0.5, -post_height * 0.5, 0)
		add_child(post)

func _build_tree_visual():
	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = trunk_color
	trunk_mat.roughness = 0.95
	
	# Trunk at one end of the branch
	var trunk = MeshInstance3D.new()
	var tcyl = CylinderMesh.new()
	tcyl.top_radius = 0.35
	tcyl.bottom_radius = 0.5
	tcyl.height = post_height + 2.0
	trunk.mesh = tcyl
	trunk.material_override = trunk_mat
	trunk.position = Vector3(-bar_length * 0.5 - 0.4, -(post_height + 2.0) * 0.5 + 1.0, 0)
	add_child(trunk)
	
	# The branch IS the swing bar
	var branch = MeshInstance3D.new()
	var bcyl = CylinderMesh.new()
	bcyl.top_radius = bar_radius * 1.1
	bcyl.bottom_radius = bar_radius * 1.6
	bcyl.height = bar_length + 0.8
	branch.mesh = bcyl
	branch.material_override = trunk_mat
	branch.rotation.z = PI * 0.5
	branch.position.x = -0.4
	add_child(branch)
	
	# Leaf blob on top of the trunk
	var leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_color = leaf_color
	leaf_mat.roughness = 0.9
	
	var leaves = MeshInstance3D.new()
	var sph = SphereMesh.new()
	sph.radius = 1.6
	sph.height = 2.6
	leaves.mesh = sph
	leaves.material_override = leaf_mat
	leaves.position = Vector3(-bar_length * 0.5 - 0.4, 1.8, 0)
	add_child(leaves)

func get_bar_axis() -> Vector3:
	"""The bar's long axis in world space."""
	return global_transform.basis.x.normalized()

func get_grab_point(near_position: Vector3) -> Vector3:
	"""Closest point on the bar's axis to the player - you swing from where
	you grabbed, not always the center."""
	var axis = get_bar_axis()
	var along = clampf((near_position - global_position).dot(axis), -bar_length * 0.45, bar_length * 0.45)
	return global_position + axis * along

func notify_released(body: Node3D, lockout: float):
	body.set_meta("swingbar_regrab_until", Time.get_ticks_msec() + int(lockout * 1000))

func _on_body_entered(body: Node3D):
	if not body.is_in_group("Player"):
		return
	if body.get("is_dead") == true or body.get("controls_disabled") == true:
		return
	# Regrab lockout after a release
	if body.has_meta("swingbar_regrab_until") and Time.get_ticks_msec() < body.get_meta("swingbar_regrab_until"):
		return
	# Airborne only
	if body.is_on_floor():
		return
	
	var sm = body.get_node_or_null("StateMachine")
	if not sm:
		return
	var state_name = sm.current_state.get_script().get_global_name() if sm.current_state else ""
	if not state_name in ["JumpingState", "FallingState", "DoubleJumpState", "WallJumpingState", "GrappleHookState", "DodgeDashState"]:
		return
	
	var bar_state = sm.states.get("swingbarstate")
	if bar_state:
		bar_state.setup(self)
		sm.change_state("SwingBarState")
