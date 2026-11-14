extends Control

# Replace these string values with the exact IDs from your GameDB .tres files
const ROD_IDS := {
	"light": "rod_light",
	"medium_light": "rod_medium_light",
	"medium": "rod_medium",
	"medium_heavy": "rod_medium_heavy",
	"heavy": "rod_heavy",
}

const BAIT_IDS := {
	"dough": "bait_dough",
	"worm": "bait_worm",
	"hardbait": "bait_hardbait",
	"shrimp": "bait_shrimp",
	"softbait": "bait_softbait",
	"topwater_lure": "bait_topwater_lure",
}


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	pass


# ============================================================================
# EQUIP HELPERS
# ============================================================================

func _equip_rod(rod_id: String) -> void:
	# SaveManager owns owned_rods and equipped_rod
	if not SaveManager.has_rod(rod_id):
		push_warning("InventoryUI: Cannot equip '%s' (rod not owned)." % rod_id)
		return

	if SaveManager.set_equipped_rod(rod_id):
		print("Equipped rod: ", rod_id)


func _equip_bait(bait_id: String) -> void:
	# InventoryManager checks if the player has at least 1 of this bait in the Tackle Box
	if not InventoryManager.has_item(bait_id, 1):
		push_warning("InventoryUI: Not enough '%s' in Tackle Box to equip." % bait_id)
		return

	# SaveManager stores equipped_bait
	if SaveManager.set_equipped_bait(bait_id):
		print("Equipped bait: ", bait_id)


# ============================================================================
# ROD BUTTON SIGNALS
# ============================================================================

func _on_light_rod_pressed() -> void:
	_equip_rod(ROD_IDS["light"])


func _on_medium_light_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium_light"])


func _on_medium_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium"])


func _on_medium_heavy_rod_pressed() -> void:
	_equip_rod(ROD_IDS["medium_heavy"])


func _on_heavy_rod_pressed() -> void:
	_equip_rod(ROD_IDS["heavy"])


# ============================================================================
# BAIT BUTTON SIGNALS
# ============================================================================

func _on_dough_pressed() -> void:
	_equip_bait(BAIT_IDS["dough"])


func _on_worm_pressed() -> void:
	_equip_bait(BAIT_IDS["worm"])


func _on_hardbait_pressed() -> void:
	_equip_bait(BAIT_IDS["hardbait"])


func _on_shrimp_pressed() -> void:
	_equip_bait(BAIT_IDS["shrimp"])


func _on_softbait_pressed() -> void:
	_equip_bait(BAIT_IDS["softbait"])


func _on_topwater_lure_pressed() -> void:
	_equip_bait(BAIT_IDS["topwater_lure"])


# ============================================================================
# UI NAVIGATION
# ============================================================================

func _on_back_button_pressed() -> void:
	visible = false
