# ADR 0009 · Arte de los juegos: escenario, tablero con volumen y marcador con mascotas

- **Estado:** Aceptada
- **Fecha:** 2026-09-27

## Contexto
La maqueta `docs/design/referencia_juego_pintar.webp` ("Pintar el piso") muestra cómo tienen que verse los juegos: un escenario de bloques y juguetes desenfocado alrededor, un tablero que "flota" (sombra, marco grueso de bloques con bisel y estrellas en las esquinas), baldosas con relieve y patrón por jugador, un marcador con una píldora por jugador `[1P | mascota | puntaje]` y un reloj en una píldora oscura con borde arcoíris, un globito `1P`–`4P` sobre cada mascota y power-ups con brillo. Los juegos se veían planos: cielo en degradé, marco de rectángulos, chips hexagonales. Todo tiene que seguir entrando en el presupuesto de la TV de gama baja (ADR 0006, `docs/PERFORMANCE.md`).

## Decisión
- **Un módulo de arte común**, `host/minigames/game_art.gd` (`GameArt`), que usan `MiniGame` (capas cacheadas) y cada juego. Tokens en `UiTheme`, sección "Juegos".
- **Escenario desenfocado como textura chica**: una imagen de 480×270 armada una vez por proceso con `Image` (cielo, nubes, piso de baldosas, pilas de bloques, bandera y estrellas) y desenfocada achicándola y agrandándola; se estira a toda la pantalla con filtro lineal. Si hay tablero, solo se pintan las franjas de alrededor (lo de abajo no se ve).
- **Tablero con volumen en un solo lote** (`GameArt.TriBatch`: lista de triángulos sin índices, un draw call): sombra proyectada difusa (solo el borde que asoma), anillo de tinta con borde suavizado, bloques del marco con bisel y canto de abajo, bloques con estrella en las esquinas, baldosas con labio oscuro y línea de luz, y la sombra que el marco hace sobre el piso. Figuras de pocos triángulos (esquinas ochavadas) y sin capas que se tapen de más: la GPU de la TV paga cada píxel.
- **Marcador**: la capa `_hud` dibuja píldoras, mascotas, etiquetas y reloj (casi nunca cambia) y su hija `_hud_text` solo los números y el texto del reloj. La mascota de cada píldora se dibuja **una vez** en un `SubViewport` chico al doble de tamaño (`GameArt.make_portrait`, `UPDATE_ONCE`) y el marcador pinta esa textura: 1 draw call en vez de ~15 por mascota, y sigue a `PlayerAvatar.draw_mascot` (si cambian las mascotas, cambia el marcador).
- **Globito 1P–4P y nombre** (`MiniGame.draw_player_tags`): todos los globitos en un lote y todas las letras después (contornos primero, rellenos después) para que el motor las junte. Si arriba lo taparía el marcador, el globito va al costado de la cabeza.
- **Lo fijo de cada juego se dibuja una vez** (`MiniGame.draw_static(fn)`): mesa de Ping Pong, paneles y cajitas de Reloj exacto, tribunas de Empujones. Carrera de toques arma su lote fijo una vez y lo vuelve a mandar en cada frame (`TriBatch.draw`).
- **Baldosas de Pintar el piso precalculadas** por jugador (`GameArt.tile_template`): relieve y patrón como triángulos locales; una fila entera es un `append_array` por baldosa y un draw call.
- **Brillo de premios** (`GameArt.add_glow`): degradé radial y rayos que giran, con formas y colores cacheados.

## Motivos
- Se parece a la maqueta en los 7 juegos con los mismos helpers (consistencia) y sin tocar reglas ni puntajes.
- Draw calls iguales o menores que antes en todos los juegos (Pintar el piso 170 → 83) y render parecido en xvfb; ver `docs/PERFORMANCE.md`.
- Jugadores distinguibles sin color: etiqueta en la píldora del marcador, en el globito y en los carteles; mascota con accesorio en el marcador; patrón de baldosa en Pintar el piso.

## Alternativas descartadas
- **Perspectiva real del tablero** (trapecio como en la maqueta): obliga a transformar posiciones, choques y dibujo de todos los juegos. Se usa sombra proyectada + canto de abajo para dar volumen sin tocar la lógica.
- **Desenfoque con shader en cada frame**: caro en una GPU Mali-G31 a pantalla completa. La textura chica ya desenfocada cuesta lo mismo que el cielo en degradé de antes.
- **Todo el marcador a una textura**: a 4K el texto se vería borroso (ver ADR 0006). Solo las mascotas van a textura, al doble de resolución (a 4K quedan 1:1).
- **Figuras redondeadas en todo**: cada rectángulo redondeado son ~36 triángulos; en baldosas y bloques del marco duplicaba el tiempo de render en xvfb. Se usan ochavas (6 triángulos) donde son chicas.

## Consecuencias
- ADR 0004 decía "sin texturas": ahora hay dos texturas generadas en tiempo de ejecución (el escenario, 480×270, y las mascotas del marcador, 168×208 cada una). Ninguna es un archivo: el APK no crece.
- El marcador depende de `SubViewport` (renderiza una vez al empezar el juego). Con el renderer `mobile`/`gl_compatibility` y la pantalla virtual funciona igual; en los tests (`--headless`) no dibuja nada pero no falla.
- `draw_static(fn)` no se vuelve a dibujar: lo que cambie durante la partida no puede ir ahí.
- Los contornos se ven suavizados solo donde se agregó el borde difuso (`TriBatch.feather_*`); las figuras de adentro siguen sin antialiasing, como antes.
