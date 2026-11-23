class_name TideIndicator
extends HBoxContainer

const UI_FONT: FontFile = preload("res://Assets/2D/ShortStack-Regular.ttf")

const COLOR_WAVE := Color(0.45, 0.82, 0.98, 1.0)
const COLOR_RISING := Color(0.45, 0.96, 0.72, 1.0)
const COLOR_FALLING := Color(1.0, 0.80, 0.36, 1.0)
const COLOR_SLACK := Color(0.76, 0.84, 0.92, 1.0)


class _WaveArrowIcon extends Control:
	var state: String = "rising"

	func _init() -> void:
		custom_minimum_size = Vector2(28, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# Smooth wave curve on the left (x: 2..16)
		var wave_pts := PackedVector2Array([
			Vector2(2.0, 13.0),
			Vector2(5.5, 8.0),
			Vector2(9.0, 11.5),
			Vector2(12.5, 15.0),
			Vector2(16.0, 10.0),
		])
		draw_polyline(wave_pts, COLOR_WAVE, 2.2, true)

		# Direction indicator on the right (x ~ 22)
		match state:
			"rising":
				draw_line(Vector2(22.0, 17.0), Vector2(22.0, 7.0), COLOR_RISING, 2.2, true)
				draw_colored_polygon(PackedVector2Array([
					Vector2(22.0, 4.0),
					Vector2(18.0, 9.5),
					Vector2(26.0, 9.5),
				]), COLOR_RISING)
			"falling":
				draw_line(Vector2(22.0, 5.0), Vector2(22.0, 15.0), COLOR_FALLING, 2.2, true)
				draw_colored_polygon(PackedVector2Array([
					Vector2(22.0, 18.0),
					Vector2(18.0, 12.5),
					Vector2(26.0, 12.5),
				]), COLOR_FALLING)
			_:
				draw_line(Vector2(18.5, 11.0), Vector2(26.5, 11.0), COLOR_SLACK, 2.4, true)


var tide_state: String = ""
var _icon: _WaveArrowIcon = null
var _label: Label = null


func _init() -> void:
	name = "TideIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 5)

	_icon = _WaveArrowIcon.new()
	add_child(_icon)

	_label = Label.new()
	_label.name = "TideLabel"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UI_FONT)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.05, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)


func set_tide(tide_info: Dictionary) -> void:
	var new_state := String(tide_info.get("state", "rising"))
	var label_txt := String(tide_info.get("label", "Rising"))
	var mult := float(tide_info.get("multiplier", 1.0))
	tooltip_text = "%s Tide (%.2fx)" % [label_txt, mult]
	if _label != null:
		_label.text = label_txt
		var col := COLOR_SLACK
		if new_state == "rising":
			col = COLOR_RISING
		elif new_state == "falling":
			col = COLOR_FALLING
		_label.add_theme_color_override("font_color", col)
	if new_state != tide_state:
		tide_state = new_state
		if _icon != null:
			_icon.state = new_state
			_icon.queue_redraw()


func get_display_text() -> String:
	return _label.text if _label != null else ""
