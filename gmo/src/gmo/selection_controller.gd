extends Node

# Initialize after the original character screen. GMO must never be a dependency
# of the native screen script or replace its ready/input/player-joining logic.
var _screen = null
var _fusion = null
var _controls = null
var _first = [null, null, null, null]
var _previews = [{}, {}, {}, {}]
var _consume_cancel_release = false
var _cancel_player = 0
var _player_count = 0
var _cooperative = false
var _installed = false


func _ready() -> void:
	call_deferred("_install")


func _install() -> void:
	_screen = get_parent()
	_fusion = load("res://gmo/fusion.gd")
	var controls_script = load("res://gmo/selection_controls.gd")
	if _fusion == null or not _fusion.can_instance() or controls_script == null or not controls_script.can_instance():
		_show_unavailable()
		return
	_controls = controls_script.new()
	_controls.mode_enabled = ProgressData.settings.get("gmo_mode_toggled", false)
	_controls.preset = ProgressData.settings.get("gmo_balance_preset", "default")
	_controls.custom_balance = _fusion.balance_values("custom", ProgressData.settings.get("gmo_custom_balance", [-10, 10, 15, 3]))
	# Use the existing header space. Adding another VBox row pushed the character
	# grid below the viewport at smaller window heights.
	_screen.add_child(_controls)
	_controls.anchor_right = 1.0
	_controls.margin_left = 340
	_controls.margin_right = -25
	_controls.margin_top = 32
	_controls.margin_bottom = 84
	_controls.connect("configured", self, "_reset")
	_controls.connect("reset_requested", self, "_reset")
	for index in _screen._get_inventories().size():
		var inventory = _screen._get_inventories()[index]
		for binding in [["element_pressed", "_on_element_pressed", "_on_pressed"], ["element_hovered", "_on_element_hovered", "_on_hovered"], ["element_focused", "_on_element_focused", "_on_focused"]]:
			if inventory.is_connected(binding[0], _screen, binding[1]):
				inventory.disconnect(binding[0], _screen, binding[1])
			inventory.connect(binding[0], self, binding[2], [index])
		inventory.connect("elements_changed", self, "_queue_refresh")
	var back = _screen.get_node("%BackButton")
	if back.is_connected("pressed", _screen, "_on_BackButton_pressed"):
		back.disconnect("pressed", _screen, "_on_BackButton_pressed")
	back.connect("pressed", self, "_on_back")
	_screen.get_node("%CoopButton").connect("coop_initialized", self, "_on_mode_changed")
	CoopService.connect("connected_players_updated", self, "_on_players_changed")
	_register_focus()
	_player_count = RunData.get_player_count()
	_cooperative = RunData.is_coop_run
	_installed = true
	_update_hint()


func _show_unavailable() -> void:
	var label = Label.new()
	label.text = "GMO could not load. Standard character selection is available."
	label.autowrap = true
	_screen.add_child(label)
	label.anchor_right = 1.0
	label.margin_left = 340
	label.margin_right = -25
	label.margin_top = 32
	label.margin_bottom = 84
	printerr("GMO: character-selection controller could not load its resources.")


func _register_focus() -> void:
	var emulator = _screen._get_focus_emulator(0)
	var data = FocusEmulatorBaseData.new()
	data.path = emulator.get_path_to(_controls)
	data.contain_horizontal_focus_exception_paths = []
	data.require_entry_from_control_paths = []
	data.focus_neighbour_top_paths = []
	data.focus_neighbour_bottom_paths = []
	data.focus_neighbour_left_paths = []
	data.focus_neighbour_right_paths = []
	emulator.focus_base_data.append(data)
	emulator._focus_base_nodes.append(_controls)
	# Make the row reachable from the original keyboard/controller focus graph.
	var back = _screen.get_node("%BackButton")
	var toggle = _controls.get_toggle()
	back.focus_neighbour_right = back.get_path_to(toggle)
	toggle.focus_neighbour_top = toggle.get_path_to(back)
	toggle.focus_neighbour_left = toggle.get_path_to(back)
	toggle.focus_neighbour_bottom = toggle.get_path_to(_screen._inventory1)


func _index(element: InventoryElement, inventory_index: int) -> int:
	var player = FocusEmulatorSignal.get_player_index(element)
	if player < 0 and not RunData.is_coop_run:
		player = inventory_index
	if player < 0 or player >= RunData.get_player_count():
		return -1
	return player


func _on_pressed(element: InventoryElement, inventory_index: int) -> void:
	if not _controls.mode_enabled:
		_screen._on_element_pressed(element, inventory_index)
		return
	var player = _index(element, inventory_index)
	if player < 0 or _screen._has_player_selected[player]:
		return
	if element.is_special and not element.is_random:
		return
	var candidate = element.item
	if element.is_random:
		var choices = []
		for possible in _screen.displayed_elements[0]:
			if not possible.is_locked and (_first[player] == null or _fusion.incompatibility(_first[player], possible) == ""):
				choices.append(possible)
		if choices.empty():
			_controls.set_hint("No compatible unlocked character. Reset fusion to choose again.")
			return
		candidate = Utils.get_rand_element(choices)
	if candidate == null or candidate.is_locked:
		return
	if _first[player] == null:
		_first[player] = candidate
		_screen._get_panels()[player].set_data(candidate, player)
		_refresh()
		_update_hint()
		return
	var reason = _fusion.incompatibility(_first[player], candidate)
	if reason != "":
		_controls.set_hint(reason)
		return
	var combined = _preview(player, candidate)
	_screen._player_characters[player] = combined
	_screen._get_panels()[player].set_data(combined, player)
	_screen._set_selected_element(player)
	_update_hint()


func _on_hovered(element: InventoryElement, inventory_index: int) -> void:
	_on_focused(element, inventory_index)


func _on_focused(element: InventoryElement, inventory_index: int) -> void:
	# Let the native screen own locked/random panels, focus state, and temporary
	# single-character stats. Never replace element.item or apply fusion effects
	# merely to show a preview: this used to leak REPLACE-effect state on hover.
	_screen._on_element_focused(element, inventory_index)
	if not _controls.mode_enabled:
		return
	var player = _index(element, inventory_index)
	if player < 0 or _screen._has_player_selected[player] or _first[player] == null:
		return
	if _screen._latest_focused_element[player] != element:
		return
	if element.is_random:
		_controls.set_hint("Choose a random compatible second character.")
		return
	if element.is_special or element.item == null:
		return
	var reason = _fusion.incompatibility(_first[player], element.item)
	if reason != "":
		_controls.set_hint(reason)
		return
	var combined = _preview(player, element.item)
	_screen._get_panels()[player].set_data(combined, player)
	if not RunData.is_coop_run:
		_screen.update_info_panel(combined)
	_controls.set_hint("Second: " + tr(element.item.name) + " · select to continue")


func _preview(player: int, candidate: CharacterData) -> CharacterData:
	var key = candidate.my_id
	if not _previews[player].has(key):
		_previews[player][key] = _fusion.create(_first[player], candidate, _controls.preset, _controls.custom_balance)
	return _previews[player][key]


func _reset() -> void:
	_first = [null, null, null, null]
	_previews = [{}, {}, {}, {}]
	_consume_cancel_release = false
	for player in RunData.get_player_count():
		_screen._clear_selected_element(player)
	CoopService.listening_for_inputs = RunData.is_coop_run
	_refresh()
	_update_hint()


func _on_back() -> void:
	if _controls.mode_enabled:
		for first in _first:
			if first != null:
				_reset()
				_focus_inventory(0)
				return
	_screen._on_BackButton_pressed()


func _input(event: InputEvent) -> void:
	if not _installed:
		return
	var cancel_released = event.is_action_released("ui_cancel")
	if _cancel_player < RunData.get_player_count():
		cancel_released = cancel_released or Utils.is_player_cancel_released(event, _cancel_player)
	if _consume_cancel_release and cancel_released:
		_consume_cancel_release = false
		get_tree().set_input_as_handled()
		return
	if _controls.is_custom_open():
		if event.is_action_pressed("ui_cancel") or Utils.is_player_cancel_pressed(event, 0):
			_controls.close_custom()
			_consume_cancel_release = true
			_cancel_player = 0
			get_tree().set_input_as_handled()
		return
	if not _controls.mode_enabled:
		return
	for player in RunData.get_player_count():
		if not Utils.is_player_cancel_pressed(event, player):
			continue
		if _screen._has_player_selected[player]:
			_screen._clear_selected_element(player)
		elif _first[player] != null:
			_first[player] = null
			_previews[player] = {}
		else:
			continue
		_consume_cancel_release = true
		_cancel_player = player
		CoopService.listening_for_inputs = RunData.is_coop_run
		_refresh()
		_update_hint()
		_focus_inventory(player)
		get_tree().set_input_as_handled()
		return


func _focus_inventory(player: int) -> void:
	var inventory = _screen._inventory1
	if inventory.get_child_count() > 0:
		Utils.call_deferred("focus_player_control", inventory.get_child(0), player)


func _on_mode_changed(_active: bool) -> void:
	call_deferred("_sync_players")


func _on_players_changed(_players: Array) -> void:
	call_deferred("_sync_players")


func _sync_players() -> void:
	if not _installed:
		return
	if _player_count != RunData.get_player_count() or _cooperative != RunData.is_coop_run:
		_player_count = RunData.get_player_count()
		_cooperative = RunData.is_coop_run
		_reset()


func _queue_refresh() -> void:
	call_deferred("_refresh")


func _refresh() -> void:
	if _controls == null:
		return
	for element in _screen._inventory1.get_children():
		if not element is InventoryElement or element.item == null:
			continue
		if not element.has_meta("gmo_base_tooltip"):
			element.set_meta("gmo_base_tooltip", element.hint_tooltip)
			element.set_meta("gmo_base_modulate", element.self_modulate)
		element.self_modulate = element.get_meta("gmo_base_modulate")
		element.hint_tooltip = element.get_meta("gmo_base_tooltip")
		if not _controls.mode_enabled or RunData.is_coop_run or _first[0] == null or element.is_special:
			continue
		if element.item.my_id == _first[0].my_id:
			element.self_modulate = Color(1, 1, 0.65, 1)
			element.hint_tooltip = "First character selected. Choose another character."
			continue
		var reason = _fusion.incompatibility(_first[0], element.item)
		if reason != "":
			var color = element.self_modulate
			color.a *= 0.35
			element.self_modulate = color
			element.hint_tooltip = reason


func _update_hint() -> void:
	var parts = []
	for player in RunData.get_player_count():
		var prefix = ("P%s: " % (player + 1)) if RunData.is_coop_run else ""
		if _screen._has_player_selected[player]:
			parts.append(prefix + "Fusion ready")
		elif _first[player] != null:
			parts.append(prefix + tr(_first[player].name) + " + … · choose second character")
		else:
			parts.append(prefix + "Choose first character")
	_controls.set_hint(PoolStringArray(parts).join("   |   "))
