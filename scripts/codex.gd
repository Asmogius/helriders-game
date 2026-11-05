extends RefCounted
## The Database (pause menu): everything the player can meet, by category.
## An entry shows once the player has met it (Profile.is_discovered); until
## then it's censored. Parts and crew specialties are listed from parts.gd
## and crew.gd; the rest are written here.

const Parts := preload("res://scripts/parts.gd")
const Crew := preload("res://scripts/crew.gd")
const T := preload("res://scripts/tuning.gd")
const Layouts := preload("res://scripts/layouts.gd")

const CATEGORIES := ["parts", "crew", "enemies", "hazards", "places", "jobs"]
const CATEGORY_NAMES := {"parts": "PARTS", "crew": "CREW", "enemies": "ENEMIES", "hazards": "HAZARDS",
	"places": "PLACES", "jobs": "JOBS"}

const ENEMIES := [
	["shambler", "Shambler", "The bulk of every horde. Slow, weak alone, dangerous in a crowd that pins you against a wall."],
	["brute", "Brute", "Plated zombie. Its armor halves bullet damage, so ram it or burn it."],
	["tank", "Tank", "A huge zombie that soaks a magazine and leaves a scrap crate when it drops."],
	["boomer", "Boomer", "Bursts when killed and goops everything nearby: GOOPED rigs draw the whole horde."],
	["slimer", "Slimer", "Leaves a slime trail. Rigs that cross it lose grip and slide."],
	["hunter", "Hunter", "A fast leaper that latches onto your hull and chews through it. Scrape it off on a wall."],
	["outrider", "Outrider", "Light enemy flanker with twin forward guns. Makes strafing passes and loops back."],
	["bulwark", "Bulwark", "Heavy rammer with a near-solid front. Hit it in the sides or the rear."],
	["gunner", "Gunner Rig", "Holds 350-550 px off and works you over with a burst turret. Drive fast across its line."],
	["scrapper", "Scrapper", "Fast and unarmed. Weaves ahead of you laying oil and spike strips."],
	["scrapper_gunner", "Scrapper Gunner", "A tougher Scrapper with a weak turret that lays mines too."],
	["convoy", "Convoy Lead", "An armored semi with a ram, towing a turret trailer. Shoot the trailer off or wreck the cab."],
	["patcher", "Patcher", "Unarmed tow truck. Hooks an ally on a cable and repairs it, and brings wrecks back. Cut the cable."],
	["torcher", "Torcher", "Fire skirmisher with a flame nozzle. Its fuel tank is on the back: hit it there and it goes up."],
	["sludger", "Sludger", "Lobs acid and goop shells from long range. Close in and it backs off."],
	["elite", "Hunt Target", "A named enemy rig with every layer hardened. Its wreck always carries a schematic."],
]

const HAZARDS := [
	["barrel_explosive", "Explosive Barrel", "Blows for 60 damage and a hard shove. Lights oil."],
	["barrel_fire", "Fire Barrel", "Sets the ground burning for a few seconds."],
	["barrel_acid", "Acid Barrel", "Splashes acid: plates corrode and take more damage."],
	["barrel_slime", "Slime Barrel", "Spills a wide slime pool. Everything slides."],
	["barrel_boomer", "Boomer Barrel", "Goops everything nearby. The horde rushes whoever's covered."],
	["slime", "Slime", "Rigs on it lose grip; zombies wade through."],
	["bile", "Bile", "A Boomer's burst. It marks you for the horde."],
	["acid", "Acid Puddle", "Acid on the ground. Plates corrode while you sit in it."],
	["oil", "Oil Slick", "Slippery. Fire or an explosion lights it, and burning oil only hurts enemies."],
	["spikes", "Spike Strip", "Rigs crossing it slow down; zombies on it bleed."],
	["fire", "Burning Ground", "Builds BURNING on anything standing in it."],
	["status_shock", "STUNNED", "Shock buildup: no driving, firing or turning turrets for a moment."],
	["status_fire", "BURNING", "Fire buildup: damage over time that spreads between zombies."],
	["status_acid", "CORRODED", "Acid buildup: you take more damage for a while."],
	["status_toxic", "TOXIC", "Toxic buildup: eats HP down to a floor; a shield blocks it."],
	["status_slime", "SLICK", "Slime buildup: your grip drops and you slide."],
	["status_goop", "GOOPED", "Goop buildup: zombies nearby rush you, faster."],
]

const PLACE_TEXT := {
	"outer_blocks": "The edge of the safe zone. Low-threat jobs to learn the streets.",
	"midtown": "Collapsed offices and choked avenues. Tougher jobs, better salvage.",
	"industrial": "Rail yards and refineries. Rigs travel in numbers here.",
	"core": "The heart of the collapse. The worst jobs and the best parts.",
}


## [id, name, text] rows for a category.
static func entries(category: String) -> Array:
	var out: Array = []
	match category:
		"parts":
			for id: String in Parts.CATALOG:
				var p := Parts.get_part(id)
				out.append([id, str(p.name), "%s %s.  %s" % [str(p.rarity), str(p.category).to_lower(), _part_text(p)]])
		"crew":
			for role: String in Crew.CLASSES:
				for spec: String in Crew.SPECIALTIES[role]:
					var a: Dictionary = Crew.ABILITIES.get(spec, {})
					out.append([spec, "%s (%s)" % [str(a.get("name", spec)), str(Crew.ROLE_NAMES[role])], "Ability: %s." % str(a.get("ability", "-"))])
		"enemies":
			out = ENEMIES.duplicate()
		"hazards":
			out = HAZARDS.duplicate()
		"places":
			for d: Dictionary in T.DISTRICTS:
				out.append([str(d.id), str(d.name), "%s Jobs at %d-%d skulls." % [str(PLACE_TEXT.get(str(d.id), "")), int(d.skulls[0]), int(d.skulls[1])]])
			for id: String in Layouts.LAYOUTS:
				var l: Dictionary = Layouts.LAYOUTS[id]
				var jobs: Array = l.jobs
				var about := "A layout for %s jobs." % ", ".join(jobs.map(func(j: String) -> String: return str(T.MISSIONS[j].label).capitalize()))
				if jobs.is_empty():
					about = str(l.get("landmark", "A Quickplay canvas."))
				out.append(["map_" + id, "Map: %s" % str(l.name), about])
		"jobs":
			for type: String in T.MISSIONS:
				out.append([type, str(T.MISSIONS[type].label), str(T.MISSIONS[type].get("brief", ""))])
	return out


static func _part_text(p: Dictionary) -> String:
	var bits: Array[String] = []
	if p.has("power"):
		bits.append("Power %d" % int(p.power))
	if p.has("weight"):
		bits.append("weight %d" % int(p.weight))
	if p.has("ability"):
		bits.append("utility, every %d s" % int(p.get("cooldown", 0)))
	if float(p.get("bullet_damage", 0.0)) > 0.0:
		bits.append("%d damage a hit" % int(p.bullet_damage))
	if p.has("shield"):
		bits.append("shield %d" % int(p.shield))
	if p.has("armor"):
		bits.append("armor %d" % int(p.armor))
	return ", ".join(bits) + "."
