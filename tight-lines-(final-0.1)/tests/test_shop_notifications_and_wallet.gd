extends SceneTree

const HUD_SCENE := "res://UIScenesAndScript/Shared/GameHUD.tscn"
const SHOP_SCENE := "res://UIScenesAndScript/RodShopUI/ShopUI.tscn"

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


func _reset_toasts(hud: Node) -> void:
	hud._toast_showing = false
	hud._toast_queue.clear()
	if hud._toast_panel != null:
		hud._toast_panel.visible = false


func _run() -> void:
	print("=== Shop Notifications & Wallet HUD Tests ===")

	var sm := root.get_node_or_null("SaveManager")
	var inv := root.get_node_or_null("InventoryManager")
	var db := root.get_node_or_null("GameDB")
	sm.new_game()
	inv.clear_all()

	var container := Control.new()
	root.add_child(container)

	var hud := (load(HUD_SCENE) as PackedScene).instantiate()
	var shop := (load(SHOP_SCENE) as PackedScene).instantiate()
	container.add_child(hud)
	container.add_child(shop)
	await process_frame

	# 1. GameHUD Wallet badge & texture
	var wallet_panel := hud.find_child("WalletPanel", true, false) as PanelContainer
	var wallet_icon := hud.find_child("WalletIcon", true, false) as TextureRect
	var wallet_label := hud.find_child("WalletLabel", true, false) as Label
	_check(wallet_panel != null, "GameHUD has WalletPanel")
	_check(wallet_icon != null and wallet_icon.texture != null, "GameHUD WalletIcon has loaded purse texture")
	_check(wallet_label != null and wallet_label.text == "₱0", "GameHUD WalletLabel starts at ₱0")

	sm.add_money(500)
	await process_frame
	_check(wallet_label != null and wallet_label.text == "₱500", "GameHUD WalletLabel updates to ₱500 on money_changed")
	_check(hud._toast_panel != null and hud._toast_panel.z_index >= 100, "GameHUD ToastBanner z_index >= 100")

	# 2. ShopUI TopBar removed
	_check(shop.find_child("TopBar", true, false) == null, "ShopUI TopBar is removed")

	# 3. Buy Rod notification
	_reset_toasts(hud)
	shop._rod_shop._buy_rod("rod_medium_light")
	await process_frame
	var rod_toast: String = hud.get_active_toast_text()
	_check(rod_toast.contains("Bought") and rod_toast.contains("Medium Light") and rod_toast.contains("-₱"),
		"Buying rod shows toast notification: %s" % rod_toast)

	# 4. Buy Bait notification
	_reset_toasts(hud)
	shop._bait_shop._buy_bait("bait_2")
	await process_frame
	var bait_toast: String = hud.get_active_toast_text()
	_check(bait_toast.contains("Bought") and bait_toast.contains("x5") and bait_toast.contains("-₱"),
		"Buying bait shows toast notification: %s" % bait_toast)

	# 5. Sell single fish & Sell All notifications
	var pool: Array = db.get_location_fish_pool("location_marikina")
	var fish_a: FishData = pool[0].fish
	inv.add_fish(fish_a.id, fish_a.avg_size)
	inv.add_fish(fish_a.id, fish_a.avg_size)
	await process_frame

	_reset_toasts(hud)
	var money_before_cancel: int = sm.get_money()
	shop._sell_fish_ui._on_fish_slot_pressed(0)
	await process_frame
	var confirm_overlay := shop._sell_fish_ui.find_child("SellConfirmOverlay", true, false) as ColorRect
	var confirm_ok := shop._sell_fish_ui.find_child("SellConfirmButton", true, false) as Button
	var confirm_cancel := shop._sell_fish_ui.find_child("SellCancelButton", true, false) as Button
	_check(confirm_overlay != null and confirm_overlay.visible, "Selling single fish opens confirmation prompt")
	_check(inv.get_used_slot_count(inv.FISH_BOX) == 2 and sm.get_money() == money_before_cancel,
		"Fish is not sold before confirming")
	confirm_cancel.pressed.emit()
	await process_frame
	_check(not confirm_overlay.visible and inv.get_used_slot_count(inv.FISH_BOX) == 2,
		"Cancelling confirmation keeps fish in FishBox")

	shop._sell_fish_ui._on_fish_slot_pressed(0)
	await process_frame
	confirm_ok.pressed.emit()
	await process_frame
	var sell_one_toast: String = hud.get_active_toast_text()
	_check(sell_one_toast.contains("Sold") and sell_one_toast.contains("+₱"),
		"Selling single fish shows toast notification: %s" % sell_one_toast)

	_reset_toasts(hud)
	shop._sell_fish_ui._on_sell_all_pressed()
	await process_frame
	_check(confirm_overlay.visible, "Sell All opens confirmation prompt")
	confirm_ok.pressed.emit()
	await process_frame
	var sell_all_toast: String = hud.get_active_toast_text()
	_check(sell_all_toast.contains("Sold") and sell_all_toast.contains("+₱"),
		"Selling all fish shows toast notification: %s" % sell_all_toast)

	# 6. EquippedRod & EquippedBait icons + translucent black backgrounds
	var eq_rod := hud.get_node_or_null("HUDButtons/LeftMenuColumn/EquippedRod") as TextureRect
	var eq_bait := hud.get_node_or_null("HUDButtons/LeftMenuColumn/EquippedBait") as TextureRect
	_check(eq_rod != null and eq_rod.texture == db.get_rod("rod_light").icon,
		"EquippedRod starts with rod_light icon")
	_check(eq_bait != null and eq_bait.texture == db.get_bait("bait_1").icon,
		"EquippedBait starts with bait_1 icon")

	for slot_node in [eq_rod, eq_bait]:
		var bg := slot_node.get_node_or_null("Background") as Panel if slot_node != null else null
		var sb := bg.get_theme_stylebox("panel") as StyleBoxFlat if bg != null else null
		_check(bg != null and bg.show_behind_parent and sb != null and sb.bg_color.r == 0.0 and sb.bg_color.g == 0.0 and sb.bg_color.b == 0.0 and sb.bg_color.a > 0.0 and sb.bg_color.a < 1.0,
			"%s has translucent black Background panel" % (slot_node.name if slot_node != null else "null"))

	sm.add_owned_rod("rod_heavy")
	sm.set_equipped_rod("rod_heavy")
	sm.set_equipped_bait("bait_3")
	await process_frame
	_check(eq_rod != null and eq_rod.texture == db.get_rod("rod_heavy").icon,
		"EquippedRod updates to rod_heavy icon on equipment_changed")
	_check(eq_bait != null and eq_bait.texture == db.get_bait("bait_3").icon,
		"EquippedBait updates to bait_3 icon on equipment_changed")

	container.queue_free()
	await process_frame
	print("=== Shop Notifications & Wallet HUD Tests Summary: %d passed, %d failed ===" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
