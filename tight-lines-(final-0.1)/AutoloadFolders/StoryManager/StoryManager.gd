extends Node

# ============================================================================
# STORY MANAGER (GODOT)  -  TightLines                                (Ver. 1)
# ============================================================================
# Autoload singleton named exactly "StoryManager". Load it AFTER QuestManager.
#
# JOB: read the story .txt files (in STORY_FILES order), turn them into
# cutscenes, and play them step by step. It draws no UI: DialogueBox listens
# to the signals below and calls advance() / choose().
#
# SEEN CUTSCENES are stored as SaveManager unlock flags "seen_<cutscene_id>",
# so they are saved with the slot without any SaveManager change.
#
# FILE FORMAT  -  the first character of a line decides what it is:
#   # comment                     === cutscene_id | scene: x | requires: a, b
#   @speaker[:emotion] [text]     @  (narrator)
#   plain text  (consecutive lines = same box)    blank line = next box
#   !command args   (!? = !shake) * choice text -> label
#   :: label                      -> label        \ escapes the first char
# ============================================================================

signal cutscene_started(cutscene_id: String)
signal cutscene_finished(cutscene_id: String)
signal line_shown(speaker_name: String, text: String, portrait: Texture2D)
signal choices_shown(options: PackedStringArray)
signal dialogue_hidden
signal box_style_changed(style: String)
signal command_emitted(command: String, args: PackedStringArray)
signal notice_requested(text: String)
signal jeep_reached

signal _advanced
signal _chosen(index: int)
signal _skipped

# ============================================================================
# STORY FILES  -  the ORDER of this list is the order of the story
# ============================================================================
const STORY_FILES: Array = [
	"res://data/story/01_marikina.txt",
	"res://data/story/02_imus.txt",
	"res://data/story/03_kawit.txt",
	"res://data/story/04_noveleta_pen.txt",
	"res://data/story/05_noveleta_salt.txt",
	"res://data/story/06_calatagan.txt",
	"res://data/story/07_fortune_island.txt",
	"res://data/story/08_ending.txt",
]

# Quest completion -> cutscene to play when back in the overworld.
const QUEST_COMPLETION_CUTSCENES: Dictionary = {
	"quest_gear_up": "marikina_complete",
	"quest_paddy_page": "imus_complete",
	"quest_salt_and_sea": "kawit_complete",
	"quest_fenced_in": "pen_complete",
	"quest_bright_water": "salt_complete",
	"quest_roots": "mangrove_complete",
	"quest_deep_giants": "island_complete",
}

# Speaker ids used after "@". Portraits: <portraits>/<emotion>.png
# (falls back to DEFAULT_EMOTION). Unknown ids show as capitalized text.
const CHARACTERS: Dictionary = {
	"john": {"name": "John", "portraits": "res://Assets/Portraits/John"},
	"diary": {"name": "Jeremy Wave", "portraits": "res://Assets/Portraits/Diary"},
}
const DEFAULT_EMOTION := "neutral"

const DIALOGUE_BOX_SCENE := "res://UIScenesAndScript/DialogueBox/DialogueBox.tscn"
const SEEN_PREFIX := "seen_"
const MAX_LINES_PER_BOX := 3
const MAX_STEPS_WITHOUT_INPUT := 10000
const INPUT_CONTEXT_MENU := 1          # InputManager.InputContext.MENU

# {key} in dialogue is replaced with variables[key].
var variables: Dictionary = {"player": "John"}

var _cutscenes: Dictionary = {}        # { id: {id, file, options, ops, labels} }
var _order: Array = []                 # cutscene ids in story order
var _running_id := ""
var _skipping := false
var _stopping := false
var _scene_after := ""
var _queued_cutscenes: Array[String] = [] # e.g. quest completions waiting for overworld
var _prev_input_context := -1
var _warned_speakers: Dictionary = {}
var _slug := RegEx.new()
var _sfx: AudioStreamPlayer

var _shake_tween: Tween
var _shake_cam2d: Camera2D
var _shake_cam3d: Camera3D
var _shake_base := Vector2.ZERO


func _ready() -> void:
	_slug.compile("^[a-z][a-z0-9_]*$")
	_sfx = AudioStreamPlayer.new()
	_sfx.bus = "SFX"
	add_child(_sfx)
	load_story()

	var save := _autoload("SaveManager")
	if save != null and save.has_method("get_player_name"):
		variables["player"] = String(save.call("get_player_name"))

	var gm := _autoload("GameManager")
	if gm != null and gm.has_signal("scene_changed"):
		gm.connect("scene_changed", _on_scene_changed)

	var qm := _autoload("QuestManager")
	if qm != null and qm.has_signal("quest_completed"):
		qm.connect("quest_completed", _on_quest_completed)

	if ResourceLoader.exists(DIALOGUE_BOX_SCENE):
		add_child((load(DIALOGUE_BOX_SCENE) as PackedScene).instantiate())
	else:
		push_warning("StoryManager: no dialogue box at %s." % DIALOGUE_BOX_SCENE)

	call_deferred("_check_initial_scene")


# ============================================================================
# PUBLIC API
# ============================================================================

# Plays a cutscene. Callers may wait for it:  await StoryManager.play("x")
func play(cutscene_id: String) -> void:
	if is_playing():
		push_warning("StoryManager: '%s' is playing; ignored play('%s')." % [_running_id, cutscene_id])
		return
	if not _cutscenes.has(cutscene_id):
		push_error("StoryManager: unknown cutscene '%s'." % cutscene_id)
		return
	_running_id = cutscene_id
	_skipping = false
	_stopping = false
	_scene_after = ""
	_lock_input()
	box_style_changed.emit("normal")
	cutscene_started.emit(cutscene_id)

	await _run(_cutscenes[cutscene_id])

	if _stopping:
		_stopping = false
		return

	dialogue_hidden.emit()
	box_style_changed.emit("normal")
	_stop_shake()
	_mark_seen(cutscene_id)
	_unlock_input()
	_running_id = ""
	_skipping = false
	cutscene_finished.emit(cutscene_id)
	if _scene_after != "":
		var gm := _autoload("GameManager")
		if gm != null:
			gm.call("change_scene", _scene_after)


func stop() -> void:
	if not is_playing():
		return
	var stopped_id := _running_id
	_stopping = true
	_skipping = true
	_scene_after = ""
	_running_id = ""
	dialogue_hidden.emit()
	box_style_changed.emit("normal")
	_stop_shake()
	_unlock_input()
	_advanced.emit()
	_chosen.emit(0)
	cutscene_finished.emit(stopped_id)


func clear_queued_cutscenes() -> void:
	_queued_cutscenes.clear()


func is_playing() -> bool:
	return _running_id != ""


func get_running_id() -> String:
	return _running_id


# DialogueBox: the player pressed "next" after the text finished typing.
func advance() -> void:
	if is_playing():
		_advanced.emit()


# DialogueBox: the player picked choice `index` (0-based).
func choose(index: int) -> void:
	if is_playing():
		_chosen.emit(index)


# Skips the currently playing cutscene, applying any !flag commands left in it.
func skip() -> void:
	if not is_playing() or _skipping:
		return
	_skipping = true
	_advanced.emit()
	_chosen.emit(0)


# Shows a quick non-blocking notice (e.g. locked area gate message).
func show_notice(text: String) -> void:
	notice_requested.emit(text)


func notify_jeep_reached() -> void:
	jeep_reached.emit()


func get_current_objective() -> String:
	var dlg := get_node_or_null("DialogueBox")
	if dlg != null and dlg.has_method("get_objective"):
		return String(dlg.call("get_objective"))
	return ""


func has_cutscene(cutscene_id: String) -> bool:
	return _cutscenes.has(cutscene_id)


func get_cutscene_ids() -> Array:
	return _order.duplicate()


func has_seen(cutscene_id: String) -> bool:
	var save := _autoload("SaveManager")
	return save != null and bool(save.call("has_unlock_flag", SEEN_PREFIX + cutscene_id))


# quest_* = quest completed, a cutscene id = seen, anything else = unlock flag.
# A leading "!" negates:  "!got_first_rod"
func check_condition(cond: String) -> bool:
	if cond.begins_with("!"):
		return not check_condition(cond.substr(1))
	if cond.begins_with("quest_"):
		var qm := _autoload("QuestManager")
		return qm != null and bool(qm.call("is_completed", cond))
	if _cutscenes.has(cond):
		return has_seen(cond)
	var save := _autoload("SaveManager")
	return save != null and bool(save.call("has_unlock_flag", cond))


func requirements_met(cutscene_id: String) -> bool:
	if not _cutscenes.has(cutscene_id):
		return false
	for cond in _cutscenes[cutscene_id]["options"]["requires"]:
		if not check_condition(String(cond)):
			return false
	return true


# First cutscene that should auto-play in this scene, or "".
# Story beats (scene-triggered, not "side") must be seen in file order.
func find_cutscene_for_scene(scene_id: String) -> String:
	var previous_beat := ""
	for raw_id in _order:
		var id := String(raw_id)
		var options: Dictionary = _cutscenes[id]["options"]
		if options["scene"] == "":
			continue
		var chain_ok: bool = options["side"] or previous_beat == "" or has_seen(previous_beat)
		if not options["side"]:
			previous_beat = id
		if options["scene"] != scene_id or not chain_ok:
			continue
		if has_seen(id) and not options["repeat"]:
			continue
		if requirements_met(id):
			return id
	return ""


func get_speaker_info(speaker_id: String, emotion: String = "") -> Dictionary:
	if speaker_id == "":
		return {"name": "", "portrait": null}
	if not CHARACTERS.has(speaker_id):
		return {"name": speaker_id.capitalize(), "portrait": null}
	var c: Dictionary = CHARACTERS[speaker_id]
	var folder := String(c.get("portraits", ""))
	var portrait: Texture2D = null
	if folder != "":
		for e in [emotion, DEFAULT_EMOTION]:
			var path := folder.path_join("%s.png" % e)
			if String(e) != "" and ResourceLoader.exists(path):
				portrait = load(path) as Texture2D
				break
	var display_name := String(c.get("name", speaker_id.capitalize()))
	if speaker_id == "john":
		var custom := String(variables.get("player", "")).strip_edges()
		if custom != "":
			display_name = custom
	return {"name": display_name, "portrait": portrait}


func shake_camera(strength: float = 8.0, duration: float = 0.4) -> void:
	_stop_shake()
	_shake_cam2d = get_viewport().get_camera_2d()
	_shake_cam3d = null if _shake_cam2d != null else get_viewport().get_camera_3d()
	if _shake_cam2d != null:
		_shake_base = _shake_cam2d.offset
	elif _shake_cam3d != null:
		_shake_base = Vector2(_shake_cam3d.h_offset, _shake_cam3d.v_offset)
	else:
		return
	_shake_tween = create_tween()
	_shake_tween.tween_method(_apply_shake.bind(strength), 1.0, 0.0, maxf(duration, 0.01))
	_shake_tween.finished.connect(_stop_shake)


func play_sfx(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		push_warning("StoryManager: sfx not found: '%s'." % path)
		return
	_sfx.stream = load(path) as AudioStream
	_sfx.play()


# Re-reads every story file (handy while writing: call it from a debug key).
func load_story() -> void:
	_cutscenes.clear()
	_order.clear()
	for path in STORY_FILES:
		_parse_file(String(path))


# ============================================================================
# PARSER  (text -> cutscenes made of "ops")
# ============================================================================

func _parse_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("StoryManager: cannot open '%s' (missing, or data/story/*.txt not in export filter)." % path)
		return
	var st := {"cs": {}, "skip": false, "box": [], "speaker": "", "emotion": "", "where": "", "file": path}
	var lines := file.get_as_text().split("\n")
	for i in lines.size():
		st["where"] = "%s:%d" % [path.get_file(), i + 1]
		_parse_line(st, lines[i].strip_edges())
	_flush_box(st)
	_close_cutscene(st)


func _parse_line(st: Dictionary, line: String) -> void:
	if line.begins_with("#"):
		return
	if line.begins_with("==="):
		_flush_box(st)
		_close_cutscene(st)
		st["cs"] = _open_cutscene(line, st)
		st["skip"] = (st["cs"] as Dictionary).is_empty()
		st["speaker"] = ""
		st["emotion"] = ""
		return
	if line.is_empty():
		_flush_box(st)                         # blank line = next dialogue box
		return
	if st["skip"]:
		return
	if (st["cs"] as Dictionary).is_empty():
		_err(st, "text before the first '=== cutscene_id' header")
		st["skip"] = true
		return

	var ops: Array = st["cs"]["ops"]
	if line.begins_with("::"):
		_flush_box(st)
		var label := line.substr(2).strip_edges()
		if _slug.search(label) == null:
			_err(st, "label '%s' must be lowercase snake_case" % label)
		else:
			st["cs"]["labels"][label] = ops.size()
	elif line.begins_with("->"):
		_flush_box(st)
		ops.append({"op": "jump", "label": line.substr(2).strip_edges(), "where": st["where"]})
	elif line.begins_with("*"):
		_flush_box(st)
		var arrow := line.find("->")
		if arrow < 0:
			_err(st, "a choice needs '-> label' (for text starting with *, write \\*)")
			return
		var option := {
			"text": line.substr(1, arrow - 1).strip_edges(),
			"label": line.substr(arrow + 2).strip_edges(),
		}
		if ops.is_empty() or ops[-1]["op"] != "choice":
			ops.append({"op": "choice", "options": [], "where": st["where"]})
		ops[-1]["options"].append(option)
	elif line.begins_with("!"):
		_flush_box(st)
		_parse_command(st, line.substr(1).strip_edges())
	elif line.begins_with("@"):
		_flush_box(st)
		var rest := line.substr(1)
		var space := rest.find(" ")
		var spec := rest if space < 0 else rest.substr(0, space)
		st["speaker"] = spec.get_slice(":", 0).strip_edges().to_lower()
		st["emotion"] = spec.get_slice(":", 1).strip_edges().to_lower() if spec.contains(":") else ""
		if space >= 0 and rest.substr(space + 1).strip_edges() != "":
			st["box"].append(rest.substr(space + 1).strip_edges())
	elif line.begins_with("\\"):
		st["box"].append(line.substr(1))
	else:
		st["box"].append(line)


func _parse_command(st: Dictionary, body: String) -> void:
	if body.is_empty():
		return                                 # lone "!" = just end the box
	if body.begins_with("?"):
		body = "shake " + body.substr(1)       # "!?" shorthand
	var parts := body.split(" ", false)
	var cmd := parts[0].to_lower()
	var args := parts.slice(1)
	var ops: Array = st["cs"]["ops"]
	if cmd == "if":
		if args.size() != 3 or args[1] != "->":
			_err(st, "write it as:  !if condition -> label")
			return
		ops.append({"op": "if", "cond": args[0], "label": args[2], "where": st["where"]})
		return
	ops.append({"op": "cmd", "name": cmd, "args": args, "where": st["where"]})


func _flush_box(st: Dictionary) -> void:
	var box: Array = st["box"]
	if box.is_empty():
		return
	if not (st["cs"] as Dictionary).is_empty():
		if box.size() > MAX_LINES_PER_BOX:
			push_warning("StoryManager: %s: box has %d lines (max %d)." % [st["where"], box.size(), MAX_LINES_PER_BOX])
		var speaker := String(st["speaker"])
		if speaker != "" and not CHARACTERS.has(speaker) and not _warned_speakers.has(speaker):
			_warned_speakers[speaker] = true
			push_warning("StoryManager: %s: speaker '%s' is not in CHARACTERS (typo?)." % [st["where"], speaker])
		st["cs"]["ops"].append({
			"op": "say",
			"speaker": speaker,
			"emotion": st["emotion"],
			"text": "\n".join(PackedStringArray(box)),
		})
	box.clear()


func _open_cutscene(line: String, st: Dictionary) -> Dictionary:
	var parts := line.lstrip("=").split("|")
	var id := parts[0].rstrip("= ").strip_edges()
	if _slug.search(id) == null:
		_err(st, "cutscene id '%s' must be lowercase snake_case" % id)
		return {}
	if _cutscenes.has(id):
		_err(st, "duplicate cutscene id '%s'" % id)
		return {}
	var options := {"scene": "", "requires": [], "repeat": false, "side": false}
	for i in range(1, parts.size()):
		var part := parts[i].strip_edges()
		var key := part.get_slice(":", 0).strip_edges().to_lower()
		var value := part.substr(part.find(":") + 1).strip_edges() if part.contains(":") else ""
		match key:
			"scene":
				options["scene"] = value
			"requires":
				for r in value.split(",", false):
					options["requires"].append(r.strip_edges())
			"repeat":
				options["repeat"] = true
			"side":
				options["side"] = true
			_:
				push_warning("StoryManager: %s: unknown option '%s'." % [st["where"], key])
	return {"id": id, "file": st["file"], "options": options, "ops": [], "labels": {}}


# Validates labels, then registers the cutscene in story order.
func _close_cutscene(st: Dictionary) -> void:
	var cs: Dictionary = st["cs"]
	st["cs"] = {}
	if cs.is_empty():
		return
	var labels: Dictionary = cs["labels"]
	for op in cs["ops"]:
		var targets: Array = []
		match op["op"]:
			"jump", "if":
				targets.append(op["label"])
			"choice":
				for o in op["options"]:
					targets.append(o["label"])
		for t in targets:
			if not labels.has(t):
				push_error("StoryManager: %s: unknown label '%s'; cutscene '%s' skipped." % [op["where"], t, cs["id"]])
				return
	_cutscenes[cs["id"]] = cs
	_order.append(cs["id"])


func _err(st: Dictionary, msg: String) -> void:
	push_error("StoryManager: %s: %s." % [st["where"], msg])


# ============================================================================
# RUNNER
# ============================================================================

func _run(cs: Dictionary) -> void:
	var ops: Array = cs["ops"]
	var labels: Dictionary = cs["labels"]
	var pc := 0
	var steps := 0
	while pc < ops.size():
		if _stopping:
			return
		steps += 1
		if steps > MAX_STEPS_WITHOUT_INPUT:
			push_error("StoryManager: '%s' loops without waiting for the player; stopped." % cs["id"])
			return
		var op: Dictionary = ops[pc]
		pc += 1
		match op["op"]:
			"say":
				steps = 0
				if _skipping:
					continue
				_show_line(op)
				var has_choices: bool = pc < ops.size() and ops[pc]["op"] == "choice"
				if not has_choices:
					await _advanced
					if _stopping:
						return
			"choice":
				steps = 0
				if _skipping:
					pc = labels[op["options"][0]["label"]]
					continue
				var texts := PackedStringArray()
				for option in op["options"]:
					texts.append(_substitute(String(option["text"])))
				choices_shown.emit(texts)
				var index: int = await _chosen
				if _stopping:
					return
				index = clampi(index, 0, texts.size() - 1)
				pc = labels[op["options"][index]["label"]]
			"jump":
				pc = labels[op["label"]]
			"if":
				if check_condition(String(op["cond"])):
					pc = labels[op["label"]]
			"cmd":
				var stop_cmd: bool = await _run_command(op)
				if stop_cmd or _stopping:
					return


func _run_command(op: Dictionary) -> bool:
	var args: PackedStringArray = op["args"]
	match op["name"]:
		"shake":
			shake_camera(_arg_float(args, 0, 8.0), _arg_float(args, 1, 0.4))
		"wait":
			if not _skipping:
				await get_tree().create_timer(_arg_float(args, 0, 0.5), false).timeout
		"hide":
			dialogue_hidden.emit()
		"box":
			box_style_changed.emit(_arg(args, 0, "normal"))
		"flag":
			var save := _autoload("SaveManager")
			for flag in args:
				if save != null:
					save.call("add_unlock_flag", flag)
		"sfx":
			play_sfx(_arg(args, 0))
		"music":
			var gm := _autoload("GameManager")
			if gm != null:
				gm.call("play_music", _arg(args, 0))
		"call":
			await _call_scene_method(args)
		"scene":
			_scene_after = _arg(args, 0)
			return true
		"end":
			return true
		_:
			command_emitted.emit(op["name"], args)
	return false


func _call_scene_method(args: PackedStringArray) -> void:
	var scene := get_tree().current_scene
	var method := _arg(args, 0)
	if scene == null or method == "" or not scene.has_method(method):
		push_warning("StoryManager: current scene has no method '%s' for !call." % method)
		return
	await scene.callv(method, Array(args.slice(1)))


func _show_line(op: Dictionary) -> void:
	var info := get_speaker_info(String(op["speaker"]), String(op["emotion"]))
	line_shown.emit(info["name"], _substitute(String(op["text"])), info["portrait"])


func _substitute(text: String) -> String:
	for key in variables:
		text = text.replace("{%s}" % key, str(variables[key]))
	return text


# ============================================================================
# HELPERS
# ============================================================================

func _check_initial_scene() -> void:
	var gm := _autoload("GameManager")
	if gm == null:
		return
	var scene_id := String(gm.get("current_scene_id"))
	if scene_id != "":
		_on_scene_changed(scene_id)


func _on_scene_changed(scene_id: String) -> void:
	if _running_id != "":
		stop()
	if not _queued_cutscenes.is_empty() and scene_id.begins_with("overworld_"):
		while not _queued_cutscenes.is_empty():
			var qid: String = _queued_cutscenes.pop_front()
			if not has_seen(qid):
				play(qid)
				return
	var id := find_cutscene_for_scene(scene_id)
	if id != "":
		play(id)


func _on_quest_completed(quest_id: String) -> void:
	if not QUEST_COMPLETION_CUTSCENES.has(quest_id):
		return
	var cutscene_id := String(QUEST_COMPLETION_CUTSCENES[quest_id])
	if has_seen(cutscene_id) or not has_cutscene(cutscene_id):
		return
	var gm := _autoload("GameManager")
	var current_scene := String(gm.get("current_scene_id")) if gm != null else ""
	if current_scene.begins_with("overworld_") and not is_playing():
		play(cutscene_id)
	elif not _queued_cutscenes.has(cutscene_id):
		_queued_cutscenes.append(cutscene_id)


func _mark_seen(cutscene_id: String) -> void:
	var save := _autoload("SaveManager")
	if save != null:
		save.call("add_unlock_flag", SEEN_PREFIX + cutscene_id)


func _lock_input() -> void:
	var im := _autoload("InputManager")
	if im == null:
		return
	_prev_input_context = int(im.get("context"))
	im.call("set_context", INPUT_CONTEXT_MENU)


func _unlock_input() -> void:
	var im := _autoload("InputManager")
	if im != null and _prev_input_context >= 0 and int(im.get("context")) == INPUT_CONTEXT_MENU:
		im.call("set_context", _prev_input_context)
	_prev_input_context = -1


func _apply_shake(decay: float, strength: float) -> void:
	var o := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * strength * decay
	if is_instance_valid(_shake_cam2d):
		_shake_cam2d.offset = _shake_base + o
	elif is_instance_valid(_shake_cam3d):
		_shake_cam3d.h_offset = _shake_base.x + o.x * 0.01
		_shake_cam3d.v_offset = _shake_base.y + o.y * 0.01


func _stop_shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	if is_instance_valid(_shake_cam2d):
		_shake_cam2d.offset = _shake_base
	elif is_instance_valid(_shake_cam3d):
		_shake_cam3d.h_offset = _shake_base.x
		_shake_cam3d.v_offset = _shake_base.y
	_shake_cam2d = null
	_shake_cam3d = null


func _arg(args: PackedStringArray, i: int, fallback: String = "") -> String:
	return args[i] if i < args.size() else fallback


func _arg_float(args: PackedStringArray, i: int, fallback: float) -> float:
	return args[i].to_float() if i < args.size() and args[i].is_valid_float() else fallback


func _autoload(autoload_name: String) -> Node:
	return get_tree().root.get_node_or_null(autoload_name)
