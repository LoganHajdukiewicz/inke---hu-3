@tool
extends StaticBody3D
class_name ClimbableWall

## A wall the player can free-climb (up / down / left / right).
## Just being in the "ClimbableWall" group is what makes it climbable -
## this script only handles sizing and the visual.
## Default look: CHAIN-LINK FENCE (galvanized posts + rails + a woven
## diamond-mesh panel). @tool: builds in the editor so you can see and
## place it like any other prop. Resize via wall_size.

@export var wall_size: Vector3 = Vector3(8, 6, 0.5):
	set(value):
		wall_size = value
		if is_inside_tree():
			_rebuild()

@export_group("Fence Look")
@export var frame_color: Color = Color(0.62, 0.65, 0.68)   # Galvanized steel
@export var mesh_color: Color = Color(0.7, 0.73, 0.76)     # Chain-link wire
## Size of one diamond in the mesh, in world units.
@export var diamond_size: float = 0.35:
	set(value):
		diamond_size = maxf(value, 0.1)
		if is_inside_tree():
			_rebuild()

# One shared chain-link texture for every fence in the scene
static var _chainlink_tex: ImageTexture = null

func _ready():
	add_to_group("ClimbableWall")
	_rebuild()

func _rebuild():
	for child in get_children():
		child.queue_free()
	
	# Collision - full slab so climbing raycasts and wall jumps all connect
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = wall_size
	collision.shape = box
	add_child(collision)
	
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = frame_color
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.45
	
	# --- Chain-link mesh panel (both faces of a quad, alpha-scissor) ------
	var panel = MeshInstance3D.new()
	var quad = QuadMesh.new()
	quad.size = Vector2(wall_size.x, wall_size.y)
	panel.mesh = quad
	
	var mesh_mat = StandardMaterial3D.new()
	mesh_mat.albedo_color = mesh_color
	mesh_mat.albedo_texture = _get_chainlink_texture()
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mesh_mat.alpha_scissor_threshold = 0.5
	mesh_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # Visible from both sides
	mesh_mat.metallic = 0.5
	mesh_mat.roughness = 0.5
	# Tile the diamond pattern to match the requested diamond size
	mesh_mat.uv1_scale = Vector3(wall_size.x / diamond_size, wall_size.y / diamond_size, 1.0)
	panel.material_override = mesh_mat
	add_child(panel)
	
	# --- Frame: posts at the sides, rails top & bottom --------------------
	var post_radius = 0.07
	for x_side in [1.0, -1.0]:
		var post = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = post_radius
		cyl.bottom_radius = post_radius
		cyl.height = wall_size.y
		post.mesh = cyl
		post.material_override = frame_mat
		post.position = Vector3(x_side * (wall_size.x * 0.5 - post_radius), 0, 0)
		add_child(post)
	
	for y_side in [1.0, -1.0]:
		var rail = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = post_radius * 0.75
		cyl.bottom_radius = post_radius * 0.75
		cyl.height = wall_size.x - post_radius * 2.0
		rail.mesh = cyl
		rail.material_override = frame_mat
		rail.rotation.z = PI * 0.5
		rail.position = Vector3(0, y_side * (wall_size.y * 0.5 - post_radius), 0)
		add_child(rail)

static func _get_chainlink_texture() -> ImageTexture:
	"""One tileable diamond-weave cell, drawn once and shared by all fences."""
	if _chainlink_tex:
		return _chainlink_tex
	
	var size := 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	
	# A chain-link cell is an X: two diagonals crossing corner to corner.
	# Tiled, that reads as the classic diamond weave.
	var wire := 4.0   # Wire thickness in pixels
	for y in range(size):
		for x in range(size):
			# Distance to the two diagonals of the tile (wrapped)
			var fx := float(x)
			var fy := float(y)
			var d1 = absf(fposmod(fx - fy, float(size)))             # "\" diagonal
			d1 = minf(d1, size - d1)
			var d2 = absf(fposmod(fx + fy, float(size)))             # "/" diagonal
			d2 = minf(d2, size - d2)
			if d1 < wire or d2 < wire:
				# Slight shading so the wire looks round
				var d = minf(d1, d2)
				var shade = 1.0 - (d / wire) * 0.35
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	
	_chainlink_tex = ImageTexture.create_from_image(img)
	return _chainlink_tex
