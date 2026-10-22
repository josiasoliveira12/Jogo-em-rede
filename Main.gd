extends Node2D

const PORT := 7000
const MAX_CLIENTS := 1
const PLAYER_01_SCENE: PackedScene = preload("res://player_01.tscn")
const PLAYER_02_SCENE: PackedScene = preload("res://player_02.tscn")

@onready var players: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var spawn_host: Marker2D = $SpawnHost
@onready var spawn_client: Marker2D = $SpawnClient
@onready var status_label: Label = $CanvasLayer/Interface/StatusLabel
@onready var address_input: LineEdit = $CanvasLayer/Interface/AddressLineEdit
@onready var score_label: Label = $CanvasLayer/Interface/ScoreLabel
@onready var winner_label: Label = $WinnerLabel

var match_finished := false
var wins_player_1 := 0
var wins_player_2 := 0


func _ready() -> void:
    spawner.add_spawnable_scene("res://player_01.tscn")
    spawner.add_spawnable_scene("res://player_02.tscn")

    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected_to_server)
    multiplayer.connection_failed.connect(_on_connection_failed)
    multiplayer.server_disconnected.connect(_on_server_disconnected)

    _update_score_label()


func host_game() -> void:
    var peer := ENetMultiplayerPeer.new()
    var error := peer.create_server(PORT, MAX_CLIENTS)

    if error != OK:
        status_label.text = "Não foi possível criar o servidor. Código: %s" % error
        return

    multiplayer.multiplayer_peer = peer
    status_label.text = "Servidor criado. Você é o Jogador 1."
    spawn_player(1)


func join_game(address: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    var error := peer.create_client(address, PORT)

    if error != OK:
        status_label.text = "Não foi possível iniciar a conexão. Código: %s" % error
        return

    multiplayer.multiplayer_peer = peer
    status_label.text = "Conectando ao servidor..."


func _on_join_button_pressed() -> void:
    var address := address_input.text.strip_edges()
    if address.is_empty():
        address = "127.0.0.1"
    join_game(address)


func _on_peer_connected(id: int) -> void:
    if multiplayer.is_server():
        spawn_player(id)
        status_label.text = "Jogador %s conectado." % id


func _on_peer_disconnected(id: int) -> void:
    if not multiplayer.is_server():
        return

    var player := players.get_node_or_null(str(id))
    if player != null:
        player.queue_free()

    status_label.text = "Jogador %s desconectou." % id


func _on_connected_to_server() -> void:
    status_label.text = "Conectado! Você é o Jogador 2."
    _update_score_label()


func _on_connection_failed() -> void:
    status_label.text = "A conexão falhou. Confira o endereço e tente novamente."
    multiplayer.multiplayer_peer = null


func _on_server_disconnected() -> void:
    status_label.text = "A conexão com o servidor foi encerrada."
    multiplayer.multiplayer_peer = null


func spawn_player(id: int) -> void:
    if not multiplayer.is_server():
        return

    if players.has_node(str(id)):
        return

    var cena_jogador: PackedScene
    var ponto_nascimento: Marker2D

    if id == 1:
        cena_jogador = PLAYER_01_SCENE
        ponto_nascimento = spawn_host
    else:
        cena_jogador = PLAYER_02_SCENE
        ponto_nascimento = spawn_client

    var jogador := cena_jogador.instantiate()
    # O nome numérico identifica o peer dono do personagem.
    jogador.name = str(id)
    jogador.set_meta("player_number", 1 if id == 1 else 2)
    jogador.position = ponto_nascimento.position
    players.add_child(jogador, true)


func _on_portal_body_entered(body: Node2D) -> void:
    # A colisão pode acontecer na instância do cliente. O servidor é quem
    # registra a vitória e atualiza o placar para todos.
    if not body.is_in_group("players"):
        return

    var peer_id := int(body.name) if body.name.is_valid_int() else 0
    if peer_id <= 0:
        return

    if multiplayer.is_server():
        _finish_match(peer_id)
    else:
        request_portal_win.rpc_id(1, peer_id)


@rpc("any_peer", "call_remote", "reliable")
func request_portal_win(peer_id: int) -> void:
    if not multiplayer.is_server() or match_finished:
        return

    # O cliente só pode informar a vitória do próprio peer.
    var sender_id := multiplayer.get_remote_sender_id()
    if sender_id == 0 or sender_id != peer_id:
        return

    _finish_match(peer_id)


func _finish_match(peer_id: int) -> void:
    if not multiplayer.is_server() or match_finished:
        return

    var jogador := players.get_node_or_null(str(peer_id))
    if jogador == null:
        return

    var winner_number := int(jogador.get_meta("player_number", 0))
    if winner_number != 1 and winner_number != 2:
        return

    match_finished = true
    if winner_number == 1:
        wins_player_1 += 1
    else:
        wins_player_2 += 1

    announce_winner.rpc(winner_number, wins_player_1, wins_player_2)
    # Aguarda um pouco para que todos vejam quem venceu e depois inicia outra corrida.
    await get_tree().create_timer(2.5).timeout
    _start_new_round()


@rpc("authority", "call_local", "reliable")
func announce_winner(winner_id: int, score_1: int, score_2: int) -> void:
    wins_player_1 = score_1
    wins_player_2 = score_2
    status_label.text = "Jogador %d venceu! A próxima corrida vai começar..." % winner_id
    winner_label.text = "Último vencedor: Jogador %d" % winner_id
    _update_score_label()

    for jogador in players.get_children():
        jogador.set_physics_process(false)


func _update_score_label() -> void:
    score_label.text = "PLACAR DE VITÓRIAS\nJogador 1: %d     |     Jogador 2: %d" % [
        wins_player_1, wins_player_2
    ]


func _start_new_round() -> void:
    if not multiplayer.is_server():
        return

    match_finished = false
    restart_round.rpc()
    status_label.text = "Nova corrida! Chegue primeiro ao portal."


@rpc("authority", "call_local", "reliable")
func restart_round() -> void:
    match_finished = false
    for jogador in players.get_children():
        var peer_id := int(jogador.name) if jogador.name.is_valid_int() else 0
        if peer_id == 1:
            jogador.global_position = spawn_host.global_position
        elif peer_id > 1:
            jogador.global_position = spawn_client.global_position
        jogador.velocity = Vector2.ZERO
        jogador.set_physics_process(true)
    _update_score_label()
