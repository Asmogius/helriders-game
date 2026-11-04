extends SceneTree
## Rarity colours (VISUAL_PLAN V1.1-V1.4): one source of truth, every tier has
## a colour and a frame, and every card type asks UI.rarity_* for its colour.
## The six-tier capture is `rarity_tiers.png` from tools/art/capture_all.gd.
##
## Run:  godot --headless --fixed-fps 60 --path . -s res://tests/rarity_test.gd

const T := preload("res://scripts/tuning.gd")
const UI := preload("res://scripts/ui_theme.gd")
const Parts := preload("res://scripts/parts.gd")
const Crew := preload("res://scripts/crew.gd")
const CrewCard := preload("res://scripts/crew_card.gd")
const RarityFrame := preload("res://scripts/rarity_frame.gd")
const Garage := preload("res://scripts/garage.gd")

# Card types and the files that draw them: each must use UI.rarity_* and
# none may colour by rarity another way.
const CARD_FILES := {
	"part card / slot tag": "res://scripts/garage.gd",
	"crew card": "res://scripts/crew_card.gd",
	"perk card / offers": "res://scripts/inn.gd",
	"research row": "res://scripts/research.gd",
	"comms odds": "res://scripts/comms.gd",
	"crate": "res://scripts/pickup.gd",
	"results / banners": "res://scripts/hud.gd",
	"database": "res://scripts/game_menu.gd",
}

var failures: Array[String] = []
var frame := 0
var _card: Control


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL: ", what)


func _initialize() -> void:
	var profile: Node = root.get_node("Profile")
	profile.persist = false
	profile.new_game()
	# Every rarity has its own colour, and the helpers agree with tuning.gd.
	_check(T.RARITY_ORDER.size() == 6, "six rarities")
	var seen := {}
	for i in T.RARITY_ORDER.size():
		var r: String = T.RARITY_ORDER[i]
		_check(T.RARITY_COLORS.has(r), "%s has a colour" % r)
		_check(UI.rarity_color(r) == T.RARITY_COLORS[r], "UI.rarity_color(%s) reads tuning.gd" % r)
		_check(UI.rarity_tier(r) == i + 1, "%s is tier %d" % [r, i + 1])
		_check(UI.rarity_text("x", r) == "[color=#%s]x[/color]" % T.RARITY_COLORS[r].to_html(false), "rarity_text(%s) BBCode" % r)
		seen[T.RARITY_COLORS[r].to_html(false)] = true
		_check(Crew.color_of({"rarity": r}) == T.RARITY_COLORS[r], "Crew.color_of(%s) reads tuning.gd" % r)
	_check(seen.size() == 6, "the six colours differ")
	_check(Parts.RARITY_COLORS == T.RARITY_COLORS, "Parts.RARITY_COLORS is tuning.gd's")
	for id: String in Parts.CATALOG:
		var r := str(Parts.get_part(id).rarity)
		_check(T.RARITY_COLORS.has(r), "part %s has a known rarity (%s)" % [id, r])
	for tier: String in T.PERK_TIER_RARITY:
		_check(T.RARITY_COLORS.has(UI.perk_rarity(tier)), "perk tier %s maps to a rarity" % tier)
	_check(UI.perk_rarity("") == "Common", "untiered perks show as Common")
	# Only tuning.gd defines a rarity colour.
	var def := RegEx.create_from_string("\"(Common|Uncommon|Rare|Epic|Legendary|Mythic)\"\\s*:\\s*Color\\(|MYTHIC_COLOR\\s*:?=")
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd") and f != "tuning.gd":
			_check(def.search(FileAccess.get_file_as_string("res://scripts/" + f)) == null, "%s defines no rarity colour" % f)
	# No card file colours by rarity through the old Parts/Crew helpers.
	for kind: String in CARD_FILES:
		var src := FileAccess.get_file_as_string(CARD_FILES[kind])
		_check(not src.contains("Parts.color_of") and not src.contains("Crew.color_of"), "%s has no other rarity colour source" % kind)
	# A crew card wears its member's frame.
	_card = CrewCard.new()
	_card.member = {"id": 1, "name": "Test Person", "role": "mechanic", "rarity": "Legendary", "xp": 0}
	root.add_child(_card)
	var cf: Control = _card.get_node_or_null("RarityFrame")
	_check(cf != null and str(cf.rarity) == "Legendary", "crew card has a Legendary frame")
	_card.member = null
	_check(cf != null and not cf.visible, "crew card hides its frame when the member is cleared")
	_card.member = {"id": 2, "name": "Back Again", "role": "mechanic", "rarity": "Rare", "xp": 0}
	_check(cf != null and cf.visible and str(cf.rarity) == "Rare", "crew card shows the frame again for a new member")


## Checks that need nodes to be ready and processing (run on the first frame).
func _live_checks() -> void:
	var profile: Node = root.get_node("Profile")
	# Behaviour: each card type, built with a known rarity, draws its frame in
	# exactly tuning.gd's colour for that rarity.
	for r: String in T.RARITY_ORDER:
		var cards := {
			"crew card": CrewCard.new(),
			"slot tag": Garage.SlotTag.new(),
			"part card": Garage.PartCard.new(),
		}
		for kind: String in cards:
			var card: Control = cards[kind]
			if kind == "crew card":
				card.member = {"id": 1, "name": "Test Person", "role": "mechanic", "rarity": r, "xp": 0}
			else:
				card.rarity = r
			root.add_child(card)
			var f: Control = card.get_node_or_null("RarityFrame")
			_check(f != null and f.visible, "%s (%s) shows a rarity frame" % [kind, r])
			if f != null:
				f.animate = false   # static colour (Mythic cycles when animated)
				_check(f.color() == T.RARITY_COLORS[r], "%s (%s) frame colour is T.RARITY_COLORS" % [kind, r])
			card.free()
	var q0 := str(profile.settings.get("quality", "High"))
	profile.set_setting("quality", "High")
	# A frame on every tier; Epic and up animate, Common to Rare stay static.
	for r: String in T.RARITY_ORDER:
		var c := Control.new()
		c.size = Vector2(200, 120)
		root.add_child(c)
		var f: Control = UI.rarity_frame(c, r)
		_check(f.get_script() == RarityFrame and str(f.rarity) == r, "%s frame added" % r)
		_check(UI.rarity_frame(c, r) == f, "%s frame reused, not stacked" % r)
		_check(f.animated() == (UI.rarity_tier(r) >= 4), "%s animates only if Epic+" % r)
		_check(f.is_processing() == (UI.rarity_tier(r) >= 4), "%s frame processes only if Epic+" % r)
		# Behaviour: the quality preset drives animation, live, on frames
		# already on screen (toggling Low then High in settings).
		profile.set_setting("quality", "Low")
		_check(not f.animated() and not f.is_processing(), "%s frame idle after switching to Low" % r)
		var fresh: Control = UI.rarity_frame(Control.new(), r)
		root.add_child(fresh.get_parent())
		_check(not fresh.animated(), "%s frame made on Low starts static" % r)
		profile.set_setting("quality", "High")
		_check(f.animated() == (UI.rarity_tier(r) >= 4) and f.is_processing() == (UI.rarity_tier(r) >= 4), "%s frame animates again after switching back to High" % r)
		fresh.get_parent().free()
		c.free()
	profile.set_setting("quality", q0)


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_live_checks()
	if frame < 3:
		return false
	if failures.is_empty():
		print("RARITY TEST PASSED")
	else:
		print("RARITY TEST FAILED (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
	return true
