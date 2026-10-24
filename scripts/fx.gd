class_name Fx
extends RefCounted
## One-shot visual effects.

static func explosion(parent: Node, at: Vector3, scale := 1.0) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = at

	var fire := _burst(70, 1.4, 12.0 * scale, 38.0 * scale, Vector3(0, 3, 0), Geo.particle_mat(true))
	fire.scale_amount_min = 5.0 * scale
	fire.scale_amount_max = 11.0 * scale
	fire.scale_amount_curve = Geo.curve(0.4, 1.0)
	fire.color_ramp = Geo.ramp([[0.0, Color(1.0, 0.95, 0.8, 1.0)], [0.2, Color(1.0, 0.55, 0.15, 0.9)], [0.6, Color(0.6, 0.18, 0.05, 0.5)], [1.0, Color(0.2, 0.1, 0.05, 0.0)]])
	root.add_child(fire)

	var smoke := _burst(50, 6.0, 6.0 * scale, 20.0 * scale, Vector3(0, 2.5, 0), Geo.particle_mat())
	smoke.scale_amount_min = 8.0 * scale
	smoke.scale_amount_max = 15.0 * scale
	smoke.scale_amount_curve = Geo.curve(0.3, 1.0)
	smoke.color_ramp = Geo.ramp([[0.0, Color(0.25, 0.22, 0.2, 0.0)], [0.1, Color(0.2, 0.18, 0.17, 0.8)], [1.0, Color(0.35, 0.34, 0.33, 0.0)]])
	root.add_child(smoke)

	var debris := _burst(36, 3.0, 15.0 * scale, 45.0 * scale, Vector3(0, -9.8, 0), Geo.mat(Color(0.15, 0.14, 0.14), 0.5, 0.5))
	debris.mesh = Geo.box(Vector3(0.5, 0.25, 0.8))
	debris.particle_flag_rotate_y = true
	debris.angular_velocity_min = -400.0
	debris.angular_velocity_max = 400.0
	debris.damping_min = 0.5
	debris.damping_max = 1.0
	root.add_child(debris)

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.light_energy = 14.0
	flash.omni_range = 90.0 * scale
	root.add_child(flash)
	flash.create_tween().tween_property(flash, "light_energy", 0.0, 1.4).set_ease(Tween.EASE_OUT)

	var timer := root.get_tree().create_timer(8.0)
	timer.timeout.connect(root.queue_free)

static func _burst(n: int, life: float, vmin: float, vmax: float, gravity: Vector3, material: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = n
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = vmin
	p.initial_velocity_max = vmax
	p.gravity = gravity
	p.damping_min = 3.0
	p.damping_max = 6.0
	var q := QuadMesh.new()
	q.material = material
	p.mesh = q
	p.emitting = true
	return p
