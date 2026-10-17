class_name BaseSelection
extends Control

export (Texture) var random_icon
export (bool) var add_random_element = true


export (bool) var enable_coop_panels = true

var displayed_elements: = [[], [], [], []]
var _has_player_selected: = [false, false, false, false]
var _displayed_panel_data_element = [null, null, null, null]
var _latest_focused_element: = [null, null, null, null]
var __going_back: = false


var _selections_completed_timer: Timer
var _selections_completed_delay: = 0.8

onready var _inventory1: Container = $"%Inventory1"
onready var _inventory2: Container = get_node_or_null("%Inventory2")
onready var _inventory3: Container = get_node_or_null("%Inventory3")
onready var _inventory4: Container = get_node_or_null("%Inventory4")
onready var _panel1: Control = $"%Panel1"
onready var _panel2: Control = $"%Panel2"
onready var _panel3: Control = $"%Panel3"
onready var _panel4: Control = $"%Panel4"
onready var _background: TextureRect = $"%Background"


func _ready() -> void :
	_selections_completed_timer = Timer.new()
	_selections_completed_timer.wait_time = _selections_completed_delay
	_selections_completed_timer.one_shot = true
	_selections_completed_timer.autostart = false
	add_child(_selections_completed_timer)
	var _error_timeout = _selections_completed_timer.connect("timeout", self, "_on_selections_completed_timer_timeout")

	_init_players()

	var inventories = _get_inventories()
	for i in inventories.size():
		var inventory = inventories[i]
		inventory.connect("element_pressed", self, "_on_element_pressed", [i])
		inventory.connect("element_hovered", self, "_on_element_hovered", [i])
		inventory.connect("element_focused", self, "_on_element_focused", [i])

	var did_set_focus: = [false, false, false, false]
	for player_index in RunData.get_player_count():
		var last_elt = Utils.last_elt_selected[player_index]
		if last_elt == null:
			continue
		var my_id = last_elt.my_id_hash
		var element: = _find_inventory_element_by_id(my_id, player_index)
		if element != null:
			
			Utils.call_deferred("focus_player_control", element, player_index)
			did_set_focus[player_index] = true
	Utils.reset_last_elt_selected()

	for player_index in RunData.get_player_count():
		if did_set_focus[player_index]:
			continue
		var inventory = inventories[player_index % inventories.size()]
		if inventory.get_child_count() == 0:
			continue
		var element = inventory.get_child(0)
		Utils.call_deferred("focus_player_control", element, player_index)


func _input(event: InputEvent) -> void :
	for player_index in RunData.get_player_count():
		if Utils.is_player_cancel_pressed(event, player_index) and _has_player_selected[player_index]:
			_clear_selected_element(player_index)
			return
	if event.is_action_released("ui_cancel") and _can_go_back_with_ui_cancel():
		_manage_back()
		return


func _init_players() -> void :
	
	_set_base_ui_player_count(RunData.get_player_count(), RunData.is_coop_run, true)


func _get_unlocked_elements(_player_index: int) -> Array:
	return []


func _get_all_possible_elements(_player_index: int) -> Array:
	return []


func _get_displayed_elements(possible_elements: Array, unlocked_elements: Array) -> Array:
	var result: = []
	for element in possible_elements:
		var new_element = element.duplicate()

		new_element.is_locked = not unlocked_elements.has(new_element.my_id_hash)

		if not _is_locked_elements_displayed() and new_element.is_locked:
			continue

		result.push_back(new_element)

	return result


func _set_base_ui_player_count(count: int, is_coop_run: bool, initialize: bool = false) -> void :
	if count == 0 or not is_coop_run:
		
		for player_index in CoopService.UI_MAX_PLAYER_COUNT:
			_clear_selected_element(player_index)

	if not enable_coop_panels:
		count = 1

	var panels: = _get_panels()
	for i in range(panels.size()):
		var panel = panels[i]
		
		if count == 0:
			panel.visible = false
		if i >= count:
			
			panel.visible = false
		panel.player_color_index = i if is_coop_run and enable_coop_panels else - 1

	var inventories = _get_inventories()
	var inventory_containers = _get_inventory_containers()
	for i in range(inventories.size()):
		var inventory = inventories[i]
		var container = inventory_containers[i]

		var was_visible = container.visible
		container.visible = i < count

		var inventory_appeared: bool = container.visible and ( not was_visible or not is_coop_run or initialize)
		if inventory_appeared:
			var possible_elements = _get_all_possible_elements(i)
			var unlocked_elements = _get_unlocked_elements(i)
			displayed_elements[i] = _get_displayed_elements(possible_elements, unlocked_elements)
			inventory.clear_elements()
			if possible_elements.size() > 1 and add_random_element:
				inventory.add_special_element(random_icon, true)
			inventory.set_elements(displayed_elements[i], false, false)

		inventory.mouse_focus_enabled = container.visible and not is_coop_run


func _set_selected_element(p_player_index: int) -> void :
	if _has_player_selected[p_player_index]:
		return

	_get_panels()[p_player_index].selected = RunData.is_coop_run
	_has_player_selected[p_player_index] = true

	for player_index in RunData.get_player_count():
		if not _has_player_selected[player_index]:
			return

	
	if RunData.is_coop_run and RunData.get_player_count() <= 1:
		return

	
	CoopService.listening_for_inputs = false

	if RunData.is_coop_run:
		_selections_completed_timer.start()
	else:
		_on_selections_completed()


func _on_selections_completed_timer_timeout() -> void :
	_on_selections_completed()


func _clear_selected_element(player_index: int) -> void :
	_get_panels()[player_index].selected = false
	_has_player_selected[player_index] = false
	_selections_completed_timer.stop()


func _display_element_panel_data(element: InventoryElement, player_index: int) -> void :
	_displayed_panel_data_element[player_index] = element
	var panel = _get_panels()[player_index]
	if element.is_random:
		panel.set_custom_data("RANDOM", element.get_inventory_icon())
	else:
		panel.set_data(element.item, player_index)


func _manage_back() -> void :
	if not __going_back:
		__going_back = true
		_go_back()


func _go_back() -> void :
	pass


func _can_go_back_with_ui_cancel() -> bool:
	
	return not RunData.play_mode != RunData.PlayMode.SOLO


func _on_element_pressed(_element: InventoryElement, _inventory_player_index: int) -> void :
	pass


func _on_element_hovered(element: InventoryElement, inventory_player_index: int) -> void :
	_on_element_focused(element, inventory_player_index)


func _on_element_focused(element: InventoryElement, inventory_player_index: int, displayPanelData: bool = true) -> void :
	var player_index = FocusEmulatorSignal.get_player_index(element)
	
	
	if player_index < 0:
		player_index = inventory_player_index

	var panel = _get_panels()[player_index]
	if element.is_random:
		if displayPanelData:
			panel._show_random()
		panel.visible = true
	else:
		panel.visible = not element.is_special

	_latest_focused_element[player_index] = element
	if panel.visible and displayPanelData:
		_display_element_panel_data(element, player_index)


func _on_selections_completed() -> void :
	
	pass


func _set_initial_focus() -> void :
	
	pass


func _get_reward_type() -> int:
	return RewardType.CHARACTER


func _is_locked_elements_displayed() -> bool:
	return true


func _get_inventory_containers() -> Array:
	var containers: = [_inventory1]
	for inventory in [_inventory2, _inventory3, _inventory4]:
		if inventory != null:
			containers.push_back(inventory)
	return containers


func _get_inventories() -> Array:
	
	return _get_inventory_containers()


func _get_panels() -> Array:
	return [_panel1, _panel2, _panel3, _panel4]


func _get_focus_emulator(player_index: int) -> FocusEmulator:
	return get_node("FocusEmulator%s" % (player_index + 1)) as FocusEmulator


func _find_inventory_element_by_id(my_id: int, player_index: int) -> InventoryElement:
	var inventories = _get_inventories()
	var inventory = inventories[player_index % inventories.size()]
	for child in inventory.get_children():
		if child.is_special:
			continue
		if child.item.my_id_hash == my_id:
			return child
	return null



func _change_scene(path: String) -> void :
	var _error = get_tree().change_scene(path)
