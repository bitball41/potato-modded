extends HBoxContainer

signal configured()
signal reset_requested()

const PRESET_NAMES = ["default", "original", "easy", "custom"]
const CUSTOM_LABELS = ["XP gain (%)", "Item prices (%)", "Enemy count (%)", "Enemy speed (%)"]
const CUSTOM_MAX = [500, 1000, 500, 300]

var mode_enabled = false
var preset = "default"
var custom_balance = [-10, 10, 15, 3]
var _toggle: CheckButton
var _preset_button: OptionButton
var _custom_button: Button
var _reset_button: Button
var _hint: Label
var _dialog: ConfirmationDialog
var _spins = []
var _listening_before_dialog = false


func _ready() -> void:
	name = "GMOControls"
	add_constant_override("separation", 20)
	rect_min_size.y = 52
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle = CheckButton.new()
	_toggle.text = "GMO"
	_toggle.hint_tooltip = "Genetically Modified Overkill: fuse two different characters, including Abyssal Terrors."
	_toggle.pressed = mode_enabled
	add_child(_toggle)
	_preset_button = OptionButton.new()
	for title in ["Default balance", "Original balance", "Easy balance", "Custom balance"]:
		_preset_button.add_item(title)
	if not PRESET_NAMES.has(preset):
		preset = "default"
	_preset_button.selected = PRESET_NAMES.find(preset)
	add_child(_preset_button)
	_custom_button = Button.new()
	_custom_button.text = "Customize"
	add_child(_custom_button)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_hint.valign = Label.VALIGN_CENTER
	add_child(_hint)
	_reset_button = Button.new()
	_reset_button.text = "Reset fusion"
	add_child(_reset_button)
	_build_dialog()
	_toggle.connect("toggled", self, "_on_toggled")
	_preset_button.connect("item_selected", self, "_on_preset_selected")
	_custom_button.connect("pressed", self, "_show_custom")
	_reset_button.connect("pressed", self, "_on_reset")
	_update_visibility()


func _build_dialog() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.window_title = "Custom GMO balance"
	_dialog.dialog_hide_on_ok = true
	add_child(_dialog)
	# AcceptDialog/ConfirmationDialog has no get_vbox() in Godot 3.x.
	var content = VBoxContainer.new()
	content.add_constant_override("separation", 16)
	_dialog.add_child(content)
	_dialog.get_label().hide()
	var explanation = Label.new()
	explanation.text = "These modifiers apply in addition to both characters' abilities."
	content.add_child(explanation)
	for i in 4:
		var row = HBoxContainer.new()
		row.add_constant_override("separation", 30)
		var label = Label.new()
		label.text = CUSTOM_LABELS[i]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var spin = SpinBox.new()
		spin.min_value = -90
		spin.max_value = CUSTOM_MAX[i]
		spin.step = 1
		spin.rect_min_size.x = 180
		row.add_child(spin)
		_spins.append(spin)
		content.add_child(row)
	_dialog.connect("confirmed", self, "_on_custom_confirmed")
	_dialog.connect("popup_hide", self, "_on_custom_closed")


func _show_custom() -> void:
	for i in _spins.size():
		_spins[i].value = custom_balance[i]
	_listening_before_dialog = CoopService.listening_for_inputs
	CoopService.listening_for_inputs = true
	_dialog.popup_centered(Vector2(850, 390))
	Utils.call_deferred("focus_player_control", _dialog.get_ok(), 0)


func _on_custom_confirmed() -> void:
	custom_balance = []
	for spin in _spins:
		custom_balance.append(int(spin.value))
	preset = "custom"
	_preset_button.selected = 3
	_publish_configuration()


func _on_toggled(value: bool) -> void:
	mode_enabled = value
	_publish_configuration()


func _on_preset_selected(index: int) -> void:
	preset = PRESET_NAMES[index]
	_publish_configuration()


func _publish_configuration() -> void:
	ProgressData.settings["gmo_mode_toggled"] = mode_enabled
	ProgressData.settings["gmo_balance_preset"] = preset
	ProgressData.settings["gmo_custom_balance"] = custom_balance.duplicate()
	ProgressData.save_settings()
	_update_visibility()
	emit_signal("configured")


func _update_visibility() -> void:
	_preset_button.visible = mode_enabled
	_custom_button.visible = mode_enabled and preset == "custom"
	_reset_button.visible = mode_enabled
	_hint.visible = mode_enabled
	var presets = {"default": [-10, 10, 15, 3], "original": [-25, 40, 50, 10], "easy": [0, 0, 0, 0]}
	var values = custom_balance if preset == "custom" else presets[preset]
	_preset_button.hint_tooltip = "XP: %s%%; item prices: %s%%; enemies: %s%%; enemy speed: %s%%" % values


func set_hint(message: String) -> void:
	_hint.text = message
	_hint.hint_tooltip = message


func _on_reset() -> void:
	emit_signal("reset_requested")


func get_toggle() -> CheckButton:
	return _toggle


func is_custom_open() -> bool:
	return _dialog != null and _dialog.visible


func close_custom() -> void:
	_dialog.hide()


func _on_custom_closed() -> void:
	CoopService.listening_for_inputs = _listening_before_dialog
	Utils.call_deferred("focus_player_control", _custom_button, 0)
