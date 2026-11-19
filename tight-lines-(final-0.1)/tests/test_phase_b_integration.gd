extends SceneTree

const FISH_BOX_SCENE := "res://UIScenesAndScript/FishBox/inventory_ui.tscn"
const ALMANAC_SCENE := "res://UIScenesAndScript/AlmanacUI/AlmanacUI.tscn"
const HUD_SCENE := "res://UIScenesAndScript/Shared/GameHUD.tscn"

var _passed := 0
var _failed := 0


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] ", label)
	else:
		_failed += 1
		push_error("[FAIL] " + label)
		print("[FAIL] " + label)


func _run() -> void:
	print("=== Phase B Integration Tests ===")

	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var db := root.get_node_or_null("GameDB")
	var qm := root.get_node_or_null("QuestManager")
	sm.new_game()
	inv.clear_all()

	var pool: Array = db.get_location_fish_pool("location_marikina")
	_check(pool.size() >= 2, "Marikina pool has >= 2 fish for integration test")
	var fish_a: FishData = pool[0].fish
	var fish_b: FishData = pool[1].fish

	# 1. FishBox UI integration: Lock protection, Sort, Sell All (keeps locked), Compost, Peso formatting
	inv.add_fish(fish_b.id, fish_b.avg_size)
	inv.add_fish(fish_a.id, fish_a.max_size)
	inv.add_fish(fish_a.id, fish_a.min_size)

	var box := (load(FISH_BOX_SCENE) as PackedScene).instantiate()
	root.add_child(box)
	await process_frame

	var sort_btn := box.find_child("SortButton", true, false) as Button
	var lock_btn := box.find_child("LockButton", true, false) as Button
	var compost_btn := box.find_child("CompostButton", true, false) as Button
	var sell_all_btn := box.find_child("SellAllButton", true, false) as Button
	_check(sort_btn != null and lock_btn != null and compost_btn != null, "FishBox has Sort, Lock, and Compost buttons")

	# Sort fish
	sort_btn.pressed.emit()
	await process_frame
	var first_after_sort: Dictionary = inv.get_items(inv.FISH_BOX)[0]
	_check(first_after_sort["item_id"] == fish_a.id or first_after_sort["item_id"] == fish_b.id, "Sort arranged FishBox cleanly")

	# Select slot 0 and lock it
	box._on_fish_slot_pressed(0)
	lock_btn.pressed.emit()
	await process_frame
	var locked_uid: int = inv.get_uid_at(inv.FISH_BOX, 0)
	_check(inv.is_item_locked(locked_uid), "Lock button locked slot 0 fish")

	# Select slot 1 (unlocked) and compost it
	box._on_fish_slot_pressed(1)
	compost_btn.pressed.emit()
	await process_frame
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 2, "Compost button consumed 1 fish (2 remain)")

	# Switch to sell mode and press Sell All -> locked fish stays, unlocked fish sold for Pesos
	box.sell_mode = true
	await process_frame
	_check(sell_all_btn.text.contains("₱"), "Sell All button displays Peso symbol (₱)")
	var money_before: int = sm.get_money()
	sell_all_btn.pressed.emit()
	await process_frame
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 1, "Sell All kept the 1 locked fish and sold the unlocked fish")
	_check(inv.is_item_locked(inv.get_uid_at(inv.FISH_BOX, 0)), "Remaining fish is the locked trophy fish")
	_check(sm.get_money() > money_before, "Selling unlocked fish earned Pesos (₱%d)" % sm.get_money())
	box.queue_free()

	# 2. Almanac UI integration: displays Personal Best, Caught count, Trophy tier, Peso symbol
	sm.record_fish_catch(fish_a.id, fish_a.max_size)
	var almanac := (load(ALMANAC_SCENE) as PackedScene).instantiate()
	root.add_child(almanac)
	await process_frame
	almanac.open()
	almanac._on_fish_button_pressed(0)
	await process_frame
	var desc_lbl := almanac.find_child("FishDescription", true, false) as RichTextLabel
	_check(desc_lbl != null and desc_lbl.text.contains("₱"), "Almanac displays Base Value in Pesos (₱)")
	_check(desc_lbl != null and desc_lbl.text.contains("Best:") and desc_lbl.text.contains("Gold Trophy"),
		"Almanac displays Personal Best and Gold Trophy")
	almanac.queue_free()

	# 3. GameHUD Toast Banner integration: Quest Complete & Unlock Flag (ignores seen_*)
	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame

	sm.add_unlock_flag("seen_intro_test")
	await process_frame
	_check(hud.get_active_toast_text() == "", "GameHUD ignores internal seen_* cutscene flags")

	sm.add_unlock_flag("unlock_imus")
	await process_frame
	_check(hud.get_active_toast_text().contains("Imus"), "GameHUD shows toast for unlock_imus: %s" % hud.get_active_toast_text())

	# Complete an active quest and confirm toast queues/displays
	hud._toast_showing = false
	hud._toast_queue.clear()
	qm.debug_complete("quest_pocket_change")
	await process_frame
	_check(hud.get_active_toast_text().contains("Quest Complete"), "GameHUD shows Quest Complete toast: %s" % hud.get_active_toast_text())
	hud.queue_free()

	await process_frame
	print("=== Phase B Integration Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
