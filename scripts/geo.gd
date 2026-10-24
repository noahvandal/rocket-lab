class_name Geo
extends RefCounted
## Procedural mesh and material helpers.

## Surface of revolution around Y. Profile points are (radius, y), ordered bottom to top.
static func lathe(profile: PackedVector2Array, segments: int = 32) -> ArrayMesh:
	var n := profile.size()
	var pn := PackedVector2Array()
	pn.resize(n)
	for i in n:
		var t := Vector2.ZERO
		if i > 0:
			t += (profile[i] - profile[i - 1]).normalized()
		if i < n - 1:
			t += (profile[i + 1] - profile[i]).normalized()
		pn[i] = Vector2(t.y, -t.x).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in n:
		for s in segments + 1:
			var a := TAU * float(s) / segments
			var c := cos(a)
			var sn := sin(a)
			verts.append(Vector3(c * profile[i].x, profile[i].y, sn * profile[i].x))
			norms.append(Vector3(c * pn[i].x, pn[i].y, sn * pn[i].x).normalized())
			uvs.append(Vector2(float(s) / segments, float(i) / (n - 1)))
	var row := segments + 1
	for i in n - 1:
		for s in segments:
			var a0 := i * row + s
			var b0 := a0 + row
			idx.append(a0)
			idx.append(a0 + 1)
			idx.append(b0)
			idx.append(b0)
			idx.append(a0 + 1)
			idx.append(b0 + 1)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Flat extruded convex polygon in the XY plane (used for fins).
static func prism(points: PackedVector2Array, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := thick * 0.5
	var n := points.size()
	for i in range(1, n - 1):
		_tri(st, _v(points[0], h), _v(points[i], h), _v(points[i + 1], h))
		_tri(st, _v(points[0], -h), _v(points[i + 1], -h), _v(points[i], -h))
	for i in n:
		var p := points[i]
		var q := points[(i + 1) % n]
		_tri(st, _v(p, h), _v(p, -h), _v(q, h))
		_tri(st, _v(q, h), _v(p, -h), _v(q, -h))
	st.generate_normals()
	return st.commit()

static func _v(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func mat(color: Color, metallic := 0.0, roughness := 0.6, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func glow_mat(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	return m

static func mesh_node(mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	return mi

static func cylinder(r_top: float, r_bottom: float, h: float, segs := 32) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

## Soft round sprite used for smoke and fire particles.
static func soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

static func particle_mat(additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.disable_receive_shadows = true
	return m

static func ramp(stops: Array) -> Gradient:
	# stops: [[offset, Color], ...]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([stops[0][0], stops[stops.size() - 1][0]])
	g.colors = PackedColorArray([stops[0][1], stops[stops.size() - 1][1]])
	for i in range(1, stops.size() - 1):
		g.add_point(stops[i][0], stops[i][1])
	return g

static func curve(a: float, b: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0, a))
	c.add_point(Vector2(1, b))
	return c
