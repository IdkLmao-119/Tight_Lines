## LocationData: one fishing spot = one 3D scene (Kawit, Dock...). One .tres file per location in
## [code]res://data/locations/[/code].
##
## The scene, background, music and ambience are NOT stored here: they are built into the 3D scene
## itself. ALL VALUES IN THE SAMPLE FILES ARE PLACEHOLDERS.
class_name LocationData
extends DatabaseEntry

@export_group("Access")

## Name of the unlock flag the player needs before they can fish here, lowercase snake_case, e.g.
## "unlock_dock". Empty = open from the start. The game grants the flag when the player interacts with
## the NPC who opens the spot; SaveManager remembers it and passes the player's flags to
## GameDB as context["unlocked"].
@export var unlock_flag: String = ""

@export_group("Fish")

## The fish that can appear here (at least one). This is the ONLY place the fish<->location relationship
## is stored; fish do not list their locations.
@export var fish_pool: Array[PoolEntry] = []


func get_id_prefix() -> String:
	return "location_"


## True if the location is open for a player with the flags in [param unlocked] (an Array or
## PackedStringArray of flag names): either no flag is needed, or the player has it.
func is_open_for(unlocked: Variant) -> bool:
	return unlock_flag.is_empty() or (unlocked != null and unlocked.has(unlock_flag))


## The pool entry for [param fish], or null if the fish does not appear here.
func find_entry(fish: FishData) -> PoolEntry:
	for entry in fish_pool:
		if entry != null and entry.fish == fish:
			return entry
	return null
