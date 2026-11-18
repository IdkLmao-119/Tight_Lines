extends CanvasLayer

# Pokemon-style text box. Owned by StoryManager (it instances this scene).
# Press while typing = finish the text. Press after = next box.

const CHARS_PER_SECOND := 45.0

@onready var _box: PanelContainer = %Box
@onready var _name_label: Label = %NameLabel
@onready var _portrait: TextureRect = %Portrait
@onready var _text_label: RichTextLabel = %TextLabel
@onready var _arrow: Control = %NextArrow
@onready var _choices: VBoxContainer = %Choices

var _typing := false
var _shown := 0.0
var _options := PackedStringArray()
var _pending_choices := PackedStringArray()
var _choice_index := -1                 # -1 = no choice menu open


func _ready() -> void:
	layer = 50
	_hide_all()
	StoryManager.line_shown.connect(_on_line_shown)
	StoryManager.choices_shown.connect(_on_choices_shown)
	StoryManager.dialogue_hidden.connect(_hide_all)
	StoryManager.box_style_changed.connect(_on_box_style_changed)
	var im := get_node_or_null("/root/InputManager")
	if im != null:
		im.connect("interact_pressed", _on_interact)
		im.connect("menu_action", _on_menu_action)


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += CHARS_PER_SECOND * delta
	_text_label.visible_characters = int(_shown)
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
		StoryManager.choose(picked)
	elif _box.visible:
		StoryManager.advance()


func _on_line_shown(speaker: String, text: String, portrait: Texture2D) -> void:
	_close_choices()
	_box.show()
	_arrow.hide()
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_text_label.text = text
	_text_label.visible_characters = 0
	_shown = 0.0
	_typing = true


func _on_choices_shown(options: PackedStringArray) -> void:
	if _typing:
		_pending_choices = options
	else:
		_open_choices(options)


func _on_box_style_changed(style: String) -> void:
	if style == "parchment":
		_box.self_modulate = Color(0.95, 0.88, 0.72, 1.0)
	else:
		_box.self_modulate = Color.WHITE


func _finish_typing() -> void:
	_typing = false
	_text_label.visible_characters = -1
	if _pending_choices.is_empty():
		_arrow.show()
	else:
		_open_choices(_pending_choices)
		_pending_choices = PackedStringArray()


func _open_choices(options: PackedStringArray) -> void:
	_close_choices()
	_options = options
	for text in options:
		var label := Label.new()
		label.text = text
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


func _hide_all() -> void:
	_typing = false
	_pending_choices = PackedStringArray()
	_close_choices()
	_box.hide()


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)
