# Recursos open source y assets: qué reutilizar

Investigación del 26/09/2026, ampliada el 27/09/2026 con un [relevamiento en GitHub](#relevamiento-en-github-27092026) en el que cada repositorio se clonó y se leyó su código y su archivo de licencia. Los marcados *(indirecto)* se confirmaron por buscadores o READMEs, porque el sitio original no se pudo abrir. **Antes de usar cada recurso, revisar su licencia de nuevo** y anotarlo en [CREDITS.md](../CREDITS.md).

## Qué licencias se pueden usar en un juego que se vende

| Licencia | ¿Se puede? | Condición |
|---|---|---|
| CC0 / dominio público | ✅ | Ninguna (dar crédito es opcional) |
| MIT, Apache 2.0, BSD, ISC | ✅ | Incluir el aviso de copyright **dentro del juego** (pantalla de créditos), no solo en el repo |
| OFL (fuentes) | ✅ | Incluir la licencia junto a la fuente (ya lo hacemos con Fredoka) |
| CC-BY, OGA-BY | ✅ | Atribución obligatoria en los créditos |
| CC-BY-SA | ⚠️ | Los derivados deben compartirse con la misma licencia: evitar |
| CC-BY-NC, CC-BY-NC-SA | ❌ | Prohíben el uso comercial |
| GPL, AGPL | ❌ | Obligan a liberar el código del producto; solo sirven como referencia de lectura |
| **Sin archivo de licencia** | ❌ | "Todos los derechos reservados": se puede leer para aprender ideas, **no copiar código** |

## Addons de Godot recomendados

Resumen; el detalle, con fechas y versiones, está en el [relevamiento](#1-addons-de-godot-4).

| Addon | Licencia | Para qué | Decisión |
|---|---|---|---|
| **QR** (codificador de [godot-phone-mass-controllers](https://github.com/splatterfacegames/godot-phone-mass-controllers)) | MIT | QR en la TV para unirse con la IP y el código precargados | **Integrado** en `addons/pmc_qr/` (27/09). Reemplaza a Kenyoni QR, que pesa 10 veces más ([por qué](#qr-por-qué-pmcqr-y-no-kenyoni)) |
| [Sentry for Godot](https://github.com/getsentry/sentry-godot) | MIT | Reportes de errores y crashes con stack de GDScript. **Corrección:** las versiones 1.x y 2.x requieren Godot 4.5+; la 0.x funciona desde 4.3 | **Usar** tras actualizar Godot (Fase B–D) |
| [Aptabase Godot](https://github.com/aptabase/aptabase-godot) | MIT (SDK) | Analítica anónima sin identificadores del dispositivo | **Usar** en Fase D |
| [TweenFX](https://github.com/EvilBunnyMan/TweenFX) | MIT | "Juice" en una línea (sacudida, pop, flotar) | **Solo leer.** Anima nodos; nuestros juegos dibujan todo en un solo nodo con `_draw()`. Copiar las curvas a tokens de `UiTheme` |
| [godotshaders.com](https://godotshaders.com/license/) *(indirecto)* | Cada shader tiene su licencia: CC0, MIT o GPL-3 | Brillos, outline, transiciones | **Solo CC0 o MIT**, nunca GPL |
| [Beehave](https://github.com/bitbrain/beehave) / [LimboAI](https://github.com/limbonaut/limboai) | MIT | Árboles de comportamiento para bots | **Fase C, solo si un bot con reglas no alcanza.** LimboAI es GDExtension (binarios nativos por plataforma) |
| Localización nativa (gettext `.po`) | MIT (motor) | Traducciones es / en / pt | **Usar** (Fase D) |

## Assets libres para el arte y sonido final

| Fuente | Licencia | Para qué |
|---|---|---|
| [Kenney](https://kenney.nl): UI Audio, Interface Sounds, Music Jingles, Impact Sounds, Particle Pack, Input Prompts | CC0 (**verificado el 27/09** leyendo el `License.txt` de los packs de audio) | Sonidos de interfaz, stingers, partículas, íconos de control remoto |
| [Sonniss GDC Bundle 2026](https://gdc.sonniss.com/) | Royalty-free comercial, sin atribución (no redistribuir los archivos sueltos) | Efectos de sonido profesionales |
| [Juhani Junkala en OpenGameArt](https://opengameart.org/content/5-chiptunes-action) | CC0 | Música chiptune en loop para la primera versión |
| [OpenGameArt](https://opengameart.org/content/faq) | Mixtas | Solo tomar CC0 o CC-BY y registrar cada archivo |
| [Freesound](https://freesound.org/help/faq/) | Mixtas | Filtrar CC0 o CC-BY; **nunca NC** |
| [google/fonts](https://github.com/google/fonts) | OFL (casi todas), Apache 2.0 (algunas) | Tipografía "sticker" para títulos y una de lectura para textos chicos (ver [assets](#4-assets-en-github)) |

**En uso** (27/09/2026, [ADR 0015](adr/0015-musica-y-mezcla.md)): 6 bucles de Juhani Junkala (Chiptune Adventures y Retro Game Music Pack) y 3 clics de Kenney Interface Sounds, todos CC0 verificados en el texto de licencia del autor. Las webs de los autores estaban bloqueadas desde el entorno de desarrollo: se tomaron de repositorios públicos de GitHub que incluyen el archivo de licencia original. Detalle y commits en [CREDITS.md](../CREDITS.md).

**Estilos de música** (27/09/2026, [ADR 0017](adr/0017-estilos-de-musica.md)): 4 bucles de **Abstraction** (Benjamin Burnes / Tallbeard Studios, *Music Loop Bundle*, **CC0**) para el estilo Relajado, tomados del release `music-v1` de [jfpx/cc0-media-library](https://github.com/jfpx/cc0-media-library), que trae los OGG originales sin recodificar y el aviso de licencia del autor. Descartado [SoundSafari/CC0-1.0-Music](https://github.com/SoundSafari/CC0-1.0-Music): mezcla fuentes sin el aviso de cada autor (y parte es CC-BY). Fiesta y Latino no usan recursos: los compone el juego (`MusicGen`). Los temas del dueño hechos con Suno llevan un `NOTICE` con la condición de uso comercial (solo con plan pago).

## Proyectos parecidos (para leer, no para copiar)

| Proyecto | Licencia | Qué aprender |
|---|---|---|
| [godot-phone-mass-controllers](https://github.com/splatterfacegames/godot-phone-mass-controllers) | MIT | La TV sirve una página web como control (sin instalar app), QR, reingreso con token, votaciones y rotación de jugadores. De acá sale nuestro codificador QR |
| [Open Party Lab](https://github.com/Hartwich/Open-Party-Lab) | Apache 2.0 | 19 juegos web y un SDK de juegos separado del protocolo: ideas de minijuegos |
| [openpartygames](https://github.com/asaf-shitrit/openpartygames) | AGPL-3.0 | Arquitectura de relay con Cloudflare Durable Objects (solo leer) |
| [Super Tux Party](https://gitlab.com/SuperTuxParty/SuperTuxParty) | GPL-3.0 | Party game en Godot: catálogo de minijuegos por tipo (FFA, 2v2, 1v3, cooperativo) y dificultad de bots (solo ideas) |
| [HappyFunTimes](https://github.com/greggman/HappyFunTimes) | BSD-3 (deprecado; último commit en 2020) | Por qué el control en navegador tuvo problemas: HTTPS y cambios del navegador |

## Decisión abierta: ¿control en navegador en vez de app?

godot-phone-mass-controllers muestra que la TV puede **servir una página web como control**.

- **A favor:** nadie instala nada, se entra escaneando el QR y el iPhone no necesita la App Store ni el permiso de red local.
- **En contra:** menos vibración (Safari en iOS no la expone), los sensores (inclinación) exigen HTTPS y hay que convivir con cambios de los navegadores.
- **Dato nuevo (27/09):** su "juego fuera de la red local" usa `cloudflared`, un programa que la TV tiene que ejecutar; eso **no es posible en Android TV ni iOS** (lo dice su propio [docs/relay-scope.md](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/docs/relay-scope.md)). Para nosotros sigue haciendo falta el relay de la Fase E.

**Propuesta:** mantener la app como experiencia principal y evaluar un control web liviano como "invitado rápido" en la Fase B. Se decide en un ADR.

---

## Relevamiento en GitHub (27/09/2026)

**Pregunta:** ¿qué otros repositorios de GitHub suman valor y qué ejemplos conviene aprovechar?

**Método:** se clonaron 37 repositorios (en `/tmp`, nunca dentro del repo; uno más ya no se pudo clonar). De cada uno se leyó el archivo `LICENSE`/`COPYING` (y el de los assets cuando tienen uno propio), se tomó el último commit con `git log -1` y se leyó el código relevante. Con Godot 4.4.1 se probaron lo integrado y, para comparar, Kenyoni QR. Las fechas de "último commit" son del clon superficial del 27/09/2026.

**Cómo leer la decisión:**
- **Usar ya:** entra ahora sin tocar lo que otros están cambiando.
- **Fase B / C / D:** sirve, pero cuando llegue esa fase (ver [PLAN.md](PLAN.md)).
- **Solo leer:** aprender el patrón y escribirlo a nuestra manera (por licencia, por peso o porque no encaja con "todo dibujado por código").
- **Descartar:** no aporta o tiene un riesgo que no se justifica.

### Conceptos nuevos (con ejemplos del juego)

- **Vendorizar:** copiar el código de un tercero dentro de nuestro repo (en `addons/`), sin modificarlo, con su licencia al lado. *Ejemplo:* `addons/pmc_qr/` es una copia exacta de dos archivos de otro proyecto; si mañana sale una versión mejor, se reemplazan esos dos archivos y el test dice si algo se rompió.
- **GDExtension:** un addon hecho en C++ que se distribuye como biblioteca compilada para cada plataforma (Android ARM64, Windows, etc.). *Ejemplo:* Sentry y LimboAI son GDExtension: si la Google TV usa un procesador para el que no hay binario, el juego no arranca. Un addon en GDScript puro, como el del QR, corre en cualquier lado.
- **Test "golden" (referencia de oro):** guardar el resultado correcto hecho por **otra** herramienta y comparar. *Ejemplo:* el QR de "partygame://join?ip=192.168.1.87&code=AB23" se generó con segno (Python) y se guardó en `tests/data/`; el test compara los 841 módulos uno por uno con los de nuestro addon.
- **Mapa de degradé (*gradient map* / *palette swap*):** un shader que reemplaza cada gris de un dibujo por un color de una rampa. *Ejemplo:* el ilustrador dibuja al Oso una vez en grises y el shader lo pinta rojo para 1P y celeste para 3P (lo propone [CALIDAD.md](CALIDAD.md)); `PalettSwap2D.gdshader` de GDQuest es exactamente eso.
- **Física por eventos:** en lugar de avanzar todas las bolas 1/60 s y buscar choques, se calcula **cuándo** va a ocurrir el próximo choque y se salta hasta ese instante. *Ejemplo:* en Pool loco, un tiro fortísimo nunca "atraviesa" la banda (el *tunneling*), porque el choque se calcula, no se muestrea.
- **Comportamientos de conducción (*steering behaviors*):** fuerzas simples que se suman para mover a un bot: "llegar a" (*arrive*), "perseguir" (*pursue*), "separarse" (*separation*), "seguir un camino" (*follow path*). *Ejemplo:* el bot de Arena suma "llegar a la estrella más cercana" + "separarse de los otros" y parece que juega, sin árbol de decisiones.
- **Cámara de grupo:** una cámara que encuadra a todos los jugadores y se aleja cuando se separan. *Ejemplo:* en un Karts con pista más grande que la pantalla, la cámara sigue el rectángulo que contiene a las 4 mascotas.
- **Sincronización de reloj:** el celular estima la diferencia entre su reloj y el de la TV con varios ping/pong (la mediana de los últimos 5). *Ejemplo:* en Reloj exacto, un toque de Juli con 90 ms de Wi-Fi y uno de Tomi con 20 ms se podrían comparar "en el momento del dedo" y no "en el momento en que llegó". **Cuidado:** el celular no decide resultados; la TV solo acepta una corrección acotada por la latencia que ella misma midió.

### Qué se integró: QR para unirse

**`addons/pmc_qr/`** (2 archivos, 718 líneas de GDScript puro, MIT), copiados sin cambios de [godot-phone-mass-controllers/addons/phone_mass_controllers/qr](https://github.com/splatterfacegames/godot-phone-mass-controllers/tree/8c87cb6/addons/phone_mass_controllers/qr) (commit `8c87cb6`, 14/09/2026). Registrado en [CREDITS.md](../CREDITS.md). No tiene autoload ni plugin, no toca `project.godot` ni el lobby.

- **Herramienta:** [`tools/make_join_qr.gd`](../tools/make_join_qr.gd) genera un PNG con el QR de la TV (IP local + código de sala) con los colores de `UiTheme`, e imprime versión, tamaño y tiempo.
  ```bash
  godot --headless --path . -s res://tools/make_join_qr.gd -- --out=/tmp/qr.png
  godot --headless --path . -s res://tools/make_join_qr.gd -- --ip=192.168.1.87 --code=AB23 --module=10 --out=/tmp/qr.png
  ```
- **Test:** `test_join_qr` en `tests/run_tests.gd`: compara módulo por módulo contra una referencia hecha con [segno](https://github.com/heuer/segno) (otro codificador, en Python), verifica versión, determinismo, textos demasiado largos (devuelve `null`, sin error) y colores.
- **Verificación extra (manual):** los PNG generados se leyeron con [ZXing](https://github.com/zxing-cpp/zxing-cpp), el decodificador que usan muchos celulares Android: devolvió el texto exacto con corrección M.
- **Enlace provisional:** `partygame://join?ip=<IP>&code=<CÓDIGO>` (42 caracteres → versión 3, 29 × 29 módulos). El puerto solo va si no es el de siempre: con "&port=47777" pasaría a la versión 4 y los módulos se achican. El esquema definitivo (¿`partygame://` o un enlace `https://` que abra la tienda si no hay app?) se decide en la Fase B con ADR y cambio en `Protocol`.

#### QR: por qué PMCQr y no Kenyoni

Medido en este contenedor con Godot 4.4.1 (en una Google TV será varias veces más lento):

| | Kenyoni QR Code 2.0.0 | PMCQr (phone-mass-controllers) |
|---|---|---|
| Código | 25 000 líneas (23 000 son una tabla Shift-JIS para kanji, 800 KB) | 718 líneas |
| Cargar el script | **~386 ms** (255 ms solo la tabla) | **~33 ms** |
| Codificar el enlace | ~10 ms | ~1,2 ms |
| Resultado | Idéntico a segno en las máscaras 0, 2, 5 y 7 | Idéntico a segno (test) y leído por ZXing |
| Ruta | Fija en `res://addons/kenyoni/qr_code/` (usa `preload`) | Sin rutas: se puede mover |
| Madurez | Desde 2022, en el Asset Store, mantenido | 2026, parte de un addon más grande, con tests contra ZXing y el paquete npm `qrcode` |

El presupuesto de arranque es ≤ 3 s hasta el lobby ([PLAN.md](PLAN.md)) y el lobby es la primera pantalla: 386 ms solo por cargar el QR (más de 1 s en una TV de gama baja) no se justifican cuando solo hace falta modo byte. **Riesgo de PMCQr:** es un proyecto joven. Mitigación: el test golden detecta cualquier cambio y, si el proyecto se abandona, son 718 líneas que podemos mantener. **Ojo:** si algún día se adopta el addon completo (control web), sus clases `PMCQr`/`PMCQrMatrix` chocarían con esta copia: en ese caso se borra `addons/pmc_qr/`.

**Para la Fase B (lobby):** generar el QR una sola vez al abrir la sala (o al cambiar la IP), dibujarlo en una capa cacheada o como `ImageTexture` con filtro *nearest*, ≥ 10 px por módulo (≈ 370 px de lado en 1080p) y siempre con el margen claro de 4 módulos.

### 1. Addons de Godot 4

| Repo | Licencia (archivo leído) | Último commit | Godot 4.4 / 4.5+ | Qué problema nuestro resuelve | Esfuerzo | Riesgo | Decisión |
|---|---|---|---|---|---|---|---|
| [splatterfacegames/godot-phone-mass-controllers](https://github.com/splatterfacegames/godot-phone-mass-controllers) | MIT (`LICENSE`) | 14/09/2026 `8c87cb6` | 4.3+ (probado en 4.7.1) / sí | QR (integrado); control web "invitado rápido"; `PMCVote`, `PMCRotation`, `PMCQueue` para modos | QR: S (hecho). Control web: L | Bajo el QR; medio el control web (navegadores) | **QR: usar ya** (hecho). Resto: **Fase B** (ADR del invitado web) y **solo leer** para modos |
| [kenyoni-software/godot-addons](https://github.com/kenyoni-software/godot-addons) (QR Code) | MIT (`LICENSE.md`) | 14/08/2026 `3d92d1b` | ≥ 4.4 (v1.2+) / sí | QR | S | Bajo, pero pesado (tabla) | **Descartar** para el QR (ver arriba). Su *License Manager* es una idea para la pantalla de créditos |
| [getsentry/sentry-godot](https://github.com/getsentry/sentry-godot) | MIT (`LICENSE.md`) | 26/09/2026 `0e7fb73` (v2.2.0) | **No** con 1.x/2.x (piden 4.5+); 0.x sí / sí | Crashes con stack y "migas de pan" por fase | M | Medio: GDExtension, binarios por plataforma | **Fase D**, después de actualizar Godot |
| [aptabase/aptabase-godot](https://github.com/aptabase/aptabase-godot) | MIT (`LICENSE`) | 18/06/2026 `d548ed7` | 4.2+ / sí | Qué juegos se eligen, cuánto cuesta unirse | S (285 líneas, autoload) | Bajo. Manda modelo del dispositivo y locale: declararlo en la política de privacidad | **Fase D** |
| [EvilBunnyMan/TweenFX](https://github.com/EvilBunnyMan/TweenFX) | MIT (`LICENSE`) | 28/03/2026 `392f244` | Sí / sí | Juice de UI: `pop_in`, `punch_in`, `squash`, `shake` | S | Bajo, pero anima `position`/`scale` de nodos (choca con `Container`s) y usa `randf` (capturas no deterministas) | **Solo leer**: pasar sus curvas a `UiTheme` (`DUR_*`, `EASE_POP`) |
| [ramokz/phantom-camera](https://github.com/ramokz/phantom-camera) | MIT (`LICENSE`) | 22/09/2026 `e2f6cf2` (v0.11) | 4.4+ / sí | Cámara de grupo con zoom automático | M (10 000 líneas, nodos `Camera2D`) | Medio: versión 0.x, API cambia | **Solo leer**; usar si un juego necesita pista más grande que la pantalla (Fase C) |
| [Eneskp3441/Shaker](https://github.com/Eneskp3441/Shaker) | MIT (`LICENSE`) | 15/09/2024 `c127bcc` | 4.2+ / sí | Temblor de cámara con ruido y presets | S | Bajo, pero sacude nodos; nuestro shake es un `Vector2` que se suma al dibujo (Empujones) | **Solo leer** |
| [saltmire/saltmire-transitions](https://github.com/saltmire/saltmire-transitions) | MIT (`LICENSE.txt`) | 08/07/2026 `7c6f5cc` | **No** (pide 4.6+) / 4.6+ | Transiciones (círculo, wipe, pixelado) | S | — | **Solo leer**: ya tenemos `host/ui/widgets/transition.gd`; sus shaders de círculo y pixelado sirven de receta |
| [bitbrain/beehave](https://github.com/bitbrain/beehave) | MIT (`LICENSE`) | 20/09/2026 `fe58915` | Rama 2.9.x / 2.10+ (main apunta a 4.7) | Árboles de comportamiento para bots | M | Medio: pensado para nodos en escena | **Fase C, solo si hace falta** |
| [limbonaut/limboai](https://github.com/limbonaut/limboai) | MIT (`LICENSE.md`) | 04/09/2026 `3f14ea4` | 1.6.x (GDExtension) / sí | Árboles + máquinas de estado | M | Medio-alto: binarios nativos | **Fase C, solo si hace falta** |
| [gdquest/godot-steering-ai-framework](https://github.com/gdquest/godot-steering-ai-framework) | MIT (`LICENSE`) | 13/09/2024 `9d7cf0d` | Proyecto 4.1 (GDScript) / probable | Movimiento de bots: arrive, pursue, separation, follow path | S por bot | Bajo; poco activo | **Fase C: solo leer** y escribir 4–5 funciones propias (ver patrones) |
| [bitwes/Gut](https://github.com/bitwes/Gut) | MIT (`addons/gut/LICENSE.md`) | 18/08/2026 `cf45f66` | Solo 9.4.0 / 9.5+ (una versión por Godot) | Framework de tests con dobles y espías | L (migrar ~500 verificaciones) | Medio: 20 000 líneas y hay que cambiar de versión con cada Godot | **Solo leer**: copiar su `junit_xml_export.gd` como idea para que la CI muestre qué test falló |
| [MikeSchulze/gdUnit4](https://github.com/MikeSchulze/gdUnit4) | MIT (`LICENSE`) | 30/08/2026 `dba0b28` (v6.2.1) | Solo 5.x / 6.x pide 4.5+ | Tests con aserciones fluidas, *scene runner*, reportes HTML/XML | L | Medio: 53 000 líneas | **Descartar**. Nuestro runner (1 archivo, sin dependencias, corre en CI en segundos) alcanza |
| [lihop/godot-pixelmatch](https://github.com/lihop/godot-pixelmatch) | ISC + MIT (`LICENSE`) | 06/04/2024 `124fe49` | 4.2+ / sí | Regresión visual de capturas | S | Bajo | **Fase A–B** (ya propuesto en [CALIDAD.md](CALIDAD.md)) |
| [abarichello/godot-ci](https://github.com/abarichello/godot-ci) | MIT (`LICENSE`) | 22/06/2026 `6b5c4c4` | Imagen Docker por versión / sí | Exportar APK/AAB en la CI con plantillas ya instaladas | S | Bajo; nunca poner el keystore en el repo (usar secretos) | **Fase D** |
| [firebelley/godot-export](https://github.com/firebelley/godot-export) | MIT (`LICENSE`) | 28/05/2026 `615a6f7` | Sí / sí | Acción de GitHub que exporta todos los presets y arma releases | S | Bajo | **Fase D** (la PRODUCCION.md ya la elige) |
| [foxssake/netfox](https://github.com/foxssake/netfox) | MIT (`LICENSE`) | 26/09/2026 `cf5189d` | Sí / sí | Rollback y predicción en el cliente | — | — | **Descartar**: nuestro celular no simula el juego, solo manda `axis`/`btn` |
| [appsinacup/godot-rapier-physics](https://github.com/appsinacup/godot-rapier-physics) | MIT (`LICENSE`) | 15/09/2026 `8d01421` | Apunta a 4.7 / sí | Física 2D determinista entre plataformas | M | Alto: GDExtension y reemplaza el motor de física | **Descartar**: nuestros juegos usan física propia de pocos cuerpos |
| [rsubtil/controller_icons](https://github.com/rsubtil/controller_icons) | MIT (código) + CC0 (íconos de Xelu) | 28/07/2026 `4246544` | Sí / sí | Íconos de joystick/teclado según el dispositivo | M | Bajo | **Descartar por ahora**: la TV se maneja con el D-pad del control remoto y el celular dibuja sus controles |
| [IsItLucas/godot_easy_transitions](https://github.com/IsItLucas/godot_easy_transitions) | MIT (según buscador) | — | — | Transiciones | — | El repo ya no se puede clonar | **Descartar** |

### 2. Ejemplos y demos para aprender

| Repo | Licencia (archivo leído) | Último commit | Godot | Qué aprender para nosotros | Decisión |
|---|---|---|---|---|---|
| [godotengine/godot-demo-projects](https://github.com/godotengine/godot-demo-projects) | MIT (`LICENSE.md`) | 25/09/2026 `15d4fcd` | `master` = 4.7; no hay rama 4.4 (la más cercana es `4.3`) | `2d/bullet_shower` (cientos de objetos sin nodos), `networking/websocket_minimal`, `2d/screen_space_shaders`, `2d/particles` | **Solo leer** (se puede copiar: MIT) |
| [37Rb/godot-overhead-car-2d](https://github.com/37Rb/godot-overhead-car-2d) | MIT (`LICENSE.txt`) | 20/03/2023 `1cddf10` | 4.0+ | Física de auto vista desde arriba (modelo de bicicleta), zonas que cambian la fricción (charcos), auto que sigue un camino (bots) | **Fase C (Karts): copiar el modelo** a nuestra física propia |
| [KenneyNL/Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | MIT (código) + CC0 (modelos y sonidos) | 21/08/2026 `2f2e5f2` | 4.6 | Auto arcade 3D con una esfera física, derrape con humo, sonidos de motor y chirrido | **Solo leer**; sus sonidos CC0 pueden servir (Fase D) |
| [danielKlmr/BreakoutShot](https://github.com/danielKlmr/BreakoutShot) | MIT (`LICENSE.md`) | 03/11/2023 `6b1a83c` | 4.1 | Pool 2D: la tronera "chupa" la bola con una fuerza hacia el centro, línea de apuntado | **Fase C (Pool loco): copiar ideas**; no su `RigidBody2D` (no determinista) |
| [lmf-git/poolsnookermultiplayergodot](https://github.com/lmf-git/poolsnookermultiplayergodot) | **Sin licencia** | 25/09/2026 `e3a5f86` | 4.8 | Física de pool por eventos (explicada en `EXPLAINER.md`): sin *tunneling*, independiente de los fps | **Solo leer ideas; no copiar código** |
| [twstewart42/purgatory-pool](https://github.com/twstewart42/purgatory-pool) | GPL-3.0 (`LICENSE`) | 09/09/2025 `ecdacc9` | 4.4 | Pool con CPU rival | **Solo leer** (GPL) |
| [Super Tux Party](https://gitlab.com/SuperTuxParty/SuperTuxParty) | GPL-3.0 (`licenses/LICENSE`; arte, música y shaders con licencias propias) | 24/01/2025 `4812d74` | 4.2 | Metadatos por minijuego (`"type": ["FFA", "2v2", "1v3", "Duel"]`), dificultad del bot como *handicap* físico | **Solo leer** (GPL) |
| [Hartwich/Open-Party-Lab](https://github.com/Hartwich/Open-Party-Lab) | Apache 2.0 (`LICENSE`) | 25/09/2026 `2cdd724` | Web (TypeScript) | SDK de minijuegos separado del protocolo, guía de controles, *Drift Racer* y *Air Hockey* | **Solo leer** |
| [jalaad/godot-phone-controller](https://github.com/jalaad/godot-phone-controller) | **Sin licencia** | 26/09/2026 `921455c` | 4.3+ | Otro "celular como control por navegador" con QR | **Descartar** (sin licencia, y phone-mass-controllers cubre lo mismo con MIT) |
| [greggman/HappyFunTimes](https://github.com/greggman/HappyFunTimes) | BSD-3 (`LICENSE.md`) | 17/04/2020 `da2ba35` | — | Lecciones de por qué el control web se rompió (HTTPS, sensores) | **Solo leer** (deprecado) |
| [gdquest-demos/godot-shaders](https://github.com/gdquest-demos/godot-shaders) | **Doble:** MIT el código y los shaders; **CC-BY-NC-SA** el arte | 16/05/2026 `05a3931` | 4.3 | Ver sección 3 | Shaders: **usar en Fase A–D**; texturas: **nunca** |

### 3. Shaders 2D (CC0/MIT)

**Regla de rendimiento:** un shader sobre un sprite chico cuesta poco; uno que lee la pantalla entera (`hint_screen_texture`) obliga a copiar el cuadro y es caro en una TV de gama baja. Preferir shaders por objeto, o **hornear** el resultado una vez en una textura (como ya hace `soft_blur.gdshader` con el fondo).

| Shader | Repo · archivo | Licencia | Costo | Para qué | Decisión |
|---|---|---|---|---|---|
| Palette swap / gradient map | GDQuest [`PalettSwap2D.gdshader`](https://github.com/gdquest-demos/godot-shaders/blob/05a3931/godot/Shaders/PalettSwap2D.gdshader) | MIT | 2 lecturas de textura por píxel del sprite | Mascotas en grises teñidas por jugador (CALIDAD, "700 dibujos → 70") | **Fase D**, cuando llegue el arte del ilustrador |
| Contorno externo | GDQuest [`outline2D_outer.gdshader`](https://github.com/gdquest-demos/godot-shaders/blob/05a3931/godot/Shaders/outline2D_outer.gdshader) | MIT | 9 lecturas por píxel | Contorno "sticker" en sprites y títulos | **Fase D** (hoy el contorno se dibuja por código) |
| Disolver | GDQuest [`dissolve2D.gdshader`](https://github.com/gdquest-demos/godot-shaders/blob/05a3931/godot/Shaders/dissolve2D.gdshader) | MIT | 2 lecturas | Eliminado en Esquivar o Empujones que se desintegra con borde brillante | **Fase A–C**, con un `NoiseTexture2D` generado por Godot (**no** las texturas de GDQuest, que son NC) |
| Agua | GDQuest [`water_2D.gdshader`](https://github.com/gdquest-demos/godot-shaders/blob/05a3931/godot/Shaders/water_2D.gdshader) | MIT | 2 lecturas + senos | Agua alrededor de la isla de Empujones | **Fase C**, medir con el benchmark |
| Onda expansiva | GDQuest [`shockwave.gdshader`](https://github.com/gdquest-demos/godot-shaders/blob/05a3931/godot/Shaders/shockwave.gdshader) | MIT | Lee la pantalla | Golpe fuerte en Empujones | **Solo leer**: caro; un anillo dibujado da el 80 % del efecto |
| CRT | [SimpleGodotCRTShader](https://github.com/henriquelalves/SimpleGodotCRTShader/blob/239cdf7/addons/crt_shader/CRTShader.gdshader) (65 líneas, 4.3) · [nofacer/godot-crt](https://github.com/nofacer/godot-crt) (261 líneas, 4.5) | MIT (`LICENSE` de cada uno) | Pantalla completa | Variante "arcade retro" | **Descartar por ahora**: no es nuestro estilo y cuesta un pase completo |
| Viñeta, pixelado, desenfoque | godot-demo-projects [`2d/screen_space_shaders/shaders/`](https://github.com/godotengine/godot-demo-projects/tree/15d4fcd/2d/screen_space_shaders/shaders) | MIT | Pantalla completa | Pausa desenfocada, transiciones | **Solo leer** (la viñeta ya la dibuja `PartyBackground`) |
| Transiciones círculo / pixelado | saltmire-transitions [`shaders/`](https://github.com/saltmire/saltmire-transitions/tree/7c6f5cc/addons/saltmire_transitions/shaders) | MIT | Pantalla completa, solo 0,4 s | Otra variante de barrido | **Solo leer** |
| Colección CC0 | [CodingLikeAMonkey/GodotShaderLibrary](https://github.com/CodingLikeAMonkey/GodotShaderLibrary) | CC0 (`LICENSE`) | — | Tiene **un solo** shader (3D) | **Descartar** |

### 4. Assets en GitHub

| Repo | Licencia (archivo leído) | Último commit | Qué trae | Decisión |
|---|---|---|---|---|
| [google/fonts](https://github.com/google/fonts) | OFL 1.1 por familia (`ofl/<familia>/OFL.txt`); Luckiest Guy es Apache 2.0 | 24/09/2026 `23e54b5` | **Lilita One** y **Luckiest Guy** (títulos tipo sticker), **Baloo 2** (redondeada, variable), **Atkinson Hyperlegible** (diseñada para baja visión: textos chicos del celular) | **Fase D** con el estilo elegido; cada fuente con su `OFL.txt`/`LICENSE.txt` al lado. Fredoka sigue siendo la base |
| [lavenderdotpet/CC0-Public-Domain-Sounds](https://github.com/lavenderdotpet/CC0-Public-Domain-Sounds) | CC0 (`LICENSE`); cada pack trae su `License.txt`/`_README.txt` | 22/02/2024 `f2b6264` | 2,6 GB: packs de Kenney (UI Audio, Interface Sounds, Music Jingles, Impact, Digital Audio), "bb" y "Micro Packs" CC0 | **Fase A–D para escuchar y elegir**, pero **bajar cada pack de su fuente original** (kenney.nl, etc.): es una recopilación de un tercero |
| [game-icons/icons](https://github.com/game-icons/icons) | **CC-BY 3.0** (la mayoría) o CC0 si se indica (`license.txt`, por autor) | 23/04/2026 `82d9488` | 4000+ íconos SVG de juegos | **Fase D si hace falta**: exige crédito por autor en la pantalla de créditos |
| [DJLink/Xelu_Free_Controller-Key_Prompts](https://github.com/DJLink/Xelu_Free_Controller-Key_Prompts) | CC0 (`LICENSE` y `Readme.txt`) | 31/05/2022 `e71969d` | Botones de joysticks (Xbox, PS, Switch, Steam Deck) | **Descartar por ahora** (usamos control remoto y celular); si se suma soporte de gamepad en la TV, bajar de la [fuente original](https://thoseawesomeguys.com/prompts/) |
| [KenneyNL/Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing) | CC0 los assets (según README), MIT el código | 21/08/2026 `2f2e5f2` | Sonidos de motor, derrape e impacto | **Fase C–D** para Karts, anotando cada archivo |

### Top 10

| # | Recurso | Por qué | Cuándo |
|---|---|---|---|
| 1 | **PMCQr** (de godot-phone-mass-controllers) | QR para unirse: saca la IP del camino y evita el permiso de multicast del iPhone | **Integrado** |
| 2 | **godot-overhead-car-2d** | El modelo de auto que necesitan Karts de mascotas, con charcos y autos que siguen un camino | Fase C |
| 3 | **Shaders de GDQuest** (palette swap, dissolve, outline, agua) | Calidad visual con costo bajo y licencia MIT | Fase A–D |
| 4 | **Sentry for Godot** | Saber por qué se cuelga una TV que no tenemos | Fase D (con Godot 4.5+) |
| 5 | **godot-export + godot-ci** | Publicar en Play sin pasos manuales | Fase D |
| 6 | **Aptabase** | Qué juegos gustan, sin datos personales | Fase D |
| 7 | **godot-steering-ai-framework** (como receta) | Bots creíbles con pocas líneas | Fase C |
| 8 | **Packs de audio CC0 de Kenney** | Música de lobby, stingers y sonidos de UI con calidad de estudio | Fase A–D |
| 9 | **google/fonts** (Lilita One / Luckiest Guy / Atkinson Hyperlegible) | Títulos "sticker" y textos chicos más legibles | Fase D |
| 10 | **godot-pixelmatch** | Que la calidad visual no retroceda en la CI | Fase A–B |

### Riesgos de licencia

1. **GDQuest godot-shaders tiene dos licencias:** el código y los shaders son MIT, pero **las texturas y modelos son CC-BY-NC-SA** (prohíben el uso comercial). Copiar solo `.gdshader`; el ruido se genera con `NoiseTexture2D`.
2. **Repos sin archivo de licencia** (poolsnookermultiplayergodot, godot-phone-controller): se leen para entender ideas, pero **no se copia ni una función**.
3. **GPL** (Super Tux Party, purgatory-pool): solo ideas. Ojo con Super Tux Party: algunos de sus shaders son MIT (vienen de GDQuest), pero otros son GPL; ante la duda, ir a la fuente original.
4. **Recopilaciones de terceros** (CC0-Public-Domain-Sounds, espejos de Kenney o Xelu): la licencia la da el autor original, no quien lo sube a GitHub. Bajar de la fuente original y anotar ese enlace en CREDITS.md.
5. **CC-BY** (game-icons): cada ícono exige el nombre de su autor en los créditos del juego.
6. **MIT/BSD/ISC/Apache también "cobran":** el aviso de copyright tiene que estar **dentro de la app** publicada, incluido el de Godot (`Engine.get_license_text()`). Pendiente para la Fase D: pantalla "Créditos" que lea CREDITS.md.
7. **GDExtension (Sentry, LimboAI, Rapier):** además de su licencia, traen bibliotecas nativas con licencias propias (por ejemplo sentry-native y crashpad); revisar su carpeta de licencias al integrarlas.

### Patrones que conviene copiar

Enlaces fijados al commit leído. MIT/Apache: se puede copiar con el aviso; GPL o sin licencia: **solo la idea**.

**Pool loco (física de círculos)**
- **Pasos fijos con sub-pasos** para que un tiro fuerte no atraviese la banda: si la bola avanza más de su radio en un paso, dividir el paso. La versión "perfecta" es la física por eventos de [`EXPLAINER.md`](https://github.com/lmf-git/poolsnookermultiplayergodot/blob/e3a5f86/EXPLAINER.md) (sin licencia: solo la idea); para 5–10 bolas alcanza con sub-pasos.
- **Tronera que "chupa":** cuando la bola entra al radio de la tronera, aplicarle una fuerza hacia el centro y más freno ([`ball/ball.gd`](https://github.com/danielKlmr/BreakoutShot/blob/6b1a83c/ball/ball.gd), MIT). Se siente justo aunque el tiro no fuera perfecto.
- **Línea de apuntado** con el mismo cálculo de rebote que la física (no una aproximación), así lo que se ve es lo que pasa.

**Karts de mascotas**
- **Modelo de bicicleta:** rueda delantera y trasera, el rumbo nuevo sale de la recta entre ambas; tracción baja por encima de cierta velocidad = derrape ([`overhead_car_body_2d.gd`](https://github.com/37Rb/godot-overhead-car-2d/blob/1cddf10/lib/overhead_car_2d/overhead_car_body_2d.gd), MIT). Portarlo a nuestra física propia (sin `CharacterBody2D`), con el joystick como `steering` y aceleración automática.
- **Charcos resbalosos:** zonas que **suman** fricción/arrastre al entrar y **restan** al salir ([`overhead_car_area_2d.gd`](https://github.com/37Rb/godot-overhead-car-2d/blob/1cddf10/lib/overhead_car_2d/overhead_car_area_2d.gd)).
- **Bots que siguen la pista:** un punto que avanza por la `Curve2D` delante del auto y el bot dobla hacia él ([`overhead_car_path_follow_2d.gd`](https://github.com/37Rb/godot-overhead-car-2d/blob/1cddf10/lib/overhead_car_2d/overhead_car_path_follow_2d.gd)). La dificultad es cuánto adelanta ese punto y cuánto error se suma.
- **Derrape con humo y chirrido:** [`scripts/vehicle.gd`](https://github.com/KenneyNL/Starter-Kit-Racing/blob/2f2e5f2/scripts/vehicle.gd) (3D, MIT) activa estelas y sonido cuando el ángulo entre velocidad y rumbo supera un umbral: la misma regla sirve en 2D.

**Cámaras**
- **Cámara de grupo:** rectángulo que contiene a todos + margen, zoom entre un mínimo y un máximo, movimiento suavizado ([`phantom_camera_2d.gd`](https://github.com/ramokz/phantom-camera/blob/e2f6cf2/addons/phantom_camera/scripts/phantom_camera/phantom_camera_2d.gd), modo `GROUP` y `auto_zoom`). Solo si un juego no entra en una pantalla; la regla de JUEGOS.md sigue siendo "la pista entra entera".
- **Temblor con "trauma":** un valor 0–1 que sube con cada golpe y baja con el tiempo; el temblor es `trauma²` × ruido. Con eso, dos golpes seguidos no se suman de forma exagerada. Hoy Empujones usa un temblor lineal (`sumo.gd`); con `trauma²` los golpes chicos casi no mueven la pantalla y los grandes sí.

**Bots (Fase C)**
- **Steering:** `arrive` (frenar al llegar), `pursue` (ir adonde *va a estar* el otro), `separation` (no amontonarse) y `follow_path` ([`Behaviors/`](https://github.com/gdquest/godot-steering-ai-framework/tree/9d7cf0d/godot/addons/com.gdquest.godot-steering-ai-framework/Behaviors), MIT). Son 20–40 líneas cada uno; escribir los nuestros sobre `Vector2`, con el mismo contrato `think(game, id, dt) -> {axis, btn}` de [MODOS.md](MODOS.md).
- **Dificultad como handicap físico:** en Super Tux Party el bot fácil acelera menos y tiene menos velocidad máxima; no es "más tonto" (idea; el código es GPL). Combinado con la demora de reacción que propone MODOS.md da 3 niveles con dos números.
- **Muchas partidas de bots en CI:** el patrón de [`2d/bullet_shower/bullets.gd`](https://github.com/godotengine/godot-demo-projects/blob/15d4fcd/2d/bullet_shower/bullets.gd) (lógica sin nodos) es el mismo que permite simular miles de partidas sin pantalla.

**Modos (MODOS.md)**
- **Fiesta infinita / Torneo por eliminación:** `PMCRotation` ([`lobby/rotation.gd`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/addons/phone_mass_controllers/lobby/rotation.gd), MIT): "el ganador se queda" con tope de rachas, para que nadie acapare la cancha.
- **Votar el próximo juego desde los celulares:** `PMCVote` ([`lobby/vote.gd`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/addons/phone_mass_controllers/lobby/vote.gd)): mayoría, vetos y tiempo límite, lógica pura y testeable. El celular solo manda su botón; la TV cuenta.
- **Cola que respeta el lugar del desconectado:** `PMCQueue.pop_next(n, is_eligible)` ([`lobby/queue.gd`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/addons/phone_mass_controllers/lobby/queue.gd)) salta al que se cortó sin sacarlo de la fila: sirve para espectadores que esperan turno.
- **Metadatos de tipo de juego:** Super Tux Party marca cada minijuego con `"type": ["FFA", "2v2", "1v3", "Duel"]` (idea): es lo que MODOS.md propone como `teams`/`coop` en `get_info()`.

**Red**
- **Reingreso con "lápida" (*tombstone*):** al desconectarse, el jugador queda guardado `grace_seconds` con su id y sus datos, y si vuelve con el mismo token recupera todo ([`host.gd`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/addons/phone_mass_controllers/host.gd)). Ya lo hacemos; comparar el tiempo de gracia (ellos usan 30 s).
- **Reloj compartido para juegos de timing:** mediana del desfase de los últimos 5 ping/pong ([`web/pmc.js`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/addons/phone_mass_controllers/web/pmc.js)). En nuestra versión la TV mide el RTT de cada celular y, en Reloj exacto y Carrera de toques, puede **restar la mitad del RTT medido por ella**, nunca un tiempo que diga el celular.

**Calidad y CI**
- **Test golden contra otra implementación:** lo que hizo phone-mass-controllers con [`tests/node/qr-decode.mjs`](https://github.com/splatterfacegames/godot-phone-mass-controllers/blob/8c87cb6/tests/node/qr-decode.mjs) y lo que hicimos con `test_join_qr`. Sirve igual para la física: guardar la trayectoria de un tiro de Pool loco y compararla después de cada cambio.
- **Reporte JUnit en la CI:** [`junit_xml_export.gd`](https://github.com/bitwes/Gut/blob/cf45f66/addons/gut/junit_xml_export.gd) de GUT (MIT) muestra el formato; sumar `--junit=ruta.xml` a nuestro runner permite que GitHub marque el test que falló sin abrir el log.
- **Juice de UI con tokens:** `pop_in` = escala a 1,1 con `TRANS_BACK`/`EASE_OUT` y vuelta a 1 en ⅓ del tiempo; `punch_in` = ida y vuelta con `TRANS_QUAD` ([`TweenFX.gd`](https://github.com/EvilBunnyMan/TweenFX/blob/392f244/addons/TweenFX/TweenFX.gd)). Llevar esas recetas a `UiTheme` con `DUR_FAST`/`EASE_POP` y respetar "Reducir movimiento".

### Correcciones respecto del 26/09

- **QR:** de Kenyoni QR Code a PMCQr, por peso y tiempo de carga (medido). PLAN.md se actualizó.
- **Sentry:** no solo la 2.x; también la 1.x pide Godot 4.5+. La 0.x funciona desde 4.3.
- **TweenFX:** de "evaluar" a "solo leer" (anima nodos; nuestros juegos dibujan por código).
- **Kenney:** licencia CC0 confirmada leyendo los `License.txt` de los packs de audio (antes era *indirecto*).
- **godot-demo-projects:** `master` ya apunta a Godot 4.7 y no hay rama `4.4` (la más cercana es `4.3`): al copiar algo, verificar que no use API de 4.5+.
- **Beehave:** `main` apunta a 4.7; con Godot 4.4 corresponde la línea 2.9.x.
