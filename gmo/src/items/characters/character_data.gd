class_name CharacterData
extends ItemData

export (Array, String) var wanted_tags
export (Array, String) var banned_item_groups
export (Array, String) var banned_items
export (Array, Resource) var starting_weapons
export (Array, Resource) var starting_items


func get_category() -> int:
	return Category.CHARACTER


# GMO fields are exported so Resource.duplicate retains fusion identity.
export (Array, String) var gmo_character_ids = []
export (Array, int) var gmo_character_hashes = []
export (Array, int) var gmo_balance = []
export (String) var gmo_preset = "default"


func _generate_hashes() -> void:
	._generate_hashes()
	gmo_character_hashes = []
	for character_id in gmo_character_ids:
		gmo_character_hashes.append(Keys.generate_hash(character_id))


func has_character_hash(character_hash: int) -> bool:
	return my_id_hash == character_hash or gmo_character_hashes.has(character_hash)


func get_effects_text(player_index: int) -> String:
	if gmo_character_ids.empty():
		return .get_effects_text(player_index)
	var text = ""
	for character_id in gmo_character_ids:
		var source = ItemService.get_element_safe(ItemService.characters, character_id)
		if source == null:
			continue
		if text != "":
			text += "\n\n"
		text += "[b]" + tr(source.name) + "[/b]\n" + source.get_effects_text(player_index)
	text += "\n\n[b]GMO balance (" + gmo_preset.capitalize() + ")[/b]"
	var shown = false
	var balance_keys = ["xp_gain", "items_price", "number_of_enemies", "enemy_speed"]
	for i in gmo_balance.size():
		if gmo_balance[i] == 0:
			continue
		var effect = Effect.new()
		effect.key = balance_keys[i]
		effect.value = gmo_balance[i]
		var beneficial = gmo_balance[i] > 0 if i == 0 else gmo_balance[i] < 0
		effect.effect_sign = Effect.Sign.POSITIVE if beneficial else Effect.Sign.NEGATIVE
		effect.custom_args = []
		effect._generate_hashes()
		text += "\n" + effect.get_text(player_index)
		shown = true
	if not shown:
		text += "\nNo additional penalties."
	return text
