extends Node3D

# ============================================================================
# WEATHER SYSTEM (SCENE NODE) - TightLines                 Version 0.1 (2026-10-22)
# ============================================================================
# Add ONE Node3D named "WeatherSystem" to the 3D fishing scene and attach this
# script. It is NOT an autoload (no class_name, on purpose).
#
# WHAT IT DOES
#   1. Runs an in-game clock (time_of_day: dawn / day / dusk / night).
#   2. Picks a new random weather every `weather_change_game_minutes`
#      IN-GAME minutes (default 10).
#   3. Shows the weather: rain particles, fog, and sun light, built in code.
#   4. Tells FishingManager the current weather and time of day, so the catch
#      odds (GameDB modifiers) change with them. FishingManager finds this node
#      by itself through the group "weather_system".
#
# SPEED OF TIME (the one number to tune)
#   day_length_real_minutes = how many REAL minutes one in-game day lasts.
#   Default 48  ->  1 in-game minute = 2 real seconds
#               ->  weather changes every 20 real seconds, a day is 48 minutes.
#   Weather every 60 real seconds? Set day_length_real_minutes to 144.
#
# WEATHER WORDS come from the database: GameDB.get_condition_values("weather"),
# i.e. FishingTerms.WEATHERS, so a modifier on a fish always matches. Visuals are
# chosen by keyword in the word (storm, rain, fog, cloud, clear).
# An unknown word still works for the odds and just looks like clear weather.
#
# OPTIONAL SCENE LINKS (found automatically when left empty)
#   world_environment : fog is changed on its Environment (duplicated at start)
#   sun               : DirectionalLight3D, dimmed by weather and turned by time
#
# The clock pauses with the game (normal pause), and restarts at `start_hour`
# every time the scene loads.
# ============================================================================

signal weather_changed(new_weather: String, old_weather: String)
signal time_of_day_changed(new_time: String, old_time: String)
signal day_passed(day_number: int)

@export_group("Clock")
@export var day_length_real_minutes := 48.0     # real minutes for one in-game day
@export_range(0.0, 24.0, 0.25) var start_hour := 8.0
@export var clock_running := true
@export var dawn_start := 5.0                   # hour each phase begins (24 h clock)
@export var day_start := 8.0
@export var dusk_start := 17.0
@export var night_start := 20.0

@export_group("Weather")
@export var weather_change_game_minutes := 10.0 # IN-GAME minutes between changes
@export var start_weather := ""                 # "" = random
@export var avoid_repeat := true                # never the same weather twice in a row
@export var weather_weights: Dictionary = {}    # e.g. {"storm": 0.3, "clear": 2.0}; missing = 1.0
@export var fallback_weathers: PackedStringArray = ["clear", "cloudy", "rain", "storm", "fog"]

@export_group("Scene links (optional)")
@export var world_environment: WorldEnvironment
@export var sun: DirectionalLight3D
@export var rotate_sun := true                  # turn the sun with the time of day

@export_group("Look")
@export var transition_seconds := 5.0           # real seconds to fade between weathers
@export var max_fog_density := 0.03
@export var rain_radius := 14.0
@export var rain_height := 12.0
@export var rain_max_amount := 2000
@export var debug_log := false

# What each kind of weather looks like. 0..1 values:
#   rain  = rain intensity, fog = fog amount, light = sun brightness multiplier
const LOOKS := {
	"clear": {"rain": 0.0, "fog": 0.0, "light": 1.0},
	"cloudy": {"rain": 0.0, "fog": 0.2, "light": 0.7},
	"rain": {"rain": 0.55, "fog": 0.35, "light": 0.55},
	"storm": {"rain": 1.0, "fog": 0.5, "light": 0.35},
	"fog": {"rain": 0.0, "fog": 1.0, "light": 0.6},
}
const NIGHT_LIGHT := 0.12     # sun brightness multiplier at night (moonlight)

# --- Public state (read by FishingManager and the HUD) ---
var weather := ""
var time_of_day := ""
var game_minutes := 0.0       # minutes since midnight, 0..1440
var day_count := 0

# --- Internals ---
var _db: Node = null
var _pool := PackedStringArray()
var _weather_timer := 0.0
var _from := {"rain": 0.0, "fog": 0.0, "light": 1.0}
var _to := {"rain": 0.0, "fog": 0.0, "light": 1.0}
var _current := {"rain": 0.0, "fog": 0.0, "light": 1.0}
var _blend := 1.0
var _rain: GPUParticles3D = null
var _base_fog_enabled := false
var _base_fog_density := 0.0
var _base_sun_energy := 1.0
var _warned: Dictionary = {}


func _ready() -> void:
	add_to_group("weather_system")
	_db = get_node_or_null("/root/GameDB")
	_pool = _load_pool()
	_check_time_words()

	if world_environment == null:
		world_environment = _find_first("WorldEnvironment") as WorldEnvironment
	if sun == null:
		sun = _find_first("DirectionalLight3D") as DirectionalLight3D

	if world_environment != null and world_environment.environment != null:
		# Own copy, so changing fog never edits a shared .tres.
		world_environment.environment = world_environment.environment.duplicate()
		_base_fog_enabled = world_environment.environment.fog_enabled
		_base_fog_density = world_environment.environment.fog_density
	if sun != null:
		_base_sun_energy = sun.light_energy

	_build_rain()

	set_hour(start_hour)
	var first := start_weather if start_weather != "" else _pick_weather()
	if start_weather != "" and not _pool.has(start_weather):
		_warn_once("start_weather", "start_weather '%s' is not in the weather list %s." % [start_weather, str(_pool)])
	set_weather(first, true)
	_update_sun()


func _process(delta: float) -> void:
	if clock_running:
		_advance_minutes(delta * 1440.0 / maxf(day_length_real_minutes * 60.0, 1.0))

	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(transition_seconds, 0.01), 1.0)
		for key in _current:
			_current[key] = lerpf(float(_from[key]), float(_to[key]), _blend)
		_apply_look()

	_follow_camera()
	_update_sun()


# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

# {time_of_day, weather}: the words GameDB expects in its odds context.
func get_context() -> Dictionary:
	return {"time_of_day": time_of_day, "weather": weather}


func get_hour() -> float:
	return game_minutes / 60.0


# "08:30": for a HUD label.
func get_clock_text() -> String:
	return "%02d:%02d" % [int(game_minutes / 60.0) % 24, int(game_minutes) % 60]


# Jump the clock to an hour (0..24). Does not roll new weather.
func set_hour(hour: float) -> void:
	game_minutes = fposmod(hour, 24.0) * 60.0
	_update_time_of_day()


# Force a weather word now (testing, cutscenes, story events).
func set_weather(word: String, immediate := false) -> void:
	if word == "":
		return
	var old := weather
	weather = word
	_from = _current.duplicate()
	_to = _look_for(word)
	if immediate:
		_current = _to.duplicate()
		_blend = 1.0
		_apply_look()
	else:
		_blend = 0.0
	if debug_log:
		print("[WeatherSystem] weather %s -> %s at %s" % [old if old != "" else "(none)", word, get_clock_text()])
	if old != word:
		weather_changed.emit(word, old)


# Pick a new random weather right now and restart the 10-minute timer.
func roll_weather() -> void:
	set_weather(_pick_weather())


# ----------------------------------------------------------------------------
# Clock
# ----------------------------------------------------------------------------
func _advance_minutes(minutes: float) -> void:
	game_minutes += minutes
	if game_minutes >= 1440.0:
		game_minutes = fmod(game_minutes, 1440.0)
		day_count += 1
		day_passed.emit(day_count)
	_update_time_of_day()

	if weather_change_game_minutes <= 0.0:
		return
	_weather_timer += minutes
	var guard := 0
	while _weather_timer >= weather_change_game_minutes and guard < 8:
		_weather_timer -= weather_change_game_minutes
		roll_weather()
		guard += 1


func _update_time_of_day() -> void:
	var new_time := _phase_for_hour(get_hour())
	if new_time == time_of_day:
		return
	var old := time_of_day
	time_of_day = new_time
	if debug_log:
		print("[WeatherSystem] time of day %s -> %s at %s" % [old if old != "" else "(none)", new_time, get_clock_text()])
	time_of_day_changed.emit(new_time, old)


func _phase_for_hour(h: float) -> String:
	if h >= dawn_start and h < day_start:
		return "dawn"
	if h >= day_start and h < dusk_start:
		return "day"
	if h >= dusk_start and h < night_start:
		return "dusk"
	return "night"


# ----------------------------------------------------------------------------
# Weather picking
# ----------------------------------------------------------------------------
func _pick_weather() -> String:
	var candidates := PackedStringArray()
	for word in _pool:
		if avoid_repeat and _pool.size() > 1 and word == weather:
			continue
		candidates.append(word)
	if candidates.is_empty():
		return weather

	var total := 0.0
	for word in candidates:
		total += maxf(float(weather_weights.get(word, 1.0)), 0.0)
	if total <= 0.0:
		return candidates[0]

	var roll := randf() * total
	var acc := 0.0
	for word in candidates:
		acc += maxf(float(weather_weights.get(word, 1.0)), 0.0)
		if roll <= acc:
			return word
	return candidates[candidates.size() - 1]


func _load_pool() -> PackedStringArray:
	var words := PackedStringArray()
	if _db != null and _db.has_method("get_condition_values"):
		words = _db.get_condition_values("weather")
	if words.is_empty():
		_warn_once("pool", "GameDB gave no weather words - using fallback_weathers %s." % str(fallback_weathers))
		words = fallback_weathers
	return words


# The clock uses dawn / day / dusk / night. Warn once if the database does not
# know one of those words (its odds modifiers would never match it).
func _check_time_words() -> void:
	if _db == null or not _db.has_method("get_condition_values"):
		return
	var allowed: PackedStringArray = _db.get_condition_values("time_of_day")
	if allowed.is_empty():
		return
	for word in ["dawn", "day", "dusk", "night"]:
		if not allowed.has(word):
			_warn_once("time_" + word, "FishingTerms.TIMES_OF_DAY is %s and has no '%s'. Rename the phase in _phase_for_hour() or add the word to the database." % [str(allowed), word])


# ----------------------------------------------------------------------------
# Visuals
# ----------------------------------------------------------------------------
func _look_for(word: String) -> Dictionary:
	return (LOOKS[_category_for(word)] as Dictionary).duplicate()


func _category_for(word: String) -> String:
	var w := word.to_lower()
	if w.contains("storm") or w.contains("thunder"):
		return "storm"
	if w.contains("rain") or w.contains("shower") or w.contains("drizzle"):
		return "rain"
	if w.contains("fog") or w.contains("mist"):
		return "fog"
	if w.contains("cloud") or w.contains("overcast"):
		return "cloudy"
	if not (w.contains("clear") or w.contains("sun")):
		_warn_once("look_" + w, "no look for weather '%s' - showing it as clear weather (the odds still use the word)." % word)
	return "clear"


func _apply_look() -> void:
	var rain := float(_current["rain"])
	var fog := float(_current["fog"])

	if _rain != null:
		_rain.amount_ratio = clampf(rain, 0.01, 1.0)
		_rain.emitting = rain > 0.02

	if world_environment != null and world_environment.environment != null:
		var env := world_environment.environment
		env.fog_enabled = _base_fog_enabled or fog > 0.01
		env.fog_density = lerpf(_base_fog_density, max_fog_density, fog)


func _update_sun() -> void:
	if sun == null:
		return
	var h := get_hour()
	var daylight := 0.0
	if h > 6.0 and h < 18.0:
		daylight = sin((h - 6.0) / 12.0 * PI)
	sun.light_energy = _base_sun_energy * float(_current["light"]) * lerpf(NIGHT_LIGHT, 1.0, daylight)
	if rotate_sun:
		# Horizon at 06:00, overhead at 12:00, horizon at 18:00. At night the
		# light stays high and dim, like the moon, instead of shining upward.
		var pitch := -40.0
		if h > 6.0 and h < 18.0:
			pitch = -clampf((h - 6.0) / 12.0 * 180.0, 10.0, 170.0)
		sun.rotation_degrees.x = pitch


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.top_level = true
	_rain.amount = rain_max_amount
	_rain.lifetime = 0.7
	_rain.preprocess = 1.0
	_rain.emitting = false
	_rain.visibility_aabb = AABB(
		Vector3(-rain_radius, -rain_height - 2.0, -rain_radius),
		Vector3(rain_radius * 2.0, rain_height + 4.0, rain_radius * 2.0))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(rain_radius, 0.5, rain_radius)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 3.0
	process.initial_velocity_min = 18.0
	process.initial_velocity_max = 22.0
	process.gravity = Vector3(0.0, -9.8, 0.0)
	_rain.process_material = process

	var streak := BoxMesh.new()
	streak.size = Vector3(0.015, 0.45, 0.015)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	streak.material = material
	_rain.draw_pass_1 = streak

	add_child(_rain)


# One rain area that follows the main camera. (Split-screen: each player would
# need its own rain node; not built yet.)
func _follow_camera() -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_rain.global_position = cam.global_position + Vector3(0.0, rain_height, 0.0)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
func _find_first(type_name: String) -> Node:
	var found := get_tree().root.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("WeatherSystem: " + message)
