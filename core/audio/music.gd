class_name Music
extends Node
## Música de la TV (ADR 0015). Una pista en bucle por pantalla, con fundido
## cruzado entre pantallas, jingles de marca y *ducking*. El celular no tiene
## música: la batería importa y la música ya suena en la TV.
##
## Conceptos:
## - *Fundido cruzado* (crossfade): la pista que se va baja mientras la que
##   llega sube, en FADE segundos. La suma de los dos volúmenes (lineales)
##   nunca pasa de 1: no hay un instante con dos temas fuertes a la vez.
## - *Bucle sin cortes*: los OGG están compuestos como compases enteros y
##   AudioStreamOggVorbis.loop vuelve al principio con precisión de muestra.
## - *Ducking*: cuando suena un efecto importante ("¡YA!", ganar, eliminado)
##   la música baja DUCK_DB un instante para que el efecto se entienda, y
##   vuelve sola. Ejemplo: la cuenta regresiva termina, suena "go" y la
##   música se corre 6 dB durante 0,3 s.
##
## Uso: agregar UN nodo Music a HostMain y llamar desde cualquier lado
## `Music.play("lobby")`, `Music.play(Music.track_for_game(id))` o
## `Music.jingle("studio")`. Sin nodo (tests, celular) no hace nada.
##
## Rendimiento: el decodificado OGG corre en el hilo de audio. Este script
## solo trabaja (_process) mientras hay un fundido o ducking en curso; el
## resto del tiempo está apagado (set_process(false)).

const TRACKS := {
	"lobby": "res://assets/audio/music/lobby.ogg",
	"game_calm": "res://assets/audio/music/game_calm.ogg",
	"game_play": "res://assets/audio/music/game_play.ogg",
	"game_action": "res://assets/audio/music/game_action.ogg",
	"summary": "res://assets/audio/music/summary.ogg",
	"podium": "res://assets/audio/music/podium.ogg",
}

## Juegos agrupados por energía. Un juego que no está acá usa DEFAULT_GAME_TRACK.
##   game_calm   -> precisión y duelo (Reloj exacto, Ping Pong)
##   game_play   -> movido (Arena, Pintar el piso)
##   game_action -> caos y esfuerzo (Esquivar, Empujones, Carrera de toques)
const GAME_TRACKS := {
	"stop_clock": "game_calm",
	"pingpong": "game_calm",
	"arena": "game_play",
	"paint": "game_play",
	"dodge": "game_action",
	"sumo": "game_action",
	"tap_race": "game_action",
}
const DEFAULT_GAME_TRACK := "game_play"

const FADE := 0.8             ## Segundos del fundido cruzado.
const DUCK_DB := -6.0         ## Cuánto baja la música con un efecto importante.
const DUCK_HOLD := 0.3        ## Cuánto se queda abajo.
const DUCK_RELEASE := 0.4     ## Cuánto tarda en volver.
const JINGLE_DUCK_DB := -12.0 ## Si un jingle suena sobre una pista, la pista se corre más.
## Efectos que bajan la música (ver Sfx.play).
const DUCK_SOUNDS := ["go", "win", "fanfare", "hit", "lose"]

static var _instance: Music

## Pista que suena (o que va a sonar tras un jingle). "" = silencio.
var current := ""
var _players: Array[AudioStreamPlayer] = []
var _gains := PackedFloat32Array([0.0, 0.0])     # Volumen lineal de cada reproductor.
var _targets := PackedFloat32Array([0.0, 0.0])
var _active := 0                                  # Reproductor de la pista actual.
var _jingle_player: AudioStreamPlayer
var _jingles: Dictionary = {}                     # nombre -> AudioStreamWAV (cache)
var _jingle_tasks: Dictionary = {}                # nombre -> tarea de WorkerThreadPool
var _rendered: Dictionary = {}                    # Lo que dejan los hilos (con _mutex)
var _mutex := Mutex.new()
var _streams: Dictionary = {}                     # pista -> AudioStream (cache)
var _pending_delay := 0.0                         # La pista arranca cuando termina el jingle.
var _duck_db := 0.0
var _duck_target := 0.0
var _duck_hold := 0.0
var _paused := false


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	for jingle_name: String in _jingle_tasks.keys():
		_take_jingle(jingle_name)  # No liberar el nodo con un hilo escribiendo.
	if _instance == self:
		_instance = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # La pausa no corta los fundidos.
	var bus := AudioMix.music_bus()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = linear_to_db(0.0)
		add_child(p)
		_players.append(p)
	_jingle_player = AudioStreamPlayer.new()
	_jingle_player.bus = bus
	add_child(_jingle_player)
	set_process(false)
	# Los jingles se sintetizan en segundo plano (~70–100 ms cada uno en PC):
	# así el paso de la presentación al lobby no pierde frames.
	for jingle_name: String in Jingles.SCORES:
		_jingle_tasks[jingle_name] = WorkerThreadPool.add_task(_render_jingle.bind(jingle_name))


# --- API estática (no hace nada sin nodo) --------------------------------------

## Pasa a la pista `track` con fundido cruzado. La misma pista no se reinicia.
## Con `intro_jingle`, primero suena el jingle y la pista entra al terminar.
static func play(track: String, intro_jingle: String = "") -> void:
	if _instance != null and _instance.is_inside_tree():
		_instance._play(track, intro_jingle)


## Baja todo con fundido.
static func stop() -> void:
	if _instance != null and _instance.is_inside_tree():
		_instance._play("", "")


## Logo sonoro o golpe musical corto por encima de la pista (que se corre).
static func jingle(jingle_name: String) -> void:
	if _instance != null and _instance.is_inside_tree():
		_instance._jingle(jingle_name)


## Baja la música DUCK_DB durante `hold` segundos y la devuelve sola.
static func duck(db: float = DUCK_DB, hold: float = DUCK_HOLD) -> void:
	if _instance != null and _instance.is_inside_tree():
		_instance._duck(db, hold)


## Lo llama Sfx al reproducir un efecto: los importantes bajan la música.
static func on_sfx(sound_name: String) -> void:
	if sound_name in DUCK_SOUNDS:
		duck()


## Aplica el ajuste "Sonido" de la TV (Sfx.muted): silencia el bus Master y
## pausa la música para no decodificar de gusto.
static func sync_mute() -> void:
	AudioMix.set_muted(Sfx.muted)
	if _instance != null:
		_instance._set_paused(Sfx.muted)


## Pista de un minijuego según su energía.
static func track_for_game(game_id: String) -> String:
	return str(GAME_TRACKS.get(game_id, DEFAULT_GAME_TRACK))


static func instance() -> Music:
	return _instance


# --- Estado (público para los tests) --------------------------------------------

## Volumen lineal actual de cada reproductor de pista.
func gains() -> PackedFloat32Array:
	return _gains


## Ducking actual en dB (0 = sin ducking).
func duck_db() -> float:
	return _duck_db


func is_paused() -> bool:
	return _paused


## Avanza fundidos y ducking `delta` segundos. Lo llama _process; los tests
## lo llaman directo para no depender del reloj.
func advance(delta: float) -> void:
	var busy := false
	if _pending_delay > 0.0:
		_pending_delay -= delta
		busy = true
		if _pending_delay <= 0.0:
			_start_track()
	var step := delta / FADE
	for i in 2:
		if _gains[i] != _targets[i]:
			_gains[i] = move_toward(_gains[i], _targets[i], step)
			busy = true
		if _gains[i] <= 0.0 and _targets[i] <= 0.0 and _players[i].playing:
			_players[i].stop()
	if _duck_hold > 0.0:
		_duck_hold -= delta
		busy = true
	elif _duck_db < 0.0:
		_duck_db = minf(0.0, _duck_db + absf(_duck_target) * delta / DUCK_RELEASE)
		busy = true
	_apply_volumes()
	set_process(busy)


func _process(delta: float) -> void:
	advance(delta)


# --- Interno ----------------------------------------------------------------------

func _play(track: String, intro_jingle: String) -> void:
	if track == current:
		return
	current = track if TRACKS.has(track) else ""
	_pending_delay = 0.0
	# Lo que suena se va con fundido.
	_targets[0] = 0.0
	_targets[1] = 0.0
	if Jingles.has_jingle(intro_jingle):
		_jingle(intro_jingle)
		_pending_delay = maxf(0.01, Jingles.duration(intro_jingle) - 0.2)
	else:
		_start_track()
	set_process(true)


## Arranca `current` en el reproductor libre, desde silencio.
func _start_track() -> void:
	_pending_delay = 0.0
	if current.is_empty():
		return
	var stream := _stream(current)
	if stream == null:
		return
	# Si el anterior todavía se estaba yendo en el otro reproductor, se corta:
	# su volumen ya es bajo y así nunca hay tres pistas.
	_active = 1 - _active
	var p := _players[_active]
	p.stop()
	p.stream = stream
	_gains[_active] = 0.0
	_targets[_active] = 1.0
	_targets[1 - _active] = 0.0
	_apply_volumes()
	p.play()
	p.stream_paused = _paused
	set_process(true)


func _jingle(jingle_name: String) -> void:
	if not Jingles.has_jingle(jingle_name):
		return
	_take_jingle(jingle_name)
	if not _jingles.has(jingle_name):
		_jingles[jingle_name] = Jingles.render(jingle_name)
	_jingle_player.stream = _jingles[jingle_name]
	_jingle_player.play()
	_jingle_player.stream_paused = _paused
	_duck(JINGLE_DUCK_DB, Jingles.duration(jingle_name))


func _duck(db: float, hold: float) -> void:
	_duck_target = minf(db, 0.0)
	_duck_db = minf(_duck_db, _duck_target)
	_duck_hold = maxf(_duck_hold, hold)
	_apply_volumes()
	set_process(true)


func _set_paused(paused: bool) -> void:
	_paused = paused
	for p: AudioStreamPlayer in _players + [_jingle_player]:
		p.stream_paused = paused


func _stream(track: String) -> AudioStream:
	if not _streams.has(track):
		var path: String = TRACKS.get(track, "")
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		_streams[track] = stream
	return _streams[track]


func _apply_volumes() -> void:
	for i in _players.size():
		_players[i].volume_db = linear_to_db(maxf(_gains[i], 0.0001)) + _duck_db


## Corre en un hilo: no toca el árbol, solo sintetiza y guarda.
func _render_jingle(jingle_name: String) -> void:
	var stream := Jingles.render(jingle_name)
	_mutex.lock()
	_rendered[jingle_name] = stream
	_mutex.unlock()


## Espera (si hace falta) la síntesis en segundo plano y la pasa a la cache.
func _take_jingle(jingle_name: String) -> void:
	if not _jingle_tasks.has(jingle_name):
		return
	WorkerThreadPool.wait_for_task_completion(_jingle_tasks[jingle_name])
	_jingle_tasks.erase(jingle_name)
	_mutex.lock()
	if _rendered.has(jingle_name):
		_jingles[jingle_name] = _rendered[jingle_name]
		_rendered.erase(jingle_name)
	_mutex.unlock()
