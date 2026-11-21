## DatabaseEntry: base class of every authored record in the game database.
##
## Each fish, bait, rod and location is one [code].tres[/code] file whose script is a subclass of
## this class. The class definitions live in [code]res://resources/[/code] (the "shape" of the data);
## the .tres files in [code]res://data/[/code] hold the actual values.
##
## [b]Class tree[/b]
## [codeblock]
## DatabaseEntry        id, display_name
## |-- ItemData         + icon, grid inventory footprint (anything the player can carry)
## |   |-- FishData
## |   `-- BaitData
## |-- RodData
## `-- LocationData
## [/codeblock]
## Records are static, authored data: the game never changes them at runtime. GDScript cannot
## mark an object read-only, so this is a convention (the loader never modifies valid records).
class_name DatabaseEntry
extends Resource

## Stable unique key, lowercase snake_case, starting with the kind's prefix (fish_, bait_, rod_,
## location_), e.g. "fish_bluegill". Save files store this text, so [b]never rename or reuse an id[/b]
## once any save could contain it: change [member display_name] instead. Convention: name the .tres
## file exactly like the id (fish_bluegill.tres); the loader only warns if they differ.
@export var id: String = ""

## Name shown to the player in menus and the fish log.
@export var display_name: String = ""


## The prefix every id of this kind must start with. Overridden by each subclass; the loader uses it
## to catch an id pasted into the wrong kind of record (e.g. a rod called "fish_basic").
func get_id_prefix() -> String:
	return ""
