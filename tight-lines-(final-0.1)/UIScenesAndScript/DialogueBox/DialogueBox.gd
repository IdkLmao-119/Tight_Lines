extends CanvasLayer

# Pokemon-style text box + story HUD overlays (objective, tutorial, banner, credits).
# Owned by StoryManager (it instances this scene).

signal choice_selected(index: int)

const CHARS_PER_SECOND := 45.0
const BLIP_CHAR_INTERVAL := 2

@onready var _box: PanelContainer = %Box
@onready var _name_label: Label = %NameLabel
@onready var _portrait: TextureRect = %Portrait
@onready var _text_label: RichTextLabel = %TextLabel
@onready var _arrow: Control = %NextArrow
@onready var _choices: VBoxContainer = %Choices
@onready var _skip_button: Button = %SkipButton

@onready var _objective_panel: PanelContainer = %ObjectivePanel
@onready var _objective_label: Label = %ObjectiveLabel
@onready var _tutorial_toast: PanelContainer = %TutorialToast
@onready var _tutorial_label: Label = %TutorialLabel
@onready var _banner_panel: PanelContainer = %BannerPanel
@onready var _banner_label: Label = %BannerLabel
@onready var _credits_overlay: PanelContainer = %CreditsOverlay
@onready var _keep_fishing_button: Button = %KeepFishingButton

var _typing := false
var _shown := 0.0
var _last_blip_char := 0
var _is_parchment := false
var _arrow_phase := 0.0
var _arrow_base_y := 0.0

var _options := PackedStringArray()
var _pending_choices := PackedStringArray()
var _choice_index := -1
var _current_objective := ""

var _box_tween: Tween
var _tutorial_tween: Tween
var _banner_tween: Tween

var _blip_player: AudioStreamPlayer
var _blip_playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	# Layer 40 sits over GameHUD buttons (1/30) and under GameHUD Overlays (50).
	layer = 40
	_objective_label.text = ""
	_objective_panel.hide()
	_hide_all()
	_setup_blip_audio()

	var right_col := _arrow.get_parent() as Container
	if right_col != null:
		right_col.sort_children.connect(func() -> void:
			_arrow_base_y = _arrow.position.y
		)
	_arrow_base_y = _arrow.position.y

	_box.gui_input.connect(_on_box_gui_input)
	_skip_button.pressed.connect(StoryManager.skip)
	_keep_fishing_button.pressed.connect(_on_keep_fishing_pressed)

	StoryManager.line_shown.connect(_on_line_shown)
	StoryManager.choices_shown.connect(_on_choices_shown)
	StoryManager.dialogue_hidden.connect(_hide_all)
	StoryManager.box_style_changed.connect(_on_box_style_changed)
	StoryManager.command_emitted.connect(_on_command_emitted)
	StoryManager.notice_requested.connect(_show_tutorial)
	StoryManager.jeep_reached.connect(_on_jeep_reached)

	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("scene_changed"):
		gm.connect("scene_changed", _on_scene_changed)

	var im := get_node_or_null("/root/InputManager")
	if im != null:
		im.connect("interact_pressed", _on_interact)
		im.connect("menu_action", _on_menu_action)


func _exit_tree() -> void:
	if StoryManager != null:
		if StoryManager.line_shown.is_connected(_on_line_shown):
			StoryManager.line_shown.disconnect(_on_line_shown)
		if StoryManager.choices_shown.is_connected(_on_choices_shown):
			StoryManager.choices_shown.disconnect(_on_choices_shown)
		if StoryManager.dialogue_hidden.is_connected(_hide_all):
			StoryManager.dialogue_hidden.disconnect(_hide_all)
		if StoryManager.box_style_changed.is_connected(_on_box_style_changed):
			StoryManager.box_style_changed.disconnect(_on_box_style_changed)
		if StoryManager.command_emitted.is_connected(_on_command_emitted):
			StoryManager.command_emitted.disconnect(_on_command_emitted)
		if StoryManager.notice_requested.is_connected(_show_tutorial):
			StoryManager.notice_requested.disconnect(_show_tutorial)
		if StoryManager.jeep_reached.is_connected(_on_jeep_reached):
			StoryManager.jeep_reached.disconnect(_on_jeep_reached)
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.has_signal("scene_changed") and gm.is_connected("scene_changed", _on_scene_changed):
		gm.disconnect("scene_changed", _on_scene_changed)
	var im := get_node_or_null("/root/InputManager")
	if im != null:
		if im.has_signal("interact_pressed") and im.is_connected("interact_pressed", _on_interact):
			im.disconnect("interact_pressed", _on_interact)
		if im.has_signal("menu_action") and im.is_connected("menu_action", _on_menu_action):
			im.disconnect("menu_action", _on_menu_action)


func _process(delta: float) -> void:
	if _arrow.visible:
		_arrow_phase += delta * 6.0
		_arrow.position.y = _arrow_base_y + sin(_arrow_phase) * 3.0

	if not _typing:
		return
	_shown += CHARS_PER_SECOND * delta
	var chars := int(_shown)
	_text_label.visible_characters = chars
	if chars >= _last_blip_char + BLIP_CHAR_INTERVAL:
		_last_blip_char = chars
		_play_blip()
	if _text_label.visible_characters >= _text_label.get_total_character_count():
		_finish_typing()


func _unhandled_input(event: InputEvent) -> void:
	if not StoryManager.is_playing() or event.is_echo():
		return
	if _pressed(event, "tl_interact") or _pressed(event, "ui_accept"):
		_press()
	elif _choice_index >= 0 and _pressed(event, "ui_up"):
		_move_choice(-1)
	elif _choice_index >= 0 and _pressed(event, "ui_down"):
		_move_choice(1)
	else:
		return
	get_viewport().set_input_as_handled()


func _on_box_gui_input(event: InputEvent) -> void:
	if not StoryManager.is_playing():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_press()
		get_viewport().set_input_as_handled()


func _on_interact(_player_id: int) -> void:
	if StoryManager.is_playing():
		_press()


func _on_menu_action(_player_id: int, action: String) -> void:
	if not StoryManager.is_playing():
		return
	match action:
		"up":
			_move_choice(-1)
		"down":
			_move_choice(1)
		"select", "confirm", "accept":
			_press()


func _press() -> void:
	if _typing:
		_finish_typing()
	elif _choice_index >= 0:
		var picked := _choice_index
		_close_choices()
		choice_selected.emit(picked)
		StoryManager.choose(picked)
	elif _box.visible:
		StoryManager.advance()


func _on_line_shown(speaker: String, text: String, portrait: Texture2D) -> void:
	_close_choices()
	var was_hidden := not _box.visible
	_box.show()
	if was_hidden:
		_animate_box_in()
	_arrow.hide()
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_text_label.text = text
	_text_label.visible_characters = 0
	_shown = 0.0
	_last_blip_char = 0
	_typing = true


func _on_choices_shown(options: PackedStringArray) -> void:
	if _typing:
		_pending_choices = options
	else:
		_open_choices(options)


func _on_box_style_changed(style: String) -> void:
	_is_parchment = style == "parchment"
	_box.self_modulate = Color(0.95, 0.88, 0.72, 1.0) if _is_parchment else Color.WHITE


func _on_command_emitted(command: String, args: PackedStringArray) -> void:
	var text := " ".join(args)
	match command:
		"objective":
			set_objective(text)
		"tutorial":
			show_tutorial(text)
		"banner":
			set_objective(text)
			_show_banner(text)
		"open_ui":
			if args.size() > 0 and args[0] == "credits":
				_show_credits()


func _on_scene_changed(scene_id: String) -> void:
	var show_obj := scene_id.begins_with("overworld_") and _objective_label.text != ""
	_objective_panel.visible = show_obj


func set_objective(text: String) -> void:
	_show_objective(text)


func get_objective() -> String:
	return _current_objective


func complete_objective(filter: String = "") -> bool:
	if _current_objective == "":
		return false
	if filter != "" and not _current_objective.to_lower().contains(filter.to_lower()):
		return false
	var done := _current_objective
	_show_objective("")
	_show_tutorial("Objective Complete: " + done)
	return true


func show_tutorial(text: String) -> void:
	_show_tutorial(text)


func _on_jeep_reached() -> void:
	complete_objective("jeep")


func _show_objective(text: String) -> void:
	_current_objective = text
	if text == "":
		_objective_label.text = ""
		_objective_panel.hide()
		return
	_objective_label.text = "Objective: " + text
	_objective_panel.show()


func _show_tutorial(text: String) -> void:
	if text == "":
		return
	if _tutorial_tween != null and _tutorial_tween.is_valid():
		_tutorial_tween.kill()
	_tutorial_label.text = text
	_tutorial_toast.modulate.a = 0.0
	_tutorial_toast.show()
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial_toast, "modulate:a", 1.0, 0.25)
	_tutorial_tween.tween_interval(4.2)
	_tutorial_tween.tween_property(_tutorial_toast, "modulate:a", 0.0, 0.5)
	_tutorial_tween.tween_callback(_tutorial_toast.hide)


func _show_banner(text: String) -> void:
	if text == "":
		return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_label.text = text
	_banner_panel.modulate.a = 0.0
	_banner_panel.show()
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_panel, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(2.4)
	_banner_tween.tween_property(_banner_panel, "modulate:a", 0.0, 0.5)
	_banner_tween.tween_callback(_banner_panel.hide)


func _show_credits() -> void:
	_credits_overlay.modulate.a = 0.0
	_credits_overlay.show()
	var t := create_tween()
	t.tween_property(_credits_overlay, "modulate:a", 1.0, 0.8)


func _on_keep_fishing_pressed() -> void:
	_credits_overlay.hide()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.call("change_scene", "overworld_spawn")


func _animate_box_in() -> void:
	if _box_tween != null and _box_tween.is_valid():
		_box_tween.kill()
	_box.modulate.a = 0.0
	_box_tween = create_tween()
	_box_tween.tween_property(_box, "modulate:a", 1.0, 0.16)


func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	if _pending_choices.is_empty():
		_arrow_phase = 0.0
		_arrow.show()
	else:
		_open_choices(_pending_choices)
		_pending_choices = PackedStringArray()


func _open_choices(options: PackedStringArray) -> void:
	_close_choices()
	if options.is_empty():
		return
	_options = options
	for i in options.size():
		var text := options[i]
		var label := Label.new()
		label.text = text
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.add_theme_font_size_override(&"font_size", 18)
		var choice_idx := i
		label.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_choice_index = choice_idx
				_close_choices()
				choice_selected.emit(choice_idx)
				StoryManager.choose(choice_idx)
				get_viewport().set_input_as_handled()
		)
		_choices.add_child(label)
	_choice_index = 0
	_choices.show()
	_arrow.hide()
	_refresh_choices()


func _close_choices() -> void:
	for child in _choices.get_children():
		_choices.remove_child(child)
		child.queue_free()
	_choices.hide()
	_options = PackedStringArray()
	_choice_index = -1


func _move_choice(step: int) -> void:
	if _choice_index < 0:
		return
	_choice_index = wrapi(_choice_index + step, 0, _options.size())
	_refresh_choices()


func _refresh_choices() -> void:
	for i in _choices.get_child_count():
		var label := _choices.get_child(i) as Label
		label.text = ("▶ " if i == _choice_index else "   ") + _options[i]
		label.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.55, 1.0) if i == _choice_index else Color(0.86, 0.9, 0.96, 0.9))


func _hide_all() -> void:
	_typing = false
	_pending_choices = PackedStringArray()
	_close_choices()
	_box.hide()


func _setup_blip_audio() -> void:
	_blip_player = AudioStreamPlayer.new()
	_blip_player.bus = "SFX"
	_blip_player.volume_db = -14.0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050.0
	gen.buffer_length = 0.08
	_blip_player.stream = gen
	add_child(_blip_player)
	_blip_player.play()
	_blip_playback = _blip_player.get_stream_playback() as AudioStreamGeneratorPlayback


func _play_blip() -> void:
	if _blip_playback == null:
		return
	var frames := _blip_playback.get_frames_available()
	var needed := mini(frames, 520)
	if needed <= 0:
		return
	var freq := 340.0 if _is_parchment else 560.0 + randf_range(-30.0, 40.0)
	var step := freq / 22050.0
	for i in needed:
		var env := 1.0 - float(i) / float(needed)
		var sample := sin(float(i) * step * TAU) * 0.25 * env
		_blip_playback.push_frame(Vector2(sample, sample))


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)
