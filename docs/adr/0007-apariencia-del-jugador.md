# ADR 0007 · Apariencia del jugador: color y estilo elegidos desde el celular

- **Estado:** Aceptada
- **Fecha:** 2026-09-27

## Contexto
Hasta ahora la mascota de cada jugador salía de su lugar: 1P rojo con antena, 2P azul oso, 3P amarillo gato y 4P verde brote (`Protocol.player_color(slot)` y el estilo = `slot`). `PlayerAvatar` ya dibuja 7 estilos (Antena, Oso, Gato, Brote, Robot, Diablito, Conejo) y se probó una paleta de 10 colores con negro y blanco (`docs/img/mascotas_estilos.png`). Elegir tu personaje es parte de la gracia de un party game.

## Decisión
**Concepto:** el celular *pide* una apariencia y la TV la *decide*. Es el mismo esquema que el apodo: el control manda un dato cosmético, el host lo valida, lo recorta y lo confirma.

- **Paleta con índice** (`Protocol.MASCOT_COLORS`, 10 colores con nombre en `MASCOT_COLOR_NAMES`): por la red viaja el índice, nunca un color libre. Los 4 primeros son los de siempre, así el color por defecto de cada lugar no cambia. `Protocol.MASCOT_STYLES = 7` (un test verifica que coincide con `PlayerAvatar.STYLE_NAMES`).
- **Campos opcionales en `join`**: `color` y `style` (índices). Mensaje nuevo control → TV **`look`** `{color?, style?}` para cambiar en el lobby. Mensaje nuevo TV → control **`appearance`** `{color, style, taken}` con lo confirmado y los colores que usan los demás; `welcome` suma `colorIndex` y `style`.
- **Colores únicos:** en `join`, si el color pedido lo usa otro, se asigna el del lugar y, si tampoco está libre, el primero libre. En `look`, si está ocupado se conserva el propio (no salta a un color que nadie eligió). Los estilos se pueden repetir: la etiqueta 1P–4P sigue distinguiendo a los jugadores sin depender del color.
- **Solo en el lobby:** `look` se ignora si la fase no es `lobby` o si la competencia ya arrancó (`HostServer.can_change_look()`), porque el torneo copia color y estilo al empezar (`Tournament._remember`).
- En el host el jugador lleva `color` (Color), `color_index` y `style`; `get_players()` los expone y `player_updated(player)` avisa de un cambio. En juegos y pantallas el estilo se lee con `PlayerAvatar.style_of(p)` (si falta, el del lugar).
- **Celular:** `LookPicker` (flechas ◀ ▶ para el estilo y una grilla de 10 colores, botones de 128 px) al lado de la mascota grande, que hace de vista previa en vivo. La preferencia se guarda en `user://settings.cfg` (como el apodo) y se manda en el próximo `join`.

### Ejemplo
```
celular → TV   {"v":1,"type":"join","room":"K7QX","name":"Juli","color":9,"style":5}
TV → celular   {"v":1,"type":"welcome","playerId":4,…,"color":"16171d","colorIndex":9,"style":5,…}
TV → todos     {"v":1,"type":"appearance","color":9,"style":5,"taken":[0,5,7]}   (a cada uno, lo suyo)
celular → TV   {"v":1,"type":"look","color":0}          ← rojo, ya lo usa 1P
TV → celular   {"v":1,"type":"appearance","color":9,"style":5,"taken":[0,5,7]}   ← sigue en negro
```

## Seguridad
- **El celular elige solo la apariencia, nunca resultados.** `look` no toca puntos, puestos, lugar (`slot`), nombre ni fase. La TV sigue siendo autoritativa (ver `docs/SECURITY.md`).
- **Validación estricta** (`Protocol.parse_color_index`, `parse_style_index`, `parse_look`): solo números enteros (JSON trae floats: `3.0` vale, `3.5` no), finitos y en rango. Strings, bools, listas, `NaN` o `1e999` se descartan **sin rechazar** la conexión: un control viejo o con datos raros entra igual con la apariencia de su lugar.
- **Límite de frecuencia propio** para `look` (`LOOK_RATE_LIMIT_PER_SEC = 8`), porque cada cambio avisa a todos los celulares.
- El control tampoco confía en la TV: `parse_appearance` valida índices y limpia `taken`.

## Compatibilidad
Todo es opcional: los tipos nuevos se ignoran en versiones viejas y los campos nuevos de `join`/`welcome` también. **`VERSION` sigue en 1.** Con una TV vieja (sin `colorIndex` en `welcome`) el celular no muestra el selector.

## Alternativas descartadas
- **Color libre (hex) desde el celular:** permitiría colores ilegibles o iguales al fondo; con índice la TV controla el contraste.
- **Reenviar `welcome` para confirmar:** el cliente lo interpreta como "me uní" (sonido, guardar apodo); un mensaje propio es más claro.
- **Estilos únicos:** con 7 estilos y 4 jugadores alcanzaría, pero no hace falta para distinguirse (etiqueta 1P–4P + color único) y frustraría a dos amigos que quieren ser conejos.

## Consecuencias
- Las pantallas que muestran jugadores deben usar `p.color` y `PlayerAvatar.style_of(p)` (no `Protocol.player_color(slot)` ni `slot`). Un test revisa que todas las llamadas a `draw_mascot` de los juegos pasen el estilo del jugador.
- Blanco y negro obligan a cuidar el contraste: la mascota siempre lleva contorno de tinta y aclara las luces de los colores oscuros; sobre pisos claros se usa `UiTheme.on_light()` (ej. las baldosas de Pintar el piso).
- Queda pendiente que el lobby (`lobby_screen.gd`, `seat_card.gd`) dibuje `player.color` y `player.style` y se refresque con `player_updated` (HostMain ya llama `_refresh_lobby()`).
