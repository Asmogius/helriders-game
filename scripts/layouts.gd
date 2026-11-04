extends RefCounted
## Map layouts (§14 Maps; six for the beta, twelve since V5.7: three per
## district). Every
## layout is the same size (T.WORLD_SIZE) and lists which job types use it.
## Jobs on the daily board are given a layout and a variation seed; the same
## job always builds the same map. Variation (seeded): mirrored left-right
## and/or top-bottom, props nudged, one or two roads barricaded (from each
## layout's safe `blocks`), and zombies coming from fewer sides. `district`
## is art data only (V5.5 uses it for the look); job picking ignores it.
##
## A layout: start, buildings [Rect2], props [[center, size, rotation, kind]]
## (kind 0 car wreck, 1 barrier, 2 crates), roads [Rect2] (drawn only),
## checkpoints (Courier stops, Retrieve caches, Escort sites; open ground),
## barrel_spots, spawn_points (edges, open ground), blocks [[center, size,
## rotation]] (barricades that never cut anything off), jobs, and the V5.7
## design notes: district, landmark (what the player steers by), arena (an
## open fighting space, Rect2) and chokes (narrow gaps, kept clear of nudges).

const T := preload("res://scripts/tuning.gd")

const DEFAULT := "crossroads"

const LAYOUTS := {
	"crossroads": {
		"name": "Crossroads",
		"district": "outer_blocks",
		"landmark": "the four-way junction",
		"arena": Rect2(900, 850, 1400, 700),
		"chokes": [Vector2(100, 1200)],
		"jobs": ["clear", "survive", "hunt", "courier", "retrieve", "escort"],
		"start": Vector2(1600, 1200),
		"buildings": [
			Rect2(180, 180, 420, 300), Rect2(900, 160, 520, 340), Rect2(1700, 220, 380, 280), Rect2(2400, 160, 560, 360),
			Rect2(160, 900, 300, 560), Rect2(2780, 860, 260, 600), Rect2(180, 1880, 420, 340), Rect2(1000, 1900, 440, 320),
			Rect2(1720, 1880, 360, 360), Rect2(2480, 1900, 520, 320),
		],
		"props": [
			[Vector2(1240, 980), Vector2(110, 54), 0.35, 0], [Vector2(1980, 1420), Vector2(110, 54), -0.4, 0],
			[Vector2(1080, 1360), Vector2(150, 36), 0.0, 1], [Vector2(2160, 960), Vector2(150, 36), 1.2, 1],
			[Vector2(1600, 860), Vector2(64, 64), 0.2, 2], [Vector2(1420, 1480), Vector2(64, 64), -0.1, 2],
			[Vector2(2500, 1250), Vector2(110, 54), 1.4, 0], [Vector2(760, 1150), Vector2(110, 54), -1.2, 0],
			[Vector2(1900, 700), Vector2(150, 36), 0.0, 1], [Vector2(1000, 1720), Vector2(110, 54), 0.1, 0],
		],
		"roads": [Rect2(0, 620, 3200, 200), Rect2(0, 1600, 3200, 200), Rect2(640, 0, 220, 2400), Rect2(2120, 0, 240, 2400)],
		"checkpoints": [
			Vector2(150, 720), Vector2(750, 720), Vector2(1450, 720), Vector2(2240, 720), Vector2(3050, 720),
			Vector2(150, 1700), Vector2(750, 1700), Vector2(1550, 1700), Vector2(2240, 1700), Vector2(3050, 1700),
			Vector2(750, 170), Vector2(750, 1400), Vector2(750, 2260),
			Vector2(2240, 170), Vector2(2240, 1250), Vector2(2240, 2260),
			Vector2(1350, 1250), Vector2(1950, 1150),
		],
		"barrel_spots": [
			Vector2(270, 720), Vector2(1500, 720), Vector2(1700, 720), Vector2(2600, 720),
			Vector2(400, 1700), Vector2(1650, 1700), Vector2(1850, 1700), Vector2(2700, 1700),
			Vector2(750, 500), Vector2(750, 1270), Vector2(2240, 500), Vector2(2240, 950),
		],
		"spawn_points": [
			Vector2(60, 720), Vector2(60, 1700), Vector2(3140, 720), Vector2(3140, 1700),
			Vector2(750, 60), Vector2(820, 2340), Vector2(2240, 60), Vector2(2240, 2340),
			Vector2(1560, 80), Vector2(1580, 2330), Vector2(100, 1200), Vector2(3110, 1200),
		],
		"blocks": [[Vector2(750, 400), Vector2(230, 36), 0.0], [Vector2(2240, 2000), Vector2(250, 36), 0.0],
			[Vector2(1300, 720), Vector2(36, 210), 0.0], [Vector2(2900, 1700), Vector2(36, 210), 0.0]],
	},
	"main_drag": {
		"name": "Main Drag",
		"district": "midtown",
		"landmark": "the long main street",
		"arena": Rect2(620, 1010, 1960, 420),
		"chokes": [Vector2(1550, 850)],
		"jobs": ["clear", "courier", "retrieve", "escort"],
		"start": Vector2(1600, 1220),
		"buildings": [
			Rect2(140, 160, 460, 360), Rect2(140, 640, 460, 340), Rect2(960, 140, 560, 420), Rect2(1640, 140, 600, 300),
			Rect2(1640, 560, 300, 420), Rect2(960, 700, 500, 300), Rect2(2600, 160, 460, 820),
			Rect2(140, 1440, 460, 820), Rect2(960, 1440, 420, 380), Rect2(1500, 1440, 760, 300), Rect2(960, 1940, 620, 320),
			Rect2(1720, 1860, 520, 400), Rect2(2600, 1440, 460, 360), Rect2(2600, 1920, 460, 340),
		],
		"props": [
			[Vector2(1300, 1135), Vector2(110, 54), 0.1, 0], [Vector2(2650, 1305), Vector2(110, 54), -0.1, 0],
			[Vector2(760, 960), Vector2(110, 54), 1.57, 0], [Vector2(2440, 1520), Vector2(110, 54), 1.5, 0],
			[Vector2(2100, 700), Vector2(64, 64), 0.2, 2], [Vector2(1900, 1310), Vector2(150, 36), 0.05, 1],
		],
		"roads": [Rect2(0, 1100, 3200, 240), Rect2(700, 0, 160, 2400), Rect2(2340, 0, 160, 2400)],
		"checkpoints": [
			Vector2(150, 1220), Vector2(780, 1220), Vector2(1250, 1220), Vector2(2000, 1220), Vector2(2420, 1220), Vector2(3050, 1220),
			Vector2(780, 300), Vector2(780, 2200), Vector2(2420, 300), Vector2(2420, 2200), Vector2(2140, 820),
			Vector2(2420, 760), Vector2(780, 760),
		],
		"barrel_spots": [
			Vector2(400, 1150), Vector2(1000, 1290), Vector2(1800, 1150), Vector2(2900, 1290),
			Vector2(780, 520), Vector2(780, 1700), Vector2(2420, 520), Vector2(2420, 1700),
			Vector2(1150, 1150), Vector2(2200, 1290), Vector2(3000, 1150), Vector2(250, 1290),
		],
		"spawn_points": [
			Vector2(60, 1220), Vector2(3140, 1220), Vector2(780, 60), Vector2(780, 2340), Vector2(2420, 60), Vector2(2420, 2340),
			Vector2(60, 1150), Vector2(3140, 1300), Vector2(2100, 900), Vector2(800, 1500), Vector2(2400, 900),
		],
		"blocks": [[Vector2(780, 450), Vector2(170, 36), 0.0], [Vector2(780, 1900), Vector2(170, 36), 0.0],
			[Vector2(2420, 450), Vector2(170, 36), 0.0], [Vector2(2420, 1900), Vector2(170, 36), 0.0]],
	},
	"lots": {
		"name": "Parking Lots",
		"district": "outer_blocks",
		"landmark": "a mall car park",
		"arena": Rect2(100, 760, 780, 900),
		"chokes": [Vector2(1600, 1420)],
		"jobs": ["clear", "survive", "hunt", "escort"],
		"start": Vector2(1600, 860),
		"buildings": [
			Rect2(140, 140, 500, 300), Rect2(2560, 140, 500, 300), Rect2(140, 1960, 500, 300), Rect2(2560, 1960, 500, 300),
			Rect2(1350, 140, 500, 240), Rect2(1350, 2020, 500, 240), Rect2(1450, 1050, 300, 300),
		],
		"props": [
			[Vector2(350, 980), Vector2(110, 54), 1.57, 0], [Vector2(560, 980), Vector2(110, 54), 1.5, 0],
			[Vector2(1250, 980), Vector2(110, 54), 1.6, 0], [Vector2(1950, 980), Vector2(110, 54), 1.57, 0],
			[Vector2(2600, 980), Vector2(110, 54), 1.55, 0], [Vector2(2850, 980), Vector2(110, 54), 1.57, 0],
			[Vector2(350, 1450), Vector2(110, 54), 1.57, 0], [Vector2(700, 1450), Vector2(110, 54), 1.6, 0],
			[Vector2(1250, 1450), Vector2(110, 54), 1.57, 0], [Vector2(1950, 1450), Vector2(110, 54), 1.5, 0],
			[Vector2(2500, 1450), Vector2(110, 54), 1.57, 0], [Vector2(2850, 1450), Vector2(110, 54), 1.6, 0],
			[Vector2(1600, 1500), Vector2(150, 36), 0.0, 1], [Vector2(700, 300), Vector2(64, 64), 0.3, 2],
		],
		"roads": [Rect2(0, 560, 3200, 180), Rect2(0, 1700, 3200, 180), Rect2(900, 0, 180, 2400), Rect2(2120, 0, 180, 2400)],
		"checkpoints": [
			Vector2(300, 650), Vector2(1600, 650), Vector2(2900, 650), Vector2(300, 1790), Vector2(1600, 1790), Vector2(2900, 1790),
			Vector2(990, 300), Vector2(990, 2100), Vector2(2210, 300), Vector2(2210, 2100), Vector2(600, 1200), Vector2(2600, 1200),
			Vector2(1600, 1600), Vector2(1250, 1200), Vector2(1950, 1200),
		],
		"barrel_spots": [
			Vector2(500, 650), Vector2(1300, 650), Vector2(2000, 620), Vector2(2700, 650),
			Vector2(500, 1790), Vector2(1800, 1790), Vector2(2000, 1760), Vector2(2700, 1790),
			Vector2(990, 1200), Vector2(2210, 1200), Vector2(1600, 960), Vector2(1100, 1450),
		],
		"spawn_points": [
			Vector2(60, 650), Vector2(3140, 650), Vector2(60, 1790), Vector2(3140, 1790), Vector2(990, 60), Vector2(2210, 60),
			Vector2(990, 2340), Vector2(2210, 2340), Vector2(60, 1200), Vector2(3140, 1200),
		],
		"blocks": [[Vector2(990, 420), Vector2(190, 36), 0.0], [Vector2(2210, 1980), Vector2(190, 36), 0.0],
			[Vector2(1900, 650), Vector2(36, 190), 0.0], [Vector2(700, 1790), Vector2(36, 190), 0.0]],
	},
	"alleys": {
		"name": "Back Alleys",
		"district": "midtown",
		"landmark": "the open courtyard",
		"arena": Rect2(1160, 940, 760, 640),
		"chokes": [Vector2(640, 780)],
		"jobs": ["clear", "hunt", "courier", "retrieve"],
		"start": Vector2(1540, 1260),
		"buildings": [
			Rect2(120, 140, 440, 320), Rect2(720, 140, 440, 320), Rect2(1320, 140, 440, 320), Rect2(1920, 140, 440, 320), Rect2(2520, 140, 440, 320),
			Rect2(120, 620, 440, 320), Rect2(720, 620, 440, 320), Rect2(1320, 620, 440, 320), Rect2(1920, 620, 440, 320),
			Rect2(120, 1100, 440, 320), Rect2(720, 1100, 440, 320), Rect2(1920, 1100, 440, 320), Rect2(2520, 1100, 440, 320),
			Rect2(120, 1580, 440, 320), Rect2(1320, 1580, 440, 320), Rect2(1920, 1580, 440, 320), Rect2(2520, 1580, 440, 320),
		],
		"props": [
			[Vector2(1240, 300), Vector2(64, 64), 0.2, 2], [Vector2(3060, 1260), Vector2(64, 64), 0.1, 2],
			[Vector2(2140, 2130), Vector2(110, 54), 0.3, 0], [Vector2(940, 2050), Vector2(110, 54), -0.2, 0],
		],
		"roads": [Rect2(0, 460, 3200, 160), Rect2(0, 940, 3200, 160), Rect2(0, 1420, 3200, 160),
			Rect2(560, 0, 160, 2400), Rect2(1760, 0, 160, 2400)],
		"checkpoints": [
			Vector2(640, 540), Vector2(1840, 540), Vector2(2440, 540), Vector2(640, 1020), Vector2(1240, 1020), Vector2(2440, 1020),
			Vector2(640, 1500), Vector2(1840, 1500), Vector2(2440, 1500), Vector2(1540, 1260), Vector2(2740, 780),
			Vector2(940, 1740), Vector2(1600, 2130), Vector2(300, 2130), Vector2(2900, 2130),
		],
		"barrel_spots": [
			Vector2(800, 540), Vector2(2100, 540), Vector2(400, 1020), Vector2(1500, 1020), Vector2(2700, 1020),
			Vector2(900, 1500), Vector2(1900, 1500), Vector2(640, 780), Vector2(1840, 1260), Vector2(2440, 1260),
			Vector2(1240, 1740), Vector2(2700, 2130),
		],
		"spawn_points": [
			Vector2(640, 60), Vector2(1840, 60), Vector2(2440, 60), Vector2(60, 540), Vector2(60, 1500), Vector2(3140, 1020),
			Vector2(3140, 540), Vector2(640, 2340), Vector2(1840, 2340), Vector2(3140, 2130), Vector2(60, 2130),
		],
		"blocks": [[Vector2(1040, 1020), Vector2(36, 150), 0.0], [Vector2(2160, 540), Vector2(36, 150), 0.0],
			[Vector2(1840, 780), Vector2(150, 36), 0.0], [Vector2(640, 1260), Vector2(150, 36), 0.0]],
	},
	"rail_yard": {
		"name": "Rail Yard",
		"district": "industrial",
		"landmark": "the rail sidings",
		"arena": Rect2(810, 740, 1580, 880),
		"chokes": [Vector2(1450, 310)],
		"jobs": ["clear", "survive", "courier", "escort"],
		"start": Vector2(1600, 1200),
		"buildings": [
			Rect2(200, 260, 1100, 100), Rect2(1600, 260, 1300, 100), Rect2(400, 620, 1000, 100), Rect2(1800, 620, 1100, 100),
			Rect2(200, 1640, 1200, 100), Rect2(1700, 1640, 1200, 100), Rect2(400, 2000, 1000, 100), Rect2(1800, 2000, 1100, 100),
			Rect2(300, 1000, 500, 360), Rect2(2400, 1000, 500, 360),
		],
		"props": [
			[Vector2(1450, 960), Vector2(64, 64), 0.3, 2], [Vector2(1750, 1440), Vector2(64, 64), -0.2, 2],
			[Vector2(900, 1450), Vector2(110, 54), 0.2, 0], [Vector2(2300, 950), Vector2(110, 54), -0.3, 0],
		],
		"roads": [Rect2(0, 440, 3200, 140), Rect2(0, 1780, 3200, 180), Rect2(1450, 0, 140, 2400)],
		"checkpoints": [
			Vector2(1520, 150), Vector2(1520, 2250), Vector2(150, 500), Vector2(3050, 500), Vector2(150, 1860), Vector2(3050, 1860),
			Vector2(1000, 1200), Vector2(2200, 1200), Vector2(1600, 800), Vector2(1600, 1530), Vector2(150, 1200),
			Vector2(3050, 1200), Vector2(800, 500), Vector2(2400, 1860),
		],
		"barrel_spots": [
			Vector2(700, 500), Vector2(2300, 500), Vector2(1350, 1870), Vector2(2300, 1870), Vector2(1520, 350), Vector2(1520, 2080),
			Vector2(1450, 1200), Vector2(1750, 1200), Vector2(150, 800), Vector2(3050, 800), Vector2(150, 1550), Vector2(3050, 1550),
		],
		"spawn_points": [
			Vector2(60, 500), Vector2(3140, 500), Vector2(60, 1860), Vector2(3140, 1860), Vector2(1520, 60), Vector2(1520, 2340),
			Vector2(60, 1200), Vector2(3140, 1200), Vector2(60, 150), Vector2(3140, 2250),
		],
		"blocks": [[Vector2(1100, 510), Vector2(36, 130), 0.0], [Vector2(2600, 1870), Vector2(36, 170), 0.0],
			[Vector2(1520, 1870), Vector2(130, 36), 0.0], [Vector2(2000, 510), Vector2(36, 130), 0.0]],
	},
	"plaza": {
		"name": "Plaza",
		"district": "midtown",
		"landmark": "the plaza monument",
		"arena": Rect2(1050, 800, 1100, 800),
		"chokes": [Vector2(1600, 400)],
		"jobs": ["clear", "survive", "hunt", "retrieve"],
		"start": Vector2(1600, 950),
		"buildings": [
			Rect2(160, 160, 700, 500), Rect2(1050, 160, 450, 500), Rect2(1700, 160, 450, 500), Rect2(2340, 160, 700, 500),
			Rect2(160, 800, 700, 260), Rect2(160, 1340, 700, 260), Rect2(2340, 800, 700, 260), Rect2(2340, 1340, 700, 260),
			Rect2(160, 1740, 700, 500), Rect2(1050, 1740, 450, 500), Rect2(1700, 1740, 450, 500), Rect2(2340, 1740, 700, 500),
			Rect2(1500, 1100, 200, 200),
		],
		"props": [
			[Vector2(1300, 1050), Vector2(110, 54), 0.5, 0], [Vector2(1760, 1540), Vector2(110, 54), -0.6, 0],
			[Vector2(2050, 900), Vector2(64, 64), 0.0, 2], [Vector2(1150, 1550), Vector2(150, 36), 0.3, 1],
		],
		"roads": [Rect2(0, 660, 3200, 140), Rect2(0, 1600, 3200, 140), Rect2(860, 0, 190, 2400), Rect2(2150, 0, 190, 2400)],
		"checkpoints": [
			Vector2(1600, 950), Vector2(1200, 1200), Vector2(2000, 1200), Vector2(1600, 1450), Vector2(955, 300), Vector2(955, 2100),
			Vector2(2245, 300), Vector2(2245, 2100), Vector2(1600, 400), Vector2(1600, 2000), Vector2(300, 730), Vector2(2900, 730),
			Vector2(300, 1670), Vector2(2900, 1670), Vector2(500, 1200), Vector2(2700, 1200),
		],
		"barrel_spots": [
			Vector2(1250, 950), Vector2(1950, 950), Vector2(1250, 1450), Vector2(1950, 1450), Vector2(955, 730), Vector2(2245, 730),
			Vector2(955, 1670), Vector2(2245, 1670), Vector2(600, 730), Vector2(2500, 1670), Vector2(1250, 1200), Vector2(1600, 2150),
		],
		"spawn_points": [
			Vector2(955, 60), Vector2(2245, 60), Vector2(955, 2340), Vector2(2245, 2340), Vector2(1600, 60), Vector2(1600, 2340),
			Vector2(60, 730), Vector2(3140, 730), Vector2(60, 1670), Vector2(3140, 1670), Vector2(60, 1200), Vector2(3140, 1200),
		],
		"blocks": [[Vector2(955, 1200), Vector2(200, 36), 0.0], [Vector2(2245, 1200), Vector2(200, 36), 0.0],
			[Vector2(1600, 600), Vector2(210, 36), 0.0], [Vector2(1600, 1800), Vector2(210, 36), 0.0]],
	},
	# --- V5.7: six new layouts (two per district beyond the first six) ---
	"gas_station": {
		"name": "Gas Station",
		"district": "outer_blocks",
		"landmark": "the gas station kiosk and pumps",
		"jobs": ["clear", "survive", "hunt", "courier", "retrieve", "escort"],
		"start": Vector2(1600, 1500),
		"arena": Rect2(900, 1380, 1400, 500),
		"chokes": [Vector2(660, 1050), Vector2(600, 290)],
		"buildings": [
			Rect2(160, 160, 360, 260), Rect2(680, 160, 360, 260), Rect2(1260, 160, 680, 260), Rect2(2160, 160, 360, 260), Rect2(2680, 160, 360, 260),
			Rect2(160, 900, 420, 300), Rect2(160, 1360, 420, 300), Rect2(740, 880, 300, 440), Rect2(1440, 1000, 320, 180),
			Rect2(2620, 900, 420, 300), Rect2(2620, 1360, 420, 300),
			Rect2(160, 1940, 420, 300), Rect2(740, 1940, 420, 300), Rect2(2040, 1940, 420, 300), Rect2(2620, 1940, 420, 300),
		],
		"props": [
			[Vector2(1460, 1290), Vector2(64, 64), 0.0, 2], [Vector2(1600, 1290), Vector2(64, 64), 0.0, 2], [Vector2(1740, 1290), Vector2(64, 64), 0.0, 2],
			[Vector2(2300, 1000), Vector2(110, 54), 0.4, 0], [Vector2(1250, 850), Vector2(110, 54), -0.3, 0],
			[Vector2(2000, 1250), Vector2(150, 36), 1.3, 1], [Vector2(400, 1800), Vector2(110, 54), 0.1, 0],
			[Vector2(2450, 700), Vector2(110, 54), 0.05, 0],
		],
		"roads": [Rect2(0, 560, 3200, 200), Rect2(580, 0, 160, 2400), Rect2(2460, 760, 160, 1640), Rect2(1160, 1880, 880, 520)],
		"checkpoints": [
			Vector2(200, 660), Vector2(900, 660), Vector2(1600, 660), Vector2(2300, 660), Vector2(3000, 660),
			Vector2(1200, 1100), Vector2(2100, 1100), Vector2(660, 1050), Vector2(660, 1800), Vector2(2540, 1800),
			Vector2(1600, 1950), Vector2(1600, 850), Vector2(2900, 1280), Vector2(1150, 300),
		],
		"barrel_spots": [
			Vector2(1360, 1300), Vector2(1840, 1300), Vector2(1000, 620), Vector2(1100, 700), Vector2(2200, 620), Vector2(2300, 720),
			Vector2(1500, 2100), Vector2(1700, 2150), Vector2(300, 1280), Vector2(450, 1280), Vector2(2800, 1800), Vector2(2900, 1850),
		],
		"spawn_points": [
			Vector2(60, 660), Vector2(60, 1280), Vector2(60, 1800), Vector2(3140, 660), Vector2(3140, 1280), Vector2(3140, 1800),
			Vector2(600, 60), Vector2(1150, 60), Vector2(2600, 60), Vector2(660, 2340), Vector2(1600, 2340),
		],
		"blocks": [[Vector2(1000, 760), Vector2(36, 180), 0.0], [Vector2(2200, 760), Vector2(36, 180), 0.0],
			[Vector2(2540, 1500), Vector2(150, 36), 0.0], [Vector2(660, 1650), Vector2(150, 36), 0.0]],
	},
	"overpass": {
		"name": "Collapsed Overpass",
		"district": "core",
		"landmark": "the collapsed overpass deck",
		"jobs": ["clear", "survive", "hunt", "courier", "retrieve"],
		"start": Vector2(1600, 1600),
		"arena": Rect2(950, 1340, 1350, 560),
		"chokes": [Vector2(1125, 1170), Vector2(2075, 1170)],
		"buildings": [
			Rect2(200, 1100, 800, 140), Rect2(1250, 1100, 700, 140), Rect2(2200, 1100, 800, 140),
			Rect2(300, 250, 500, 450), Rect2(1100, 200, 450, 350), Rect2(1900, 250, 400, 400), Rect2(2600, 200, 450, 500),
			Rect2(250, 1700, 550, 450), Rect2(1300, 2000, 600, 240), Rect2(2500, 1650, 500, 500),
		],
		"props": [
			[Vector2(1050, 1290), Vector2(64, 64), 0.4, 2], [Vector2(2150, 1010), Vector2(64, 64), -0.5, 2],
			[Vector2(1400, 800), Vector2(110, 54), 0.6, 0], [Vector2(2450, 650), Vector2(110, 54), -0.8, 0],
			[Vector2(600, 1450), Vector2(150, 36), 0.2, 1], [Vector2(2350, 1500), Vector2(110, 54), 1.1, 0],
			[Vector2(950, 1000), Vector2(64, 64), 0.1, 2], [Vector2(2700, 1000), Vector2(110, 54), 0.2, 0],
		],
		"roads": [Rect2(0, 900, 3200, 200), Rect2(0, 1240, 3200, 160), Rect2(1000, 0, 250, 2400), Rect2(1950, 0, 250, 2400)],
		"checkpoints": [
			Vector2(900, 500), Vector2(1700, 700), Vector2(2450, 800), Vector2(1600, 900), Vector2(150, 900), Vector2(2800, 900),
			Vector2(1000, 2200), Vector2(2200, 2150), Vector2(400, 1450), Vector2(2800, 1450), Vector2(1125, 1170), Vector2(2075, 1170),
			Vector2(150, 1500), Vector2(3050, 1500), Vector2(2900, 2300),
		],
		"barrel_spots": [
			Vector2(1060, 1000), Vector2(1190, 1000), Vector2(2020, 1360), Vector2(2140, 1360), Vector2(600, 850), Vector2(700, 900),
			Vector2(2500, 900), Vector2(2600, 950), Vector2(1000, 1950), Vector2(1100, 2000), Vector2(2300, 1950), Vector2(2400, 2000),
		],
		"spawn_points": [
			Vector2(60, 600), Vector2(60, 1500), Vector2(3140, 600), Vector2(3140, 1500), Vector2(900, 60), Vector2(1700, 60),
			Vector2(2450, 60), Vector2(1000, 2340), Vector2(2200, 2340), Vector2(60, 2300), Vector2(3140, 2300),
		],
		"blocks": [[Vector2(120, 1170), Vector2(170, 36), 0.0], [Vector2(3080, 1170), Vector2(170, 36), 0.0],
			[Vector2(950, 650), Vector2(300, 36), 0.0], [Vector2(2450, 450), Vector2(300, 36), 0.0]],
	},
	"stadium_gate": {
		"name": "Stadium Gate",
		"district": "core",
		"landmark": "the stadium and its turnstile gate",
		"jobs": ["clear", "survive", "hunt", "retrieve", "escort"],
		"start": Vector2(1600, 1300),
		"arena": Rect2(900, 1050, 1400, 550),
		"chokes": [Vector2(880, 450), Vector2(2320, 450), Vector2(1030, 2000), Vector2(2170, 2000)],
		"buildings": [
			Rect2(1000, 200, 1200, 700), Rect2(160, 160, 600, 500), Rect2(2440, 160, 600, 500),
			Rect2(160, 900, 500, 400), Rect2(2540, 900, 500, 400),
			Rect2(160, 1800, 700, 440), Rect2(1200, 1800, 800, 440), Rect2(2340, 1800, 700, 440),
		],
		"props": [
			[Vector2(1100, 960), Vector2(150, 36), 0.0, 1], [Vector2(1350, 960), Vector2(150, 36), 0.0, 1],
			[Vector2(1850, 960), Vector2(150, 36), 0.0, 1], [Vector2(2100, 960), Vector2(150, 36), 0.0, 1],
			[Vector2(500, 1500), Vector2(110, 54), 0.3, 0], [Vector2(2700, 1450), Vector2(110, 54), -0.4, 0],
			[Vector2(1600, 1700), Vector2(64, 64), 0.2, 2], [Vector2(2400, 780), Vector2(110, 54), 1.2, 0],
		],
		"roads": [Rect2(0, 700, 3200, 200), Rect2(0, 1600, 3200, 200), Rect2(760, 0, 240, 1800), Rect2(2200, 0, 240, 1800)],
		"checkpoints": [
			Vector2(880, 450), Vector2(2320, 450), Vector2(450, 780), Vector2(2750, 780), Vector2(800, 1100), Vector2(2400, 1100),
			Vector2(1600, 960), Vector2(450, 1550), Vector2(2750, 1550), Vector2(1030, 2000), Vector2(2170, 2000),
			Vector2(1600, 1580), Vector2(1600, 2300), Vector2(150, 1500),
		],
		"barrel_spots": [
			Vector2(1250, 1080), Vector2(1350, 1120), Vector2(1850, 1080), Vector2(1950, 1120), Vector2(600, 1600), Vector2(700, 1650),
			Vector2(2500, 1600), Vector2(2600, 1650), Vector2(880, 650), Vector2(2320, 650), Vector2(1400, 1720), Vector2(1800, 1720),
		],
		"spawn_points": [
			Vector2(880, 60), Vector2(2320, 60), Vector2(60, 750), Vector2(3140, 750), Vector2(60, 1550), Vector2(3140, 1550),
			Vector2(1030, 2340), Vector2(2170, 2340),
		],
		"blocks": [[Vector2(880, 580), Vector2(240, 36), 0.0], [Vector2(2320, 580), Vector2(240, 36), 0.0],
			[Vector2(1030, 2150), Vector2(340, 36), 0.0], [Vector2(2170, 2150), Vector2(340, 36), 0.0]],
	},
	"factory_yard": {
		"name": "Factory Yard",
		"district": "industrial",
		"landmark": "the factory yard under the pipe rack",
		"jobs": ["clear", "survive", "hunt", "courier", "escort"],
		"start": Vector2(1600, 1250),
		"arena": Rect2(880, 820, 1440, 880),
		"chokes": [Vector2(1180, 630), Vector2(2020, 630), Vector2(400, 1900), Vector2(2800, 1900)],
		"buildings": [
			Rect2(160, 160, 900, 500), Rect2(1300, 160, 600, 300), Rect2(2140, 160, 900, 500), Rect2(1300, 600, 600, 60),
			Rect2(160, 900, 500, 900), Rect2(2540, 900, 500, 900),
			Rect2(160, 2000, 1100, 240), Rect2(1500, 1950, 300, 290), Rect2(2040, 2000, 1000, 240),
		],
		"props": [
			[Vector2(750, 820), Vector2(110, 54), 0.3, 0], [Vector2(2450, 820), Vector2(110, 54), -0.3, 0],
			[Vector2(1600, 1730), Vector2(150, 36), 0.0, 1], [Vector2(780, 1700), Vector2(64, 64), 0.4, 2],
			[Vector2(2420, 1700), Vector2(64, 64), -0.2, 2], [Vector2(1150, 1850), Vector2(110, 54), 0.1, 0],
		],
		"roads": [Rect2(0, 700, 3200, 160), Rect2(1060, 0, 240, 700), Rect2(1900, 0, 240, 700), Rect2(0, 1800, 3200, 200)],
		"checkpoints": [
			Vector2(1180, 630), Vector2(2020, 630), Vector2(1600, 530), Vector2(400, 780), Vector2(2800, 780), Vector2(780, 1300),
			Vector2(2420, 1300), Vector2(400, 1900), Vector2(2800, 1900), Vector2(1380, 2100), Vector2(1920, 2100),
			Vector2(1600, 1850), Vector2(1600, 1000), Vector2(1180, 300),
		],
		"barrel_spots": [
			Vector2(1100, 1000), Vector2(1200, 1050), Vector2(2000, 1000), Vector2(2100, 1050), Vector2(1100, 1550), Vector2(1200, 1500),
			Vector2(2000, 1550), Vector2(2100, 1500), Vector2(300, 1900), Vector2(2900, 1900), Vector2(1600, 720), Vector2(1700, 740),
		],
		"spawn_points": [
			Vector2(60, 780), Vector2(3140, 780), Vector2(60, 1900), Vector2(3140, 1900), Vector2(1180, 60), Vector2(2020, 60),
			Vector2(1380, 2340), Vector2(1920, 2340),
		],
		"blocks": [[Vector2(550, 1900), Vector2(36, 200), 0.0], [Vector2(2650, 1900), Vector2(36, 200), 0.0],
			[Vector2(1180, 480), Vector2(240, 36), 0.0], [Vector2(2020, 480), Vector2(240, 36), 0.0]],
	},
	"rail_bridge": {
		"name": "Rail Bridge",
		"district": "industrial",
		"landmark": "the rail bridge embankment and its underpasses",
		"jobs": ["clear", "survive", "courier", "retrieve", "escort"],
		"start": Vector2(1600, 1650),
		"arena": Rect2(900, 1400, 1400, 500),
		"chokes": [Vector2(1045, 1130), Vector2(2150, 1130)],
		"buildings": [
			Rect2(40, 1050, 900, 160), Rect2(1150, 1050, 900, 160), Rect2(2250, 1050, 910, 160),
			Rect2(200, 200, 600, 500), Rect2(1000, 200, 500, 350), Rect2(1700, 200, 500, 350), Rect2(2400, 200, 600, 500),
			Rect2(200, 1450, 500, 500), Rect2(2500, 1450, 500, 500),
			Rect2(300, 2100, 700, 200), Rect2(1200, 2050, 800, 190), Rect2(2200, 2100, 700, 200),
		],
		"props": [
			[Vector2(1300, 850), Vector2(110, 54), 0.2, 0], [Vector2(1900, 870), Vector2(110, 54), -0.3, 0],
			[Vector2(600, 1350), Vector2(150, 36), 0.1, 1], [Vector2(2600, 1330), Vector2(150, 36), -0.1, 1],
			[Vector2(1600, 620), Vector2(64, 64), 0.3, 2], [Vector2(2350, 1600), Vector2(110, 54), 1.4, 0],
		],
		"roads": [Rect2(0, 750, 3200, 200), Rect2(940, 0, 210, 2400), Rect2(2050, 0, 200, 2400)],
		"checkpoints": [
			Vector2(900, 400), Vector2(1600, 400), Vector2(2300, 400), Vector2(600, 850), Vector2(1600, 800), Vector2(2600, 850),
			Vector2(1045, 1130), Vector2(2150, 1130), Vector2(450, 1300), Vector2(2750, 1300), Vector2(800, 1700),
			Vector2(2400, 1750), Vector2(1600, 1990), Vector2(450, 2040),
		],
		"barrel_spots": [
			Vector2(980, 950), Vector2(1110, 950), Vector2(2090, 950), Vector2(2210, 950), Vector2(980, 1320), Vector2(1110, 1320),
			Vector2(2090, 1320), Vector2(2210, 1320), Vector2(400, 900), Vector2(2800, 900), Vector2(1400, 1980), Vector2(1800, 1980),
		],
		"spawn_points": [
			Vector2(60, 800), Vector2(3140, 800), Vector2(60, 2000), Vector2(3140, 2000), Vector2(900, 60), Vector2(1600, 60),
			Vector2(2300, 60), Vector2(1100, 2340), Vector2(2100, 2340),
		],
		"blocks": [[Vector2(900, 620), Vector2(200, 36), 0.0], [Vector2(2300, 620), Vector2(200, 36), 0.0],
			[Vector2(800, 2000), Vector2(36, 200), 0.0], [Vector2(2400, 2000), Vector2(36, 200), 0.0]],
	},
	"crater_rim": {
		"name": "Crater Rim",
		"district": "core",
		"landmark": "the blast crater ringed with rubble",
		"jobs": ["clear", "survive", "hunt", "courier", "retrieve"],
		"start": Vector2(1600, 1200),
		"arena": Rect2(1320, 1000, 560, 400),
		"chokes": [Vector2(2100, 1200), Vector2(1100, 1200), Vector2(1600, 700), Vector2(1600, 1700)],
		"buildings": [
			Rect2(160, 160, 700, 450), Rect2(2340, 160, 700, 450), Rect2(160, 1790, 700, 450), Rect2(2340, 1790, 700, 450),
			Rect2(160, 900, 350, 600), Rect2(2690, 900, 350, 600),
		],
		"props": [
			[Vector2(2087, 1311), Vector2(64, 64), 0.22, 2], [Vector2(2050, 1416), Vector2(64, 64), 0.45, 2], [Vector2(1990, 1511), Vector2(64, 64), 0.67, 2],
			[Vector2(1911, 1590), Vector2(64, 64), 0.90, 2], [Vector2(1816, 1650), Vector2(64, 64), 1.12, 2], [Vector2(1711, 1687), Vector2(64, 64), 1.35, 2],
			[Vector2(1488, 1687), Vector2(64, 64), 1.80, 2], [Vector2(1383, 1650), Vector2(64, 64), 2.02, 2], [Vector2(1288, 1590), Vector2(64, 64), 2.24, 2],
			[Vector2(1209, 1511), Vector2(64, 64), 2.47, 2], [Vector2(1149, 1416), Vector2(64, 64), 2.69, 2], [Vector2(1112, 1311), Vector2(64, 64), 2.92, 2],
			[Vector2(1112, 1088), Vector2(64, 64), 3.37, 2], [Vector2(1149, 983), Vector2(64, 64), 3.59, 2], [Vector2(1209, 888), Vector2(64, 64), 3.81, 2],
			[Vector2(1288, 809), Vector2(64, 64), 4.04, 2], [Vector2(1383, 749), Vector2(64, 64), 4.26, 2], [Vector2(1488, 712), Vector2(64, 64), 4.49, 2],
			[Vector2(1711, 712), Vector2(64, 64), 4.94, 2], [Vector2(1816, 749), Vector2(64, 64), 5.16, 2], [Vector2(1911, 809), Vector2(64, 64), 5.39, 2],
			[Vector2(1990, 888), Vector2(64, 64), 5.61, 2], [Vector2(2050, 983), Vector2(64, 64), 5.83, 2], [Vector2(2087, 1088), Vector2(64, 64), 6.06, 2],
			[Vector2(900, 1000), Vector2(110, 54), 0.7, 0], [Vector2(2300, 1450), Vector2(110, 54), -0.6, 0],
		],
		"roads": [Rect2(0, 650, 3200, 200), Rect2(0, 1550, 3200, 200), Rect2(1500, 0, 200, 2400)],
		"checkpoints": [
			Vector2(2100, 1200), Vector2(1100, 1200), Vector2(1600, 700), Vector2(1600, 1700), Vector2(1600, 1000), Vector2(1400, 1350),
			Vector2(1800, 1350), Vector2(900, 700), Vector2(2300, 700), Vector2(900, 1700), Vector2(2300, 1700), Vector2(600, 1200),
			Vector2(2600, 1200), Vector2(1600, 300), Vector2(1600, 2100),
		],
		"barrel_spots": [
			Vector2(1400, 1050), Vector2(1480, 1000), Vector2(1800, 1050), Vector2(1720, 1000), Vector2(1400, 1400), Vector2(1480, 1440),
			Vector2(1720, 1440), Vector2(1800, 1400), Vector2(900, 500), Vector2(1000, 450), Vector2(2200, 1900), Vector2(2300, 1950),
		],
		"spawn_points": [
			Vector2(60, 750), Vector2(3140, 750), Vector2(60, 1650), Vector2(3140, 1650), Vector2(1100, 60), Vector2(2100, 60),
			Vector2(1100, 2340), Vector2(2100, 2340),
		],
		"blocks": [[Vector2(1100, 450), Vector2(36, 300), 0.0], [Vector2(2100, 1950), Vector2(36, 300), 0.0],
			[Vector2(600, 800), Vector2(36, 260), 0.0], [Vector2(2600, 1600), Vector2(36, 260), 0.0]],
	},
}


static func ids_for(job_type: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in LAYOUTS:
		if (LAYOUTS[id].jobs as Array).has(job_type):
			out.append(id)
	return out


## The layout a board job gets, from its seed (Comms and the mission agree).
static func pick(job_type: String, job_seed: int) -> String:
	var ids := ids_for(job_type)
	if ids.is_empty():
		return DEFAULT
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-layout-%d" % job_seed)
	return ids[rng.randi_range(0, ids.size() - 1)]


## The map for a job: `id`'s layout, varied by `vary_seed` (0 = as drawn).
static func build(id: String, vary_seed := 0) -> Dictionary:
	var src: Dictionary = LAYOUTS.get(id, LAYOUTS[DEFAULT])
	var out := {
		"id": id if LAYOUTS.has(id) else DEFAULT,
		"name": str(src.name),
		"start": src.start,
		"buildings": (src.buildings as Array).duplicate(),
		"props": (src.props as Array).duplicate(true),
		"roads": (src.roads as Array).duplicate(),
		"checkpoints": (src.checkpoints as Array).duplicate(),
		"barrel_spots": (src.barrel_spots as Array).duplicate(),
		"spawn_points": (src.spawn_points as Array).duplicate(),
		"district": str(src.get("district", "")),
		"landmark": str(src.get("landmark", "")),
		"arena": src.get("arena", Rect2()),
		"chokes": (src.get("chokes", []) as Array).duplicate(),
		"blocks_used": 0,
	}
	if vary_seed == 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("helriders-vary-%d" % vary_seed)
	var keep_clear: Array = [out.start]
	keep_clear.append_array(out.checkpoints)
	keep_clear.append_array(out.barrel_spots)
	keep_clear.append_array(out.chokes)
	# Props nudged (never onto a stop, a barrel spot or the start).
	for p: Array in out.props:
		var moved: Vector2 = (p[0] as Vector2) + Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50))
		if _clear_of(moved, keep_clear, 110.0):
			p[0] = moved
			p[2] = float(p[2]) + rng.randf_range(-0.3, 0.3)
	# One or two barricades from the layout's safe list.
	var blocks: Array = (src.blocks as Array).duplicate(true)
	_shuffle(blocks, rng)
	var n := rng.randi_range(1, 2)
	for i in mini(n, blocks.size()):
		var b: Array = blocks[i]
		out.props.append([b[0], b[1], float(b[2]), 1])
	out.blocks_used = mini(n, blocks.size())
	# Zombies come from two or three sides.
	var sides := ["left", "right", "top", "bottom"]
	_shuffle(sides, rng)
	var use := sides.slice(0, rng.randi_range(2, 3))
	var spawns: Array = out.spawn_points.filter(func(s: Vector2) -> bool: return use.has(_side_of(s)))
	if spawns.size() >= 4:
		out.spawn_points = spawns
	# Mirrored.
	var flip_x := rng.randf() < 0.5
	var flip_y := rng.randf() < 0.5
	if flip_x or flip_y:
		_mirror(out, flip_x, flip_y)
	return out


static func _clear_of(p: Vector2, points: Array, dist: float) -> bool:
	for q: Vector2 in points:
		if p.distance_to(q) < dist:
			return false
	return true


static func _side_of(p: Vector2) -> String:
	var w := T.WORLD_SIZE
	var d := {"left": p.x, "right": w.x - p.x, "top": p.y, "bottom": w.y - p.y}
	var best := "left"
	for k: String in d:
		if float(d[k]) < float(d[best]):
			best = k
	return best


static func _mirror(out: Dictionary, fx: bool, fy: bool) -> void:
	var w := T.WORLD_SIZE
	var mp := func(p: Vector2) -> Vector2:
		return Vector2(w.x - p.x if fx else p.x, w.y - p.y if fy else p.y)
	var mr := func(r: Rect2) -> Rect2:
		var a: Vector2 = mp.call(r.position)
		var b: Vector2 = mp.call(r.end)
		return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), r.size)
	out.start = mp.call(out.start)
	out.arena = mr.call(out.arena)
	for key: String in ["buildings", "roads"]:
		var list: Array = []
		for r: Rect2 in out[key]:
			list.append(mr.call(r))
		out[key] = list
	for key: String in ["checkpoints", "barrel_spots", "spawn_points", "chokes"]:
		var list: Array = []
		for p: Vector2 in out[key]:
			list.append(mp.call(p))
		out[key] = list
	for p: Array in out.props:
		p[0] = mp.call(p[0])
		if fx != fy:
			p[2] = -float(p[2])   # one mirror flips the turn; two cancel out


static func _shuffle(list: Array, rng: RandomNumberGenerator) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = list[i]
		list[i] = list[j]
		list[j] = tmp
