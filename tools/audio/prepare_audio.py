#!/usr/bin/env python3
"""Prepara la música y los efectos CC0 de assets/audio/ (ver ADR 0015 y CREDITS.md).

No es parte del juego: se corre a mano solo si hay que regenerar los .ogg.
Hace tres cosas con cada archivo original:
  1. Nivel parejo: lleva todas las pistas a la misma sonoridad (RMS) sin que
     el pico pase de -1,4 dBFS, para que ningún tema "salte" más fuerte.
  2. Bucle sin clic: corrige con una rampa de 6 ms el salto entre la última
     muestra y la primera (las pistas ya están compuestas como bucles de
     compases enteros; solo se elimina el escalón).
  3. OGG Vorbis a calidad media (~80 kbps estéreo), para que toda la música
     entre en ~3 MB.

Uso (las fuentes son clones de repos públicos, fuera del proyecto):
  python3 -m venv /tmp/venv && /tmp/venv/bin/pip install soundfile numpy
  git clone --depth 1 https://github.com/PacktPublishing/Game-Development-Patterns-with-Godot-4 /tmp/src/packt
  git clone --depth 1 https://github.com/excaliburjs/sample-tactics /tmp/src/tactics
  git clone --depth 1 https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds /tmp/src/cc0
  /tmp/venv/bin/python tools/audio/prepare_audio.py --src=/tmp/src
"""
import os
import sys

import numpy as np
import soundfile as sf

ADV = "packt/12.cross-fading-with-service-locator/01.start/Assets/Juhani Junkala [Chiptune Adventures] OGG/"
RETRO = "tactics/res/5 Action Chiptunes By Juhani Junkala/"
UI = "cc0/kenney_interfacesounds/Audio/"

# destino -> (origen, tipo). La sonoridad objetivo depende del tipo.
FILES = {
    "music/lobby.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 4. Stage Select.ogg", "music"),
    "music/game_calm.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 1. Stage 1.ogg", "music"),
    "music/game_play.ogg": (ADV + "Juhani Junkala [Chiptune Adventures] 2. Stage 2.ogg", "music"),
    "music/game_action.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Level 1.wav", "music"),
    "music/summary.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Title Screen.wav", "music"),
    "music/podium.ogg": (RETRO + "Juhani Junkala [Retro Game Music Pack] Ending.wav", "music"),
    "sfx/ui_tick.ogg": (UI + "tick_004.ogg", 0.22),
    "sfx/ui_select.ogg": (UI + "select_002.ogg", 0.35),
    "sfx/ui_back.ogg": (UI + "back_004.ogg", 0.30),
}

MUSIC_RMS_DB = -16.0   # Sonoridad común de la música.
PEAK_MAX = 0.85        # ~ -1,4 dBFS: margen para lo que agrega el códec
SEAM_SAMPLES = 256     # Rampa de la costura del bucle (~6 ms a 44,1 kHz).
MUSIC_QUALITY = 0.72   # compression_level de libsndfile: 1 - calidad Vorbis (q≈0,28)
SFX_QUALITY = 0.4


def fix_seam(d: np.ndarray) -> np.ndarray:
    """Quita el escalón entre el final y el principio sumando una rampa."""
    step = d[0] - d[-1]
    ramp = np.linspace(0.0, 1.0, SEAM_SAMPLES, dtype=np.float32)[:, None]
    d = d.copy()
    d[-SEAM_SAMPLES:] += ramp * step
    return d


def main() -> None:
    src = "."
    for a in sys.argv[1:]:
        if a.startswith("--src="):
            src = a.split("=", 1)[1]
    out_root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
    for dest, (rel, kind) in FILES.items():
        d, sr = sf.read(os.path.join(src, rel), dtype="float32", always_2d=True)
        if kind == "music":
            rms = float(np.sqrt((d ** 2).mean()))
            gain = min(10 ** (MUSIC_RMS_DB / 20) / rms, PEAK_MAX / float(np.abs(d).max()))
            d = fix_seam(d * gain)
            quality = MUSIC_QUALITY
        else:
            d = d.mean(axis=1, keepdims=True)  # Efectos en mono.
            d = d * (float(kind) / float(np.abs(d).max()))
            quality = SFX_QUALITY
        path = os.path.normpath(os.path.join(out_root, dest))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        d = np.clip(d, -1.0, 1.0)
        # Por bloques: libsndfile 1.2 se cae si se le pasa un OGG largo de una vez.
        with sf.SoundFile(path, "w", sr, d.shape[1], format="OGG", subtype="VORBIS",
                          compression_level=quality) as f:
            for i in range(0, len(d), 16384):
                f.write(d[i:i + 16384])
        print("%-24s %6.1f s  %4d KB" % (dest, len(d) / sr, os.path.getsize(path) // 1024))


if __name__ == "__main__":
    main()
