# Calidad de producto: auditoría y backlog

Auditoría del 27/09/2026 sobre el commit `4d4997f` (capturas de [docs/img](img/) y referencias de [docs/design](design/)). Responde a "cómo trabajar la calidad del diseño, qué se puede mejorar y qué se puede sumar para dar más calidad al producto".

**"Nivel empresarial"** acá no significa "más cosas", sino **calidad que se puede medir y que no retrocede**: cada criterio tiene un número o una prueba automática, y lo que ya se logró queda protegido en la CI.

*Ejemplo:* "los textos se leen a 3 m" es una opinión; "ningún `Label` de la TV mide menos de 24 px y todo texto tiene contraste ≥ 4,5:1 con su fondo, verificado por un test" es un criterio de nivel empresarial.

> Mientras se escribía esto, otros agentes estaban mejorando el lobby, las mascotas, el fondo, las miniaturas de los juegos y el celular. Algunas brechas de la sección 1 pueden quedar cerradas cuando se integren; sirven igual como **criterios para revisar** esos cambios.

## Resumen

1. **La base es muy buena para un proyecto dibujado por código:** sistema de tokens, 1P–4P en todas partes, patrones en Pintar el piso, foco del D-pad visible, intro de cada juego, pausa segura y presupuestos de rendimiento medidos.
2. **La brecha con las referencias es de "volumen y riqueza":** las referencias tienen sombreado 3D, miniaturas ilustradas de cada juego, un fondo con profundidad y tipografía tipo sticker; lo actual es más plano y repite el mismo tablero en 3 juegos.
3. **Hay 4 errores de legibilidad concretos**, todos por los colores nuevos blanco y negro ([ADR 0007](adr/0007-apariencia-del-jugador.md)): nombres invisibles en Carrera de toques, Reloj exacto y Esquivar, y "¡Listo!" en verde con contraste bajo.
4. **Falta "juice"** (respuesta exagerada y placentera a cada acción) en casi todos los juegos, y **no hay música**.
5. **La calidad visual no está protegida por la CI:** las capturas se generan, pero nadie las compara. Se propone una regresión visual con las herramientas que ya existen (sección 5).

---

## 1. Diseño visual

### 1.1 Lobby: brechas con la referencia

Referencia: [`design/referencia_lobby.webp`](design/referencia_lobby.webp). Actual: [`img/lobby_full.png`](img/lobby_full.png).

| Zona | Referencia | Hoy | Qué hacer |
|---|---|---|---|
| **Mascotas en las tarjetas** | Ocupan ~70 % del alto de la tarjeta, se "salen" un poco del borde y saludan | ~40 % del alto, centradas en un halo | Mascota más grande, anclada abajo y cortada por la tarjeta: se siente como "gente sentada", no como un ícono |
| **Tarjeta de jugador** | Degradé del color del jugador de arriba a abajo | Fondo blanco con halo concéntrico | Degradé suave del color (con `on_light` para blanco/negro) |
| **Miniaturas de juegos** | Cada juego tiene su escena: mesa de ping pong, reloj, arena con estrellas | Todas iguales: piso a cuadros en perspectiva + ícono del control; solo cambia el color | Miniatura propia por juego (`MiniGame.draw_thumbnail()` o sprite). Es la brecha que más se nota a 3 m |
| **Código de sala** | Fichas grandes con relieve y brillo, ~2× el tamaño actual | Fichas planas de 90×112 px | Fichas más altas y con volumen: es lo que la gente tiene que leer desde el sillón |
| **Fondo** | Patio de juegos 3D desenfocado (profundidad de campo): el fondo "se aleja" | Torres de bloques nítidas y saturadas que compiten con las tarjetas | Bajar saturación y contraste del fondo detrás de los paneles, o un velo claro; nunca más contraste que el primer plano |
| **Títulos de sección** | "¿A qué jugamos?" blanco con contorno oscuro (estilo sticker) | Tinta sobre cielo, peso normal | Usar `UiTheme.headline` en todos los títulos de sección |
| **Botón "¡A jugar!"** | Muy grande, con brillo y rayitas de "energía" | Botón amarillo estándar | Botón primario con variante "héroe": más alto, brillo que late y rayitas cuando está habilitado |
| **Mascota que saluda** | Grande, cortada por el borde inferior izquierdo | Chica, entera | Más grande y cortada por el borde: da escala y personalidad |
| Barra de desarrollo (Tests, CI…) | Está | No está | ✅ Correcto no copiarla (ver [design/lobby.md](design/lobby.md)) |

### 1.2 Mascotas: brechas con la referencia

Referencia: [`design/referencia_mascotas.webp`](design/referencia_mascotas.webp). Actual: [`img/mascotas.png`](img/mascotas.png) y [`img/mascotas_estilos.png`](img/mascotas_estilos.png).

| Aspecto | Referencia | Hoy | Qué hacer |
|---|---|---|---|
| **Volumen** | Sombreado en degradé (luz arriba a la izquierda, sombra abajo), brillo especular grande y luz de borde (*rim light*) | Color plano + un brillo | Degradé radial en el cuerpo y la cabeza; es lo que da el aspecto "de juguete de plástico" |
| **Contorno** | Del mismo tono que el cuerpo, más oscuro | Tinta azul marino para todos | Contorno = color del cuerpo oscurecido (para negro y blanco, tinta). Suaviza y "une" la figura |
| **Ojos** | Grandes, con dos brillos | Chicos, un brillo | +20 % de tamaño y segundo brillo: se leen mejor a 3 m y dan más expresión |
| **Salto** | Brazos arriba, cuerpo apenas estirado | Cuerpo muy estirado verticalmente, brazos quietos | Menos *stretch* y brazos arriba (la pose comunica "¡bien!", no "me estiraron") |
| **Aterriza** | Aplastado y ancho, ojos cerrados de impacto | Aplastado | Bien; sumar polvito (ver 1.7) |
| **Triste** | Cejas caídas, boca ondulada | Lágrima y boca | Bien; sumar cejas |

### 1.3 Resto de pantallas, captura por captura

Contrastes medidos con la fórmula de WCAG 2 sobre los tokens de `UiTheme` y `Protocol.MASCOT_COLORS`. **Concepto — contraste:** relación entre la luminancia del texto y la del fondo, de 1:1 (invisible) a 21:1 (negro sobre blanco). WCAG pide 4,5:1 para texto normal y 3:1 para texto grande.

| Captura | Qué se encontró | Arreglo |
|---|---|---|
| [tap_race](img/tap_race.png) | **"Tomi" blanco sobre pastilla blanca: 1,07:1, invisible** | Helper `UiTheme.text_on(bg)` que elige tinta o blanco según el contraste, y usarlo en todo nombre sobre color de jugador |
| [stop_clock](img/stop_clock.png) | **"Juli" en tinta sobre tarjeta negra: 1,14:1, invisible**; el visor "--.--" casi no se separa de la tarjeta | Ídem `text_on`; borde claro del visor en tarjetas oscuras |
| [dodge](img/dodge.png) | Los eliminados quedan semitransparentes **y su nombre también**: "Pablo" y "Tomi" no se leen | Mantener el fantasma pero el nombre opaco con un ícono de "fuera" (✕), así se sabe quién cayó |
| [lobby_full](img/lobby_full.png) | "¡Listo!" en `SUCCESS` sobre blanco: **2,74:1** (no llega ni a 3:1); "Solo 2 jugadores" en rojo sobre gris: 3,49:1 | Token `SUCCESS_TEXT` más oscuro (~#1C8A52) para texto; `DANGER` solo en íconos o con fondo |
| [arena](img/arena.png), [dodge](img/dodge.png), [tap_race](img/tap_race.png) | **Mismo tablero a cuadros** en 3 juegos; mascotas chicas (~80 px en 1080p) en un campo enorme y vacío | Un "tema" por juego (arena: pasto con flores; esquivar: patio de obra con conos) y mascotas +25 % |
| [arena](img/arena.png) | El nombre sobre la mascota no tiene 1P–4P; en [sumo](img/sumo.png) sí ("1P Pablo"). Como los estilos se pueden repetir ([ADR 0007](adr/0007-apariencia-del-jugador.md)), la etiqueta es **lo único** que distingue a dos conejos del mismo color… de distinto tono | Una sola función para la "chapita" del jugador (tag + nombre) usada por todos los juegos |
| [pingpong](img/pingpong.png) | Sin fondo de fiesta; banda blanca inferior que corta de golpe; colores de la mesa fuera de `UiTheme` | Fondo común de juego, tokens `TABLE_*` |
| [final](img/final.png) | Jerarquía buena. "4° Pablo · 330 pts" y "Se jugó: …" en 24 px apretados | 4° como un escalón bajo con su mascota; "Se jugó" puede ir en el celular |
| [game_intro](img/game_intro.png) | Muy buena: control dibujado, jugadores con tag, cuenta regresiva | Faltan: "tocá tu botón para decir ¡listo!" (sección 2) |
| [round_summary](img/round_summary.png) | Muy buena: mascota triste/feliz, puntos grandes, puesto | Animar la entrada (ver 1.7) |
| [splash](img/splash.png) | Neón oscuro (IO-GAMES) vs. juguete celeste (PARTY-GAME): dos lenguajes | Correcto separar estudio y juego; falta una transición que los una (barrido de bloques desde el logo) y un sonido de marca |
| [ctrl_join](img/ctrl_join.png) | Formulario técnico: el primer campo es una IP (`127.0.0.1`) | Con QR (Fase B) desaparece; mientras tanto, lista de TVs primero, IP detrás de "¿No aparece?" |
| [ctrl_joy](img/ctrl_joy.png) | Pantalla vacía sin identidad; **"86 ms"** es un dato de desarrollo; **"Salir"** arriba a la izquierda, donde cae el pulgar | Fondo teñido con el color del jugador, joystick con el color, latencia solo en modo desarrollador, "Salir" con confirmación o mantener apretado |
| [ctrl_look](img/ctrl_look.png) | Colores ocupados tachados (no solo con color ✅). **Grafito y Negro casi iguales** (ver 1.8) | Reemplazar Grafito por un color más distinto (ej. marrón o lima) |

### 1.4 Consistencia del sistema visual

**Concepto — design tokens:** constantes con nombre de intención en lugar de valores sueltos. `UiTheme` ya los usa para colores; faltan tres familias.

| Qué falta | Hoy | Propuesta |
|---|---|---|
| **Escala tipográfica** | Tamaños sueltos en las pantallas: 24, 26, 28, 30, 32, 34, 38, 40, 44, 56, 60, 64 | 6 pasos: `TEXT_HINT 24 · TEXT_BODY 30 · TEXT_LABEL 36 · TEXT_TITLE 48 · TEXT_HEAD 64 · TEXT_HERO 96` |
| **Movimiento** | Duraciones y curvas en cada tween | `DUR_FAST 0.12 · DUR_MED 0.25 · DUR_SLOW 0.45` y `EASE_POP` (back out), `EASE_MOVE` (cubic in-out) |
| **Espaciado** | Márgenes y separaciones a mano | Escala de 8: `SPACE_1 8 … SPACE_6 64` |
| Colores sueltos | 19 `Color(...)` fuera de `UiTheme` (ej. mesa de ping pong `#2F6FDB`, visor `#15182A` en `score_pedestal.gd`, `accent` de cada juego en hex) | Moverlos a tokens (`TABLE_BLUE`, `SCREEN_DARK`, `GAME_ACCENTS`) |
| Nombre del producto | Logo "PARTY-GAME", README "Party Games", paso 1 "Abrí PARTY-GAME" | Decidir uno (sección 6) y usar un token `PRODUCT_NAME` |

*Ejemplo:* hoy, para que todos los textos secundarios pasen de 28 a 30 px hay que buscar números en 8 archivos; con `TEXT_BODY` es una línea.

### 1.5 Jerarquía

**Concepto:** jerarquía visual es el orden en que el ojo recorre la pantalla. Se prueba con el "test de entrecerrar los ojos": mirar la captura borrosa y ver qué se nota primero.

*Ejemplo en el lobby:* lo primero que alguien que llega necesita es **el código** (o el QR) y lo segundo, **si ya está adentro** (su tarjeta). Hoy, entrecerrando los ojos, lo más fuerte es la grilla de 7 tarjetas de juegos de colores; el código compite con las torres del fondo. En la referencia el código y las mascotas ganan.

Reglas propuestas: **un solo** elemento "héroe" por pantalla (lobby: código/QR; intro: título; resumen: puntos; podio: ganador), el fondo siempre con menos contraste que el contenido y el botón primario siempre en `ACCENT`.

### 1.6 Legibilidad a 3 m

**Concepto — ángulo visual:** lo que importa no es el tamaño en píxeles sino cuánto ocupa en el ojo. En una TV de 50" a 3 m, un texto de 24 px (en 1080p) mide 14 mm de alto y subtiende ~16 minutos de arco: es el mínimo cómodo para leer.

**Prueba práctica sin TV:** las capturas de `docs/img` (960 px de ancho) vistas en un monitor de 24" a 60 cm ocupan casi el mismo ángulo (~25°) que una TV de 50" a 3 m (~21°). **Si en `docs/img` no se lee, en la TV tampoco.** Así se detectaron los 4 errores de 1.3.

Criterios: pistas ≥ 24 px, texto de lectura ≥ 30 px, nombres de jugador ≥ 32 px en juegos, contraste ≥ 4,5:1 (o ≥ 3:1 si es ≥ 36 px o lleva contorno de tinta).

### 1.7 Animación y *juice*

**Concepto — juice:** que el juego responda a cada acción con más de lo necesario: rebote, partículas, sonido, vibración. La charla de referencia es *Juice it or lose it* (Jonasson y Purho, 2012), que toma un Breakout aburrido y lo vuelve divertido sin cambiar reglas; y *The Art of Screenshake* (Nijman, Vlambeer, 2013).

| Técnica | Qué es | Ejemplo en el juego | ¿Está? |
|---|---|---|---|
| **Anticipación** | Avisar antes de que pase algo | Esquivar marca con sombra punteada dónde cae el bloque | ✅ Esquivar (el aviso titila cada vez más rápido) · ✅ Empujones (el borde titila 1,5 s antes de achicarse, con un aviso sonoro) |
| **Easing** | Moverse con aceleración, no a velocidad constante | Las tarjetas del resumen entran con rebote (`EASE_POP`) en vez de aparecer | Parcial (transiciones) |
| **Squash & stretch** | Aplastar/estirar al chocar o saltar | Mascotas al saltar y aterrizar | ✅ Mascotas · ✅ pelota de Ping Pong, estrellas de Arena (aparecen con rebote), baldosas de Pintar el piso (saltan) |
| **Partículas** | Chispas, polvo, confeti | Estrella que explota en brillitos al tomarla; polvo al aterrizar; salpicadura al caer al agua en Empujones | ✅ Todos los juegos (`FxParticles`, un draw call; ver [ADR 0011](adr/0011-efectos.md)) |
| **Screen shake** | Temblor de cámara en impactos | Golpe fuerte en Empujones | ✅ Empujones · ✅ Esquivar (cámara; el marcador no tiembla) |
| **Hit-stop** | Congelar 60–100 ms en el momento clave | Reloj exacto: al frenar, el número se congela, hace *zoom* y suena | ✅ Esquivar, Empujones, Ping Pong · ✅ Reloj exacto (número con golpe de escala + zoom, sin congelar el reloj de los demás) |
| **Números flotantes** | "+1" que sube y se desvanece | "+5" en Empujones | ✅ Empujones, Arena, Ping Pong, Pintar el piso (power-ups), en una píldora del color del jugador |
| **Micro-interacciones** | Respuesta a cada gesto de UI | El foco del D-pad "rebota" al moverse; el check de una tarjeta hace *pop*; la ficha del código se sacude si alguien pone uno incorrecto | Parcial (sonido `tick`) |
| **Conteo animado** | Los números suben de a poco | Total del resumen que cuenta de 70 a 170 con `tick` | ❌ |

Condiciones: el juice respeta el presupuesto de [PERFORMANCE.md](PERFORMANCE.md) (partículas propias en un `ShapeBatch`, no un nodo por partícula) y se puede bajar con **"Reducir movimiento"** (sin shake ni destellos), que además es una pauta de accesibilidad. *Hecho en los 7 juegos:* módulo `Juice` + `FxParticles`, momento final con "¡Tiempo!" y festejo, y "Movimiento: Reducido" en el menú de pausa ([ADR 0011](adr/0011-efectos.md)).

### 1.8 Daltonismo: la paleta de 10 colores

Se simularon los 10 colores de `Protocol.MASCOT_COLORS` (con el amarillo dorado #F5B82C y el verde pasto #45C35A de la maqueta, desde el 29/09/2026) con las matrices de Machado et al. (2009) y se midió la distancia en OKLab (0 = iguales; por debajo de ~0,08 se confunden a simple vista). Pares más cercanos:

| Visión | Pares que se confunden |
|---|---|
| Normal | Grafito/Negro 0,095 |
| Deuteranopía (la más común, ~5 % de los hombres) | **Rosa/Celeste 0,055 · Azul/Violeta 0,058** · Rojo/Verde 0,089 |
| Protanopía | **Amarillo/Verde 0,047 · Azul/Rosa 0,073** · Azul/Violeta 0,094 |
| Tritanopía | **Verde/Celeste 0,050** · Grafito/Negro 0,094 · Azul/Verde 0,099 |

Es aceptable **porque** el juego no depende del color (1P–4P, patrones en Pintar el piso, colores únicos). Pero conviene: (a) cambiar Grafito; (b) un test que falle si un color nuevo queda a menos de 0,05 de otro en visión normal; (c) sumar a `tools/styles/` un filtro `--style=deutan|protan|tritan` para mirar las capturas como las ve una persona daltónica (misma infraestructura que [ESTILOS.md](ESTILOS.md)).

---

## 2. UX de punta a punta

**Concepto — recorrido del usuario (*user journey*):** listar cada momento desde que alguien prende la TV hasta que apaga, y preguntar en cada uno "¿qué siente?, ¿qué puede salir mal?".

| Momento | Hoy | Problema | Propuesta | Fase |
|---|---|---|---|---|
| **Primera vez** | Splash → lobby | Nadie explica que el celular es el control | Tarjeta de bienvenida la primera vez: 3 dibujos (bajá la app → escaneá → jugá) | D |
| **Unirse** | 3 pasos: app, elegir TV, apodo + código | 4 decisiones antes de jugar; en iPhone depende del multicast | **QR** en la TV con IP y código ([Kenyoni QR](https://github.com/kenyoni-software/godot-addons), MIT) + *deep link* `partygame://join?ip=…&code=…`; si la app no está, el link lleva a la tienda. Apodo sugerido al azar ("Pingüino veloz") | B |
| **Código incorrecto** | Mensaje claro en el celular ✅ | La TV no se entera | La TV sacude la ficha del código (micro-interacción) | A |
| **Llega tarde** | "Hay una partida en curso. Esperá a que termine." | En una fiesta alguien llega a mitad | "Entrás en el próximo juego": queda en cola y la TV lo muestra | C |
| **Desconexión** | El celular dice "Reconectando…"; la TV solo suena `back` | Los demás no saben por qué Pablo no se mueve | Cartel en la TV: "1P Pablo se desconectó · esperando 15 s" con la mascota dormida; si no vuelve, un bot lo reemplaza (con bots) | A |
| **Pausa** | "Atrás" abre la pausa con confirmación ✅ | Solo "Sonido" como ajuste | Sumar volumen de música/efectos, "Reducir movimiento", tamaño de texto y "¿Cómo se juega?" del juego actual | D |
| **Durante el juego** | Intro con cuenta regresiva | Arranca aunque alguien no miró | **Ready check:** cada celular muestra "¡Listo!" y la TV arranca cuando todos tocaron (o a los 10 s) | A |
| **Fin de partida** | Podio + "Jugar otra vez" / "Cambiar juegos" | Termina seco | Momento de gloria de 5 s del ganador (baile + música), estadísticas divertidas ("Juli: 42 estrellas en total") y "revancha" con un toque desde los celulares | A |
| **Salir** | "Salir" siempre visible en el celular | Toque accidental | Mantener 1 s o confirmar | A |

### 2.1 Accesibilidad

Fuente principal: [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/) (niveles básico, intermedio y avanzado según alcance, impacto y costo). Las cuatro quejas más comunes que reportan son remapeo, tamaño de texto, daltonismo y subtítulos.

| Tema | Hoy | Propuesta | Ejemplo |
|---|---|---|---|
| Daltonismo | 1P–4P + accesorio + colores únicos + patrones en Pintar el piso ✅ | Ver 1.8; mantener la regla "nunca solo color" en cada juego nuevo | En un futuro "Fútbol 2 vs 2", los equipos se distinguen por camiseta lisa vs. rayada, no solo rojo vs. azul |
| Alto contraste | No | Ajuste que apaga el fondo animado, pone paneles opacos y contorno de tinta de 4 px en todo | En Arena, el campo pasa a blanco liso y las estrellas llevan contorno negro grueso |
| Tamaño de texto | Fijo | Ajuste "Texto grande" (+25 %) que multiplica la escala tipográfica (1.4) | Solo es posible si los tamaños son tokens |
| Subtítulos de sonido | No hay voz, pero sí sonidos que informan | **Regla: todo sonido que da información tiene un equivalente visual** | El `go` de "¡YA!" ya tiene texto ✅; el `hit` de eliminado en Esquivar necesita el ✕ sobre el nombre |
| Movimiento | Temblor, destellos | "Reducir movimiento" (1.7) | Sin shake en Empujones; el confeti cae más lento |
| Motricidad | Joystick relativo "arrastrá en cualquier lugar" ✅ | Opción "mantener = tocar repetido" en Carrera de toques | Alguien con poca fuerza en los dedos puede competir |
| Tiempo | Intro de 5 s | Ready check (arriba) | Nadie queda afuera por leer lento |

### 2.2 Localización

**Concepto:** traducir no es solo cambiar textos: también fechas, números ("10,00" vs "10.00"), largos distintos y banners con texto.

- **Hoy:** todos los textos están escritos en español dentro del código ("¡A jugar!", "Reconectando…"). Godot traduce con `tr()` y archivos `.po` o `.csv`; los `Label` se traducen solos si el texto es una clave.
- **Paso 1 (barato):** envolver todo texto visible en `tr()` y extraerlo a `locale/es.po`. Un test que busque strings con letras en `UiTheme.label(…)` sin `tr()`.
- **Paso 2:** **pseudo-localización.** *Ejemplo:* un idioma falso que alarga todo un 35 % y agrega acentos ("¡À jûgàr! ·····"). Si las capturas con ese idioma no se cortan, el inglés y el portugués tampoco se van a cortar. Godot lo trae (`internationalization/pseudolocalization`).
- **Paso 3:** en / pt, y **un banner de TV por idioma**: Android pide que el banner de 320×180 incluya el texto y tenga una versión por idioma ([Android TV](https://developer.android.com/training/tv/start/start)).
- Los nombres de jugador **no** se traducen ni pasan por `tr()` (regla de seguridad de `CLAUDE.md`).

---

## 3. Audio

**Antes:** 16 efectos sintetizados por código ([ADR 0005](adr/0005-sonido-sintetizado.md)) y vibración, **sin música**: el silencio en el lobby se sentía como "esto no arrancó".

**Hecho ([ADR 0015](adr/0015-musica-y-mezcla.md)):** música CC0 de Juhani Junkala por pantalla y por energía del juego, con fundido cruzado; buses `Music` y `SFX` con volumen en la pausa; *ducking* de 6 dB con `go`, `win`, `fanfare`, `hit` y `lose`; logos sonoros propios de IO-GAMES y PARTY-GAME; clics de menú de Kenney (CC0). Créditos en [CREDITS.md](../CREDITS.md). Pendiente: *stinger* de intro, capa extra en los últimos 10 s y bus `UI` separado.

**Hecho ([ADR 0017](adr/0017-estilos-de-musica.md)):** "Estilo" de música en la pausa: PARTY-GAME (temas del dueño, por defecto), Fiesta y Latino (compuestos por el juego, 0 MB), Relajado (CC0 de Abstraction), Retro y Sin música; se guarda en los ajustes de la TV. Estilos nuevos igualados en LUFS (≤ 1 dB de diferencia). Música total: 7,7 MB.

### 3.1 Música

| Momento | Qué suena | Por qué |
|---|---|---|
| Splash IO-GAMES | **Logo sonoro** de 2 s (3–4 notas) | Identidad de marca: lo mismo que el "tudum" de una plataforma de series |
| Lobby | Loop tranquilo y alegre | Llena el silencio mientras la gente se une |
| Intro del juego | *Stinger* (golpe musical corto) | Marca "empieza algo" |
| Juego | Loop con energía, uno por "familia" (acción, precisión, carrera) | Los últimos 10 s: versión más rápida o capa extra de percusión |
| Resumen | Jingle corto ganador | |
| Podio | Fanfarria + loop de festejo | |

**Concepto — música por capas:** el mismo tema en varias pistas (base, percusión, melodía) que se suben o bajan según lo que pasa. *Ejemplo:* en Empujones, cuando quedan 2 jugadores, entra la percusión. Es barato (un solo tema) y se siente "vivo".

### 3.2 Mezcla

- **Buses:** `Master`, `Music`, `SFX`, `UI` (Godot `AudioServer`). Hoy todo sale por el mismo.
- **Ducking:** la música baja ~6 dB 300 ms cuando suena `win` o la cuenta regresiva. *Ejemplo:* el "¡YA!" se escucha claro aunque la música esté fuerte.
- **Sonoridad:** normalizar todo a un mismo nivel medido en LUFS (por ejemplo con el filtro `ebur128` de ffmpeg), para que un efecto no "salte" más fuerte que otro, y probar en parlantes de TV (sin graves).
- **Identidad por jugador:** cada estilo de mascota con su "voz" (la misma receta con otro tono). *Ejemplo:* al unirse, el Oso suena grave y el Conejo agudo; se distingue quién entró sin mirar.

### 3.3 Fuentes CC0 (ver [RECURSOS.md](RECURSOS.md))

| Fuente | Licencia | Para qué |
|---|---|---|
| [Juhani Junkala · Retro Game Music Pack](https://archive.org/details/JuhaniJunkalafiveactionchiptunes) (5 loops, entre ellos "Title Screen" y "Ending") | CC0 | Lobby y juegos en la primera versión; combina con los efectos chiptune actuales |
| [Kenney · Music Jingles](https://kenney.nl/assets/music-jingles) (85 jingles: 8-bit, pizzicato, saxo, steel drum) *(indirecto: confirmado por el [Asset Library de Godot](https://godotengine.org/asset-library/asset/1839))* | CC0 | Stingers, resumen y podio |
| Kenney UI Audio / Interface Sounds | CC0 | Reemplazo de `tick`, `select`, `back` si se quiere un sonido menos "chip" |
| [Sonniss GDC Bundle](https://gdc.sonniss.com/) | Royalty-free, sin atribución | Impactos, agua, multitud (Empujones, podio) |

**Integración sin romper nada:** `Music.play("lobby")` con la misma forma que `Sfx.play`, archivos `.ogg` en `assets/audio/` y cada uno anotado en `CREDITS.md`. **Presupuesto:** a ~128 kbps, un minuto de OGG pesa ~1 MB; con el APK ≤ 40 MB, reservar ≤ 8 MB de música (~8 minutos de loops).

---

## 4. Contenido y rejugabilidad

### 4.1 Variedad

| | Arena | Ping Pong | Carrera | Reloj | Esquivar | Empujones | Pintar |
|---|---|---|---|---|---|---|---|
| Control | Joystick | Slider | Botón | Botón | Joystick | Joystick | Joystick |
| Emoción | Codicia | Duelo | Esfuerzo | Precisión | Supervivencia | Caos físico | Territorio |
| Escenario | Tablero | Mesa | Tablero | Visor | Tablero | Isla | Baldosas |

Lectura: **4 de 7 son joystick y 3 comparten tablero**. El plan de la Fase C ([PLAN.md](PLAN.md)) ya apunta a los controles nuevos (dos botones, cuatro botones, inclinación); sumar como criterio que **cada juego nuevo tenga su propio escenario** y que ninguno repita la combinación control + emoción.

### 4.2 Modos

| Modo | Qué es | Ejemplo | Fase |
|---|---|---|---|
| **Partida rápida** | 3 juegos al azar sin configurar nada | "Tenemos 10 minutos": un botón en el lobby | A |
| **Equipos 2 vs 2** | Puntos compartidos | Fútbol 2 vs 2, y en Pintar el piso, dos colores en vez de cuatro | C |
| **Bots** | Completar lugares | 1 persona + 3 bots para probar solo; reemplazar a quien se desconecta | C |
| **Ronda final doble** | El último juego vale el doble | Mantiene la tensión hasta el final (nadie "ya perdió" en la ronda 4 de 6) | A |
| **Handicap suave** | Ayuda al último | El último del ranking arranca Arena con 1 estrella | C, medirlo con simulaciones de bots |

### 4.3 Progresión y personalización

**Concepto — progresión cosmética:** desbloquear cosas que cambian cómo te ves, nunca cómo jugás. Da motivo para volver sin romper la justicia de la partida.

- **Stickers por jugar:** cada partida da un sticker; con 5 se desbloquea un accesorio (gorro, anteojos, moño). *Ejemplo:* "Jugaste 10 partidas de Empujones → casco de sumo".
- **Logros locales:** "Ganar sin moverse en Reloj exacto", "Pintar 100 baldosas en una partida". Se muestran en el celular al terminar.
- **Dónde se guarda:** el perfil (apodo, apariencia, stickers) vive en el celular (`user://`), como hoy el apodo. La TV **valida** que el accesorio pedido exista (mismo esquema que `look` en [ADR 0007](adr/0007-apariencia-del-jugador.md)): el celular pide cosmética, nunca resultados.
- **Personalización extra:** baile de victoria elegible, color de la chapita, emotes en el lobby (reacciones que la TV muestra sobre la mascota, con límite de frecuencia).
- **Sin cuentas ni patrones oscuros:** para público familiar, nada de cajas sorpresa pagas ni temporizadores de "volvé mañana".

---

## 5. Calidad técnica

### 5.1 Regresión visual automática en la CI

**Concepto — prueba de regresión visual:** guardar una captura "aprobada" (*baseline*) de cada pantalla y, en cada PR, comparar la nueva contra ella. Si difiere más que una tolerancia, la CI avisa y sube una imagen con las diferencias marcadas.

*Ejemplo:* alguien cambia `RADIUS` de 28 a 20 para los botones del celular y sin querer también cambian las tarjetas del lobby. Hoy nadie lo nota hasta mirar la TV; con la regresión visual, el PR muestra `lobby_full: 3,2 % de píxeles distintos` con las tarjetas en rojo.

**Cómo, con lo que ya existe:**

1. **Hacer las capturas deterministas** (`capture_screens.gd --deterministic`). Hoy cambian entre corridas por las nubes, la respiración y el parpadeo (usan `Time.get_ticks_msec()`), el azar de estrellas/bloques (`randomize()`), el código de sala, la IP y la latencia.
   - Un reloj común overridable (ej. `UiTheme.now_ms()`) que en modo determinista devuelve un tiempo fijo.
   - Semilla fija en los `RandomNumberGenerator` de los juegos cuando la herramienta lo pide.
   - Código de sala fijo (`8A73`) y latencia oculta.
   - `tools/character_sheet.gd` **ya es determinista** (PERFORMANCE.md reporta 0 píxeles distintos): es el primer candidato.
2. **Comparador `tools/visual_diff.gd`** sin dependencias nuevas: Godot 4.4 trae [`Image.compute_image_metrics()`](https://docs.godotengine.org/en/4.4/classes/class_image.html) (devuelve error máximo, medio, RMS y PSNR). Para un reporte por píxel, un bucle propio o [godot-pixelmatch](https://github.com/lihop/godot-pixelmatch) (ISC + MIT, Godot 4.2+, detecta antialiasing).
   - **Tolerancia:** un píxel "difiere" si algún canal cambia más de 8/255; la pantalla falla si difiere más del 0,1 % de los píxeles.
   - **Máscaras:** rectángulos que se ignoran por pantalla (ej. el reloj de Reloj exacto).
   - **Salida:** `diff_<pantalla>.png` (actual con lo distinto en magenta) y una tabla en el *Summary* del job.
3. **Baselines** en `tests/visual/baseline/*.png` a 960 px (~20 imágenes, ~3 MB). Se actualizan a propósito con `--update-baseline` en el mismo PR que cambia el diseño, así el revisor ve el antes/después en el diff de GitHub.
4. **CI:** el job `capturas` ya tiene pantalla virtual; se suma un paso que compara y sube los diffs. Arranca **informativo** (como el benchmark) y pasa a bloqueante cuando dos semanas de corridas den 0 falsos positivos.

**Comparar contra la referencia de diseño** (una maqueta, no una captura) **no** se hace píxel a píxel: siempre va a diferir. Para eso, una **hoja de comparación**: `tools/compare_sheet.gd` arma una imagen con referencia | actual lado a lado a la misma escala y una grilla, y es la que se revisa a ojo (sección 7).

### 5.2 Tests de diseño que no necesitan capturas

Más baratos que la regresión visual y corren en `run_tests.gd` (headless):

- **Contraste:** para cada par de tokens usado como texto/fondo (y para cada color de `MASCOT_COLORS` con su texto), `contrast >= 4.5` o `>= 3` si es grande. Hubiera detectado los 4 errores de 1.3.
- **Tamaño mínimo:** construir cada pantalla, recorrer los `Label` y verificar `font_size >= 24`.
- **Foco:** cada pantalla de la TV tiene un control enfocado al abrirse.
- **Distancia de paleta:** ningún par de `MASCOT_COLORS` a menos de 0,05 en OKLab (1.8).
- **Tokens:** ningún `Color("#…")` fuera de `core/ui/` (un grep en el test).

### 5.3 Presupuestos

Ya están en [PLAN.md](PLAN.md) y [PERFORMANCE.md](PERFORMANCE.md). Sumar:

- **Draw calls como puerta de la CI:** los milisegundos varían entre runners, pero la cantidad de draw calls de una escena determinista **no**. Puede fallar el PR si un juego pasa de 150.
- **Tamaño del APK** medido en cada export (cuando exista el pipeline).
- **Prueba de resistencia (*soak test*):** una competencia de 20 minutos con 4 controles simulados en la CI, verificando que `OBJECT_COUNT` no crezca (fugas).

### 5.4 Telemetría y reportes de errores

- **Crash reporting:** [Sentry for Godot](https://github.com/getsentry/sentry-godot) (MIT; la versión 2.x pide Godot ≥ 4.5, ver [PRODUCCION.md](PRODUCCION.md)). *Migas de pan* (*breadcrumbs*): cada cambio de fase (`lobby → playing:sumo → results`), así un crash dice "pasó en Empujones con 3 jugadores, tras una reconexión".
- **Analítica anónima:** [Aptabase](https://github.com/aptabase/aptabase-godot) (MIT). Eventos mínimos, sin nombres ni IDs de dispositivo:

| Evento | Datos | Pregunta que responde |
|---|---|---|
| `session_start` | cantidad de jugadores | ¿Se juega más de a 2 o de a 4? |
| `game_finished` | id del juego, duración, jugadores | ¿Qué juego gusta? ¿Dura lo que debería? |
| `game_skipped` | id del juego | ¿Qué juego saltean? (señal de que aburre) |
| `competition_end` | rondas jugadas / elegidas, `rematch` sí/no | ¿La gente vuelve a jugar? (la métrica de la Fase D) |
| `join_failed` | motivo (`bad_room`, `unreachable`) | ¿Cuánto cuesta unirse? (justifica el QR) |

- **Privacidad:** con público familiar, analítica opcional (activada por defecto solo si la política de la tienda lo permite) y declarada en la política de privacidad.

---

## 6. Producto y tienda

### 6.1 Ficha

| Pieza | Requisito | Cómo producirla |
|---|---|---|
| **Nombre** | Uno solo | Hoy conviven "PARTY-GAME" (logo) y "Party Games" (README, repo). Decidir antes de hacer arte de tienda y revisar disponibilidad de marca ([TRADEMARKS.md](../TRADEMARKS.md)) |
| Ícono | 512×512 | Una mascota de frente con el fondo celeste; se tiene que reconocer en 48 px |
| **Banner de TV (en la app)** | 320×180, con texto, uno por idioma ([Android TV](https://developer.android.com/training/tv/start/start)) | Logo + 4 mascotas |
| Banner de TV (tienda) | 1280×720, sin transparencia *(indirecto: [AppScreens](https://help.appscreens.com/device-screenshots/google-play-store-screenshot-size-requirements-for-android-phones-tablets-wear-os-feature-graphic-android-tv-1))* | |
| Gráfico destacado | 1024×500, sin transparencia, contenido clave en el centro *(indirecto: [ScreenKit](https://screenkit.tools/specs/google-play-feature-graphic-size))* | |
| **Capturas** | Hasta 8 por tipo de dispositivo; al menos 1 de TV *(indirecto, misma fuente)* | `capture_screens.gd` a 1920×1080 **sin** reducir + un modo `--store` que agregue una frase grande arriba ("¡Hasta 4 jugadores con sus celulares!") |
| **Tráiler** | 30 s | Guion abajo |

**Guion del tráiler (30 s):** 0–3 s gancho: 4 mascotas saltan en el podio · 3–8 s: un celular escanea el QR y la mascota aparece en la TV · 8–22 s: 5 cortes de 2–3 s (Empujones, Pintar, Esquivar, Reloj, Carrera) con gente riéndose en el sillón (plano real) · 22–27 s: podio con confeti · 27–30 s: logo + "Gratis en Google TV". Se puede grabar con el Movie Maker de Godot (`--write-movie`) sobre una partida con bots.

### 6.2 IO-GAMES como plataforma

**Concepto — núcleo reutilizable (*core*):** separar lo que cualquier juego "TV + celulares" necesita de lo que es propio de PARTY-GAME. *Ejemplo:* un futuro "IO-Trivia" reutiliza unirse con QR, reconexión, mascotas y pausa, y solo escribe sus preguntas y pantallas.

| Pieza | Dónde está | ¿Al core? |
|---|---|---|
| Red: `HostServer`, `ControllerClient`, descubrimiento, reconexión, límites | `host/network`, `controller/network` | **Sí** |
| Protocolo base: `join`, `welcome`, `reject`, `axis`, `btn`, `feedback`, `look`, `appearance`, validación | `core/protocol` | **Sí**; los layouts y fases propias del juego quedan en una extensión |
| Layouts del celular (joystick, botón, slider) | `controller/layouts` | Sí |
| Sistema visual: `UiTheme` (helpers, `ShapeBatch`), pausa, foco, transiciones | `core/ui`, `host/ui` | Sí los helpers; **los valores de los tokens** son de cada juego |
| **Mascotas** (`PlayerAvatar`, paleta, estilos) | `core/ui/widgets` | **Sí: elenco de la marca**, como los Mii. El jugador reconoce "su" personaje en todos los juegos de IO-GAMES |
| Splash IO-GAMES, sonido de marca | `host/ui`, `core/audio` | Sí |
| Modo competencia (`Tournament`) | `host/tournament` | Probablemente (sirve a otros party games) |
| Minijuegos, lobby, logo PARTY-GAME | | **No** |

**Cuándo separarlo:** no ahora. La regla práctica es extraer cuando exista el segundo juego (antes se adivina mal la frontera). **Ahora sí:** cuidar la frontera con un test que falle si algo en `core/` referencia `res://host/` o `res://controller/`, y un ADR "Núcleo IO-GAMES" que diga qué va y cómo se versiona (addon en `addons/io_core/` con versión semántica).

---

## 7. Proceso: cómo trabajar la calidad del diseño

### 7.1 El ciclo

```
 referencia ──► implementación ──► captura ──► comparación ──► revisión ──┐
     ▲                                                                    │
     └────────────── se ajusta la referencia o el código ◄───────────────┘
```

| Paso | Qué es | Ejemplo con el lobby |
|---|---|---|
| **Referencia** | Imagen aprobada de cómo tiene que verse, con fecha | `docs/design/referencia_lobby.webp` + tabla "zona → implementación" en `design/lobby.md` |
| **Implementación** | Código con tokens, sin valores sueltos | `SeatCard` con `TEXT_LABEL`, `RADIUS`, degradé del color del jugador |
| **Captura** | Pantalla real, no maqueta | `capture_screens.gd --lobby-only` (rápido para iterar) |
| **Comparación** | Referencia y captura lado a lado a la misma escala | Hoja de `compare_sheet.gd`: "las mascotas ocupan 40 % vs 70 %" |
| **Revisión** | Checklist (7.3) + regresión visual (5.1) en el PR | El revisor aprueba la baseline nueva |

Cada pantalla importante tiene su archivo en `docs/design/` (como `lobby.md`): referencia, tabla de zonas y **qué se decidió no copiar y por qué**.

### 7.2 Design tokens en tres niveles

**Concepto:** los tokens se ordenan de lo crudo a lo específico, así un cambio de marca toca un solo nivel.

| Nivel | Qué nombra | Ejemplo |
|---|---|---|
| **Primitivo** | El valor | `BLUE_500 = #3E7BFA` |
| **Semántico** | La intención | `FOCUS = YELLOW_400`, `TEXT_SECONDARY = INK_SOFT` |
| **De componente** | Una pieza | `SEAT_CARD_RADIUS = RADIUS`, `CODE_TILE_HEIGHT = 140` |

Hoy `UiTheme` mezcla primitivos y semánticos. *Ejemplo del beneficio:* un tema nocturno "neon" ([ESTILOS.md](ESTILOS.md)) cambia solo los semánticos (`SURFACE = NIGHT_900`), sin tocar pantallas. Tipografía, movimiento y espaciado pasan a tokens (1.4).

### 7.3 Checklist de "terminado" visual

Complementa la definición de "terminado" de [PLAN.md](PLAN.md). Se marca en la descripción del PR:

- [ ] Captura revisada en `docs/img` a 960 px (≈ TV a 3 m, ver 1.6).
- [ ] Comparada con la referencia (si existe) con la hoja lado a lado.
- [ ] Un solo elemento héroe; el fondo no compite.
- [ ] Textos ≥ 24 px; contraste ≥ 4,5:1 (o 3:1 grande/con contorno); test de contraste en verde.
- [ ] Probado con los 10 colores, **incluidos blanco y negro**.
- [ ] Jugadores con 1P–4P visible en esa pantalla.
- [ ] Foco del D-pad visible y en un lugar lógico al abrir.
- [ ] Todo sale de tokens (sin `Color("#…")`, tamaños ni duraciones sueltos).
- [ ] Entradas/salidas animadas con `DUR_*`/`EASE_*`; respeta "Reducir movimiento".
- [ ] Todo sonido informativo tiene su equivalente visual.
- [ ] Textos con `tr()`; no se cortan con pseudo-localización.
- [ ] Regresión visual: baseline actualizada a propósito o 0 diferencias.
- [ ] Benchmark: draw calls dentro del presupuesto.

### 7.4 Cuándo contratar ilustrador o artista 3D

- **Todavía no:** mientras cambien los juegos (Fase C) y no esté elegida la dirección de arte (recomendada: `paper` en [ESTILOS.md](ESTILOS.md)).
- **Sí, al empezar la Fase D:** antes de las capturas de tienda, porque la ficha se hace una vez y con el arte final.
- **Qué encargar, en orden:** (1) hoja de mascotas: 7 estilos × 10 poses, como `mascotas.png`; (2) logo en variantes (horizontal, ícono, banner); (3) una miniatura por juego; (4) arte de tienda (gráfico destacado, banner de TV).
- **2D vs 3D:** mantener 2D ([PLAN.md](PLAN.md)). Si se quiere el look de la referencia (volumen, brillo), un artista 3D puede modelar las mascotas y **renderizarlas a sprites 2D**: se ve 3D y el juego sigue siendo 2D y liviano.
- **Contrato:** cesión de derechos de autor (obra por encargo) y entrega de fuentes editables (Krita/PSD/Blender); lo exige el registro de marca de los personajes ([TRADEMARKS.md](../TRADEMARKS.md)).

### 7.5 Integrar el arte sin romper nada

**El contrato:** `PlayerAvatar.draw_mascot(…)` sigue recibiendo lo mismo (posición, tamaño, color, estilo, ánimo, pose). Adentro, si hay sprites para ese estilo, los usa; si no, dibuja por código como hoy. Ni pantallas ni juegos se enteran ([ADR 0004](adr/0004-sistema-visual.md)).

**Problema:** 7 estilos × 10 colores × 10 poses serían 700 dibujos. **Solución: sprites en escala de grises + máscara teñida por shader.**

1. El ilustrador entrega cada pose **en grises** (el volumen: luces y sombras) y una **máscara** en los canales de color:
   - **R** = zonas que toman el color del jugador (cuerpo);
   - **G** = acento (interior de orejas, antena);
   - **B** = zonas que no se tiñen (cara blanca, ojos, mejillas).
2. Un shader `canvas_item` lee el gris y la máscara y **aplica una rampa de color por jugador** (*gradient map*): el gris oscuro se vuelve la sombra del color, el medio el color y el claro el brillo.
3. **¿Por qué rampa y no multiplicar?** Multiplicar gris × color funciona para rojo o azul, pero el **negro** se come todo el volumen (negro × cualquier gris = negro) y el **blanco** queda gris sucio. Con una rampa, cada color define sus 3 tonos en `UiTheme`: para Negro `#0B0C10 → #16171D → #4A4D5C`, así se sigue viendo el brillo.
4. Las 10 rampas van en **una textura de 256×10** (una fila por color, índice = `color_index` del [ADR 0007](adr/0007-apariencia-del-jugador.md)): el shader recibe la fila como parámetro. Sumar un color nuevo = sumar una fila.

*Ejemplo:* el ilustrador dibuja una sola vez "Oso feliz" en grises. El shader lo pinta rojo para 1P, rosa para 2P y negro para 4P, con el mismo brillo en los tres. 700 dibujos pasan a ser 70.

**Reglas de entrega:**

- Tamaño fijo por cuadro (ej. 512×512), pivote en los pies, mismos nombres de pose que `character_sheet.gd` (Normal, Parpadeo, Mira, Feliz, Triste, Sorpresa, Paso 1, Paso 2, Salto, Aterriza).
- Un atlas por estilo; importación con mipmaps (la TV escala) y compresión ETC2/ASTC.
- **Verificación:** `character_sheet.gd` genera la hoja con sprites y la hoja por código lado a lado; los tests de contraste y paleta siguen valiendo.
- **Rendimiento:** un sprite es 1 draw call; hoy una mascota son varios tramos de `ShapeBatch`. El arte final probablemente **baja** el costo (ver "Mascotas como nodos" en [PERFORMANCE.md](PERFORMANCE.md)).

---

## 8. Backlog priorizado

Impacto: lo que cambia en la experiencia de un grupo real. Esfuerzo: **S** ≤ 1 día · **M** 2–5 días · **L** > 1 semana. Fases de [PLAN.md](PLAN.md).

| # | Ítem | Área | Impacto | Esfuerzo | Fase |
|---|---|---|---|---|---|
| 1 | `UiTheme.text_on(bg)` y arreglo de los 4 textos ilegibles (Carrera, Reloj, Esquivar, "¡Listo!") | Visual / a11y | Alto | S | A |
| 2 | Tests de diseño: contraste, tamaño mínimo, foco, distancia de paleta, colores sueltos | Técnica | Alto | S | A |
| 3 | Capturas deterministas + `visual_diff.gd` + baselines (informativo en CI) | Técnica | Alto | M | A |
| 4 | Tokens de tipografía, movimiento y espaciado; migrar 19 colores sueltos | Visual | Medio | M | A |
| 5 | Cartel de desconexión en la TV y "entrás en el próximo juego" | UX | Alto | M | A |
| 6 | Ready check desde los celulares en la intro | UX | Medio | S | A |
| 7 | Juice: partículas, hit-stop, números flotantes, conteo animado, anticipación en Empujones | Visual | Alto | M | A |
| 8 | Música CC0 con buses y ducking (`Music.play`) + logo sonoro | Audio | Alto | S–M | A |
| 9 | Miniatura propia por juego en el lobby | Visual | Alto | M | A *(en curso)* |
| 10 | Mascotas con volumen, contorno de color y ojos más grandes | Visual | Alto | M | A *(en curso)* |
| 11 | Escenario propio en Arena, Esquivar y Carrera (sin tablero repetido) | Visual / contenido | Medio | M | C |
| 12 | Chapita única 1P–4P + nombre en todos los juegos | a11y | Medio | S | A |
| 13 | Celular en juego: color del jugador, sin latencia visible, "Salir" seguro | UX | Medio | S | A |
| 14 | Reemplazar Grafito; filtro `--style=deutan/protan/tritan` | a11y | Medio | S | A |
| 15 | QR + deep link y pantalla de unirse sin IP | UX | Alto | M | B |
| 16 | Draw calls como puerta de CI + soak test de 20 min | Técnica | Medio | M | B |
| 17 | Partida rápida y ronda final doble | Contenido | Medio | S | A |
| 18 | Bots con reglas (reemplazo al desconectarse, 1 jugador) | Contenido | Alto | L | C |
| 19 | Equipos 2 vs 2 | Contenido | Medio | L | C |
| 20 | `tr()` en todos los textos + pseudo-localización | Localización | Medio | M | D |
| 21 | Ajustes: volumen por bus, reducir movimiento, alto contraste, texto grande | a11y | Medio | M | D |
| 22 | Progresión cosmética (stickers, accesorios, logros) | Contenido | Medio | L | D |
| 23 | Decidir nombre, dirección de arte e ilustrador; pipeline gris + rampa | Producto | Alto | L | D |
| 24 | Sentry + Aptabase con los eventos de 5.4 | Técnica | Medio | M | D |
| 25 | Ficha de tienda, capturas `--store`, tráiler, banners por idioma | Producto | Alto | M | D |
| 26 | Test de frontera `core/` y ADR del núcleo IO-GAMES | Plataforma | Medio (alto a futuro) | S | C |

## 9. Los 10 próximos pasos

1. **Arreglar los 4 textos ilegibles** con `UiTheme.text_on(bg)` y un token `SUCCESS_TEXT` (ítem 1). Es el defecto más visible y cuesta horas.
2. **Tests de diseño** en `run_tests.gd`: contraste de pares de tokens y colores de jugador, `font_size ≥ 24`, foco al abrir y ningún `Color("#…")` fuera de `core/ui/` (ítem 2).
3. **Modo `--deterministic`** en `capture_screens.gd` (reloj común, semillas fijas, código `8A73`, latencia oculta) y poner `character_sheet.gd` bajo comparación primero (ítem 3).
4. **`tools/visual_diff.gd`** con `Image.compute_image_metrics()` + imágenes de diferencias, y baselines en `tests/visual/`; job de CI informativo (ítem 3).
5. **Escala tipográfica y de movimiento** en `UiTheme` (`TEXT_*`, `DUR_*`, `EASE_*`) y migrar las pantallas (ítem 4).
6. **Música CC0** (Juhani Junkala para lobby/juego, Kenney Jingles para resumen/podio) con buses `Music`/`SFX` y ducking; `CREDITS.md` (ítem 8).
7. **Cartel de desconexión en la TV** y ready check en la intro (ítems 5 y 6).
8. **Pasada de juice** en Arena (estrella que explota + "+1"), Reloj exacto (hit-stop + zoom), Empujones (anticipación del anillo) y conteo animado en el resumen (ítem 7).
9. **Celular en juego:** fondo con el color del jugador, latencia solo en modo desarrollador, "Salir" con mantener apretado; cambiar Grafito (ítems 13 y 14).
10. **Decisiones de producto** (son del dueño): nombre único (PARTY-GAME o Party Games), dirección de arte (`paper`) y brief del ilustrador con el contrato de sprites en grises + rampa (ítem 23).

---

## Fuentes

Consultadas el 27/09/2026. Las marcadas *(indirecto)* se confirmaron por buscadores o sitios de terceros: verificar en la consola de la tienda antes de publicar.

- [Game Accessibility Guidelines](https://gameaccessibilityguidelines.com/full-list/): niveles básico/intermedio/avanzado; pautas de daltonismo, texto y subtítulos.
- [Android TV · Get started](https://developer.android.com/training/tv/start/start): banner de 320×180 con texto, uno por idioma; `LEANBACK_LAUNCHER`.
- [Godot 4.4 · Image](https://docs.godotengine.org/en/4.4/classes/class_image.html): `compute_image_metrics()`.
- [godot-pixelmatch](https://github.com/lihop/godot-pixelmatch): ISC (original) + MIT (modificaciones), Godot 4.2+.
- [Kenney · Music Jingles](https://kenney.nl/assets/music-jingles) y [su página en el Asset Library de Godot](https://godotengine.org/asset-library/asset/1839): CC0, 85 jingles.
- [Juhani Junkala · Retro Game Music Pack / 5 action chiptunes](https://archive.org/details/JuhaniJunkalafiveactionchiptunes): CC0, loops.
- Requisitos de ficha de Google Play *(indirecto)*: [AppScreens](https://help.appscreens.com/device-screenshots/google-play-store-screenshot-size-requirements-for-android-phones-tablets-wear-os-feature-graphic-android-tv-1), [ScreenKit](https://screenkit.tools/specs/google-play-feature-graphic-size).
- *Juice it or lose it* (M. Jonasson y P. Purho, 2012) y *The Art of Screenshake* (J. W. Nijman, 2013); ambas en la lista de [Kenney · Must-see videos](https://kenney.nl/knowledge-base/learning/must-see-videos-for-indie-developers).
- Simulación de daltonismo: matrices de G. M. Machado, M. M. Oliveira y L. A. F. Fernandes, *A Physiologically-based Model for Simulation of Color Vision Deficiency*, IEEE TVCG 2009; distancias en OKLab (B. Ottosson, 2020). Contraste: fórmula de luminancia relativa de WCAG 2.
