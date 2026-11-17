extends CharacterBody2D
class_name Player

const SPEED = 75.0
const DEADZONE = 0.25
const MAX_HEALTH := 100
const INVULNERABILITY_TIME := 0.35
const REGEN_DELAY := 3.0
const REGEN_INTERVAL := 0.1

signal health_changed(current: int, maximum: int)
signal died

enum State {
	IDLE,
	WALK
}

var current_state: State = State.IDLE
var max_health := MAX_HEALTH
var health := MAX_HEALTH
var invulnerability_timer := 0.0
var idle_timer := 0.0
var regen_timer := 0.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _physics_process(delta: float) -> void:
	invulnerability_timer = maxf(invulnerability_timer - delta, 0.0)

	# Teclado: WASD e setas
	var keyboard_direction := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) -
		float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) -
		float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	).normalized()

	# Controle: primeiro dispositivo conectado
	var controller_direction := Vector2.ZERO
	var joypads := Input.get_connected_joypads()

	if not joypads.is_empty():
		var joy_id: int = joypads[0]

		var joy_x := Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_X)
		var joy_y := Input.get_joy_axis(joy_id, JOY_AXIS_LEFT_Y)

		controller_direction = Vector2(joy_x, joy_y)

		# Filtra o drift do analógico
		if controller_direction.length() < DEADZONE:
			controller_direction = Vector2.ZERO
		else:
			controller_direction = controller_direction.normalized()

	# Combina as entradas sem sobrescrever o teclado
	var direction := (keyboard_direction + controller_direction).limit_length(1.0)

	velocity = direction * SPEED

	if direction == Vector2.ZERO:
		change_state(State.IDLE)
		_regenerate_health(delta)
	else:
		idle_timer = 0.0
		regen_timer = 0.0
		change_state(State.WALK)
		_update_walk_animation(direction)

	move_and_slide()


func _regenerate_health(delta: float) -> void:
	if health <= 0:
		return

	var previous_idle_time := idle_timer
	idle_timer = minf(idle_timer + delta, REGEN_DELAY)
	if health >= max_health:
		regen_timer = 0.0
		return

	# Conta apenas o tempo após os três segundos parado.
	regen_timer += maxf(delta - (REGEN_DELAY - previous_idle_time), 0.0)
	while regen_timer >= REGEN_INTERVAL and health < max_health:
		regen_timer -= REGEN_INTERVAL
		health += 1
		health_changed.emit(health, max_health)


func take_damage(amount: int) -> void:
	if invulnerability_timer > 0.0 or health <= 0:
		return

	health = maxi(health - amount, 0)
	invulnerability_timer = INVULNERABILITY_TIME
	idle_timer = 0.0
	regen_timer = 0.0
	health_changed.emit(health, max_health)

	if health == 0:
		died.emit()


func change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	current_state = new_state

	match current_state:
		State.IDLE:
			animated_sprite.play("idle")
		State.WALK:
			animated_sprite.play("walking")


func _update_walk_animation(direction: Vector2) -> void:
	var animation_name := "walking"

	# Em diagonais, usa a animação do eixo dominante para evitar trocar
	# de animação a cada frame.
	if absf(direction.y) > absf(direction.x):
		animation_name = "walking_up" if direction.y < 0.0 else "walking_down"
		animated_sprite.flip_h = false
	else:
		if direction.x < 0.0:
			animated_sprite.flip_h = true
		elif direction.x > 0.0:
			animated_sprite.flip_h = false

	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)
