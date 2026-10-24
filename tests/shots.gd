extends SceneTree
## Renders screenshots of the builder and flight for visual checks.

var out := "/private/tmp/claude-501/-Users-noahvandal-Documents-Personal-ClaudeVideos/21d3ffe0-69d3-493d-afd4-df895b2f3412/scratchpad/"

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + name + ".png")

func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 30: await process_frame
	await _shot("1_build")
	main.design = {"nose": "cone", "tanks": ["L", "M"], "engine": "titan", "count": 1, "fins": true, "legs": true}
	main._rebuild()
	for i in 10: await process_frame
	await _shot("2_build_big")
	main.mission_idx = 4
	main.launch()
	for i in 60 * 5: await process_frame
	await _shot("3_liftoff")
	for i in 60 * 6: await process_frame
	main.cam_mode = 1
	await _shot("4_groundcam")
	main.cam_mode = 0
	main.cam_zoom = 2.5
	main.warp_idx = 2
	for i in 60 * 14: await process_frame
	await _shot("5_high")
	quit()
