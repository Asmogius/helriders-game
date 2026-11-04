extends RefCounted
## Crew (DESIGN §6): who rides the rig. Numbers were approved by the owner in
## the "Helriders: Crew Draft" and "Helriders: Crew Expansion Draft" docs;
## don't change them without asking.
##
## A crew member is a plain dictionary (it goes in the save file):
##   id          unique number in this save
##   name        "Mae Voss"
##   role        the class: driver, gunner, mechanic, spotter, engineer,
##               medic, scavenger, bruiser
##   specialty   rolled at hire; decides the triggered ability (SPECIALTIES)
##   rarity      "Common" .. "Mythic"; sets the level cap, the base passive
##               and the ability's strength
##   xp          total XP earned (a job's skulls, split among the crew on it)
##   perks       perk ids picked so far (one every 3rd level)
##   perk_offer  the 3 perks on offer while a pick is waiting
##   rest        days left resting at the Inn after an injury (0 = fit)
##   seated      riding the rig
##
## compute_mods() turns a crew (and any active abilities) into one set of
## modifiers. The Garage stat sheet and vehicle.gd both use it, so they agree.

const T := preload("res://scripts/tuning.gd")
const Parts := preload("res://scripts/parts.gd")

const RARITIES := ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]
const MAX_LEVEL := [5, 8, 11, 14, 17, 20]
const PERK_LEVELS := [3, 6, 9, 12, 15, 18]
const MYTHIC_COLOR := Color(1.0, 0.36, 0.42)

# Every class, in seat order. Driver and Gunner have their own seats; the rest
# take a frame's open seats, one of each class aboard.
const CLASSES := ["driver", "gunner", "mechanic", "spotter", "engineer", "medic", "scavenger", "bruiser"]
const OPEN_CLASSES := ["mechanic", "spotter", "engineer", "medic", "scavenger", "bruiser"]
const ROLES := ["driver", "gunner"]   # the free Common hires at the Saloon
const ROLE_NAMES := {
	"driver": "Driver", "gunner": "Gunner", "mechanic": "Mechanic", "spotter": "Spotter",
	"engineer": "Engineer", "medic": "Medic", "scavenger": "Scavenger", "bruiser": "Bruiser",
}
const ROLE_COLORS := {
	"driver": Color(0.25, 0.82, 0.88), "gunner": Color(1.0, 0.85, 0.55), "mechanic": Color(0.45, 0.9, 0.5),
	"spotter": Color(0.95, 0.4, 0.35), "engineer": Color(0.95, 0.85, 0.35), "medic": Color(0.95, 0.95, 0.95),
	"scavenger": Color(0.93, 0.6, 0.25), "bruiser": Color(0.7, 0.55, 0.45),
}

# --- Passives ----------------------------------------------------------------------
# Lists are indexed by rarity (Common first), at level 1; every level after
# adds the per_level amount.
const DRIVER := {
	"turn": [0.04, 0.06, 0.08, 0.10, 0.12, 0.14],      # turn rate bonus
	"grip": [0.3, 0.5, 0.7, 0.9, 1.1, 1.3],            # added grip
	"turn_per_level": 0.01,
	"grip_per_level": 0.1,
	# Hard Line (Wheelman): sharper steering and grip, Epic+ adds top speed.
	"hl_turn": [0.30, 0.30, 0.35, 0.35, 0.40, 0.40],
	"hl_grip": [3.0, 3.0, 3.5, 3.5, 4.0, 4.0],
	"hl_speed": [0.0, 0.0, 0.0, 0.15, 0.20, 0.25],
	"hl_time": [3.0, 3.5, 4.0, 4.5, 5.0, 5.5],
	"hl_cooldown": [22.0, 20.0, 18.0, 16.0, 15.0, 14.0],
}
const GUNNER := {
	"spread": [0.10, 0.15, 0.20, 0.25, 0.30, 0.35],    # less spread, every weapon
	"aim": [0.05, 0.08, 0.10, 0.12, 0.15, 0.18],       # faster turret aim
	"lock": [0.0, 0.0, 0.0, 0.10, 0.15, 0.20],         # Epic+: longer lock range
	"spread_per_level": 0.01,
	"aim_per_level": 0.01,
	# Overcharge (Gunslinger): fire rate and damage.
	"oc_fire": [0.40, 0.45, 0.50, 0.55, 0.60, 0.70],
	"oc_damage": [0.20, 0.25, 0.30, 0.35, 0.40, 0.45],
	"oc_time": [5.0, 5.0, 6.0, 6.0, 7.0, 7.0],
	"oc_cooldown": [25.0, 23.0, 20.0, 19.0, 18.0, 16.0],
}
# The six newer classes: [key, values by rarity, per level].
const PASSIVES := {
	"mechanic": [["taken", [0.04, 0.05, 0.06, 0.07, 0.08, 0.09], 0.0025]],
	"spotter": [["util_cd", [0.08, 0.10, 0.12, 0.14, 0.16, 0.18], 0.005]],
	"engineer": [["power", [0.05, 0.07, 0.09, 0.11, 0.13, 0.15], 0.005]],
	"medic": [["injury", [0.15, 0.20, 0.25, 0.30, 0.35, 0.40], 0.01]],
	"scavenger": [["scrap", [0.10, 0.15, 0.20, 0.25, 0.30, 0.35], 0.01], ["schematic", [0.02, 0.03, 0.04, 0.05, 0.06, 0.07], 0.0]],
	"bruiser": [["ram", [0.10, 0.15, 0.20, 0.25, 0.30, 0.35], 0.01], ["ram_taken", [0.10, 0.13, 0.16, 0.19, 0.22, 0.25], 0.005]],
}

# --- Specialties and their triggered abilities --------------------------------------
const SPECIALTIES := {
	"driver": ["wheelman", "speedster", "bootlegger"],
	"gunner": ["gunslinger", "marksman", "breacher", "demolisher"],
	"mechanic": ["patcher", "gearhead"],
	"spotter": ["marker", "scout", "jammer"],
	"engineer": ["conduit", "tinkerer"],
	"medic": ["field_medic", "poisoner"],
	"scavenger": ["magpie", "salvager"],
	"bruiser": ["bracer", "breaker", "wrangler"],
}
# Common numbers. Each rarity above Common adds 10% to `effect` and to the
# duration and takes 1 s off the cooldown. `fixed` numbers don't scale.
# Hard Line and Overcharge use the DRIVER / GUNNER tables instead.
const ABILITIES := {
	"wheelman": {"name": "Wheelman", "ability": "Hard Line", "kind": "hard_line"},
	"speedster": {"name": "Speedster", "ability": "Floor It", "kind": "floor_it", "time": 3.0, "cooldown": 20.0,
		"effect": {"speed": 0.35, "accel": 0.5}},
	"bootlegger": {"name": "Bootlegger", "ability": "Bootleg Turn", "kind": "bootleg", "time": 0.0, "cooldown": 10.0},
	"gunslinger": {"name": "Gunslinger", "ability": "Overcharge", "kind": "overcharge"},
	"marksman": {"name": "Marksman", "ability": "Deadeye", "kind": "deadeye", "time": 5.0, "cooldown": 22.0,
		"effect": {"bullet_speed": 0.5, "damage": 0.25}},
	"breacher": {"name": "Breacher", "ability": "Piercing Rounds", "kind": "piercing", "time": 5.0, "cooldown": 24.0,
		"effect": {"pierce": 3.0}},
	"patcher": {"name": "Patcher", "ability": "Field Repair", "kind": "field_repair", "time": 0.0, "cooldown": 28.0,
		"effect": {"heal": 30.0}, "fixed": {"epic_dr": 0.3, "epic_time": 3.0}},
	"welder_old": {"name": "Welder", "ability": "Weld Plates", "kind": "weld", "time": 4.0, "cooldown": 25.0,
		"effect": {"dr": 0.5}},
	"marker": {"name": "Marker", "ability": "Mark", "kind": "mark", "time": 6.0, "cooldown": 20.0,
		"effect": {"vuln": 0.3}},
	"scout": {"name": "Scout", "ability": "Flare", "kind": "flare", "time": 5.0, "cooldown": 24.0,
		"effect": {"slow": 0.4, "vuln": 0.2}, "fixed": {"radius": 600.0}},
	"overclocker_old": {"name": "Overclocker", "ability": "Overclock", "kind": "overclock", "time": 4.0, "cooldown": 25.0,
		"effect": {"speed": 0.2, "accel": 0.2}},
	# DESIGN §14 specialty changes (ability numbers agreed; proposal 01 §0).
	"gearhead": {"name": "Gearhead", "ability": "Tune-Up", "kind": "tune_up", "time": 6.0, "cooldown": 22.0,
		"effect": {"speed": 0.15, "fire": 0.15}},
	"conduit": {"name": "Conduit", "ability": "Power Divert", "kind": "power_divert", "time": 6.0, "cooldown": 24.0},
	"poisoner": {"name": "Poisoner", "ability": "Miasma", "kind": "miasma", "time": 6.0, "cooldown": 22.0,
		"fixed": {"radius": 250.0, "buildup": 25.0}},
	"tinkerer": {"name": "Tinkerer", "ability": "Scrap Drones", "kind": "scrap_drones", "time": 10.0, "cooldown": 26.0,
		"fixed": {"drones": 2, "drone_hp": 20.0, "drone_damage": 4.0, "drone_rate": 3.0}},
	# Retired by the §14 rework (old saves map onto the new ones; see RENAMED).
	"tinkerer_reroute": {"name": "Tinkerer", "ability": "Reroute", "kind": "reroute", "time": 0.0, "cooldown": 30.0,
		"effect": {"cut": 0.5}},
	"field_medic": {"name": "Field Medic", "ability": "Field Dressing", "kind": "field_dressing", "time": 0.0, "cooldown": 40.0},
	"combat_medic_old": {"name": "Combat Medic", "ability": "Stim", "kind": "stim", "time": 6.0, "cooldown": 30.0,
		"effect": {"passive": 0.5}},
	"magpie": {"name": "Magpie", "ability": "Magnet", "kind": "magnet", "time": 0.0, "cooldown": 20.0,
		"fixed": {"radius": 900.0}},
	"salvager": {"name": "Salvager", "ability": "Gold Rush", "kind": "gold_rush", "time": 6.0, "cooldown": 30.0,
		"effect": {"bonus": 2.0}},
	"bracer": {"name": "Bracer", "ability": "Brace", "kind": "brace", "time": 3.0, "cooldown": 20.0,
		"effect": {"dr": 0.6, "ram": 0.5}},
	"breaker": {"name": "Breaker", "ability": "Shockwave", "kind": "shockwave", "time": 0.0, "cooldown": 18.0,
		"effect": {"damage": 40.0}, "fixed": {"radius": 150.0}},
	# Content proposal 01 (approved by the owner 2026-11-03).
	"demolisher": {"name": "Demolisher", "ability": "Cook Off", "kind": "cook_off", "time": 5.0, "cooldown": 24.0,
		"effect": {"fire_rider": 0.5}, "fixed": {"barrel_mult": 1.5}},
	"jammer": {"name": "Jammer", "ability": "Static Burst", "kind": "static_burst", "time": 4.0, "cooldown": 26.0,
		"effect": {"shock_buildup": 60.0}, "fixed": {"radius": 450.0, "shield_off": 1.0}},
	"wrangler": {"name": "Wrangler", "ability": "Chain Drag", "kind": "chain_drag", "time": 3.0, "cooldown": 22.0,
		"effect": {"ram": 0.4}, "fixed": {"latch_range": 260.0}},
}
# Specialty injury penalties (proposal 01), on top of the class's own.
const SPECIALTY_INJURY := {
	"demolisher": {"spread": 1.3},     # fixed weapons spread +30%
	"jammer": {"util_cd": 1.15},       # utility cooldowns +15%
	"wrangler": {"ram": 0.8},          # ram dealt -20%
}
const MAX_DAMAGE_REDUCTION := 0.9

# --- Perks ---------------------------------------------------------------------------
const SHARED_PERKS := ["veteran", "quick_hands", "endurance", "tough"]
const CLASS_PERKS := {
	"driver": ["drift_king", "lead_foot", "road_warrior", "crash_test"],
	"gunner": ["steady_aim", "hot_barrels", "big_game", "long_barrel"],
	"mechanic": ["reinforced", "quick_fix", "salvage_plating", "hardened"],
	"spotter": ["long_eyes", "pathfinder", "weak_spot", "mine_expert"],
	"engineer": ["efficient", "lightweight", "turbocharger", "capacitor"],
	"medic": ["triage", "morale", "steady", "calm"],
	"scavenger": ["haggler", "sharp_eye", "packrat", "strip_mine"],
	"bruiser": ["spikes", "thick_skull", "plow", "shake_it_off"],
}
const PERKS := {
	"veteran": ["Veteran", "Passive +25%"],
	"quick_hands": ["Quick Hands", "Ability cooldown -20%"],
	"endurance": ["Endurance", "Ability lasts 30% longer"],
	"tough": ["Tough", "Half as likely to be the one injured; rests 1 day less"],
	"drift_king": ["Drift King", "Grip +0.8"],
	"lead_foot": ["Lead Foot", "Top speed +6%"],
	"road_warrior": ["Road Warrior", "Ram damage +15%"],
	"crash_test": ["Crash Test", "Wall crash damage -50%"],
	"steady_aim": ["Steady Aim", "Spread -15%"],
	"hot_barrels": ["Hot Barrels", "Fire rate +8%"],
	"big_game": ["Big Game", "+15% damage to Hunters and enemy rigs"],
	"long_barrel": ["Long Barrel", "Bullet range +15%"],
	"reinforced": ["Reinforced", "Max armor +10%"],
	"quick_fix": ["Quick Fix", "Emergency Patch heals +50%"],
	"salvage_plating": ["Salvage Plating", "Each enemy rig wreck restores 15 armor"],
	"hardened": ["Hardened", "Latched Hunter damage -50%"],
	"long_eyes": ["Long Eyes", "Lock range +15%"],
	"pathfinder": ["Pathfinder", "Courier par times +10%"],
	"weak_spot": ["Weak Spot", "Marked or flared targets take +10% more"],
	"mine_expert": ["Mine Expert", "Mines +30% damage"],
	"efficient": ["Efficient", "Power draw -8%"],
	"lightweight": ["Lightweight", "Weight capacity +10%"],
	"turbocharger": ["Turbocharger", "Acceleration +8%"],
	"capacitor": ["Capacitor", "Utility cooldowns -10%"],
	"triage": ["Triage", "Injured crew rest 1 day less"],
	"morale": ["Morale", "Other crew's passives +10%"],
	"steady": ["Steady", "Crew injured mid-fight keep half their passive"],
	"calm": ["Calm", "A big hit needs 20% of max armor, not 15%"],
	"haggler": ["Haggler", "Saloon prices -10% while on your roster"],
	"sharp_eye": ["Sharp Eye", "Schematic odds +5 points"],
	"packrat": ["Packrat", "Scrap caches +50%"],
	"strip_mine": ["Strip Mine", "Enemy rig kill scrap +50%"],
	"spikes": ["Spikes", "Ram damage +15%"],
	"thick_skull": ["Thick Skull", "Ram damage taken -15%"],
	"plow": ["Plow", "Driving through shamblers doesn't slow you"],
	"shake_it_off": ["Shake It Off", "Any ram throws off latched Hunters"],
}

# Tiered specialty perks (DESIGN §14 first-draft table; numbers from content
# proposal 01 §3.1 / §2.4, approved 2026-11-03). Picks 1-2 are Minor, 3-4
# Major, 5-6 Signature; each pick offers 3 from that tier's 2 specialty perks
# plus the 4 shared perks, no repeats. Rarity's level cap decides how many
# picks a member ever gets (Common Minor 3 only ... Mythic all six).
# Every specialty is tiered now; the class perks stay valid for old saves.
const PERK_TIER_OF_PICK := ["minor", "minor", "major", "major", "signature", "signature"]
const SPECIALTY_PERKS := {
	"wheelman": {"minor": ["sp_long_line", "sp_sure_footing"], "major": ["sp_clean_exit", "sp_threading"], "signature": ["sp_immovable_line", "sp_racing_line"]},
	"speedster": {"minor": ["sp_deep_tank", "sp_quick_fuse"], "major": ["sp_battering_speed", "sp_open_road"], "signature": ["sp_afterburn", "sp_clean_run"]},
	"bootlegger": {"minor": ["sp_tight_swing", "sp_shake_off"], "major": ["sp_tail_swipe", "sp_about_face"], "signature": ["sp_double_back", "sp_oil_spin"]},
	"gunslinger": {"minor": ["sp_hot_barrels", "sp_quick_draw"], "major": ["sp_bottomless", "sp_red_hot"], "signature": ["sp_siphon", "sp_full_auto"]},
	"marksman": {"minor": ["sp_steady_aim", "sp_deep_breath"], "major": ["sp_plate_splitter", "sp_called_shot"], "signature": ["sp_opening_shot", "sp_executioner"]},
	"breacher": {"minor": ["sp_long_burn", "sp_deeper_cuts"], "major": ["sp_overpenetration", "sp_bleed_through"], "signature": ["sp_rail_line", "sp_acid_core"]},
	"patcher": {"minor": ["sp_spare_parts", "sp_quick_wrench"], "major": ["sp_kickstart", "sp_fresh_weld"], "signature": ["sp_full_rebuild", "sp_hull_patch"]},
	"marker": {"minor": ["sp_lingering_mark", "sp_quick_spot"], "major": ["sp_exposed", "sp_pass_it_on"], "signature": ["sp_weak_point", "sp_shutdown"]},
	"scout": {"minor": ["sp_bright_flare", "sp_slow_fade"], "major": ["sp_pinned", "sp_magnesium"], "signature": ["sp_signal_flare", "sp_flashbang"]},
	"field_medic": {"minor": ["sp_clean_bandage", "sp_quick_kit"], "major": ["sp_back_in_it", "sp_second_kit"], "signature": ["sp_full_recovery", "sp_last_breath"]},
	"magpie": {"minor": ["sp_wide_pull", "sp_sticky_fingers"], "major": ["sp_scrap_plating", "sp_snatch"], "signature": ["sp_shrapnel_storm", "sp_second_look"]},
	"salvager": {"minor": ["sp_long_haul", "sp_quick_count"], "major": ["sp_bounty", "sp_strip_mine"], "signature": ["sp_jackpot", "sp_safe_deposit"]},
	"bracer": {"minor": ["sp_firm_stance", "sp_quick_set"], "major": ["sp_shell", "sp_counterweight"], "signature": ["sp_juggernaut", "sp_absorb"]},
	"breaker": {"minor": ["sp_wider_blast", "sp_quick_reset"], "major": ["sp_live_wire", "sp_clear_out"], "signature": ["sp_aftershock", "sp_payback"]},
	"demolisher": {"minor": ["sp_long_fuse", "sp_quick_strike"], "major": ["sp_chain_reaction", "sp_shrapnel"], "signature": ["sp_powder_keg", "sp_fire_discipline"]},
	"jammer": {"minor": ["sp_wide_band", "sp_quick_tune"], "major": ["sp_lingering_static", "sp_blind_spot"], "signature": ["sp_blackout", "sp_feedback_loop"]},
	"gearhead": {"minor": ["sp_fine_tuning", "sp_spare_time"], "major": ["sp_tight_servos", "sp_clean_lines"], "signature": ["sp_crew_tune", "sp_afterglow"]},
	"conduit": {"minor": ["sp_clean_routing", "sp_capacitor"], "major": ["sp_insulated_feed", "sp_spillover"], "signature": ["sp_arc_feedback", "sp_grid_priority"]},
	"tinkerer": {"minor": ["sp_longer_leash", "sp_spare_rotors"], "major": ["sp_third_wheel", "sp_bait_drones"], "signature": ["sp_kamikaze", "sp_copycat"]},
	"poisoner": {"minor": ["sp_thick_fumes", "sp_quick_vent"], "major": ["sp_lingering_cloud", "sp_caustic_gas"], "signature": ["sp_contagion", "sp_neurotoxin"]},
	"wrangler": {"minor": ["sp_long_chain", "sp_quick_throw"], "major": ["sp_hogtie", "sp_slingshot"], "signature": ["sp_bulldog", "sp_two_hooks"]},
}
# Numeric effects on the ability (applied in ability()): time_add (s),
# time_mult, cd_mult, or "add": {ability key: amount}. Perks not listed here
# are rules the game checks with has_perk().
const SPECIALTY_PERK_FX := {
	"sp_long_line": {"time_mult": 1.2}, "sp_deep_tank": {"time_mult": 1.2}, "sp_quick_fuse": {"cd_mult": 0.85},
	"sp_battering_speed": {"add": {"battering": 0.3}},
	"sp_tight_swing": {"cd_mult": 0.85},
	"sp_hot_barrels": {"time_add": 1.0}, "sp_quick_draw": {"cd_mult": 0.85}, "sp_red_hot": {"add": {"red_hot": 0.3}},
	"sp_steady_aim": {"time_add": 1.0}, "sp_deep_breath": {"cd_mult": 0.85},
	"sp_long_burn": {"time_add": 1.0}, "sp_deeper_cuts": {"add": {"pierce": 1.0}},
	"sp_spare_parts": {"add_mult": {"heal": 1.2}}, "sp_quick_wrench": {"cd_mult": 0.85},
	"sp_lingering_mark": {"time_add": 2.0}, "sp_quick_spot": {"cd_mult": 0.85},
	"sp_bright_flare": {"add": {"radius": 100.0}}, "sp_slow_fade": {"time_add": 2.0},
	"sp_quick_kit": {"cd_mult": 0.85},
	"sp_wide_pull": {"add": {"radius": 200.0}}, "sp_sticky_fingers": {"cd_mult": 0.85},
	"sp_long_haul": {"time_add": 2.0}, "sp_quick_count": {"cd_mult": 0.85},
	"sp_firm_stance": {"time_add": 1.0}, "sp_quick_set": {"cd_mult": 0.85},
	"sp_wider_blast": {"add": {"radius": 50.0}}, "sp_quick_reset": {"cd_mult": 0.85},
	"sp_long_fuse": {"time_add": 1.0}, "sp_quick_strike": {"cd_mult": 0.85},
	"sp_wide_band": {"add": {"radius": 75.0}}, "sp_quick_tune": {"cd_mult": 0.85}, "sp_lingering_static": {"add": {"jam_add": 2.0}},
	"sp_long_chain": {"add": {"latch_range": 80.0}}, "sp_quick_throw": {"cd_mult": 0.85},
	"sp_fine_tuning": {"time_add": 1.0}, "sp_spare_time": {"cd_mult": 0.85}, "sp_tight_servos": {"add": {"servos": 1.0}},
	"sp_clean_routing": {"time_add": 1.0}, "sp_capacitor": {"cd_mult": 0.85}, "sp_grid_priority": {"add": {"grid": 1.0}},
	"sp_longer_leash": {"time_add": 2.0}, "sp_spare_rotors": {"cd_mult": 0.85},
	"sp_thick_fumes": {"time_add": 2.0}, "sp_quick_vent": {"cd_mult": 0.85}, "sp_caustic_gas": {"add": {"caustic": 1.0}},
	"sp_full_auto": {"add": {"full_auto": 1.0}}, "sp_threading": {"add": {"threading": 1.0}},
	"sp_live_wire": {}, "sp_clean_bandage": {},
}
const SPECIALTY_PERK_NAMES := {
	"sp_long_line": ["Long Line", "Hard Line +20% duration"], "sp_sure_footing": ["Sure Footing", "SLICK builds 50% slower during Hard Line"],
	"sp_clean_exit": ["Clean Exit", "Ending a DRIFT during it takes 1 s off cooldown"], "sp_threading": ["Threading", "Shamblers brushed aside without slowing you"],
	"sp_immovable_line": ["Immovable Line", "No shoves from Tank or Bulwark during it"], "sp_racing_line": ["Racing Line", "Each near-miss shot extends it 0.5 s"],
	"sp_deep_tank": ["Deep Tank", "Floor It +20% duration"], "sp_quick_fuse": ["Quick Fuse", "Floor It cooldown -15%"],
	"sp_battering_speed": ["Battering Speed", "RAMs +30% during Floor It"], "sp_open_road": ["Open Road", "Above 80% top speed, restore 1% max armor/s to the most damaged facing (max 20% per mission)"],
	"sp_afterburn": ["Afterburn", "Burning trail 50 px wide, 3 s, 20 fire buildup/s"], "sp_clean_run": ["Clean Run", "No HP/armor lost during it: refund 50% of cooldown"],
	"sp_tight_swing": ["Tight Swing", "Bootleg Turn cooldown -15%"], "sp_shake_off": ["Shake Off", "Throws off a latched Hunter"],
	"sp_tail_swipe": ["Tail Swipe", "Rear counts as a RAM at 60% of front ram while swinging"], "sp_about_face": ["About Face", "Fixed guns +25% for 2 s after"],
	"sp_double_back": ["Double Back", "2 charges"], "sp_oil_spin": ["Oil Spin", "Enemy-only oil ring, 120 px, 8 s"],
	"sp_hot_barrels": ["Hot Barrels", "Overcharge +1 s"], "sp_quick_draw": ["Quick Draw", "Overcharge cooldown -15%"],
	"sp_bottomless": ["Bottomless", "No ammo use or heat during Overcharge"], "sp_red_hot": ["Red Hot", "During Overcharge, 30% of each shot's damage as fire"],
	"sp_siphon": ["Siphon", "10% of damage dealt refills shield, max 40 per activation"], "sp_full_auto": ["Full Auto", "Turrets turn 2x fast, no spread"],
	"sp_steady_aim": ["Steady Aim", "Deadeye +1 s"], "sp_deep_breath": ["Deep Breath", "Deadeye cooldown -15%"],
	"sp_plate_splitter": ["Plate Splitter", "+30% damage to armor during Deadeye"], "sp_called_shot": ["Called Shot", "+50% vs MARKED"],
	"sp_opening_shot": ["Opening Shot", "3x on the first shot, once per activation"], "sp_executioner": ["Executioner", "Wrecks rigs below 10% HP on a stripped facing hit"],
	"sp_long_burn": ["Long Burn", "Piercing Rounds +1 s"], "sp_deeper_cuts": ["Deeper Cuts", "Pierce 4"],
	"sp_overpenetration": ["Overpenetration", "+10% per target passed"], "sp_bleed_through": ["Bleed-Through", "20% of armor hits go to HP"],
	"sp_rail_line": ["Rail Line", "Pierces 1 rig"], "sp_acid_core": ["Acid Core", "Pierced targets take acid, build CORRODED"],
	"sp_spare_parts": ["Spare Parts", "Field Repair +20%"], "sp_quick_wrench": ["Quick Wrench", "Field Repair cooldown -15%"],
	"sp_kickstart": ["Kickstart", "Skips the shield recharge delay"], "sp_fresh_weld": ["Fresh Weld", "Repaired facing -20% damage for 4 s"],
	"sp_full_rebuild": ["Full Rebuild", "Once per mission, fully restores a stripped facing"], "sp_hull_patch": ["Hull Patch", "Also restores 5% max HP"],
	"sp_lingering_mark": ["Lingering Mark", "Mark +2 s"], "sp_quick_spot": ["Quick Spot", "Mark cooldown -15%"],
	"sp_exposed": ["Exposed", "MARKED shields stop recharging"], "sp_pass_it_on": ["Pass It On", "Mark jumps on kill"],
	"sp_weak_point": ["Weak Point", "+50% to HP on a MARKED rig's stripped facing"], "sp_shutdown": ["Shutdown", "MARKED rigs can't use abilities for 3 s"],
	"sp_bright_flare": ["Bright Flare", "Flare +100 px"], "sp_slow_fade": ["Slow Fade", "Flare +2 s"],
	"sp_pinned": ["Pinned", "Hunters inside can't pounce"], "sp_magnesium": ["Magnesium", "Flare burns: 15 fire buildup/s inside"],
	"sp_signal_flare": ["Signal Flare", "Rigs inside become MARKED"], "sp_flashbang": ["Flashbang", "Ignition stuns zombies inside 1.5 s"],
	"sp_clean_bandage": ["Clean Bandage", "Half rest days"], "sp_quick_kit": ["Quick Kit", "Field Dressing cooldown -15%"],
	"sp_back_in_it": ["Back in It", "Treated crew's ability ready"], "sp_second_kit": ["Second Kit", "2 charges"],
	"sp_full_recovery": ["Full Recovery", "No rest days"], "sp_last_breath": ["Last Breath", "Once per mission, HP floors at 1, 1 s invulnerable"],
	"sp_wide_pull": ["Wide Pull", "Magnet +200 px"], "sp_sticky_fingers": ["Sticky Fingers", "Magnet cooldown -15%"],
	"sp_scrap_plating": ["Scrap Plating", "2 armor per salvage pulled, cap 30 per mission"], "sp_snatch": ["Snatch", "Steals a wreck's crate before a revive"],
	"sp_shrapnel_storm": ["Shrapnel Storm", "Pulled salvage damages enemies"], "sp_second_look": ["Second Look", "Pulled rig crate rolls twice"],
	"sp_long_haul": ["Long Haul", "Gold Rush +2 s"], "sp_quick_count": ["Quick Count", "Gold Rush cooldown -15%"],
	"sp_bounty": ["Bounty", "+10 scrap per rig wreck"], "sp_strip_mine": ["Strip Mine", "1 scrap per 40 armor dealt, cap 25"],
	"sp_jackpot": ["Jackpot", "Rig wrecks always drop a schematic"], "sp_safe_deposit": ["Safe Deposit", "Gold Rush scrap survives a wreck"],
	"sp_firm_stance": ["Firm Stance", "Brace +1 s"], "sp_quick_set": ["Quick Set", "Brace cooldown -15%"],
	"sp_shell": ["Shell", "No splash spill during Brace"], "sp_counterweight": ["Counterweight", "25% heavier in collisions"],
	"sp_juggernaut": ["Juggernaut", "RAMs don't slow you, rigs go flying"], "sp_absorb": ["Absorb", "Releases 50% of blocked damage as a 150 px shock wave"],
	"sp_wider_blast": ["Wider Blast", "Shockwave +50 px"], "sp_quick_reset": ["Quick Reset", "Shockwave cooldown -15%"],
	"sp_live_wire": ["Live Wire", "Shockwave deals shock"], "sp_clear_out": ["Clear Out", "Hurls zombies, throws off a Hunter"],
	"sp_aftershock": ["Aftershock", "A 50% wave after 1 s"], "sp_payback": ["Payback", "+50% of damage taken in the last 3 s, cap +60"],
	"sp_long_fuse": ["Long Fuse", "Cook Off +1 s"], "sp_quick_strike": ["Quick Strike", "Cook Off cooldown -15%"],
	"sp_chain_reaction": ["Chain Reaction", "Barrels set off during it also ignite oil 200 px"], "sp_shrapnel": ["Shrapnel", "BURST weapons' last round splashes 40 px"],
	"sp_powder_keg": ["Powder Keg", "Wrecks during it explode like a Fire barrel"], "sp_fire_discipline": ["Fire Discipline", "BURNING enemies take +15% from all your hits"],
	"sp_wide_band": ["Wide Band", "Static Burst +75 px"], "sp_quick_tune": ["Quick Tune", "Static Burst cooldown -15%"],
	"sp_lingering_static": ["Lingering Static", "Shields stay down +2 s"], "sp_blind_spot": ["Blind Spot", "STUNNED rigs become MARKED 3 s"],
	"sp_blackout": ["Blackout", "Patcher hooks pop and can't re-hook 5 s"], "sp_feedback_loop": ["Feedback Loop", "OVERLOADed enemy weapons overheat instantly"],
	"sp_long_chain": ["Long Chain", "Chain Drag +80 px"], "sp_quick_throw": ["Quick Throw", "Chain Drag cooldown -15%"],
	"sp_hogtie": ["Hogtie", "Dragged rig's turn rate -50%"], "sp_slingshot": ["Slingshot", "Releasing at speed flings it; RAM damage on wall impact"],
	"sp_fine_tuning": ["Fine Tuning", "Tune-Up +1 s"], "sp_spare_time": ["Spare Time", "Tune-Up cooldown -15%"],
	"sp_tight_servos": ["Tight Servos", "Turrets +25% turn, LOCK +10% during Tune-Up"], "sp_clean_lines": ["Clean Lines", "Status buildup drains 2x during Tune-Up"],
	"sp_crew_tune": ["Crew Tune", "Tune-Up halves other crew cooldowns"], "sp_afterglow": ["Afterglow", "Boosts fade linearly over 4 s"],
	"sp_clean_routing": ["Clean Routing", "Power Divert +1 s"], "sp_capacitor": ["Capacitor", "Power Divert cooldown -15%"],
	"sp_insulated_feed": ["Insulated Feed", "Shield status bonus doubled"], "sp_spillover": ["Spillover", "Half the leftover bonus shield goes to armor, cap 30"],
	"sp_arc_feedback": ["Arc Feedback", "Shield hits put 30 shock on the shooter (0.5 s per attacker)"], "sp_grid_priority": ["Grid Priority", "Utility cooldowns 2x during Power Divert"],
	"sp_longer_leash": ["Longer Leash", "Scrap Drones +2 s"], "sp_spare_rotors": ["Spare Rotors", "Scrap Drones cooldown -15%"],
	"sp_third_wheel": ["Third Wheel", "3 drones"], "sp_bait_drones": ["Bait Drones", "Zombies prefer drones"],
	"sp_kamikaze": ["Kamikaze", "Expiring drones dive and explode: 25 dmg, 60 px each"], "sp_copycat": ["Copycat", "Drones use your weapon's damage type and keywords"],
	"sp_thick_fumes": ["Thick Fumes", "Miasma +2 s"], "sp_quick_vent": ["Quick Vent", "Miasma cooldown -15%"],
	"sp_lingering_cloud": ["Lingering Cloud", "The cloud stays 4 s after Miasma"], "sp_caustic_gas": ["Caustic Gas", "Also builds CORRODED"],
	"sp_contagion": ["Contagion", "TOXIC zombies burst: 120 px, 40 toxic buildup"], "sp_neurotoxin": ["Neurotoxin", "TOXIC rigs -25% speed, half turret turn"],
	"sp_bulldog": ["Bulldog", "Drag reels to 120 px, then a free RAM"], "sp_two_hooks": ["Two Hooks", "2 charges"],
}
# Specialty perks with a number behind them (proposal §3.1) that the game reads.
const FIRE_DISCIPLINE := 0.15

const FIRST_NAMES := ["Mae", "Jo", "Rook", "Tess", "Cal", "Dez", "Wren", "Hank", "Ivy", "Bo",
	"Nash", "Rae", "Cole", "Lux", "Pike", "Sol", "Vera", "Gus", "Juno", "Kit", "Moss", "Dell"]
const LAST_NAMES := ["Voss", "Kade", "Rusk", "Hale", "Crane", "Mott", "Pryor", "Stack", "Vance", "Dunn",
	"Grit", "Holt", "Marsh", "Quill", "Reyes", "Slade", "Thorn", "Wick", "Yates", "Zell", "Barrow", "Coil"]


## A new level-1 crew member (no id yet; the Profile assigns one). The
## specialty is rolled unless given.
static func make(role: String, rarity: String, rng: RandomNumberGenerator, specialty := "") -> Dictionary:
	var first: String = FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)]
	var last: String = LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)]
	if specialty == "":
		var options: Array = SPECIALTIES[role]
		specialty = str(options[rng.randi_range(0, options.size() - 1)])
	return {"id": 0, "name": "%s %s" % [first, last], "role": role, "specialty": specialty, "rarity": rarity,
		"xp": 0.0, "perks": [], "perk_offer": [], "rest": 0, "seated": false}


static func rarity_index(member: Dictionary) -> int:
	return maxi(RARITIES.find(str(member.get("rarity", "Common"))), 0)


static func max_level(member: Dictionary) -> int:
	return int(MAX_LEVEL[rarity_index(member)])


## XP it takes to go from `level` to the next: 4, 6, 8... up to 14.
static func xp_step(level: int) -> int:
	return mini(2 + 2 * level, 14)


## Total XP needed to reach `level`.
static func xp_for_level(level: int) -> int:
	var total := 0
	for k in range(1, level):
		total += xp_step(k)
	return total


static func level(member: Dictionary) -> int:
	var xp := float(member.get("xp", 0.0))
	var cap := max_level(member)
	var lv := 1
	while lv < cap and xp >= xp_for_level(lv + 1):
		lv += 1
	return lv


## 0..1 progress toward the next level (1 at the cap).
static func level_progress(member: Dictionary) -> float:
	var lv := level(member)
	if lv >= max_level(member):
		return 1.0
	var into := float(member.xp) - xp_for_level(lv)
	return clampf(into / xp_step(lv), 0.0, 1.0)


static func role_name(member: Dictionary) -> String:
	return str(ROLE_NAMES.get(str(member.get("role", "")), "Crew"))


static func role_color(member: Dictionary) -> Color:
	return ROLE_COLORS.get(str(member.get("role", "")), Color.WHITE)


static func color_of(member: Dictionary) -> Color:
	var rarity := str(member.get("rarity", "Common"))
	if rarity == "Mythic":
		return MYTHIC_COLOR
	return Parts.RARITY_COLORS.get(rarity, Color.WHITE)


# §14 renames: Welder -> Gearhead, Overclocker -> Conduit, Combat Medic -> Poisoner.
const RENAMED := {"welder": "gearhead", "overclocker": "conduit", "combat_medic": "poisoner"}


static func specialty(member: Dictionary) -> String:
	var options: Array = SPECIALTIES.get(str(member.get("role", "")), [])
	var s := str(member.get("specialty", ""))
	s = str(RENAMED.get(s, s))
	if options.has(s):
		return s
	return str(options[0]) if not options.is_empty() else ""


static func specialty_name(member: Dictionary) -> String:
	return str(ABILITIES.get(specialty(member), {}).get("name", ""))


static func ability_name(member: Dictionary) -> String:
	return str(ABILITIES.get(specialty(member), {}).get("ability", ""))


static func describe(member: Dictionary) -> String:
	return "%s  %s %s  L%d" % [member.name, member.rarity, role_name(member), level(member)]


static func has_perk(member: Dictionary, perk: String) -> bool:
	return (member.get("perks", []) as Array).has(perk)


## Passive modifiers at the member's level (keys depend on the class).
static func passive(member: Dictionary) -> Dictionary:
	var r := rarity_index(member)
	var steps := level(member) - 1
	var out := {}
	match str(member.role):
		"driver":
			out = {
				"turn": float(DRIVER.turn[r]) + float(DRIVER.turn_per_level) * steps,
				"grip": float(DRIVER.grip[r]) + float(DRIVER.grip_per_level) * steps,
			}
		"gunner":
			out = {
				"spread": float(GUNNER.spread[r]) + float(GUNNER.spread_per_level) * steps,
				"aim": float(GUNNER.aim[r]) + float(GUNNER.aim_per_level) * steps,
				"lock": float(GUNNER.lock[r]),
			}
		_:
			for entry: Array in PASSIVES.get(str(member.role), []):
				out[entry[0]] = float(entry[1][r]) + float(entry[2]) * steps
	if has_perk(member, "veteran"):
		for key: String in out:
			out[key] = float(out[key]) * 1.25
	return out


## The triggered ability: kind, time, cooldown and its numbers, with rarity
## and the member's perks applied.
static func ability(member: Dictionary) -> Dictionary:
	var r := rarity_index(member)
	var spec := specialty(member)
	var data: Dictionary = ABILITIES.get(spec, {})
	var out := {"kind": str(data.get("kind", "")), "name": str(data.get("ability", ""))}
	match spec:
		"wheelman":
			out.merge({"time": float(DRIVER.hl_time[r]), "cooldown": float(DRIVER.hl_cooldown[r]),
				"turn": float(DRIVER.hl_turn[r]), "grip": float(DRIVER.hl_grip[r]), "speed": float(DRIVER.hl_speed[r])})
		"gunslinger":
			out.merge({"time": float(GUNNER.oc_time[r]), "cooldown": float(GUNNER.oc_cooldown[r]),
				"fire": float(GUNNER.oc_fire[r]), "damage": float(GUNNER.oc_damage[r])})
		_:
			var scale := 1.0 + 0.1 * r
			out.time = float(data.get("time", 0.0)) * scale
			out.cooldown = maxf(float(data.get("cooldown", 10.0)) - r, 1.0)
			var effect: Dictionary = data.get("effect", {})
			for key: String in effect:
				out[key] = float(effect[key]) * scale
			out.merge(data.get("fixed", {}))
			if spec == "patcher":
				out.epic = r >= 3
	for p: String in member.get("perks", []):
		var fx: Dictionary = SPECIALTY_PERK_FX.get(p, {})
		if fx.is_empty():
			continue
		out.time = float(out.get("time", 0.0)) * float(fx.get("time_mult", 1.0)) + float(fx.get("time_add", 0.0))
		out.cooldown = float(out.cooldown) * float(fx.get("cd_mult", 1.0))
		var add: Dictionary = fx.get("add", {})
		for k: String in add:
			out[k] = float(out.get(k, 0.0)) + float(add[k])
		var mult: Dictionary = fx.get("add_mult", {})
		for k: String in mult:
			if out.has(k):
				out[k] = float(out[k]) * float(mult[k])
	if has_perk(member, "quick_hands"):
		out.cooldown = float(out.cooldown) * 0.8
	if has_perk(member, "endurance"):
		out.time = float(out.time) * 1.3
	return out


## One line on what the member does, for cards: the passive, then the ability.
static func summary(member: Dictionary) -> String:
	var p := passive(member)
	var a := ability(member)
	var bits: Array[String] = []
	match str(member.role):
		"driver":
			bits.append("TURN +%d%%  GRIP +%.1f" % [_pct(p.turn), float(p.grip)])
		"gunner":
			var lock := "  LOCK +%d%%" % _pct(p.lock) if float(p.lock) > 0.0 else ""
			bits.append("SPREAD -%d%%  AIM +%d%%%s" % [_pct(p.spread), _pct(p.aim), lock])
		"mechanic":
			bits.append("DAMAGE TAKEN -%s%%" % _pct1(p.taken))
		"spotter":
			bits.append("UTILITY COOLDOWNS -%s%%" % _pct1(p.util_cd))
		"engineer":
			bits.append("POWER OUTPUT +%s%%" % _pct1(p.power))
		"medic":
			bits.append("CREW INJURY CHANCE -%d%%" % _pct(p.injury))
		"scavenger":
			bits.append("KILL SCRAP +%d%%  SCHEMATIC +%d PTS" % [_pct(p.scrap), _pct(p.schematic)])
		"bruiser":
			bits.append("RAM +%d%%  RAM TAKEN -%s%%" % [_pct(p.ram), _pct1(p.ram_taken)])
	var timing := ("%s s, every %d s" % [_secs(float(a.time)), roundi(float(a.cooldown))]) if float(a.time) > 0.0 else "every %d s" % roundi(float(a.cooldown))
	bits.append("%s  %s" % [str(a.name).to_upper(), timing])
	return "    ".join(bits)


static func _pct(v: Variant) -> int:
	return roundi(float(v) * 100.0)


static func _pct1(v: Variant) -> String:
	var x := float(v) * 100.0
	return str(roundi(x)) if absf(x - roundf(x)) < 0.05 else "%.1f" % x


static func _secs(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


# --- Perk picks ---------------------------------------------------------------------

static func perk_pool(member: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append_array(SHARED_PERKS)
	var tiers: Dictionary = SPECIALTY_PERKS.get(specialty(member), {})
	if tiers.is_empty():
		for p: String in CLASS_PERKS.get(str(member.role), []):
			out.append(p)
	else:
		for tier: String in ["minor", "major", "signature"]:
			for p: String in tiers[tier]:
				out.append(p)
	return out


## Every perk id a save may hold for this member: the current pool plus the
## old class perks (picked before perks were tiered; they keep working).
static func perk_known(member: Dictionary) -> Array[String]:
	var out := perk_pool(member)
	for p: String in CLASS_PERKS.get(str(member.role), []):
		if not out.has(p):
			out.append(p)
	return out


## The tier of the member's next pick ("minor", "major", "signature").
static func next_tier(member: Dictionary) -> String:
	var n := (member.get("perks", []) as Array).size()
	return str(PERK_TIER_OF_PICK[mini(n, PERK_TIER_OF_PICK.size() - 1)])


## What a pick offers before the 3 are drawn: the shared perks plus, for a
## tiered specialty, that tier's 2 specialty perks.
static func tier_pool(member: Dictionary) -> Array[String]:
	var tiers: Dictionary = SPECIALTY_PERKS.get(specialty(member), {})
	if tiers.is_empty():
		return perk_pool(member)
	var out: Array[String] = []
	out.append_array(SHARED_PERKS)
	for p: String in tiers[next_tier(member)]:
		out.append(p)
	return out


## Picks earned (every 3rd level) and not yet taken.
static func perks_due(member: Dictionary) -> int:
	var lv := level(member)
	var earned := 0
	for at: int in PERK_LEVELS:
		if lv >= at:
			earned += 1
	return maxi(earned - (member.get("perks", []) as Array).size(), 0)


## 3 random perks the member doesn't have yet (fewer if the pool runs dry).
## Seeded by the member and how many picks they've made, so the offer stays
## the same until they choose.
static func roll_perk_offer(member: Dictionary) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-perk-%d-%d" % [int(member.get("id", 0)), (member.get("perks", []) as Array).size()])
	var left: Array[String] = []
	for p in tier_pool(member):
		if not has_perk(member, p):
			left.append(p)
	var out: Array[String] = []
	while out.size() < 3 and not left.is_empty():
		out.append(left.pop_at(rng.randi_range(0, left.size() - 1)))
	return out


static func perk_name(perk: String) -> String:
	return str(PERKS.get(perk, SPECIALTY_PERK_NAMES.get(perk, [perk, ""]))[0])


static func perk_text(perk: String) -> String:
	return str(PERKS.get(perk, SPECIALTY_PERK_NAMES.get(perk, ["", ""]))[1])


# --- Seats ----------------------------------------------------------------------------

## Seats a frame offers, in seat order (parts.gd "seats"): "driver",
## "gunner" and "open".
static func seats_for(loadout: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var chassis := Parts.get_part(str(loadout.get("chassis", "")))
	for seat: String in chassis.get("seats", []):
		out.append(seat)
	return out


static func open_seats(loadout: Dictionary) -> int:
	return seats_for(loadout).count("open")


# --- Modifiers ------------------------------------------------------------------------

static func base_mods() -> Dictionary:
	return {
		"turn": 1.0, "grip": 0.0, "speed": 1.0, "accel": 1.0,
		"aim": 1.0, "spread": 1.0, "lock": 1.0, "fire": 1.0, "damage": 1.0, "bullet_speed": 1.0, "pierce": 0,
		"taken": 1.0, "ram": 1.0, "ram_taken": 1.0, "wall": 1.0, "latch": 1.0, "armor": 1.0,
		"util_cd": 1.0, "patch": 1.0, "repair": 1.0, "mine": 1.0,
		"power": 1.0, "draw": 1.0, "weight_cap": 1.0, "ignore_overload": false,
		"injury": 1.0, "immune": false, "big_hit": T.CREW_BIG_HIT, "triage": false,
		"big_game": 1.0, "weak_spot": 0.0, "par": 1.0,
		"scrap": 1.0, "rig_scrap": 1.0, "schematic": 0.0, "cache": 1.0,
		"plow": false, "shake_off": false, "salvage_plating": false,
	}


## A runtime entry for compute_mods(): the member's class, passive and perks.
static func entry(member: Dictionary) -> Dictionary:
	return {"role": str(member.role), "specialty": specialty(member), "passive": passive(member),
		"perks": (member.get("perks", []) as Array).duplicate(), "injured": false}


## Everything a crew does to the rig, as one set of modifiers. `entries` come
## from entry() (vehicle.gd adds "injured"); `active` maps ability kind to its
## numbers while it runs.
static func compute_mods(entries: Array, active: Dictionary = {}) -> Dictionary:
	var m := base_mods()
	var morale := false
	var steady := false
	for e: Dictionary in entries:
		if str(e.role) == "medic" and not bool(e.injured):
			morale = morale or (e.perks as Array).has("morale")
			steady = steady or (e.perks as Array).has("steady")
	var stim := 1.0 + float(active.stim.passive) if active.has("stim") else 1.0
	for e: Dictionary in entries:
		var role := str(e.role)
		var scale := 1.0
		if bool(e.injured):
			scale = 0.5 if steady else 0.0
		else:
			if morale and role != "medic":
				scale *= 1.1
			scale *= stim
		_apply_passive(m, role, e.passive, scale)
		if bool(e.injured):
			_apply_injury(m, role)
			var hurt: Dictionary = SPECIALTY_INJURY.get(str(e.get("specialty", "")), {})
			for key: String in hurt:
				m[key] = float(m[key]) * float(hurt[key])
		else:
			for perk: String in e.perks:
				_apply_perk(m, perk)
	_apply_active(m, active)
	m.taken = maxf(float(m.taken), 1.0 - MAX_DAMAGE_REDUCTION)
	return m


static func _apply_passive(m: Dictionary, role: String, p: Dictionary, scale: float) -> void:
	if scale <= 0.0:
		return
	match role:
		"driver":
			m.turn *= 1.0 + float(p.turn) * scale
			m.grip += float(p.grip) * scale
		"gunner":
			m.spread *= 1.0 - float(p.spread) * scale
			m.aim *= 1.0 + float(p.aim) * scale
			m.lock *= 1.0 + float(p.lock) * scale
		"mechanic":
			m.taken *= 1.0 - float(p.taken) * scale
		"spotter":
			m.util_cd *= 1.0 - float(p.util_cd) * scale
		"engineer":
			m.power *= 1.0 + float(p.power) * scale
		"medic":
			m.injury *= 1.0 - float(p.injury) * scale
		"scavenger":
			m.scrap *= 1.0 + float(p.scrap) * scale
			m.schematic += float(p.schematic) * scale
		"bruiser":
			m.ram *= 1.0 + float(p.ram) * scale
			m.ram_taken *= 1.0 - float(p.ram_taken) * scale


## What an injured crew member costs the rig for the rest of the run.
static func _apply_injury(m: Dictionary, role: String) -> void:
	match role:
		"driver":
			m.turn *= T.CREW_INJURED_MULT
		"gunner":
			m.aim *= T.CREW_INJURED_MULT
		"mechanic":
			m.repair *= 0.5
		"spotter":
			m.util_cd *= 1.5
		"engineer":
			m.power *= 0.8
		"medic":
			m.injury *= 1.5
		"scavenger":
			m.scrap *= 0.5
		"bruiser":
			m.ram_taken *= 1.5


static func _apply_perk(m: Dictionary, perk: String) -> void:
	match perk:
		"drift_king":
			m.grip += 0.8
		"lead_foot":
			m.speed *= 1.06
		"road_warrior", "spikes":
			m.ram *= 1.15
		"crash_test":
			m.wall *= 0.5
		"steady_aim":
			m.spread *= 0.85
		"hot_barrels":
			m.fire *= 1.08
		"big_game":
			m.big_game *= 1.15
		"long_barrel":
			m.bullet_speed *= 1.15
		"reinforced":
			m.armor *= 1.1
		"quick_fix":
			m.patch *= 1.5
		"salvage_plating":
			m.salvage_plating = true
		"hardened":
			m.latch *= 0.5
		"long_eyes":
			m.lock *= 1.15
		"pathfinder":
			m.par *= 1.1
		"weak_spot":
			m.weak_spot += 0.1
		"mine_expert":
			m.mine *= 1.3
		"efficient":
			m.draw *= 0.92
		"lightweight":
			m.weight_cap *= 1.1
		"turbocharger":
			m.accel *= 1.08
		"capacitor":
			m.util_cd *= 0.9
		"triage":
			m.triage = true
		"calm":
			m.big_hit = maxf(float(m.big_hit), 0.20)
		"sharp_eye":
			m.schematic += 0.05
		"packrat":
			m.cache *= 1.5
		"strip_mine":
			m.rig_scrap *= 1.5
		"thick_skull":
			m.ram_taken *= 0.85
		"plow":
			m.plow = true
		"shake_it_off":
			m.shake_off = true


static func _apply_active(m: Dictionary, active: Dictionary) -> void:
	for kind: String in active:
		var a: Dictionary = active[kind]
		match kind:
			"hard_line":
				if float(a.get("threading", 0.0)) > 0.0:
					m.plow = true   # Threading: shamblers don't slow you
				m.turn *= 1.0 + float(a.turn)
				m.grip += float(a.grip)
				m.speed *= 1.0 + float(a.speed)
			"floor_it":
				m.speed *= 1.0 + float(a.speed)
				m.accel *= 1.0 + float(a.accel)
				m.ram *= 1.0 + float(a.get("battering", 0.0))   # Battering Speed perk
			"overcharge":
				m.fire *= 1.0 + float(a.fire)
				m.damage *= 1.0 + float(a.damage)
				if float(a.get("full_auto", 0.0)) > 0.0:   # Full Auto perk
					m.aim *= 2.0
					m.spread = 0.0
			"tune_up":   # Gearhead (§14): +15% speed and fire rate; shield skips its delay (vehicle.gd)
				m.speed *= 1.0 + float(a.speed)
				m.fire *= 1.0 + float(a.fire)
				if float(a.get("servos", 0.0)) > 0.0:   # Tight Servos
					m.aim *= 1.25
					m.lock *= 1.1
			"power_divert":
				if float(a.get("grid", 0.0)) > 0.0:   # Grid Priority: utilities cool twice as fast
					m.util_cd *= 0.5
			"deadeye":
				m.spread = 0.0
				m.bullet_speed *= 1.0 + float(a.bullet_speed)
				m.damage *= 1.0 + float(a.damage)
			"piercing":
				m.pierce = maxi(int(m.pierce), int(a.pierce))
			"repair_guard":
				m.taken *= 1.0 - float(a.dr)
			"weld":
				m.taken *= 1.0 - minf(float(a.dr), MAX_DAMAGE_REDUCTION)
			"overclock":
				m.ignore_overload = true
				m.speed *= 1.0 + float(a.speed)
				m.accel *= 1.0 + float(a.accel)
			"stim":
				m.immune = true
			"gold_rush":
				m.scrap *= 1.0 + float(a.bonus)
			"brace":
				m.taken *= 1.0 - minf(float(a.dr), MAX_DAMAGE_REDUCTION)
				m.ram *= 1.0 + float(a.ram)
			"chain_drag":
				m.ram *= 1.0 + float(a.ram)
			"nitro":   # the Nitro Bottle utility rides the same timer
				m.speed *= 1.0 + float(a.speed)
				m.accel *= 1.0 + float(a.accel)
				m.ram *= 1.0 + float(a.ram)


## Rig stats with the seated crew folded in (Garage stat sheet).
static func apply_passives(stats: Dictionary, members: Array) -> Dictionary:
	var entries: Array = []
	for m: Dictionary in members:
		entries.append(entry(m))
	var mods := compute_mods(entries)
	var out := stats.duplicate(true)
	out.turn_rate = float(out.turn_rate) * float(mods.turn)
	out.grip = float(out.grip) + float(mods.grip)
	out.max_speed = float(out.max_speed) * float(mods.speed)
	out.acceleration = float(out.acceleration) * float(mods.accel)
	# Max armor (Reinforced) scales every facing; HP and shield stay.
	for k: String in ["front", "side", "rear"]:
		out[k] = float(out.get(k, 0.0)) * float(mods.armor)
	out.armor = float(out.get("hp", 0.0)) + float(out.front) + 2.0 * float(out.side) + float(out.rear)
	out.ram_damage = float(out.ram_damage) * float(mods.ram)
	out.lock_range = float(out.lock_range) * float(mods.lock)
	out.power_output = float(out.power_output) * float(mods.power)
	out.power_draw = float(out.power_draw) * float(mods.draw)
	out.weight_capacity = float(out.get("weight_capacity", 0.0)) * float(mods.weight_cap)
	for w: Dictionary in out.get("weapons", []):
		w.spread_deg = float(w.spread_deg) * float(mods.spread)
		w.turret_turn_rate = float(w.turret_turn_rate) * float(mods.aim)
		w.fire_rate = float(w.fire_rate) * float(mods.fire)
		w.bullet_speed = float(w.bullet_speed) * float(mods.bullet_speed)
	out.spread_deg = float(out.spread_deg) * float(mods.spread)
	out.turret_turn_rate = float(out.turret_turn_rate) * float(mods.aim)
	out.fire_rate = float(out.fire_rate) * float(mods.fire)
	out.bullet_speed = float(out.bullet_speed) * float(mods.bullet_speed)
	return out
