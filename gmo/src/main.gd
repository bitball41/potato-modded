class_name Main
extends Node

signal gold_spawned()

export (PackedScene) var gold_bag_scene: PackedScene
export (PackedScene) var gold_scene: PackedScene
export (PackedScene) var consumable_scene: PackedScene
export (Resource) var turret_effect: Resource
export (Resource) var landmines_effect: Resource
export (Array) var gold_sprites: Array
export (Array, Resource) var gold_pickup_sounds: Array
export (Array, Resource) var gold_alt_pickup_sounds: Array
export (Resource) var level_up_sound: Resource
export (Array, Resource) var run_won_sounds: Array
export (Array, Resource) var run_lost_sounds: Array
export (Array, Resource) var end_wave_sounds: Array
export (PackedScene) var mimic_scene: PackedScene


const EDGE_SIZE = 96
const MAX_GOLDS = 50
const MIN_GOLD_CHANCE = 0.5
const MIN_MAP_SIZE = 12

const CROSSHAIR_DIST_FROM_PLAYER_MANUAL_AIM = 200

var _cleaning_up: = false
var _active_golds: = []
var _consumables: = []
var _upgrades_to_process: = [[], [], [], []]
var _consumables_to_process: = [[], [], [], []]

var _end_wave_timer_timedout: = false

var _players: = []
var _next_gold_player: int
var _players_ui: = []
var _things_to_process_player_containers: = []

var _is_run_lost: bool
var _is_wave_failed: bool
var _is_run_won: bool
var _gold_bag: Node

var _is_chal_ui_displayed = false

var _proj_on_death_stat_caches: = [null, null, null, null]
var _items_spawned_this_wave: = 0
var _player_is_under_half_health: = [false, false, false, false]

var _is_horde_wave: = false
var _is_elite_wave: = false
var _is_fog_wave: = false
var _is_bullet_hell_wave: = false

var _elite_killed_bonus: = 0
var override_gold_bag_pos: = Vector2.ZERO

var _pool: = {}
var _pool_parent: = {}
var _skip_pause_check = false
var _crosshair_cursor_active: = false
var _current_pool_id: int = Keys.empty_hash
var _current_pool = null

var _spawn_projectile_args: = WeaponServiceSpawnProjectileArgs.new()
var _take_damage_args: = TakeDamageArgs.new( - 1)

onready var _entities_container: YSort = $"%Entities"
onready var _entity_spawner = $EntitySpawner
onready var _effects_manager = $EffectsManager
onready var _stats_manager = $"%StatsManager"
onready var _wave_manager = $WaveManager
onready var _floating_text_manager = $FloatingTextManager
onready var _effect_behaviors: = $EffectBehaviors
onready var _camera: MyCamera = $Camera
onready var _screenshaker = $Camera / Screenshaker
onready var _materials_container: Node2D = $"%Materials"
onready var _consumables_container: Node2D = $"%Consumables"
onready var _births_container: Node2D = $"%Births"
onready var _pause_menu = $UI / PauseMenu
onready var _end_wave_timer = $EndWaveTimer
onready var _upgrades_ui: UpgradesUI = $UI / UpgradesUI
onready var _coop_upgrades_ui: UpgradesUI = $UI / CoopUpgradesUI
onready var _wave_timer = $WaveTimer

onready var _wave_cleared_label = $UI / WaveClearedLabel
onready var _hud = $UI / HUD
onready var _ui_bonus_gold = $UI / HUD / LifeContainerP1 / UIBonusGold
onready var _ui_bonus_gold_pos = $UI / HUD / LifeContainerP1 / UIBonusGold / Position2D
onready var _current_wave_label = $UI / HUD / WaveContainer / CurrentWaveLabel
onready var _wave_timer_label = $UI / HUD / WaveContainer / WaveTimerLabel
onready var _ui_wave_container = $UI / HUD / WaveContainer
onready var _ui_things_to_process_margin_container: MarginContainer = $"%ThingsToProcessMarginContainer"
onready var _ui_dim_screen = $UI / DimScreen
onready var _tile_map = $TileMap
onready var _tile_map_limits = $"%TileMapLimits"
onready var _background = $CanvasLayer / Background
onready var _harvesting_timer = $HarvestingTimer
onready var _challenge_completed_ui = $UI / ChallengeCompletedUI
onready var _retry_wave = $UI / RetryWave

onready var _damage_vignette = $UI / DamageVignette
onready var _info_popup = $UI / InfoPopup
onready var _fps_label = $"%FPSLabel"
onready var _explosions: Node2D = $"Explosions"
onready var _effects: Node2D = $"Effects"
onready var _floating_texts: Node2D = $"%FloatingTexts"
onready var _player_projectiles: Node2D = $"%PlayerProjectiles"
onready var _enemy_projectiles: Node2D = $"%EnemyProjectiles"
onready var _half_second_timers: Node2D = $"%HalfSecondTimers"
onready var _crosshair: Sprite = $"%Crosshair"
onready var _fog_viewport: FogViewport = $"%fog_viewport"

signal end_of_the_wave
var _consumable_pool_id: int = Keys.empty_hash
var _gold_pool_id: int = Keys.empty_hash


func _ready() -> void :
	if DebugService.display_fps:
		_fps_label.show()

	if consumable_scene != null:
		_consumable_pool_id = Keys.generate_hash(consumable_scene.resource_path)

	if gold_scene != null:
		_gold_pool_id = Keys.generate_hash(gold_scene.resource_path)

	var _e = _entity_spawner.connect("players_spawned", self, "_on_EntitySpawner_players_spawned")

	MusicManager.tween(0)
	_pause_menu.enabled = true
	_updatehidingHUD()

	RunData.on_wave_start(_wave_timer)
	_next_gold_player = Utils.randi() % RunData.get_player_count()

	var _popup = _challenge_completed_ui.connect("started", self, "on_chal_popup")
	var _popout = _challenge_completed_ui.connect("finished", self, "on_chal_popout")

	_background.texture.gradient.colors[1] = ItemService.get_background_gradient_color()
	_tile_map.tile_set.tile_set_texture(0, RunData.get_background().get_tiles_sprite())
	_tile_map.outline.modulate = RunData.get_background().outline_color

	TempStats.reset()

	var _stats = RunData.connect("stats_updated", self, "on_stats_updated")

	_gold_bag = Utils.instance_scene_on_main(gold_bag_scene, get_gold_bag_pos())
	var current_zone = ZoneService.get_zone_data(RunData.current_zone).duplicate()
	var current_wave_data = ZoneService.get_wave_data(RunData.current_zone, RunData.current_wave)

	var map_size_coef = (1 + (RunData.sum_all_player_effects(Keys.map_size_hash) / 100.0))
	current_zone.width = max(MIN_MAP_SIZE, (current_zone.width * map_size_coef)) as int
	current_zone.height = max(MIN_MAP_SIZE, (current_zone.height * map_size_coef)) as int

	ZoneService.set_current_zone(current_zone)
	_tile_map.init(current_zone)
	_tile_map_limits.init(current_zone)

	_current_wave_label.text = Text.text("WAVE", [str(RunData.current_wave)]).to_upper()

	_wave_timer.wait_time = 1 if RunData.instant_waves else current_wave_data.wave_duration

	if DebugService.custom_wave_duration != - 1:
		_wave_timer.wait_time = DebugService.custom_wave_duration

	_wave_timer.start()
	_wave_timer_label.wave_timer = _wave_timer
	var _error_wave_timer = _wave_timer.connect("tick_started", self, "on_tick_started")

	var _error_group_spawn = _wave_manager.connect("group_spawn_timing_reached", _entity_spawner, "on_group_spawn_timing_reached")
	_wave_manager.init(_wave_timer, current_zone, current_wave_data)

	var _error_connect = _coop_upgrades_ui.connect("upgrade_selected", self, "on_upgrade_selected")
	_error_connect = _coop_upgrades_ui.connect("item_take_button_pressed", self, "on_item_box_take_button_pressed")
	_error_connect = _coop_upgrades_ui.connect("item_discard_button_pressed", self, "on_item_box_discard_button_pressed")
	_error_connect = _coop_upgrades_ui.connect("item_ban_button_pressed", self, "on_item_box_ban_button_pressed")

	_error_connect = _upgrades_ui.connect("upgrade_selected", self, "on_upgrade_selected")
	_error_connect = _upgrades_ui.connect("item_take_button_pressed", self, "on_item_box_take_button_pressed")
	_error_connect = _upgrades_ui.connect("item_discard_button_pressed", self, "on_item_box_discard_button_pressed")
	_error_connect = _upgrades_ui.connect("item_ban_button_pressed", self, "on_item_box_ban_button_pressed")

	var _error_level_up = RunData.connect("levelled_up", self, "on_levelled_up")
	var _error_level_up_floating_text = RunData.connect("levelled_up", _floating_text_manager, "on_levelled_up")
	var _error_xp_added = RunData.connect("xp_added", self, "on_xp_added")
	var _error_gold_changed = RunData.connect("gold_changed", self, "on_gold_changed")
	var _error_bonus_gold_ui = RunData.connect("bonus_gold_changed", _ui_bonus_gold, "update_value")
	var _error_bonus_gold = RunData.connect("bonus_gold_changed", self, "on_bonus_gold_changed")
	on_bonus_gold_changed(RunData.bonus_gold)
	var _error_damage_effect = RunData.connect("damage_effect", self, "on_damage_effect")
	var _error_lifesteal_effect = RunData.connect("lifesteal_effect", self, "on_lifesteal_effect")
	var _error_healing_effect = RunData.connect("healing_effect", self, "on_healing_effect")
	var _error_heal_over_time_effect = RunData.connect("heal_over_time_effect", self, "on_heal_over_time_effect")

	var _error_gamepad = InputService.connect("game_lost_focus", self, "_on_game_lost_focus")

	
	var max_bounds = ZoneService.get_current_zone_rect().grow_individual(EDGE_SIZE, EDGE_SIZE * 2, EDGE_SIZE, EDGE_SIZE)
	_camera.init(max_bounds, float(EDGE_SIZE))
	on_lock_coop_camera_changed(ProgressData.settings.lock_coop_camera)
	ZoneService.current_zone_max_camera_rect = _camera.get_max_camera_bounds()

	_ui_dim_screen.color.a = 0

	var _error_options_1 = _pause_menu._menu_options.connect("character_highlighting_changed", self, "on_character_highlighting_changed")
	var _error_options_2 = _pause_menu._menu_options.connect("hp_bar_on_character_changed", self, "on_hp_bar_on_character_changed")
	var _error_options_3 = _pause_menu._menu_options.connect("weapon_highlighting_changed", self, "on_weapon_highlighting_changed")
	var _error_options_4 = _pause_menu._menu_options.connect("darken_screen_changed", self, "on_darken_screen_changed")
	var _error_options_5 = _pause_menu._menu_options.connect("lock_coop_camera_changed", self, "on_lock_coop_camera_changed")

	for player_index in CoopService.get_max_players():
		var player_idx_string = str(player_index + 1)
		var things_to_process_player_container = get_node("%%UIThingsToProcessPlayerContainer%s" % player_idx_string)
		
		things_to_process_player_container.hide()
		if not RunData.is_coop_run:
			
			things_to_process_player_container.horizontal_alignment = UIThingsToProcessPlayerContainer.Alignment.END
		_things_to_process_player_containers.push_back(things_to_process_player_container)

	_is_horde_wave = RunData.is_elite_wave(EliteType.HORDE)
	_is_elite_wave = RunData.is_elite_wave(EliteType.ELITE)
	var could_be_bullet_hell = RunData.get_player_effect(Keys.bullet_hell_event_hash, 0) and RunData.constant_projectile != 0
	var could_be_fog_wave = RunData.get_player_effect(Keys.fog_of_war_event_hash, 0)

	if not RunData.is_coop_run:
		
		
		_ui_things_to_process_margin_container.add_constant_override("margin_right", 0)

	for effect_behavior_data in EffectBehaviorService.scene_effect_behaviors:
		var effect_behavior: SceneEffectBehavior = effect_behavior_data.scene.instance()
		_effect_behaviors.add_child(effect_behavior.init(_entity_spawner, _wave_manager))

	
	_entity_spawner.init(
		ZoneService.current_zone_min_position, 
		ZoneService.current_zone_max_position, 
		current_wave_data, 
		_wave_timer
	)
	_stats_manager.init(_entity_spawner)

	EntityService.reset_cache()
	InputService.set_gamepad_echo_processing(false)
	_coop_upgrades_ui.propagate_call("set_process_input", [false])

	
	if RunData.current_wave == 1:
		for player_index in RunData.get_player_count():
			var player: Player = _players[player_index]
			player.land()

	for player_index in RunData.get_player_count():
		var effects = RunData.get_player_effects(player_index)
		if effects.has(Keys.gain_random_primary_stats_on_go_to_next_wave_hash):
			var gain_stats = effects[Keys.gain_random_primary_stats_on_go_to_next_wave_hash]
			for gain_stat in gain_stats:
				var chance = gain_stat[1]
				if Utils.get_chance_success(float(chance) / 100):
					for _i in range(gain_stat[0]):
						var stat = RunData.get_random_primary_stats()
						RunData.add_stat(stat, 1, player_index)
						RunData.add_tracked_value(player_index, Keys.item_candy_bag_hash, 1)

	var _wave = RunData.current_wave
	var events_fog_of_war = RunData.events_fog_of_war
	if (_wave in events_fog_of_war and could_be_fog_wave):
		_is_fog_wave = true
		_fog_viewport._change_fog_size(_wave)

	var events_bullet_hell = RunData.events_bullet_hell
	if (RunData.constant_projectile == 2 or (_wave in events_bullet_hell)) and could_be_bullet_hell and _is_fog_wave == false:
		if (_wave > 20):
			_wave = 20
		var rand_bullet_hell: BulletHell = ZoneService.bullets_hell.pick_random().instance()
		rand_bullet_hell._update_bullet_hell_parameters(_wave, _is_elite_wave, _is_horde_wave)
		_enemy_projectiles.add_child(rand_bullet_hell)

	_fog_viewport._initialize()

	_init_half_second_timers()


func _updatehidingHUD() -> void :
	if DebugService.hide_wave_timer:
		_ui_wave_container.hide()
	else:
		_ui_wave_container.show()
	if DebugService.hide_hud:
		_hud.hide()
		$WorldUI.hide()
	else:
		_hud.show()
		$WorldUI.show()
	if DebugService.hide_floating_text:
		_floating_texts.hide()
		$WorldUI.hide()
	else:
		_floating_texts.show()
		$WorldUI.show()


func _init_half_second_timers() -> void :
	var timer_wait_time: = 0.5
	var player_count: int = RunData.get_player_count()
	var timer_delay: = timer_wait_time / player_count
	for player_index in player_count:
		if LinkedStats.update_for_player_every_half_sec[player_index]:
			var timer: = Timer.new()
			timer.wait_time = timer_wait_time
			timer.autostart = true
			_half_second_timers.add_child(timer)
			timer.connect("timeout", self, "_on_HalfSecondTimer_timeout", [player_index])
			if not get_tree().current_scene.name == "GutRunner":
				
				yield(get_tree().create_timer(timer_delay), "timeout")


func on_ui_element_mouse_entered(ui_element: Node, text: String) -> void :
	if _cleaning_up:
		_info_popup.display(ui_element, tr(text))


func on_ui_element_mouse_exited(_ui_element: Node) -> void :
	_info_popup.hide()


func on_character_highlighting_changed(_value: bool) -> void :
	for player in _players:
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		player.update_highlight()


func on_weapon_highlighting_changed(_value: bool) -> void :
	for player in _players:
		if not is_instance_valid(player) or not player.is_inside_tree():
			continue
		player.update_weapon_highlighting()


func on_darken_screen_changed(_value: int) -> void :
	_damage_vignette.update_from_hp()


func on_lock_coop_camera_changed(value: int) -> void :
	_camera.dynamic_camera_enabled = not value


func on_hp_bar_on_character_changed(_value: int) -> void :
	for i in _players.size():
		if not is_instance_valid(_players[i]) or not _players[i].is_inside_tree(): return
		_on_player_health_updated(_players[i], _players[i].current_stats.health, _players[i].max_stats.health)


func on_stats_updated(player_index: int) -> void :
	_stats_manager.reload_stats(_players[player_index])
	_proj_on_death_stat_caches[player_index] = null


func _process(_delta: float) -> void :
	if DebugService.enable_time_scale_buttons:
		if Input.is_physical_key_pressed(KEY_1):
			Engine.time_scale = 0.5
		if Input.is_physical_key_pressed(KEY_2):
			Engine.time_scale = 1.0
		if Input.is_physical_key_pressed(KEY_3):
			Engine.time_scale = 2.0

	_handle_manual_aim_visuals()

	_check_for_pause()


func _handle_manual_aim_visuals() -> void :
	if RunData.is_coop_run:
		return

	_crosshair.hide()
	var crosshair_cursor: = false

	if not _cleaning_up:
		if Utils.is_manual_aim(0):
			if Utils.is_player_using_gamepad(0):
				_crosshair.show()
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
				var player_pos = _players[0].global_position
				player_pos.y -= 32
				_crosshair.global_position = player_pos + CROSSHAIR_DIST_FROM_PLAYER_MANUAL_AIM * _players[0].gamepad_attack_vector
			else:
				crosshair_cursor = true
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif ProgressData.settings.manual_aim_on_mouse_press and ProgressData.settings.manual_aim:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

		if ProgressData.settings.mouse_only:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_set_crosshair_cursor(crosshair_cursor)


func _set_crosshair_cursor(enable: bool) -> void :
	if enable and not _crosshair_cursor_active:
		Input.set_custom_mouse_cursor(_crosshair.texture, Input.CURSOR_ARROW, Vector2(35, 35))
		_crosshair_cursor_active = true
	elif not enable and _crosshair_cursor_active:
		Utils.set_default_cursor()
		_crosshair_cursor_active = false


func _check_for_pause() -> void :
	if _skip_pause_check:
		_skip_pause_check = false
		return

	if RunData.is_coop_run:
		if RunData.is_streamplay_run:
			var remapped_device = CoopService.get_remapped_player_device(0)
			if Input.is_action_just_released("ui_pause_%s" % remapped_device):
				_pause_menu.pause(0)
		else:
			for player_index in RunData.get_player_count():
				var remapped_device = CoopService.get_remapped_player_device(player_index)
				if Input.is_action_just_released("ui_pause_%s" % remapped_device):
					_pause_menu.pause(player_index)
					break
	else:
		if Input.is_action_just_released("ui_pause"):
			_pause_menu.pause(0)


func _physics_process(_delta: float) -> void :
	if _cleaning_up:
		_gold_bag.global_position = get_gold_bag_pos()

	for player_index in RunData.get_player_count():
		var life_bar_effects = _players[player_index].life_bar_effects()
		var player_ui: PlayerUIElements = _players_ui[player_index]
		player_ui.life_bar.update_color_from_effects(life_bar_effects)
		player_ui.player_life_bar.update_color_from_effects(life_bar_effects)

	if not _cleaning_up:
		for player_index in RunData.get_player_count():
			if not Utils.is_manual_aim(player_index) or not Utils.is_player_using_gamepad(player_index):
				continue
			var rjoy = Utils.get_player_rjoy_vector(player_index)
			if rjoy != Vector2.ZERO:
				_players[player_index].gamepad_attack_vector = rjoy.normalized()


func on_tick_started() -> void :
	_wave_timer_label.modulate = Color(ProgressData.settings.color_negative)


func on_bonus_gold_changed(value: int) -> void :
	if value == 0:
		_ui_bonus_gold.hide()


func _on_player_died(p_player: Player, _args: Entity.DieArgs) -> void :
	if (_args.from is BulletHell):
		_args.is_bullet_hell = true
	else:
		_args.is_bullet_hell = false
	RunData._players_die_args[p_player.player_index] = _args
	var player_ui: PlayerUIElements = _players_ui[p_player.player_index]
	player_ui.player_life_bar.hide()
	if RunData.is_coop_run:
		player_ui.life_bar.set_value(100)
		player_ui.life_bar.progress_color = Color.white
		player_ui.life_bar.hide_with_flash()

	p_player.highlight.hide()

	SoundManager.play(Utils.get_rand_element(run_lost_sounds), - 5, 0, true)

	var live_players: = _get_live_players()
	if not live_players.empty():
		return

	clean_up_room()

	ProgressData.reset_and_save_new_run_state()

	ChallengeService.complete_challenge(ChallengeService.chal_rookie_hash)

	if _args.from != null and _args.from is Enemy:
		if ProgressData.killed_by_enemies.has(_args.from.enemy_id_hash):
			ProgressData.killed_by_enemies[_args.from.enemy_id_hash] += 1
		else:
			ProgressData.killed_by_enemies[_args.from.enemy_id_hash] = 1

		if _args.from.enemy_id == "evil_mob":
			ProgressData.increment_stat("evil_mob_killed_by")


func _on_enemy_died(enemy: Enemy, args: Entity.DieArgs) -> void :
	RunData.current_living_enemies -= 1

	if not _cleaning_up and args.enemy_killed_by_player:
		if enemy is Boss:

			
			if _entity_spawner.get_nb_bosses_and_elites_alive() <= 1 and RunData.current_wave == RunData.nb_of_waves:

				if RunData.is_endless_run:
					var additional_groups = ZoneService.get_additional_groups(int((RunData.current_wave / 10.0) * 3), 90)
					for i in additional_groups.size():
						additional_groups[i].spawn_timing = _wave_timer.wait_time - _wave_timer.time_left + i
					_wave_manager.add_groups(additional_groups)
					RunData.all_last_wave_bosses_killed = true

				else:
					_wave_timer.wait_time = 0.1
					_wave_timer.start()

		var live_players: = _get_shuffled_live_players()

		for player in live_players:
			var player_index = player.player_index
			var dmg_when_death = RunData.get_player_effect(Keys.dmg_when_death_hash, player_index)
			if dmg_when_death.size() > 0:
				var _dmg_taken = handle_stat_damages(dmg_when_death, player_index)

		for player in live_players:
			var player_index = player.player_index
			var projectiles_on_death = RunData.get_player_effect(Keys.projectiles_on_death_hash, player_index)
			if projectiles_on_death.empty():
				continue

			for i in projectiles_on_death[0]:
				var stats = projectiles_on_death[1]
				if _proj_on_death_stat_caches[player_index] != null:
					stats = _proj_on_death_stat_caches[player_index]
				else:
					stats = WeaponService.init_ranged_stats(projectiles_on_death[1], player_index, true)
					_proj_on_death_stat_caches[player_index] = stats

				var auto_target_enemy: bool = projectiles_on_death[2]
				var from = player
				_spawn_projectile_args.damage_tracking_key_hash = Keys.item_baby_with_a_beard_hash
				_spawn_projectile_args.from_player_index = player_index
				var _projectile = WeaponService.manage_special_spawn_projectile(
					enemy, 
					stats, 
					rand_range( - PI, PI), 
					auto_target_enemy, 
					_entity_spawner, 
					from, 
					_spawn_projectile_args
				)

		for player in live_players:
			var player_index = player.player_index
			RunData.handle_explode_effect(Keys.explode_on_death_hash, enemy.global_position, player_index)

		for player in live_players:
			if args.is_burning:
				var effects = RunData.get_player_effect(Keys.gain_stat_for_killed_enemies_while_burning_hash, player.player_index)
				for effect in effects:
					if effect[5] < effect[3]:
						effect[4] += 1
						if effect[4] %int(effect[1]) == 0:
							effect[5] += 1
							RunData.add_stat(effect[0], effect[2], player.player_index)
							RunData.add_tracked_value(player.player_index, Keys.item_will_o_the_wisp_hash, 1, 0)

		spawn_loot(enemy, EntityType.ENEMY, args)

		ProgressData.increment_stat("enemies_killed")

		if ProgressData.killed_enemies.has(enemy.enemy_id_hash):
			ProgressData.killed_enemies[enemy.enemy_id_hash] += 1
		else:
			ProgressData.killed_enemies[enemy.enemy_id_hash] = 1

		if enemy.enemy_id == "evil_mob":
			ProgressData.increment_stat("evil_mob_killed")


func _on_enemy_took_damage(
	enemy: Enemy, 
	_value: int, 
	_knockback_direction: Vector2, 
	_is_crit: bool, 
	_is_dodge: bool, 
	_is_protected: bool, 
	_armor_did_something: bool, 
	args: TakeDamageArgs, 
	_hit_type: int, 
	_is_one_shot: bool
	) -> void :
	if enemy.dead and WeaponService.should_spawn_landmines_on_enemy_death(args.hitbox, args.is_burning, args.from_player_index):
		var pos = _entity_spawner.get_spawn_pos_in_area(enemy.global_position, 200)
		var queue = _entity_spawner.queues_to_spawn_structures[args.from_player_index]
		queue.push_back([EntityType.STRUCTURE, landmines_effect.scene, pos, landmines_effect])


func _on_neutral_died(neutral: Neutral, args: Entity.DieArgs) -> void :
	RunData.current_living_trees -= 1

	if not _cleaning_up:
		call_deferred("spawn_loot", neutral, EntityType.NEUTRAL, args)

		for player in _get_shuffled_live_players():
			var player_index = player.player_index
			for _i in RunData.get_player_effect(Keys.tree_turrets_hash, player_index):
				var pos = _entity_spawner.get_spawn_pos_in_area(neutral.global_position, 200)
				var queue = _entity_spawner.queues_to_spawn_structures[player_index]
				queue.push_back([EntityType.STRUCTURE, turret_effect.scene, pos, turret_effect])


func on_player_wanted_to_spawn_gold(value: int, pos: Vector2, spread: int) -> void :
	var actual_value = get_gold_value(EntityType.NEUTRAL, Utils.default_die_args, value)
	spawn_gold(actual_value, pos, spread)


func spawn_loot(unit: Unit, entity_type: int, args: Entity.DieArgs) -> void :
	if not unit.can_drop_loot:
		return

	if unit.stats.can_drop_consumables:
		spawn_consumables(unit)

	var wave_factor = RunData.current_wave * 0.015


	var spawn_chance = 1.0 if RunData.current_wave < 5 else max(0.5, (1.0 - wave_factor))

	if _is_horde_wave:
		spawn_chance *= 0.65

	if unit.stats.always_drop_consumables:
		spawn_chance = 1.0

	if entity_type == EntityType.ENEMY and not Utils.get_chance_success(spawn_chance):
		return

	var value: float = get_gold_value(entity_type, args, unit.get_stats_value(), unit)
	var gold_spread = clamp((value - 1) * 25, unit.stats.gold_spread, 200)

	spawn_gold(value, unit.global_position, gold_spread)


func spawn_consumables(unit: Unit) -> void :
	var luck: = 0.0

	for player_index in RunData.get_player_count():
		luck += Utils.get_stat(Keys.stat_luck_hash, player_index) / 100.0

	var item_chance: float = (unit.stats.item_drop_chance * (1.0 + luck)) / (1.0 + _items_spawned_this_wave)

	var total_chance_change: float = RunData.sum_all_player_effects(Keys.crate_chance_hash) / 100.0
	item_chance = item_chance + item_chance * total_chance_change

	if unit.stats.always_drop_consumables and unit.stats.item_drop_chance >= 1.0 and RunData.current_wave <= RunData.nb_of_waves:
		item_chance = 1.0

	var consumable_to_spawn: ConsumableData = ItemService.get_consumable_to_drop(unit, item_chance)
	if consumable_to_spawn != null:
		var pos: = unit.global_position
		var dist: = rand_range(50, 100 + unit.stats.gold_spread)

		if consumable_to_spawn.my_id_hash == Keys.consumable_item_box_hash or consumable_to_spawn.my_id_hash == Keys.consumable_legendary_item_box_hash:
			
				
				
				
				
				
			_items_spawned_this_wave += 1

		var consumable: Consumable = get_node_from_pool(_consumable_pool_id, _consumables_container)
		if consumable == null:
			consumable = consumable_scene.instance()
			_consumables_container.call_deferred("add_child", consumable)
			var _error = consumable.connect("picked_up", self, "on_consumable_picked_up")
			yield(consumable, "ready")

		consumable.already_picked_up = false
		consumable.consumable_data = consumable_to_spawn
		consumable.set_texture(consumable_to_spawn.icon)
		var push_back_destination: Vector2 = ZoneService.get_rand_pos_in_area(pos, dist, 0)
		consumable.drop(pos, 0, push_back_destination)
		_consumables.push_back(consumable)


func on_consumable_picked_up(consumable: Node, player_index: int) -> void :
	if consumable.already_picked_up:
		return

	consumable.already_picked_up = true
	_consumables.erase(consumable)
	add_node_to_pool(consumable, _consumable_pool_id)

	var item_box_gold_effect = RunData.get_player_effect(Keys.item_box_gold_hash, player_index)
	if consumable.consumable_data.my_id_hash == Keys.consumable_item_box_hash or consumable.consumable_data.my_id_hash == Keys.consumable_legendary_item_box_hash and item_box_gold_effect != 0:
		RunData.add_gold(item_box_gold_effect, player_index)
		RunData.add_tracked_value(player_index, Keys.item_bag_hash, item_box_gold_effect)

	var consumable_data = consumable.consumable_data
	if consumable_data.to_be_processed_at_end_of_wave:
		var consumable_to_process = UpgradesUI.ConsumableToProcess.new()
		consumable_to_process.consumable_data = consumable_data

		var player_index_to_add_to = player_index

		if ProgressData.settings.share_coop_loot:

			player_index_to_add_to = randi() % RunData.get_player_count()

			for i in RunData.get_player_count():
				if _consumables_to_process[i].size() < _consumables_to_process[player_index_to_add_to].size():
					player_index_to_add_to = i

		consumable_to_process.player_index = player_index_to_add_to
		_consumables_to_process[player_index_to_add_to].push_back(consumable_to_process)
		_things_to_process_player_containers[player_index_to_add_to].consumables.add_element(consumable_data)

	_players[player_index].on_consumable_picked_up(consumable_data)

	if not _cleaning_up:
		RunData.handle_explode_effect(Keys.explode_on_consumable_hash, consumable.global_position, player_index)
		RunData.handle_explode_effect(Keys.explode_on_consumable_burning_hash, consumable.global_position, player_index)

	RunData.apply_item_effects(consumable.consumable_data, player_index)


func spawn_gold(value: float, pos: Vector2, spread: int) -> void :
	var value_floored: = int(value)
	var residual_chance: = value - value_floored
	var spawn_count: = (value_floored + 1) if Utils.get_chance_success(residual_chance) else value_floored
	for _i in range(spawn_count):

		if _active_golds.size() >= MAX_GOLDS:
			var gold_boosted = Utils.get_rand_element(_active_golds)
			gold_boosted.value += Gold.INITIAL_VALUE
			gold_boosted.scale = Vector2(
				min(gold_boosted.scale.x + Gold.INITIAL_VALUE * 0.05, Gold.MAX_SIZE), 
				min(gold_boosted.scale.y + Gold.INITIAL_VALUE * 0.05, Gold.MAX_SIZE)
			)
			continue

		var gold = get_node_from_pool(_gold_pool_id, _materials_container)
		if gold == null:
			gold = gold_scene.instance()
			_materials_container.call_deferred("add_child", gold)
			var _error = gold.connect("picked_up", self, "on_gold_picked_up")
			_error = gold.connect("picked_up", _effects_manager, "on_gold_picked_up")
			_error = gold.connect("picked_up", _floating_text_manager, "on_gold_picked_up")
			yield(gold, "ready")

		if RunData.bonus_gold > 0:
			var gold_value = gold.value
			gold.value += min(gold.value, RunData.bonus_gold)
			gold.boosted = 2
			gold.scale.x = 1.25
			gold.scale.y = 1.25
			RunData.remove_bonus_gold(gold_value)

		gold.set_texture(gold_sprites.pick_random())
		gold.already_picked_up = false
		var dist = rand_range(50, 100 + spread)
		var push_back_destination = ZoneService.get_rand_pos_in_area(pos, dist, 0)
		gold.drop(pos, rand_range(0, 2 * PI), push_back_destination)
		_active_golds.push_back(gold)

		for player in _get_shuffled_live_players():
			var instant_gold_attracting = RunData.get_player_effect(Keys.instant_gold_attracting_hash, player.player_index)
			if instant_gold_attracting != 0 and randf() < instant_gold_attracting / 100.0:
				if RunData.get_player_effect_bool(Keys.stat_has_lootworm_hash, player.player_index) and _entity_spawner.lootworms[player.player_index] != null:
					gold.attracted_by = _entity_spawner.lootworms[player.player_index]
				else:
					gold.attracted_by = player
				gold.set_physics_process(true)
				break
	emit_signal("gold_spawned")


func get_gold_value(entity_type: int, args: Entity.DieArgs, base_value: float, unit: Unit = null) -> float:
	var value = base_value
	var coop_factor: float = CoopService.get_coop_materials_factor()
	value += value * coop_factor

	var nb_players = RunData.get_player_count()
	var gold_drops: int = RunData.sum_all_player_effects(Keys.gold_drops_hash) / nb_players
	var enemy_gold_drops: int = RunData.sum_all_player_effects(Keys.enemy_gold_drops_hash) / nb_players
	var neutral_gold_drops: int = RunData.sum_all_player_effects(Keys.neutral_gold_drops_hash) / nb_players

	if entity_type == EntityType.ENEMY:
		var total_effect: = gold_drops + enemy_gold_drops
		value += value * total_effect / 100.0

	elif entity_type == EntityType.NEUTRAL:
		var total_effect: = gold_drops + neutral_gold_drops
		value += value * total_effect / 100.0

	else:
		value += value * gold_drops / 100.0

	value = max(value, MIN_GOLD_CHANCE * base_value)

	if not unit:
		return value

	var value_modifier_from_effect_behaviors = 0.0
	for effect_behavior in unit.effect_behaviors.get_children():
		value_modifier_from_effect_behaviors += effect_behavior.get_gold_value_modifier()
	value *= 1.0 + value_modifier_from_effect_behaviors

	if args.killed_by_player_index >= 0 and args.killed_by_player_index < _players.size() and is_instance_valid(_players[args.killed_by_player_index]):
		var scale_gold_effect: Array = RunData.get_player_effect(Keys.scale_materials_with_distance_hash, args.killed_by_player_index)
		if entity_type != EntityType.NEUTRAL and args.enemy_killed_by_player and scale_gold_effect.size() > 0:
			var dist_to_player: = unit.global_position.distance_to(_players[args.killed_by_player_index].global_position)
			var scaling_percentage: int = scale_gold_effect[0].get_scaling_value(dist_to_player)
			value *= 1.0 + scaling_percentage / 100.0

	return value


func on_gold_picked_up(gold: Node, player_index: int) -> void :
	if gold.already_picked_up:
		return

	gold.already_picked_up = true
	_active_golds.erase(gold)
	add_node_to_pool(gold, _gold_pool_id)

	if player_index >= 0:
		if ProgressData.settings.alt_gold_sounds:
			SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), - 5, 0.2)
		else:
			SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)

		var increase_effect: int = RunData.get_player_effect(Keys.increase_material_value_hash, player_index)
		var value = gold.value
		value += value * (increase_effect / 100.0)

		var boost = RunData.apply_common_gold_pickup_effects(gold.value, player_index)
		value *= boost
		gold.boosted *= boost

		if Utils.get_chance_success(RunData.get_player_effect(Keys.heal_when_pickup_gold_hash, player_index) / 100.0):
			RunData.emit_signal("healing_effect", 1, player_index, Keys.item_cute_monkey_hash)

		var dmg_when_pickup_gold_effect = RunData.get_player_effect(Keys.dmg_when_pickup_gold_hash, player_index)
		if dmg_when_pickup_gold_effect.size() > 0:
			handle_stat_damages(dmg_when_pickup_gold_effect, player_index)

		var highest_cd_weapon_that_should_reload = null

		for weapon in _players[player_index].current_weapons:
			for effect in weapon.effects:
				if effect.key_hash == Keys.reload_when_pickup_gold_hash:
					if not weapon._is_shooting and (highest_cd_weapon_that_should_reload == null or weapon._current_cooldown > highest_cd_weapon_that_should_reload._current_cooldown):
						highest_cd_weapon_that_should_reload = weapon

		if highest_cd_weapon_that_should_reload:
			highest_cd_weapon_that_should_reload._current_cooldown = 0

		for structure in _entity_spawner.structures:
			if structure is BuilderTurret:
				for effect in structure.effects:
					if effect.key_hash == Keys.reload_when_pickup_gold_hash:
						structure._cooldown = 0

		if RunData.get_player_effect_bool(Keys.reload_when_pickup_gold_hash, player_index):
			for weapon in _players[player_index].current_weapons:
				weapon._current_cooldown = 0


		
		var player_gold: = [0, 0, 0, 0]
		var player_xp: = [0, 0, 0, 0]
		while value > 0:
			player_gold[_next_gold_player] += 1
			player_xp[_next_gold_player] += 1
			value -= 1
			_next_gold_player = (_next_gold_player + 1) % RunData.get_player_count()

		for i in RunData.get_player_count():
			RunData.add_gold(player_gold[i], i)
			RunData.add_xp(player_xp[i], i)

		ProgressData.increment_stat("materials_collected")
		return

	if _cleaning_up:
		RunData.add_bonus_gold(gold.value)



func on_levelled_up(player_index: int) -> void :
	SoundManager.play(level_up_sound, 0, 0, true)
	var level = RunData.get_player_level(player_index)
	_things_to_process_player_containers[player_index].upgrades.add_element(ItemService.get_icon(Keys.icon_upgrade_to_process_hash), level)

	var upgrade_to_process = UpgradesUI.UpgradeToProcess.new()
	upgrade_to_process.level = level
	upgrade_to_process.player_index = player_index
	_upgrades_to_process[player_index].push_back(upgrade_to_process)

	_players_ui[player_index].update_level_label()

	RunData.add_stat(Keys.stat_max_hp_hash, 1, player_index)
	for stat_level_up in RunData.get_player_effect(Keys.stats_on_level_up_hash, player_index):
		assert (stat_level_up[0] is int)
		RunData.add_stat(stat_level_up[0], stat_level_up[1], player_index)

		if stat_level_up[0] == Keys.stat_lifesteal_hash:
			RunData.add_tracked_value(player_index, Keys.item_decomposing_flesh_hash, stat_level_up[1])
		elif stat_level_up[0] == Keys.stat_hp_regeneration_hash:
			RunData.add_tracked_value(player_index, Keys.item_baby_squid_hash, stat_level_up[1])
		elif stat_level_up[0] == Keys.stat_curse_hash:
			var val = stat_level_up[1]

			
			

			if RunData.get_player_character(player_index).has_character_hash(Keys.character_creature_hash):
				val -= 1

			if val > 0:
				RunData.add_tracked_value(player_index, Keys.item_barnacle_hash, 1)


func on_xp_added(current_xp: float, max_xp: float, player_index: int) -> void :
	var player_ui: PlayerUIElements = _players_ui[player_index]
	var display_xp = int(current_xp) % int(ceil(max_xp))
	player_ui.xp_bar.update_value(display_xp, int(max_xp))


func connect_visual_effects(unit: Unit) -> void :
	var _error_effects = unit.connect("took_damage", _effects_manager, "_on_unit_took_damage")
	var _error_floating_text = unit.connect("took_damage", _floating_text_manager, "_on_unit_took_damage")
	var _error_crit_effect = unit.connect("crit_effect", _effects_manager, "_on_weapon_did_crit")
	var _error_one_shot_effect = unit.connect("one_shot_effect", _effects_manager, "on_one_shot")


func clean_up_room() -> void :
	_set_run_states()

	_ui_dim_screen.dim()
	_wave_timer.stop()
	for timer in _half_second_timers.get_children():
		if timer is Timer:
			timer.stop()


	_enemy_projectiles.queue_free()

	if _is_run_lost:
		_end_wave_timer.wait_time = 0.5
		DebugService.log_data("is_run_lost")

	elif _is_run_won:
		_end_wave_timer.wait_time = 4
		RunData.apply_run_won()

	if _is_wave_failed:
		MusicManager.tween( - 20)
		if RunData.current_wave > 1:
			_end_wave_timer.wait_time = 0.5

	_end_wave_timer.start()

	if RunData.current_wave % 10 == 0 and RunData.current_wave >= 10:
		RunData.init_elites_spawn(RunData.current_wave + 10, 0.0)
		RunData.init_events_nightmare(RunData.current_wave + 10)

	if RunData.is_endless_run:

		DebugService.log_data("is_endless_run")

		if RunData.current_wave >= 20:
			for player_index in RunData.get_player_count():
				var character_difficulty = ProgressData.get_character_difficulty_info(RunData.players_data[player_index].current_character.my_id_hash, RunData.current_zone)

				character_difficulty.max_endless_wave_beaten.set_info(
					RunData.current_difficulty, 
					RunData.current_wave, 
					RunData.current_run_accessibility_settings.health, 
					RunData.current_run_accessibility_settings.damage, 
					RunData.current_run_accessibility_settings.speed, 
					RunData.retries, 
					0 if not RunData.is_ban_active_in_current_run() else RunData.get_used_ban_count(), 
					RunData.constant_projectile, 
					RunData.is_coop_run, 
					true
				)

	ProgressData.save()

	SoundManager.play(Utils.get_rand_element(end_wave_sounds))
	_cleaning_up = true
	_effects_manager.clean_up_room()
	_floating_text_manager.clean_up_room()

	DebugService.log_data("attract bonus_gold and consumables...")
	if _active_golds.size() > 0:
		var attracted_by = null

		_ui_bonus_gold.show()
		attracted_by = _gold_bag

		for player in _players:
			player.disable_gold_pickup()

		var nb_builders = 0
		var indexes_builder = []

		for player_id in RunData.players_data.size():
			if RunData.get_player_character(player_id).has_character_hash(Keys.character_builder_hash):
				nb_builders += 1
				indexes_builder.push_back(player_id)

		if nb_builders > 0:
			for structure in _entity_spawner.structures:
				if structure is BuilderTurret:
					override_gold_bag_pos = structure.global_position
					var _e = RunData.connect("bonus_gold_converted", structure, "on_bonus_gold_converted")
					_e = structure.connect("stat_added", _floating_text_manager, "on_turret_stat_added")
					structure.main_ref = self

		if ProgressData.settings.optimize_end_waves:
			var bonus_gold_value = 0
			var player_count = RunData.get_player_count()
			for i in _active_golds.size():
				var gold = _active_golds[i]
				var player_index = i % player_count
				var boost = RunData.apply_common_gold_pickup_effects(gold.value, player_index)
				bonus_gold_value += gold.value * boost
				gold.boosted *= boost
				gold.visible = false

			RunData.add_bonus_gold(bonus_gold_value)
		else:
			for gold in _active_golds:
				gold.collision_layer = Utils.BONUS_GOLD_BIT
				gold.attracted_by = attracted_by
				gold.set_physics_process(true)

	var live_players: = _get_shuffled_live_players()
	if not live_players.empty():
		for i in _consumables.size():
			var player = live_players[i % live_players.size()]
			var consumable: Consumable = _consumables[i]
			if not consumable.has_damage_effect():
				consumable.attracted_by = player
				consumable.set_physics_process(true)

	DebugService.log_data("clean_up other objects...")
	_entity_spawner.clean_up_room()
	_wave_manager.clean_up_room()

	for player in _players:
		if is_instance_valid(player):
			player.on_room_cleanup()

	
	if _is_run_won:
		for player_index in RunData.get_player_count():
			var player: Player = _players[player_index]
			player.won()
		yield(_players[0], "run_won_screen")
		SoundManager.play(Utils.get_rand_element(run_won_sounds), - 5, 0, true)

	DebugService.log_data("start wave_cleared_label...")
	_wave_cleared_label.start(_is_wave_failed, _is_run_lost, _is_run_won)
	DebugService.log_data("wave_cleared_label started...")


func _set_run_states() -> void :
	var live_players: = _get_live_players()
	var all_players_dead: = live_players.empty()

	_is_wave_failed = all_players_dead
	if RunData.current_wave < RunData.nb_of_waves:
		if all_players_dead:
			_is_run_lost = true

	if RunData.current_wave == RunData.nb_of_waves:
		if RunData.is_endless_run:
			if all_players_dead and RunData.all_last_wave_bosses_killed:
				_is_run_won = true
			elif all_players_dead:
				_is_run_lost = true
		else:
			if all_players_dead:
				_is_run_lost = true
			else:
				_is_run_won = true

	if RunData.current_wave > RunData.nb_of_waves:
		if all_players_dead:
			_is_run_won = true

	RunData.run_won = _is_run_won
	if _is_run_won:
		ProgressData.increment_stat("run_won")


func get_gold_bag_pos() -> Vector2:

	if override_gold_bag_pos != Vector2.ZERO:
		return override_gold_bag_pos

	return get_viewport().get_canvas_transform().affine_inverse().xform(_ui_bonus_gold_pos.global_position)


func _on_EndWaveTimer_timeout() -> void :
	_coop_upgrades_ui.propagate_call("set_process_input", [true])
	DebugService.log_data("_on_EndWaveTimer_timeout")
	SoundManager.clear_queue()
	SoundManager2D.clear_queue()
	InputService.set_gamepad_echo_processing(true)

	_end_wave_timer_timedout = true

	if _is_wave_failed and RunData.current_wave > 0:
		_retry_wave.show()
		_pause_menu.enabled = false
		return

	_wave_cleared_label.hide()
	_wave_timer_label.hide()

	_camera.move_speed_factor = 0.0
	_camera.zoom_in_speed_factor = 0.0
	_camera.zoom_out_speed_factor = 0.0

	RunData.on_wave_end()
	LinkedStats.reset()

	var scene: String
	var _args: Entity.DieArgs = Utils.default_die_args
	if _is_run_lost or _is_run_won:
		DebugService.log_data("end run...")
		scene = RunData.get_end_run_scene_path()
	else:
		DebugService.log_data("process consumables and upgrades...")
		MusicManager.tween( - 8)

		if RunData.is_coop_run:
			
			_hud.hide()
			if _coop_upgrades_ui.show_options(_consumables_to_process, _upgrades_to_process):
				yield(_coop_upgrades_ui, "options_processed")
			_coop_upgrades_ui.hide()
		else:
			if _upgrades_ui.show_options(_consumables_to_process, _upgrades_to_process):
				var things_to_process_player_container = _things_to_process_player_containers[0]
				var ui_consumables_to_process = things_to_process_player_container.consumables
				var ui_upgrades_to_process = things_to_process_player_container.upgrades
				while not ui_consumables_to_process.is_empty():
					var consumable = yield(_upgrades_ui, "consumable_selected")
					ui_consumables_to_process.remove_element(consumable.consumable_data)
				while not ui_upgrades_to_process.is_empty():
					var args = yield(_upgrades_ui, "upgrade_selected")
					var upgrade = args[1]
					ui_upgrades_to_process.remove_element(upgrade.level)
				yield(_upgrades_ui, "options_processed")
			_upgrades_ui.hide()

		DebugService.log_data("display challenge ui...")
		if _is_chal_ui_displayed:
			yield(_challenge_completed_ui, "finished")

		scene = RunData.get_shop_scene_path()

	_change_scene(scene)


func on_upgrade_selected(upgrade_data: UpgradeData, upgrade: UpgradesUI.UpgradeToProcess) -> void :
	RunData.apply_item_effects(upgrade_data, upgrade.player_index)


func on_item_box_take_button_pressed(item_data: ItemParentData, consumable: UpgradesUI.ConsumableToProcess) -> void :
	RunData.add_item(item_data, consumable.player_index)


func on_item_box_discard_button_pressed(item_data: ItemParentData, consumable: UpgradesUI.ConsumableToProcess) -> void :
	var player_index = consumable.player_index
	var value = ItemService.get_recycling_value(RunData.current_wave, item_data.value, player_index)
	RunData.add_gold(value, player_index)
	RunData.update_recycling_tracking_value(item_data, player_index)


func on_item_box_ban_button_pressed(item_data: ItemParentData, consumable: UpgradesUI.ConsumableToProcess) -> void :
	var player_index = consumable.player_index
	var value = floor(ItemService.get_recycling_value(RunData.current_wave, item_data.value, player_index))
	var player_run_data = RunData.players_data[player_index]
	player_run_data.banned_items.push_back(item_data.my_id_hash)
	player_run_data.remaining_ban_token -= 1
	RunData.add_gold(value, player_index)
	RunData.update_recycling_tracking_value(item_data, player_index)


func _on_PauseMenu_paused() -> void :
	InputService.set_gamepad_echo_processing(true)


func _on_PauseMenu_unpaused() -> void :
	_skip_pause_check = true

	if not _end_wave_timer_timedout:
		InputService.set_gamepad_echo_processing(false)

	elif _upgrades_ui.visible:
		
		
		_upgrades_ui.focus()


func _on_WaveTimer_timeout() -> void :
	DebugService.log_run_info(_upgrades_to_process, _consumables_to_process)
	ChallengeService.check_counted_challenges()
	check_lootworm_chal()

	for player_index in RunData.get_player_count():
		if _players[player_index] != null and is_instance_valid(_players[player_index]) and _players[player_index].current_stats.health == ChallengeService.get_chal(ChallengeService.chal_reckless_hash).value:
			ChallengeService.complete_challenge(ChallengeService.chal_reckless_hash)
			break

	if _entity_spawner.neutrals.size() >= ChallengeService.get_chal(ChallengeService.chal_forest_hash).value:
		ChallengeService.complete_challenge(ChallengeService.chal_forest_hash)

	for player_index in RunData.get_player_count():
		var stats_end_of_wave = RunData.get_player_effect(Keys.stats_end_of_wave_hash, player_index)
		var hsh: int = Keys.empty_hash
		for stat_end_of_wave in stats_end_of_wave:
			assert (stat_end_of_wave[0] is int)
			hsh = stat_end_of_wave[0]
			RunData.add_stat(hsh, stat_end_of_wave[1], player_index)

			if hsh == Keys.stat_percent_damage_hash:
				RunData.add_tracked_value(player_index, Keys.item_vigilante_ring_hash, stat_end_of_wave[1])
			elif hsh == Keys.stat_max_hp_hash:
				var leaf_value = 0
				var items = RunData.get_player_items_ref(player_index)
				for item in items:
					if item.my_id_hash == Keys.item_grinds_magical_leaf_hash:
						for effect in item.effects:
							if effect.key_hash != Keys.stat_curse_hash:
								leaf_value += effect.value
				RunData.add_tracked_value(player_index, Keys.item_grinds_magical_leaf_hash, leaf_value)
			elif hsh == Keys.stat_melee_damage_hash:
				var robot_arm_value = 0
				var items = RunData.get_player_items_ref(player_index)
				for item in items:
					if item.my_id_hash == Keys.item_robot_arm_hash:
						for effect in item.effects:
							if effect.key_hash != Keys.stat_curse_hash and effect.value > 0:
								robot_arm_value += effect.value
				RunData.add_tracked_value(player_index, Keys.item_robot_arm_hash, robot_arm_value)
			elif hsh == Keys.xp_gain_hash and stat_end_of_wave[1] > 0:
				RunData.add_tracked_value(player_index, Keys.item_celery_tea_hash, stat_end_of_wave[1])
			elif hsh == Keys.stat_armor_hash and stat_end_of_wave[1] < 0:
				RunData.add_tracked_value(player_index, Keys.item_ashes_hash, abs(stat_end_of_wave[1]) as int)

	for player_index in RunData.get_player_count():
		Utils.convert_stats(RunData.get_player_effect(Keys.convert_stats_end_of_wave_hash, player_index), player_index)

	emit_signal("end_of_the_wave")

	manage_harvesting()

	DebugService.log_data("start clean_up_room...")
	clean_up_room()

	TempStats.reset()

func check_lootworm_chal():
	if not ChallengeService.is_challenge_completed(ChallengeService.chal_lootworm_hash):
		var value: = 0
		for gold in _active_golds:
			value += gold.value

		if value >= ChallengeService.get_chal(ChallengeService.chal_lootworm_hash).value:
			ChallengeService.complete_challenge(ChallengeService.chal_lootworm_hash)
			RunData.check_beast_master_chal()

func manage_harvesting() -> void :
	for player_index in RunData.get_player_count():
		var pacifist_effect = RunData.get_player_effect(Keys.pacifist_hash, player_index)
		var cryptid_effect = RunData.get_player_effect(Keys.cryptid_hash, player_index)
		var materials_per_living_enemy_effect = RunData.get_player_effect(Keys.materials_per_living_enemy_hash, player_index)
		var charmed_enemy_bonus = 0

		for enemy in _entity_spawner.enemies:
			if enemy.get_charmed_by_player_index() != - 1:
				charmed_enemy_bonus += get_gold_value(EntityType.ENEMY, Utils.default_die_args, enemy.stats.value)

		var harvesting_stat = Utils.get_stat(Keys.stat_harvesting_hash, player_index)
		if harvesting_stat != 0 or pacifist_effect != 0 or _elite_killed_bonus != 0\
		or (cryptid_effect != 0 and RunData.current_living_trees != 0) or materials_per_living_enemy_effect != 0 or charmed_enemy_bonus > 0:
			var pacifist_bonus = round((_entity_spawner.get_all_enemies().size() + _entity_spawner.enemies_removed_for_perf) * (pacifist_effect / 100.0))
			var cryptid_bonus = RunData.current_living_trees * cryptid_effect
			var living_enemy_bonus = _entity_spawner.enemies.size() * materials_per_living_enemy_effect

			if _is_horde_wave:
				pacifist_bonus = (pacifist_bonus / 2) as int

			var val = harvesting_stat + pacifist_bonus + cryptid_bonus + _elite_killed_bonus + living_enemy_bonus + charmed_enemy_bonus

			if val >= 0:
				RunData.add_gold(val, player_index)
				RunData.add_xp(val, player_index)
			else:
				RunData.remove_gold(abs(val) as int, player_index)

			_floating_text_manager.on_harvested(val, player_index)

			if harvesting_stat > 0:
				_harvesting_timer.start()

			RunData.add_xp(0, player_index)


func _get_live_players() -> Array:
	var live_players: = []
	for player in _players:
		if not player.dead:
			live_players.append(player)

	return live_players




func _get_shuffled_live_players() -> Array:
	var live_players: = _get_live_players()
	live_players.shuffle()
	return live_players



func _change_scene(path: String) -> void :
	if Utils.is_on_console():
		OS_Seaven.set_fast_cpu_mode(true)
	var _error = get_tree().change_scene(path)
	if Utils.is_on_console():
		OS_Seaven.set_fast_cpu_mode(false)


func _on_UIBonusGold_mouse_entered() -> void :
	if _cleaning_up:
		_info_popup.display(_ui_bonus_gold, Text.text("INFO_BONUS_GOLD", [str(RunData.bonus_gold)]))


func _on_UIBonusGold_mouse_exited() -> void :
	_info_popup.hide()


func _on_EntitySpawner_players_spawned(players: Array) -> void :
	_players = players
	_camera.targets = players
	_floating_text_manager.players = _players
	_floating_text_manager.players_add_stats_count = []
	for player in _players:
		_floating_text_manager.players_add_stats_count.push_back(0)

	
	EffectBehaviorService.update_active_effect_behaviors()

	if _players.size() > 1:
		_damage_vignette.active = false

	_players_ui.clear()
	for i in _players.size():
		var effects = RunData.get_player_effects(i)

		var player_ui: = PlayerUIElements.new()
		var player_idx_string = str(i + 1)

		player_ui.player_index = i
		player_ui.player_life_bar = get_node("%%PlayerLifeBarContainerP%s/PlayerLifeBarP%s" % [player_idx_string, player_idx_string])
		player_ui.player_life_bar_container = get_node("%%PlayerLifeBarContainerP%s" % player_idx_string)
		player_ui.hud_container = get_node("%%LifeContainerP%s" % player_idx_string)
		player_ui.life_bar = get_node("%%UILifeBarP%s" % player_idx_string)
		player_ui.life_label = get_node("%%UILifeBarP%s/MarginContainer/LifeLabel" % player_idx_string)
		player_ui.hit_protection = get_node("%%LifeContainerP%s/UIHitProtection" % player_idx_string)
		player_ui.xp_bar = get_node("%%UIXPBarP%s" % player_idx_string)
		player_ui.level_label = get_node("%%UIXPBarP%s/MarginContainer/LevelLabel" % player_idx_string)
		player_ui.gold = get_node("%%UIGoldP%s" % player_idx_string)

		
		player_ui.life_label.set_message_translation(false)
		player_ui.level_label.set_message_translation(false)

		_players_ui.push_back(player_ui)

		player_ui.update_hud(_players[i])
		player_ui.hud_visible = true
		player_ui.set_hud_position(i)

		_players[i].get_life_bar_remote_transform().remote_path = player_ui.player_life_bar_container.get_path()
		_players[i].current_stats.health = max(1, _players[i].max_stats.health * (effects[Keys.hp_start_wave_hash] / 100.0)) as int

		if effects[Keys.hp_start_next_wave_hash] != 100:
			_players[i].current_stats.health = max(1, _players[i].max_stats.health * (effects[Keys.hp_start_next_wave_hash] / 100.0)) as int
			effects[Keys.hp_start_next_wave_hash] = 100

		_players[i].check_hp_regen()

		_on_player_health_updated(_players[i], _players[i].current_stats.health, _players[i].max_stats.health)

		var _error = _players[i].connect("health_updated", self, "_on_player_health_updated")
		_error = _players[i].connect("healed", _floating_text_manager, "_on_player_healed")
		_error = _players[i].connect("died", self, "_on_player_died")
		_error = _players[i].connect("took_damage", _screenshaker, "_on_player_took_damage")
		_error = _players[i].connect("healed", self, "on_player_healed")
		_error = _players[i].connect("wanted_to_spawn_gold", self, "on_player_wanted_to_spawn_gold")

		var things_to_process_player_container: UIThingsToProcessPlayerContainer = _things_to_process_player_containers[i]
		things_to_process_player_container.show()
		_error = things_to_process_player_container.upgrades.connect("ui_element_mouse_entered", self, "on_ui_element_mouse_entered")
		_error = things_to_process_player_container.upgrades.connect("ui_element_mouse_exited", self, "on_ui_element_mouse_exited")
		_error = things_to_process_player_container.consumables.connect("ui_element_mouse_entered", self, "on_ui_element_mouse_entered")
		_error = things_to_process_player_container.consumables.connect("ui_element_mouse_exited", self, "on_ui_element_mouse_exited")

		connect_visual_effects(_players[i])

		var pct_val = RunData.get_player_effect(Keys.gain_pct_gold_start_wave_hash, i)
		var apply_pct_gold_wave = (pct_val > 0 and RunData.current_wave <= RunData.nb_of_waves) or pct_val < 0

		
		
		if pct_val < 0 and RunData.current_wave > RunData.nb_of_waves:
			pct_val = - 100.0

		if apply_pct_gold_wave:
			var val = RunData.get_player_gold(i) * (pct_val / 100.0)
			RunData.add_gold(val, i)

			if pct_val > 0:
				RunData.add_tracked_value(i, Keys.item_piggy_bank_hash, val)

	for player_index in _players.size():
		var effects = RunData.get_player_effects(player_index)
		if effects[Keys.stats_next_wave_hash].size() > 0:
			for stat_next_wave in effects[Keys.stats_next_wave_hash]:
				assert (stat_next_wave[0] is int)
				TempStats.add_stat(stat_next_wave[0], stat_next_wave[1], player_index)
			effects[Keys.stats_next_wave_hash].clear()

		check_half_health_stats(player_index)

	DebugService.log_run_info()
	RunData.reset_weapons_dmg_dealt()
	RunData.reset_weapons_tracked_value_this_wave()
	RunData.reset_wave_caches()


func _on_EntitySpawner_enemy_spawned(enemy: Enemy) -> void :
	var _error_died = enemy.connect("died", self, "_on_enemy_died")
	var _error_took_damage = enemy.connect("took_damage", self, "_on_enemy_took_damage")
	_error_took_damage = enemy.connect("took_damage", _screenshaker, "_on_unit_took_damage")
	var _error_stats_boost = enemy.connect("stats_boosted", _effects_manager, "on_unit_stats_boost")
	var _error_heal = enemy.connect("healed", _effects_manager, "on_enemy_healed")
	var _error_speed_removed = enemy.connect("speed_removed", _effects_manager, "on_enemy_speed_removed")
	var _error_state_changed = enemy.connect("state_changed", _floating_text_manager, "on_enemy_state_changed")
	connect_visual_effects(enemy)


func _on_EntitySpawner_enemy_respawned(_enemy: Enemy) -> void :
	RunData.current_living_enemies += 1


func _on_EntitySpawner_neutral_spawned(neutral: Neutral) -> void :
	var _error_died = neutral.connect("died", self, "_on_neutral_died")
	var _error_took_damage = neutral.connect("took_damage", _screenshaker, "_on_unit_took_damage")
	connect_visual_effects(neutral)


func _on_EntitySpawner_neutral_respawned(_neutral: Neutral) -> void :
	RunData.current_living_trees += 1


func _on_EntitySpawner_structure_spawned(structure: Structure) -> void :
	var _error_fruit = structure.connect("wanted_to_spawn_fruit", self, "on_structure_wanted_to_spawn_fruit")


func _on_EntitySpawner_structure_respawned(structure):
	if _is_fog_wave:
		_fog_viewport._on_spawn_structure_or_pet(structure)

func _on_EntitySpawner_pet_spawned(pet):
	if _is_fog_wave:
		_fog_viewport._on_spawn_structure_or_pet(pet)


func _on_EntitySpawner_enemy_charmed(enemy):
	if _is_fog_wave:
		_fog_viewport._on_spawn_structure_or_pet(enemy)

func on_structure_wanted_to_spawn_fruit(pos: Vector2) -> void :
	var consumable_to_spawn = ItemService.get_consumable_for_tier(Tier.COMMON)
	var consumable: Consumable = get_node_from_pool(_consumable_pool_id, _consumables_container)
	if consumable == null:
		consumable = consumable_scene.instance()
		_consumables_container.call_deferred("add_child", consumable)
		var _error = consumable.connect("picked_up", self, "on_consumable_picked_up")
		yield(consumable, "ready")

	consumable.consumable_data = consumable_to_spawn
	consumable.already_picked_up = false
	consumable.set_texture(consumable_to_spawn.icon)
	var dist = rand_range(100, 150)
	var push_back_destination = Vector2(rand_range(pos.x - dist, pos.x + dist), rand_range(pos.y - dist, pos.y + dist))
	consumable.drop(pos, 0, push_back_destination)
	_consumables.push_back(consumable)


func _on_HarvestingTimer_timeout() -> void :
	for player_index in RunData.get_player_count():
		var harvesting_stat = Utils.get_stat(Keys.stat_harvesting_hash, player_index)
		if harvesting_stat <= 0:
			continue
		if RunData.current_wave > RunData.nb_of_waves:
			var val = ceil(harvesting_stat * (RunData.ENDLESS_HARVESTING_DECREASE / 100.0))
			RunData.remove_stat(Keys.stat_harvesting_hash, val, player_index)
		else:
			var harvesting_growth = RunData.get_player_effect(Keys.harvesting_growth_hash, player_index)
			var val = ceil(harvesting_stat * (harvesting_growth / 100.0))

			var has_crown = false
			var crown_value = 0

			var items = RunData.get_player_items_ref(player_index)
			for item in items:
				
				
				if item.my_id_hash == Keys.item_crown_hash:
					has_crown = true
					crown_value = item.effects[0].value
					break

			if has_crown:
				RunData.add_tracked_value(player_index, Keys.item_crown_hash, ceil(harvesting_stat * (crown_value / 100.0)) as int)

			if val > 0:
				RunData.add_stat(Keys.stat_harvesting_hash, val, player_index)


func on_player_healed(_value: int, player_index: int) -> void :
	var dmg_when_heal_effect = RunData.get_player_effect(Keys.dmg_when_heal_hash, player_index)
	var _dmg_taken = handle_stat_damages(dmg_when_heal_effect, player_index)

func handle_stat_damages(stat_damages: Array, player_index: int) -> Array:
	var total_dmg_to_deal = 0
	var dmg_taken = [0, 0]
	var tracking_values: Dictionary = {}

	if stat_damages.empty():
		return dmg_taken

	var include_charmed_enemies = false
	var enemies: Array = _entity_spawner.get_all_enemies(include_charmed_enemies)
	var other_enemy = Utils.get_rand_element(enemies)
	if other_enemy == null or not is_instance_valid(other_enemy) or other_enemy.current_stats.health == 0:
		return dmg_taken

	var stat_dict = {}
	var percent_dmg_bonus = 1 + Utils.get_stat(Keys.stat_percent_damage_hash, player_index) / 100.0
	for stat_dmg in stat_damages:

		if randf() >= stat_dmg[2] / 100.0:
			continue

		assert (stat_dmg[0] is int)
		var dmg_dict = stat_dict.get(stat_dmg[0])
		if not dmg_dict:
			dmg_dict = {Keys.stat_hash: Utils.get_stat(stat_dmg[0], player_index)}
			stat_dict[stat_dmg[0]] = dmg_dict
		var dmg = dmg_dict.get(stat_dmg[1])
		if not dmg:
			var base_dmg: = floor(max(1, stat_dmg[1] / 100.0 * dmg_dict[Keys.stat_hash]))
			dmg = round(base_dmg * percent_dmg_bonus) as int
			dmg_dict[stat_dmg[1]] = dmg
		total_dmg_to_deal += dmg

		
		if stat_damages.size() == 1 and total_dmg_to_deal <= 0:
			return dmg_taken

		var tracking_key: int = stat_dmg[3] if stat_dmg.size() == 4 else - 1
		if tracking_key != - 1:
			if tracking_values.has(tracking_key):
				tracking_values[tracking_key] += dmg
			else:
				tracking_values[tracking_key] = dmg

	if total_dmg_to_deal <= 0:
		return dmg_taken

	
	_take_damage_args._init(player_index)
	dmg_taken = other_enemy.take_damage(total_dmg_to_deal, _take_damage_args)

	var remaining_damage_to_track: int = dmg_taken[1]
	for tracking_key in tracking_values.keys():
		var tracking_value = tracking_values[tracking_key]

		if tracking_value <= remaining_damage_to_track:
			RunData.add_tracked_value(player_index, tracking_key, tracking_value)
			remaining_damage_to_track -= tracking_value

		else:
			RunData.add_tracked_value(player_index, tracking_key, remaining_damage_to_track)
			break

	return dmg_taken


func check_half_health_stats(player_index: int) -> void :
	var stats_below_half_health = RunData.get_player_effect(Keys.stats_below_half_health_hash, player_index)
	if stats_below_half_health.size() == 0:
		return

	var current_val = _players[player_index].current_stats.health
	var max_val = _players[player_index].max_stats.health
	if current_val < (max_val / 2.0) and not _player_is_under_half_health[player_index]:
		_player_is_under_half_health[player_index] = true
		for stat in stats_below_half_health:
			assert (stat[0] is int)
			TempStats.add_stat(stat[0], stat[1], player_index)
			RunData.emit_signal("stat_added", stat[0], stat[1], 0.0, player_index)

	elif current_val >= max_val / 2.0 and _player_is_under_half_health[player_index]:
		_player_is_under_half_health[player_index] = false
		for stat in stats_below_half_health:
			assert (stat[0] is int)
			TempStats.remove_stat(stat[0], stat[1], player_index)
			RunData.emit_signal("stat_removed", stat[0], stat[1], 0.0, player_index)


func _on_player_health_updated(player: Player, current_val: int, max_val: int) -> void :
	var player_index = player.player_index
	RunData.players_data[player_index].current_health = current_val

	if player.player_index == 0 and not RunData.is_coop_run:
		_damage_vignette.update_from_hp(current_val, max_val)

	check_half_health_stats(player_index)

	var player_ui: PlayerUIElements = _players_ui[player_index]
	var life_bar = player_ui.life_bar
	life_bar.update_value(current_val, max_val)

	var player_life_bar = player_ui.player_life_bar
	player_life_bar.visible = ProgressData.settings.hp_bar_on_character and current_val != max_val and not player.dead
	if player_life_bar.visible:
		player_life_bar.update_value(current_val, max_val)

	var die_in_one_hit = RunData.get_player_effect(Keys.die_in_one_hit_hash, player_index)
	if die_in_one_hit == 1:
		player_ui.hide_life_label(player)
	else:
		player_ui.update_life_label(player)
	var hit_protection_count = player._hit_protection
	player_ui.update_hit_protection_count(player, hit_protection_count)


func on_gold_changed(new_value: int, player_index: int) -> void :
	var player_ui: PlayerUIElements = _players_ui[player_index]
	player_ui.gold.update_value(new_value)


func on_damage_effect(value: int, player_index: int, armor_applied: bool, dodgeable: bool, from = null) -> void :
	_players[player_index].on_damage_effect(value, armor_applied, dodgeable, from)


func on_lifesteal_effect(value: int, player_index: int) -> void :
	var player: Player = _players[player_index]
	player.on_lifesteal_effect(value)


func on_healing_effect(value: int, player_index: int, tracking_key: int = Keys.empty_hash) -> void :
	_players[player_index].on_healing_effect(value, tracking_key)


func on_heal_over_time_effect(total_healing: int, duration: int, player_index: int) -> void :
	_players[player_index].on_heal_over_time_effect(total_healing, duration)


func on_chal_popup() -> void :
	_is_chal_ui_displayed = true


func on_chal_popout() -> void :
	_is_chal_ui_displayed = false


func _on_HalfSecondTimer_timeout(player_index: int) -> void :
	if LinkedStats.update_for_player_every_half_sec[player_index]:
		LinkedStats.reset_player(player_index)


func _on_game_lost_focus() -> void :
	if not _retry_wave.visible:
		_pause_menu.on_game_lost_focus()


func _on_emit_fire_particle(burning_particle):
	if _is_fog_wave:
		_fog_viewport._on_emit_fire_particle(burning_particle)


func get_node_from_pool(id: int, parent: Node) -> Node:
	if _current_pool_id != id:
		_current_pool_id = id
		if _pool.has(id):
			_current_pool = _pool[id]
		else:
			_pool[id] = []
			_current_pool = _pool[id]
			return null

	if _current_pool.empty():
		return null

	var node = _current_pool.pop_back()
	if is_instance_valid(node):
		parent.add_child(node)
		return node

	return null



func is_pool_empty(id: int) -> bool:
	if _pool.has(id):
		return _pool[id].empty()

	return true


func add_node_to_pool(node: Node, id: int) -> void :
	assert (_pool.has(id))
	_add_node_to_pool(node, id)


func is_in_pool(node: Node) -> bool:
	for key in _pool.keys():
		var pool = _pool[key]
		for n in pool:
			if node == n:
				return true
	return false



func _add_node_to_pool(node: Node, id: int) -> void :
	if node.get_parent() == null:
		return
	
	_pool[id].push_back(node)
	node.get_parent().remove_child(node)



func add_explosion(instance: PlayerExplosion) -> void :
	_explosions.add_child(instance)


func add_effect(instance: Node) -> void :
	_effects.add_child(instance)


func add_floating_text(instance: FloatingText) -> void :
	_floating_texts.add_child(instance)


func add_player_projectile(instance: PlayerProjectile) -> void :
	_player_projectiles.add_child(instance)


func add_enemy_projectile(instance: Projectile) -> void :
	_enemy_projectiles.add_child(instance)


func add_birth(instance: EntityBirth) -> void :
	_births_container.add_child(instance)


func add_entity(instance: Entity) -> void :
	_entities_container.add_child(instance)


func _exit_tree() -> void :
	InputService.set_gamepad_echo_processing(true)
	if _pool != null:
		for key in _pool.keys():
			var pool = _pool[key]
			for node in pool:
				node.queue_free()


func _on_HalfWaveTimer_timeout() -> void :
	for player_index in RunData.get_player_count():
		Utils.convert_stats(RunData.get_player_effect(Keys.convert_stats_half_wave_hash, player_index), player_index, false)

	if RunData.concat_all_player_effects(Keys.convert_stats_half_wave_hash).size() > 0:
		_wave_timer_label.change_color(Color.deepskyblue)
