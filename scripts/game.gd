extends Node2D

const HOLD_TARGET := 60.0
const ZONE_CHANGE_INTERVAL := 30.0
const ZONE_RADIUS := 54.0
const MAX_SCARABS := 100
const GRID_SIZE := Vector2i(50, 50)
const GRID_CELL_SIZE := 16.0
const PATH_CLEARANCE := 2.0
const SPAWN_MIN_DISTANCE := 180.0
const SPAWN_CHECK_RADIUS := 8.0
const SPAWN_EDGE_MARGIN := 3
const SCARAB_SCENE: PackedScene = preload("res://entities/scarab.tscn")
const GIANT_SCARAB_SCENE: PackedScene = preload("res://entities/GiantScarab.tscn")
const GIANT_SCARAB_CHANCE := 0.18

var zone_positions: Array[Vector2] = [
	Vector2(80, 96),
	Vector2(720, 96),
	Vector2(80, 720),
	Vector2(720, 720),
]

var active_zone_index := -1
var held_seconds := 0.0
var zone_seconds := 0.0
var scarab_spawn_seconds := 0.0
var game_finished := false
var path_grid: AStarGrid2D

var objective_label: Label
var progress_label: Label
var status_label: Label
var help_label: Label
var progress_bar: ProgressBar
var health_bar: ProgressBar
var end_panel: PanelContainer
var end_label: Label
var zone_visual: ZoneVisual

@onready var player := $Player as Player


func _ready() -> void:
	randomize()
	zone_visual = ZoneVisual.new()
	zone_visual.z_index = 1
	add_child(zone_visual)
	_create_hud()
	_choose_next_zone()

	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	_on_player_health_changed(player.health, player.max_health)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	path_grid = _build_path_grid()

	for index in range(6):
		_spawn_scarab(index == 0)


func _process(delta: float) -> void:
	if game_finished:
		return

	zone_seconds += delta
	scarab_spawn_seconds += delta

	if zone_seconds >= ZONE_CHANGE_INTERVAL:
		zone_seconds = 0.0
		_choose_next_zone()

	var inside_zone := player.global_position.distance_to(zone_positions[active_zone_index]) <= ZONE_RADIUS
	if inside_zone:
		held_seconds = minf(held_seconds + delta, HOLD_TARGET)
		if held_seconds >= HOLD_TARGET:
			_win_game()

	if scarab_spawn_seconds >= 4.0:
		scarab_spawn_seconds = 0.0
		if get_tree().get_nodes_in_group("scarabs").size() < MAX_SCARABS:
			_spawn_scarab()

	_update_hud(inside_zone)


func _choose_next_zone() -> void:
	var choices: Array[int] = []
	for index in range(zone_positions.size()):
		if index != active_zone_index:
			choices.append(index)

	active_zone_index = choices[randi() % choices.size()]
	status_label.text = "Vá para o território dourado!"
	zone_visual.set_zone(zone_positions[active_zone_index])


func _spawn_scarab(force_giant: bool = false) -> void:
	var scarab_scene: PackedScene = GIANT_SCARAB_SCENE if force_giant or randf() < GIANT_SCARAB_CHANCE else SCARAB_SCENE
	var scarab: Scarab = scarab_scene.instantiate() as Scarab
	scarab.add_to_group("scarabs")
	scarab.target = player
	scarab.position = _get_scarab_spawn_position()
	scarab.set_path_grid(path_grid)
	add_child(scarab)


func _build_path_grid() -> AStarGrid2D:
	var blocked_cells := 0
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, GRID_SIZE)
	grid.cell_size = Vector2(GRID_CELL_SIZE, GRID_CELL_SIZE)
	grid.offset = Vector2(GRID_CELL_SIZE * 0.5, GRID_CELL_SIZE * 0.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()

	var query_shape := CircleShape2D.new()
	query_shape.radius = PATH_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = query_shape
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]
	var space_state := get_world_2d().direct_space_state

	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			var cell := Vector2i(x, y)
			query.transform = Transform2D(0.0, grid.get_point_position(cell))
			if not space_state.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(cell, true)
				blocked_cells += 1
	print("Células bloqueadas na grade: ", blocked_cells)
	return grid


func _get_scarab_spawn_position() -> Vector2:
	if path_grid == null:
		return Vector2(56.0, 56.0)

	var region: Rect2i = path_grid.region
	var min_x := region.position.x + SPAWN_EDGE_MARGIN
	var max_x := region.position.x + region.size.x - SPAWN_EDGE_MARGIN - 1
	var min_y := region.position.y + SPAWN_EDGE_MARGIN
	var max_y := region.position.y + region.size.y - SPAWN_EDGE_MARGIN - 1

	for _attempt in range(80):
		var side := randi() % 4
		var cell: Vector2i
		match side:
			0:
				cell = Vector2i(randi_range(min_x, max_x), min_y)
			1:
				cell = Vector2i(max_x, randi_range(min_y, max_y))
			2:
				cell = Vector2i(randi_range(min_x, max_x), max_y)
			_:
				cell = Vector2i(min_x, randi_range(min_y, max_y))

		if path_grid.is_point_solid(cell):
			continue

		var candidate := path_grid.get_point_position(cell)
		if candidate.distance_to(player.global_position) < SPAWN_MIN_DISTANCE:
			continue
		if not _is_spawn_position_clear(candidate):
			continue

		return candidate

	# Se nenhuma borda estiver livre, procura qualquer célula segura do mapa.
	for y in range(region.position.y, region.position.y + region.size.y):
		for x in range(region.position.x, region.position.x + region.size.x):
			var cell := Vector2i(x, y)
			if path_grid.is_point_solid(cell):
				continue

			var candidate := path_grid.get_point_position(cell)
			if candidate.distance_to(player.global_position) < SPAWN_MIN_DISTANCE:
				continue
			if _is_spawn_position_clear(candidate):
				return candidate

	push_warning("Não foi encontrada uma posição segura para gerar o escaravelho.")
	return Vector2(56.0, 56.0)


func _is_spawn_position_clear(candidate: Vector2) -> bool:
	var query_shape := CircleShape2D.new()
	query_shape.radius = SPAWN_CHECK_RADIUS
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = query_shape
	query.transform = Transform2D(0.0, candidate)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [player.get_rid()]

	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false

	for other in get_tree().get_nodes_in_group("scarabs"):
		if is_instance_valid(other) and other.global_position.distance_to(candidate) < 24.0:
			return false

	return true


func _create_hud() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "HUD"
	canvas_layer.layer = 10
	add_child(canvas_layer)

	# Vida: somente uma barra vermelha no canto superior esquerdo.
	var health_panel := PanelContainer.new()
	health_panel.position = Vector2(24, 24)
	health_panel.size = Vector2(300, 52)
	health_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.03, 0.02, 0.02, 0.78)))
	canvas_layer.add_child(health_panel)

	var health_margin := MarginContainer.new()
	health_margin.add_theme_constant_override("margin_left", 14)
	health_margin.add_theme_constant_override("margin_top", 14)
	health_margin.add_theme_constant_override("margin_right", 14)
	health_margin.add_theme_constant_override("margin_bottom", 14)
	health_panel.add_child(health_margin)

	health_bar = ProgressBar.new()
	health_bar.max_value = player.max_health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(0, 24)
	health_bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.16, 0.04, 0.04, 1.0)))
	health_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.709, 0.059, 0.06, 1.0)))
	health_margin.add_child(health_bar)

	# Objetivo, progresso e dicas centralizados no topo.
	var top_panel := PanelContainer.new()
	top_panel.anchor_left = 0.5
	top_panel.anchor_right = 0.5
	top_panel.offset_left = -320
	top_panel.offset_right = 320
	top_panel.offset_top = 18
	top_panel.offset_bottom = 190
	top_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.03, 0.02, 0.02, 0.75)))
	canvas_layer.add_child(top_panel)

	var top_margin := MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 24)
	top_margin.add_theme_constant_override("margin_top", 14)
	top_margin.add_theme_constant_override("margin_right", 24)
	top_margin.add_theme_constant_override("margin_bottom", 14)
	top_panel.add_child(top_margin)

	var top_box := VBoxContainer.new()
	top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_box.add_theme_constant_override("separation", 5)
	top_margin.add_child(top_box)

	var title := Label.new()
	title.text = "TOMB RUSH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	top_box.add_child(title)

	objective_label = Label.new()
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective_label.add_theme_font_size_override("font_size", 17)
	top_box.add_child(objective_label)

	progress_bar = ProgressBar.new()
	progress_bar.max_value = HOLD_TARGET
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 20)
	progress_bar.add_theme_stylebox_override("background", _make_panel_style(Color(0.16, 0.10, 0.02, 1.0)))
	progress_bar.add_theme_stylebox_override("fill", _make_panel_style(Color(0.95, 0.58, 0.08, 1.0)))
	top_box.add_child(progress_bar)

	progress_label = Label.new()
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 17)
	top_box.add_child(progress_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	top_box.add_child(status_label)

	# Mensagem de fim: invisível até vitória ou derrota.
	end_panel = PanelContainer.new()
	end_panel.anchor_left = 0.5
	end_panel.anchor_right = 0.5
	end_panel.anchor_top = 0.5
	end_panel.anchor_bottom = 0.5
	end_panel.offset_left = -310
	end_panel.offset_right = 310
	end_panel.offset_top = -100
	end_panel.offset_bottom = 100
	end_panel.visible = false
	end_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.01, 0.01, 0.92)))
	canvas_layer.add_child(end_panel)

	var end_margin := MarginContainer.new()
	end_margin.add_theme_constant_override("margin_left", 28)
	end_margin.add_theme_constant_override("margin_top", 24)
	end_margin.add_theme_constant_override("margin_right", 28)
	end_margin.add_theme_constant_override("margin_bottom", 24)
	end_panel.add_child(end_margin)

	end_label = Label.new()
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_label.add_theme_font_size_override("font_size", 24)
	end_margin.add_child(end_label)


func _make_panel_style(background_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _update_hud(inside_zone: bool) -> void:
	if game_finished:
		return

	var remaining := maxf(ZONE_CHANGE_INTERVAL - zone_seconds, 0.0)
	objective_label.text = "Zona dourada ao %s" % _get_zone_direction()
	progress_label.text = "Progresso: %.1f / %.0f s   |   Troca em %.1f s" % [held_seconds, HOLD_TARGET, remaining]
	progress_bar.value = held_seconds


func _get_zone_direction() -> String:
	var zone_position: Vector2 = zone_positions[active_zone_index]
	var offset: Vector2 = zone_position - player.global_position
	var horizontal := ""
	var vertical := ""

	if absf(offset.x) > 20.0:
		horizontal = "leste" if offset.x > 0.0 else "oeste"
	if absf(offset.y) > 20.0:
		vertical = "sul" if offset.y > 0.0 else "norte"

	if vertical == "" and horizontal == "":
		return "aqui"
	if vertical == "":
		return horizontal
	if horizontal == "":
		return vertical
	if vertical == "norte" and horizontal == "leste":
		return "nordeste"
	if vertical == "norte" and horizontal == "oeste":
		return "noroeste"
	if vertical == "sul" and horizontal == "leste":
		return "sudeste"
	return "sudoeste"


func _on_player_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_player_died() -> void:
	game_finished = true
	status_label.text = ""
	end_label.text = "VOCÊ FOI DERROTADO\n\nPressione ENTER para tentar novamente"
	end_panel.visible = true
	player.set_physics_process(false)
	_set_scarabs_active(false)


func _win_game() -> void:
	game_finished = true
	status_label.text = ""
	end_label.text = "TUMBA CONQUISTADA!"
	end_panel.visible = true
	player.set_physics_process(false)
	_set_scarabs_active(false)


func _set_scarabs_active(active: bool) -> void:
	for scarab in get_tree().get_nodes_in_group("scarabs"):
		scarab.set_physics_process(active)


func _unhandled_input(event: InputEvent) -> void:
	if game_finished and event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()
