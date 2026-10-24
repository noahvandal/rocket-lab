class_name Rocket
extends Node3D
## Procedurally assembled rocket with simple 2D (x/altitude) flight physics.

signal contact(info: Dictionary)

const R := Parts.RADIUS
const LEG_DROP := 0.6
const MAX_RATE := 0.9

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 hot : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 cool : source_color = vec3(1.0, 0.38, 0.06);
uniform float intensity = 1.0;
uniform float diamonds = 1.0;
varying float t;
void vertex() { t = clamp(-VERTEX.y, 0.0, 1.0); }
void fragment() {
	float f = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flick = 0.85 + 0.15 * sin(TIME * 57.0 + t * 31.0) * sin(TIME * 23.0);
	float shock = 1.0 + diamonds * 0.9 * pow(0.5 + 0.5 * cos(t * 30.0), 8.0) * (1.0 - t);
	vec3 col = mix(hot, cool, smoothstep(0.0, 0.75, t));
	float fade = pow(1.0 - t, 1.5) * smoothstep(0.0, 0.04, t + 0.02);
	ALBEDO = col * fade * pow(f, 1.3) * intensity * flick * shock * 1.8;
}
"""

var design := {}
var dry_mass := 1.0
var fuel := 0.0
var fuel_max := 0.0
var max_thrust := 0.0
var isp_sl := 280.0
var isp_vac := 320.0
var cd := 0.5
var height := 10.0
var com_h := 4.0
var torque := 0.0
var has_legs := false
var has_fins := false

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var ang_vel := 0.0
var throttle := 0.0
var thrust_now := 0.0
var legs_deployed := true
var leg_anim := 1.0
var on_ground := true
var airborne := false
var has_flown := false
var dead := false
var pressure := 1.0
var heat := 0.0
var ground_func: Callable
var water_func: Callable

var visual: Node3D
var flames: Array[MeshInstance3D] = []
var cores: Array[MeshInstance3D] = []
var leg_pivots: Array[Node3D] = []
var bell_mat: StandardMaterial3D
var flame_mat: ShaderMaterial
var core_mat: ShaderMaterial
var plasma_mat: ShaderMaterial
var bell_r := 0.7
var smoke: CPUParticles3D
var dust: CPUParticles3D
var plasma: MeshInstance3D
var engine_light: OmniLight3D
var flame_mesh: ArrayMesh

func _ready() -> void:
	var sh := Shader.new()
	sh.code = FLAME_SHADER
	flame_mat = ShaderMaterial.new()
	flame_mat.shader = sh
	core_mat = ShaderMaterial.new()
	core_mat.shader = sh
	core_mat.set_shader_parameter("hot", Color(0.85, 0.9, 1.0))
	core_mat.set_shader_parameter("cool", Color(1.0, 0.75, 0.45))
	plasma_mat = ShaderMaterial.new()
	plasma_mat.shader = sh
	plasma_mat.set_shader_parameter("hot", Color(1.0, 0.55, 0.3))
	plasma_mat.set_shader_parameter("cool", Color(0.9, 0.2, 0.5))
	plasma_mat.set_shader_parameter("diamonds", 0.0)
	flame_mesh = Geo.lathe(PackedVector2Array([Vector2(0.02, -1.0), Vector2(0.45, -0.75), Vector2(0.8, -0.4), Vector2(0.97, -0.12), Vector2(1.0, 0.0)]), 20)

	smoke = CPUParticles3D.new()
	smoke.amount = 360
	smoke.lifetime = 4.0
	smoke.local_coords = false
	smoke.emitting = false
	var q := QuadMesh.new()
	q.material = Geo.particle_mat()
	smoke.mesh = q
	smoke.direction = Vector3(0, -1, 0)
	smoke.spread = 10.0
	smoke.initial_velocity_min = 22.0
	smoke.initial_velocity_max = 38.0
	smoke.gravity = Vector3(0, 1.2, 0)
	smoke.damping_min = 6.0
	smoke.damping_max = 10.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.8
	smoke.scale_amount_min = 5.0
	smoke.scale_amount_max = 9.0
	smoke.scale_amount_curve = Geo.curve(0.25, 1.0)
	smoke.color_ramp = Geo.ramp([[0.0, Color(1.0, 0.75, 0.4, 0.9)], [0.07, Color(0.95, 0.85, 0.75, 0.65)], [0.35, Color(0.82, 0.82, 0.84, 0.35)], [1.0, Color(0.8, 0.8, 0.82, 0.0)]])
	add_child(smoke)

	dust = CPUParticles3D.new()
	dust.top_level = true
	dust.amount = 120
	dust.lifetime = 3.0
	dust.local_coords = false
	dust.emitting = false
	var dq := QuadMesh.new()
	dq.material = Geo.particle_mat()
	dust.mesh = dq
	dust.direction = Vector3(1, 0, 0)
	dust.spread = 180.0
	dust.flatness = 1.0
	dust.initial_velocity_min = 25.0
	dust.initial_velocity_max = 45.0
	dust.gravity = Vector3(0, 1.5, 0)
	dust.damping_min = 9.0
	dust.damping_max = 14.0
	dust.scale_amount_min = 4.0
	dust.scale_amount_max = 8.0
	dust.scale_amount_curve = Geo.curve(0.3, 1.0)
	dust.color_ramp = Geo.ramp([[0.0, Color(0.85, 0.78, 0.65, 0.7)], [1.0, Color(0.75, 0.72, 0.66, 0.0)]])
	add_child(dust)

	plasma = MeshInstance3D.new()
	plasma.top_level = true
	plasma.mesh = flame_mesh
	plasma.material_override = plasma_mat
	plasma.visible = false
	add_child(plasma)

	engine_light = OmniLight3D.new()
	engine_light.light_color = Color(1.0, 0.6, 0.25)
	engine_light.omni_range = 40.0
	engine_light.light_energy = 0.0
	add_child(engine_light)

func build(d: Dictionary) -> void:
	design = d.duplicate(true)
	if visual:
		visual.queue_free()
	visual = Node3D.new()
	add_child(visual)
	flames.clear()
	cores.clear()
	leg_pivots.clear()

	var s := Parts.stats(design)
	dry_mass = s.dry
	fuel = s.fuel
	fuel_max = s.fuel
	max_thrust = s.thrust
	isp_sl = s.isp_sl
	isp_vac = s.isp_vac
	cd = s.cd
	height = s.height
	torque = s.torque
	has_legs = design.legs
	has_fins = design.fins

	var white := Geo.mat(Color(0.93, 0.93, 0.95), 0.15, 0.32)
	var black := Geo.mat(Color(0.07, 0.07, 0.08), 0.3, 0.45)
	var accent := Geo.mat(Color(0.95, 0.38, 0.1), 0.2, 0.35)
	var steel := Geo.mat(Color(0.55, 0.56, 0.6), 0.9, 0.3)
	bell_mat = Geo.mat(Color(0.2, 0.19, 0.19), 0.85, 0.3, true)
	bell_mat.emission_enabled = true
	bell_mat.emission = Color(1.0, 0.4, 0.1)
	bell_mat.emission_energy_multiplier = 0.0

	var mass_y := 0.0
	var mass_sum := 0.0

	# engines
	var eng: Dictionary = Parts.ENGINES[design.engine]
	var count: int = design.count
	var eh: float = eng.h
	var offsets := _cluster(count)
	var spread := R * 0.55
	bell_r = eng.bell
	if count > 1:
		var spacing := (offsets[0] - offsets[1]).length() * spread
		bell_r = minf(bell_r, spacing * 0.48)
	var bell_h := eh * 0.68
	var bprof := PackedVector2Array()
	for i in 9:
		var t := i / 8.0
		bprof.append(Vector2(bell_r * 0.36 + bell_r * 0.64 * pow(1.0 - t, 2.2), t * bell_h))
	var bell_mesh := Geo.lathe(bprof, 24)
	for o in offsets:
		var p := Vector3(o.x * spread, 0, o.y * spread)
		visual.add_child(Geo.mesh_node(bell_mesh, bell_mat, p))
		visual.add_child(Geo.mesh_node(Geo.cylinder(bell_r * 0.32, bell_r * 0.42, eh - bell_h, 16), steel, p + Vector3(0, bell_h + (eh - bell_h) * 0.5, 0)))
		var f := Geo.mesh_node(flame_mesh, flame_mat, p)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		visual.add_child(f)
		flames.append(f)
		var c := Geo.mesh_node(flame_mesh, core_mat, p)
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.visible = false
		visual.add_child(c)
		cores.append(c)
	mass_y += eng.mass * count * eh * 0.5
	mass_sum += eng.mass * count

	var y := eh
	var mount_bottom := R * 0.8 if count == 1 else R * 0.98
	visual.add_child(Geo.mesh_node(Geo.cylinder(R, mount_bottom, Parts.MOUNT_H), black, Vector3(0, y + Parts.MOUNT_H * 0.5, 0)))
	mass_y += Parts.MOUNT_MASS * (y + 0.25)
	mass_sum += Parts.MOUNT_MASS
	y += Parts.MOUNT_H

	var attach_y := y
	var attach_h := 1.5
	var tanks: Array = design.tanks
	for i in range(tanks.size() - 1, -1, -1):
		var tk: Dictionary = Parts.TANKS[tanks[i]]
		var th: float = tk.h
		if i == tanks.size() - 1:
			attach_h = th
		visual.add_child(Geo.mesh_node(Geo.cylinder(R, R, th), white, Vector3(0, y + th * 0.5, 0)))
		visual.add_child(Geo.mesh_node(Geo.cylinder(R + 0.02, R + 0.02, 0.14), black, Vector3(0, y + 0.07, 0)))
		visual.add_child(Geo.mesh_node(Geo.cylinder(R + 0.02, R + 0.02, 0.14), black, Vector3(0, y + th - 0.07, 0)))
		if th >= 4.0:
			# roll pattern stripe, like a classic test rocket
			var band := Geo.mesh_node(Geo.cylinder(R + 0.015, R + 0.015, th * 0.18), black if i % 2 == 0 else accent, Vector3(0, y + th * 0.62, 0))
			visual.add_child(band)
		mass_y += (tk.dry + tk.fuel) * (y + th * 0.5)
		mass_sum += tk.dry + tk.fuel
		y += th

	# nose
	var nose: Dictionary = Parts.NOSES[design.nose]
	var nh: float = nose.h
	match design.nose:
		"cone":
			var prof := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				prof.append(Vector2(R * pow(1.0 - t, 0.55), y + t * nh))
			visual.add_child(Geo.mesh_node(Geo.lathe(prof, 32), accent))
		"capsule":
			var prof := PackedVector2Array([Vector2(R, y), Vector2(R * 0.98, y + 0.25), Vector2(R * 0.62, y + nh * 0.78), Vector2(R * 0.5, y + nh * 0.9), Vector2(R * 0.28, y + nh * 0.97), Vector2(0.0, y + nh)])
			visual.add_child(Geo.mesh_node(Geo.lathe(prof, 32), Geo.mat(Color(0.2, 0.21, 0.23), 0.4, 0.4)))
			visual.add_child(Geo.mesh_node(Geo.cylinder(R + 0.03, R + 0.03, 0.18), accent, Vector3(0, y + 0.09, 0)))
			var win := Geo.glow_mat(Color(0.5, 0.85, 1.0), 1.6)
			for a in [-0.35, 0.35]:
				var wy := y + nh * 0.42
				var wr := lerpf(R * 0.98, R * 0.62, 0.42 / 0.78)
				var wn := Geo.mesh_node(Geo.box(Vector3(0.36, 0.42, 0.06)), win, Vector3(sin(a) * wr, wy, cos(a) * wr))
				wn.rotation = Vector3(-0.3, a, 0)
				visual.add_child(wn)
		_:
			visual.add_child(Geo.mesh_node(Geo.cylinder(R * 0.9, R, nh), black, Vector3(0, y + nh * 0.5, 0)))
	mass_y += nose.mass * (y + nh * 0.4)
	mass_sum += nose.mass
	y += nh

	# fins
	if has_fins:
		var fin_mesh := Geo.prism(PackedVector2Array([Vector2(0, 0.0), Vector2(1.5, -0.6), Vector2(1.5, 0.5), Vector2(0, 2.3)]), 0.1)
		var fh := minf(attach_h, 2.3)
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var fin := Geo.mesh_node(fin_mesh, accent, Vector3(cos(a) * (R - 0.05), attach_y + 0.05, sin(a) * (R - 0.05)))
			fin.rotation.y = -a
			fin.scale = Vector3(1, fh / 2.3, 1)
			visual.add_child(fin)
		mass_y += Parts.FINS_MASS * (attach_y + 1.0)
		mass_sum += Parts.FINS_MASS

	# legs
	if has_legs:
		var carbon := Geo.mat(Color(0.12, 0.12, 0.13), 0.4, 0.5)
		var py := attach_y + minf(attach_h * 0.75, 2.2)
		var leg_len := (py + LEG_DROP) / cos(deg_to_rad(32.0))
		for k in 4:
			var a := k * PI * 0.5
			var piv := Node3D.new()
			piv.position = Vector3(cos(a) * (R + 0.12), py, sin(a) * (R + 0.12))
			piv.rotation = Vector3(0, -a, deg_to_rad(32.0))
			piv.add_child(Geo.mesh_node(Geo.box(Vector3(0.24, leg_len, 0.3)), carbon, Vector3(0, -leg_len * 0.5, 0)))
			var foot := Geo.mesh_node(Geo.cylinder(0.42, 0.5, 0.14, 12), black, Vector3(0, -leg_len, 0))
			foot.rotation.z = -deg_to_rad(32.0)
			piv.add_child(foot)
			visual.add_child(piv)
			leg_pivots.append(piv)
		mass_y += Parts.LEGS_MASS * py
		mass_sum += Parts.LEGS_MASS

	com_h = mass_y / maxf(mass_sum, 0.01)
	visual.position.y = -com_h
	smoke.position = Vector3(0, -com_h - 1.0, 0)
	engine_light.position = Vector3(0, -com_h - 3.0, 0)
	_apply_legs()

func _cluster(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	match n:
		1:
			out.append(Vector2.ZERO)
		2:
			out.append(Vector2(-1, 0))
			out.append(Vector2(1, 0))
		_:
			for i in n:
				var a := TAU * i / n + (PI * 0.25 if n == 4 else PI * 0.5)
				out.append(Vector2(cos(a), sin(a)))
	return out

func bottom_offset() -> float:
	return com_h + (LEG_DROP * leg_anim if has_legs else 0.0)

func up_vec() -> Vector2:
	return Vector2(-sin(angle), cos(angle))

func mass() -> float:
	return dry_mass + fuel

func reset_on_pad(ground_y: float) -> void:
	legs_deployed = true
	leg_anim = 1.0
	_apply_legs()
	pos = Vector2(0, ground_y + bottom_offset())
	vel = Vector2.ZERO
	angle = 0.0
	ang_vel = 0.0
	throttle = 0.0
	thrust_now = 0.0
	on_ground = true
	airborne = false
	has_flown = false
	dead = false
	heat = 0.0
	if visual:
		visual.visible = true
	update_visual(0.0)

func toggle_legs() -> void:
	if has_legs:
		legs_deployed = not legs_deployed

## Advance physics. steer > 0 rotates counter-clockwise (lean left).
func physics_step(dt: float, steer: float, sas: String) -> void:
	if dead:
		return
	var alt := pos.y
	var rho := 1.225 * exp(-maxf(alt, 0.0) / 8500.0)
	pressure = rho / 1.225
	var m := mass()
	thrust_now = 0.0
	if fuel > 0.0 and throttle > 0.001:
		thrust_now = max_thrust * throttle
		var isp := lerpf(isp_vac, isp_sl, pressure)
		fuel = maxf(fuel - thrust_now / (isp * Parts.G0) * dt, 0.0)
	var up := up_vec()
	var acc := up * (thrust_now / m)
	var g := Parts.G0 * pow(6371000.0 / (6371000.0 + maxf(alt, 0.0)), 2.0)
	acc.y -= g
	var speed := vel.length()
	var q := 0.5 * rho * speed * speed
	if speed > 0.01:
		var side := absf(up.cross(vel / speed))
		var area := PI * R * R * (1.0 + side * 5.0)
		var drag := q * (cd + (0.25 if has_legs and legs_deployed else 0.0)) * area / 1000.0
		acc -= vel / speed * minf(drag / m, speed / dt * 0.5)
	heat = clampf((rho * pow(speed, 3.0) / 1.0e8 - 0.04) * 2.0, 0.0, 1.0)

	# attitude control
	var auth := 0.25 + torque + (1.1 if thrust_now > 0.0 else 0.0) + (minf(q / 15000.0, 1.0) * 1.4 if has_fins else 0.0)
	auth /= sqrt(maxf(height, 4.0) / 10.0)
	var ang_acc := 0.0
	var target_rate := steer * MAX_RATE
	match sas:
		"OFF":
			ang_acc = steer * auth
		"RETRO", "UP":
			var want := 0.0
			if sas == "RETRO" and speed > 2.0:
				want = atan2(vel.x, -vel.y)
			var err := wrapf(want - angle, -PI, PI)
			if steer == 0.0:
				target_rate = clampf(err * 1.6, -MAX_RATE, MAX_RATE)
			ang_acc = clampf((target_rate - ang_vel) * 4.0, -auth, auth)
		_:
			ang_acc = clampf((target_rate - ang_vel) * 4.0, -auth, auth)
	if on_ground:
		ang_acc -= ang_vel * 6.0 + angle * 3.0
	ang_vel += ang_acc * dt
	angle = wrapf(angle + ang_vel * dt, -PI, PI)

	vel += acc * dt
	pos += vel * dt

	# ground contact
	var target_legs := 1.0 if legs_deployed else 0.0
	leg_anim = move_toward(leg_anim, target_legs, dt * 0.9)
	up = up_vec()
	var bottom := pos - up * bottom_offset()
	var gh: float = ground_func.call(bottom.x)
	if bottom.y > gh + 1.5:
		airborne = true
		has_flown = true
	if bottom.y <= gh:
		if not on_ground and airborne:
			airborne = false
			contact.emit({"speed": vel.length(), "vspeed": -vel.y, "hspeed": absf(vel.x), "tilt": absf(angle), "water": water_func.call(bottom.x)})
		on_ground = true
		pos.y += gh - bottom.y
		if vel.y < 0.0:
			vel.y = 0.0
		vel.x = move_toward(vel.x, 0.0, 6.0 * dt)
	else:
		on_ground = false

func explode() -> void:
	dead = true
	thrust_now = 0.0
	throttle = 0.0
	visual.visible = false
	smoke.emitting = false
	dust.emitting = false
	plasma.visible = false
	engine_light.light_energy = 0.0

func _apply_legs() -> void:
	var phi := lerpf(deg_to_rad(176.0), deg_to_rad(32.0), leg_anim)
	for p in leg_pivots:
		p.rotation.z = phi

func update_visual(delta: float) -> void:
	position = Vector3(pos.x, pos.y, 0)
	rotation = Vector3(0, 0, angle)
	_apply_legs()
	if dead:
		return
	var thr := thrust_now / maxf(max_thrust, 0.001)
	var firing := thr > 0.001
	var vac := 1.0 - pressure
	var flick := 1.0 + randf_range(-0.06, 0.06)
	var length := (5.0 + bell_r * 9.0) * pow(thr, 0.6) * (1.0 + vac * 1.6) * flick
	var width := bell_r * 0.92 * (1.0 + vac * 2.4) * (0.85 + 0.15 * thr)
	for f in flames:
		f.visible = firing
		f.scale = Vector3(width, length, width)
	for c in cores:
		c.visible = firing
		c.scale = Vector3(bell_r * 0.55, length * 0.42, bell_r * 0.55)
	flame_mat.set_shader_parameter("intensity", 0.6 + thr * 0.6)
	flame_mat.set_shader_parameter("diamonds", pressure)
	core_mat.set_shader_parameter("diamonds", pressure)
	bell_mat.emission_energy_multiplier = thr * 0.9
	engine_light.light_energy = thr * 6.0 * flick
	smoke.emitting = firing and pos.y < 28000.0
	smoke.initial_velocity_min = 20.0 + thr * 10.0
	var gh: float = ground_func.call(pos.x)
	var agl := pos.y - bottom_offset() - gh
	dust.emitting = firing and agl < 45.0 and thr > 0.15
	dust.global_position = Vector3(pos.x, gh + 0.6, 0)
	var speed := vel.length()
	plasma.visible = heat > 0.01
	if plasma.visible:
		var vd := vel / speed
		var up := up_vec()
		var lead := (height - com_h) if up.dot(vd) > 0.0 else com_h
		var y3 := Vector3(vd.x, vd.y, 0)
		var x3 := y3.cross(Vector3(0, 0, 1))
		var w := R * (1.3 + heat * 0.6)
		var b := Basis(x3 * w, y3 * (10.0 + heat * 30.0), Vector3(0, 0, w))
		plasma.global_transform = Transform3D(b, Vector3(pos.x, pos.y, 0) + y3 * (lead + 0.3))
		plasma_mat.set_shader_parameter("intensity", heat * 1.4)
