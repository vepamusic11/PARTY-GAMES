class_name MusicGen
extends RefCounted
## Compositor y sintetizador de música propia (ADR 0017). Arma bucles de
## 16 compases por estilo y pantalla —batería, bajo, acordes, colchón,
## melodía y arpegio— a partir de una *receta* y una *semilla*, y los
## sintetiza en un AudioStreamWAV estéreo que se repite sin cortes.
## Es música 100 % nuestra: no hay archivo que licenciar ni que pese en el APK.
##
## Conceptos (para quien no hizo música):
## - *Paso*: la grilla es de semicorcheas; un compás de 4/4 tiene 16 pasos y
##   un pulso ("negra") tiene 4. A 120 BPM un pulso dura 0,5 s.
## - *Progresión*: los acordes que se suceden, uno por compás, en grados de
##   la tonalidad ("I V vi IV" en Do mayor = Do, Sol, Lam, Fa). Así una
##   receta sirve en cualquier tonalidad.
## - *Motivo*: una idea melódica de 2 compases (ritmo + forma) que se repite
##   y varía (pregunta, respuesta, cierre): por eso la melodía "se entiende"
##   aunque sea generada. Las notas de los tiempos fuertes caen en notas del
##   acorde; las de paso, en la escala.
## - *Bucle sin costura*: lo que suena pasado el final (colas de notas, eco,
##   reverberación) se suma al principio, así el último compás empalma con el
##   primero sin clic ni hueco.
## - *Sidechain* ("bombeo"): en Fiesta, colchón, acordes y bajo bajan un
##   instante con cada bombo; es el "respira" típico del pop electrónico.
##
## Semilla: misma receta + misma semilla = mismas muestras, byte a byte (lo
## verifican los tests). `seed_offset` da variaciones de la misma receta.
##
## Costo: una pista de 16 compases (~30 s, 22 050 Hz estéreo) tarda ~1–2 s
## en una PC. Music la pide en un hilo de WorkerThreadPool, una por vez, y la
## guarda en memoria (~2,7 MB): nunca se sintetiza dentro de un cuadro.

## Versión del sintetizador: subirla al cambiar el código que compone o
## sintetiza (no las recetas: esas ya entran en la firma). Invalida las
## pistas guardadas en disco (MusicCache).
const GEN_VERSION := 1
const MIX_RATE := 22050
const BARS := 16
const TARGET_RMS_DB := -16.0   ## Misma sonoridad que los .ogg (prepare_audio.py).
const PEAK_MAX := 0.85         ## Techo del limitador (~ -1,4 dBFS).
const LIMIT_KNEE := 0.62       ## Desde acá el limitador redondea los picos.
const TABLE_SIZE := 2048       ## Muestras de un ciclo de las tablas de onda.

const MAJOR := [0, 2, 4, 5, 7, 9, 11]
const MINOR := [0, 2, 3, 5, 7, 8, 10]

## Grado -> [semitonos desde la tónica, intervalos del acorde].
const CHORDS := {
	"I": [0, [0, 4, 7]], "Imaj7": [0, [0, 4, 7, 11]], "Iadd9": [0, [0, 4, 7, 14]],
	"ii": [2, [0, 3, 7]], "ii7": [2, [0, 3, 7, 10]], "iii": [4, [0, 3, 7]],
	"IV": [5, [0, 4, 7]], "IVmaj7": [5, [0, 4, 7, 11]], "V": [7, [0, 4, 7]],
	"V7": [7, [0, 4, 7, 10]], "vi": [9, [0, 3, 7]], "vi7": [9, [0, 3, 7, 10]],
	"i": [0, [0, 3, 7]], "i7": [0, [0, 3, 7, 10]], "iv": [5, [0, 3, 7]],
	"III": [3, [0, 4, 7]], "VI": [8, [0, 4, 7]], "VII": [10, [0, 4, 7]],
}

## Baterías: instrumento -> [[pasos del compás], volumen]. `fill` reemplaza
## el último pulso del compás 8 y 16 (marca el fin de la frase).
const KITS := {
	"house_light": {"kick": [[0, 4, 8, 12], 0.85], "clap": [[4, 12], 0.5], "hat_c": [[2, 6, 10, 14], 0.4],
		"shaker": [[1, 3, 5, 7, 9, 11, 13, 15], 0.14], "fill": "snare"},
	"house": {"kick": [[0, 4, 8, 12], 0.95], "clap": [[4, 12], 0.6], "hat_o": [[2, 6, 10, 14], 0.3],
		"hat_c": [[0, 4, 8, 12], 0.16], "shaker": [[1, 3, 5, 7, 9, 11, 13, 15], 0.18], "fill": "snare"},
	"drive": {"kick": [[0, 4, 8, 12], 1.0], "clap": [[4, 12], 0.65], "snare": [[4, 12], 0.35],
		"hat_c": [[0, 1, 3, 4, 5, 7, 8, 9, 11, 12, 13, 15], 0.22], "hat_o": [[2, 6, 10, 14], 0.3],
		"fill": "snare"},
	"half": {"kick": [[0, 7, 10], 0.75], "snare": [[8], 0.5], "clap": [[8], 0.3],
		"hat_c": [[0, 2, 4, 6, 8, 10, 12, 14], 0.26], "shaker": [[3, 7, 11, 15], 0.12], "fill": "snare"},
	"bounce": {"kick": [[0, 6, 8], 0.85], "clap": [[4, 12], 0.55], "hat_c": [[0, 2, 4, 6, 8, 10, 12, 14], 0.3],
		"shaker": [[3, 7, 11, 15], 0.14], "fill": "snare"},
	"anthem": {"kick": [[0, 4, 8, 12], 1.0], "clap": [[4, 12], 0.6], "snare": [[4, 12], 0.4],
		"hat_o": [[2, 6, 10, 14], 0.32], "shaker": [[1, 3, 5, 7, 9, 11, 13, 15], 0.16], "crash": [[0], 0.4],
		"fill": "snare"},
	# Latino. Güiro: raspado largo en el pulso y dos cortos después (chk-chiki).
	"cumbia": {"kick": [[0, 8], 0.7], "guiro_l": [[0, 4, 8, 12], 0.36], "guiro_s": [[2, 3, 6, 7, 10, 11, 14, 15], 0.26],
		"conga_slap": [[4, 12], 0.42], "conga_open": [[6, 7, 14, 15], 0.4], "conga_mute": [[0, 2, 8, 10], 0.2],
		"fill": "timbale"},
	"cumbia_light": {"kick": [[0], 0.55], "guiro_l": [[0, 4, 8, 12], 0.3], "guiro_s": [[2, 3, 6, 7, 10, 11, 14, 15], 0.2],
		"conga_open": [[6, 14], 0.32], "conga_mute": [[0, 8], 0.18], "fill": "conga_hi"},
	"cumbia_full": {"kick": [[0, 8], 0.75], "guiro_l": [[0, 4, 8, 12], 0.36], "guiro_s": [[2, 3, 6, 7, 10, 11, 14, 15], 0.26],
		"conga_slap": [[4, 12], 0.42], "conga_open": [[6, 7, 14, 15], 0.4], "cowbell": [[0, 4, 8, 12], 0.24],
		"crash": [[0], 0.3], "fill": "timbale"},
	"dembow": {"kick": [[0, 4, 8, 12], 0.8], "rim": [[3, 6, 11, 14], 0.6], "snare": [[3, 6, 11, 14], 0.3],
		"hat_c": [[0, 2, 4, 6, 8, 10, 12, 14], 0.2], "shaker": [[1, 3, 5, 7, 9, 11, 13, 15], 0.14],
		"conga_open": [[7, 15], 0.26], "fill": "timbale"},
	"tropical": {"kick": [[0, 8], 0.5], "shaker": [[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], 0.14],
		"clave": [[0, 3, 6, 10, 12], 0.3], "conga_open": [[6, 14], 0.3], "conga_mute": [[4, 12], 0.18],
		"fill": "conga_hi"},
}

## Ajuste fino de volumen por instrumento de percusión (mezcla pareja entre
## graves y agudos: en una TV el bombo "come" todo si va al mismo nivel).
const DRUM_TRIM := {"kick": 0.72, "hat_c": 1.4, "hat_o": 1.3, "shaker": 1.6, "guiro_l": 1.7, "guiro_s": 1.7,
	"conga_slap": 0.8, "timbale": 0.75, "cowbell": 1.2}

## Bajo: [paso, intervalo (0 tónica del acorde, 7 quinta, 12 octava), largo en pasos].
const BASS := {
	"offbeat": [[2, 0, 1.6], [6, 0, 1.6], [10, 0, 1.6], [14, 0, 1.6]],
	"octave": [[0, 0, 1.6], [2, 12, 1.4], [4, 0, 1.6], [6, 12, 1.4], [8, 0, 1.6], [10, 12, 1.4], [12, 0, 1.6], [14, 12, 1.4]],
	"pop": [[0, 0, 2.6], [3, 0, 1.0], [6, 0, 1.8], [8, 0, 2.6], [11, 7, 1.0], [14, 0, 1.8]],
	"walk": [[0, 0, 3.6], [8, 7, 3.6]],
	"cumbia": [[0, 0, 3.4], [4, 7, 1.8], [6, 7, 1.8], [8, 0, 3.4], [12, 7, 1.8], [14, 7, 1.8]],
	"dembow": [[0, 0, 2.6], [3, 0, 2.6], [6, 0, 1.6], [8, 0, 2.6], [11, 7, 2.6], [14, 0, 1.6]],
	"tropical": [[0, 0, 2.6], [3, 7, 1.0], [4, 7, 3.4], [8, 0, 2.6], [11, 7, 1.0], [12, 7, 3.4]],
}

## Acompañamiento de acordes: [pasos del compás], largo en pasos.
const COMP := {
	"offbeat": [[2, 6, 10, 14], 1.3],   # "Chuk" en el contratiempo (cumbia, reggae).
	"house": [[0, 3, 6, 10, 12], 1.8],  # Piano de house sincopado.
	"pop8": [[0, 3, 6, 8, 11, 14], 1.8],
	"half": [[0, 8], 7.0],
}

## Células rítmicas de la melodía (un pulso = 4 pasos; "x" = nota).
const CELLS := {
	"pop": ["x...", "x.x.", "x..x", "..x.", "x.xx", ".xx.", "x...", "x.x."],
	"latin": ["x.x.", "x..x", ".xx.", "x.xx", "..x.", "x...", "xx.x"],
	"calm": ["x...", "x...", "..x.", "x.x.", "....", "x..."],
}

## Recetas: estilo -> pista -> parámetros. Partes (`parts`):
##   drums/bass/comp/pad/lead/arp con su instrumento y desde qué compás entran.
const RECIPES := {
	"fiesta": {
		"lobby": {"bpm": 118, "root": 62, "mode": "major", "prog": ["I", "V", "vi", "IV"], "seed": 101, "pump": true,
			"cells": "pop", "parts": [
				{"part": "drums", "kit": "house_light"}, {"part": "bass", "pattern": "offbeat", "inst": "bass_synth"},
				{"part": "comp", "pattern": "house", "inst": "keys", "gain": 0.8}, {"part": "pad", "inst": "pad"},
				{"part": "lead", "inst": "bell", "density": 0.5, "from": 0},
				{"part": "arp", "inst": "pluck", "from": 8, "rate": 2}]},
		"game_calm": {"bpm": 104, "root": 65, "mode": "major", "prog": ["Imaj7", "vi7", "ii7", "V"], "seed": 202,
			"cells": "calm", "parts": [
				{"part": "drums", "kit": "half"}, {"part": "bass", "pattern": "walk", "inst": "bass_round"},
				{"part": "comp", "pattern": "half", "inst": "keys", "gain": 0.9}, {"part": "pad", "inst": "pad", "gain": 0.7},
				{"part": "lead", "inst": "pluck", "density": 0.35, "from": 4},
				{"part": "arp", "inst": "bell", "from": 8, "rate": 4, "gain": 0.7}]},
		"game_play": {"bpm": 124, "root": 60, "mode": "major", "prog": ["vi", "IV", "I", "V"], "seed": 303, "pump": true,
			"cells": "pop", "parts": [
				{"part": "drums", "kit": "house"}, {"part": "bass", "pattern": "octave", "inst": "bass_synth"},
				{"part": "comp", "pattern": "pop8", "inst": "keys", "gain": 0.8}, {"part": "pad", "inst": "pad"},
				{"part": "lead", "inst": "square", "density": 0.55, "from": 0},
				{"part": "arp", "inst": "pluck", "from": 8, "rate": 2}]},
		"game_action": {"bpm": 132, "root": 64, "mode": "major", "prog": ["IV", "V", "iii", "vi"], "seed": 404, "pump": true,
			"cells": "pop", "parts": [
				{"part": "drums", "kit": "drive"}, {"part": "bass", "pattern": "octave", "inst": "bass_synth"},
				{"part": "comp", "pattern": "pop8", "inst": "brass", "gain": 0.7}, {"part": "pad", "inst": "pad"},
				{"part": "lead", "inst": "square", "density": 0.7, "from": 0},
				{"part": "arp", "inst": "pluck", "from": 0, "rate": 1, "gain": 0.8}]},
		"summary": {"bpm": 110, "root": 67, "mode": "major", "prog": ["IVmaj7", "V", "iii", "vi"], "seed": 505, "pump": true,
			"cells": "pop", "parts": [
				{"part": "drums", "kit": "bounce"}, {"part": "bass", "pattern": "pop", "inst": "bass_synth"},
				{"part": "comp", "pattern": "house", "inst": "keys"}, {"part": "pad", "inst": "pad", "gain": 0.8},
				{"part": "lead", "inst": "bell", "density": 0.45, "from": 0}]},
		"podium": {"bpm": 120, "root": 65, "mode": "major", "prog": ["I", "V", "vi", "IV"], "seed": 606, "pump": true,
			"cells": "pop", "parts": [
				{"part": "drums", "kit": "anthem"}, {"part": "bass", "pattern": "octave", "inst": "bass_synth"},
				{"part": "comp", "pattern": "pop8", "inst": "brass", "gain": 0.8}, {"part": "pad", "inst": "pad"},
				{"part": "lead", "inst": "square", "density": 0.6, "from": 0},
				{"part": "lead", "inst": "bell", "density": 0.6, "from": 8, "octave": 12, "gain": 0.5, "echo": true},
				{"part": "arp", "inst": "pluck", "from": 8, "rate": 2}]},
	},
	"latino": {
		"lobby": {"bpm": 96, "root": 57, "mode": "minor", "prog": ["i", "VII", "VI", "V7"], "seed": 111,
			"cells": "latin", "parts": [
				{"part": "drums", "kit": "cumbia"}, {"part": "bass", "pattern": "cumbia", "inst": "bass_round"},
				{"part": "comp", "pattern": "offbeat", "inst": "keys"},
				{"part": "lead", "inst": "accordion", "density": 0.6, "from": 0},
				{"part": "arp", "inst": "marimba", "from": 8, "rate": 2, "gain": 0.6}]},
		"game_calm": {"bpm": 92, "root": 62, "mode": "major", "prog": ["I", "vi", "ii", "V7"], "seed": 222,
			"cells": "calm", "parts": [
				{"part": "drums", "kit": "tropical"}, {"part": "bass", "pattern": "walk", "inst": "bass_round"},
				{"part": "comp", "pattern": "half", "inst": "keys", "gain": 0.7},
				{"part": "lead", "inst": "pluck", "density": 0.55, "from": 0},
				{"part": "arp", "inst": "marimba", "from": 0, "rate": 2, "gain": 0.7}]},
		"game_play": {"bpm": 100, "root": 62, "mode": "minor", "prog": ["i", "iv", "V7", "i"], "seed": 333,
			"cells": "latin", "parts": [
				{"part": "drums", "kit": "cumbia"}, {"part": "bass", "pattern": "cumbia", "inst": "bass_round"},
				{"part": "comp", "pattern": "offbeat", "inst": "keys"},
				{"part": "lead", "inst": "accordion", "density": 0.65, "from": 0},
				{"part": "arp", "inst": "marimba", "from": 8, "rate": 2, "gain": 0.6}]},
		"game_action": {"bpm": 96, "root": 57, "mode": "minor", "prog": ["i", "VI", "III", "VII"], "seed": 444,
			"cells": "latin", "parts": [
				{"part": "drums", "kit": "dembow"}, {"part": "bass", "pattern": "dembow", "inst": "bass_round", "gain": 0.7},
				{"part": "pad", "inst": "pad", "gain": 0.6},
				{"part": "arp", "inst": "marimba", "from": 0, "rate": 2, "gain": 0.8},
				{"part": "lead", "inst": "pluck", "density": 0.6, "from": 4}]},
		"summary": {"bpm": 100, "root": 65, "mode": "major", "prog": ["I", "iii", "IV", "V7"], "seed": 555,
			"cells": "latin", "parts": [
				{"part": "drums", "kit": "tropical"}, {"part": "bass", "pattern": "tropical", "inst": "bass_round"},
				{"part": "comp", "pattern": "offbeat", "inst": "pluck", "gain": 0.8},
				{"part": "lead", "inst": "marimba", "density": 0.5, "from": 0}]},
		"podium": {"bpm": 104, "root": 67, "mode": "major", "prog": ["I", "IV", "V7", "I"], "seed": 666,
			"cells": "latin", "parts": [
				{"part": "drums", "kit": "cumbia_full"}, {"part": "bass", "pattern": "cumbia", "inst": "bass_round"},
				{"part": "comp", "pattern": "offbeat", "inst": "keys"},
				{"part": "comp", "pattern": "house", "inst": "brass", "from": 8, "gain": 0.6},
				{"part": "lead", "inst": "accordion", "density": 0.65, "from": 0}]},
	},
}

## Tablas de onda compartidas entre hilos (se arman una vez, con candado).
static var _tables: Dictionary = {}
static var _tables_lock := Mutex.new()

var _rng := RandomNumberGenerator.new()
var _n := 0                       # Muestras del bucle.
var _step := 0.0                  # Muestras por paso (semicorchea).
var _swing := 0.0
var _l := PackedFloat32Array()
var _r := PackedFloat32Array()
var _pl := PackedFloat32Array()   # Bus con bombeo (sidechain), izquierdo y derecho.
var _pr := PackedFloat32Array()
var _rev := PackedFloat32Array()  # Envío a reverberación (mono).
var _dly := PackedFloat32Array()  # Envío a eco (mono).
var _cache: Dictionary = {}       # "instrumento|nota|largo|variante" -> muestras
var _root := 60
var _scale: Array = MAJOR
var _chords: Array = []           # Un acorde por compás: {"root_pc", "pcs", "intervals"}
## Microsegundos por etapa de la última síntesis (tools/render_music.gd).
var profile: Dictionary = {}
var _synth_usec := 0              # Parte de la composición que va en sintetizar notas.
## Notas de la melodía de la última síntesis: [paso, nota MIDI, largo] (para revisarla).
var lead_log: Array = []


static func has_track(style: String, track: String) -> bool:
	return RECIPES.has(style) and (RECIPES[style] as Dictionary).has(track)


## Compone y sintetiza la pista. `bars` < 1 usa BARS (los tests piden menos
## para ir rápido). Estilo o pista desconocidos -> null.
static func render(style: String, track: String, bars: int = -1, seed_offset: int = 0) -> AudioStreamWAV:
	if not has_track(style, track):
		return null
	var gen := MusicGen.new()
	return gen.render_recipe(RECIPES[style][track], bars, seed_offset)


## Segundos que dura el bucle, sin sintetizar.
static func duration(style: String, track: String, bars: int = -1) -> float:
	if not has_track(style, track):
		return 0.0
	var bpm := float(RECIPES[style][track].bpm)
	return (BARS if bars < 1 else bars) * 4.0 * 60.0 / bpm


# --- Composición ---------------------------------------------------------------------

## Como render(), pero sobre una instancia: deja el tiempo de cada etapa en
## `profile` (lo usa tools/render_music.gd para medir el costo).
func render_recipe(recipe: Dictionary, bars: int = -1, seed_offset: int = 0) -> AudioStreamWAV:
	if bars < 1:
		bars = BARS
	profile.clear()
	var t0 := Time.get_ticks_usec()
	_rng.seed = int(recipe.seed) * 7919 + seed_offset
	_step = 60.0 / float(recipe.bpm) / 4.0 * MIX_RATE
	_swing = float(recipe.get("swing", 0.0))
	_n = int(round(bars * 16 * _step))
	_l = _silence(_n)
	_r = _silence(_n)
	_pl = _silence(_n)
	_pr = _silence(_n)
	_rev = _silence(_n)
	_dly = _silence(_n)
	_root = int(recipe.root)
	_scale = MAJOR if recipe.mode == "major" else MINOR
	var prog: Array = recipe.prog
	_chords.clear()
	for b in bars:
		_chords.append(_chord(str(prog[b % prog.size()])))
	var pump := bool(recipe.get("pump", false))
	var cells: Array = CELLS[recipe.get("cells", "pop")]
	# Batería, bajo, acordes, colchón y arpegio se repiten cada vuelta de la
	# progresión (`period` compases): se sintetizan una vez y se copian. Es
	# lo que hace que una pista tarde ~1 s y no ~3 (ver ADR 0017).
	var period := prog.size() if prog.size() <= bars and bars % prog.size() == 0 else bars
	var groups := {}  # compás de entrada -> partes periódicas
	for part: Dictionary in recipe.parts:
		if str(part.part) == "lead":
			continue
		var from := int(part.get("from", 0))
		from = ceili(float(from) / period) * period
		if from < bars:
			if not groups.has(from):
				groups[from] = []
			groups[from].append(part)
	for from: int in groups:
		_periodic(groups[from], period, bars, from, pump)
	for part: Dictionary in recipe.parts:
		var from := int(part.get("from", 0))
		var gain := float(part.get("gain", 1.0))
		match str(part.part):
			"drums":
				_fills(KITS[part.kit], bars)
			"lead":
				_lead(str(part.inst), bars, from, float(part.get("density", 0.5)), int(part.get("octave", 0)),
					gain, cells, bool(part.get("echo", false)))
	var t1 := Time.get_ticks_usec()
	_effects(float(recipe.bpm))
	var t2 := Time.get_ticks_usec()
	if pump:
		_apply_pump()
	var stream := _master()
	var t3 := Time.get_ticks_usec()
	profile = {"synth": _synth_usec, "compose_mix": t1 - t0, "effects": t2 - t1, "master": t3 - t2, "total": t3 - t0}
	return stream


## Sintetiza `parts` en un tramo de `period` compases (en bucle dentro del
## tramo) y lo repite desde el compás `from` hasta el final.
func _periodic(parts: Array, period: int, bars: int, from: int, pump: bool) -> void:
	var main := [_l, _r, _pl, _pr, _rev, _dly]
	var main_n := _n
	_n = int(round(period * 16 * _step))
	_l = _silence(_n)
	_r = _silence(_n)
	_pl = _silence(_n)
	_pr = _silence(_n)
	_rev = _silence(_n)
	_dly = _silence(_n)
	for part: Dictionary in parts:
		var gain := float(part.get("gain", 1.0))
		match str(part.part):
			"drums":
				_drums(KITS[part.kit], period)
			"bass":
				_bass(BASS[part.pattern], str(part.inst), period, gain, pump)
			"comp":
				_comp(COMP[part.pattern], str(part.inst), period, 0, gain, pump)
			"pad":
				_pad(str(part.inst), period, gain, pump)
			"arp":
				_arp(str(part.inst), period, 0, int(part.get("rate", 2)), gain)
	var seg := [_l, _r, _pl, _pr, _rev, _dly]
	var seg_n := _n
	_l = main[0]
	_r = main[1]
	_pl = main[2]
	_pr = main[3]
	_rev = main[4]
	_dly = main[5]
	_n = main_n
	# Un solo lazo por copia (los PackedFloat32Array se comparten por
	# referencia: escribir en `sl` escribe en el tramo, en `_l` en la pista).
	var sl: PackedFloat32Array = seg[0]
	var sr_: PackedFloat32Array = seg[1]
	var spl: PackedFloat32Array = seg[2]
	var spr: PackedFloat32Array = seg[3]
	var sv: PackedFloat32Array = seg[4]
	var sd: PackedFloat32Array = seg[5]
	for b in range(from, bars, period):
		var j := posmod(_t(b * 16), _n)
		if pump:
			for i in seg_n:
				_l[j] += sl[i]
				_r[j] += sr_[i]
				_pl[j] += spl[i]
				_pr[j] += spr[i]
				_rev[j] += sv[i]
				_dly[j] += sd[i]
				j = j + 1 if j + 1 < _n else 0
		else:
			for i in seg_n:
				_l[j] += sl[i]
				_r[j] += sr_[i]
				_rev[j] += sv[i]
				_dly[j] += sd[i]
				j = j + 1 if j + 1 < _n else 0


## Acorde de un compás: tónica en la zona del bajo y sus notas (clases de altura).
func _chord(degree: String) -> Dictionary:
	var c: Array = CHORDS.get(degree, CHORDS["I"])
	var root_pc := (_root + int(c[0])) % 12
	var pcs: Array[int] = []
	for iv: int in c[1]:
		pcs.append((root_pc + iv) % 12)
	return {"root_pc": root_pc, "pcs": pcs, "intervals": c[1]}


## Escala del acorde: la de la tonalidad, pero si el acorde trae una nota
## fuera de ella (el Sol# de Mi7 en La menor) la reemplaza a la vecina.
func _chord_scale(ch: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for d: int in _scale:
		out.append((_root + d) % 12)
	for pc: int in ch.pcs:
		if out.has(pc):
			continue
		# Primero la vecina de abajo (Sol -> Sol#: sensible de la menor armónica).
		for neighbor: int in [(pc + 11) % 12, (pc + 1) % 12]:
			var k := out.find(neighbor)
			if k != -1 and not (ch.pcs as Array).has(neighbor):
				out[k] = pc
				break
	return out


func _t(step: float) -> int:
	# Swing: las semicorcheas impares se atrasan un poco (más "caminado").
	var s := step
	if _swing > 0.0 and int(step) % 2 == 1:
		s += _swing
	return int(round(s * _step))


## Un tramo de batería (el redoble de fin de frase va aparte, en _fills).
func _drums(kit: Dictionary, bars: int) -> void:
	for b in bars:
		for inst: String in kit:
			if inst == "fill":
				continue
			var pat: Array = kit[inst]
			for st: int in pat[0]:
				if inst == "crash" and b % 4 != 0:
					continue
				var vel := float(pat[1]) * float(DRUM_TRIM.get(inst, 1.0)) * (1.0 + _rng.randf_range(-0.08, 0.08))
				var pan := _drum_pan(inst)
				var rev := 0.12 if inst in ["clap", "snare", "rim", "timbale", "conga_open", "conga_slap", "clave"] else 0.0
				_mix(_hit(inst, _rng.randi() % 3), b * 16 + st, vel, pan, rev, 0.0, false)


## Redoble en el último pulso de cada frase de 8 compases.
func _fills(kit: Dictionary, bars: int) -> void:
	if not kit.has("fill"):
		return
	var fill_inst: String = kit.fill
	for b in range(7, bars, 8):
		for k in 4:
			_mix(_hit(fill_inst, k % 3), b * 16 + 12 + k, 0.25 + 0.12 * k, 0.25 * (k - 1.5), 0.15, 0.0, false)


func _drum_pan(inst: String) -> float:
	match inst:
		"hat_c", "hat_o": return 0.45
		"shaker": return -0.5
		"guiro_l", "guiro_s": return 0.4
		"conga_open", "conga_slap", "conga_mute", "conga_hi": return -0.3
		"cowbell", "clave": return 0.25
		"timbale", "rim": return 0.15
	return 0.0


func _bass(pattern: Array, inst: String, bars: int, gain: float, pump: bool) -> void:
	for b in bars:
		var ch: Dictionary = _chords[b]
		var root := _bass_note(int(ch.root_pc))
		for hit: Array in pattern:
			var iv := int(hit[1])
			var note := root + iv
			if iv == 7 and note > 55:
				note -= 12  # Quinta por abajo si se va de registro.
			_mix(_note(inst, note, float(hit[2])), b * 16 + int(hit[0]), 0.42 * gain, 0.0, 0.0, 0.0, pump)


## Tónica del bajo entre Mi1 y Re#2 (MIDI 40–51): graves que se oyen en una TV.
func _bass_note(pc: int) -> int:
	return 40 + posmod(pc - 4, 12)


func _voicing(ch: Dictionary, center: int) -> Array[int]:
	# Acorde en posición cerrada lo más cerca posible de `center`.
	var best: Array[int] = []
	var best_cost := 1e9
	var ivs: Array = ch.intervals
	for inv in ivs.size():
		var notes: Array[int] = []
		var base := center - 6 + posmod(int(ch.root_pc) - (center - 6), 12)
		for k in ivs.size():
			var idx := (k + inv) % ivs.size()
			var n := base + int(ivs[idx]) + (12 if k + inv >= ivs.size() else 0)
			notes.append(n)
		notes.sort()
		var mid := (notes[0] + notes[notes.size() - 1]) / 2.0
		var cost := absf(mid - center)
		if cost < best_cost:
			best_cost = cost
			best = notes
	return best


func _comp(pattern: Array, inst: String, bars: int, from: int, gain: float, pump: bool) -> void:
	var steps: Array = pattern[0]
	var length := float(pattern[1])
	var per_voice := 0.2 * gain
	for b in range(from, bars):
		var notes := _voicing(_chords[b], 66)
		for st: int in steps:
			var vel := per_voice * (1.0 if st % 4 == 0 else 0.85) * (1.0 + _rng.randf_range(-0.06, 0.06))
			for k in notes.size():
				var pan := -0.6 + 1.2 * k / maxf(1.0, notes.size() - 1.0)
				_mix(_note(inst, notes[k], length), b * 16 + st, vel, pan, 0.2, 0.0, pump)


func _pad(inst: String, bars: int, gain: float, pump: bool) -> void:
	for b in bars:
		var notes := _voicing(_chords[b], 62)
		for k in notes.size():
			var pan := -0.8 + 1.6 * k / maxf(1.0, notes.size() - 1.0)
			_mix(_note(inst, notes[k], 16.0), b * 16, 0.08 * gain, pan, 0.35, 0.0, pump)


func _arp(inst: String, bars: int, from: int, rate: int, gain: float) -> void:
	var up := [0, 1, 2, 3, 2, 1, 0, 1]
	for b in range(from, bars):
		var notes := _voicing(_chords[b], 74)
		var k := 0
		for st in range(0, 16, rate):
			var n := notes[up[k % up.size()] % notes.size()]
			var vel := 0.16 * gain * (1.0 if st % 4 == 0 else 0.75)
			_mix(_note(inst, n, float(rate) * 0.9), b * 16 + st, vel, 0.6 if k % 2 == 0 else -0.6, 0.2, 0.3, false)
			k += 1


## Melodía: motivo de 2 compases que se repite y varía en frases de 8
## compases: A (ancla), A' (el mismo motivo más arriba: "respuesta"), A, y
## cierre con nota larga en la tónica. La segunda frase abre con un motivo
## nuevo (B) y vuelve al A: forma A A' A cierre | B B' A cierre.
## Los saltos del motivo son en grados de la escala del acorde (no en
## semitonos): así nunca "se pega" en la misma nota ni sale de la tonalidad.
func _lead(inst: String, bars: int, from: int, density: float, octave: int, gain: float, cells: Array, echo: bool) -> void:
	var motif_a := _motif(cells, density)
	var motif_b := _motif(cells, density)
	var tonic_pc := _root % 12
	var lo := 67 + octave
	var hi := 86 + octave
	var center := (lo + hi) / 2 - 2
	var lift := [0, 3, 0, 1]                        # Ancla de cada bloque, en grados.
	var prev := center
	for b in range(from - from % 2, bars, 2):
		var phrase_pos := (b / 2) % 4               # 0..3 dentro de la frase de 8 compases.
		var second_half := (b / 8) % 2 == 1
		var motif: Array = motif_b if second_half and phrase_pos < 2 else motif_a
		var closing := phrase_pos == 3
		# Ancla: nota del acorde cerca del centro del registro, subida `lift` grados.
		var first: Dictionary = _chords[mini(b, bars - 1)]
		var pos := _step_scale(_snap(center, first, true, lo, hi), first, int(lift[phrase_pos]), lo, hi)
		for idx in motif.size():
			var ev: Array = motif[idx]
			var st := int(ev[0])
			if closing and st >= 20:
				break  # El cierre deja el final de la frase para una nota larga.
			var bar := b + st / 16
			if bar >= bars or bar < from:
				continue
			var ch: Dictionary = _chords[bar]
			var target := pos if idx == 0 else _step_scale(prev, ch, int(ev[1]), lo, hi)
			var note := _snap(target, ch, st % 4 == 0, lo, hi)
			_lead_note(inst, note, b * 16 + st, float(ev[2]), gain, echo)
			prev = note
		if closing and b + 1 < bars:
			# Nota larga que resuelve en la tónica (o la nota del acorde más cerca).
			var ch_end: Dictionary = _chords[b + 1]
			var pc := tonic_pc if (ch_end.pcs as Array).has(tonic_pc) else int(ch_end.root_pc)
			var end_note := _nearest_pc(prev, pc, lo, hi)
			_lead_note(inst, end_note, b * 16 + 20, 8.0, gain, echo)
			prev = end_note


## Sube o baja `steps` grados en la escala del acorde; si se pasa del
## registro, rebota hacia adentro (no se queda pegada en el borde).
func _step_scale(from: int, ch: Dictionary, steps: int, lo: int, hi: int) -> int:
	var scale := _chord_scale(ch)
	var notes: Array[int] = []
	for n in range(lo, hi + 1):
		if scale.has(n % 12):
			notes.append(n)
	if notes.is_empty():
		return from
	var idx := 0
	var best := 99
	for k in notes.size():
		if absi(notes[k] - from) < best:
			best = absi(notes[k] - from)
			idx = k
	idx += steps
	var last := notes.size() - 1
	if idx < 0:
		idx = mini(-idx, last)
	elif idx > last:
		idx = maxi(0, 2 * last - idx)
	return notes[idx]


func _lead_note(inst: String, note: int, step: int, length: float, gain: float, echo: bool) -> void:
	lead_log.append([step, note, length])
	var vel := 0.4 * gain * (1.0 + _rng.randf_range(-0.07, 0.07))
	_mix(_note(inst, note, length), step, vel, 0.05, 0.22, 0.28 if echo or inst == "bell" else 0.12, false)


## Motivo: lista de [paso (0..31), salto en semitonos aproximado, largo].
func _motif(cells: Array, density: float) -> Array:
	var starts: Array[int] = []
	for beat in 8:
		var cell := str(cells[_rng.randi() % cells.size()])
		if beat == 0:
			cell = "x" + cell.substr(1)            # La frase arranca en el pulso.
		elif beat == 7 or _rng.randf() > density + 0.25:
			cell = "x..." if _rng.randf() < density * 0.5 and beat != 7 else "...."
		for k in 4:
			if cell[k] == "x":
				starts.append(beat * 4 + k)
	var out := []
	var moves := [-2, -1, -1, -1, 1, 1, 1, 2, 2, -3, 3, 0, 4]  # En grados de la escala.
	for i in starts.size():
		var next := starts[i + 1] if i + 1 < starts.size() else 32
		var length := clampf(float(next - starts[i]) - 0.3, 0.8, 4.0)
		out.append([starts[i], int(moves[_rng.randi() % moves.size()]), length])
	return out


## Lleva `target` a una nota válida: del acorde en tiempo fuerte, de la escala
## del acorde en tiempo débil; dentro del registro [lo, hi].
func _snap(target: int, ch: Dictionary, strong: bool, lo: int, hi: int) -> int:
	var allowed: Array = ch.pcs if strong else _chord_scale(ch)
	var best := target
	var best_d := 99
	for d in range(-6, 7):
		var n := target + d
		if n < lo or n > hi:
			continue
		if allowed.has(n % 12) and absi(d) < best_d:
			best_d = absi(d)
			best = n
	return clampi(best, lo, hi)


func _nearest_pc(from: int, pc: int, lo: int, hi: int) -> int:
	var best := from
	var best_d := 99
	for n in range(lo, hi + 1):
		if n % 12 == pc and absi(n - from) < best_d:
			best_d = absi(n - from)
			best = n
	return best


# --- Mezcla ---------------------------------------------------------------------------

## Suma `buf` desde el paso `step` con volumen, paneo (-1..1) y envíos. Lo que
## pasa del final del bucle vuelve al principio (bucle sin costura).
func _mix(buf: PackedFloat32Array, step: float, vel: float, pan: float, rev: float, dly: float, pump: bool) -> void:
	var start := posmod(_t(step), _n)
	var angle := (clampf(pan, -1.0, 1.0) + 1.0) * PI / 4.0
	var gl := vel * cos(angle) * 1.41
	var gr := vel * sin(angle) * 1.41
	var gs := vel * rev
	var gd := vel * dly
	var count := buf.size()
	var i := 0
	var j := start
	# Se escribe directo en los miembros (no en una variable local que los
	# apunte) para no depender de copias de PackedFloat32Array.
	var sends := gs > 0.0 or gd > 0.0
	while i < count:
		var run := mini(count - i, _n - j)
		if pump:
			for k in run:
				var s := buf[i + k]
				_pl[j + k] += s * gl
				_pr[j + k] += s * gr
				if sends:
					_rev[j + k] += s * gs
					_dly[j + k] += s * gd
		elif sends:
			for k in run:
				var s := buf[i + k]
				_l[j + k] += s * gl
				_r[j + k] += s * gr
				_rev[j + k] += s * gs
				_dly[j + k] += s * gd
		else:
			for k in run:
				var s := buf[i + k]
				_l[j + k] += s * gl
				_r[j + k] += s * gr
		i += run
		j = 0


## Bombeo: el bus baja con cada negra (donde está el bombo) y sube en ~0,15 s.
func _apply_pump() -> void:
	var beat := _step * 4.0
	var curve := PackedFloat32Array()
	curve.resize(int(beat) + 2)
	for k in curve.size():
		curve[k] = 1.0 - 0.55 * exp(-k / (0.07 * MIX_RATE))
	for i in _n:
		var g := curve[int(fmod(float(i), beat))]
		_l[i] += _pl[i] * g
		_r[i] += _pr[i] * g


## Eco estéreo (ida y vuelta) a corchea con puntillo y una reverberación
## chica (dos filtros peine y un pasa-todo por canal). Corren a media
## frecuencia de muestreo (sus colas son opacas: no pierden nada y cuestan
## la mitad) y arrancan "cebados" con el final del bucle, así el principio
## ya tiene la cola del final.
func _effects(bpm: float) -> void:
	var half := _n / 2
	var prime := int(0.75 * MIX_RATE)
	# Eco: dos líneas que se pasan la señal (izquierda -> derecha -> izquierda).
	var d := int(60.0 / bpm * 0.75 * MIX_RATE / 2.0)
	var el := _silence(d)
	var er := _silence(d)
	var pe := 0
	var fb := 0.38
	var damp_l := 0.0
	var damp_r := 0.0
	# Reverberación (Schroeder reducida): por canal, dos peines y un pasa-todo
	# de largos distintos, así izquierda y derecha no suenan iguales.
	var n_la := 279
	var n_lb := 316
	var n_lc := 57
	var n_ra := 290
	var n_rb := 330
	var n_rc := 65
	var la := _silence(n_la)
	var lb := _silence(n_lb)
	var lc := _silence(n_lc)
	var ra := _silence(n_ra)
	var rb := _silence(n_rb)
	var rc := _silence(n_rc)
	var pla := 0
	var plb := 0
	var plc := 0
	var pra := 0
	var prb := 0
	var prc := 0
	var fla := 0.0
	var flb := 0.0
	var fra := 0.0
	var frb := 0.0
	var last_l := 0.0
	var last_r := 0.0
	var h := posmod(-prime, half)
	for i in range(-prime, half):
		var i0 := h * 2
		var i1 := i0 + 1
		var x := (_dly[i0] + _dly[i1]) * 0.5
		var v := (_rev[i0] + _rev[i1]) * 0.5
		var yl := el[pe]
		var yr := er[pe]
		damp_l += (yl - damp_l) * 0.7
		damp_r += (yr - damp_r) * 0.7
		el[pe] = x + damp_r * fb
		er[pe] = damp_l * fb
		pe = pe + 1 if pe + 1 < d else 0
		# Izquierda.
		var a1 := la[pla]
		var a2 := lb[plb]
		fla += (a1 - fla) * 0.8
		flb += (a2 - flb) * 0.8
		la[pla] = v + fla * 0.8
		lb[plb] = v + flb * 0.78
		pla = pla + 1 if pla + 1 < n_la else 0
		plb = plb + 1 if plb + 1 < n_lb else 0
		var ya := lc[plc]
		var w := (a1 + a2) * 0.5 + ya * 0.5
		lc[plc] = w
		plc = plc + 1 if plc + 1 < n_lc else 0
		# Derecha.
		var b1 := ra[pra]
		var b2 := rb[prb]
		fra += (b1 - fra) * 0.8
		frb += (b2 - frb) * 0.8
		ra[pra] = v + fra * 0.8
		rb[prb] = v + frb * 0.78
		pra = pra + 1 if pra + 1 < n_ra else 0
		prb = prb + 1 if prb + 1 < n_rb else 0
		var yb := rc[prc]
		var z := (b1 + b2) * 0.5 + yb * 0.5
		rc[prc] = z
		prc = prc + 1 if prc + 1 < n_rc else 0
		var out_l := yl * 0.8 + (ya - w * 0.5) * 0.5
		var out_r := yr * 0.8 + (yb - z * 0.5) * 0.5
		if i >= 0:
			# De vuelta a la frecuencia completa: interpolación lineal.
			_l[i0] += (last_l + out_l) * 0.5
			_r[i0] += (last_r + out_r) * 0.5
			_l[i1] += out_l
			_r[i1] += out_r
		last_l = out_l
		last_r = out_r
		h = h + 1 if h + 1 < half else 0


## Sonoridad pareja (RMS objetivo) y limitador suave para los picos.
func _master() -> AudioStreamWAV:
	var sum := 0.0
	for i in _n:
		sum += _l[i] * _l[i] + _r[i] * _r[i]
	var rms := sqrt(sum / maxf(1.0, 2.0 * _n))
	var gain := db_to_linear(TARGET_RMS_DB) / maxf(rms, 1e-6)
	var room := PEAK_MAX - LIMIT_KNEE
	var scale := gain * 32767.0
	var knee := LIMIT_KNEE * 32767.0
	var data := PackedByteArray()
	data.resize(_n * 4)
	for i in _n:
		var a := _l[i] * scale
		var b := _r[i] * scale
		if absf(a) > knee:
			a = signf(a) * (LIMIT_KNEE + room * tanh((absf(a) / 32767.0 - LIMIT_KNEE) / room)) * 32767.0
		if absf(b) > knee:
			b = signf(b) * (LIMIT_KNEE + room * tanh((absf(b) / 32767.0 - LIMIT_KNEE) / room)) * 32767.0
		data.encode_s16(i * 4, int(a))
		data.encode_s16(i * 4 + 2, int(b))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = true
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = _n
	return stream


# --- Instrumentos -------------------------------------------------------------------------

## Golpe de percusión (se sintetiza una vez por variante y se reusa).
func _hit(inst: String, variant: int) -> PackedFloat32Array:
	var key := "%s|%d" % [inst, variant]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var out := PackedFloat32Array()
	var sr := float(MIX_RATE)
	match inst:
		"kick":
			out.resize(int(0.34 * sr))
			var ph := 0.0
			for i in out.size():
				var t := i / sr
				ph += (48.0 + 110.0 * exp(-t / 0.028)) / sr
				var s := sin(TAU * ph) * exp(-t / 0.2) + rng.randf_range(-1, 1) * exp(-t / 0.0015) * 0.35
				out[i] = tanh(s * 1.6) * 0.9
		"snare", "clap", "rim", "hat_c", "hat_o", "shaker", "crash", "guiro_l", "guiro_s":
			out = _noise_hit(inst, rng)
		"conga_open", "conga_hi", "conga_mute", "conga_slap":
			var f0: float = {"conga_open": 196.0, "conga_hi": 262.0, "conga_mute": 180.0, "conga_slap": 300.0}[inst]
			var tau: float = {"conga_open": 0.17, "conga_hi": 0.13, "conga_mute": 0.035, "conga_slap": 0.05}[inst]
			var slap := 0.6 if inst == "conga_slap" else 0.2
			out.resize(int((tau * 5.0 + 0.02) * sr))
			var ph := 0.0
			var lp := 0.0
			for i in out.size():
				var t := i / sr
				ph += f0 * (1.0 + 0.12 * exp(-t / 0.012)) / sr
				lp += (rng.randf_range(-1, 1) - lp) * 0.35
				out[i] = (sin(TAU * ph) + 0.25 * sin(TAU * ph * 1.5)) * exp(-t / tau) * 0.7 + lp * exp(-t / 0.006) * slap
		"cowbell":
			out.resize(int(0.3 * sr))
			for i in out.size():
				var t := i / sr
				var a := 1.0 if fmod(t * 562.0, 1.0) < 0.5 else -1.0
				var b := 1.0 if fmod(t * 845.0, 1.0) < 0.5 else -1.0
				out[i] = (a + b) * 0.25 * (exp(-t / 0.035) * 0.6 + exp(-t / 0.12) * 0.4)
			_lowpass(out, 3200.0)
		"timbale":
			out.resize(int(0.35 * sr))
			for i in out.size():
				var t := i / sr
				out[i] = (sin(TAU * 420.0 * t) * 0.7 + sin(TAU * 655.0 * t) * 0.35) * exp(-t / 0.09) \
					+ rng.randf_range(-1, 1) * exp(-t / 0.02) * 0.35
		"clave":
			out.resize(int(0.12 * sr))
			for i in out.size():
				var t := i / sr
				out[i] = sin(TAU * 2350.0 * t) * exp(-t / 0.022) * 0.8
	_cache[key] = out
	_synth_usec += Time.get_ticks_usec() - t0
	return out


func _noise_hit(inst: String, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var sr := float(MIX_RATE)
	var length: float = {"snare": 0.22, "clap": 0.25, "rim": 0.08, "hat_c": 0.07, "hat_o": 0.3, "shaker": 0.09,
		"crash": 1.4, "guiro_l": 0.17, "guiro_s": 0.06}[inst]
	var out := PackedFloat32Array()
	out.resize(int(length * sr))
	var lp := 0.0
	var lp2 := 0.0
	for i in out.size():
		var t := i / sr
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.45
		var hp := x - lp               # Pasa-altos: el "tss" de platillos y güiro.
		lp2 += (x - lp2) * 0.12
		var bp := lp - lp2             # Pasa-banda: el cuerpo de la palma.
		var s := 0.0
		match inst:
			"snare":
				s = sin(TAU * 185.0 * t) * exp(-t / 0.045) * 0.55 + (hp * 0.6 + bp * 0.5) * exp(-t / 0.075)
			"clap":
				var e := 0.0
				for k in 3:
					var tk := t - k * 0.011
					if tk >= 0.0:
						e = maxf(e, exp(-tk / 0.004))
				e = maxf(e, exp(-maxf(0.0, t - 0.022) / 0.07) * 0.7 * (1.0 if t > 0.022 else 0.0))
				s = (bp * 1.6 + hp * 0.4) * e
			"rim":
				s = (sin(TAU * 1650.0 * t) * 0.5 + bp * 0.8) * exp(-t / 0.012)
			"hat_c":
				s = hp * exp(-t / 0.016)
			"hat_o":
				s = hp * exp(-t / 0.085) * 0.8
			"crash":
				s = (hp * 0.8 + bp * 0.3) * exp(-t / 0.45) * 0.6
			"shaker":
				s = hp * minf(1.0, t / 0.014) * exp(-t / 0.028) * 0.9
			"guiro_l", "guiro_s":
				# Raspado: pulsos de ruido a ~75 por segundo (los dientes del güiro).
				var teeth := 0.35 + 0.65 * absf(sin(PI * 75.0 * t))
				var env := minf(1.0, t / 0.012) * (1.0 - t / length)
				s = (hp * 0.8 + bp * 0.4) * teeth * env * 0.8
		out[i] = s
	return out


## Nota de un instrumento con altura (cacheada por nota y largo).
func _note(inst: String, midi: int, length_steps: float) -> PackedFloat32Array:
	var key := "%s|%d|%d" % [inst, midi, int(length_steps * 100.0)]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var sr := float(MIX_RATE)
	var f := 440.0 * pow(2.0, (midi - 69) / 12.0)
	var dur := length_steps * _step / sr          # Segundos que se sostiene.
	var out := PackedFloat32Array()
	match inst:
		"bass_synth":
			out = _osc_note("saw", f, dur, 0.004, 0.05, 0.9, [300.0, 1700.0, 0.07], 0.0)
			for i in out.size():
				out[i] = tanh(out[i] * 1.4)
		"bass_round":
			out.resize(int((dur + 0.06) * sr))
			var ph := 0.0
			for i in out.size():
				var t := i / sr
				ph += f / sr
				var env := minf(1.0, t / 0.006) * exp(-t / (dur * 1.6 + 0.12)) * _release(t, dur, 0.05)
				var s := sin(TAU * ph) + 0.38 * sin(2.0 * TAU * ph) + 0.12 * sin(3.0 * TAU * ph)
				out[i] = tanh(s * 1.2) * env * 0.85
		"keys":
			# Piano eléctrico: FM con índice que se apaga (ataque "campanita").
			out = _fm_note(f, dur, 1.0, 1.8, 0.35, 0.9, 0.12)
		"bell":
			out = _fm_note(f, dur, 4.0, 2.0, 0.15, 1.1, 0.3)  # Relación 4: armónica, tipo celesta.
		"marimba":
			out.resize(int((minf(dur, 0.5) + 0.35) * sr))
			for i in out.size():
				var t := i / sr
				var s := sin(TAU * f * t) * exp(-t / 0.28)
				if f * 4.0 < sr * 0.45:
					s += 0.3 * sin(TAU * f * 4.0 * t) * exp(-t / 0.04)
				if f * 10.0 < sr * 0.45:
					s += 0.08 * sin(TAU * f * 9.9 * t) * exp(-t / 0.012)
				out[i] = s * minf(1.0, t / 0.002) * 0.9
		"pluck":
			out = _pluck(f, maxf(dur, 0.25) + 0.25)
		"square":
			out = _osc_note("pulse", f, dur, 0.006, 0.08, 0.75, [2600.0, 1200.0, 0.2], 0.12)
		"brass":
			out = _osc_note("saw", f, dur, 0.02, 0.08, 0.8, [700.0, 2400.0, 0.06], 0.0)
		"pad":
			out = _pad_note(f, dur)
		"accordion":
			out = _osc_note("reed", f, dur, 0.025, 0.06, 0.85, [3400.0, 0.0, 1.0], 0.0, 0.0045)
		_:
			out = _osc_note("pulse", f, dur, 0.005, 0.05, 0.8, [2000.0, 0.0, 1.0], 0.0)
	_cache[key] = out
	_synth_usec += Time.get_ticks_usec() - t0
	return out


func _release(t: float, dur: float, rel: float) -> float:
	return 1.0 if t < dur else maxf(0.0, 1.0 - (t - dur) / rel)


## Oscilador de tabla: ataque, caída a `sustain`, soltado; filtro pasa-bajos
## con envolvente [corte base, cuánto abre, tiempo]; vibrato opcional
## (entra después de 0,15 s); `detune` suma una segunda voz desafinada.
func _osc_note(table_name: String, f: float, dur: float, attack: float, release: float, sustain: float,
		filt: Array, vibrato: float, detune: float = 0.0) -> PackedFloat32Array:
	var sr := float(MIX_RATE)
	var table := _table(table_name, f)
	var out := PackedFloat32Array()
	out.resize(int((dur + release) * sr))
	var ph := 0.0
	var ph2 := 0.37
	var lp := 0.0
	var lp2 := 0.0
	var base := float(filt[0])
	var amount := float(filt[1])
	var ftau := maxf(0.001, float(filt[2]))
	var size := float(TABLE_SIZE)
	for i in out.size():
		var t := i / sr
		var vib := 1.0
		if vibrato > 0.0 and t > 0.15:
			vib = 1.0 + vibrato * 0.06 * sin(TAU * 5.5 * t) * minf(1.0, (t - 0.15) / 0.2)
		ph += f * vib / sr
		ph -= floorf(ph)
		var x := table[int(ph * size) & (TABLE_SIZE - 1)]
		if detune > 0.0:
			ph2 += f * (1.0 + detune) / sr
			ph2 -= floorf(ph2)
			x = (x + table[int(ph2 * size) & (TABLE_SIZE - 1)]) * 0.5
		var fc := base + amount * exp(-t / ftau)
		var a := minf(1.0, TAU * fc / sr)
		lp += (x - lp) * a
		lp2 += (lp - lp2) * a
		var env := minf(1.0, t / attack) * lerpf(sustain, 1.0, exp(-t / 0.12)) * _release(t, dur, release)
		out[i] = lp2 * env
	return out


## FM de dos operadores: portadora f, moduladora f * ratio, índice que cae.
func _fm_note(f: float, dur: float, ratio: float, index: float, index_tau: float, decay: float, release: float) -> PackedFloat32Array:
	var sr := float(MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(int((dur + release) * sr))
	var fm := f * ratio
	if fm * 2.0 > sr * 0.45:
		index *= 0.3  # Notas muy agudas: menos brillo, sin aliasing.
	for i in out.size():
		var t := i / sr
		var mod := sin(TAU * fm * t) * index * exp(-t / index_tau)
		var env := minf(1.0, t / 0.003) * exp(-t / decay) * _release(t, dur, release)
		out[i] = sin(TAU * f * t + mod) * env * 0.8
	return out


## Cuerda pulsada (Karplus-Strong): ruido que recorre un retardo del largo de
## un período y se suaviza en cada vuelta. Suena a guitarra o a "pluck".
##
## Afinación: el lazo tarda N muestras (retardo) + d (pasa-todo fraccional) +
## 0,5 (el promedio de dos muestras) = un período exacto, también en notas
## agudas donde el período tiene pocas muestras.
func _pluck(f: float, seconds: float) -> PackedFloat32Array:
	var sr := float(MIX_RATE)
	var p := sr / f - 0.5
	var n := maxi(2, int(floorf(p - 0.1)))
	var d := p - n
	var c := (1.0 - d) / (1.0 + d)
	var line := PackedFloat32Array()
	line.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f * 100.0)
	var lp := 0.0
	for i in n:
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.55
		line[i] = lp
	var out := PackedFloat32Array()
	out.resize(int(seconds * sr))
	var decay := 0.997 if f < 300.0 else 0.994
	var idx := 0
	var ax := 0.0
	var ay := 0.0
	var prev := 0.0
	var fade := 600.0
	for i in out.size():
		var x := line[idx]
		var ap := c * x + ax - c * ay
		ax = x
		ay = ap
		line[idx] = (ap + prev) * 0.5 * decay
		prev = ap
		out[i] = ap * minf(1.0, float(out.size() - i) / fade)
		idx = idx + 1 if idx + 1 < n else 0
	# Las cuerdas agudas se apagan antes: se iguala la sonoridad del ataque.
	var e := 0.0
	var m := mini(out.size(), int(0.15 * sr))
	for i in m:
		e += out[i] * out[i]
	var gain := 0.35 / maxf(sqrt(e / maxf(1.0, m)), 1e-4)
	for i in out.size():
		out[i] *= gain
	return out


## Colchón: tres sierras apenas desafinadas, filtradas, con ataque lento.
func _pad_note(f: float, dur: float) -> PackedFloat32Array:
	var sr := float(MIX_RATE)
	var table := _table("saw", f * 1.02)
	var out := PackedFloat32Array()
	out.resize(int((dur + 0.25) * sr))
	var ph := [0.0, 0.33, 0.71]
	var det := [1.0, 1.0059, 0.9942]
	var lp := 0.0
	var lp2 := 0.0
	var a := minf(1.0, TAU * 1500.0 / sr)
	var size := float(TABLE_SIZE)
	var p0 := 0.0
	var p1 := 0.33
	var p2 := 0.71
	var s0 := f / sr
	var s1 := f * float(det[1]) / sr
	var s2 := f * float(det[2]) / sr
	for i in out.size():
		var t := i / sr
		p0 += s0
		p1 += s1
		p2 += s2
		p0 -= floorf(p0)
		p1 -= floorf(p1)
		p2 -= floorf(p2)
		var x := (table[int(p0 * size) & (TABLE_SIZE - 1)] + table[int(p1 * size) & (TABLE_SIZE - 1)]
			+ table[int(p2 * size) & (TABLE_SIZE - 1)]) / 3.0
		lp += (x - lp) * a
		lp2 += (lp - lp2) * a
		out[i] = lp2 * minf(1.0, t / 0.12) * _release(t, dur, 0.25)
	return out


## Tabla de un ciclo con armónicos limitados (sin aliasing): menos armónicos
## cuanto más aguda la nota. Se arma una vez por forma y banda.
static func _table(table_name: String, f: float) -> PackedFloat32Array:
	var harmonics := clampi(int(9500.0 / maxf(f, 20.0)), 1, 48)
	for h in [48, 24, 12, 6, 3, 1]:
		if harmonics >= h:
			harmonics = h
			break
	var key := "%s|%d" % [table_name, harmonics]
	_tables_lock.lock()
	if not _tables.has(key):
		var t := PackedFloat32Array()
		t.resize(TABLE_SIZE)
		for k in range(1, harmonics + 1):
			var amp := 0.0
			match table_name:
				"saw": amp = 1.0 / k
				"square": amp = 1.0 / k if k % 2 == 1 else 0.0
				"pulse": amp = absf(sin(PI * k * 0.25)) / k       # Pulso 25 %: más "nasal".
				"reed": amp = 1.0 / pow(k, 0.7) * (1.0 if k % 2 == 1 else 0.55)  # Lengüeta de acordeón.
			if amp == 0.0:
				continue
			for i in TABLE_SIZE:
				t[i] += amp * sin(TAU * k * i / TABLE_SIZE)
		var peak := 0.0
		for i in TABLE_SIZE:
			peak = maxf(peak, absf(t[i]))
		for i in TABLE_SIZE:
			t[i] /= maxf(peak, 1e-6)
		_tables[key] = t
	var out: PackedFloat32Array = _tables[key]
	_tables_lock.unlock()
	return out


static func _silence(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	return out


static func _lowpass(buf: PackedFloat32Array, fc: float) -> void:
	var a := minf(1.0, TAU * fc / MIX_RATE)
	var lp := 0.0
	for i in buf.size():
		lp += (buf[i] - lp) * a
		buf[i] = lp
