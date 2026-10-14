extends CharacterBody2D
class_name Scarab

const SPEED_MIN := 24.0
const SPEED_MAX := 38.0
const ATTACK_DISTANCE := 13.0
const ATTACK_COOLDOWN := 0.75
const DAMAGE := 8
const AVOIDANCE_TIME := 0.45
const STUCK_TIME := 0.3
const CELL_SIZE := 16.0
const PATH_REFRESH_INTERVAL := 0.35
const WAYPOINT_REACHED_DISTANCE := 8.0

@export var speed_min: float = SPEED_MIN
@export var speed_max: float = SPEED_MAX
@export var attack_distance: float = ATTACK_DISTANCE
@export var damage: int = DAMAGE

var target: Node2D
var path_grid: AStarGrid2D
var speed := 30.0
var attack_timer := 0.0
var path_refresh_timer := 0.0
var path_points: Array[Vector2] = []
var avoidance_direction := Vector2.ZERO
var avoidance_timer := 0.0
var stuck_timer := 0.0
var previous_position := Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	speed = randf_range(speed_min, speed_max)
	animated_sprite.play("walking")
	previous_position = global_position


func set_path_grid(grid: AStarGrid2D) -> void:
	path_grid = grid
	_refresh_path()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	attack_timer = maxf(attack_timer - delta, 0.0)
	avoidance_timer = maxf(avoidance_timer - delta, 0.0)
	path_refresh_timer = maxf(path_refresh_timer - delta, 0.0)
	var target_direction: Vector2 = global_position.direction_to(target.global_position)

	if path_refresh_timer <= 0.0:
		_refresh_path()
		path_refresh_timer = PATH_REFRESH_INTERVAL

	var desired_direction := _get_path_direction(target_direction)
	var direction := desired_direction

	# Temporariamente desativado:
	# if avoidance_timer > 0.0:
	#     direction = direction.lerp(avoidance_direction, 0.55).normalized()

	velocity = direction * speed
	move_and_slide()
	#_process_obstacles(delta, desired_direction)

	if direction.x != 0.0:
		animated_sprite.flip_h = direction.x < 0.0

	if global_position.distance_to(target.global_position) <= attack_distance and attack_timer <= 0.0:
		if target.has_method("take_damage"):
			target.take_damage(damage)
		attack_timer = ATTACK_COOLDOWN


func _process_obstacles(delta: float, target_direction: Vector2) -> void:
	var moved_distance := global_position.distance_to(previous_position)
	if target_direction.length() > 0.1 and moved_distance < 0.1:
		stuck_timer += delta
	else:
		stuck_timer = 0.0

	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		if collision.get_collider() != target:
			_start_wall_avoidance(collision.get_normal(), target_direction)
			path_refresh_timer = 0.0
			break

	if stuck_timer >= STUCK_TIME:
		_refresh_path()
		# Se uma quina bloquear o movimento, tenta uma direção perpendicular.
		_start_wall_avoidance(Vector2.ZERO, target_direction)
		stuck_timer = 0.0

	previous_position = global_position


func _start_wall_avoidance(wall_normal: Vector2, target_direction: Vector2) -> void:
	var tangent: Vector2
	if wall_normal.length_squared() > 0.01:
		var tangent_a := Vector2(-wall_normal.y, wall_normal.x).normalized()
		var tangent_b := -tangent_a
		tangent = tangent_a if tangent_a.dot(target_direction) >= tangent_b.dot(target_direction) else tangent_b
	else:
		tangent = target_direction.rotated(PI * 0.5).normalized()

	avoidance_direction = tangent
	avoidance_timer = AVOIDANCE_TIME


func _refresh_path() -> void:
	if path_grid == null or not is_instance_valid(target):
		return

	var start_cell := _find_nearest_walkable_cell(_world_to_cell(global_position))
	var target_cell := _find_nearest_walkable_cell(_world_to_cell(target.global_position))
	if start_cell.x < 0 or target_cell.x < 0:
		path_points.clear()
		return

	var cell_path := path_grid.get_id_path(start_cell, target_cell)
	if cell_path.is_empty():
		push_warning("Escaravelho sem rota: %s -> %s" % [start_cell, target_cell])
	path_points.clear()
	for cell in cell_path:
		path_points.append(path_grid.get_point_position(cell))

	if not path_points.is_empty():
		path_points.remove_at(0)


func _get_path_direction(fallback: Vector2) -> Vector2:
	while not path_points.is_empty() and global_position.distance_to(path_points[0]) <= WAYPOINT_REACHED_DISTANCE:
		path_points.remove_at(0)

	if path_points.is_empty():
		return Vector2.ZERO

	return global_position.direction_to(path_points[0])


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / CELL_SIZE), floori(world_position.y / CELL_SIZE))


func _find_nearest_walkable_cell(origin: Vector2i) -> Vector2i:
	var grid_region: Rect2i = path_grid.region
	for radius in range(0, 5):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var candidate := origin + Vector2i(x, y)
				if not grid_region.has_point(candidate):
					continue
				if not path_grid.is_point_solid(candidate):
					return candidate

	return Vector2i(-1, -1)
