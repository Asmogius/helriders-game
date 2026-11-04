extends "res://tools/art/capture_step.gd"
## All six rarity frames side by side.


func run(cap: SceneTree) -> void:
	var strip: Control = cap.new_strip(UI.PANEL)
	for i in T.RARITY_ORDER.size():
		var r: String = T.RARITY_ORDER[i]
		var card := Panel.new()
		card.position = Vector2(40 + i * 205, 260)
		card.size = Vector2(185, 200)
		strip.add_child(card)
		var l := UI.label(r, 24, UI.rarity_color(r))
		l.position = Vector2(14, 40)
		card.add_child(l)
		UI.rarity_frame(card, r).set("t", 1.0)   # shimmer mid-sweep for the shot
