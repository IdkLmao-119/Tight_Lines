# Tight Lines – Debug / Demo Saves

Pre-made saves so you can show off the game without replaying the story.
On the save-slot screen, pick a slot and press **Load Save**.

| Menu slot | File | What it is |
|---|---|---|
| Slot 1 | `slot_0.json` | Your own save. **Never touched.** |
| Slot 2 | `slot_1.json` | **DEMO**: late game, every area open |
| Slot 3 | `slot_2.json` | **ENDING**: 100% Almanac, ready for the finale |

## Slot 2 – DEMO
- Starts in **Marikina City**, Day 12, 09:00, ₱5,000
- Every map area unlocked; all story cutscenes up to Calatagan already seen
- All 5 rods (Medium-Heavy equipped), 99 of each bait, 8 fish in the Fish Box to sell
- Almanac 33/50. Not caught yet:
  - **Bighead / Common / Rohu Carp**: catch one at Marikina River with Dough or Earthworm to show the *New Species* pop-up
  - The Fortune Island fish
- Fortune Island's arrival cutscene still plays when you go there
- Side quest *Night Fisher* is at 4/5. Catch any fish at Fortune Island to show a quest completing
- Final quest *The Unfinished Almanac* is in progress

## Slot 3 – ENDING
- Starts on **Fortune Island** at dusk, Day 30, ₱12,000, Almanac 50/50
- All quests done, `unlock_ending_home` granted
- Open the map and travel to **Marikina City (Home)** to play the ending

## Rebuilding / reinstalling
```
python make_debug_saves.py --install   # regenerate + copy into the game
install_debug_saves.bat                # just copy the existing JSON files
```
Saves go to `%APPDATA%\Godot\app_userdata\Tight Lines (Capstone Edition)\saves\`.
Loading a debug slot and then saving over it in-game replaces it. Re-run the installer to reset it.
