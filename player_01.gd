extends CharacterBody2D

const SPEED := 300.0
const JUMP_VELOCITY := -400.0

@onready var animacao: AnimatedSprite2D = $AnimatedSprite2D

var spawn_position: Vector2


func _enter_tree() -> void:
    set_multiplayer_authority(name.to_int())


func _ready() -> void:
    add_to_group("players")
    spawn_position = global_position


func _physics_process(delta: float) -> void:
    # Só o dono do personagem pode controlar seus movimentos.
    if not is_multiplayer_authority():
        return

    if not is_on_floor():
        velocity += get_gravity() * delta

    if Input.is_action_just_pressed("Player01 pular ") and is_on_floor():
        velocity.y = JUMP_VELOCITY

    var direction := Input.get_axis(
        "Player01 andar a esquerda",
        "Player01 andar a direita"
    )

    if direction != 0:
        velocity.x = direction * SPEED
        animacao.scale.x = abs(animacao.scale.x) * sign(direction)
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)

    move_and_slide()

    if global_position.y > 900:
        global_position = spawn_position
        velocity = Vector2.ZERO

    if not is_on_floor() or direction != 0:
        animacao.play("run_jump")
    else:
        animacao.play("idle")
