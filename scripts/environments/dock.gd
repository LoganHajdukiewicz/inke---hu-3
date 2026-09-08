@tool
extends StaticBody3D
class_name Dock
## A wooden dock running out over the water. Plank deck on pilings, with
## collision - walk out, fish, or park a Boat at the end. Point it with
## the node's rotation; the deck extends along -Z (forward).

@export var length: float = 14.0:
	set(v): length = maxf(v, 2.0); _request_rebuild()
@export var width: float = 4.0:
	set(v): width = maxf(v, 1.0); _request_rebuild()
## Deck height above this node's origin (origin usually at water level).
@export var deck_height: float = 0.8:
	set(v): deck_height = v; _request_rebuild()
## How far the pilings reach down below the origin (into the water/bed).
@export var piling_depth: float = 4.0:
	set(v): piling_depth = maxf(v, 0.5); _request_rebuild()
@export var wood_color: Color = Color(0.45, 0.32, 0.2):
	set(v): wood_color = v; _request_rebuild()
@export var piling_color: Color = Color(0.35, 0.25, 0.16):
	set(v): piling_color = v; _request_rebuild()

var _built: Node3D = null
var _col: CollisionShape3D = null
var _rebuild_queued := false


func _ready():
	add_to_group("LedgeGrabbable")
	_request_rebuild()


func _request_rebuild():
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild():
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _built and is_instance_valid(_built):
		_built.free()
	_built = Node3D.new()
	add_child(_built)
	
	var wood := StandardMaterial3D.new()
	wood.albedo_color = wood_color
	wood.roughness = 0.9
	var dark := StandardMaterial3D.new()
	dark.albedo_color = piling_color
	dark.roughness = 0.95
	
	# --- Planked deck (visual planks with tiny gaps) -----------------------
	var plank_w := 0.55
	var gap := 0.06
	var n_planks := int(length / (plank_w + gap))
	for i in range(n_planks):
		var plank := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, 0.12, plank_w)
		plank.mesh = bm
		plank.material_override = wood if (i % 7 != 3) else dark   # Odd dark plank
		plank.position = Vector3(0, deck_height, -(i + 0.5) * (plank_w + gap))
		plank.rotation.y = randf_range(-0.008, 0.008)   # Slightly crooked = handmade
		_built.add_child(plank)
	
	# --- Pilings every ~3m, both sides -------------------------------------
	var n_pilings := maxi(int(length / 3.0), 2)
	for i in range(n_pilings + 1):
		var z := -minf(float(i) / n_pilings * length, length - 0.4) - 0.3
		for side in [-1.0, 1.0]:
			var pil := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.14
			cm.bottom_radius = 0.16
			cm.height = deck_height + piling_depth + 0.35
			cm.radial_segments = 7
			pil.mesh = cm
			pil.material_override = dark
			pil.position = Vector3(side * (width * 0.5 - 0.15), (deck_height + 0.35 - piling_depth) * 0.5, z)
			_built.add_child(pil)
	
	# --- One walk collision slab (cheap) ------------------------------------
	if _col == null or not is_instance_valid(_col):
		_col = CollisionShape3D.new()
		add_child(_col)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.14, length)
	_col.shape = shape
	_col.position = Vector3(0, deck_height, -length * 0.5)
