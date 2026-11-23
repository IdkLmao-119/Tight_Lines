extends SceneTree

const FishingManagerScript := preload("res://AutoloadFolders/FishingManager/FishingManager.gd")

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
		print("[FAIL] ", label)


func _run() -> void:
	print("=== Bite Speed Unit Tests ===")
	var fm: Node = FishingManagerScript.new()

	_check(is_equal_approx(fm.bite_delay_min, 90.0), "bite_delay_min is 90.0s (1.5 min)")
	_check(is_equal_approx(fm.bite_delay_max, 90.0), "bite_delay_max is 90.0s (1.5 min)")

	# Weather multipliers (at hour 9 where general = 1.00)
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 9), 1.00), "clear weather = 1.00")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "cloudy", 9), 1.20), "cloudy weather = 1.20")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "rain", 9), 1.30), "rain weather = 1.30")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "rainy", 9), 1.30), "rainy weather = 1.30")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "storm", 9), 0.80), "storm weather = 0.80")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "unknown", 9), 1.00), "unknown weather falls back to 1.00")

	# General hourly curve spot checks (clear weather = 1.00)
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 0), 0.80), "general hour 0 = 0.80")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 6), 1.40), "general hour 6 = 1.40")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 12), 0.75), "general hour 12 = 0.75")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 18), 1.45), "general hour 18 = 1.45")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "clear", 23), 0.85), "general hour 23 = 0.85")

	# Nocturnal hourly curve spot checks (clear weather = 1.00)
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "clear", 0), 1.50), "nocturnal hour 0 = 1.50")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "clear", 6), 0.80), "nocturnal hour 6 = 0.80")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "clear", 12), 0.35), "nocturnal hour 12 = 0.35")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "clear", 18), 0.90), "nocturnal hour 18 = 0.90")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "clear", 23), 1.45), "nocturnal hour 23 = 1.45")

	# Combined weather * time (higher = faster)
	_check(is_equal_approx(fm.get_bite_speed_multiplier(false, "rain", 18), 1.30 * 1.45), "rain + general hour 18 = 1.885")
	_check(is_equal_approx(fm.get_bite_speed_multiplier(true, "storm", 12), 0.80 * 0.35), "storm + nocturnal hour 12 = 0.28")

	fm.free()
	print("Summary: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
