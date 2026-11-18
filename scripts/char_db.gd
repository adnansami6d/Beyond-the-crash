extends RefCounted
# The list of playable characters (demo texts) + which one is equipped (saved in user://selected_character.cfg).
# To add a character: put its folder under res://characters/..., add one entry to LIST, add a portrait picture.
# "anims" = file prefix of the 3 clip files: <anims>.res, <anims>_rifle.res, <anims>_axe.res

const SAVE_PATH := "user://selected_character.cfg"

const LIST := [
	{
		"id": "rafi", "name": "Rafi", "title": "The Lone Survivor", "age": 25, "height": 175,
		"glb": "res://characters/boy.glb", "anims": "res://characters/anims/boy_anims",
		"portrait": "res://assets/ui/char_rafi.png",
		"story": "Rafi was a plane passenger who woke up alone on the beach after the crash. He does not talk much, but he never leaves a camp unfinished. Every tree he cuts and every wall he builds is a promise that he will see his family again.",
		"ability_name": "Strong Arms", "ability_text": "Good at chopping and building. (demo: +15% axe speed)",
	},
	{
		"id": "valery", "name": "Valery", "title": "The Fearless Survivor", "age": 22, "height": 168,
		"glb": "res://characters/alt/valery/valery.glb", "anims": "res://characters/alt/valery/valery_anims",
		"portrait": "res://assets/ui/char_valery.png",
		"story": "A fearless survivor, Valery always moves forward. Her calm mind and quick decisions help her survive in any situation. She believes that hope never dies, no matter how dark the island becomes.",
		"ability_name": "Agile Survivor", "ability_text": "Good at running and escaping. (demo: +15% movement speed)",
	},
	{
		"id": "luna", "name": "Luna", "title": "The Quiet Fighter", "age": 20, "height": 165,
		"glb": "res://characters/alt/girl2/girl2.glb", "anims": "res://characters/alt/girl2/girl2_anims",
		"portrait": "res://assets/ui/char_luna.png",
		"story": "Luna was a student travelling to meet her sister when the plane went down. She speaks softly, but when a night wave of bandits comes she is the last one to step back. She keeps a small notebook with the name of everyone she has helped on the island.",
		"ability_name": "Sharp Eyes", "ability_text": "Good at finding resources and spotting enemies early. (demo)",
	},
]


static func by_id(id: String) -> Dictionary:
	for c in LIST:
		if c["id"] == id:
			return c
	return LIST[0]


static func selected_id() -> String:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		return by_id(String(cf.get_value("character", "id", LIST[0]["id"])))["id"]
	return LIST[0]["id"]


static func selected() -> Dictionary:
	return by_id(selected_id())


static func set_selected(id: String) -> void:
	var cf := ConfigFile.new()
	cf.set_value("character", "id", by_id(id)["id"])
	cf.save(SAVE_PATH)
