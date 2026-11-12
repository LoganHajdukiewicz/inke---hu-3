extends RefCounted
class_name MeshMerge
## PERFORMANCE helper: collapse a little hand-built model (a Node3D full of
## MeshInstance3Ds made from Godot primitives) into ONE MeshInstance3D.
##   - every part's triangles are baked into one ArrayMesh, in the model's
##     local space, with each part's albedo color stored as a VERTEX COLOR
##   - primitive meshes are rebuilt at LOW tessellation first (a 2cm rivet
##     doesn't need a 64x32 sphere; Godot's CylinderMesh default is 64 sides)
##   - result: 1 node + 1 draw call per prop instead of 10-20, and ~5-20x
##     fewer triangles
## Parts using special materials (emission, transparency, shaders) are KEPT
## as separate nodes so glowing/animated bits still work.

const LOW_RADIAL := 10
const LOW_RINGS := 6


static func merge(model: Node3D, keep_special := true) -> MeshInstance3D:
	if model == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	var roughness := 0.8
	var metallic := 0.0
	var count := 0
	var to_free := []
	var inv := model.global_transform.affine_inverse() if model.is_inside_tree() else Transform3D.IDENTITY
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var mat: Material = m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh.get_surface_count() > 0 else null)
		var col := Color.WHITE
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if keep_special and (sm.emission_enabled or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.albedo_texture != null):
				continue
			col = sm.albedo_color
			roughness = sm.roughness
			metallic = maxf(metallic, sm.metallic * 0.5)
		elif mat != null and keep_special:
			continue   # ShaderMaterial etc. - leave it alone
		var xf: Transform3D
		if model.is_inside_tree() and m.is_inside_tree():
			xf = inv * m.global_transform
		else:
			xf = _local_xf(model, m)
		var mesh := _low_poly(m.mesh)
		for si in range(mesh.get_surface_count()):
			var arr := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			var nb := xf.basis.inverse().transposed()
			var emit := func(i: int):
				st.set_color(col)
				if norms is PackedVector3Array and norms.size() > i:
					st.set_normal((nb * norms[i]).normalized())
				st.add_vertex(xf * verts[i])
			if idx is PackedInt32Array and idx.size() > 0:
				for i in idx: emit.call(i)
			else:
				for i in range(verts.size()): emit.call(i)
			any = true
		to_free.append(m)
		count += 1
	if not any:
		return null
	var out := MeshInstance3D.new()
	out.name = "MergedModel"
	out.mesh = st.commit()
	var mat2 := StandardMaterial3D.new()
	mat2.vertex_color_use_as_albedo = true
	mat2.roughness = roughness
	mat2.metallic = metallic
	out.material_override = mat2
	for m in to_free:
		m.get_parent().remove_child(m)
		m.queue_free()
	model.add_child(out)
	return out


static func _local_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func lower_tessellation(root: Node) -> void:
	"""In-place: every primitive mesh under root (Sphere/Cylinder/Capsule/
	Torus) gets a sane segment count. Keeps nodes + materials intact, so
	flashing/animated props still work. Godot's defaults are 64 radial
	segments x 32 rings (~4000 tris per tiny sphere)."""
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh is PrimitiveMesh:
			m.mesh = _low_poly(m.mesh)


static func _low_poly(m: Mesh) -> Mesh:
	"""Copy primitive meshes at a sane tessellation."""
	if m is SphereMesh:
		var s := (m as SphereMesh).duplicate() as SphereMesh
		s.radial_segments = mini(s.radial_segments, LOW_RADIAL)
		s.rings = mini(s.rings, LOW_RINGS)
		return s
	if m is CylinderMesh:
		var c := (m as CylinderMesh).duplicate() as CylinderMesh
		c.radial_segments = mini(c.radial_segments, LOW_RADIAL)
		c.rings = 0
		return c
	if m is CapsuleMesh:
		var cp := (m as CapsuleMesh).duplicate() as CapsuleMesh
		cp.radial_segments = mini(cp.radial_segments, LOW_RADIAL)
		cp.rings = mini(cp.rings, 4)
		return cp
	if m is TorusMesh:
		var t := (m as TorusMesh).duplicate() as TorusMesh
		t.rings = mini(t.rings, 16)
		t.ring_segments = mini(t.ring_segments, 8)
		return t
	return m
