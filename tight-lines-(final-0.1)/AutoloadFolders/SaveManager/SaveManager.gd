extends Node

const SAVE_DIR = "user://saves/"

func _ready():
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_game(slot: int, data: Dictionary):
	data["timestamp"] = Time.get_datetime_string_from_system()
	var file = FileAccess.open(SAVE_DIR + "slot_%d.json" % slot, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func load_game(slot: int) -> Dictionary:
	var path = SAVE_DIR + "slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	return data if data is Dictionary else {}

func delete_save(slot: int):
	var path = SAVE_DIR + "slot_%d.json" % slot
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(SAVE_DIR + "slot_%d.json" % slot)
