extends Node3D
## Game controller: states, input, camera, mission rules and scoring.

const SAS_MODES := ["STAB", "RETRO", "UP", "OFF"]
const SAS_NAMES := {"STAB": "HOLD", "RETRO": "RETRO", "UP": "UPRIGHT", "OFF": "MANUAL"}
const WARPS := [1, 2, 4]
const SAVE_PATH := "user://rocket_lab.cfg"

var world: World
var rocket: Rocket
var cam: Camera3D
var hud: Hud
var sfx: Sfx

var design := Parts.default_design()
var mission_idx := 0
var best := {}
var state := "build"   # build, countdown, flight, over
var countdown := 0.0
var sas := 0
var warp_idx := 0
var cam_mode := 0
var cam_yaw := 0.45
var cam_pitch := 0.08
var cam_zoom := 1.0
var dragging := false
var shake := 0.0
var max_alt := 0.0
var target_reached := false
var flight_time := 0.0
var settle_time := 0.0
var touchdown_speed := 0.0
var landed_note_shown := false
var fuel_note_shown := false
var burn_note_time := 0.0
var over_timer := -1.0
var _pending_result := {}

func _ready() -> void:
	_apply_scale()
	get_tree().root.size_changed.connect(_apply_scale)
	world = World.new()
	add_child(world)
	cam = Camera3D.new()
	cam.far = 1500000.0
	cam.fov = 60.0
	add_child(cam)
	cam.current = true
	rocket = Rocket.new()
	add_child(rocket)
	rocket.ground_func = world.ground_height
	rocket.water_func = world.is_water
	rocket.contact.connect(_on_contact)
	sfx = Sfx.new()
	add_child(sfx)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Hud.new()
	hud.game = self
	layer.add_child(hud)
	_load()
	_reset_to_pad()
	hud.show_build()

func _apply_scale() -> void:
	var dpr := DisplayServer.screen_get_scale()
	if dpr <= 0.0:
		dpr = 1.0
	var win := Vector2(get_tree().root.size)
	var css := win / dpr
	var f := dpr
	if minf(css.x, css.y) < 420.0:
		f *= 0.88
	get_tree().root.content_scale_factor = f
	# Keep 3D rendering affordable on high-density phone screens.
	get_viewport().scaling_3d_scale = clampf(1.6 / dpr, 0.55, 1.0)

# --- builder actions -----------------------------------------------------------

func _rebuild() -> void:
	_reset_to_pad()
	hud.refresh_build()

func set_nose(id: String) -> void:
	design.nose = id
	_rebuild()

func add_tank(id: String) -> void:
	if design.tanks.size() < Parts.MAX_TANKS:
		design.tanks.append(id)
	_rebuild()

func remove_tank() -> void:
	if design.tanks.size() > 0:
		design.tanks.pop_back()
	_rebuild()

func set_engine(id: String) -> void:
	design.engine = id
	_rebuild()

func change_count(d: int) -> void:
	design.count = clampi(design.count + d, 1, Parts.MAX_ENGINES)
	_rebuild()

func toggle_part(key: String) -> void:
	design[key] = not design[key]
	_rebuild()

func set_mission(i: int) -> void:
	mission_idx = i
	hud.refresh_build()
	_save()

func _reset_to_pad() -> void:
	rocket.build(design)
	rocket.reset_on_pad(World.PAD_TOP)
	world.set_arm(true, false)
	state = "build"
	sas = 0
	warp_idx = 0
	shake = 0.0
	over_timer = -1.0
	sfx.set_engine(0.0, 1.0)

func launch() -> void:
	var s := Parts.stats(design)
	if s.fuel <= 0.0 or s.twr < 1.0:
		hud.flash("This rocket can't lift off.", 2.0, Color(1, 0.5, 0.4))
		return
	_save()
	_reset_to_pad()
	state = "countdown"
	countdown = 3.0
	max_alt = 0.0
	target_reached = false
	flight_time = 0.0
	settle_time = 0.0
	landed_note_shown = false
	fuel_note_shown = false
	cam_zoom = 1.0
	hud.show_flight()
	hud.flash("3", 0.8)
	sfx.beep()
	world.set_arm(false)

func retry() -> void:
	launch()

func back_to_build() -> void:
	_reset_to_pad()
	hud.show_build()

func next_mission() -> void:
	mission_idx = mini(mission_idx + 1, Parts.MISSIONS.size() - 1)
	back_to_build()

func on_action(id: String) -> void:
	match id:
		"legs":
			rocket.toggle_legs()
		"sas":
			sas = (sas + 1) % SAS_MODES.size()
			hud.flash("Assist: " + SAS_NAMES[SAS_MODES[sas]], 1.0)
		"cam":
			cam_mode = (cam_mode + 1) % 2
		"warp":
			warp_idx = (warp_idx + 1) % WARPS.size()
		"menu":
			back_to_build()

# --- input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var flying := state in ["countdown", "flight"]
		match event.keycode:
			KEY_G:
				if flying: on_action("legs")
			KEY_Q:
				if flying: on_action("sas")
			KEY_C:
				on_action("cam")
			KEY_T:
				if flying: on_action("warp")
			KEY_R:
				if state != "build": retry()
			KEY_ESCAPE, KEY_M:
				if state != "build": back_to_build()
			KEY_SPACE, KEY_ENTER:
				if state == "build": launch()
			KEY_Z:
				if flying: rocket.throttle = 1.0
			KEY_X:
				if flying: rocket.throttle = 0.0
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_zoom = clampf(cam_zoom * 0.9, 0.25, 8.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_zoom = clampf(cam_zoom * 1.1, 0.25, 8.0)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging = event.pressed
	elif event is InputEventMouseMotion and dragging:
		cam_yaw -= event.relative.x * 0.006
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.004, -0.35, 1.4)
	elif event is InputEventMagnifyGesture:
		cam_zoom = clampf(cam_zoom / event.factor, 0.25, 8.0)
	elif event is InputEventPanGesture:
		cam_zoom = clampf(cam_zoom * (1.0 + event.delta.y * 0.03), 0.25, 8.0)

func _steer_input() -> float:
	var s := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		s += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		s -= 1.0
	return clampf(s + hud.touch.steer, -1.0, 1.0)

func _throttle_input(delta: float) -> void:
	var r := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_SHIFT):
		r += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_CTRL):
		r -= 1.0
	rocket.throttle = clampf(rocket.throttle + r * delta * 0.9, 0.0, 1.0)
	if hud.touch.throttle_set >= 0.0:
		rocket.throttle = hud.touch.throttle_set

# --- simulation ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == "build":
		rocket.physics_step(delta, 0.0, "STAB")
		return
	if state == "countdown":
		var prev := ceili(countdown)
		countdown -= delta
		if ceili(countdown) != prev and countdown > 0.0:
			hud.flash(str(ceili(countdown)), 0.8)
			sfx.beep()
		if countdown <= 0.0:
			state = "flight"
			rocket.throttle = 1.0
			hud.flash("LIFTOFF!", 1.6, Color(1.0, 0.8, 0.4))
			sfx.beep(true)
	if state == "flight":
		_throttle_input(delta)
		var w: int = WARPS[warp_idx]
		var agl := _agl()
		if w > 1 and (agl < 1500.0 and rocket.vel.y < 0.0 or agl < 200.0):
			warp_idx = 0
			w = 1
		for i in w:
			rocket.physics_step(delta, _steer_input(), SAS_MODES[sas])
			if state != "flight":
				break
		flight_time += delta * w
		_mission_logic(delta * w)
	elif state == "over":
		rocket.physics_step(delta, 0.0, "OFF")
		if over_timer > 0.0:
			over_timer -= delta
			if over_timer <= 0.0:
				_show_pending_result()

func _agl() -> float:
	return rocket.pos.y - rocket.bottom_offset() - world.ground_height(rocket.pos.x)

func _altitude() -> float:
	return rocket.pos.y - rocket.bottom_offset() - World.PAD_TOP

func _safe_limits() -> Vector2:
	var legs := rocket.has_legs and rocket.legs_deployed and rocket.leg_anim > 0.9
	return Vector2(7.0, deg_to_rad(14.0)) if legs else Vector2(2.5, deg_to_rad(6.0))

func _on_contact(info: Dictionary) -> void:
	if state != "flight":
		return
	var lim := _safe_limits()
	var spd: float = info.speed
	var tilt: float = info.tilt
	if info.water:
		if spd < 12.0 and target_reached:
			_finish_splash()
		else:
			_crash("Splashed into the sea at %.0f m/s." % spd)
		return
	if spd > lim.x:
		var why := "Hit the ground at %.1f m/s." % spd
		if spd < 7.0:
			why += "\nWithout legs deployed you must touch down below 2.5 m/s."
		_crash(why)
	elif tilt > lim.y:
		_crash("Touched down tilted %.0f° and tipped over." % rad_to_deg(tilt))
	else:
		touchdown_speed = spd
		settle_time = 0.0
		landed_note_shown = false
		hud.flash("Touchdown: %.1f m/s" % spd, 1.4, Color(0.6, 1.0, 0.7))

func _mission_logic(dt: float) -> void:
	var m: Dictionary = Parts.MISSIONS[mission_idx]
	var alt := _altitude()
	max_alt = maxf(max_alt, alt)
	if not target_reached and alt >= m.alt:
		target_reached = true
		sfx.chime()
		hud.flash("TARGET REACHED!\nNow come back and land.", 3.0, Color(0.55, 1.0, 0.65))
	if rocket.fuel <= 0.0 and not fuel_note_shown:
		fuel_note_shown = true
		hud.flash("OUT OF FUEL", 2.0, Color(1.0, 0.5, 0.35))
	# suicide-burn hint
	var agl := _agl()
	if rocket.vel.y < -15.0 and not rocket.on_ground:
		var a_max := rocket.max_thrust / rocket.mass() - 9.81
		var stop := INF if a_max <= 0.0 else rocket.vel.y * rocket.vel.y / (2.0 * a_max)
		burn_note_time -= dt
		if agl < stop * 1.25 + 30.0 and rocket.throttle < 0.6 and rocket.fuel > 0.0 and burn_note_time <= 0.0:
			burn_note_time = 2.0
			hud.flash("BURN NOW!", 1.0, Color(1.0, 0.4, 0.3))
		if agl < 600.0 and rocket.has_legs and not rocket.legs_deployed and burn_note_time <= 0.0:
			burn_note_time = 2.0
			hud.flash("Deploy legs! (G)", 1.2, Color(1.0, 0.85, 0.4))
	# tipping over on the ground
	if rocket.on_ground and absf(rocket.angle) > deg_to_rad(30.0):
		_crash("The rocket tipped over.")
		return
	# settled after landing
	if rocket.on_ground and rocket.has_flown:
		var weight := rocket.mass() * 9.81
		if rocket.vel.length() < 0.5 and rocket.thrust_now < weight * 0.9:
			settle_time += dt
		else:
			settle_time = 0.0
		if settle_time > 1.2:
			if target_reached:
				_finish_landing()
			elif not landed_note_shown:
				landed_note_shown = true
				hud.flash("Landed, but the target is %s.\nThrottle up and try again!" % Hud._fmt_alt(m.alt), 3.0, Color(1.0, 0.85, 0.4))

func _crash(reason: String) -> void:
	state = "over"
	var p := rocket.global_position
	rocket.explode()
	Fx.explosion(self, p, clampf(rocket.height / 10.0, 0.7, 2.0))
	sfx.boom()
	sfx.set_engine(0.0, 1.0)
	shake = 1.6
	_pending_result = {"success": false, "title": "RAPID UNSCHEDULED DISASSEMBLY", "body": reason + "\n\nMax altitude %s" % Hud._fmt_dist(max_alt), "stars": 0}
	over_timer = 2.4

func _finish_splash() -> void:
	state = "over"
	_pending_result = {"success": true, "title": "SPLASHDOWN", "body": "Target reached, but you landed in the ocean.\nThe recovery crew is not amused.\n\nMax altitude %s" % Hud._fmt_dist(max_alt), "stars": 1}
	_record(1)
	over_timer = 1.0

func _finish_landing() -> void:
	state = "over"
	rocket.throttle = 0.0
	var dist := absf(rocket.pos.x)
	var on_pad := dist < World.PAD_RADIUS - 1.0
	var fuel_pct := rocket.fuel / maxf(rocket.fuel_max, 0.001)
	var stars := 1
	if dist < 150.0 and touchdown_speed < 5.0:
		stars = 2
	if on_pad and touchdown_speed < 3.5:
		stars = 3
	var score := int(1000 * (mission_idx + 1) + (1500.0 if on_pad else maxf(0.0, 800.0 - dist * 2.0)) + fuel_pct * 800.0 + maxf(0.0, 7.0 - touchdown_speed) * 100.0)
	var where := "Bullseye! Landed on the pad." if on_pad else "Landed %s from the pad." % Hud._fmt_dist(dist)
	var body := "%s\nTouchdown %.1f m/s  ·  Fuel left %d%%\nMax altitude %s  ·  Flight time %d:%02d\n\nSCORE  %d" % [where, touchdown_speed, int(fuel_pct * 100.0), Hud._fmt_dist(max_alt), int(flight_time) / 60, int(flight_time) % 60, score]
	_pending_result = {"success": true, "title": "MISSION COMPLETE", "body": body, "stars": stars}
	_record(stars)
	sfx.chime()
	over_timer = 0.6

func _record(stars: int) -> void:
	var k := str(mission_idx)
	best[k] = maxi(int(best.get(k, 0)), stars)
	_save()

func _show_pending_result() -> void:
	var r := _pending_result
	hud.show_result(r.success, r.title, r.body, r.stars)

# --- per-frame visuals ----------------------------------------------------------

func _process(delta: float) -> void:
	rocket.update_visual(delta)
	var thr := rocket.thrust_now / maxf(rocket.max_thrust, 0.001)
	if state in ["countdown", "flight"]:
		sfx.set_engine(thr * (0.35 + 0.65 * rocket.pressure), 0.8 + thr * 0.35)
		_update_hud()
	else:
		sfx.set_engine(0.0, 1.0)
	var agl := _agl()
	shake = maxf(shake - delta * 1.2, thr * 0.18 * clampf(1.0 - agl / 300.0, 0.0, 1.0))
	var d := _update_camera(delta)
	world.update_env(maxf(cam.global_position.y, 0.0), d, delta)

func _update_hud() -> void:
	var m: Dictionary = Parts.MISSIONS[mission_idx]
	var lim := _safe_limits()
	var mission := "%s  ·  %s" % [m.name.to_upper(), ("LAND IT!" if target_reached else "reach " + Hud._fmt_alt(m.alt))]
	var status := "Assist %s  ·  Legs %s" % [SAS_NAMES[SAS_MODES[sas]], ("down" if rocket.legs_deployed else "up") if rocket.has_legs else "none"]
	if WARPS[warp_idx] > 1:
		status += "  ·  Warp %d×" % WARPS[warp_idx]
	status += "\nSafe touchdown < %.1f m/s" % lim.x
	hud.update_telemetry({
		"mission": mission,
		"alt": _altitude(),
		"agl": _agl(),
		"vs": rocket.vel.y,
		"hs": absf(rocket.vel.x),
		"pad": absf(rocket.pos.x),
		"twr": rocket.thrust_now / (rocket.mass() * 9.81),
		"fuel": rocket.fuel / maxf(rocket.fuel_max, 0.001),
		"throttle": rocket.throttle,
		"safe_v": lim.x,
		"status": status,
		"buttons": {
			"legs": ("LEGS UP" if rocket.legs_deployed else "LEGS DOWN") if rocket.has_legs else "NO LEGS",
			"sas": SAS_NAMES[SAS_MODES[sas]],
			"cam": "CHASE CAM" if cam_mode == 0 else "GROUND CAM",
			"warp": "WARP %d×" % WARPS[warp_idx],
			"menu": "BUILD",
		},
	})

func _update_camera(_delta: float) -> float:
	var target := rocket.global_position
	if rocket.dead:
		target = Vector3(rocket.pos.x, rocket.pos.y, 0)
	var shake_v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.25
	var d := 0.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	if cam_mode == 1 and state != "build":
		var gp := Vector3(-150.0, World.LAND_BASE + 1.8, 230.0)
		cam.global_position = gp
		cam.look_at(target + shake_v * 0.3, Vector3.UP)
		d = gp.distance_to(target)
		cam.fov = clampf(rad_to_deg(2.0 * atan(rocket.height * 1.7 / d)), 0.6, 55.0)
		cam.near = clampf(d * 0.01, 0.2, 30.0)
		return 120.0
	var base := rocket.height * 1.6 + 14.0
	if state == "build":
		base = rocket.height * 2.0 + 9.0
	elif state in ["flight", "countdown"]:
		base += minf(rocket.vel.length() * 0.04, 25.0)
	d = base * cam_zoom
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var p := target + dir * d
	var floor_h := maxf(world.grid_height(p.x, p.z), 0.0)
	if absf(p.x) < World.PAD_RADIUS + 2.0 and absf(p.z) < World.PAD_RADIUS + 2.0:
		floor_h = World.PAD_TOP
	p.y = maxf(p.y, floor_h + 1.5)
	cam.global_position = p + shake_v
	cam.look_at(target, Vector3.UP)
	cam.fov = 60.0
	cam.near = clampf(d * 0.02, 0.1, 5.0)
	if state == "build":
		if hud.is_landscape():
			cam.h_offset = -d * 0.32
		else:
			cam.v_offset = -d * 0.3
	return d

# --- persistence -------------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "best", best)
	cfg.set_value("game", "design", design)
	cfg.set_value("game", "mission", mission_idx)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best = cfg.get_value("game", "best", {})
	mission_idx = clampi(cfg.get_value("game", "mission", 0), 0, Parts.MISSIONS.size() - 1)
	var d = cfg.get_value("game", "design", null)
	if d is Dictionary and d.has_all(["nose", "tanks", "engine", "count", "fins", "legs"]) \
			and Parts.NOSES.has(d.nose) and Parts.ENGINES.has(d.engine):
		design = d
