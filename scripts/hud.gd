class_name Hud
extends Control
## All 2D UI: rocket builder, flight telemetry, touch controls and results.

const ACCENT := Color(1.0, 0.5, 0.18)
const TEXT := Color(0.92, 0.95, 1.0)
const DIM := Color(0.62, 0.68, 0.78)

var game

# builder
var build_panel: PanelContainer
var nose_btns := {}
var engine_btns := {}
var mission_btns: Array[Button] = []
var mission_stars: Array[Control] = []
var count_label: Label
var stack_label: Label
var fins_btn: Button
var legs_btn: Button
var stats_label: RichTextLabel
var mission_desc: Label

# flight
var flight_root: Control
var telem_panel: PanelContainer
var mission_label: Label
var values := {}
var fuel_bar: ProgressBar
var status_label: Label
var msg_label: Label
var hint_label: Label
var touch: TouchControls
var _msg_tween: Tween

# result
var result_panel: PanelContainer
var result_title: Label
var result_stars: Control
var result_body: Label
var next_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_builder()
	_build_flight()
	_build_result()
	resized.connect(_layout)
	_layout()

# --- theme -------------------------------------------------------------------

func _box(color: Color, radius := 10, margin := 8.0, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin * 1.4
	s.content_margin_right = margin * 1.4
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	return s

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.035, 0.05, 0.09, 0.82), 16, 14.0, Color(1, 1, 1, 0.09)))
	t.set_stylebox("normal", "Button", _box(Color(0.13, 0.17, 0.25, 0.95)))
	t.set_stylebox("hover", "Button", _box(Color(0.19, 0.25, 0.36, 0.95)))
	t.set_stylebox("pressed", "Button", _box(ACCENT))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT.lightened(0.1)))
	t.set_stylebox("disabled", "Button", _box(Color(0.1, 0.12, 0.16, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		t.set_color(c, "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color(0.08, 0.05, 0.02))
	t.set_color("font_hover_pressed_color", "Button", Color(0.08, 0.05, 0.02))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("background", "ProgressBar", _box(Color(0, 0, 0, 0.45), 5, 0.0))
	t.set_stylebox("fill", "ProgressBar", _box(ACCENT, 5, 0.0))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t

func _label(text: String, size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 38
	b.pressed.connect(cb)
	return b

func _row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	parent.add_child(h)
	return h

func _stars(size: Vector2) -> Control:
	var c := Control.new()
	c.custom_minimum_size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("n", 0)
	c.draw.connect(func():
		var n: int = c.get_meta("n")
		var r := minf(c.size.y * 0.5, c.size.x / 6.6)
		for i in 3:
			var center := Vector2(c.size.x * 0.5 + (i - 1) * r * 2.2, c.size.y * 0.5)
			var pts := PackedVector2Array()
			for k in 10:
				var a := -PI * 0.5 + k * PI / 5.0
				pts.append(center + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
			c.draw_colored_polygon(pts, Color(1.0, 0.78, 0.2) if i < n else Color(1, 1, 1, 0.14)))
	return c

# --- builder -----------------------------------------------------------------

func _section(parent: Control, text: String) -> void:
	var l := _label(text, 12, DIM)
	parent.add_child(l)

func _build_builder() -> void:
	build_panel = PanelContainer.new()
	add_child(build_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)

	var title := _label("ROCKET LAB", 30, ACCENT)
	v.add_child(title)
	v.add_child(_label("Build it. Launch it. Land it.", 14, DIM))

	_section(v, "NOSE")
	var r := _row(v)
	for id in ["capsule", "cone", "none"]:
		var b := _button(Parts.NOSES[id].name, game.set_nose.bind(id), true)
		r.add_child(b)
		nose_btns[id] = b

	_section(v, "FUEL TANKS  (top to bottom)")
	r = _row(v)
	for id in ["S", "M", "L"]:
		r.add_child(_button("+ " + Parts.TANKS[id].name, game.add_tank.bind(id)))
	r = _row(v)
	stack_label = _label("", 14, TEXT)
	stack_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_child(stack_label)
	var rm := _button("Remove", game.remove_tank)
	rm.size_flags_horizontal = Control.SIZE_SHRINK_END
	rm.custom_minimum_size.x = 90
	r.add_child(rm)

	_section(v, "ENGINE")
	r = _row(v)
	for id in ["sparrow", "falcon", "titan"]:
		var b := _button(Parts.ENGINES[id].name, game.set_engine.bind(id), true)
		r.add_child(b)
		engine_btns[id] = b
	r = _row(v)
	var cl := _label("Engines", 15, TEXT)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(cl)
	var minus := _button("-", game.change_count.bind(-1))
	minus.size_flags_horizontal = Control.SIZE_SHRINK_END
	minus.custom_minimum_size.x = 48
	r.add_child(minus)
	count_label = _label("1", 18)
	count_label.custom_minimum_size.x = 30
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(count_label)
	var plus := _button("+", game.change_count.bind(1))
	plus.size_flags_horizontal = Control.SIZE_SHRINK_END
	plus.custom_minimum_size.x = 48
	r.add_child(plus)

	_section(v, "EXTRAS")
	r = _row(v)
	fins_btn = _button("Fins", game.toggle_part.bind("fins"), true)
	legs_btn = _button("Landing Legs", game.toggle_part.bind("legs"), true)
	r.add_child(fins_btn)
	r.add_child(legs_btn)

	_section(v, "MISSION")
	for i in Parts.MISSIONS.size():
		var m: Dictionary = Parts.MISSIONS[i]
		var b := _button("%d. %s  ·  %s" % [i + 1, m.name, _fmt_alt(m.alt)], game.set_mission.bind(i), true)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var st := _stars(Vector2(66, 20))
		st.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		st.offset_left -= 8
		st.offset_right -= 8
		b.add_child(st)
		v.add_child(b)
		mission_btns.append(b)
		mission_stars.append(st)
	mission_desc = _label("", 14, DIM)
	mission_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(mission_desc)

	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	stats_label.add_theme_font_size_override("normal_font_size", 15)
	stats_label.add_theme_font_size_override("bold_font_size", 15)
	stats_label.custom_minimum_size.x = 200
	v.add_child(stats_label)

	var launch := _button("LAUNCH", game.launch)
	launch.custom_minimum_size.y = 56
	launch.add_theme_font_size_override("font_size", 24)
	launch.add_theme_stylebox_override("normal", _box(ACCENT))
	launch.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.15)))
	launch.add_theme_color_override("font_color", Color(0.1, 0.05, 0.0))
	launch.add_theme_color_override("font_hover_color", Color(0.1, 0.05, 0.0))
	v.add_child(launch)
	var tip := _label("Drag to orbit the camera · scroll to zoom", 12, DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)

func refresh_build() -> void:
	var d: Dictionary = game.design
	for id in nose_btns:
		nose_btns[id].set_pressed_no_signal(id == d.nose)
	for id in engine_btns:
		engine_btns[id].set_pressed_no_signal(id == d.engine)
	fins_btn.set_pressed_no_signal(d.fins)
	legs_btn.set_pressed_no_signal(d.legs)
	count_label.text = str(d.count)
	var names: Array[String] = []
	for t in d.tanks:
		names.append(Parts.TANKS[t].name)
	stack_label.text = "Stack: " + (", ".join(names) if names.size() > 0 else "(empty)")
	for i in mission_btns.size():
		mission_btns[i].set_pressed_no_signal(i == game.mission_idx)
		mission_stars[i].set_meta("n", int(game.best.get(str(i), 0)))
		mission_stars[i].queue_redraw()
	mission_desc.text = Parts.MISSIONS[game.mission_idx].desc

	var s := Parts.stats(d)
	var twr: float = s.twr
	var twr_col := "#ff6b5a" if twr < 1.0 else ("#ffd25a" if twr < 1.3 else "#7dff9a")
	var dv: float = s.dv
	var need := _dv_needed(Parts.MISSIONS[game.mission_idx].alt)
	var dv_col := "#7dff9a" if dv >= need else ("#ffd25a" if dv >= need * 0.8 else "#ff6b5a")
	var txt := "[table=2]"
	txt += _stat_row("Height", "%.1f m" % s.height)
	txt += _stat_row("Mass", "%.1f t  (%.1f t fuel)" % [s.wet, s.fuel])
	txt += _stat_row("Thrust", "%d kN" % int(s.thrust))
	txt += _stat_row("Thrust/Weight", "[color=%s]%.2f[/color]" % [twr_col, twr])
	txt += _stat_row("Delta-v", "[color=%s]%d m/s[/color]" % [dv_col, int(dv)])
	txt += _stat_row("Mission needs", "~%d m/s" % int(need))
	txt += "[/table]"
	if s.fuel <= 0.0:
		txt += "\n[color=#ff6b5a]Add a fuel tank![/color]"
	elif twr < 1.0:
		txt += "\n[color=#ff6b5a]Too heavy to lift off. Add engines or remove tanks.[/color]"
	elif not d.legs:
		txt += "\n[color=#ffd25a]No legs: you must touch down under 2.5 m/s.[/color]"
	stats_label.text = txt

func _stat_row(k: String, v: String) -> String:
	return "[cell][color=#9aa6b8]%s[/color]   [/cell][cell]%s[/cell]" % [k, v]

## Rough delta-v estimate to go up to an altitude and land again (gravity + drag losses).
func _dv_needed(alt: float) -> float:
	return 2.0 * sqrt(2.0 * 9.81 * alt) * 1.18 + 120.0

static func _fmt_alt(a: float) -> String:
	return "%.0f m" % a if a < 1000.0 else "%s km" % str(snappedf(a / 1000.0, 0.1))

# --- flight ------------------------------------------------------------------

func _build_flight() -> void:
	flight_root = Control.new()
	flight_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flight_root)

	touch = TouchControls.new()
	flight_root.add_child(touch)
	touch.action.connect(func(id): game.on_action(id))

	telem_panel = PanelContainer.new()
	telem_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_root.add_child(telem_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	telem_panel.add_child(v)
	mission_label = _label("", 14, ACCENT)
	v.add_child(mission_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)
	for k in ["ALT", "VERT", "HORIZ", "PAD", "TWR"]:
		grid.add_child(_label(k, 13, DIM))
		var val := _label("-", 17)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size.x = 104
		grid.add_child(val)
		values[k] = val
	var fr := _row(v)
	fr.add_child(_label("FUEL", 13, DIM))
	fuel_bar = ProgressBar.new()
	fuel_bar.show_percentage = false
	fuel_bar.custom_minimum_size = Vector2(110, 12)
	fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fuel_bar.max_value = 1.0
	fr.add_child(fuel_bar)
	status_label = _label("", 13, DIM)
	v.add_child(status_label)

	msg_label = _label("", 34)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	msg_label.add_theme_constant_override("outline_size", 10)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_root.add_child(msg_label)

	hint_label = _label("W/S throttle   A/D steer   Z full   X cut   G legs   Q assist   C camera   T warp   R retry", 12, Color(1, 1, 1, 0.55))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.visible = not DisplayServer.is_touchscreen_available()
	flight_root.add_child(hint_label)

func update_telemetry(t: Dictionary) -> void:
	mission_label.text = t.mission
	values.ALT.text = _fmt_dist(t.alt)
	values.VERT.text = "%+.1f m/s" % t.vs
	values.HORIZ.text = "%.1f m/s" % t.hs
	values.PAD.text = _fmt_dist(t.pad)
	values.TWR.text = "%.2f" % t.twr
	values.VERT.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if t.vs < -t.safe_v and t.agl < 400.0 else TEXT)
	fuel_bar.value = t.fuel
	status_label.text = t.status
	touch.throttle_display = t.throttle
	touch.labels = t.buttons
	touch.queue_redraw()

static func _fmt_dist(m: float) -> String:
	if absf(m) < 1000.0:
		return "%.0f m" % m
	return "%.2f km" % (m / 1000.0)

func flash(text: String, secs := 2.5, color := TEXT) -> void:
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", color)
	msg_label.modulate.a = 1.0
	if _msg_tween:
		_msg_tween.kill()
	_msg_tween = create_tween()
	_msg_tween.tween_interval(secs)
	_msg_tween.tween_property(msg_label, "modulate:a", 0.0, 0.6)

# --- result ------------------------------------------------------------------

func _build_result() -> void:
	result_panel = PanelContainer.new()
	add_child(result_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	result_panel.add_child(v)
	result_title = _label("", 30, ACCENT)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_title)
	result_stars = _stars(Vector2(200, 54))
	result_stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(result_stars)
	result_body = _label("", 16)
	result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(result_body)
	var r := _row(v)
	r.add_child(_button("Retry", game.retry))
	r.add_child(_button("Edit Rocket", game.back_to_build))
	next_btn = _button("Next Mission", game.next_mission)
	r.add_child(next_btn)

func show_result(success: bool, title: String, body: String, stars: int) -> void:
	result_title.text = title
	result_title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if success else Color(1.0, 0.45, 0.35))
	result_stars.set_meta("n", stars)
	result_stars.visible = success
	result_stars.queue_redraw()
	result_body.text = body
	next_btn.visible = success and game.mission_idx < Parts.MISSIONS.size() - 1
	result_panel.visible = true
	telem_panel.visible = false
	hint_label.visible = false
	touch.visible = false
	touch.release_all()
	_layout()
	_fit_result.call_deferred()

# --- modes & layout ------------------------------------------------------------

func show_build() -> void:
	build_panel.visible = true
	flight_root.visible = false
	result_panel.visible = false
	touch.release_all()
	refresh_build()
	_layout()

func show_flight() -> void:
	build_panel.visible = false
	flight_root.visible = true
	touch.visible = true
	telem_panel.visible = true
	hint_label.visible = not DisplayServer.is_touchscreen_available()
	result_panel.visible = false
	msg_label.text = ""
	_layout()

func is_landscape() -> bool:
	return size.x >= size.y

func _layout() -> void:
	if not build_panel:
		return
	if is_landscape():
		build_panel.position = Vector2(14, 14)
		build_panel.size = Vector2(minf(380.0, size.x * 0.45), size.y - 28)
	else:
		build_panel.position = Vector2(10, size.y * 0.46)
		build_panel.size = Vector2(size.x - 20, size.y * 0.54 - 10)
	telem_panel.position = Vector2(10, 10)
	telem_panel.size = Vector2.ZERO
	telem_panel.scale = Vector2.ONE * clampf((size.x - 130.0) / 300.0, 0.68, 1.0)
	msg_label.position = Vector2(size.x * 0.1, size.y * (0.24 if is_landscape() else 0.4))
	msg_label.size = Vector2(size.x * 0.8, 120)
	hint_label.position = Vector2(0, size.y - 26)
	hint_label.size = Vector2(size.x, 20)
	_fit_result()

func _fit_result() -> void:
	var rw := minf(460.0, size.x - 24.0)
	result_panel.size = Vector2(rw, 0)
	result_panel.position = Vector2((size.x - rw) * 0.5, maxf(size.y * 0.5 - result_panel.size.y * 0.5, 12.0))
