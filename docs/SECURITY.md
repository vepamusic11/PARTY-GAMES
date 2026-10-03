# Seguridad

## Modelo de amenazas

Un party game en la red de una casa. Lo que queremos evitar:

| Amenaza | Ejemplo | Control |
|---|---|---|
| Intruso en la partida | El vecino en la misma Wi-Fi entra a tu partida | Código de sala de 4 caracteres **solo visible en la TV** (no se anuncia por red). 32⁴ ≈ 1 millón de combinaciones y cada intento incorrecto corta la conexión |
| Robo de lugar | Alguien intenta reconectarse como otro jugador | Token aleatorio de 128 bits por jugador, generado con `Crypto` (aleatoriedad criptográfica), enviado solo a su dueño |
| Mensajes maliciosos | JSON gigante, tipos incorrectos, NaN | Tope de 512 bytes, parseo que nunca lanza error, validación de tipos, recorte de rangos |
| Inundación (DoS) | Script que manda miles de mensajes | 90 inputs/seg por jugador, máximo 8 conexiones pendientes, 5 seg para unirse o se corta |
| Trampa en el juego | Control modificado que "toca" 100 veces por segundo | Host autoritativo + límites propios del juego (ej. 14 toques/seg en Carrera) |
| Inyección en pantalla | Apodo `[img]http://…[/img]` | Nombres sin caracteres de control, mostrados solo en `Label`/`draw_string` |
| Apariencia maliciosa | `look` con color `"#000"`, `1e999` o en plena partida para confundir | Solo índices de una paleta fija, validados y recortados; solo en el lobby; 8 `look`/seg; nunca toca puntos ni puestos (ADR 0007) |
| Servidor HTTP del control web como puerta de entrada | `GET /../project.godot`, `%2e%2e`, métodos raros, cabeceras gigantes, conexiones que no mandan nada | Lista blanca fija de rutas → archivo (nunca se arma una ruta con lo que pide el cliente); solo `GET`/`HEAD` (405); cabecera ≤ 4 KB (431); 5 s para mandarla; 16 conexiones a la vez; cierre tras responder; respuestas 400/404 sin detalles; nunca lanza errores por datos externos ([ADR 0022](adr/0022-control-web.md)) |
| Página del control manipulada o inyección en el navegador | Un apodo o `hint` con `<script>`; una página que hable con otro servidor | Todo texto de la red se pinta con `textContent` (nunca HTML); CSP `default-src 'none'` con recursos solo de la TV y `connect-src` solo al WebSocket de la misma IP y puerto; `nosniff`; sin scripts ni estilos en línea; sin `eval`. Un test revisa que el JS no use `innerHTML` |
| Encabezado `Host` falso | `Host: evil.com` para que la CSP apunte a otro lado | Se acepta solo una IP (v4 o v6 entre corchetes) o un nombre `[A-Za-z0-9.-]`; si no, 400 |

## Decisiones conscientes

- **Tráfico sin cifrar (ws:// y http://) en la red local.** Lo que viaja son posiciones de joystick, un apodo y una página estática; no hay datos personales ni credenciales. Cifrar en LAN requeriría certificados en la TV, con mucha complejidad y poco beneficio; además una página `https://` no podría abrir `ws://` hacia la TV. **Cuando exista el relay en la nube, ese tramo va obligatoriamente por `wss://` (TLS).**
- **Sin cuentas ni datos personales.** Solo un apodo y la apariencia de la mascota (índices de color y estilo) guardados localmente en el celular (`user://settings.cfg` en la app; `localStorage` en el control web, junto con el token de la última sala para volver al mismo lugar).
- **El código de sala viaja en el QR** (`http://IP:47770/K7QX`). No cambia el modelo: para escanearlo hay que estar frente a la TV, igual que para leer las fichas. El anuncio UDP sigue sin incluirlo.

## Privacidad y tiendas

- Si el juego apunta a familias/chicos, Google Play aplica la política **Designed for Families** y Apple la categoría **Kids**: restringen SDKs de anuncios y analítica. Decidir el público objetivo **antes** de integrar monetización.
- Las tiendas exigen una política de privacidad publicada aunque no se recolecten datos.

## Secretos

- Keystores de Android, certificados y perfiles de Apple **nunca** van al repo (ver `.gitignore`). En CI se cargan desde *GitHub Secrets*.
- El APK de prueba de la CI se firma con un keystore **debug** creado en el job y descartado al terminar, o con el secreto opcional `ANDROID_DEBUG_KEYSTORE_BASE64` (un keystore de prueba, nunca el de publicación). Ver [BUILD.md](BUILD.md#firma-estable-opcional-para-actualizar-sin-desinstalar).

## Reportar un problema

Abrir un issue privado (Security → Report a vulnerability) en el repositorio.
