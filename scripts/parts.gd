extends RefCounted
## Part definitions. Placeholder until the Garage lands: parts can drop and be
## extracted, but nothing equips them yet. Rarity names match DESIGN §4.

const RARITY_COLORS := {
	"Common": Color(0.75, 0.75, 0.72),
	"Uncommon": Color(0.4, 0.85, 0.45),
	"Rare": Color(0.35, 0.6, 1.0),
	"Epic": Color(0.75, 0.45, 1.0),
	"Legendary": Color(1.0, 0.72, 0.25),
}

# What an Outrider can drop when you wreck it.
const OUTRIDER_DROPS := [
	{"name": "Outrider Twin Guns", "category": "Weapon", "rarity": "Uncommon"},
	{"name": "Outrider Light Plating", "category": "Armor", "rarity": "Uncommon"},
	{"name": "Outrider Sport Wheels", "category": "Drive", "rarity": "Uncommon"},
]


static func describe(part: Dictionary) -> String:
	return "%s (%s %s)" % [part.name, part.rarity, part.category]


static func color_of(part: Dictionary) -> Color:
	return RARITY_COLORS.get(part.rarity, Color.WHITE)
