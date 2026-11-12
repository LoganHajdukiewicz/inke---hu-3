@tool
extends Node3D
class_name DialogueCameraBounds
## Box the dialogue camera may never leave. Drop one around an alley, a
## room or a stage, scale `size` to fit, and every dynamic-camera shot of a
## conversation inside it stays inside the box (shots that would leave are
## clamped or replaced). Rotate the node to align with the space.
## Visible as an orange wireframe in the editor only.

@export var size: Vector3 = Vector3(12, 6, 12):
	set(v): size = v.abs(); _update_preview()

var _preview: MeshInstance3D


func _ready() -> void:
	add_to_group("DialogueCameraBounds")
	_update_preview()


func contains(p: Vector3) -> bool:
	var l := to_local(p)
	var h := size * 0.5
	return absf(l.x) <= h.x + 0.01 and absf(l.y) <= h.y + 0.01 and absf(l.z) <= h.z + 0.01


func clamp_point(p: Vector3) -> Vector3:
	var l := to_local(p)
	var h := size * 0.5 - Vector3(0.2, 0.2, 0.2)
	l = Vector3(clampf(l.x, -h.x, h.x), clampf(l.y, -h.y, h.y), clampf(l.z, -h.z, h.z))
	return to_global(l)


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		add_child(_preview)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1, 0.55, 0.1)
		_preview.material_override = m
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var h := size * 0.5
	var c := []
	for i in range(8):
		c.append(Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1)))
	for e in [[0,1],[2,3],[4,5],[6,7],[0,2],[1,3],[4,6],[5,7],[0,4],[1,5],[2,6],[3,7]]:
		im.surface_add_vertex(c[e[0]]); im.surface_add_vertex(c[e[1]])
	im.surface_end()
	_preview.mesh = im
