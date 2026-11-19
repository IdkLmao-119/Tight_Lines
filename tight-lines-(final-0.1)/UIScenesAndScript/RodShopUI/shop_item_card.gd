class_name ShopItemCard
extends PanelContainer

signal action_pressed(item_id: String)

@onready var _name_label: Label = %NameLabel
@onready var _icon_texture: TextureRect = %IconTexture
@onready var _action_button: Button = %ActionButton

var _item_id: String = ""


func _ready() -> void:
	_action_button.pressed.connect(func() -> void:
		action_pressed.emit(_item_id)
	)


func configure(item_id: String, title: String, icon: Texture2D, button_text: String, button_disabled: bool) -> void:
	_item_id = item_id
	_name_label.text = title
	_icon_texture.texture = icon
	_action_button.text = button_text
	_action_button.disabled = button_disabled
