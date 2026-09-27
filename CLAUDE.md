# Party Games · contexto para Claude Code

Juego party para 1–4 jugadores: la TV es el host y los celulares son controles. Godot 4.4, GDScript. Documentación y comentarios en **español**, identificadores en **inglés**.

## Comandos

```bash
godot --headless --path . --import                      # primera vez / tras agregar class_name
godot --headless --path . -s res://tests/run_tests.gd   # tests (exit 0 = OK)
godot --path . -- --host                                # correr como TV
godot --path . -- --controller                          # correr como control
# Capturas reales de TV y celular (pantalla virtual; ver skill verificar-visual)
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy -s res://tools/capture_screens.gd -- --out=/tmp/capturas
# Benchmark de rendimiento por pantalla y juego (ver docs/PERFORMANCE.md)
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy -s res://tools/benchmark.gd -- --json=/tmp/bench.json
```

En Claude Code en la web, `.claude/hooks/session-start.sh` instala Godot 4.4.1 automáticamente.

Siempre correr los tests antes de dar un cambio por terminado.

## Arquitectura (resumen)

- `core/protocol/protocol.gd` — **contrato único** de mensajes. Cualquier cambio: actualizar `docs/PROTOCOL.md` y subir `VERSION` si rompe compatibilidad.
- `host/network/host_server.gd` — servidor WebSocket, autoritativo. Valida todo lo que entra.
- `host/host_main.gd` — orquesta las fases (lobby → playing → results → …). No tiene lógica de puntos ni UI propia.
- `host/tournament/tournament.gd` — modo competencia: rondas y puntos por posición (lógica pura, testeada).
- `host/ui/` — pantallas (lobby, resumen de ronda, podio, pausa) y componentes de la TV.
- `core/ui/ui_theme.gd` — sistema visual: tokens de color/medidas, tema y funciones de dibujo. Mascotas, fondo y chips en `core/ui/widgets/`.
- `core/art3d/` — piezas 3D (estrellas, bloques, medallas…) horneadas una vez a un atlas con el plástico de las mascotas; siempre con respaldo 2D (ADR 0016).
- `host/minigames/` — cada juego extiende `MiniGame` y se registra en `registry.gd`. Guía: `docs/ADDING_A_MINIGAME.md`.
- `controller/` — cliente, descubrimiento y layouts táctiles.
- `app/boot.gd` — decide modo host/control.

## Reglas

- La TV es autoritativa: el control solo manda `axis` y `btn`. Nunca agregar mensajes que permitan al control decidir resultados.
- Validar y recortar toda entrada de red en el host; nunca lanzar errores por datos externos.
- Nombres de jugador: solo `Label`/`draw_string`, jamás `RichTextLabel` con BBCode.
- UI de la TV navegable con D-pad (sin mouse/táctil).
- UI construida por código (sin .tscn salvo `app/boot.tscn`); mantener ese estilo o migrar de forma consistente.
- Colores, tamaños y tipografía solo desde `UiTheme`; nada de valores sueltos en pantallas o juegos.
- Jugadores distinguibles sin depender solo del color: etiqueta 1P–4P siempre, más el accesorio de la mascota o, si el jugador es un objeto de su color (tanque, víbora, paleta), una forma o patrón propio. No hace falta la mascota entera en todos los juegos (ver "Cómo se ve cada jugador" en `docs/JUEGOS.md`).
- El botón "Atrás" abre el menú de pausa; nunca corta una partida sin confirmar.
- Nuevos juegos: agregar al registry; los tests genéricos los cubren solos.
- Rendimiento (60 fps en TV de gama baja): lo que no cambia no se redibuja en cada frame; presupuestos en `docs/PERFORMANCE.md`.
- Decisiones de arquitectura relevantes: nuevo ADR en `docs/adr/`.
- Nunca commitear keystores, certificados ni `export_credentials.cfg`.

## Skills del proyecto (`.claude/skills/`)

- `nuevo-minijuego` — checklist para crear o cambiar un juego.
- `diseno-tv` — sistema visual y reglas de UI para TV/celular.
- `verificar-visual` — capturas reales para revisar cambios de UI.
- `nuevo-layout` — sumar un tipo de control en el celular (toca protocolo y VERSION).

Análisis de qué skills conviene usar (y cuáles no): `docs/SKILLS.md`.

## Estado y próximos pasos

Ver `docs/PLAN.md` (definición de "terminado", presupuestos de rendimiento y fases) y `docs/ROADMAP.md`. **Para retomar el trabajo: `docs/PENDIENTES.md`** (qué falta, agentes en curso y qué depende del dueño). Limitación importante: Godot no exporta a tvOS (ver `docs/adr/0001-motor-godot.md`).
