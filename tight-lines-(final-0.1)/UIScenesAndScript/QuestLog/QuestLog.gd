extends Control

# ============================================================================
# QUEST LOG UI (GODOT)  -  TightLines                                 (Ver. 1)
# ============================================================================
# Script of QuestLog.tscn. Shows the player's quests (reads QuestManager, never
# changes it):
#   - Tabs: Active / Completed (inactive quests stay hidden, no spoilers).
#   - Left: a list grouped by questline. Active quests show their progress.
#   - Right: details of the selected quest (story line, description, progress
#     bar, rewards). A note appears if rewards are waiting for room.
#
# HOW TO USE IT
#   This scene only DRAWS the log. It does not pause the game or change the
#   input context (GameManager owns those, rulings C4 / D7). Host it somewhere
#   that already does, for example as a tab/child of the inventory overlay, or
#   as its own overlay opened by GameManager (MENU context, game paused).
#       var log := preload("res://ui/QuestLog.tscn").instantiate()
#       log.close_requested.connect(_on_quest_log_closed)
#       add_child(log)
#   When the player closes it (Close button, or ui_cancel = Esc / phone swing),
#   it hides itself and emits close_requested so the host can clean up
#   (e.g. GameManager.close_inventory(), or free the node).
#
# CONTROLS (all work with the keyboard AND the phone, because the phone's
# swipe / tap / swing are injected as ui_* actions in the MENU context):
#   ui_up / ui_down  : choose a quest      ui_left / ui_right : change tab
#   ui_cancel        : close
#
# Requires the autoloads QuestManager and GameDB.
# ============================================================================

# Emitted when the player closes the log. The host decides what happens next.
signal close_requested

const STATE_IN_PROGRESS := "in_progress"
const STATE_COMPLETED := "completed"
# Tab index -> quest state shown on that tab.
const TAB_STATES := [STATE_IN_PROGRESS, STATE_COMPLETED]
const TAB_NAMES := ["Active", "Completed"]

# Turn off when the host handles ui_cancel itself.
@export var close_on_cancel := true

@onready var _tabs: TabBar = %Tabs
@onready var _tree: Tree = %QuestTree
@onready var _name_label: Label = %NameLabel
@onready var _state_label: Label = %StateLabel
@onready var _story_label: Label = %StoryLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _progress_label: Label = %ProgressLabel
@onready var _rewards_label: Label = %RewardsLabel
@onready var _pending_label: Label = %PendingLabel
@onready var _close_button: Button = %CloseButton

var _selected_id := ""
var _refresh_queued := false


func _ready() -> void:
	# Keep working while the game is paused (overlays run during pause).
	process_mode = Node.PROCESS_MODE_ALWAYS

	for name in TAB_NAMES:
		_tabs.add_tab(name)
	_tabs.tab_changed.connect(_on_tab_changed)

	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_SINGLE
	_tree.item_selected.connect(_on_item_selected)
	_tree.gui_input.connect(_on_tree_gui_input)

	_close_button.pressed.connect(close)

	# quests_changed can fire many times in one frame (a completion cascades),
	# so redraws are merged into one.
	QuestManager.quests_changed.connect(_queue_refresh)
	visibility_changed.connect(_on_visibility_changed)

	_refresh()
	if visible:
		_tree.grab_focus()


# ============================================================================
# PUBLIC API
# ============================================================================

func open() -> void:
	show()
	_refresh()
	_tree.grab_focus()


func close() -> void:
	hide()
	close_requested.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func handle_mobile_action(action: String) -> void:
	match action:
		"back":
			close()
		"tab_prev", "left":
			_step_tab(-1)
		"tab_next", "right":
			_step_tab(1)
		"up":
			_step_selection(-1)
		"down":
			_step_selection(1)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()
		_tree.grab_focus()


func _step_selection(step: int) -> void:
	var root := _tree.get_root()
	if root == null:
		return
	var items: Array[TreeItem] = []
	var header := root.get_first_child()
	while header != null:
		var child := header.get_first_child()
		while child != null:
			items.append(child)
			child = child.get_next()
		header = header.get_next()
	if items.is_empty():
		return
	var selected := _tree.get_selected()
	var idx := items.find(selected)
	idx = 0 if idx < 0 else clampi(idx + step, 0, items.size() - 1)
	var target := items[idx]
	target.select(0)
	_tree.ensure_cursor_is_visible()
	if target.get_metadata(0) != null:
		_show_details(String(target.get_metadata(0)))


# ============================================================================
# INPUT
# ============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if visible and close_on_cancel and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# Left / right change the tab (works from the phone too). Handled here because
# the Tree would otherwise use them itself.
func _on_tree_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left"):
		_tree.accept_event()
		_step_tab(-1)
	elif event.is_action_pressed(&"ui_right"):
		_tree.accept_event()
		_step_tab(1)


func _step_tab(direction: int) -> void:
	_tabs.current_tab = clampi(_tabs.current_tab + direction, 0, _tabs.tab_count - 1)


func _on_tab_changed(_tab: int) -> void:
	_selected_id = ""
	_refresh()


func _on_item_selected() -> void:
	var item := _tree.get_selected()
	if item != null and item.get_metadata(0) != null:
		_show_details(String(item.get_metadata(0)))


# ============================================================================
# DRAWING
# ============================================================================

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	for i in TAB_STATES.size():
		var count := QuestManager.get_quest_ids(TAB_STATES[i]).size()
		_tabs.set_tab_title(i, "%s (%d)" % [TAB_NAMES[i], count])
	_populate()
	_pending_label.visible = QuestManager.has_pending_rewards()


func _populate() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var wanted: String = TAB_STATES[_tabs.current_tab]
	var first: TreeItem = null
	var keep: TreeItem = null

	for line in QuestManager.get_questline_ids():
		var header: TreeItem = null
		for id in QuestManager.get_questline_quests(line):
			if QuestManager.get_state(id) != wanted:
				continue
			if header == null:
				header = _tree.create_item(root)
				header.set_text(0, _pretty(line).to_upper())
				header.set_selectable(0, false)
			var info := QuestManager.get_quest_info(id)
			var label: String = info["title"]
			if wanted == STATE_IN_PROGRESS:
				label += "    %d/%d" % [info["current"], info["target"]]
			var item := _tree.create_item(header)
			item.set_text(0, label)
			item.set_metadata(0, id)
			if first == null:
				first = item
			if id == _selected_id:
				keep = item

	var pick: TreeItem = keep if keep != null else first
	if pick != null:
		pick.select(0)
		_show_details(String(pick.get_metadata(0)))
	else:
		_show_details("")


func _show_details(quest_id: String) -> void:
	_selected_id = quest_id
	if quest_id == "" or not QuestManager.has_quest(quest_id):
		_selected_id = ""
		var completed_tab: bool = TAB_STATES[_tabs.current_tab] == STATE_COMPLETED
		_name_label.text = "Nothing completed yet." if completed_tab else "No active quests right now."
		_state_label.text = ""
		_story_label.text = ""
		_description_label.text = ""
		_progress_bar.visible = false
		_progress_label.text = ""
		_rewards_label.text = ""
		return

	var info := QuestManager.get_quest_info(quest_id)
	var done: bool = info["state"] == STATE_COMPLETED

	_name_label.text = info["title"]
	_state_label.text = "Completed" if done else "In progress"
	_story_label.text = info["complete_text"] if done else info["start_text"]
	_description_label.text = info["description"]

	_progress_bar.visible = true
	_progress_bar.max_value = maxf(float(info["target"]), 1.0)
	_progress_bar.value = float(info["current"])
	_progress_label.text = "%d / %d" % [info["current"], info["target"]]

	var rewards_text := _rewards_text(info["rewards"])
	if rewards_text == "":
		_rewards_label.text = ""
	else:
		_rewards_label.text = ("Rewards received:\n" if done else "Rewards:\n") + rewards_text


func _rewards_text(rewards: Dictionary) -> String:
	var lines := PackedStringArray()
	var money := int(rewards.get("money", 0))
	if money > 0:
		lines.append("- Money: %d" % money)
	for entry in rewards.get("bait", []):
		lines.append("- %s x%d" % [_bait_name(entry["id"]), entry["count"]])
	for rod_id in rewards.get("rods", []):
		lines.append("- %s" % _rod_name(rod_id))
	return "\n".join(lines)


func _bait_name(bait_id: String) -> String:
	if GameDB.has_bait(bait_id):
		return GameDB.get_bait(bait_id).display_name
	return bait_id


func _rod_name(rod_id: String) -> String:
	if GameDB.has_rod(rod_id):
		return GameDB.get_rod(rod_id).display_name
	return rod_id


# "main_story" -> "Main Story"
func _pretty(snake_case: String) -> String:
	return snake_case.replace("_", " ").capitalize()
