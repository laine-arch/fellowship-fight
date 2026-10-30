class_name Chars
extends RefCounted
## Display data for each fighter (gameplay numbers live in Sim.CHARS).
## To add a fighter: add art under res://art/fighters/<id>/, an entry here and in Sim.CHARS,
## then rebuild the rig with tools/build_fighters.gd.

const LIST := [
	{"id": "bubbles", "name": "Bubbles", "tag": "Fast hands, floaty bubbles", "super": "BUBBLE STORM", "stats": {"Speed": 5, "Power": 3, "Range": 4}},
	{"id": "preacher", "name": "The Preacher", "tag": "Heavy hitter, loud waves", "super": "THE BENEDICTION", "stats": {"Speed": 3, "Power": 5, "Range": 4}},
]
const LOCKED_SLOTS := 2
const STAGES := [{"id": "plaza", "name": "Welcome Plaza", "image": "res://art/stages/welcome_plaza.jpg"}]


static func get_char(id: String) -> Dictionary:
	for c in LIST:
		if c.id == id: return c
	return LIST[0]


static func head(id: String) -> Texture2D:
	return load("res://art/fighters/%s/head.webp" % id)


## Square portrait for the select screen and HUD.
static func portrait(id: String) -> Texture2D:
	return load("res://art/fighters/%s/portrait.webp" % id)


static func bust(id: String) -> Texture2D:
	return load("res://art/fighters/%s/bust.webp" % id)


static func rig(id: String) -> PackedScene:
	return load("res://fighters/%s.tscn" % id)


static func stage(id: String) -> Dictionary:
	for s in STAGES:
		if s.id == id: return s
	return STAGES[0]
