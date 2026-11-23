"""
Tight Lines - debug / demo save generator
=========================================
Builds ready-made save slots so the game can be demonstrated without
playing through the story first. Output matches SaveManager.gd
(SAVE_FORMAT_VERSION 1), InventoryManager.gd (v2) and QuestManager.gd (v1).

    python make_debug_saves.py            # writes slot_1.json + slot_2.json here
    python make_debug_saves.py --install  # also copies them into the game's saves folder

Slots are 0-based in code: slot_1.json = "Slot 2" in the menu, slot_2.json = "Slot 3".
Slot 1 (slot_0.json) is left alone so your normal save is never overwritten.
"""
import json
import os
import random
import shutil
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_SAVES = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata",
                          "Tight Lines (Capstone Edition)", "saves")

# ---------------------------------------------------------------------------
# Game data (copied from res://data/fish/*.tres and res://data/locations/*.tres)
# id: (size_class, min_size, avg_size, max_size, avg_weight)
# ---------------------------------------------------------------------------
FISH = {
    "fish_african_catfish": ("large", 40.0, 70.0, 140.0, 4.5),
    "fish_amberjack": ("large", 120.0, 155.0, 190.0, 80.0),
    "fish_archerfish": ("small", 10.0, 18.0, 30.0, 0.3),
    "fish_armored_catfish": ("medium", 15.0, 30.0, 50.0, 1.0),
    "fish_barramundi": ("large", 45.0, 75.0, 120.0, 5.2),
    "fish_bighead_carp": ("large", 50.0, 80.0, 140.0, 6.0),
    "fish_black_chin_tilapia": ("small", 10.0, 20.0, 30.0, 0.4),
    "fish_climbing_perch": ("small", 8.0, 15.0, 25.0, 0.2),
    "fish_clown_knife_fish": ("large", 40.0, 70.0, 100.0, 3.5),
    "fish_cobia": ("large", 75.0, 138.0, 200.0, 45.0),
    "fish_common_carp": ("medium", 25.0, 50.0, 85.0, 2.8),
    "fish_coral_grouper": ("large", 100.0, 170.0, 240.0, 100.0),
    "fish_crescent_grunter": ("medium", 20.0, 27.0, 35.0, 0.5),
    "fish_giant_snakehead": ("large", 35.0, 65.0, 130.0, 6.5),
    "fish_green_spotted_goby": ("small", 8.0, 16.0, 28.0, 0.25),
    "fish_juvenile_grouper": ("medium", 60.0, 90.0, 120.0, 7.5),
    "fish_juvenile_queenfish": ("medium", 25.0, 45.0, 65.0, 2.0),
    "fish_juvenile_trevally": ("small", 30.0, 45.0, 60.0, 1.5),
    "fish_ladyfish": ("medium", 25.0, 45.0, 75.0, 1.8),
    "fish_long_comb_sawfish": ("large", 100.0, 250.0, 400.0, 45.0),
    "fish_malabar_grouper": ("large", 75.0, 100.0, 235.0, 75.0),
    "fish_mangrove_red_snapper": ("medium", 40.0, 60.0, 80.0, 2.0),
    "fish_manila_catfish": ("medium", 20.0, 40.0, 70.0, 2.1),
    "fish_marlin": ("large", 170.0, 335.0, 500.0, 400.0),
    "fish_mayan_cichlid": ("small", 10.0, 22.0, 35.0, 0.45),
    "fish_milkfish": ("medium", 30.0, 55.0, 90.0, 3.0),
    "fish_moray_eel": ("medium", 100.0, 200.0, 300.0, 30.0),
    "fish_mosquito_fish": ("small", 3.0, 5.0, 7.0, 0.05),
    "fish_mozambique_tilapia": ("medium", 15.0, 30.0, 45.0, 1.1),
    "fish_mud_crab": ("medium", 12.0, 20.0, 35.0, 1.5),
    "fish_mullet": ("medium", 20.0, 38.0, 60.0, 1.4),
    "fish_needle_fish": ("small", 30.0, 60.0, 90.0, 3.0),
    "fish_nile_tilapia": ("medium", 15.0, 32.0, 50.0, 1.2),
    "fish_pangasius_catfish": ("large", 40.0, 75.0, 130.0, 5.5),
    "fish_queenfish": ("small", 60.0, 90.0, 120.0, 15.0),
    "fish_rohu_carp": ("medium", 25.0, 45.0, 75.0, 2.3),
    "fish_scatophagus_argus": ("small", 10.0, 20.0, 30.0, 0.5),
    "fish_sea_bream": ("medium", 25.0, 47.5, 70.0, 3.5),
    "fish_shad_fish": ("medium", 20.0, 35.0, 55.0, 1.3),
    "fish_silverperch": ("medium", 18.0, 32.0, 50.0, 1.2),
    "fish_snubnose_halfbeak": ("small", 12.0, 22.0, 32.0, 0.2),
    "fish_striped_pufferfish": ("small", 12.0, 25.0, 40.0, 0.8),
    "fish_striped_snakehead": ("medium", 20.0, 40.0, 75.0, 2.2),
    "fish_tank_goby": ("small", 10.0, 18.0, 30.0, 0.35),
    "fish_tarpon": ("large", 50.0, 110.0, 180.0, 15.0),
    "fish_three_spot_gourami": ("small", 6.0, 12.0, 18.0, 0.15),
    "fish_tiger_gourami": ("small", 10.0, 18.0, 25.0, 0.3),
    "fish_titan_triggerfish": ("medium", 40.0, 57.5, 75.0, 0.5),
    "fish_walking_catfish": ("small", 26.0, 36.0, 47.0, 0.8),
    "fish_yellowfin_tuna": ("large", 100.0, 167.5, 235.0, 0.5),
}

POOLS = {
    "marikina": ["fish_clown_knife_fish", "fish_armored_catfish", "fish_african_catfish",
                 "fish_walking_catfish", "fish_manila_catfish", "fish_pangasius_catfish",
                 "fish_nile_tilapia", "fish_black_chin_tilapia", "fish_common_carp",
                 "fish_bighead_carp", "fish_rohu_carp", "fish_mosquito_fish"],
    "imus": ["fish_striped_snakehead", "fish_giant_snakehead", "fish_african_catfish",
             "fish_three_spot_gourami", "fish_tiger_gourami", "fish_climbing_perch",
             "fish_mosquito_fish"],
    "kawit": ["fish_tarpon", "fish_black_chin_tilapia", "fish_manila_catfish", "fish_mullet",
              "fish_snubnose_halfbeak", "fish_mosquito_fish"],
    "fish_pens": ["fish_barramundi", "fish_nile_tilapia", "fish_black_chin_tilapia",
                  "fish_tarpon", "fish_milkfish", "fish_ladyfish"],
    "salt_farm": ["fish_ladyfish", "fish_tarpon", "fish_black_chin_tilapia",
                  "fish_mozambique_tilapia", "fish_mayan_cichlid", "fish_manila_catfish",
                  "fish_tank_goby", "fish_green_spotted_goby", "fish_barramundi", "fish_mullet",
                  "fish_mud_crab", "fish_mosquito_fish", "fish_shad_fish", "fish_silverperch"],
    "calatagan": ["fish_tarpon", "fish_ladyfish", "fish_milkfish", "fish_barramundi",
                  "fish_mangrove_red_snapper", "fish_juvenile_trevally", "fish_archerfish",
                  "fish_green_spotted_goby", "fish_tank_goby", "fish_crescent_grunter",
                  "fish_striped_pufferfish", "fish_juvenile_queenfish", "fish_mud_crab",
                  "fish_mullet"],
    "fortune_island": ["fish_needle_fish", "fish_queenfish", "fish_cobia", "fish_yellowfin_tuna",
                       "fish_malabar_grouper", "fish_coral_grouper", "fish_moray_eel",
                       "fish_amberjack", "fish_titan_triggerfish", "fish_tarpon",
                       "fish_long_comb_sawfish", "fish_sea_bream", "fish_marlin"],
}

ALL_RODS = ["rod_light", "rod_medium_light", "rod_medium", "rod_medium_heavy", "rod_heavy"]
ALL_BAIT = ["bait_1", "bait_2", "bait_3", "bait_4", "bait_5", "bait_6"]

MAIN_QUESTS = ["quest_gear_up", "quest_paddy_page", "quest_salt_and_sea", "quest_fenced_in",
               "quest_bright_water", "quest_roots", "quest_deep_giants"]
SIDE_QUESTS = ["quest_pocket_change", "quest_bait_tester", "quest_big_sea_catch",
               "quest_steady_hands", "quest_all_day_angler", "quest_rainy_catch",
               "quest_night_fisher"]

AREA_FLAGS = ["unlock_imus", "unlock_kawit", "unlock_fish_pens", "unlock_salt_farm",
              "unlock_cavite_complete", "unlock_calatagan", "unlock_fortune_island"]
# met_lolo_diary gates the "marikina_street" cutscene; saw_lolo_diary is set by 01_marikina.txt.
INTRO_FLAGS = ["met_lolo_diary", "saw_lolo_diary"]


def seen(*ids):
    return ["seen_" + i for i in ids]


def area_cutscenes(prefix):
    return [f"{prefix}_arrival", f"{prefix}_first_bite", f"{prefix}_first_catch",
            f"{prefix}_first_fail", f"{prefix}_complete"]


MARIKINA_CUTSCENES = ["marikina_room", "marikina_desk", "marikina_hallway", "marikina_street",
                      "marikina_arrival", "marikina_fishing_intro", "marikina_fishing_tutorial",
                      "marikina_phone_store", "marikina_duplicate_fish", "marikina_complete"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def weight_for(fish_id, size_cm):
    _, _, avg, _, avg_w = FISH[fish_id]
    return size_cm * avg_w / avg


def roll_size(rng, fish_id, lo=0.25, hi=0.97):
    _, mn, _, mx, _ = FISH[fish_id]
    return round(mn + (mx - mn) * rng.uniform(lo, hi), 1)


def build_records(rng, fish_ids):
    records = {}
    for fid in fish_ids:
        size = roll_size(rng, fid)
        records[fid] = {
            "count": rng.randint(1, 9),
            "best_size_cm": size,
            "best_weight_kg": round(weight_for(fid, size), 2),
        }
    return records


def build_inventory(rng, bait_counts, box_fish):
    items, uid = [], 1
    for bait_id, count in bait_counts.items():
        items.append({"uid": uid, "item_id": bait_id, "container": "tackle_box",
                      "count": count, "meta": {}})
        uid += 1
    for fid in box_fish:
        items.append({"uid": uid, "item_id": fid, "container": "fish_box", "count": 1,
                      "meta": {"size_cm": roll_size(rng, fid, 0.2, 0.9)}})
        uid += 1
    return {"version": 2, "next_uid": uid, "items": items}


def world_time(day, minutes, weather):
    h = minutes / 60.0
    if 5.0 <= h < 8.0:
        phase = "dawn"
    elif 8.0 <= h < 17.0:
        phase = "day"
    elif 17.0 <= h < 20.0:
        phase = "dusk"
    else:
        phase = "night"
    return {"day_count": day, "game_minutes": float(minutes), "time_of_day": phase,
            "weather": weather}


def ordered_unique(seq):
    out = []
    for x in seq:
        if x not in out:
            out.append(x)
    return out


def base_save(scene, money, flags, caught, records, rods, rod, bait, inventory, quests, wt):
    return {
        "version": 1,
        "timestamp": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
        "scene": scene,
        "difficulty": "casual",
        "money": money,
        "unlock_flags": flags,
        "owned_rods": rods,
        "caught_fish": caught,
        "fish_records": records,
        "equipped_rod": rod,
        "equipped_bait": bait,
        "inventory": inventory,
        "quests": quests,
        "world_time": wt,
    }


# ---------------------------------------------------------------------------
# Slot 2 (file slot_1.json): DEMO - late game, everything open, things left to show
# ---------------------------------------------------------------------------
def build_demo():
    rng = random.Random(2026)

    # Left uncaught on purpose so the demo can show a "NEW SPECIES" catch:
    #  - Marikina carps: catchable right next to home with Dough (bait_1) / Earthworm (bait_2)
    #  - Fortune Island exclusives (final area)
    demo_uncaught = {"fish_bighead_carp", "fish_common_carp", "fish_rohu_carp"}
    caught = ordered_unique(
        fid for area in ["marikina", "imus", "kawit", "fish_pens", "salt_farm", "calatagan"]
        for fid in POOLS[area] if fid not in demo_uncaught)

    flags = INTRO_FLAGS + AREA_FLAGS + seen(
        *MARIKINA_CUTSCENES,
        *area_cutscenes("imus"), *area_cutscenes("kawit"), *area_cutscenes("pen"),
        *area_cutscenes("salt"), *area_cutscenes("mangrove"))
    # island_* cutscenes and the ending are NOT marked seen -> Fortune Island story intro still plays.

    states = {q: "completed" for q in MAIN_QUESTS[:-1]}
    states["quest_deep_giants"] = "in_progress"            # 100% Almanac goal (final quest)
    states.update({q: "completed" for q in SIDE_QUESTS[:-1]})
    states["quest_night_fisher"] = "in_progress"           # 4/5 -> one catch at Fortune Island completes it
    quests = {"version": 1, "states": states, "progress": {"quest_night_fisher": 4},
              "pending_bait": {}, "pending_money": 0}

    inventory = build_inventory(
        rng, {b: 99 for b in ALL_BAIT},
        ["fish_nile_tilapia", "fish_nile_tilapia", "fish_black_chin_tilapia", "fish_mullet",
         "fish_milkfish", "fish_barramundi", "fish_tarpon", "fish_giant_snakehead"])

    return base_save(
        scene="overworld_spawn",               # Marikina City (home, shops nearby)
        money=5000,
        flags=flags,
        caught=caught,
        records=build_records(rng, caught),
        rods=list(ALL_RODS),
        rod="rod_medium_heavy",
        bait="bait_1",
        inventory=inventory,
        quests=quests,
        wt=world_time(12, 9 * 60, "clear"),
    )


# ---------------------------------------------------------------------------
# Slot 3 (file slot_2.json): ENDING - 100% Almanac, go home to trigger the ending
# ---------------------------------------------------------------------------
def build_ending():
    rng = random.Random(777)
    caught = list(FISH.keys())                             # every species -> Almanac 100%

    flags = INTRO_FLAGS + AREA_FLAGS + ["unlock_ending_home"] + seen(
        *MARIKINA_CUTSCENES,
        *area_cutscenes("imus"), *area_cutscenes("kawit"), *area_cutscenes("pen"),
        *area_cutscenes("salt"), *area_cutscenes("mangrove"), *area_cutscenes("island"))
    # ending_street / ending_hallway / ending_message_to_lolo NOT seen -> ending plays
    # when the player travels back to Marikina City (overworld_spawn).

    states = {q: "completed" for q in MAIN_QUESTS + SIDE_QUESTS}
    quests = {"version": 1, "states": states, "progress": {},
              "pending_bait": {}, "pending_money": 0}

    inventory = build_inventory(
        rng, {b: 99 for b in ALL_BAIT},
        ["fish_marlin", "fish_yellowfin_tuna", "fish_coral_grouper", "fish_tarpon"])

    return base_save(
        scene="overworld_island",              # Fortune Island; open the map -> Marikina City
        money=12000,
        flags=flags,
        caught=caught,
        records=build_records(rng, caught),
        rods=list(ALL_RODS),
        rod="rod_heavy",
        bait="bait_3",
        inventory=inventory,
        quests=quests,
        wt=world_time(30, 17 * 60 + 30, "clear"),   # 17:30 dusk
    )


def main():
    saves = {"slot_1.json": build_demo(), "slot_2.json": build_ending()}
    for name, data in saves.items():
        path = os.path.join(HERE, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=1)
        print(f"wrote {path}  ({len(data['caught_fish'])}/{len(FISH)} fish)")

    if "--install" in sys.argv:
        os.makedirs(GAME_SAVES, exist_ok=True)
        for name in saves:
            shutil.copyfile(os.path.join(HERE, name), os.path.join(GAME_SAVES, name))
            print(f"installed -> {os.path.join(GAME_SAVES, name)}")


if __name__ == "__main__":
    main()
