---
name: nuevo-layout
description: Agregar un tipo de control nuevo en el celular de Party Games (dos botones, cuatro botones, inclinación/acelerómetro, etc.). Usar cuando un minijuego necesita un control que no existe en Protocol.LAYOUTS.
---

# Nuevo layout de control

Un layout es **qué dibuja el celular** y **qué manda** (`axis` y `btn`). Agregar uno toca el protocolo, así que la app del celular tiene que actualizarse.

## Checklist

1. **Protocolo** (`core/protocol/protocol.gd`):
   - Constante `LAYOUT_...` con comentario de qué manda.
   - Agregarla a `LAYOUTS`.
   - Si usa botones nuevos: `BTN_C`, `BTN_D` y ampliar `BTN_MASK`.
   - **Subir `VERSION`**: un control viejo no sabría dibujarlo y el jugador quedaría mirando "Mirá la TV" sin poder jugar. Con la versión nueva, la TV lo rechaza con "Actualizá ambas apps".
2. **Celular**:
   - Control nuevo en `controller/layouts/`, con el estilo de `big_button.gd` (multitouch, `Haptics.buzz("tap")` al apretar, colores desde `UiTheme`).
   - Caso nuevo en `ControllerMain._on_layout_changed` y lectura del valor en `ControllerMain._process`.
3. **Inclinación (acelerómetro):** leer `Input.get_accelerometer()`, filtrar el ruido (promedio móvil), convertirlo a `axis` en -1..1 y recortarlo **en el celular y en la TV**. Ofrecer "calibrar" (tomar la posición actual como centro).
4. **Tarjeta del lobby:** ícono en `GameCard._draw_control_icon` y nombre en `GameCard.CONTROL_NAMES`.
5. **Capturas:** nombre en `CONTROL_SHOTS` de `tools/capture_screens.gd`.
6. **Docs:** tabla de layouts en `docs/PROTOCOL.md` (con qué manda) y la sección "Un layout nuevo" de `docs/ADDING_A_MINIGAME.md`.
7. **Tests:**
   - `parse_input` con los botones nuevos enmascarados.
   - El layout está en `LAYOUTS`.
   - Integración: la TV manda el layout y el control lo recibe.

## Consejo

Conviene agrupar varios layouts en **una sola** subida de `VERSION`, para no obligar a actualizar el celular muchas veces.
