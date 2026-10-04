class_name Jingles
extends RefCounted
## Logos sonoros de la marca, compuestos para este juego y sintetizados por
## código (ADR 0015): nadie más los tiene, a diferencia de un jingle de banco.
##   studio -> IO-GAMES, en la presentación: dos notas "I-O" que suben una
##             quinta y abren un acorde brillante con destellos (Mi mayor).
##   party  -> PARTY-GAME, al llegar al lobby: "PAR-TY-GA-ME" saltarín en
##             Do mayor con bajo, bombo y platillo, y un final sostenido.
##
## Concepto: *partitura*. Cada nota es [pulso de inicio, duración en pulsos,
## nota MIDI, onda, volumen, nota MIDI final opcional (glissando)]. MIDI 60 =
## Do central; +12 = una octava arriba. Varias notas pueden sonar a la vez
## (a diferencia de Sfx, que es una nota tras otra): se suman en un buffer.
##
## Se sintetiza una sola vez, en un hilo aparte, y Music guarda el resultado:
## ~1,8 s de audio a 22 050 Hz tardan ~70–100 ms en una PC.

const MIX_RATE := 22050
const TAIL := 0.25          ## Segundos extra al final para que el acorde se apague.
const ATTACK := 0.004       ## Ataque de cada nota (evita el "clic").
const RELEASE := 0.03       ## Fundido al final de cada nota.

const SCORES := {
	"studio": {
		"bpm": 120,
		"notes": [
			# "I-O": Mi5 -> Si5 con pulso fino (timbre de videojuego nuevo).
			[0.0, 0.45, 76, "pulse", 0.30], [0.5, 0.45, 83, "pulse", 0.30],
			# Golpe grave con glissando hacia abajo (bombo) y bajo sostenido.
			[1.0, 0.35, 45, "sin", 0.45, 28], [1.0, 2.0, 40, "tri", 0.30],
			# Acorde de Mi mayor con novena: brillo "neón".
			[1.0, 2.0, 64, "tri", 0.12], [1.0, 2.0, 68, "tri", 0.12],
			[1.0, 2.0, 71, "tri", 0.12], [1.0, 2.0, 78, "tri", 0.10],
			# Destellos que suben.
			[1.0, 0.3, 88, "tri", 0.12], [1.125, 0.3, 92, "tri", 0.11],
			[1.25, 0.3, 95, "tri", 0.10], [1.375, 0.6, 100, "tri", 0.09],
		],
	},
	"party": {
		"bpm": 150,
		"notes": [
			# Melodía "PAR-TY-GA-ME" (cuadrada, juguete).
			[0.0, 0.45, 72, "sq", 0.26], [0.5, 0.45, 76, "sq", 0.26],
			[1.0, 0.7, 79, "sq", 0.26], [1.75, 0.22, 76, "sq", 0.24],
			[2.0, 0.45, 79, "sq", 0.26], [2.5, 1.5, 84, "sq", 0.28],
			# Armonía del final: Do mayor.
			[2.5, 1.5, 76, "tri", 0.18], [2.5, 1.5, 79, "tri", 0.18],
			# Bajo I-V-V-I.
			[0.0, 0.45, 48, "tri", 0.45], [1.0, 0.45, 43, "tri", 0.45],
			[2.0, 0.45, 43, "tri", 0.45], [2.5, 1.5, 48, "tri", 0.45],
			# Bombo, redoblante y platillo.
			[0.0, 0.2, 50, "sin", 0.5, 30], [2.5, 0.25, 50, "sin", 0.55, 28],
			[1.0, 0.12, 0, "noise", 0.18], [2.0, 0.12, 0, "noise", 0.18],
			[2.5, 1.0, 0, "noise", 0.08],
		],
	},
}


static func has_jingle(jingle_name: String) -> bool:
	return SCORES.has(jingle_name)


## Duración en segundos (incluida la cola), sin sintetizar.
static func duration(jingle_name: String) -> float:
	var score: Dictionary = SCORES.get(jingle_name, {})
	if score.is_empty():
		return 0.0
	var beat := 60.0 / float(score.bpm)
	var end := 0.0
	for n: Array in score.notes:
		end = maxf(end, (float(n[0]) + float(n[1])) * beat)
	return end + TAIL


## Sintetiza el jingle en PCM de 16 bits mono. Nombre desconocido -> null.
static func render(jingle_name: String) -> AudioStreamWAV:
	var score: Dictionary = SCORES.get(jingle_name, {})
	if score.is_empty():
		return null
	var beat := 60.0 / float(score.bpm)
	var mix := PackedFloat32Array()
	mix.resize(int(duration(jingle_name) * MIX_RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7  # Ruido reproducible: el jingle suena siempre igual.
	for n: Array in score.notes:
		_add_note(mix, n, beat, rng)
	# Límite suave (tanh): si varias voces se suman de más, redondea en vez
	# de recortar; por debajo de ~0,5 casi no cambia el sonido.
	var data := PackedByteArray()
	data.resize(mix.size() * 2)
	for i in mix.size():
		data.encode_s16(i * 2, int(tanh(mix[i]) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream


static func _add_note(mix: PackedFloat32Array, n: Array, beat: float, rng: RandomNumberGenerator) -> void:
	var start := int(float(n[0]) * beat * MIX_RATE)
	var count := mini(int(float(n[1]) * beat * MIX_RATE), mix.size() - start)
	if count <= 0:
		return
	var wave := str(n[3])
	var vol := float(n[4])
	var f0 := _midi_hz(float(n[2]))
	var f1 := _midi_hz(float(n[5])) if n.size() > 5 else f0
	var attack := ATTACK * MIX_RATE
	var release := RELEASE * MIX_RATE
	# Caída exponencial: notas cortas se apagan rápido, las largas cantan.
	var tau := maxf(0.08, float(n[1]) * beat * 0.7) * MIX_RATE
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += lerpf(f0, f1, t) / MIX_RATE
		var cycle := fposmod(phase, 1.0)
		var s := 0.0
		match wave:
			"sq": s = 0.6 if cycle < 0.5 else -0.6
			"pulse": s = 0.6 if cycle < 0.25 else -0.6
			"tri": s = 1.0 - 4.0 * absf(cycle - 0.5)
			"sin": s = sin(TAU * phase)
			_: s = rng.randf_range(-1.0, 1.0)
		var env := minf(1.0, i / attack) * minf(1.0, (count - i) / release) * exp(-i / tau)
		mix[start + i] += s * env * vol


static func _midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)
