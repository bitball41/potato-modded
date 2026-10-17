extends Reference

# Native Godot 3.7 adaptation of Flabort's GMO 0.2.0.
# All character abilities come from this build's CharacterData resources,
# including active DLC resources. No abilities are reimplemented in JavaScript.
const PAIRS = preload("res://gmo/upstream_compatibility.gd")
const PREFIX = "gmo_v1__"
const BALANCE_KEYS = ["xp_gain", "items_price", "number_of_enemies", "enemy_speed"]
const PRESETS = {
	"default": [-10, 10, 15, 3],
	"original": [-25, 40, 50, 10],
	"easy": [0, 0, 0, 0]
}
const ICON = "res://mods-unpacked/flabort-GMO/content/characters/GMO_dummy/GMO_hybrid_reworked.png"


static func balance_values(preset: String, custom: Array = []) -> Array:
	if PRESETS.has(preset):
		return PRESETS[preset].duplicate()
	if custom.size() != 4:
		return PRESETS["default"].duplicate()
	return [int(clamp(custom[0], -90, 500)), int(clamp(custom[1], -90, 1000)), int(clamp(custom[2], -90, 500)), int(clamp(custom[3], -90, 300))]


static func resolve(character_id: String) -> CharacterData:
	if not character_id.begins_with(PREFIX):
		return ItemService.get_element_safe(ItemService.characters, character_id)
	var parts = character_id.split("__")
	if parts.size() != 8:
		return null
	var first = ItemService.get_element_safe(ItemService.characters, parts[2])
	var second = ItemService.get_element_safe(ItemService.characters, parts[3])
	if first == null or second == null:
		return null
	var values = []
	for i in range(4, 8):
		if not parts[i].is_valid_integer():
			return null
		values.append(int(parts[i]))
	# Saved penalties are authoritative, even if a later release changes presets.
	return create(first, second, parts[1], values, true)


static func _union(first: Array, second: Array) -> Array:
	var result = first.duplicate()
	for value in second:
		if not result.has(value):
			result.append(value)
	return result


static func _traits(first: CharacterData, second: CharacterData) -> Dictionary:
	if first.my_id > second.my_id:
		var swap = first
		first = second
		second = swap
	var result = {"weapon_slot": 6, "no_melee_weapons": 0, "no_ranged_weapons": 0, "min_weapon_tier": 0, "max_weapon_tier": 3}
	for character in [first, second]:
		for effect in character.effects:
			if not result.has(effect.key) or effect.custom_key != "":
				continue
			if effect.storage_method == Effect.StorageMethod.REPLACE:
				result[effect.key] = effect.value
			elif effect.storage_method == Effect.StorageMethod.SUM:
				result[effect.key] += effect.value
	return result


static func _weapon_allowed(weapon: WeaponData, traits: Dictionary) -> bool:
	if traits.weapon_slot <= 0:
		return false
	if traits.no_melee_weapons > 0 and weapon.type == WeaponType.MELEE:
		return false
	if traits.no_ranged_weapons > 0 and weapon.type == WeaponType.RANGED:
		return false
	return weapon.tier >= traits.min_weapon_tier and weapon.tier <= traits.max_weapon_tier


static func incompatibility(first: CharacterData, second: CharacterData) -> String:
	if first == null or second == null:
		return "Choose two characters."
	if first.my_id == second.my_id:
		return "Choose a different second character."
	if PAIRS.INCOMPATIBLE.get(first.my_id, []).has(second.my_id) or PAIRS.INCOMPATIBLE.get(second.my_id, []).has(first.my_id):
		return "This pairing is excluded by GMO's original compatibility rules."
	# New/DLC characters are checked by their actual mechanics, not a stale roster.
	var replacements = {}
	var all_effects = first.effects + second.effects
	for effect in all_effects:
		if effect.storage_method != Effect.StorageMethod.REPLACE or effect.custom_key != "":
			continue
		if replacements.has(effect.key) and replacements[effect.key] != effect.value:
			return "Conflicting character limits: " + effect.key.replace("_", " ") + "."
		replacements[effect.key] = effect.value
	var traits = _traits(first, second)
	if traits.weapon_slot < 0:
		return "These characters leave fewer than zero weapon slots."
	if traits.min_weapon_tier > traits.max_weapon_tier:
		return "These characters require incompatible weapon tiers."
	if traits.weapon_slot > 0 and traits.no_melee_weapons > 0 and traits.no_ranged_weapons > 0:
		return "These characters forbid both melee and ranged weapons."
	var forced_weapons = 0
	for effect in all_effects:
		if effect.custom_key == "starting_weapon" or effect.custom_key == "cursed_starting_weapon":
			var weapon = ItemService.get_element_safe(ItemService.weapons, effect.key)
			if weapon != null and not _weapon_allowed(weapon, traits):
				return "A required starting weapon conflicts with this pairing."
			forced_weapons += effect.value
	if forced_weapons > traits.weapon_slot:
		return "Required starting weapons exceed this pairing's weapon slots."
	if traits.weapon_slot > 0:
		var has_start = false
		for weapon in _union(first.starting_weapons, second.starting_weapons):
			if _weapon_allowed(weapon, traits) and ProgressData.weapons_unlocked.has(weapon.weapon_id_hash):
				has_start = true
				break
		if not has_start and first.starting_items.empty() and second.starting_items.empty():
			return "This pairing has no unlocked, compatible starting weapon."
	return ""


static func create(first: CharacterData, second: CharacterData, preset: String = "default", custom: Array = [], restore_values: bool = false) -> CharacterData:
	# Canonical order makes reversed selections the same build and save identity.
	if first.my_id > second.my_id:
		var swap = first
		first = second
		second = swap
	var values = balance_values("custom" if restore_values else preset, custom)
	var character = first.duplicate()
	character.gmo_character_ids = [first.my_id, second.my_id]
	character.gmo_balance = values.duplicate()
	character.gmo_preset = preset
	character.my_id = PREFIX + preset + "__" + first.my_id + "__" + second.my_id
	for value in values:
		character.my_id += "__" + str(value)
	character._generate_hashes()
	character.name = "GMO: " + TranslationServer.translate(first.name) + " + " + TranslationServer.translate(second.name)
	character.icon = load(ICON)
	character.can_be_looted = false
	character.tracking_text = "[EMPTY]"
	character.effects = []
	var replacements = {}
	for source in [first, second]:
		for source_effect in source.effects:
			# Identical REPLACE effects must apply/unapply once, including hover previews.
			if source_effect.storage_method == Effect.StorageMethod.REPLACE and source_effect.custom_key == "":
				if replacements.has(source_effect.key):
					continue
				replacements[source_effect.key] = true
			var effect = source_effect.duplicate(true)
			effect._generate_hashes()
			character.effects.append(effect)
	for i in BALANCE_KEYS.size():
		if values[i] == 0:
			continue
		var effect = Effect.new()
		effect.key = BALANCE_KEYS[i]
		effect.value = values[i]
		var beneficial = values[i] > 0 if i == 0 else values[i] < 0
		effect.effect_sign = Effect.Sign.POSITIVE if beneficial else Effect.Sign.NEGATIVE
		effect.custom_args = []
		effect._generate_hashes()
		character.effects.append(effect)
	character.wanted_tags = _union(first.wanted_tags, second.wanted_tags)
	character.banned_item_groups = _union(first.banned_item_groups, second.banned_item_groups)
	character.banned_items = _union(first.banned_items, second.banned_items)
	character.item_appearances = _union(first.item_appearances, second.item_appearances)
	character.tags = _union(first.tags, second.tags)
	character.starting_items = _union(first.starting_items, second.starting_items)
	character.starting_weapons = []
	var traits = _traits(first, second)
	for weapon in _union(first.starting_weapons, second.starting_weapons):
		if _weapon_allowed(weapon, traits):
			character.starting_weapons.append(weapon)
	return character


static func ensure_progress(character: CharacterData) -> void:
	if character == null or character.gmo_character_ids.empty():
		return
	var progress = null
	for existing in ProgressData.difficulties_unlocked:
		if existing.character_id == character.my_id:
			progress = existing
			break
	if progress == null:
		progress = CharacterDifficultyInfo.new(character.my_id)
		ProgressData.difficulties_unlocked.append(progress)
	for zone in ZoneService.zones:
		var found = false
		for existing in progress.zones_difficulty_info:
			if existing.zone_id == zone.my_id:
				found = true
		if found:
			continue
		var info = ZoneDifficultyInfo.new(zone.my_id)
		var unlocked = ProgressData.MAX_DIFFICULTY
		for character_id in character.gmo_character_ids:
			var native_info = ProgressData.get_character_difficulty_info(Keys.generate_hash(character_id), zone.my_id)
			unlocked = min(unlocked, native_info.max_selectable_difficulty)
		info.max_selectable_difficulty = unlocked
		progress.zones_difficulty_info.append(info)
