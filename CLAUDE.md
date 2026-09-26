# Party Games · contexto para Claude Code

Juego party para 1–4 jugadores: la TV es el host y los celulares son controles. Godot 4.4, GDScript. Documentación y comentarios en **español**, identificadores en **inglés**.

## Comandos

```bash
godot --headless --path . --import                      # primera vez / tras agregar class_name
godot --headless --path . -s res://tests/run_tests.gd   # tests (exit 0 = OK)
godot --path . -- --host                                # correr como TV
godot --path . -- --controller                          # correr como control
```

Siempre correr los tests antes de dar un cambio por terminado.

## Arquitectura (resumen)

- `core/protocol/protocol.gd` — **contrato único** de mensajes. Cualquier cambio: actualizar `docs/PROTOCOL.md` y subir `VERSION` si rompe compatibilidad.
- `host/network/host_server.gd` — servidor WebSocket, autoritativo. Valida todo lo que entra.
- `host/host_main.gd` — lobby y fases (lobby → playing → results).
- `host/minigames/` — cada juego extiende `MiniGame` y se registra en `registry.gd`. Guía: `docs/ADDING_A_MINIGAME.md`.
- `controller/` — cliente, descubrimiento y layouts táctiles.
- `app/boot.gd` — decide modo host/control.

## Reglas

- La TV es autoritativa: el control solo manda `axis` y `btn`. Nunca agregar mensajes que permitan al control decidir resultados.
- Validar y recortar toda entrada de red en el host; nunca lanzar errores por datos externos.
- Nombres de jugador: solo `Label`/`draw_string`, jamás `RichTextLabel` con BBCode.
- UI de la TV navegable con D-pad (sin mouse/táctil).
- UI construida por código (sin .tscn salvo `app/boot.tscn`); mantener ese estilo o migrar de forma consistente.
- Nuevos juegos: agregar al registry; los tests genéricos los cubren solos.
- Decisiones de arquitectura relevantes: nuevo ADR en `docs/adr/`.
- Nunca commitear keystores, certificados ni `export_credentials.cfg`.

## Estado y próximos pasos

Ver `docs/ROADMAP.md`. Limitación importante: Godot no exporta a tvOS (ver `docs/adr/0001-motor-godot.md`).
