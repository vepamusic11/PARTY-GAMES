#!/usr/bin/env python3
"""Prepara la música y los efectos de assets/audio/ (ver ADR 0015, ADR 0017 y CREDITS.md).

No es parte del juego: se corre a mano solo si hay que regenerar los .ogg.
Hace tres cosas con cada archivo original:
  1. Nivel parejo: lleva todas las pistas a la misma sonoridad sin que el pico
     pase de -1,4 dBFS, para que ningún tema "salte" más fuerte al cambiar de
     pantalla o de estilo. Los temas del estilo Retro se igualan por RMS
     (-16 dB, ADR 0015); los nuevos, por sonoridad percibida (-14,5 LUFS,
     BS.1770), que es lo que dan los Retro medidos así.
  2. Bucle sin clic: en los bucles (ya compuestos como compases enteros)
     corrige con una rampa de 6 ms el salto entre la última muestra y la
     primera. En las *canciones* (temas con principio y final, como los del
     dueño) arma el bucle: arranca en `start`, vuelve a `loop` (una frase
     elegida porque lo que sigue suena igual que lo que sigue al final) y
     funde 0,25 s el final con lo que suena justo antes de `loop`, así el
     salto no se nota. Godot vuelve a `loop` con loop_offset (en el .import).
  3. OGG Vorbis: calidad media para los bucles, más alta para las canciones.

Uso (las fuentes son clones de repos públicos y archivos del dueño, fuera del proyecto):
  python3 -m venv /tmp/venv && /tmp/venv/bin/pip install soundfile numpy pyloudnorm
  git clone --depth 1 https://github.com/PacktPublishing/Game-Development-Patterns-with-Godot-4 /tmp/src/packt
  git clone --depth 1 https://github.com/excaliburjs/sample-tactics /tmp/src/tactics
  git clone --depth 1 https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds /tmp/src/cc0
  # Abstraction (Relajado): ZIP del release music-v1 de jfpx/cc0-media-library, sha256 en SHA256SUMS.txt
  curl -L -o /tmp/src/music-cc0.zip https://github.com/jfpx/cc0-media-library/releases/download/music-v1/music-cc0.zip
  unzip /tmp/src/music-cc0.zip -d /tmp/src/abs
  # Temas del dueño (PARTY-GAME): los MP3 que exporta Suno, en /tmp/src/owner/
  /tmp/venv/bin/python tools/audio/prepare_audio.py --src=/tmp/src [--only=original]
"""
import os
import sys

import numpy as np
import soundfile as sf

ADV = "packt/12.cross-fading-with-service-locator/01.start/Assets/Juhani Junkala [Chiptune Adventures] OGG/"
RETRO = "tactics/res/5 Action Chiptunes By Juhani Junkala/"
UI = "cc0/kenney_interfacesounds/Audio/"
ABS = "abs/music/unspecified/"
OWNER = "owner/"

# destino -> (origen, tipo). La sonoridad objetivo depende del tipo.
FILES = {
    "music/lobby.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 4. Stage Select.ogg", "music"),
    "music/game_calm.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 1. Stage 1.ogg", "music"),
    "music/game_play.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 2. Stage 2.ogg", "music"),
    "music/game_action.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Level 1.wav", "music"),
    "music/summary.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Title Screen.wav", "music"),
    "music/podium.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Ending.wav", "music"),
    # Relajado (ADR 0017): bucles de Abstraction (CC0), chillout / lo-fi / jazz suave.
    # Cuatro archivos para seis pantallas (ver MusicStyles): el APK no da para más.
    "music/relajado/lobby.ogg": (ABS + "lofi/abstraction-4e6836606331898f144502c1.ogg", "loop"),
    "music/relajado/calm.ogg": (ABS + "jazz/abstraction-d20307161d504210a0dd287e.ogg", "loop"),
    "music/relajado/groove.ogg": (ABS + "jazz/abstraction-9ccab202734d1e91a94d3042.ogg", "loop"),
    "music/relajado/action.ogg": (ABS + "jazz/abstraction-f23d9e696a256a1881c5d216.ogg", "loop"),
    "sfx/ui_tick.ogg": (UI + "tick_004.ogg", 0.22),
    "sfx/ui_select.ogg": (UI + "select_002.ogg", 0.35),
    "sfx/ui_back.ogg": (UI + "back_004.ogg", 0.30),
}

# Canciones (temas con principio y final): destino -> (origen, arranque s,
# vuelta del bucle s, largo del bucle en muestras del original). El punto de
# vuelta y el largo se buscaron por parecido de armonía y timbre (pulsos
# sincronizados) y se afinaron a la muestra por correlación de ataques: el
# bucle dura 80 compases exactos (~146,6 BPM).
SONGS = {
    "music/original/breakpoint_rush.ogg": (OWNER + "breakpoint_rush.mp3", 12.94, 33.080, 6284731),
}

MUSIC_RMS_DB = -16.0   # Sonoridad común de la música Retro (RMS).
TARGET_LUFS = -14.5    # Sonoridad percibida de los estilos nuevos (= la de Retro medida en LUFS).
PEAK_MAX = 0.85        # ~ -1,4 dBFS: margen para lo que agrega el códec
LIMIT_KNEE = 0.62      # Desde acá se redondean los picos (mismo limitador que MusicGen).
SEAM_SAMPLES = 256     # Rampa de la costura del bucle (~6 ms a 44,1 kHz).
SONG_XFADE = 0.25      # Fundido del bucle de las canciones (s).
SONG_FADE_IN = 0.012   # Entrada sin clic al arrancar la canción (s).
MUSIC_QUALITY = 0.72   # compression_level de libsndfile: 1 - calidad Vorbis (q≈0,28, ~80 kbps)
LOOP_QUALITY = 0.95    # Relajado: ~62 kbps estéreo; temas suaves, sin agudos filosos: lo toleran.
SONG_QUALITY = 0.62    # Canciones del dueño: q≈0,38 (~115–125 kbps estéreo).
SFX_QUALITY = 0.4


def fix_seam(d: np.ndarray) -> np.ndarray:
    """Quita el escalón entre el final y el principio sumando una rampa."""
    step = d[0] - d[-1]
    ramp = np.linspace(0.0, 1.0, SEAM_SAMPLES, dtype=np.float32)[:, None]
    d = d.copy()
    d[-SEAM_SAMPLES:] += ramp * step
    return d


def soft_limit(d: np.ndarray) -> np.ndarray:
    """Limitador suave: por debajo de LIMIT_KNEE no toca nada; arriba redondea
    los picos (tanh) sin pasar de PEAK_MAX."""
    room = PEAK_MAX - LIMIT_KNEE
    a = np.abs(d)
    over = a > LIMIT_KNEE
    a[over] = LIMIT_KNEE + room * np.tanh((a[over] - LIMIT_KNEE) / room)
    return np.sign(d) * a


def to_lufs(d: np.ndarray, sr: int) -> np.ndarray:
    """Lleva a TARGET_LUFS (sonoridad integrada) y limita los picos."""
    import pyloudnorm as pyln
    lufs = pyln.Meter(sr).integrated_loudness(d)
    d = d * (10 ** ((TARGET_LUFS - lufs) / 20))
    return soft_limit(d)


def make_song(d: np.ndarray, sr: int, start: float, loop: float, length: int) -> tuple:
    """Recorta la canción desde `start` hasta el final del bucle y funde el
    final con lo que suena antes de `loop`. Devuelve (audio, loop_offset en s)."""
    s, a = int(round(start * sr)), int(round(loop * sr))
    b = a + length
    x = int(SONG_XFADE * sr)
    out = d[s:b].copy()
    t = np.linspace(0.0, 1.0, x, dtype=np.float32)[:, None]
    # Lineal (no de igual potencia): las dos partes son casi la misma música.
    out[-x:] = d[b - x:b] * (1.0 - t) + d[a - x:a] * t
    fin = int(SONG_FADE_IN * sr)
    out[:fin] *= np.linspace(0.0, 1.0, fin, dtype=np.float32)[:, None]
    return out, (a - s) / sr


def write_ogg(path: str, d: np.ndarray, sr: int, quality: float) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    d = np.clip(d, -1.0, 1.0)
    # Por bloques: libsndfile 1.2 se cae si se le pasa un OGG largo de una vez.
    with sf.SoundFile(path, "w", sr, d.shape[1], format="OGG", subtype="VORBIS",
                      compression_level=quality) as f:
        for i in range(0, len(d), 16384):
            f.write(d[i:i + 16384])


def set_loop_offset(path: str, seconds: float) -> None:
    """Escribe loop=true y loop_offset en el .import de Godot (si existe)."""
    imp = path + ".import"
    if not os.path.exists(imp):
        print("   (sin .import todavía: correr `godot --headless --path . --import` y volver a correr esto)")
        return
    lines = []
    for line in open(imp, encoding="utf-8").read().splitlines():
        if line.startswith("loop="):
            line = "loop=true"
        elif line.startswith("loop_offset="):
            line = "loop_offset=%.6f" % seconds
        lines.append(line)
    open(imp, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def main() -> None:
    src = "."
    only = ""
    for a in sys.argv[1:]:
        if a.startswith("--src="):
            src = a.split("=", 1)[1]
        elif a.startswith("--only="):
            only = a.split("=", 1)[1]
    out_root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
    for dest, (rel, kind) in FILES.items():
        if only and only not in dest:
            continue
        d, sr = sf.read(os.path.join(src, rel), dtype="float32", always_2d=True)
        if kind == "music":
            rms = float(np.sqrt((d ** 2).mean()))
            gain = min(10 ** (MUSIC_RMS_DB / 20) / rms, PEAK_MAX / float(np.abs(d).max()))
            d = fix_seam(d * gain)
            quality = MUSIC_QUALITY
        elif kind == "loop":
            d = fix_seam(to_lufs(d, sr))
            quality = LOOP_QUALITY
        else:
            d = d.mean(axis=1, keepdims=True)  # Efectos en mono.
            d = d * (float(kind) / float(np.abs(d).max()))
            quality = SFX_QUALITY
        path = os.path.normpath(os.path.join(out_root, dest))
        write_ogg(path, d, sr, quality)
        print("%-34s %6.1f s  %4d KB" % (dest, len(d) / sr, os.path.getsize(path) // 1024))
    for dest, (rel, start, loop, length) in SONGS.items():
        if only and only not in dest:
            continue
        full = os.path.join(src, rel)
        if not os.path.exists(full):
            print("%-34s (falta %s: se saltea)" % (dest, rel))
            continue
        d, sr = sf.read(full, dtype="float32", always_2d=True)
        d, offset = make_song(to_lufs(d, sr), sr, start, loop, length)
        path = os.path.normpath(os.path.join(out_root, dest))
        write_ogg(path, d, sr, SONG_QUALITY)
        set_loop_offset(path, offset)
        print("%-34s %6.1f s  %4d KB  bucle desde %.3f s" % (dest, len(d) / sr, os.path.getsize(path) // 1024, offset))


if __name__ == "__main__":
    main()
