# Exploración de estilos visuales

Para elegir la dirección de arte final sin encargar arte todavía, `tools/capture_screens.gd` puede aplicar un **post-proceso de pantalla completa** al juego real (TV y celular) y guardar las mismas capturas de siempre. No es una maqueta: es la TV y el control de verdad, recorriendo una competencia, con un filtro encima.

- **El juego no cambia.** El post-proceso vive en `tools/styles/` y solo lo cargan las herramientas. Sin `--style` las capturas quedan idénticas a hoy.
- **Es una aproximación.** Un filtro puede cambiar colores, texturas y resolución, pero no la forma de las cosas (relieve de los botones, grosor de contornos, diseño de las mascotas). Sirve para *sentir* la dirección; el arte final se haría en `UiTheme`, las mascotas y el fondo, no con un filtro.

## Cómo generar las capturas

```bash
# Un estilo (pixel | neon | paper | flat). Sin --style: el estilo actual.
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/capture_screens.gd -- --out=/tmp/estilos/pixel --style=pixel

# Cambiar un parámetro del shader (se puede repetir):
…  -- --out=/tmp/estilos/pixel_270 --style=pixel --style-param=pixel_height=270

# Costo de cada estilo sobre el lobby de la TV:
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --audio-driver Dummy \
  -s res://tools/style_benchmark.gd -- --frames=300
```

Si hay otros procesos usando Godot en la misma máquina, conviene serializarlos: `flock /tmp/party-games-godot.lock bash script.sh`.

Las capturas para comparar son `lobby_full`, `game_intro`, `arena`, `paint`, `round_summary`, `final` (TV) y `ctrl_standing` (celular).

### Cómo funciona

`tools/styles/style_layer.gd` agrega un `CanvasLayer` en la capa 128 (encima de todo, incluida la pausa) con un `ColorRect` a pantalla completa y un shader `canvas_item` que lee lo ya dibujado con `hint_screen_texture` y lo redibuja. Se aplica al viewport de la TV (`root`) y al `SubViewport` del celular; cada viewport tiene su propia textura de pantalla. Los shaders trabajan en OKLab (un espacio de color donde brillo y tono se separan bien) y miden sus efectos en "píxeles de 1080p", así se ven igual en 720p, 1080p o 4K.

## Los estilos

### `pixel` · pixel art retro (`tools/styles/pixel.gdshader`)

- Baja la pantalla a una grilla de **640×360** (cada píxel de arte = 3×3 en 1080p), promedia 4 muestras por celda y cuantiza a **24 colores** de la paleta *Resurrect 64* (Kerrie Lake, publicada para uso libre en Lospec) con **dithering Bayer 4×4**.
- Paleta elegida por cercanía a los tokens de `UiTheme`: cielo (`#4d9be6`, `#8fd3ff`), tinta (`#2e222f`), foco amarillo (`#f9c22b`) y los 4 colores de jugador. Primero se probó un subconjunto de Endesga 32: no tiene celestes claros y el cielo quedaba gris.
- **360 y no 270:** a 480×270 las etiquetas `1P`–`4P` de la intro y las pistas de 24 px se vuelven manchas (ver `/tmp/estilos/pixel_270/game_intro.png`), y eso rompe la regla de distinguir jugadores sin depender del color. A 640×360 todo lo de ≥ 24 px se lee.
- Límites: el texto sigue siendo Fredoka pixelada, no una fuente pixel real; el degradé del cielo muestra bandas de tramado (es parte del look retro).

### `neon` · noche de arcade (`tools/styles/neon.gdshader`)

- Las **superficies** neutras (papel, cielo, pantallas de los marcadores) pasan a ser noche violeta; los **trazos** (letras, números) pasan a ser luz; los **colores vivos** (jugadores, bloques, foco) suben de brillo y saturación, y suman un **halo** tomado de dos mipmaps borrosos de la pantalla. La mezcla es de tipo "trama" (screen): nunca pasa de blanco, así los textos no se queman.
- Distinguir superficie de trazo sin saber qué es cada cosa es lo difícil. Se resolvió comparando cada píxel con el promedio de su zona (mipmaps de ~11 y ~24 px). Intentos descartados, porque dejaban "ecos" o manchas: 12 muestras sueltas en anillo, 8 muestras en estrella, un solo mipmap de 8 px (vaciaba los números de los marcadores).
- Límites que quedan: las caras blancas de las mascotas quedan como **visores oscuros** (se ve bien, pero en un arte final neon habría que diseñarlas así a propósito); los títulos blancos que caen sobre una nube quedan en parte "huecos"; en párrafos densos aparece alguna sombra horizontal sobre las letras. Todo sigue legible.

### `paper` · libro ilustrado (`tools/styles/paper.gdshader`)

- Contorno tembloroso (desplazamiento con ruido de ≈2 px que cambia 4 veces por segundo, como la animación dibujada a mano), colores 18 % desaturados y cálidos, blanco → papel crema, manchas de pigmento en las zonas de color (no en el papel ni en la tinta oscura), grano de papel y un leve oscurecimiento de bordes, como tinta acumulada.
- Es el que mejor conserva la legibilidad: no invierte nada y el contraste baja muy poco.

### `flat` · minimalista moderno (`tools/styles/flat.gdshader`), aproximación parcial

- Lo que sí se puede con un filtro: **cielo liso** (el degradé y las sombras que caen sobre él pasan a un solo color), **sin relieve de juguete** (el borde inferior oscurecido de botones, tarjetas y podios toma el color de arriba) y colores algo más claros y menos saturados.
- Lo que no se puede: contornos finos, más aire entre elementos, sin bloques ni nubes. Se probó afinar los contornos de tinta reemplazándolos por el color vecino, pero se comía el texto oscuro de los botones amarillos y los números de los podios, así que se descartó.
- **Se mantiene solo como referencia.** Para evaluar flat de verdad hay que hacerlo en `UiTheme` (`button_style` sin `border_width_bottom` ni sombra, `panel_style` sin sombra, `headline` sin contorno, `PartyBackground` sin bloques ni nubes). Es un cambio chico de tokens, pero toca el aspecto por defecto, así que queda fuera de esta exploración.

## Rendimiento

`tools/style_benchmark.gd` sobre el lobby de la TV, 300 cuadros por estilo, promedios en ms. Máquina de CI/nube **sin GPU**: Mesa llvmpipe (OpenGL por software), 1920×1080.

| Estilo | Cuadro total | Diferencia vs. actual | TIME_PROCESS | Dibujo CPU | Dibujo "GPU" |
|---|---|---|---|---|---|
| actual (sin shader) | 49,5 | — | 59,7 | 8,2 | 13,7 |
| solo copia de pantalla | 60,9 | +11,3 | 71,9 | 44,4 | 25,4 |
| pixel | 79,4 | +29,9 | 87,8 | 44,1 | 44,5 |
| neon | 151,4 | +101,9 | 160,5 | 56,8 | 114,8 |
| paper | 77,2 | +27,7 | 85,1 | 44,2 | 42,4 |
| flat | 76,6 | +27,0 | 86,3 | 44,9 | 41,1 |

Cómo leerla:

- **Los valores absolutos no sirven como presupuesto de TV**: todo corre por software (el juego sin filtro ya tarda 49 ms). Sirven para comparar estilos entre sí. Dos corridas seguidas dieron diferencias de ±2 ms.
- "Solo copia de pantalla" es un shader que no hace nada: aísla el costo de copiar la pantalla (`hint_screen_texture`), que pagan todos los estilos.
- **pixel, paper y flat** cuestan lo mismo (el shader dibuja unas 2 veces más que la escena). **neon** cuesta unas 7 veces lo que la escena: genera la cadena de mipmaps de la pantalla en cada cuadro y hace más conversiones de color por píxel.
- En una GPU real de TV (Mali, PowerVR) una pasada de 1080p con 3–5 lecturas de textura cuesta del orden de 1–3 ms, pero **hay que medirlo en el dispositivo** antes de usar cualquiera en el juego (presupuesto de `docs/PLAN.md`: ≤ 8 ms por cuadro). neon sería el primero en pasarse.
- Si se adoptara un estilo, no convendría dejarlo como post-proceso: paper, por ejemplo, se logra más barato con una textura de papel fija multiplicada y el temblor en los contornos al dibujarlos.

## Comparación para el producto

| | Actual (juguete) | pixel | neon | paper | flat |
|---|---|---|---|---|---|
| **Legibilidad a 3 m** | Muy buena | Buena a 640×360 (mala a 480×270) | Buena, con algunos títulos huecos y visores oscuros | Muy buena | Muy buena |
| **Foco del D-pad** | Anillo amarillo | Se ve (amarillo de la paleta) | Se ve mucho (halo) | Se ve (algo más apagado) | Se ve |
| **Jugadores sin depender del color** | 1P–4P + accesorio | Se mantiene a 360 | Se mantiene; las caras pasan a visores | Se mantiene | Se mantiene |
| **Costo del arte final** | Bajo: ya está hecho por código | Bajo a medio: sprites chicos y baratos de producir, fuente pixel y animación cuadro a cuadro | Medio: rediseño oscuro de toda la UI y de las mascotas, efectos de brillo | Medio: el código actual + texturas y contornos a mano; la mayor parte del look sale de un filtro barato | Bajo: tocar tokens, pero hay que diseñar el "aire" |
| **Diferenciación en tiendas** | Media: se parece a muchos party games de consola | Alta, pero en un nicho lleno (retro indie); comunica "para gamers" más que "para la familia" | Alta: capturas oscuras y saturadas que resaltan en la tienda | Alta y cálida: poco común en party games, comunica "familia" | Baja: parece una app |
| **Accesibilidad** | Contornos gruesos, alto contraste | Contraste bueno; el tramado puede molestar a algunas personas | Cómodo de noche con la luz apagada; el brillo y los colores sobre negro exigen revisar contraste | Contraste alto y sin fatiga; el temblor debe poder desactivarse (movimiento) | Contraste bueno; menos pistas de "esto se aprieta" sin relieve |
| **Costo por cuadro (post-proceso)** | — | Medio | Alto | Medio | Medio |

## Recomendación

**`paper` como dirección de arte**, con `neon` como posible tema nocturno más adelante.

- Es una evolución del estilo actual y no un reemplazo: mantiene mascotas, colores de jugador y contornos gruesos, que ya cumplen las reglas de legibilidad y accesibilidad (ver ADR 0004). El riesgo de romper la UI de TV es el más bajo de los cuatro.
- Se diferencia en la tienda (party game "de libro ilustrado", cálido, para la familia) sin necesitar un ilustrador para cada pantalla: textura de papel, contorno tembloroso y paleta crema se aplican una sola vez, sobre el dibujo por código que ya existe.
- Su costo se puede bajar bastante más que el del filtro medido acá (textura fija + temblor al dibujar) y no depende de mipmaps como neon.
- **pixel** queda segundo: se ve muy bien y el arte es barato, pero posiciona el juego como retro/indie, obliga a una fuente pixel real para textos chicos y a 270 líneas ya no se lee.
- **neon** es el más llamativo en capturas, pero es el más caro (rediseño oscuro de UI y mascotas) y el más pesado para una TV de gama baja.
- **flat** se descarta como dirección: es el que menos diferencia al producto, y un filtro no lo representa bien.

Antes de decidir conviene mirar las capturas en una TV real a 3 m, no en el monitor: el tramado de pixel y el grano de paper se perciben distinto a esa distancia.
