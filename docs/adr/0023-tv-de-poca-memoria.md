# ADR 0023 · Caché en disco de las mascotas y perfil "TV de poca memoria"

- **Estado:** Aceptada
- **Fecha:** 2026-10-04
- **Relacionados:** [ADR 0012](0012-mascotas-3d.md) (mascotas horneadas), [ADR 0016](0016-piezas-3d-horneadas.md) y [ADR 0019](0019-tablero-25d-horneado.md) (cachés en disco de piezas y tableros), [ADR 0021](0021-google-tv.md) (Google TV), [PERFORMANCE.md](../PERFORMANCE.md#tv-de-poca-memoria-adr-0023).

## Contexto
La prueba real es en un Xiaomi TV Stick 4K (2.ª gen.): CPU ARM chica, GPU Mali de gama baja y **2 GB de RAM** compartidos con Google TV. Medido en la PC (xvfb), una competencia terminaba en ~220 MB de RAM estática y ~265 MB de texturas, y las mascotas se horneaban en memoria en cada arranque (lobby completo a los ~10 s en llvmpipe; los primeros juegos arrancaban con mascotas 2D).

El censo de texturas (`tools/texture_census.gd`, `playtest --census`) mostró de dónde salían los 265 MB: **letras ~120 MB** (cada tamaño y cada contorno que se dibuja deja un caché de glifos; desde 65 px, una textura de 1024×1024 = 2 MB en la placa y otros 2 MB en la RAM; los carteles que "laten" cambiando el tamaño de letra, como el de vueltas de Karts, dejaban uno por cada tamaño intermedio), atlas de mascotas 40 MB (su presupuesto), viewports ~25 MB (la ventana de 1080p y el escenario del fondo), retroceso del `CanvasGroup` ~11 MB, dioramas y logo del lobby ~11 MB, tableros 2.5D 6–12 MB y piezas 3D 7 MB.

## Decisión
1. **Caché en disco de las hojas de mascotas** (`MascotDiskCache`, `user://mascot_cache/`), como las de tableros, piezas y música: cada trabajo horneado se guarda en un hilo (PNG dentro de un archivo propio con encabezado validado) con una **firma** (hash de `mascot_3d.gd`, sus mallas, el baker, `MascotAtlas` y `PlayerAvatar` —en el APK, sus `.gdc`—, los dos shaders, los colores `MASCOT_*` y afines de `UiTheme`, las medidas del baker, `Props3D.VERSION`, una `VERSION` propia y la versión del motor). Antes de hornear una pose, `MascotAtlas` busca en el índice del disco (leído una vez en un hilo) y lee la hoja en un hilo. Archivo roto, cortado o de otra firma → se borra sin errores y se hornea. **Tope de 64 MB** (se borran los más viejos).
2. **Perfil "TV de poca memoria"** (`LowMemory`): automático en Android con ≤ ~3 GB de RAM (`OS.get_memory_info()`), forzable con `-- --low-memory` (y apagable con `-- --no-low-memory`). En la PC sin la bandera no cambia nada. Con el perfil:
   - al cambiar de pantalla (con el barrido tapando todo) se sueltan los cachés de glifos de más de 32 px; la pantalla nueva arma solo los que usa;
   - los textos de tamaño animado (cartel de vueltas y "¡Al revés!" de Karts, anuncio de ¡Que no te deje la cámara!) se dibujan a un tamaño fijo y se escalan con la transformación (`LowMemory.draw_text_sized`): un caché en vez de uno por tamaño;
   - el atlas de mascotas tiene 24 MB de presupuesto (40 MB sin el perfil): lo soltado vuelve del disco en unos ms. Para que no se suelte lo que se va a usar, las poses precalentadas del juego en curso quedan **protegidas** hasta que termina (`protect_game`/`unprotect`) y la mascota del marcador (dibujada una vez en un SubViewport) queda **fijada** (`pin`);
   - con el lobby oculto se sueltan los dioramas de las tarjetas y el logo, y se vuelven a cargar al volver;
   - fuera de los juegos se sueltan los tableros 2.5D que nadie dibuja.

## Consecuencias
- **Arranque** (xvfb + llvmpipe, 3 celulares): con la caché llena el lobby queda con todas las mascotas 3D en **0,8 s** (antes 10,5 s: se horneaban en cada arranque) y Arena, Esquivar y Karts quedan listos a los 0,3–0,4 s de la intro (antes Arena y Esquivar arrancaban con mascotas 2D). La primera vez en el aparato igual hay que hornear (12,4 s, como antes) y queda guardado.
- **Memoria** (dos competencias seguidas con el perfil forzado, xvfb): texturas 77–97 MB durante los juegos y ~80 MB en el podio, RAM estática ~103–105 MB, contra ~265 MB y ~220 MB sin el perfil. Números en [PERFORMANCE.md](../PERFORMANCE.md#tv-de-poca-memoria-adr-0023).
- **Disco**: ~5 MB de hojas para 3 jugadores y 3 juegos; una competencia completa con 4 jugadores, 8 MB (tope 64 MB).
- **Costo con el perfil**: al cambiar de pantalla se vuelven a rasterizar las letras grandes de la pantalla nueva (decenas de glifos, tapado por el barrido); durante el golpe de escala de un cartel, sus letras se ven escaladas de un caché fijo (≤ 15 %, al final del golpe es idéntico). Las poses de pantalla que se soltaron durante un juego vuelven del disco al llegar al resumen (unos cuadros con el tamaño vecino de la misma mascota).
- **Riesgos**: cambiar el código de la mascota sin que cambie ningún archivo hasheado (ej. una constante en otro script que la mascota lee) no invalida la caché: subir `MascotDiskCache.VERSION`. El `CanvasGroup` de Esquivar y de la ayuda de los eliminados reserva un retroceso de pantalla completa (~11 MB) que el motor no suelta: queda como está.

## Alternativas descartadas
- **Fuentes MSDF** (un caché sirve para todos los tamaños): cambia cómo se ven las letras chicas y los contornos.
- **Comprimir en la placa (ETC2) lo horneado en tiempo de ejecución**: `Image.compress` en el stick es lento y con pérdida (se nota en los bordes de las mascotas); con el perfil ya entra holgado.
- **Celdas del atlas más chicas o menos poses en la TV**: se ve distinto (mascotas más blandas, menos cuadros de animación).
