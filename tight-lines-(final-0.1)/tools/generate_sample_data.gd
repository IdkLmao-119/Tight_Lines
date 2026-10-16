## One-time tool: saves the PLACEHOLDER sample records as .tres files in res://data/.
##
## You do NOT need this to use the database: the sample files are already in the zip, and your real
## content is authored in the Godot Inspector. It exists so the sample data can be regenerated (and
## so you can see how records are built in code).
##
## Run from the project folder (the project must have been opened or imported once, so Godot knows
## the class names):
## [codeblock]
## godot --headless --path . --import
## godot --headless --path . --script res://tools/generate_sample_data.gd
## [/codeblock]
## SAFETY: the tool refuses to run if any target file already exists, because it would overwrite your
## edits. Pass [code]-- --force[/code] after the script path to overwrite anyway.
extends SceneTree

const SampleData := preload("res://tools/sample_data.gd")

# Where each kind of record is saved.
const FOLDERS := {"fish": "res://data/fish/", "bait": "res://data/bait/", "rods": "res://data/rods/", "locations": "res://data/locations/"}


func _initialize() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	var world := SampleData.build_world()

	# Refuse to overwrite existing files unless asked to.
	if not force:
		for kind in FOLDERS:
			for record in world[kind]:
				var path: String = FOLDERS[kind] + record.id + ".tres"
				if FileAccess.file_exists(path):
					printerr("Refusing to overwrite %s (pass '-- --force' to allow)." % path)
					quit(1)
					return

	# Fish first: baits and locations refer to them (see take_over_path below).
	var saved := 0
	for kind in ["fish", "bait", "rods", "locations"]:
		DirAccess.make_dir_recursive_absolute(FOLDERS[kind])
		for record in world[kind]:
			var path: String = FOLDERS[kind] + record.id + ".tres"
			var error := ResourceSaver.save(record, path, ResourceSaver.FLAG_CHANGE_PATH)
			if error != OK:
				printerr("Could not save %s (error %d)" % [path, error])
				quit(1)
				return
			# Give the in-memory record its file path so records saved after it link to the file
			# (ext_resource) instead of embedding a private copy of it.
			record.take_over_path(path)
			saved += 1
	print("Saved %d sample records under res://data/." % saved)
	quit(0)
