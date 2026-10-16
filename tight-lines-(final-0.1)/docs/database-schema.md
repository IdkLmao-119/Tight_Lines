# Appendix A — Game Database (`.tres` Resources): Schema, Manager & Open Questions

**Revision 4 — the database is now Godot Resources (`.tres`), not JSON.** Godot 4.6. Every number, name and text in the sample data is a **placeholder**. Tested: the loader and 201 headless checks on Godot 4.6. **Not tested:** authoring in the Inspector UI (no editor available in my environment), exporting a build.

---

## 1. What changed from the JSON version

| | JSON (rev 1–3) | `.tres` (rev 4) |
|---|---|---|
| Records | Dictionaries in 5 files | One typed `Resource` per record, one file each |
| Editing | Text editor | Godot Inspector (drag-and-drop for links) |
| Fish ↔ bait/location links | id strings, checked by the loader | Direct links to the fish `.tres` (the editor updates them when you move/rename files) |
| Typos in a field name | Caught by the loader | Impossible: the Inspector only shows real fields |
| Read-only guarantee | Deep-copied dictionaries | **Lost.** Records are shared, mutable objects (see §7) |
| `schema_version`, `deprecated` | Present | Dropped (see §10) |

Decisions that carried over unchanged: kg and cm; weight = size × avg_weight ÷ avg_size; sell price = base_price × size ÷ avg_size; no localisation, rarity or pity; three size classes; rod gives a chance per class and fish in a class share it by weight; bait is required, consumed per bite, whitelists fish and boosts specific ones; quests/buffs are runtime `extra_multipliers`; one 3D scene per location, unlocked by an NPC-granted flag; time of day / weather / season only boost or reduce odds; slug ids with a type prefix; the phone app needs no game data.

## 2. `.tres` vs JSON (your Q19, short version)

A `.tres` file is Godot's own text format for a saved object. Godot reads it natively, knows the field types, shows each field in the Inspector, and keeps links between files correct when you move them. The cost: you author in the editor, and the file is less pleasant to hand-edit or diff for big changes. It is still plain text, so version control works.

## 3. File layout

```
res://
  resources/            ← the "shape" of each record (scripts, you rarely touch these)
    fishing_terms.gd      allowed words: size classes, times of day, weather, seasons
    database_entry.gd     base: id + display_name
    item_data.gd          base for things in the grid inventory
    fish_data.gd  bait_data.gd  bait_boost.gd
    rod_data.gd   location_data.gd  pool_entry.gd  odds_modifier.gd
  data/                 ← YOUR CONTENT, one .tres per record (subfolders are scanned too)
    fish/ bait/ rods/ locations/
  scripts/autoload/game_database.gd   ← the manager (register as autoload "GameDatabase")
  tools/sample_data.gd, generate_sample_data.gd   ← regenerate the placeholder data
  tests/test_game_database.gd, fixtures/
```

Name each file like its id (`fish_bass.tres`); a mismatch only produces a warning.

## 4. Field reference

**DatabaseEntry** (all records): `id` (slug with the type prefix), `display_name`.
**ItemData** (fish, bait): `icon`, `grid_width`, `grid_height` (1–20), `max_stack` (1–999).

**FishData** (`fish_…`): `scientific_name`, `description`, `icon_3d` (Texture2D), `size_class` (small/medium/large), `base_price`, `speed` (scales reel-bar drift and tension rise), `min_size` ≤ `avg_size` ≤ `max_size` (cm), `avg_weight` (kg at average size).

**BaitData** (`bait_…`): `enables_fish` (whitelist, at least one), `boosts` (list of **BaitBoost**: `fish`, `multiplier` > 0; the fish must also be in `enables_fish`; no duplicates).

**RodData** (`rod_…`): `icon`, `icon_3d`, `model_3d` (`.tscn`, must have a Node3D root and a `Marker3D` named `LineTip`), `rod_price`, `chance_small`, `chance_medium`, `chance_large` (each 0–1, **sum to 1.0**).

**LocationData** (`location_…`): `unlock_flag` (empty = open), `fish_pool` (list of **PoolEntry**, at least one, no fish twice).
**PoolEntry**: `fish`, `weight_multiplier` (0 removes the fish), `modifiers` (list of **OddsModifier**).
**OddsModifier**: `time_of_day`, `weather`, `season` (each a list of allowed words; empty = no restriction; at least one must be set), `multiplier` > 0. All set conditions must match (AND); a value inside a list is OR.

Placeholder situation words: time_of_day `dawn/day/dusk/night`; weather `clear/cloudy/rain/storm`; season `dry/wet`. The words live in `FishingTerms` **and** in the `@export_enum` lines (Godot needs literals there); a test fails if they disagree.

## 5. How a catch is decided

```
weight(fish) = location weight_multiplier × bait boost × matching modifiers × extra_multipliers
rod chance per class (e.g. small .2 / medium .3 / large .5)
a class the rod can catch but with no candidate fish here is "lost":
   its chance is split EQUALLY among classes the rod can catch that have candidates
odds(fish) = class_share × weight(fish) ÷ sum of weights in that class
```

Worked example (tested): Kawit, dry season, worm, sturdy rod (.5/.5/0): bluegill 0.375, perch 0.125, bass 0.5. Heavy rod (.2/.3/.5): large has no candidate (worm cannot catch catfish/carp), so 0.5 is split equally: small 0.2+0.25, medium 0.3+0.25 → bluegill 0.3375, perch 0.1125, bass 0.55.
Consequence: multipliers only shift odds **within a class**; a fish alone in its class always gets the whole class share.

**Context** passed by the game: `{"time_of_day": "night", "weather": "rain", "season": "wet", "unlocked": ["unlock_dock"]}`. A missing key means modifiers on that key do not apply.

## 6. Size, weight, price

`weight = size × avg_weight ÷ avg_size`; `sell price = round(base_price × size ÷ avg_size)`. Bluegill at 25 cm → 17; at 7.5 cm → 5, 0.075 kg. Carp at 65 cm → 90.

## 7. The manager (`GameDatabase`) and the `.tres` hazards

Load pipeline: scan `res://data/` recursively (export-safe, uses `ResourceLoader.list_directory`, Godot 4.4+) → load each file → validate each record → check references → build indexes. **Strict mode** (default in debug): any error fails the whole load. **Lenient** (release): bad records are skipped and logged. An empty database is always fatal. One cause gives one error (a rejected fish does not also report every bait that mentions it).

Public API: `load_all`, `load_records`, `reload`, `get_summary`; `get_fish/bait/rod/location` (null + warning if unknown), `has_*`, `get_all_*`, `get_ids/get_all/get_record`; `is_location_available`, `get_unlock_flag`, `get_condition_values`; `get_location_fish_pool`, `get_bait_enabled_fish`, `bait_enables_fish`, `get_catchable_fish_ids`, `get_location_weight_multiplier`, `get_bait_boost`; `get_catch_odds(location, bait, rod, context, extra_multipliers)`; `get_size_class_ids`, `get_rod_size_probabilities`, `get_fish_ids_in_class`, `get_weight_for_size_kg`, `get_sell_price`; `instantiate_rod_model`, `find_line_tip`. Signals: `database_loaded`, `database_load_failed(errors)`.

**Hazards to know:**
1. **Renaming an exported variable in a script silently drops that field's data from every existing `.tres`.** Add new fields freely; to rename, re-enter the values.
2. **Ids are permanent** (saves refer to them). Moving/renaming files is safe; changing `id` is not.
3. **Records are shared and mutable.** `get_fish()` returns the one real object; code that writes to it changes it for everyone. Never modify records at runtime; keep per-player state (stack counts, caught size) in your own objects.
4. Values equal to the script default are not written to the file (you saw this in the generated files). Do not set `_init` defaults on exports.
5. `reload()` refreshes edited files while running; anything holding an old record keeps the old copy.

## 8. Authoring workflow (untested in the editor)

FileSystem dock → right-click `data/fish/` → **New Resource…** → pick `FishData` → fill the Inspector → save as `fish_<name>.tres`. For a bait, drag fish files into `enables_fish`; for a location, add `PoolEntry` items to `fish_pool` and drag the fish in. Run the game (or the tests) to see validation messages. To regenerate the placeholder data: `godot --headless --path . --script res://tools/generate_sample_data.gd` (refuses to overwrite unless `-- --force`).

## 9. Outdated saves (SaveManager job, specification only)

Not implemented here. Rule you chose: an outdated **whole save file** is hidden from the slot list and the player gets a warning that old saves are no longer compatible. Needs a `save_version` stored in each save and a constant in the game; compare on load. Because `schema_version` is gone from the database, this is the only version check.

## 10. Assumptions I made

- `icon_3d` is a `Texture2D` (the spec said "3D icon"; could be a mesh/scene).
- Dropped `deprecated` and `schema_version` (never needed once saves are version-checked as a whole).
- Exactly three size classes. Adding one means: `FishingTerms.SIZE_CLASSES`, the `@export_enum` on `FishData`, a new `chance_*` on `RodData`, and updating the rod validation/tests.
- `Array[String]` fields with `@export_enum` should show as dropdown lists in the Inspector (Godot 4.x feature); I could not see the Inspector, so verify.
- `.tres` files under `res://data/` should be exported in the default "export all resources" mode; I could not test an export. If you use a custom resource filter, include `data/*`.
- Only 4.6 was tested.

## 11. Changes needed in `project-architecture.md` (not edited by me)

§3/§5/§6/§7 still mention rarity, pity, `base_weight` and `location_weights`. They should instead describe: size classes per fish, rod chance per class, `PoolEntry.weight_multiplier`, bait whitelist/boost, `extra_multipliers`. GameDatabaseManager is now "scans `res://data/*.tres`, validates, answers queries".

## 12. Open questions (default if you do not answer)

1. Should `LocationData` reference its 3D scene (`PackedScene`)? *Default: no, GameManager decides.*
2. Is `icon_3d` a texture? *Default: yes.*
3. Do bait and fish need shop prices? *Default: bait gets a `price` later; fish sell by formula.*
4. Inventory grid positions and rotation: runtime (InventoryManager), not in the database. *Default: yes.*
5. When an outdated save is hidden, can the player still start a new game in that slot? *Default: yes, with a warning.*
6. Final lists of times of day, weather and seasons, and do all three exist? *Default: the placeholder words.*
7. NPC unlocks: one flag per location, set by the NPC script. *Default: yes.*
