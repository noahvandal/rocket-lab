extends SceneTree
func _initialize() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 5: await process_frame
	print("root size ", root.size, " csf ", root.content_scale_factor, " visible ", root.get_visible_rect())
	print("hud size ", main.hud.size, " anchors ", main.hud.anchor_right, " touch ", main.hud.touch.size, " panel ", main.hud.build_panel.size)
	quit()
