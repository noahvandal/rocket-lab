extends SceneTree
## Screenshots of a landing, the result screen, and a phone-portrait layout.

var out := "/private/tmp/claude-501/-Users-noahvandal-Documents-Personal-ClaudeVideos/21d3ffe0-69d3-493d-afd4-df895b2f3412/scratchpad/"

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 10: await process_frame
	main.design = Parts.default_design()
	main.mission_idx = 0
	main._rebuild()
	main.launch()
	var phase := 0
	var shot_taken := false
	for i in 60 * 120:
		await process_frame
		var r: Rocket = main.rocket
		if main.state == "flight":
			var agl: float = main._agl()
			if phase == 0 and main._altitude() > 330.0:
				phase = 1
			var thr := 1.0
			if phase == 1:
				thr = 0.0
				if r.vel.y < 0:
					var amax := r.max_thrust / r.mass() - 9.81
					if agl < r.vel.y * r.vel.y / (2.0 * amax) * 1.1 + 5.0:
						phase = 2
			if phase == 2:
				var err := -clampf(agl * 0.25, 1.5, 60.0) - r.vel.y
				thr = clampf((9.81 + err * 2.0) * r.mass() / r.max_thrust, 0.0, 1.0)
				if agl < 14.0 and not shot_taken:
					shot_taken = true
					await _shot("6_landing")
			main.hud.touch.throttle_set = thr
		if main.state == "over" and main.over_timer <= 0.0:
			break
	main.hud.touch.throttle_set = -1.0
	for i in 20: await process_frame
	await _shot("7_result")
	main.back_to_build()
	DisplayServer.window_set_size(Vector2i(600, 1100))
	for i in 20: await process_frame
	await _shot("8_portrait_build")
	main.launch()
	for i in 60 * 4: await process_frame
	await _shot("9_portrait_flight")
	quit()
