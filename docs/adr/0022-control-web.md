# ADR 0022 · Control web servido por la propia TV (QR, sin instalar nada)

- **Estado:** Aceptada
- **Fecha:** 2026-10-03

## Contexto

Para jugar, cada invitado tenía que instalar la app del celular: un APK de ~60 MB, solo Android, con "orígenes desconocidos" habilitado; en iPhone directamente no se podía. Para una juntada con 2–4 invitados y sus propios celulares (mezcla de Android y iPhone) eso es una barrera demasiado alta: la prueba real del viernes 9/10 necesita que **escanear un QR alcance**, como en Jackbox o AirConsole.

La TV puede ser una PC o una Google TV con el APK como host. La red local puede no tener internet.

## Decisión

La **TV sirve por HTTP una página web que hace de control** y que habla **el mismo protocolo v2** (`docs/PROTOCOL.md`) por WebSocket. La app Godot del celular sigue existiendo y funcionando igual: conviven.

1. **Servidor HTTP mínimo en la TV** (`host/network/web_server.gd`, `WebControllerServer`): un `TCPServer` propio en `Protocol.HTTP_PORT` (47770; si está ocupado, 47771–47774). Solo `GET`/`HEAD` de una **lista blanca fija** de archivos (`ROUTES`), más la ruta del QR (`/K7QX`), que sirve la misma página. Nunca arma rutas de disco con lo que manda el cliente. Cabeceras: `Content-Type` correcto, `X-Content-Type-Options: nosniff`, `Content-Security-Policy` (`default-src 'none'`, recursos solo `'self'`, `connect-src ws://<IP del encabezado Host, validada>:<puerto real del WebSocket>`), `Cache-Control` (`no-cache` para html/js/css, una semana para fuentes e imágenes), `Connection: close`. Límites: cabecera ≤ 4 KB (431), 5 s para mandarla, 16 conexiones a la vez, se cierra después de responder. Poll no bloqueante: lee y escribe de a pedazos en `_process`; sin conexiones cuesta un `is_connection_available()` por cuadro.
2. **Enlace del QR**: `http://192.168.1.34:47770/K7QX` (`Protocol.web_join_url`). El código va en la ruta (sin `?`/`=`) para que el QR quede en **versión 3** (29 módulos) y se lea desde el sillón. El **puerto real del WebSocket** (puede caer en 47778–47781) **no viaja en el enlace**: la TV reemplaza `{{WS_PORT}}` en `index.html` al servirla y el JS lo lee de `<meta name="pg-ws-port">`. Lo que viaja es lo que ya se ve en la TV: estar frente a ella = ver el código.
3. **Cliente web** (`web/index.html`, `controller.css`, `controller.js`): sin frameworks ni nada externo. Unirse (apodo guardado en `localStorage`, código prellenado desde la ruta, fichas de colores como la app), espera "¡Mirá la TV!" con selector de mascota (colores ocupados según `appearance.taken`) y resultado propio (`standing`), y los layouts `joystick`, `slider_h`, `one_button` y `joystick_ab` dibujados en `canvas` con la misma semántica que `controller/layouts/` (joystick flotante, zona muerta 0,12, 30 Hz solo si cambió + keepalive de 250 ms, multitáctil con un dedo por pieza). Reconexión automática con el token (`localStorage`, backoff 0,5→5 s, 8 intentos; al volver a la pestaña reintenta ya; al recargar la página vuelve sola a su lugar). Wake Lock, `navigator.vibrate` y sonidos cortos con WebAudio para `feedback`; "Salir" manteniendo apretado 1 s. En vertical también se juega (las piezas bajan a la mitad de abajo). Objetivo: iPhone Safari 15+ y Chrome Android.
4. **Seguridad del cliente**: todo texto de la red va con `textContent` (equivalente a la regla "nunca BBCode"); cada mensaje entrante se valida y recorta como `Protocol.parse_*` (tipos, rangos, NaN, listas blancas de layouts, fases y tipos de feedback); lo inválido se descarta. La TV sigue siendo autoritativa: el control solo manda `axis`/`btn` (y `look` en el lobby).
5. **Lobby de la TV**: el QR es el héroe de la columna "¡Sumate desde tu celular!" (`host/ui/widgets/join_qr.gd`): se codifica **una vez** por enlace (`addons/pmc_qr`, ~4 ms con la textura) a una textura de un píxel por módulo dibujada con filtro *nearest* a píxeles enteros por módulo (10 px a 1080p). Debajo, "Escaneá con la cámara del celular", la dirección corta para escribirla a mano (`192.168.1.34:47770`), el código en fichas y una línea para quien tiene la app. Si la TV tiene varias IP, se elige la más probable para los celulares (`WebControllerServer.sort_lan_ips`: 192.168.x, 10.x, 172.16–31.x —WSL/Hyper-V/VirtualBox—, el resto) y las demás se muestran en chico.
6. **Archivos en el export**: viven en `res://web/` y se leen con `FileAccess` (funciona desde el proyecto y desde el APK con `web/*` en el `include_filter`). Las fuentes e imágenes van con extensión **`.bin`** (`fredoka-bold.woff2.bin`, `logo.png.bin`): Godot importaría un `.woff2` o un `.png` y el original no viajaría en el export. Además, `tools/build_web_bundle.gd` genera `host/network/web_bundle.gd` con **todos los archivos embebidos en base64**: un script siempre viaja en el APK, así que el servidor cae a esa copia si `res://web/` no está. El test `test_web_bundle_in_sync` falla si el bundle quedó viejo.

## Alternativas descartadas

- **Solo el APK**: 60 MB, Android únicamente, orígenes desconocidos, nada en iPhone. Queda como opción para quien ya la tiene (misma TV, mismos jugadores).
- **PWA / página alojada en internet**: la red del living puede no tener internet, y una página en `https://` no puede abrir `ws://` hacia la TV (contenido mixto). Servirla desde la TV en `http://` evita las dos cosas.
- **Export web de Godot del control**: ~30 MB de wasm, arranque lento en celulares viejos, problemas en Safari con hilos y audio; el control es una pantalla simple que en HTML/JS pesa 160 KB.
- **Pasar el código por `?r=` o un `/info.json`**: el código en la ruta hace el QR más chico y el puerto inyectado en la página evita un pedido extra.
- **Librería HTTP externa o `HTTPServer` de GDExtension**: un servidor de 300 líneas sin dependencias es más fácil de auditar y de exportar a Android.

## Consecuencias

- Hay un puerto más que abrir en el firewall de la PC (TCP 47770–47774), ver [BUILD.md](../BUILD.md).
- El protocolo **no cambió** (sigue en `VERSION` 2): el control web es un cliente más. `docs/PROTOCOL.md` suma la sección de transporte HTTP.
- La página solo ofrece lo que el navegador permite: en iPhone no vibra, Wake Lock requiere Safari 16.4+ (antes, la pantalla puede apagarse si el juego no se toca), y los `ws://` solo funcionan porque la página también es `http://` (nunca servir el control por `https` sin pasar el WebSocket a `wss`).
- Si se cambia algo en `web/`, hay que regenerar el bundle (`godot --headless --path . -s res://tools/build_web_bundle.gd`); el test lo recuerda.
- Las mascotas del control web son una versión dibujada en canvas (cabeza, cuerpo y el accesorio de cada estilo), no las 3D horneadas: alcanza para que cada jugador se reconozca (color + 1P–4P + accesorio). Servir PNG de las 3D queda para después si vale la pena (pesarían más que todo el resto).
- Verificación: `tests/run_tests.gd` (servidor, enlace, bundle, lobby, HostMain) y `tools/web_e2e.mjs` (Chromium emulando iPhone/Pixel contra la TV real, toques multitáctiles, reconexión y dos rondas). El QR de la captura de la TV se decodificó con dos lectores independientes (OpenCV y jsQR), también reducido a 720p y 480p.
