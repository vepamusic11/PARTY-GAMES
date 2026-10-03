# ADR 0014 · Layout "joystick_ab": joystick + botones A y B, y protocolo v2

- **Estado:** Aceptada
- **Fecha:** 2026-09-27

## Contexto
Los cuatro layouts del celular (`wait`, `joystick`, `slider_h`, `one_button`) alcanzan para moverse **o** apretar, pero no para las dos cosas a la vez. Varios juegos propuestos en [JUEGOS.md](../JUEGOS.md) necesitan moverse y hacer una acción: patear en Fútbol, tirar bombas, saltar, reventar globos. Un control de consola resuelve eso con un stick y dos botones: A para la acción principal y B para la secundaria.

El bit `BTN_B` ya existía en `Protocol` y `parse_input` ya lo dejaba pasar; lo que faltaba era un control que lo mande y que la TV pueda pedirlo.

## Decisión
- **Protocolo:** `Protocol.LAYOUT_JOYSTICK_AB = "joystick_ab"`. El celular sigue mandando solo `input` con `axis` (el joystick) y `btn` (`BTN_A = 1`, `BTN_B = 2`, los dos a la vez = `3`). La TV decide qué hace cada botón. `data` opcional `{"a": "Patear", "b": "Saltar"}`: un texto chico debajo de cada botón (se recorta a 12 caracteres y se dibuja con `draw_string`, nunca BBCode).
- **`VERSION` pasa de 1 a 2** (ver "Compatibilidad").
- **Celular:** `controller/layouts/joystick_ab.gd` (`JoystickAB`) arma el control con las piezas que ya existen, así se ve igual que el resto: un `VirtualJoystick` flotante en su zona (54 % del ancho) y dos `BigButton` (aro de arcade, bisel, brillo, squash y onda al tocar, vibración y sonido). A es el más grande, lleva el color del jugador y va abajo del lado de afuera; B es neutro (`UiTheme.PHONE_KEY_NEUTRAL`), más chico, arriba y hacia adentro en diagonal, a un pulgar de distancia. Los dos miden ≥ 128 px de diámetro en cualquier celular (celular de 2340×1080: A 356 px y B 300 px).
- **Multitouch:** `JoystickAB` recibe todos los toques y reparte cada dedo al apoyarlo (joystick en su zona; en la otra, el botón más cercano relativo a su tamaño). Ese dedo sigue yendo a la misma pieza hasta que se levanta, como el "touch focus" de Godot. Así se camina con un pulgar y se aprieta A, B o los dos con el otro. Un segundo dedo en la zona del joystick no le roba el control al primero. Al perder el foco la app, se suelta todo.
- **Modo zurdo:** propiedad `JoystickAB.left_handed` que invierte todo en espejo (joystick a la derecha, botones a la izquierda). Cambiarla suelta los dedos para no dejar un botón trabado. El ajuste del celular lo agrega otro cambio en paralelo; este layout solo expone la propiedad. Para conectarlo: en `ControllerMain._on_layout_changed`, caso `LAYOUT_JOYSTICK_AB`, `pad.left_handed = <ajuste zurdo>`; y si el ajuste cambia con el control en pantalla, `if _active_layout is JoystickAB: _active_layout.left_handed = valor`.
- **TV:** un juego declara `"layout": Protocol.LAYOUT_JOYSTICK_AB` en `get_info()` y lee `input.btn`. `MiniGame` suma ayudas para no repetir la detección de flancos en cada juego: `track_buttons(player_id, input)` (guarda el estado y devuelve los botones que se acaban de apretar), `is_button_down`, `pressed_a` y `pressed_b`. `on_player_disconnected` manda `btn = 0`, así que un jugador que se corta suelta todo solo.
- **Lobby e intro:** ícono propio en `UiTheme.draw_control_icon` (stick + A + B) y nombre "Joystick + A/B" en `GameCard.CONTROL_NAMES`.

## Compatibilidad: por qué sube `VERSION`
La pregunta era si un celular v1, que no conoce `joystick_ab`, podía "degradar" (por ejemplo, mostrar solo el joystick y avisar "Actualizá la app") en vez de obligar a actualizar.

- **Un control v1 ya publicado no puede degradar:** su código trata cualquier layout desconocido como `wait` ("Mirá la TV"). No hay forma de enseñarle otra cosa desde la TV. En un juego con `joystick_ab` ese jugador quedaría quieto toda la partida sin entender por qué, y la TV lo contaría como si jugara.
- **Un joystick sin botones tampoco sirve para jugar:** si el juego pide A para patear, "moverse sin patear" no es una versión reducida del juego, es perder seguro.
- Con `VERSION` 2 la TV rechaza al control v1 **al unirse** con `bad_version`, y el celular ya muestra "Esta app y la de la TV son de versiones distintas. Actualizá las dos." Es un error claro, en el momento correcto (antes de jugar), y no requiere código nuevo en los celulares viejos.

Así lo pide la skill `nuevo-layout`. Un test confirma que un `join` con `"v":1` se rechaza con `bad_version` y que el celular actual, ante un layout que no conoce, queda en la espera sin romper.

## Alternativas descartadas
- **No subir `VERSION` y degradar a `joystick`:** imposible en los celulares v1 (ver arriba). Solo serviría para celulares futuros.
- **Campo `fallback` en el mensaje `layout`** (ej. `{"layout":"joystick_ab","data":{"fallback":"joystick"}}`) para que los celulares **futuros** degraden solos ante un layout que no conocen: no ayuda con los v1 y hoy no hace falta. Queda anotado como opción si algún día hay celulares publicados de versiones distintas y se quiere sumar un layout sin obligar a actualizar.
- **Dos layouts separados (`stick_button` de un botón y otro de dos):** [JUEGOS.md](../JUEGOS.md) proponía `stick_button` (joystick + un botón). Un solo layout con A y B cubre los dos casos: un juego que solo usa A ignora B (el botón se ve igual, y el texto `b` vacío lo deja como secundario). Menos código en el celular y un solo ícono para aprender.
- **Botones fijos en las esquinas y joystick fijo:** el joystick flotante (se apoya donde cae el dedo) y la zona de botones entera como área de toque permiten jugar sin mirar el celular, que es lo que pasa mirando la TV.

## Consecuencias
- **Todos los celulares tienen que actualizarse** a la vez que la TV. Por eso conviene sumar en esta **misma** `VERSION` 2 los otros layouts previstos (`four_buttons`, inclinación…) antes de publicar: una sola actualización. Si otro cambio en paralelo también sube `VERSION`, al juntarlos tiene que quedar en 2, no en 3.
- `VirtualJoystick` suma la propiedad `hint` (la pista "Arrastrá…"), que `JoystickAB` acorta a "Arrastrá para moverte".
- Todavía no hay juego que use `joystick_ab`: la captura del celular es una vista previa (`tools/preview_joystick_ab.gd` → `docs/img/ctrl_joy_ab.png`). Cuando un juego lo use, `tools/capture_screens.gd` ya tiene el nombre `ctrl_joy_ab` en `CONTROL_SHOTS`.
