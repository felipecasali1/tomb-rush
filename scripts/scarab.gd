extends CharacterBody2D
class_name Scarab

const SPEED_MIN := 24.0
const SPEED_MAX := 38.0
const ATTACK_DISTANCE := 13.0
const ATTACK_COOLDOWN := 0.75
const DAMAGE := 8
const AVOIDANCE_TIME := 0.45
const STUCK_TIME := 0.3

var target: Node2D
var speed := 30.0
var attack_timer := 0.0
var avoidance_direction := Vector2.ZERO
var avoidance_timer := 0.0
var stuck_timer := 0.0
var previous_position := Vector2.ZERO

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	speed = randf_range(SPEED_MIN, SPEED_MAX)
	animated_sprite.play("walking")
	previous_position = global_position


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		return

	attack_timer = maxf(attack_timer - delta, 0.0)
	avoidance_timer = maxf(avoidance_timer - delta, 0.0)
	var target_direction: Vector2 = global_position.direction_to(target.global_position)
	var direction := target_direction

	if avoidance_timer > 0.0:
		direction = target_direction.lerp(avoidance_direction, 0.85).normalized()

	velocity = direction * speed
	move_and_slide()
	_process_obstacles(delta, target_direction)

	if direction.x != 0.0:
		animated_sprite.flip_h = direction.x < 0.0

	if global_position.distance_to(target.global_position) <= ATTACK_DISTANCE and attack_timer <= 0.0:
		if target.has_method("take_damage"):
			target.take_damage(DAMAGE)
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
			break

	if stuck_timer >= STUCK_TIME:
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
