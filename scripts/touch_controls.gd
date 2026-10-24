class_name TouchControls
extends Control
## Multi-touch flight controls (steer pads, throttle bar, action buttons). Also works with a mouse.

signal action(id: String)

const MOUSE_ID := 1000

var steer := 0.0
var throttle_set := -1.0
var throttle_display := 0.0
var labels := {}
var _touches := {}
var _emu_capture := false
var _k := 1.0
var _pad_l := Vector2.ZERO
var _pad_r := Vector2.ZERO
var _pad_rad := 44.0
var _thr_rect := Rect2()
var _buttons: Array = []   # [{id, rect}]
var _ids := ["legs", "sas", "cam", "warp", "menu"]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	_k = clampf(minf(size.x, size.y) / 420.0, 0.8, 1.5)
	_pad_rad = 46.0 * _k
	var by := size.y - 72.0 * _k
	_pad_l = Vector2(70.0 * _k, by)
	_pad_r = Vector2(178.0 * _k, by)
	var bw := 104.0 * _k
	var bh := 38.0 * _k
	var tw := 54.0 * _k
	var th := minf(260.0 * _k, size.y * 0.5)
	_thr_rect = Rect2(size.x - bw - tw - 30.0 * _k, size.y - th - 26.0 * _k, tw, th)
	if size.y > size.x:
		# portrait: buttons stack above the throttle, which sits in the corner
		_thr_rect.position.x = size.x - tw - 22.0 * _k
		th = minf(th, size.y - (12.0 + 5.0 * 46.0 + 70.0) * _k)
		_thr_rect = Rect2(_thr_rect.position.x, size.y - th - 26.0 * _k, tw, th)
	_buttons.clear()
	for i in _ids.size():
		_buttons.append({"id": _ids[i], "rect": Rect2(size.x - bw - 12.0 * _k, 12.0 * _k + i * (bh + 8.0 * _k), bw, bh)})
	queue_redraw()

func _zone_at(p: Vector2) -> String:
	for b in _buttons:
		if b.rect.grow(4.0).has_point(p):
			return "btn:" + b.id
	if _thr_rect.grow(18.0 * _k).has_point(p):
		return "thr"
	if p.distance_to(_pad_l) < _pad_rad * 1.25:
		return "left"
	if p.distance_to(_pad_r) < _pad_rad * 1.25:
		return "right"
	return ""

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var e = make_input_local(event)
	if e is InputEventScreenTouch:
		if e.pressed:
			var z := _zone_at(e.position)
			if z != "":
				_touches[e.index] = z
				_press(z, e.position)
				get_viewport().set_input_as_handled()
		elif _touches.has(e.index):
			var z: String = _touches[e.index]
			_touches.erase(e.index)
			_release(z)
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag:
		if _touches.has(e.index):
			_touches[e.index] = _drag(_touches[e.index], e.position)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.device == InputEvent.DEVICE_ID_EMULATION:
			# Mouse events synthesized from touches: the touch handler already acted on them.
			if e.pressed and _zone_at(e.position) != "":
				_emu_capture = true
				get_viewport().set_input_as_handled()
			elif not e.pressed and _emu_capture:
				_emu_capture = false
				get_viewport().set_input_as_handled()
			return
		if e.pressed:
			var z := _zone_at(e.position)
			if z != "":
				_touches[MOUSE_ID] = z
				_press(z, e.position)
				get_viewport().set_input_as_handled()
		elif _touches.has(MOUSE_ID):
			var z: String = _touches[MOUSE_ID]
			_touches.erase(MOUSE_ID)
			_release(z)
			get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if e.device == InputEvent.DEVICE_ID_EMULATION:
			if _emu_capture:
				get_viewport().set_input_as_handled()
		elif _touches.has(MOUSE_ID):
			_touches[MOUSE_ID] = _drag(_touches[MOUSE_ID], e.position)
			get_viewport().set_input_as_handled()

func _press(z: String, p: Vector2) -> void:
	if z.begins_with("btn:"):
		action.emit(z.substr(4))
	elif z == "thr":
		_set_thr(p)
	_update_steer()
	queue_redraw()

func _drag(z: String, p: Vector2) -> String:
	if z == "thr":
		_set_thr(p)
	elif z == "left" or z == "right":
		z = "left" if p.distance_to(_pad_l) < p.distance_to(_pad_r) else "right"
	_update_steer()
	queue_redraw()
	return z

func _release(z: String) -> void:
	if z == "thr":
		throttle_set = -1.0
	_update_steer()
	queue_redraw()

func _set_thr(p: Vector2) -> void:
	throttle_set = clampf(1.0 - (p.y - _thr_rect.position.y) / _thr_rect.size.y, 0.0, 1.0)
	if throttle_set < 0.04:
		throttle_set = 0.0

func _update_steer() -> void:
	steer = 0.0
	for z in _touches.values():
		if z == "left":
			steer += 1.0
		elif z == "right":
			steer -= 1.0

func release_all() -> void:
	_touches.clear()
	steer = 0.0
	throttle_set = -1.0
	_emu_capture = false

func _held(z: String) -> bool:
	return z in _touches.values()

func _draw() -> void:
	var font := get_theme_default_font()
	var fs := int(15.0 * _k)
	# steer pads
	for side in [["left", _pad_l, -1.0], ["right", _pad_r, 1.0]]:
		var c: Vector2 = side[1]
		var held := _held(side[0])
		draw_circle(c, _pad_rad, Color(1, 1, 1, 0.22 if held else 0.09))
		draw_arc(c, _pad_rad, 0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * _k, true)
		var d: float = side[2]
		var s := _pad_rad * 0.42
		draw_colored_polygon(PackedVector2Array([c + Vector2(d * s, 0), c + Vector2(-d * s * 0.6, -s), c + Vector2(-d * s * 0.6, s)]), Color(1, 1, 1, 0.85 if held else 0.6))
	# throttle
	var r := _thr_rect
	draw_rect(r, Color(0, 0, 0, 0.35))
	var fill := r.size.y * throttle_display
	draw_rect(Rect2(r.position.x, r.end.y - fill, r.size.x, fill), Color(1.0, 0.5, 0.15, 0.85))
	draw_rect(r, Color(1, 1, 1, 0.45), false, 2.0 * _k)
	for i in range(1, 4):
		var yy := r.position.y + r.size.y * i / 4.0
		draw_line(Vector2(r.position.x, yy), Vector2(r.position.x + r.size.x * 0.3, yy), Color(1, 1, 1, 0.4), 1.0)
	draw_string(font, Vector2(r.position.x - 20.0 * _k, r.position.y - 8.0 * _k), "THR %d%%" % int(round(throttle_display * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0 * _k, fs)
	# buttons
	for b in _buttons:
		var rect: Rect2 = b.rect
		var held := _held("btn:" + b.id)
		draw_rect(rect, Color(0.1, 0.14, 0.22, 0.85) if not held else Color(1.0, 0.45, 0.15, 0.9))
		draw_rect(rect, Color(1, 1, 1, 0.18), false, 1.0)
		var txt: String = labels.get(b.id, b.id.to_upper())
		var ty := rect.position.y + rect.size.y * 0.5 + fs * 0.36
		draw_string(font, Vector2(rect.position.x, ty), txt, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs)
