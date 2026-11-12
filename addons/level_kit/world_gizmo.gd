@tool
extends EditorNode3DGizmoPlugin
## DRAG HANDLES FOR EVERYTHING.
## Select a Room, Hallway, Floor, Terrain, Water, Fence, Ladder, Beam, Rope,
## Swing bar, Heal patch, Dialogue trigger, Location flag, Flatten pad,
## Terrain path, Cred gate... and orange dots appear on its edges. Drag a
## dot to resize that side. Values snap to the Level Kit grid. Every drag
## is one Ctrl+Z.
##
## SPECS: one entry per node type. Each handle = {prop, axis, kind, ...}
##   kind "half"  - prop component is a full size, handle sits at +size/2
##   kind "full"  - handle sits at +size (origin is on that edge)
##   kind "neg"   - handle sits at -size (hangs DOWN / extends backward)
##   axis 0/1/2 = x/y/z of a Vector3 prop. For Vector2 props: 0 = x, 2 = y.
##   For float props axis says which direction the handle points.
##   "offset" shifts where the axis starts (e.g. pivot not centered).

var plugin: EditorPlugin

const SPECS := {
	"Room": [
		{"prop": "interior_size", "axis": 0, "kind": "half", "y": 0.5},
		{"prop": "interior_size", "axis": 2, "kind": "half", "y": 0.5},
		{"prop": "interior_size", "axis": 1, "kind": "full"},
	],
	"Hallway": [
		{"prop": "width", "axis": 0, "kind": "half", "y": 0.5},
		{"prop": "height", "axis": 1, "kind": "full"},
	],
	"Floor": [
		{"prop": "floor_size", "axis": 0, "kind": "half"},
		{"prop": "floor_size", "axis": 2, "kind": "half"},
		{"prop": "floor_size", "axis": 1, "kind": "neg"},
		{"prop": "cylinder_radius", "axis": 0, "kind": "full", "when": "floor_shape", "is": 1},
	],
	"Terrain": [
		{"prop": "size", "axis": 0, "kind": "half"},
		{"prop": "size", "axis": 2, "kind": "half"},
		{"prop": "hill_height", "axis": 1, "kind": "full", "min": 0.0},
		{"prop": "brush_radius", "axis": 0, "kind": "full", "at": "brush", "min": 1.0},
	],
	"WaterZone": [
		{"prop": "water_size", "axis": 0, "kind": "half"},
		{"prop": "water_size", "axis": 2, "kind": "half"},
		{"prop": "water_depth", "axis": 1, "kind": "neg", "min": 1.0},
	],
	"ClimbableWall": [
		{"prop": "wall_size", "axis": 0, "kind": "half"},
		{"prop": "wall_size", "axis": 1, "kind": "half"},
	],
	"Ladder": [
		{"prop": "wall_size", "axis": 0, "kind": "half"},
		{"prop": "wall_size", "axis": 1, "kind": "half"},
	],
	"BalanceBeam": [
		{"prop": "beam_length", "axis": 2, "kind": "half", "min": 1.0},
	],
	"SwingRope": [
		{"prop": "rope_length", "axis": 1, "kind": "neg", "min": 1.0},
	],
	"SwingBar": [
		{"prop": "bar_length", "axis": 0, "kind": "half", "min": 0.5},
		{"prop": "post_height", "axis": 1, "kind": "neg", "min": 0.5},
	],
	"HealPatch": [
		{"prop": "patch_size", "axis": 0, "kind": "half"},
		{"prop": "patch_size", "axis": 2, "kind": "half"},
	],
	"DialogueTrigger": [
		{"prop": "box_size", "axis": 0, "kind": "half"},
		{"prop": "box_size", "axis": 1, "kind": "half"},
		{"prop": "box_size", "axis": 2, "kind": "half"},
	],
	"LocationFlag": [
		{"prop": "size", "axis": 0, "kind": "half"},
		{"prop": "size", "axis": 1, "kind": "half"},
		{"prop": "size", "axis": 2, "kind": "half"},
	],
	"FlattenPad": [
		{"prop": "radius", "axis": 0, "kind": "full", "min": 0.5},
		{"prop": "blend", "axis": 2, "kind": "full", "from": "radius", "min": 0.0},
	],
	"TerrainPath": [
		{"prop": "width", "axis": 0, "kind": "half", "at": "start", "min": 0.5},
	],
	"GroundPoundMound": [
		{"prop": "patch_radius", "axis": 0, "kind": "full", "min": 0.3},
	],
	"CredGate": [
		{"prop": "size", "axis": 0, "kind": "half"},
		{"prop": "size", "axis": 1, "kind": "half"},
	],
	"DialogueCameraBounds": [
		{"prop": "size", "axis": 0, "kind": "half"},
		{"prop": "size", "axis": 1, "kind": "half"},
		{"prop": "size", "axis": 2, "kind": "half"},
	],
	"CurvedFloor": [
		{"prop": "width", "axis": 0, "kind": "half", "min": 0.5},
	],
}

const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


func _init() -> void:
	create_material("box", Color(1, 0.6, 0.15, 0.7), false, true)
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "LevelKit World Handles"


func _get_priority() -> int:
	return -1


static func type_of(node: Node) -> String:
	var s: Script = node.get_script()
	while s:
		var g := s.get_global_name()
		if SPECS.has(g):
			return g
		s = s.get_base_script()
	return ""


func _has_gizmo(node: Node3D) -> bool:
	return type_of(node) != ""


func _specs(node: Node) -> Array:
	var out := []
	for sp in SPECS.get(type_of(node), []):
		if sp.has("when") and node.get(sp.when) != sp.is:
			continue
		# Cylinder floors: radius handle replaces the X/Z box handles
		if type_of(node) == "Floor" and sp.prop == "floor_size" and sp.axis != 1 and int(node.get("floor_shape")) == 1:
			continue
		out.append(sp)
	return out


func _component(node: Node, sp: Dictionary) -> float:
	var v = node.get(sp.prop)
	if v is Vector3:
		return v[sp.axis]
	if v is Vector2:
		return v.x if sp.axis == 0 else v.y
	return float(v)


func _set_component(node: Node, sp: Dictionary, value: float) -> void:
	var v = node.get(sp.prop)
	if v is Vector3:
		v[sp.axis] = value
	elif v is Vector2:
		if sp.axis == 0: v.x = value
		else: v.y = value
	else:
		v = value
	node.set(sp.prop, v)


func _handle_pos(node: Node3D, sp: Dictionary) -> Vector3:
	var c := _component(node, sp)
	var dir: Vector3 = AXES[sp.axis]
	var dist: float
	match sp.kind:
		"half": dist = c * 0.5
		"neg": dist = c; dir = -dir
		_: dist = c
	var base := Vector3.ZERO
	if sp.has("y"):
		var v = node.get(sp.prop)
		var h: float = v.y if v is Vector3 else float(node.get("height")) if "height" in node else 0.0
		base.y = h * sp.y
	if sp.has("from"):
		base += AXES[sp.axis] * float(node.get(sp.from))
	if sp.get("at", "") == "start" and node is Path3D and (node as Path3D).curve and (node as Path3D).curve.point_count > 0:
		base += (node as Path3D).curve.get_point_position(0)
	if sp.get("at", "") == "brush":
		base.y = float(node.get("hill_height")) + 2.0
	return base + dir * dist


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var specs := _specs(node)
	var pts := PackedVector3Array()
	var ids := PackedInt32Array()
	var lines := PackedVector3Array()
	for i in range(specs.size()):
		var p := _handle_pos(node, specs[i])
		pts.append(p)
		ids.append(i)
		# a short guide line from the axis start to the handle
		var start: Vector3 = p - AXES[specs[i].axis] * (0.6 if specs[i].kind != "neg" else -0.6)
		lines.append(start); lines.append(p)
	if not lines.is_empty():
		gizmo.add_lines(lines, get_material("box", gizmo), false)
	if not pts.is_empty():
		gizmo.add_handles(pts, get_material("handles", gizmo), ids)


func _get_handle_name(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	var sp: Dictionary = _specs(gizmo.get_node_3d())[id]
	var nm := str(sp.prop).capitalize()
	var v = gizmo.get_node_3d().get(sp.prop)
	if v is Vector3 or v is Vector2:
		nm += " " + ["X", "Y", "Z"][sp.axis]
	return nm


func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	var sp: Dictionary = _specs(gizmo.get_node_3d())[id]
	return gizmo.get_node_3d().get(sp.prop)


func _set_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var sp: Dictionary = _specs(node)[id]
	var gt := node.global_transform
	var dir_local: Vector3 = AXES[sp.axis] * (-1.0 if sp.kind == "neg" else 1.0)
	var axis := (gt.basis * dir_local).normalized()
	# origin of the axis = handle position minus current offset along it
	var hp := _handle_pos(node, sp)
	var c := _component(node, sp)
	var along := c * 0.5 if sp.kind == "half" else c
	var origin := gt * (hp - dir_local * along)
	var t := _closest_on_axis(origin, axis, camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	# undo node scaling so handles track the cursor on scaled nodes
	var sc := (gt.basis * dir_local).length()
	t /= maxf(sc, 0.0001)
	var value := t * 2.0 if sp.kind == "half" else t
	var snap: float = plugin.grid_snap if plugin else 0.5
	if snap > 0.0:
		value = snappedf(value, snap * (0.5 if value < 4.0 else 1.0))
	value = maxf(value, sp.get("min", 0.1))
	_set_component(node, sp, value)
	node.update_gizmos()


func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	var sp: Dictionary = _specs(node)[id]
	if cancel:
		node.set(sp.prop, restore)
		return
	var ur := plugin.get_undo_redo()
	ur.create_action("Resize " + str(sp.prop))
	ur.add_do_property(node, sp.prop, node.get(sp.prop))
	ur.add_undo_property(node, sp.prop, restore)
	ur.add_do_method(node, "update_gizmos")
	ur.add_undo_method(node, "update_gizmos")
	ur.commit_action(false)


static func _closest_on_axis(origin: Vector3, axis: Vector3, ray_from: Vector3, ray_dir: Vector3) -> float:
	var w0 := origin - ray_from
	var b := axis.dot(ray_dir)
	var c := ray_dir.dot(ray_dir)
	var d := axis.dot(w0)
	var e := ray_dir.dot(w0)
	var denom := axis.dot(axis) * c - b * b
	if absf(denom) < 0.0001:
		return 0.0
	return (b * e - c * d) / denom
