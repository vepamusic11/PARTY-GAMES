class_name Sfx
extends Node
## Efectos de sonido sintetizados por código: sin archivos de audio que
## licenciar, importar o que agranden la app. Lo usan la TV y el celular.
##
## Concepto: *síntesis*. Un sonido digital es una lista de números (muestras)
## que dicen cuánto se mueve el parlante en cada instante. Una onda cuadrada
## a 880 Hz suena a "bip" de videojuego; si la frecuencia sube de 660 a 990 Hz
## mientras suena, se oye como una confirmación ("¡bling!"). Cada efecto de
## RECIPES es una secuencia de notas así, con un volumen que arranca rápido y
## se apaga de a poco (*envolvente*), para que no haga "clic".
##
## Uso: agregar UN nodo Sfx a la pantalla raíz (HostMain / ControllerMain) y
## llamar desde cualquier lado `Sfx.play("point")`. Sin nodo (tests) o con
## `Sfx.muted`, no hace nada.

const MIX_RATE := 22050
const VOICES := 8   ## Sonidos simultáneos máximos; el más viejo se corta.

## Nota: [frecuencia inicial Hz, final Hz, duración s, onda, volumen 0..1].
## Onda: "sq" cuadrada, "tri" triangular, "sin" senoidal, "noise" ruido.
const RECIPES := {
	"tick": [[1200, 1200, 0.03, "sq", 0.18]],                                  # Mover el foco.
	"select": [[660, 990, 0.08, "sq", 0.3]],                                   # Confirmar.
	"back": [[520, 300, 0.1, "sq", 0.25]],                                     # Volver / salir.
	"join": [[523, 523, 0.07, "tri", 0.5], [659, 659, 0.07, "tri", 0.5], [784, 784, 0.12, "tri", 0.5]],
	"count": [[880, 880, 0.12, "sq", 0.3]],                                    # 3, 2, 1…
	"go": [[1320, 1320, 0.35, "sq", 0.32]],                                    # ¡YA!
	"point": [[1040, 1560, 0.09, "tri", 0.55]],                                # Estrella, punto.
	"pop": [[300, 900, 0.08, "sin", 0.6]],                                     # Aparece un puntaje.
	"stop": [[700, 1400, 0.07, "sq", 0.3]],                                    # Frenar el reloj.
	"tap": [[900, 900, 0.025, "sq", 0.2]],                                     # Toque en el celular.
	"pong": [[440, 440, 0.05, "sq", 0.3]],                                     # Rebote de paleta.
	"hit": [[0, 0, 0.16, "noise", 0.45], [160, 60, 0.2, "sin", 0.6]],          # Golpe, eliminado.
	"whoosh": [[0, 0, 0.22, "noise", 0.22]],                                   # Transición, pausa.
	"lose": [[440, 220, 0.35, "tri", 0.45]],
	"win": [[523, 523, 0.08, "sq", 0.28], [659, 659, 0.08, "sq", 0.28], [784, 784, 0.08, "sq", 0.28], [1047, 1047, 0.3, "sq", 0.3]],
	"fanfare": [[392, 392, 0.12, "sq", 0.28], [523, 523, 0.12, "sq", 0.28], [659, 659, 0.12, "sq", 0.28],
		[784, 784, 0.2, "sq", 0.3], [659, 659, 0.1, "sq", 0.28], [784, 784, 0.5, "sq", 0.32]],
	# Memoria de colores: una nota por símbolo, como el juguete Simón (sol, mi, do, sol grave).
	"memo_star": [[784, 784, 0.3, "tri", 0.55]],
	"memo_heart": [[659, 659, 0.3, "tri", 0.55]],
	"memo_diamond": [[523, 523, 0.3, "tri", 0.55]],
	"memo_circle": [[392, 392, 0.3, "tri", 0.6]],
	# Efectos de los juegos (ADR 0011). Una nota en 0 Hz senoidal es silencio.
	"time_up": [[1900, 2100, 0.1, "sin", 0.45], [0, 0, 0.05, "sin", 0.0], [2100, 1750, 0.32, "sin", 0.45]],  # Silbato de "¡Tiempo!".
	"thud": [[0, 0, 0.04, "noise", 0.16], [150, 60, 0.09, "sin", 0.4]],        # Bloque que cae al piso.
	"splash": [[0, 0, 0.3, "noise", 0.3], [320, 110, 0.14, "sin", 0.3]],       # Chapuzón.
	"warn": [[700, 700, 0.07, "sq", 0.22]],                                    # Aviso: algo está por pasar.
	"power": [[520, 1040, 0.08, "tri", 0.5], [1040, 1560, 0.1, "tri", 0.5]],   # Agarrar un power-up.
}

static var muted := false
static var _instance: Sfx

var _streams: Dictionary = {}              # nombre -> AudioStream (receta o archivo)
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	for sound_name: String in RECIPES:
		_streams[sound_name] = synth(RECIPES[sound_name])
	_streams.merge(SfxFiles.load_streams(), true)  # Grabados CC0 (ADR 0015).
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = AudioMix.sfx_bus()
		add_child(p)
		_players.append(p)


## Reproduce un efecto. Nombres desconocidos se ignoran (nunca rompe el juego).
## pitch permite variar un mismo sonido (ej. puntajes que suben de tono).
static func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted or _instance == null or not _instance.is_inside_tree():
		return
	_instance._play(sound_name, volume_db, pitch)


## Preferencias de sonido y vibración (sección [audio] del archivo dado).
static func load_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		muted = bool(cfg.get_value("audio", "muted", false))
		Haptics.enabled = bool(cfg.get_value("audio", "vibration", true))


static func save_prefs(path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # Conserva el resto de las secciones (ej. el apodo).
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "vibration", Haptics.enabled)
	cfg.save(path)


static func has_sound(sound_name: String) -> bool:
	return RECIPES.has(sound_name)


func _play(sound_name: String, volume_db: float, pitch: float) -> void:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.5, 2.0)
	p.play()
	Music.on_sfx(sound_name)  # Los efectos importantes bajan la música un instante.


## Convierte una receta en audio PCM de 16 bits mono. Pública y estática
## para poder testearla.
static func synth(notes: Array) -> AudioStreamWAV:
	var total := 0
	for n: Array in notes:
		total += int(float(n[2]) * MIX_RATE)
	var data := PackedByteArray()
	data.resize(total * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1  # Ruido reproducible: el mismo efecto suena siempre igual.
	var offset := 0
	for n: Array in notes:
		var count := int(float(n[2]) * MIX_RATE)
		var attack := 0.005 * MIX_RATE
		var phase := 0.0
		for i in count:
			var t := float(i) / count
			phase += lerpf(float(n[0]), float(n[1]), t) / MIX_RATE
			var cycle := fposmod(phase, 1.0)
			var s := 0.0
			match str(n[3]):
				"sq": s = 0.6 if cycle < 0.5 else -0.6
				"tri": s = 1.0 - 4.0 * absf(cycle - 0.5)
				"sin": s = sin(TAU * phase)
				_: s = rng.randf_range(-1.0, 1.0)
			# Envolvente: ataque de 5 ms y caída suave hasta el final de la nota.
			var env := minf(1.0, i / attack) * pow(1.0 - t, 1.6)
			data.encode_s16(offset, int(clampf(s * env * float(n[4]), -1.0, 1.0) * 32767.0))
			offset += 2
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
