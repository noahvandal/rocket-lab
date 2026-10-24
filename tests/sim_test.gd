extends SceneTree
## Headless autopilot: launches each early mission and tries a hoverslam landing.

func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	for mi in [0, 1]:
		main.mission_idx = mi
		main.launch()
		var dt := 1.0 / 60.0
		var target: float = Parts.MISSIONS[mi].alt
		var phase := 0
		for i in 60 * 400:
			var r: Rocket = main.rocket
			if main.state == "flight":
				var agl: float = main._agl()
				if phase == 0 and main._altitude() > target * 1.05:
					phase = 1
				var thr := 1.0
				if phase == 1:
					thr = 0.0
					if r.vel.y < 0:
						var amax := r.max_thrust / r.mass() - 9.81
						var stop := r.vel.y * r.vel.y / (2.0 * amax)
						if agl < stop * 1.1 + 5.0:
							phase = 2
				if phase == 2:
					var want := -clampf(agl * 0.25, 1.5, 60.0)
					var err := want - r.vel.y
					thr = clampf((9.81 + err * 2.0) * r.mass() / r.max_thrust, 0.0, 1.0)
				r.throttle = thr
				main.hud.touch.throttle_set = thr
			main._physics_process(dt)
			main._process(dt)
			if main.state == "over" and main.over_timer <= 0.0:
				break
		print("mission ", mi, " -> ", main._pending_result.get("title", "?"), " | ", str(main._pending_result.get("body", "")).replace("\n", " / "), " | max_alt ", int(main.max_alt), " fuel ", snappedf(main.rocket.fuel, 0.01))
		main.hud.touch.throttle_set = -1.0
	quit()
