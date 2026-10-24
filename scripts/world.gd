class_name World
extends Node3D
## Island terrain, ocean, sky, lighting and the launch site.

const PAD_TOP := 4.2
const PAD_RADIUS := 14.0
const LAND_BASE := 3.0
const SIZE := 24000.0
const GRID := 160

const SKY_SHADER := """
shader_type sky;
uniform float space = 0.0;
uniform vec3 sun_dir = vec3(0.4, 0.6, 0.6);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 zen = mix(vec3(0.09, 0.30, 0.70), vec3(0.0, 0.0, 0.004), space);
	vec3 hor = mix(vec3(0.66, 0.80, 0.95), vec3(0.04, 0.10, 0.30), smoothstep(0.0, 0.9, space));
	vec3 col = mix(hor, zen, pow(clamp(up, 0.0, 1.0), 0.45));
	vec3 below = mix(vec3(0.58, 0.68, 0.80), vec3(0.02, 0.06, 0.14), space);
	col = mix(col, below, smoothstep(0.0, -0.12, up));
	// thin glowing limb of atmosphere seen from space
	float limb = exp(-abs(up + 0.06 * space) * 38.0);
	col += vec3(0.25, 0.5, 1.0) * limb * space * 0.9;
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.82, 0.55) * pow(sdot, 6.0) * 0.32 * (1.0 - space * 0.7);
	col += vec3(1.0, 0.96, 0.88) * pow(sdot, 1200.0) * 40.0;
	vec3 p = d * 230.0;
	vec3 cell = floor(p);
	float h = hash(cell);
	float star = smoothstep(0.994, 1.0, h) * smoothstep(0.3, 0.0, length(fract(p) - 0.5));
	col += vec3(0.9, 0.95, 1.0) * star * 3.0 * smoothstep(0.3, 0.9, space) * smoothstep(-0.1, 0.1, up);
	COLOR = col;
}
"""

const OCEAN_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.01, 0.07, 0.16);
uniform vec3 shallow : source_color = vec3(0.04, 0.32, 0.40);
uniform vec3 haze : source_color = vec3(0.60, 0.72, 0.86);
uniform float haze_dist = 30000.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float dist = length(VERTEX);
	float amp = 0.12 * clamp(1.0 - dist / 4000.0, 0.0, 1.0) + 0.01;
	vec2 w = vec2(
		sin(p.x * 0.050 + t * 0.9) + sin(p.y * 0.071 - t * 0.7) * 0.7 + sin((p.x + p.y) * 0.21 + t * 1.7) * 0.3,
		cos(p.y * 0.043 + t * 0.6) + cos(p.x * 0.033 - t * 0.8) * 0.7 + cos((p.x - p.y) * 0.19 - t * 1.5) * 0.3);
	vec3 nw = normalize(vec3(w.x * amp, 1.0, w.y * amp));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 col = mix(deep, shallow, 0.25 + 0.2 * w.x * amp * 4.0);
	float hz = 1.0 - exp(-dist / haze_dist);
	ALBEDO = mix(col, haze * 0.25, hz);
	EMISSION = haze * hz * 0.55 + vec3(0.6, 0.75, 0.9) * fres * 0.18 * (1.0 - hz);
	ROUGHNESS = mix(0.06, 0.4, hz);
	SPECULAR = 0.7;
}
"""

var noise := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var heights := PackedFloat32Array()
var env: Environment
var sky_mat: ShaderMaterial
var ocean_mat: ShaderMaterial
var sun: DirectionalLight3D
var blink_lights: Array[MeshInstance3D] = []
var tower_arm: Node3D
var _t := 0.0
var _space := -1.0

func _ready() -> void:
	noise.seed = 7
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.00035
	noise.fractal_octaves = 5
	ridge.seed = 21
	ridge.frequency = 0.00016
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 5
	_build_env()
	_build_terrain()
	_build_ocean()
	_build_trees()
	_build_pad()
	_build_base()

# --- terrain height -------------------------------------------------------

static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func raw_height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var hills := (noise.get_noise_2d(x, z) * 0.5 + 0.5) * 340.0
	var h := LAND_BASE + hills * _ss(1000.0, 3400.0, d)
	var r := ridge.get_noise_2d(x, z) * 0.5 + 0.5
	h += r * r * 2600.0 * _ss(-2500.0, -7500.0, z)
	var coast := maxf(_ss(8500.0, 11600.0, d), _ss(4300.0, 6400.0, x))
	return lerpf(h, -70.0, coast)

func grid_height(x: float, z: float) -> float:
	var fx := (x + SIZE * 0.5) / SIZE * GRID
	var fz := (z + SIZE * 0.5) / SIZE * GRID
	if fx < 0.0 or fz < 0.0 or fx >= GRID or fz >= GRID:
		return -70.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var w := GRID + 1
	var h0 := lerpf(heights[iz * w + ix], heights[iz * w + ix + 1], tx)
	var h1 := lerpf(heights[(iz + 1) * w + ix], heights[(iz + 1) * w + ix + 1], tx)
	return lerpf(h0, h1, tz)

## Height of whatever the rocket would touch along the flight line (z = 0).
func ground_height(x: float) -> float:
	if absf(x) < PAD_RADIUS:
		return PAD_TOP
	return maxf(grid_height(x, 0.0), 0.0)

func is_water(x: float) -> bool:
	return absf(x) >= PAD_RADIUS and grid_height(x, 0.0) < 0.0

# --- build ------------------------------------------------------------------

func _build_env() -> void:
	sky_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	sky_mat.shader = sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.73, 0.86)
	env.fog_density = 0.00012
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, 38, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.5
	add_child(sun)
	sky_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)

func _build_terrain() -> void:
	var w := GRID + 1
	var cell := SIZE / GRID
	heights.resize(w * w)
	for iz in w:
		for ix in w:
			heights[iz * w + ix] = raw_height(-SIZE * 0.5 + ix * cell, -SIZE * 0.5 + iz * cell)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	verts.resize(w * w)
	norms.resize(w * w)
	cols.resize(w * w)
	var grass_a := Color(0.20, 0.36, 0.13)
	var grass_b := Color(0.36, 0.44, 0.19)
	var rock := Color(0.40, 0.38, 0.36)
	var snow := Color(0.94, 0.96, 1.0)
	var sand := Color(0.78, 0.71, 0.52)
	for iz in w:
		for ix in w:
			var i := iz * w + ix
			var h := heights[i]
			var x := -SIZE * 0.5 + ix * cell
			var z := -SIZE * 0.5 + iz * cell
			verts[i] = Vector3(x, h, z)
			var hl := heights[iz * w + maxi(ix - 1, 0)]
			var hr := heights[iz * w + mini(ix + 1, GRID)]
			var hd := heights[maxi(iz - 1, 0) * w + ix]
			var hu := heights[mini(iz + 1, GRID) * w + ix]
			var n := Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			norms[i] = n
			var v := noise.get_noise_2d(x * 7.0, z * 7.0) * 0.5 + 0.5
			var c := grass_a.lerp(grass_b, v)
			c = c.lerp(rock, clampf((1.0 - n.y) * 4.0, 0.0, 1.0))
			c = c.lerp(rock, _ss(500.0, 1100.0, h))
			c = c.lerp(snow, _ss(1300.0, 1700.0, h + v * 200.0) * clampf(n.y * 1.6 - 0.4, 0.0, 1.0))
			c = c.lerp(sand, _ss(2.6, 1.0, h))
			if h < 0.0:
				c = sand.darkened(clampf(-h / 40.0, 0.0, 0.7))
			cols[i] = c
	for iz in GRID:
		for ix in GRID:
			var a := iz * w + ix
			idx.append(a)
			idx.append(a + 1)
			idx.append(a + w)
			idx.append(a + 1)
			idx.append(a + w + 1)
			idx.append(a + w)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	m.albedo_texture = _detail_texture()
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(0.012, 0.012, 0.012)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := Geo.mesh_node(mesh, m)
	add_child(mi)

func _detail_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.02
	n.fractal_octaves = 4
	var img := n.get_seamless_image(256, 256)
	img.convert(Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var v := 0.72 + img.get_pixel(x, y).r * 0.38
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_ocean() -> void:
	ocean_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = OCEAN_SHADER
	ocean_mat.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000000, 3000000)
	var mi := Geo.mesh_node(pm, ocean_mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _build_trees() -> void:
	var prof := PackedVector2Array([Vector2(0.35, -0.5), Vector2(0.35, 1.5), Vector2(2.6, 1.6), Vector2(1.2, 5.5), Vector2(1.9, 5.6), Vector2(0.0, 11.0)])
	var mesh := Geo.lathe(prof, 7)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var tries := 0
	while xforms.size() < 2200 and tries < 20000:
		tries += 1
		var p := Vector2(rng.randf_range(-9000, 9000), rng.randf_range(-9000, 5000))
		if p.length() < 380.0 or (p.x < -250 and p.x > -560 and p.y < -120 and p.y > -400):
			continue
		var h := grid_height(p.x, p.y)
		if h < 7.0 or h > 900.0:
			continue
		var s := rng.randf_range(0.7, 1.6)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.3), s))
		xforms.append(Transform3D(b, Vector3(p.x, h, p.y)))
		colors.append(Color(0.10, 0.22, 0.10).lerp(Color(0.2, 0.32, 0.12), rng.randf()))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _build_pad() -> void:
	var concrete := Geo.mat(Color(0.55, 0.55, 0.53), 0.0, 0.92)
	var dark := Geo.mat(Color(0.16, 0.17, 0.19), 0.3, 0.7)
	add_child(Geo.mesh_node(Geo.cylinder(PAD_RADIUS, PAD_RADIUS + 1.5, PAD_TOP - LAND_BASE + 0.4, 48), concrete, Vector3(0, (PAD_TOP + LAND_BASE - 0.4) * 0.5, 0)))
	# apron
	add_child(Geo.mesh_node(Geo.cylinder(32, 34, 0.3, 48), Geo.mat(Color(0.42, 0.42, 0.41), 0.0, 0.95), Vector3(0, LAND_BASE + 0.1, 0)))
	# landing marker
	var yellow := Geo.glow_mat(Color(1.0, 0.75, 0.15), 1.4)
	var ring := TorusMesh.new()
	ring.inner_radius = 9.0
	ring.outer_radius = 9.9
	ring.rings = 48
	var rn := Geo.mesh_node(ring, yellow, Vector3(0, PAD_TOP + 0.01, 0))
	rn.scale = Vector3(1, 0.04, 1)
	add_child(rn)
	for a in [0.0, PI * 0.5]:
		var bar := Geo.mesh_node(Geo.box(Vector3(11, 0.04, 0.9)), yellow, Vector3(0, PAD_TOP + 0.02, 0))
		bar.rotation.y = a + PI * 0.25
		add_child(bar)
	# tower
	var steel := Geo.mat(Color(0.75, 0.28, 0.14), 0.4, 0.5)
	var tower := Node3D.new()
	tower.position = Vector3(0, PAD_TOP, -11.0)
	add_child(tower)
	var th := 42.0
	for c in [Vector2(-1.6, -1.6), Vector2(1.6, -1.6), Vector2(-1.6, 1.6), Vector2(1.6, 1.6)]:
		tower.add_child(Geo.mesh_node(Geo.box(Vector3(0.35, th, 0.35)), steel, Vector3(c.x, th * 0.5, c.y)))
	var y := 3.0
	while y < th:
		for side in [Vector3(0, 0, 1.6), Vector3(0, 0, -1.6)]:
			tower.add_child(Geo.mesh_node(Geo.box(Vector3(3.4, 0.22, 0.22)), steel, Vector3(0, y, 0) + side))
		for side in [Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0)]:
			tower.add_child(Geo.mesh_node(Geo.box(Vector3(0.22, 0.22, 3.4)), steel, Vector3(0, y, 0) + side))
		var diag := Geo.mesh_node(Geo.box(Vector3(0.15, 4.7, 0.15)), steel, Vector3(0, y + 2.0, 1.6))
		diag.rotation.z = 0.72 * (1.0 if int(y) % 8 < 4 else -1.0)
		tower.add_child(diag)
		y += 4.0
	tower.add_child(Geo.mesh_node(Geo.box(Vector3(4.4, 0.5, 4.4)), dark, Vector3(0, th, 0)))
	var red := Geo.glow_mat(Color(1.0, 0.1, 0.05), 3.0)
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.7
	for p in [Vector3(1.8, th + 0.6, 1.8), Vector3(-1.8, th + 0.6, -1.8), Vector3(1.8, 22, 1.8), Vector3(-1.8, 22, 1.8)]:
		var b := Geo.mesh_node(bulb, red.duplicate(), p)
		tower.add_child(b)
		blink_lights.append(b)
	tower_arm = Node3D.new()
	tower_arm.position = Vector3(0, 15.0, 1.6)
	tower.add_child(tower_arm)
	tower_arm.add_child(Geo.mesh_node(Geo.box(Vector3(1.2, 1.0, 7.0)), steel, Vector3(0, 0, 3.5)))
	var flood := OmniLight3D.new()
	flood.position = Vector3(0, 30, 6)
	flood.light_color = Color(1.0, 0.9, 0.75)
	flood.light_energy = 0.6
	flood.omni_range = 45.0
	tower.add_child(flood)

func _build_base() -> void:
	var white := Geo.mat(Color(0.88, 0.89, 0.9), 0.1, 0.6)
	var stripe := Geo.mat(Color(0.12, 0.25, 0.55), 0.1, 0.5)
	var gray := Geo.mat(Color(0.35, 0.36, 0.38), 0.2, 0.8)
	var base_h := LAND_BASE
	# assembly building
	add_child(Geo.mesh_node(Geo.box(Vector3(90, 120, 70)), white, Vector3(-400, base_h + 60, -260)))
	add_child(Geo.mesh_node(Geo.box(Vector3(90.4, 8, 70.4)), stripe, Vector3(-400, base_h + 100, -260)))
	add_child(Geo.mesh_node(Geo.box(Vector3(30, 90, 1)), gray, Vector3(-400, base_h + 45, -224.6)))
	# hangars and tanks
	for i in 3:
		add_child(Geo.mesh_node(Geo.box(Vector3(40, 18, 30)), gray, Vector3(-260 + i * 55, base_h + 9, -330)))
	var sphere := SphereMesh.new()
	sphere.radius = 9.0
	sphere.height = 18.0
	for i in 3:
		add_child(Geo.mesh_node(sphere, white, Vector3(90 + i * 24, base_h + 12, -120)))
		add_child(Geo.mesh_node(Geo.cylinder(1.2, 1.2, 4), gray, Vector3(90 + i * 24, base_h + 2, -120)))
	# road
	var road := Geo.mesh_node(Geo.box(Vector3(10, 0.2, 460)), Geo.mat(Color(0.2, 0.2, 0.21), 0.0, 0.9), Vector3(-200, base_h + 0.05, -120))
	road.rotation.y = -1.1
	add_child(road)

# --- runtime ---------------------------------------------------------------

func update_env(alt: float, cam_dist: float, delta: float) -> void:
	_t += delta
	var s := 1.0 - exp(-maxf(alt, 0.0) / 20000.0)
	if absf(s - _space) > 0.008:
		_space = s
		sky_mat.set_shader_parameter("space", s)
		env.ambient_light_energy = lerpf(0.5, 0.2, s)
		env.fog_light_color = Color(0.62, 0.73, 0.86).lerp(Color(0.05, 0.1, 0.25), s)
		ocean_mat.set_shader_parameter("haze", Color(0.60, 0.72, 0.86).lerp(Color(0.10, 0.20, 0.45), s))
		ocean_mat.set_shader_parameter("haze_dist", 30000.0 + alt * 6.0)
	env.fog_density = 0.00012 * exp(-maxf(alt, 0.0) / 2500.0)
	sun.directional_shadow_max_distance = clampf(cam_dist * 3.5, 60.0, 600.0)
	var on := fmod(_t, 1.2) < 0.6
	for b in blink_lights:
		b.visible = on

func set_arm(attached: bool, animate := true) -> void:
	var target := 0.0 if attached else -1.9
	if animate:
		create_tween().tween_property(tower_arm, "rotation:y", target, 2.0).set_trans(Tween.TRANS_SINE)
	else:
		tower_arm.rotation.y = target
