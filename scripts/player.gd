
extends CharacterBody2D

const SPEED = 75.0
const DEADZONE = 0.25

enum State {
	IDLE,
	WALK
}

var current_state: State = State.IDLE

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _physics_process(_delta: float) -> void:
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
	else:
		change_state(State.WALK)

		if direction.x < 0:
			animated_sprite.flip_h = true
		elif direction.x > 0:
			animated_sprite.flip_h = false

	move_and_slide()


func change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	current_state = new_state

	match current_state:
		State.IDLE:
			animated_sprite.play("idle")
		State.WALK:
			animated_sprite.play("walking")
