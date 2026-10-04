class_name MascotAtlas
extends Node
## Caché de mascotas 3D horneadas (ADR 0012): para cada apariencia (color +
## estilo) y tamaño guarda los cuadros (poses) ya renderizados como
## texturas. `PlayerAvatar.draw_mascot` dibuja el cuadro que corresponde y,
## si todavía no está (o no hay render: --headless, tests, horneado fallido),
## dibuja la mascota 2D de siempre. Pantallas y juegos no se enteran.
##
## Concepto: *caché con presupuesto* (LRU). Las texturas ocupan memoria de
## video; en vez de guardar todo para siempre, se guarda lo que se usa y, si
## se pasa del presupuesto (BUDGET_BYTES), se suelta lo que hace más tiempo
## que no se dibuja. Ejemplo: al terminar "Pintar el piso" (mascotas chicas)
## y pasar al podio (grandes), las chicas quedan hasta que haga falta lugar.
##
## Concepto: *horneado perezoso + precalentado*. Un cuadro que se pide y no
## está se encola y se hornea en los cuadros siguientes (mientras tanto se
## dibuja el más parecido que ya esté: la mascota quieta con el mismo ánimo).
## Para que eso casi nunca se vea, el host "precalienta" lo que va a hacer
## falta: las poses de pantalla al sumarse un jugador en el lobby y las del
## juego durante la intro "¿Cómo se juega?" (prewarm_screens, prewarm_game).
##
## Tamaños (TIERS_U): la mascota se hornea a unos pocos tamaños fijos (en u
## de PlayerAvatar) y se dibuja escalada (0,7×–1,08×) al tamaño pedido.
## Ejemplo: los juegos con u = 0,8 usan el de 0,95 (celda de 114×133 px)
## achicado a 0,84; el lobby (u ≈ 1,8) usa el de 2,25 (270×315 px).
## Memoria por pose: 60 KB (0,95) · 141 KB (1,45) · 340 KB (2,25) · 777 KB (3,4).
## Ver docs/PERFORMANCE.md ("Mascotas 3D horneadas").
##
## El trabajo se reparte en cuadros (Mascot3DBaker.Job): un horneado a la
## vez, pocas mascotas armadas por cuadro. Un nodo propio (creado solo, bajo
## la raíz) lo avanza en su _process.
##
## Caché en disco (MascotDiskCache, ADR 0023): cada hoja horneada se guarda
## en `user://mascot_cache/` (en un hilo) y, antes de hornear una pose, se
## busca en el disco: si está, se lee en un hilo (unos ms) en vez de
## renderizarla. Así, desde el segundo arranque de la app, el lobby y los
## juegos casi no hornean.

## Tamaños de horneado (u de PlayerAvatar). Ver tier_for().
const TIERS_U: Array[float] = [0.62, 0.95, 1.45, 2.25, 3.4]
## Cuánto se puede agrandar un cuadro al dibujarlo antes de pasar al tamaño
## siguiente (más que esto se ve borroso).
const MAX_UPSCALE := 1.08
## Presupuesto de memoria de todas las texturas horneadas (bytes, RGBA8).
const BUDGET_BYTES := 40 * 1024 * 1024
## Una apariencia que ya nadie usa se suelta si no se dibujó en este tiempo.
const RELEASE_AFTER_MSEC := 3000
const SWEEP_EVERY_MSEC := 1000
## Horneados fallidos (imagen vacía con pantalla) antes de apagar el 3D.
const MAX_FAILURES := 2

## Poses "de pantalla" (lobby, intro, resumen, podio, celular): quieta,
## parpadeo, mira a los costados, feliz saludando (4 cuadros), triste.
const SCREEN_POSES: Array[String] = ["idle@0", "blink@0", "look_l@0", "look_r@0", "idle@1",
	"wave_0@1", "wave_1@1", "wave_2@1", "wave_3@1", "idle@2",
	"hello@0", "hello@1"]
## u típico de las pantallas (tarjetas del lobby, resumen, podio).
const SCREEN_U := 2.0
## Poses de juego sin caminata (juegos con mascotas grandes y quietas).
const GAME_POSES_STATIC: Array[String] = ["idle@0", "blink@0", "look_l@0", "look_r@0", "look_u@0", "look_d@0",
	"idle@1", "wave_0@1", "wave_1@1", "wave_2@1", "wave_3@1", "idle@2", "idle@3"]
## Hasta este u los juegos mueven a las mascotas: se precalienta la caminata.
const GAME_WALK_MAX_U := 1.1
## Mascota de los avisos de la TV (TvToasts).
const TOAST_U := 0.76

## Período (s) de los cuadros animados: saludo con los brazos, saludo con
## una mano y cada baile (mismos relojes que la 2D de PlayerAvatar).
const WAVE_PERIOD := TAU / 12.0
const GREET_PERIOD := TAU / 11.0
const DANCE_PERIODS: Array[float] = [0.5, 1.0, 1.0]
const WALK_FRAMES := 8

## false: siempre 2D (lo apagan `--mascots-2d` o dos horneados fallidos).
static var enabled := true
## Solo tests (--headless): se comporta como si hubiera render (encola, busca
## y dibuja lo que se le inyecta con inject()), pero no hornea nada.
static var fake_render := false
## Presupuesto y demora para soltar (variables para poder probarlas).
static var budget_bytes := BUDGET_BYTES
static var release_after_msec := RELEASE_AFTER_MSEC
## Imprime cada horneado (tools/mascot_atlas_check.gd).
static var log_jobs := false
## Estadísticas para medir (tools/benchmark.gd, docs/PERFORMANCE.md).
## "late": poses que se pidieron recién al dibujar (no estaban precalentadas):
## en la TV son un tirón chico y un cuadro con la pose parecida.
static var stats := {"jobs": 0, "poses": 0, "worst_frame_ms": 0.0, "cpu_ms": 0.0, "failures": 0,
	"last_job": {}, "released": 0, "late": 0,
	"disk_loads": 0, "disk_poses": 0, "disk_ms": 0.0, "disk_saves": 0, "disk_scan_ms": 0.0}
## Poses horneadas tarde: "<pose> u=<tamaño>" -> veces (para medir el
## precalentado: tools/mascot_prewarm_check.gd). Se puede vaciar a mano.
static var late_poses: Dictionary = {}

static var _runner: MascotAtlas
static var _entries: Dictionary = {}        # int (ver _key) -> Entry
static var _queue: Array[Entry] = []        # Apariencias con poses pendientes, en orden.
static var _job: Mascot3DBaker.Job
static var _job_entry: Entry
static var _keep: Dictionary = {}           # dueño -> {look_key: true}
static var _protected: Dictionary = {}      # clave de Entry -> true (ver protect_game)
static var _pins: Dictionary = {}           # clave de Entry -> {pose: true} (ver pin)
static var _failures := 0
static var _supported_moods: Dictionary = {}  # ánimo -> bool (la cara 3D lo tiene)
static var _last_sweep := 0
static var _notifier: Notifier
## Solo tests (--headless con fake_render): usar igual la caché en disco
## (leer hojas del disco no necesita render).
static var disk_in_headless := false
static var _disk_state := 0                 # 0: sin leer la carpeta · 1: leyéndola · 2: lista
static var _disk_task := -1
static var _disk_box: Array = []
static var _disk_started := 0
static var _disk_index: Dictionary = {}     # clave de Entry -> [{"path", "poses", "cell"}]
static var _load_task := -1
static var _load_box: Array = []
static var _load_entry: Entry
static var _load_path := ""
static var _load_started := 0
static var _save_queue: Array[Dictionary] = []
static var _save_task := -1
static var _save_box: Array = []


## Emisor de `changed`: cambió el caché (se horneó o se soltó algo). Los
## nodos que no se redibujan solos (ej. la marca de agua del celular) se
## conectan para volver a dibujarse.
class Notifier extends RefCounted:
	signal changed


## Una hoja horneada (una textura con varias poses).
class Sheet extends RefCounted:
	var texture: Texture2D
	var regions: Dictionary = {}   ## pose -> Rect2 (px)
	var bytes := 0
	var last_used := 0


## Las poses de una apariencia a un tamaño.
class Entry extends RefCounted:
	var key := 0
	var color := Color.WHITE
	var style := 0
	var tier := 0
	var native_u := 1.0
	var cell := Vector2i.ONE
	var feet := Vector2.ZERO
	var poses: Dictionary = {}     ## pose -> Sheet
	var pending: Dictionary = {}   ## pose -> true (urgentes primero: ver order)
	var order: Array[String] = []  ## Orden de horneado de las pendientes.
	var last_used := 0


# --- Consultas (baratas: se llaman al dibujar) ---------------------------------------

## ¿Se puede hornear en este aparato? (hay render, no está apagado y no falló).
static func available() -> bool:
	return enabled and _failures < MAX_FAILURES and (fake_render or not _headless())


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Índice de tamaño para una mascota de unidad u: el más chico que no haya
## que agrandar más de MAX_UPSCALE.
static func tier_for(u: float) -> int:
	for i in TIERS_U.size():
		if TIERS_U[i] * MAX_UPSCALE >= u:
			return i
	return TIERS_U.size() - 1


## Nombre de la pose que corresponde a un ánimo y a las claves de anim de
## PlayerAvatar.draw_mascot: "<base>@<ánimo>". Bases: idle, blink,
## look_l/r/u/d, walk_{r,l,f}_0..7, wave_0..3, greet_0..1, hello (una mano
## bien arriba, quieta, con el ánimo pedido), defeat, danceK_0..3.
## Ejemplo: caminando hacia la derecha a mitad de paso, feliz → "walk_r_4@1".
static func pose_for(p_mood: int, anim: Dictionary, p_style: int = 0) -> String:
	var t := float(anim.get("t", 0.0))
	var look: Vector2 = anim.get("look", Vector2.ZERO)
	var m := clampi(p_mood, 0, PlayerAvatar.Mood.size() - 1)
	if float(anim.get("dance", 0.0)) > 0.5:
		var kind := int(anim.get("dance_kind", -1))
		if kind < 0 or kind >= PlayerAvatar.DANCE_KINDS:
			kind = posmod(p_style, PlayerAvatar.DANCE_KINDS)
		var per := DANCE_PERIODS[kind]
		return "dance%d_%d@%d" % [kind, int(fposmod(t, per) / per * 4.0) % 4, m]
	var walk := float(anim.get("walk", -1.0))
	if walk >= 0.0:
		var dir := "r" if look.x > 0.35 else ("l" if look.x < -0.35 else "f")
		return "walk_%s_%d@%d" % [dir, int(fposmod(walk, 1.0) * WALK_FRAMES) % WALK_FRAMES, m]
	if float(anim.get("hello", 0.0)) > 0.35:
		return "hello@%d" % m
	if float(anim.get("greet", 0.0)) > 0.35:
		return "greet_%d@%d" % [int(fposmod(t, GREET_PERIOD) / GREET_PERIOD * 2.0) % 2, PlayerAvatar.Mood.HAPPY]
	if float(anim.get("defeat", 0.0)) > 0.5:
		return "defeat@%d" % m
	if bool(anim.get("wave", false)):
		return "wave_%d@%d" % [int(fposmod(t, WAVE_PERIOD) / WAVE_PERIOD * 4.0) % 4, m]
	if (m == PlayerAvatar.Mood.NORMAL or m == PlayerAvatar.Mood.ANGRY) and t > 0.0 and is_blinking(t, p_style):
		return "blink@%d" % m
	if look.length() > 0.5:
		if absf(look.x) >= absf(look.y):
			return ("look_r@%d" if look.x > 0.0 else "look_l@%d") % m
		return ("look_d@%d" if look.y > 0.0 else "look_u@%d") % m
	return "idle@%d" % m


## Parpadeo con el mismo reloj que la 2D: cada ~3,3 s, a veces doble.
static func is_blinking(t: float, p_style: int) -> bool:
	var bt := t + posmod(p_style, PlayerAvatar.STYLE_NAMES.size()) * 1.37
	var cycle := floorf(bt / 3.3)
	var ph := bt - cycle * 3.3
	return ph < 0.12 or (posmod(int(cycle), 3) == 1 and ph > 0.24 and ph < 0.36)


## Definición de una pose para el baker: {"name", "mood", "anim"} o {} si
## el nombre no es válido. Todas se hornean "en el lugar": el salto, el
## squash, la inclinación y los efectos que se mueven (estrellitas, Z) los
## agrega PlayerAvatar en 2D encima del sprite.
static func pose_def(pose: String, p_style: int = 0) -> Dictionary:
	var parts := pose.split("@")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return {}
	var m := int(parts[1])
	if m < 0 or m >= PlayerAvatar.Mood.size():
		return {}
	var base := parts[0]
	var anim := {"fx": false, "in_place": true}
	var frame := int(base.get_slice("_", base.get_slice_count("_") - 1)) if base.get_slice_count("_") > 1 else 0
	if base == "idle" or base == "defeat" or base == "blink" or base == "hello":
		if base == "blink":
			anim["blink"] = true
		elif base == "defeat":
			anim["defeat"] = 1.0
		elif base == "hello":  # Un solo cuadro (quieta, como la maqueta): la mano a mitad del vaivén.
			anim["hello"] = 1.0
			anim["t"] = _safe_t(0.25 * Mascot3D.HELLO_PERIOD, Mascot3D.HELLO_PERIOD, p_style)
	elif base.begins_with("look_") and base.length() == 6:
		var d: Variant = {"l": Vector2(-1, 0), "r": Vector2(1, 0), "u": Vector2(0, -1), "d": Vector2(0, 1)}.get(base[5])
		if d == null:
			return {}
		anim["look"] = d
	elif base.begins_with("walk_") and base.get_slice_count("_") == 3:
		var d: Variant = {"l": Vector2(-1, 0), "r": Vector2(1, 0), "f": Vector2.ZERO}.get(base.get_slice("_", 1))
		if d == null or frame < 0 or frame >= WALK_FRAMES:
			return {}
		anim["walk"] = float(frame) / WALK_FRAMES
		anim["look"] = d
	elif base.begins_with("wave_") and frame >= 0 and frame < 4:
		anim["wave"] = true
		anim["t"] = _safe_t(frame * WAVE_PERIOD / 4.0, WAVE_PERIOD, p_style)
	elif base.begins_with("greet_") and frame >= 0 and frame < 2:
		anim["greet"] = 1.0
		anim["t"] = _safe_t((0.25 + frame * 0.5) * GREET_PERIOD, GREET_PERIOD, p_style)
	elif base.begins_with("dance") and base.length() == 8 and frame >= 0 and frame < 4:
		var kind := int(base[5])
		if kind < 0 or kind >= PlayerAvatar.DANCE_KINDS:
			return {}
		anim["dance"] = 1.0
		anim["dance_kind"] = kind
		anim["wave"] = true  # Si la 3D todavía no baila, al menos festeja con los brazos.
		anim["t"] = _safe_t(frame * DANCE_PERIODS[kind] / 4.0, DANCE_PERIODS[kind], p_style)
	else:
		return {}
	return {"name": pose, "mood": m, "anim": anim}


## Poses alternativas mientras la pedida se hornea (de más a menos parecida).
static func fallbacks(pose: String) -> Array[String]:
	var m := pose.get_slice("@", 1)
	var base := pose.get_slice("@", 0)
	var out: Array[String] = []
	if base.begins_with("walk_r") or base.begins_with("walk_l"):
		out.append("look_%s@%s" % [base[5], m])
	if base.begins_with("wave_") or base.begins_with("dance") or base.begins_with("greet_") or base == "hello":
		out.append("wave_0@%s" % m)
	if base != "idle":
		out.append("idle@" + m)
	if m != "0":
		out.append("idle@0")
	return out


## ¿La cara 3D tiene este ánimo? Si Mascot3D todavía no lo dibuja (muestra
## la cara normal), ese ánimo se dibuja en 2D para no perder la expresión.
static func mood_supported(p_mood: int) -> bool:
	if p_mood == PlayerAvatar.Mood.NORMAL:
		return true
	if _supported_moods.is_empty():
		var probe := Mascot3D.new().setup(Color.RED, 0)
		if not probe.has_method("visible_features"):
			probe.free()
			for m in PlayerAvatar.Mood.size():
				_supported_moods[m] = true
			return true
		probe.apply(PlayerAvatar.Mood.NORMAL, {})
		var normal: Array = probe.visible_features()
		for m in PlayerAvatar.Mood.size():
			probe.apply(m, {})
			_supported_moods[m] = m == PlayerAvatar.Mood.NORMAL or probe.visible_features() != normal
		probe.free()
	return bool(_supported_moods.get(p_mood, false))


## Cuadro horneado para dibujar, o [] si no hay (→ 2D). Devuelve
## [textura, región (Rect2 px), pies dentro de la región (px), escala].
## Si la pose no está, la encola y devuelve la más parecida que haya.
static func lookup(col: Color, p_style: int, u: float, pose: String) -> Array:
	if not available():
		return []
	var style := posmod(p_style, PlayerAvatar.STYLE_NAMES.size())
	var tier := tier_for(u)
	var e: Entry = _entries.get(_key(col, style, tier))
	if e == null:
		e = _new_entry(col, style, tier)
	var now := Time.get_ticks_msec()
	e.last_used = now
	var sheet: Sheet = e.poses.get(pose)
	if sheet == null:
		if not e.pending.has(pose) and not pose_def(pose).is_empty():
			_request(e, pose, true)
			stats.late = int(stats.late) + 1
			var lk := "%s u=%.2f" % [pose, e.native_u]
			late_poses[lk] = int(late_poses.get(lk, 0)) + 1
		for fb in fallbacks(pose):
			sheet = e.poses.get(fb)
			if sheet != null:
				pose = fb
				break
	if sheet == null:
		# Otro tamaño de la misma apariencia (se ve un poco más blando, no 2D).
		for d in [1, -1, 2, -2]:
			var other: Entry = _entries.get(_key(col, style, tier + d))
			if other == null:
				continue
			for p in [pose] + fallbacks(pose):
				sheet = other.poses.get(p)
				if sheet != null:
					sheet.last_used = now
					return [sheet.texture, sheet.regions[p], other.feet, u / other.native_u]
		return []
	sheet.last_used = now
	return [sheet.texture, sheet.regions[pose], e.feet, u / e.native_u]


# --- Precalentado y liberación ----------------------------------------------------

## Apariencia normalizada de un jugador (dict de HostServer o de la tabla).
static func look_of(p: Dictionary) -> Dictionary:
	var c: Variant = p.get("color", Color.WHITE)
	return {"color": c if c is Color else Color.WHITE, "style": PlayerAvatar.style_of(p)}


## Encola poses (nombres "<base>@<ánimo>") de estas apariencias a tamaño u.
## No hace nada sin render. Lo ya horneado o pendiente no se repite.
static func prewarm(looks: Array, u: float, poses: Array) -> void:
	if not available():
		return
	var tier := tier_for(u)
	for look: Dictionary in looks:
		var col: Color = look.get("color", Color.WHITE)
		var style := posmod(int(look.get("style", 0)), PlayerAvatar.STYLE_NAMES.size())
		var e: Entry = _entries.get(_key(col, style, tier))
		if e == null:
			e = _new_entry(col, style, tier)
		e.last_used = maxi(e.last_used, Time.get_ticks_msec())
		for p: String in poses:
			if not e.poses.has(p) and not e.pending.has(p) and not pose_def(p).is_empty() \
					and mood_supported(int(p.get_slice("@", 1))):
				_request(e, p, false)


## Lobby / pantallas: poses de pantalla de cada jugador.
static func prewarm_screens(players: Array) -> void:
	prewarm(players.map(look_of), SCREEN_U, SCREEN_POSES)


## Antes de un juego (durante la intro): las poses del juego al tamaño en
## que las dibuja (u, su MASCOT_SCALE), las extra que declara el juego
## (extra: lista de [u, poses], su MASCOT_PREWARM; ver expand_poses) y las
## de los avisos. Las extra van antes que las de pantalla: se usan primero.
static func prewarm_game(players: Array, u: float, extra: Array = []) -> void:
	var looks := players.map(look_of)
	var poses: Array[String] = GAME_POSES_STATIC.duplicate()
	if u <= GAME_WALK_MAX_U:
		poses.append_array(expand_poses(["walk@0"]))
	prewarm(looks, u, poses)
	var tiers := {tier_for(u): true}
	for item: Variant in extra:
		if item is Array and (item as Array).size() == 2 and (item[0] is float or item[0] is int) and item[1] is Array:
			prewarm(looks, float(item[0]), expand_poses(item[1]))
			tiers[tier_for(float(item[0]))] = true
	prewarm(looks, TOAST_U, ["idle@0", "idle@1", "idle@2"])
	prewarm_screens(players)
	protect_game(looks, tiers.keys())


## Las poses del juego que empieza no se sueltan por el presupuesto aunque
## todavía no se dibujen (durante la intro solo se ven las de pantalla).
## Sin esto, con un presupuesto chico (LowMemory) lo precalentado se soltaba
## antes de empezar el juego y se volvía a hornear. Dura hasta unprotect()
## (HostMain lo llama al terminar el juego) o hasta el próximo juego.
static func protect_game(looks: Array, tiers: Array) -> void:
	_protected.clear()
	for look: Dictionary in looks:
		var col: Color = look.get("color", Color.WHITE)
		var style := posmod(int(look.get("style", 0)), PlayerAvatar.STYLE_NAMES.size())
		for t: int in tiers:
			_protected[_key(col, style, t)] = true


static func unprotect() -> void:
	_protected.clear()
	_pins.clear()


## Una pose que se dibuja UNA vez en algo que queda guardado (ej. la mascota
## del marcador, en un SubViewport UPDATE_ONCE): no se suelta por el
## presupuesto hasta unprotect(). Si se soltara, cada aviso de `changed`
## volvería a dibujar el marcador, la pediría tarde y la leería otra vez.
static func pin(col: Color, p_style: int, u: float, pose: String) -> void:
	var style := posmod(p_style, PlayerAvatar.STYLE_NAMES.size())
	var poses: Dictionary = _pins.get_or_add(_key(col, style, tier_for(u)), {})
	poses[pose] = true


## Nombres de pose con atajos: "walk@M" son los 24 cuadros de caminata
## (derecha, izquierda y de frente) con el ánimo M, "walk_r@M" (o _l, _f)
## los 8 de una dirección y "wave@M" los 4 del saludo. Lo demás pasa tal
## cual (lo inválido lo descarta prewarm).
## Ejemplo: ["walk@3", "idle@2"] → walk_r_0@3 … walk_f_7@3, idle@2.
static func expand_poses(poses: Array) -> Array[String]:
	var out: Array[String] = []
	for p: Variant in poses:
		var s := str(p)
		var base := s.get_slice("@", 0)
		var m := s.get_slice("@", 1)
		if base == "walk" or base in ["walk_r", "walk_l", "walk_f"]:
			for dir in (["r", "l", "f"] if base == "walk" else [base[5]]):
				for i in WALK_FRAMES:
					out.append("walk_%s_%d@%s" % [dir, i, m])
		elif base == "wave":
			for i in 4:
				out.append("wave_%d@%s" % [i, m])
		elif not s in out:
			out.append(s)
	return out


## Estas son las apariencias que usa `owner` (ej. "tv" con los jugadores,
## "phone" con la propia). Las que no usa ningún dueño y no se dibujaron en
## RELEASE_AFTER_MSEC se sueltan solas (ej. un jugador que se fue o que
## cambió de color en el lobby).
static func keep_only(owner: String, looks: Array) -> void:
	var set := {}
	for look: Dictionary in looks:
		var col: Color = look.get("color", Color.WHITE)
		set[_look_key(col, posmod(int(look.get("style", 0)), PlayerAvatar.STYLE_NAMES.size()))] = true
	_keep[owner] = set
	_sweep(Time.get_ticks_msec())


## Suelta todo lo de una apariencia (todos los tamaños).
static func release(col: Color, p_style: int) -> void:
	var lk := _look_key(col, posmod(p_style, PlayerAvatar.STYLE_NAMES.size()))
	for k: int in _entries.keys():
		if k >> 3 == lk:
			_drop_entry(_entries[k])
	_emit_changed()


## Suelta todo (y corta el horneado en curso).
static func clear() -> void:
	for e: Entry in _entries.values():
		_drop_entry(e)
	_entries.clear()
	_queue.clear()
	_keep.clear()
	_protected.clear()
	_pins.clear()
	_emit_changed()


## Nada pendiente ni horneándose.
static func is_idle() -> bool:
	return _job == null and _queue.is_empty()


## Memoria de todas las texturas horneadas (bytes).
static func memory_bytes() -> int:
	var total := 0
	var seen := {}
	for e: Entry in _entries.values():
		for s: Sheet in e.poses.values():
			if not seen.has(s):
				seen[s] = true
				total += s.bytes
	return total


## Cantidad de poses horneadas (todas las apariencias y tamaños).
static func pose_count() -> int:
	var n := 0
	for e: Entry in _entries.values():
		n += e.poses.size()
	return n


## Apariencias (color + estilo) con algo en el caché.
static func look_count() -> int:
	var seen := {}
	for k: int in _entries:
		seen[k >> 3] = true
	return seen.size()


## Poses pendientes de hornear.
static func pending_count() -> int:
	var n := 0
	for e: Entry in _entries.values():
		n += e.pending.size()
	return n


## Para dibujos que se preparan una vez (ej. la mascota del marcador en un
## SubViewport UPDATE_ONCE): cuando se hornea algo, se vuelven a dibujar (y
## el viewport, si se pasa, se vuelve a renderizar una vez). Sin render no
## hace nada. Las conexiones se sueltan solas al liberar el nodo.
static func redraw_on_bake(item: CanvasItem, viewport: SubViewport = null) -> void:
	if not available():
		return
	var sig := notifier().changed
	if not sig.is_connected(item.queue_redraw):
		sig.connect(item.queue_redraw)
	if viewport != null:
		var again := viewport.set.bind("render_target_update_mode", SubViewport.UPDATE_ONCE)
		if not sig.is_connected(again):
			sig.connect(again)


## Para enterarse de los cambios: MascotAtlas.notifier().changed.connect(...).
static func notifier() -> Notifier:
	if _notifier == null:
		_notifier = Notifier.new()
	return _notifier


## Solo tests: agrega una pose "ya horneada" (textura cualquiera) para una
## apariencia y tamaño, con su hora de último uso. Devuelve la hoja.
static func inject(col: Color, p_style: int, u: float, pose: String, texture: Texture2D,
		last_used_msec: int = -1) -> Sheet:
	var style := posmod(p_style, PlayerAvatar.STYLE_NAMES.size())
	var tier := tier_for(u)
	var e: Entry = _entries.get(_key(col, style, tier))
	if e == null:
		e = _new_entry(col, style, tier)
	var sheet := Sheet.new()
	sheet.texture = texture
	sheet.regions[pose] = Rect2(Vector2.ZERO, Vector2(e.cell))
	sheet.bytes = e.cell.x * e.cell.y * 4
	sheet.last_used = Time.get_ticks_msec() if last_used_msec < 0 else last_used_msec
	e.poses[pose] = sheet
	e.pending.erase(pose)
	e.last_used = sheet.last_used
	return sheet


# --- Interno ------------------------------------------------------------------------

static func _look_key(col: Color, style: int) -> int:
	return (col.to_rgba32() << 3) | clampi(style, 0, 7)


static func _key(col: Color, style: int, tier: int) -> int:
	return (_look_key(col, style) << 3) | clampi(tier, 0, 7)


static func _new_entry(col: Color, style: int, tier: int) -> Entry:
	var e := Entry.new()
	e.color = col
	e.style = style
	e.tier = clampi(tier, 0, TIERS_U.size() - 1)
	e.key = _key(col, style, e.tier)
	e.native_u = TIERS_U[e.tier]
	e.cell = Mascot3DBaker.atlas_cell_px(e.native_u)
	e.feet = Mascot3DBaker.atlas_feet(e.cell)
	_entries[e.key] = e
	return e


static func _request(e: Entry, pose: String, urgent: bool) -> void:
	e.pending[pose] = true
	if urgent:
		e.order.push_front(pose)
		_queue.erase(e)
		_queue.push_front(e)
	else:
		e.order.append(pose)
		if not e in _queue:
			_queue.append(e)
	_ensure_runner()


static func _ensure_runner() -> void:
	if is_instance_valid(_runner):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_runner = MascotAtlas.new()
	_runner.name = "MascotAtlas"
	_runner.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_runner)


static func _drop_entry(e: Entry) -> void:
	if _job_entry == e and _job != null:
		_job.cancel()
		_job = null
		_job_entry = null
	_queue.erase(e)
	stats.released = int(stats.released) + e.poses.size()
	e.poses.clear()
	e.pending.clear()
	e.order.clear()
	_entries.erase(e.key)


## Suelta apariencias que ningún dueño usa y hace rato que no se dibujan, y
## si la memoria pasa del presupuesto, las hojas menos usadas.
static func _sweep(now: int) -> void:
	_last_sweep = now
	var dropped := false
	if not _keep.is_empty():
		var keep := {}
		for set: Dictionary in _keep.values():
			keep.merge(set)
		for e: Entry in _entries.values():
			if not keep.has(e.key >> 3) and now - e.last_used >= release_after_msec:
				_drop_entry(e)
				dropped = true
	var total := memory_bytes()
	if total > budget_bytes:
		var sheets: Array = []
		var skip := {}  # Hojas con una pose fijada (pin): no se sueltan.
		for e: Entry in _entries.values():
			var pinned: Dictionary = _pins.get(e.key, {})
			for p: String in pinned:
				if e.poses.has(p):
					skip[e.poses[p]] = true
		for e: Entry in _entries.values():
			if _protected.has(e.key):
				continue
			for s: Sheet in e.poses.values():
				if not s in sheets and not skip.has(s):
					sheets.append(s)
		sheets.sort_custom(func(a: Sheet, b: Sheet) -> bool: return a.last_used < b.last_used)
		for s: Sheet in sheets:
			if total <= budget_bytes or now - s.last_used < release_after_msec:
				break
			for e: Entry in _entries.values():
				for p: String in s.regions:
					if e.poses.get(p) == s:
						e.poses.erase(p)
			total -= s.bytes
			stats.released = int(stats.released) + s.regions.size()
			dropped = true
	if dropped:
		_emit_changed()


static func _emit_changed() -> void:
	if _notifier != null:
		_notifier.changed.emit()


func _process(_delta: float) -> void:
	if self != _runner:
		return
	var now := Time.get_ticks_msec()
	if now - _last_sweep > SWEEP_EVERY_MSEC:
		_sweep(now)
	if _disk_allowed():
		_poll_save()
		# Primero el disco: leer una hoja son unos ms; hornearla, varios cuadros.
		if not _disk_ready() or not _finish_load():
			return
		if _start_disk_load():
			return
	if _headless():
		return  # Sin render no se hornea (tests con fake_render).
	if _job == null:
		_start_next()
	if _job == null:
		Mascot3DBaker.release_pool()  # Nada más por hornear: suelta el viewport.
		return
	if not _job.step(self):
		return
	var job := _job
	var e := _job_entry
	_job = null
	_job_entry = null
	stats.jobs = int(stats.jobs) + 1
	stats.worst_frame_ms = maxf(float(stats.worst_frame_ms), job.worst_ms)
	stats.cpu_ms = float(stats.cpu_ms) + job.cpu_ms
	stats.last_job = {"poses": job.poses.size(), "cell": job.cell, "frames": job.frames,
		"worst_ms": job.worst_ms, "cpu_ms": job.cpu_ms, "wall_ms": now - job.started_msec, "bytes": job.bytes,
		"stages": job.stage_ms}
	if log_jobs:
		print("MascotAtlas: ", stats.last_job)
	for p in job.poses:
		e.pending.erase(p.name)
	if not job.ok:
		_failures += 1
		stats.failures = _failures
		push_warning("MascotAtlas: el horneado 3D falló (%d); se dibuja en 2D." % _failures)
		_emit_changed()
		return
	var sheet := Sheet.new()
	sheet.texture = job.texture
	sheet.regions = job.regions
	sheet.bytes = job.bytes
	sheet.last_used = now
	for p: String in job.regions:
		e.poses[p] = sheet
	stats.poses = int(stats.poses) + job.regions.size()
	if job.image != null and _disk_allowed():
		_save_queue.append({"rgba": e.color.to_rgba32(), "style": e.style, "tier": e.tier, "cell": e.cell,
			"regions": job.regions.duplicate(), "image": job.image, "key": e.key})
	job.image = null
	if memory_bytes() > budget_bytes:
		_sweep(now)
	_emit_changed()


## Arma el próximo trabajo: la primera apariencia de la cola, hasta las
## poses que entren en un viewport (Mascot3DBaker.max_job_poses).
func _start_next() -> void:
	while not _queue.is_empty():
		var e: Entry = _queue[0]
		if not _entries.has(e.key) or e.pending.is_empty():
			_queue.pop_front()
			e.order.clear()
			continue
		var grid := Mascot3DBaker.job_grid(e.cell)
		var n := grid.x * grid.y
		var defs: Array = []
		var names: Array[String] = []
		for p in e.order:
			if names.size() >= n:
				break
			if e.pending.has(p) and not p in names:
				names.append(p)
				var d := pose_def(p, e.style)
				if not d.is_empty():
					defs.append(d)
				else:
					e.pending.erase(p)
		for p in names:
			e.order.erase(p)
		if defs.is_empty():
			continue
		if e.pending.size() <= names.size():
			_queue.pop_front()
		_job = Mascot3DBaker.Job.new({"color": e.color, "style": e.style}, defs, e.cell)
		_job_entry = e
		return


func _exit_tree() -> void:
	if self == _runner:
		_wait_disk_tasks()
		Mascot3DBaker.release_pool()
		if _job != null:
			_job.cancel()
			for p in _job.poses:
				_job_entry.pending.erase(p.name)
		_job = null
		_job_entry = null
		_runner = null


## t de un cuadro animado que no cae en un parpadeo automático de Mascot3D
## (la 3D parpadea sola con "t" y ánimo normal): se corre un período entero.
static func _safe_t(t: float, period: float, p_style: int) -> float:
	var out := t + period * 4.0
	for i in 8:
		if fposmod(out + p_style * 1.37, 3.3) >= 0.14:
			return out
		out += period
	return out


# --- Caché en disco (MascotDiskCache) ------------------------------------------------

static func _disk_allowed() -> bool:
	return MascotDiskCache.enabled and (not _headless() or disk_in_headless)


## Índice de la carpeta: se lee una vez (en un hilo) antes del primer
## horneado. true cuando está listo.
static func _disk_ready() -> bool:
	if _disk_state == 2:
		return true
	if _disk_state == 0:
		_disk_state = 1
		_disk_started = Time.get_ticks_usec()
		var sig := MascotDiskCache.signature()
		var box := [[]]
		_disk_box = box
		_disk_task = WorkerThreadPool.add_task(func() -> void: box[0] = MascotDiskCache.scan(sig))
		return false
	if not WorkerThreadPool.is_task_completed(_disk_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_disk_task)
	_disk_task = -1
	_disk_index.clear()
	for h: Dictionary in _disk_box[0]:
		_index_add(h.path, int(h.color), int(h.style), int(h.tier), h.cell, h.regions)
	_disk_box = []
	_disk_state = 2
	stats.disk_scan_ms = (Time.get_ticks_usec() - _disk_started) / 1000.0
	return true


static func _index_add(path: String, rgba: int, style: int, tier: int, cell: Vector2i, regions: Dictionary) -> void:
	var key := (((rgba << 3) | clampi(style, 0, 7)) << 3) | clampi(tier, 0, 7)
	var files: Array = _disk_index.get_or_add(key, [])
	for info: Dictionary in files:
		if info.path == path:
			files.erase(info)
			break
	files.append({"path": path, "poses": regions, "cell": cell})


## Si alguna apariencia de la cola tiene en el disco una hoja con poses que
## le faltan, la empieza a leer (en un hilo). true si empezó una lectura.
static func _start_disk_load() -> bool:
	if _load_task != -1 or _disk_index.is_empty():
		return false
	for e: Entry in _queue:
		if e == _job_entry or e.pending.is_empty() or not _entries.has(e.key):
			continue
		for info: Dictionary in _disk_index.get(e.key, []):
			if Vector2i(info.cell) != e.cell:
				continue
			var useful := false
			for p: String in info.poses:
				if e.pending.has(p):
					useful = true
					break
			if not useful:
				continue
			# Si la lectura falla, la hoja sale del índice (y se hornea).
			var path: String = info.path
			var sig := MascotDiskCache.signature()
			var box := [{}]
			_load_box = box
			_load_entry = e
			_load_path = path
			_load_started = Time.get_ticks_usec()
			_load_task = WorkerThreadPool.add_task(func() -> void: box[0] = MascotDiskCache.load_sheet(path, sig))
			return true
	return false


## Termina la lectura en curso (si la hay): sube la imagen y deja las poses
## listas. false mientras el hilo sigue leyendo.
static func _finish_load() -> bool:
	if _load_task == -1:
		return true
	if not WorkerThreadPool.is_task_completed(_load_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_load_task)
	_load_task = -1
	var data: Dictionary = _load_box[0]
	var e := _load_entry
	var path := _load_path
	_load_box = []
	_load_entry = null
	_load_path = ""
	if data.is_empty():
		# Rota, vieja o borrada por el tope: se olvida (y se hornea).
		var files: Array = _disk_index.get(e.key, []) if e != null else []
		for info: Dictionary in files:
			if info.path == path:
				files.erase(info)
				break
		return true
	if e == null or _entries.get(e.key) != e:
		return true  # Se soltó mientras se leía (ej. el jugador se fue).
	var img: Image = data.image
	var now := Time.get_ticks_msec()
	var sheet := Sheet.new()
	for p: String in data.regions:
		if not e.poses.has(p):
			sheet.regions[p] = data.regions[p]
	if sheet.regions.is_empty():
		return true
	sheet.texture = ImageTexture.create_from_image(img)
	sheet.bytes = img.get_width() * img.get_height() * 4
	sheet.last_used = now
	for p: String in sheet.regions:
		e.poses[p] = sheet
		e.pending.erase(p)
		e.order.erase(p)
	if e.pending.is_empty():
		_queue.erase(e)
	stats.disk_loads = int(stats.disk_loads) + 1
	stats.disk_poses = int(stats.disk_poses) + sheet.regions.size()
	stats.disk_ms = float(stats.disk_ms) + (Time.get_ticks_usec() - _load_started) / 1000.0
	if log_jobs:
		print("MascotAtlas: del disco ", path.get_file(), " (", sheet.regions.size(), " poses, ",
			"%.1f ms)" % ((Time.get_ticks_usec() - _load_started) / 1000.0))
	if memory_bytes() > budget_bytes:
		_sweep(now)
	_emit_changed()
	return true


## Guarda en el disco las hojas recién horneadas, de a una y en un hilo.
static func _poll_save() -> void:
	if _save_task != -1:
		if not WorkerThreadPool.is_task_completed(_save_task):
			return
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
		var done: Dictionary = _save_box[0]
		_save_box = []
		if not str(done.get("path", "")).is_empty():
			stats.disk_saves = int(stats.disk_saves) + 1
			_index_add(done.path, int(done.rgba), int(done.style), int(done.tier), done.cell, done.regions)
	if _save_queue.is_empty():
		return
	var item: Dictionary = _save_queue.pop_front()
	var sig := MascotDiskCache.signature()
	var box := [item]
	_save_box = box
	_save_task = WorkerThreadPool.add_task(func() -> void:
		var it: Dictionary = box[0]
		it["path"] = MascotDiskCache.save_sheet(sig, int(it.rgba), int(it.style), int(it.tier), it.cell, it.regions, it.image)
		it.erase("image"))


## Espera los hilos del disco (al cerrar: que ninguno quede suelto).
static func _wait_disk_tasks() -> void:
	for t in [_disk_task, _load_task, _save_task]:
		if t != -1:
			WorkerThreadPool.wait_for_task_completion(t)
	_disk_task = -1
	_load_task = -1
	_save_task = -1
	if _disk_state == 1:
		_disk_state = 0
	_load_entry = null
	_save_queue.clear()


## Tests: olvida el índice del disco y lo que se estaba leyendo o guardando.
static func reset_disk() -> void:
	_wait_disk_tasks()
	_disk_state = 0
	_disk_index.clear()
	_disk_box = []
	_load_box = []
	_save_box = []


## Tests y herramientas: espera a que se guarde lo horneado (y a leer la
## carpeta), sin cuadros de por medio.
static func flush_disk() -> void:
	while _save_task != -1 or not _save_queue.is_empty():
		while _save_task != -1 and not WorkerThreadPool.is_task_completed(_save_task):
			OS.delay_msec(1)
		_poll_save()
