extends Control
# ============================================================================
# FISH ALMANAC UI  (static reference book)
# ============================================================================
# Lists every fish species on the left and shows its details on the right.
# No unlocks, no catch tracking: everything is always visible.
#
# Open it with:
#     GameManager.change_scene("res://ui/FishAlmanacUI.tscn")
# or instance it as an overlay and listen for `back_pressed`.
#
# DATA SOURCE (FishData resources, one .tres per species):
#   1. GameDatabase.get_all_fish(), if that autoload provides it
#   2. otherwise every .tres in res://data/fish/ is loaded directly
#
# NOTE: the display name and the generic icon come from ItemData (parent of
# FishData). I don't know ItemData's exact field names, so _name_of() tries
# display_name / item_name / name and falls back to the prettified id. If
# yours differs, change the key list there.
# ============================================================================

signal back_pressed

const FISH_DIR := "res://data/fish/"
const SIZE_ORDER := ["small", "medium", "large"]
const ICON_SIZE := 128

var _list: ItemList
var _detail: RichTextLabel
var _counter: Label
var _fish: Array = [] # Array of FishData


func _ready() -> void:
	_build_ui()
	_load_fish()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		back_pressed.emit()


# ---------------------------------------------------------------------------
# UI CONSTRUCTION
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Fish Almanac"
	title.add_theme_font_size_override("font_size", 28)
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_counter = Label.new()
	header.add_child(_counter)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): back_pressed.emit())
	header.add_child(back)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(260, 0)
	_list.item_selected.connect(_show_detail)
	split.add_child(_list)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_detail)


# ---------------------------------------------------------------------------
# DATA
# ---------------------------------------------------------------------------
func _load_fish() -> void:
	_fish = _get_fish_resources()
	# Small -> medium -> large, then alphabetical.
	_fish.sort_custom(func(a: FishData, b: FishData) -> bool:
		var sa := SIZE_ORDER.find(a.size_class)
		var sb := SIZE_ORDER.find(b.size_class)
		if sa != sb:
			return sa < sb
		return _name_of(a) < _name_of(b))

	_list.clear()
	for f in _fish:
		_list.add_item(_name_of(f))

	_counter.text = "%d species" % _fish.size()

	if _fish.is_empty():
		_detail.text = "[center]No fish data found.\nAdd FishData .tres files to %s[/center]" % FISH_DIR
	else:
		_list.select(0)
		_show_detail(0)


func _get_fish_resources() -> Array:
	var out: Array = []

	var db := get_node_or_null("/root/GameDatabase")
	if db and db.has_method("get_all_fish"):
		for f in db.get_all_fish():
			if f is FishData:
				out.append(f)
		if not out.is_empty():
			return out

	# Fallback: load the .tres files straight from the fish folder.
	var dir := DirAccess.open(FISH_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		# Exported builds list resources as "name.tres.remap".
		var fname := file.trim_suffix(".remap")
		if fname.ends_with(".tres"):
			var res = load(FISH_DIR + fname)
			if res is FishData:
				out.append(res)
	return out


func _name_of(f: FishData) -> String:
	for key in ["display_name", "item_name", "name"]:
		var v = f.get(key)
		if v is String and v != "":
			return v
	if f.resource_name != "":
		return f.resource_name
	var id = f.get("id")
	return _prettify(str(id)) if id != null else "Unnamed fish"


func _prettify(text: String) -> String:
	return text.replace("fish_", "").replace("_", " ").capitalize()


func _num(v: float) -> String:
	return String.num(v, 2)


# ---------------------------------------------------------------------------
# DETAIL PANEL
# ---------------------------------------------------------------------------
func _show_detail(index: int) -> void:
	var f: FishData = _fish[index]
	_detail.clear()

	# Prefer the 3D-style icon; fall back to ItemData's generic icon if any.
	var icon: Texture2D = f.icon_3d
	if icon == null:
		var generic = f.get("icon")
		if generic is Texture2D:
			icon = generic
	if icon:
		_detail.add_image(icon, ICON_SIZE, ICON_SIZE)
		_detail.append_text("\n\n")

	_detail.append_text("[font_size=28][b]%s[/b][/font_size]\n" % _name_of(f))
	if f.scientific_name != "":
		_detail.append_text("[i]%s[/i]\n" % f.scientific_name)
	_detail.append_text("\n")

	var w := f.get_weight_range_kg()
	var rows := [
		["Category", f.size_class.capitalize()],
		["Size", "%s - %s cm (average %s cm)" % [_num(f.min_size), _num(f.max_size), _num(f.avg_size)]],
		["Weight", "%s - %s kg (average %s kg)" % [_num(w.x), _num(w.y), _num(f.avg_weight)]],
		["Sell price", "%d - %d (average %d)" % [f.get_sell_price(f.min_size), f.get_sell_price(f.max_size), f.base_price]],
		["Difficulty", _num(f.speed)],
		["Pull strength", _num(f.pull_strength)],
		["Stamina", "%s s" % _num(f.stamina)],
	]
	for row in rows:
		_detail.append_text("%s: [b]%s[/b]\n" % [row[0], row[1]])

	if f.description != "":
		_detail.append_text("\n%s" % f.description)
