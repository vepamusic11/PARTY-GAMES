# ADR 0011 · Efectos de respuesta ("juice") en los juegos

- **Estado:** Aceptada
- **Fecha:** 2026-09-27

## Contexto

La revisión de calidad ([CALIDAD.md](../CALIDAD.md), sección 1.7) marcó que casi todos los juegos respondían "seco": juntar una estrella en Arena solo cambiaba un número, el bloque que aplasta en Esquivar no se sentía, al frenar en Reloj exacto no pasaba nada y los juegos que terminan por tiempo saltaban al resumen sin un momento final. Empujones tenía estrellitas, temblor y "+5", pero hechos a mano (varios draw calls por efecto) y sin forma de apagarlos.

**Concepto — *juice*:** responder a cada acción con más de lo estrictamente necesario —partículas, un número que salta, un temblor, un sonido— para que el jugador sienta que lo que hizo "pegó". No cambia reglas ni puntajes: cambia cómo se *siente* jugar. Referencias: *Juice it or lose it* (Jonasson y Purho, 2012) y *The Art of Screenshake* (Nijman, 2013).

Ejemplos concretos en el juego:

| Acción | Antes | Ahora |
|---|---|---|
| Juntar una estrella (Arena) | +1 en el marcador | Estrellitas, anillo de brillo, "+1" en una píldora del color del jugador, estrella nueva que aparece con rebote |
| Ser alcanzado (Esquivar) | Sonido | Pausa de impacto de 80 ms, sacudida leve, estrellitas; los bloques levantan polvo y hacen "tud" al caer; el aviso punteado titila cada vez más rápido |
| Frenar (Reloj exacto) | Sonido | Zoom sutil (+3,5 %) hacia tu cajita, tu número "se congela" con un golpe de escala, estrellitas a los costados (no tapan el número) |
| Pegarle a la pelota (Ping Pong) | Sonido | Estela del color de quien le pegó, pelota que se aplasta, chispas; si viene rápida, pausa de 50 ms |
| Tocar (Carrera de toques) | La mascota avanza | Polvo detrás de la mascota en cada toque |
| Pintar (Pintar el piso) | La baldosa crece | La baldosa salta (rebote y se levanta 7 px); power-up con sonido, brillo y "¡Brocha!"/"¡Rápido!" |
| Choque y caída (Empujones) | Temblor de la isla, estrellas y "+5" dibujados a mano | Chispas y estrellitas en lote, sacudida de cámara y pausa en los choques fuertes, chapuzón con gotas y sonido; la isla **titila 1,5 s antes** de achicarse, con un aviso sonoro en cada titileo |
| Fin del juego | Salto directo al resumen | "¡Tiempo!" / "¡Meta!" / "¡Gana 2P!" / "¡Último en pie!" con golpe de escala, confeti sobre los ganadores y mascotas festejando (1,4 s) |

## Decisión

- **Módulo compartido** `host/minigames/juice.gd` (`Juice`): un nodo hijo interno de cada `MiniGame` que se crea la primera vez que el juego lo pide (`juice()`; un juego sin efectos no paga nada). Recetas con nombre (`sparkles`, `shine`, `dust`, `sparks`, `confetti`, `splash`, `stop_dust`), números flotantes (`float_text`), cartel del final (`banner`) y "cámara" (`shake`, `zoom_punch`).
- **Partículas en lote con pool fijo** (`core/ui/widgets/fx_particles.gd`, `FxParticles`): arreglos empaquetados de tamaño fijo (`UiTheme.FX_MAX_PARTICLES` = 192); emitir ocupa el lugar siguiente en ronda y, si está lleno, pisa el más viejo. **Un draw call** por sistema (`canvas_item_add_triangle_array`) con formas precalculadas ubicadas con `Transform2D * PackedVector2Array` (C++). Sin partículas vivas apaga su `_process`. Tipos: estrellita con contorno, chispa, gota, polvo, papelito de confeti y anillo.
- **Cámara sin redibujar**: la sacudida y el zoom cambian el `transform` del juego entero (mover un nodo no redibuja nada). Un poco de zoom tapa los bordes que la sacudida dejaría al descubierto. El marcador recibe la transformación inversa: **no tiembla ni se agranda**. Empujones dejó su temblor propio (redibujaba 5 capas de la isla por golpe) y usa esta cámara.
- **Pausa de impacto** (`MiniGame.hit_stop` / `hit_stopped`): la lógica del juego se congela 50–80 ms en el golpe (Esquivar al ser alcanzado, choques fuertes de Empujones, pelotazos rápidos de Ping Pong). No se usa en Reloj exacto: congelaría el reloj de los demás.
- **Momento final** (`MiniGame.finish_after` / `celebrate`): cartel con golpe de escala, silbato (`time_up`), confeti sobre los ganadores (`is_celebrating`, `celebrate_hop`) y recién después `finished`. Los juegos que ya tenían su pausa final (Pintar el piso, Empujones, Reloj exacto) solo llaman `celebrate`. `finish()` directo sigue funcionando igual (el host y los tests lo usan).
- **Cuenta regresiva con golpe de escala** (`MiniGame.draw_countdown`): los "3, 2, 1, ¡YA!" de los cuatro juegos que la tenían, en un solo lugar.
- **"Reducir movimiento"** (`UiTheme.reduce_motion`, en el menú de pausa: "Movimiento: Normal/Reducido", guardado en `user://tv_settings.cfg` sección `[video]`): sin sacudida, sin zoom, sin golpes de escala y 35 % de las partículas. La pausa de impacto se mantiene (no es movimiento).
- **Tokens** en `UiTheme`, sección "Efectos": duraciones `DUR_*`, curva `EASE_POP` (rebote *back out*), medidas `FX_*` y colores (`FX_DUST`, `FX_SPARK`, `FX_SHINE`, `FX_WATER`). El confeti usa `UiTheme.BRICKS`.
- **Sonido**: recetas nuevas en `Sfx.RECIPES` (`time_up`, `thud`, `splash`, `warn`, `power`), sintetizadas como las demás.
- **Números flotantes legibles con cualquier color**: píldora del color del jugador con contorno de tinta y el texto en `UiTheme.text_on(color)`; van arriba del globito 1P–4P, no lo tapan.

## Motivos

- Un solo módulo = mismos efectos en todos los juegos (consistencia) y un juego nuevo los usa con una línea (`juice().sparkles(pos)`).
- Presupuesto de la TV: un draw call para todas las partículas y cero redibujos para la cámara. Medido con `tools/benchmark.gd` (ver [PERFORMANCE.md](../PERFORMANCE.md), sección "Efectos").
- Accesibilidad: las [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/) piden poder apagar el temblor de pantalla y el movimiento fuerte.

## Alternativas descartadas

- **`CPUParticles2D`/`GPUParticles2D`**: un nodo (y un draw call) por emisor; para estallidos en distintos lugares a la vez hacen falta varios, y necesitan texturas. `GPUParticles2D` además no es confiable en las GPU de TV de gama baja con el renderer de compatibilidad.
- **Una partícula = un diccionario en un `Array`** (como hacía Empujones): crea basura en cada estallido y el costo no tiene techo.
- **`Camera2D`** para la sacudida: la TV no usa cámaras y la UI del host (pausa, transición) vive en el mismo viewport; mover el nodo del juego es más simple y no afecta al resto.
- **Congelar con `Engine.time_scale`**: es global (frenaría la transición, la pausa y el celular en las pruebas).

## Consecuencias

- Los juegos que terminaban en el acto (Arena, Esquivar, Carrera de toques, Ping Pong) ahora esperan `UiTheme.DUR_FINALE` (1,4 s) antes de emitir `finished`; mientras tanto ignoran el input. El test de Esquivar espera el festejo.
- `MiniGame` tiene un hijo interno más (`Juice`) solo cuando se usan efectos.
- Mientras dura una sacudida o un zoom el `transform` del juego no es la identidad: si algo del host midiera posiciones del juego en ese instante, verá el desplazamiento (hoy nada lo hace).
- Con un pool lleno el efecto más viejo desaparece antes de tiempo: se nota solo con cientos de partículas a la vez, que no pasa en los juegos actuales.
