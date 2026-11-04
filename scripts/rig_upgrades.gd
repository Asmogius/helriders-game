extends RefCounted
## The rig upgrade tracks (Fabrication Discount, Loot Quality, Salvage Yield):
## which keys they are and the "now / next" line shown beside each. Display
## only: costs, levels and buying stay in profile.gd (upgrade_level,
## upgrade_cost, buy_upgrade), numbers in tuning.gd (T.UPGRADES). Shown on the
## Research screen's RIG UPGRADES view and the garage's UPGRADES overlay.

const T := preload("res://scripts/tuning.gd")

const KEYS: Array[String] = ["fabrication", "loot", "salvage"]


## What `key` does at its current level, and at the next one unless maxed.
static func effect_text(profile: Node, key: String) -> String:
	var level: int = profile.upgrade_level(key)
	var step: float = T.UPGRADES[key].per_level
	var next := level + 1
	var max_level: int = (T.UPGRADES[key].costs as Array).size()
	var now_text := ""
	var next_text := ""
	match key:
		"fabrication":
			now_text = "Parts cost %d%% less" % roundi(step * level * 100.0)
			next_text = "%d%%" % roundi(step * next * 100.0)
		"loot":
			now_text = "Outrider schematic drop chance %d%%" % roundi(float(profile.schematic_chance()) * 100.0)
			next_text = "%d%%" % roundi(minf(T.SCHEMATIC_DROP_CHANCE + step * next, 0.95) * 100.0)
		"salvage":
			now_text = "Scrap from kills +%d%%" % roundi(step * level * 100.0)
			next_text = "+%d%%" % roundi(step * next * 100.0)
	return now_text if level >= max_level else "%s    (next: %s)" % [now_text, next_text]
