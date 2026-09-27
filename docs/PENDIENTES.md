# Pendientes para retomar

Estado al **27/09/2026** (rama `claude/laughing-ramanujan-tfi3ps`, [PR #1](https://github.com/vepamusic11/PARTY-GAMES/pull/1)). Lo hecho está en el PR y en [PLAN.md](PLAN.md); acá va solo **lo que falta**, ordenado para retomar sin buscar.

## Cómo retomar (5 minutos)

1. Traer lo último: `git pull` en `D:\Claude\PARTY-GAMES` (rama `claude/laughing-ramanujan-tfi3ps`).
2. Importar (arma el índice de clases; hace falta después de cada `git pull` con archivos nuevos):
   `& "D:\Claude\Godot\Godot_v4.4.1-stable_win64_console.exe" --headless --path . --import`
3. Probar en la PC: `... --path . -- --host` (TV, ventana izquierda) y `... --path . -- --controller` (control, ventana derecha). Para jugar solo: en el lobby, Enter sobre un lugar libre → "Sumar bot".
4. Pedirle a Claude: *"retomá los pendientes de docs/PENDIENTES.md"*.

## 1. Lo que depende del dueño

| Qué | Por qué | Cómo |
|---|---|---|
| **Subir como archivo los temas de Suno** del lobby (`suno.com/s/29C9BMlJJeFzj1jz`) y de batallas (`suno.com/s/F9Tq26dAwsYYmFG0`, `suno.com/s/BdjIiimEjU85XsRR`) | El entorno de Claude no puede entrar a suno.com | En Suno: menú **⋯ → Download → MP3 Audio** y adjuntar el `.mp3` en el chat (como se hizo con *Breakpoint Rush*) |
| **Confirmar el plan de Suno** con el que se hicieron los temas | Suno da uso comercial solo a canciones creadas con plan pago (Pro/Premier); con el gratis es uso no comercial | Si fueron con plan gratis, regenerarlos con plan pago antes de publicar |
| **Probar en la PC** y mandar capturas de lo que no guste | Validar diseño y jugabilidad reales | Ver "Cómo retomar" |
| **Instalar el APK de prueba** en un celular Android (cuando esté el job de CI) | Probar con el celular real como control | GitHub → Actions → última corrida → Artifacts → `party-game-debug-apk`; permitir "orígenes desconocidos" ([BUILD.md](BUILD.md)) |
| **Decidir**: enlace definitivo del QR para unirse; pantalla de Créditos antes de publicar | Fase B/D | [RECURSOS.md](RECURSOS.md), [CREDITS.md](../CREDITS.md) |
| **Conseguir un aparato de gama baja** (Chromecast con Google TV o TV box Android, ~30–40 USD) | Es la única forma de medir 60 fps reales y el 3D horneado en el chip de una TV barata | — |

## 2. Trabajo en curso (agentes de Claude)

Tres agentes quedaron trabajando el 27/09 en copias aisladas (`.claude/worktrees/`). Si al retomar ya no están (el contenedor se recicla tras un rato sin uso), **se vuelven a lanzar con el mismo pedido**; lo ya integrado está a salvo en la rama.

| Agente | Qué hace | Al terminar |
|---|---|---|
| **Piezas del escenario en 3D** | Estrellas, trofeo, medallas, premios y bloques del tablero horneados con el mismo plástico (`core/art3d/`) | Integrar, revisar capturas y rendimiento |
| **APK de prueba por CI** | `export_presets.cfg` (Android) + job de GitHub Actions que arma el APK debug con keystore efímero (nunca en el repo) + guía en BUILD.md | Integrar y verificar que el job quede verde y el APK se instale |
| **Estilos de música** | Estilo "Original" con los temas del dueño (por defecto) + Fiesta / Retro / Relajado (/ Latino) + "Sin música", elegibles en la pausa; muestras para escuchar en `scratchpad/musica_estilos/` | Mandar muestras al dueño, integrar el estilo elegido y los temas de Suno que falten |

## 3. Diseño (pedido: "3D como la maqueta o mejor")

- [x] Mascotas 3D horneadas en todo el juego (lobby, intro, 13 juegos, resumen, podio, celular) con respaldo 2D ([ADR 0012](adr/0012-mascotas-3d.md)).
- [x] Podio centrado (la línea "Se jugó…" lo corría a la derecha y cortaba el 3.°).
- [x] Calidad de las mascotas 3D al nivel de la maqueta: plástico, cara, contorno y los 9 ánimos ([comparación](img/mascotas_3d_comparacion.png)). Pendiente de decisión: el amarillo y el verde de la paleta tiran a naranja y turquesa respecto de la maqueta (`Protocol.MASCOT_COLORS`).
- [ ] Piezas del escenario en 3D (agente en curso).
- [ ] Capturas de Empujones y ¡Que no te deje la cámara!: muestran el resumen en vez del juego (el juego termina antes de la foto); ajustar `SHOT_DELAY` en `tools/capture_screens.gd`.
- [ ] Revisar con la maqueta de Pintar el piso (`docs/design/referencia_juego_pintar.webp`) juego por juego una vez integrado todo.
- [ ] Algunas poses se hornean la primera vez que se dibujan (Empujones, Karts): si se nota un tirón en la TV real, sumarlas al precalentado.

## 4. Juegos nuevos (ver [JUEGOS.md](JUEGOS.md))

- **Siguiente:** *Bombas de mascotas* (tipo Bomberman; estrena el joystick + A/B), *Tanquecitos* (tipo Battle City, 2 contra 2 cuidando la base), *Víboras*, *Come-come*.
- Regla nueva: no todos los juegos necesitan la mascota entera; alcanza el color del jugador **con** etiqueta 1P–4P y patrón propio ("Cómo se ve cada jugador" en JUEGOS.md).
- Máximo de jugadores: **4** (confirmado). Juegos por competencia: **sin límite** (confirmado).

## 5. Técnico y calidad

- [ ] Medir en un Google TV real: 60 fps, horneado de mascotas (ajustar `Mascot3DBaker.POSES_PER_FRAME`), memoria (~25–30 MB de atlas).
- [ ] Carrera de obstáculos: re-medir p95 con la máquina libre (quedó en el límite de 8 ms con la máquina cargada).
- [ ] Sumo, Pool y Karts: confirmar p95 ≤ 8 ms con la máquina libre (con carga no lo cumplían ni en 2D ni en 3D).
- [ ] Protocolo v2 (joystick + A/B): TV y celulares se actualizan juntos; ningún juego usa todavía A/B.
- [ ] Multitáctil del joystick A/B y "Salir" mantenido: probar en celular real.
- [ ] Música: confirmar en OpenGameArt y kenney.nl las licencias CC0 de los temas actuales (vinieron de repos espejo).
- [ ] Pantalla de Créditos dentro de la app (lo piden las licencias MIT/OFL/CC-BY) antes de publicar.
- [ ] Durante la intro de cada juego el celular no muestra "¡Mirá la TV!" (distinguirlo pide un cambio de protocolo).

## 6. Herramientas para revisar sin TV

- Capturas reales: `tools/capture_screens.gd` (también las sube la CI como artefacto de cada PR).
- Videos cortos: Godot graba cuadro por cuadro con `--write-movie` (probado; ver el lobby animado del 27/09). Pendiente si se quiere: herramienta que grabe 5–8 s de cada juego jugado por bots y los publique en el tablero.
- Tablero de avance: https://claude.ai/artifact/SZTee3B6GCL15wBnSdW795
