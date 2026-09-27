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

## Decisiones conscientes

- **Tráfico sin cifrar (ws://) en la red local.** Lo que viaja son posiciones de joystick y un apodo; no hay datos personales ni credenciales. Cifrar en LAN requeriría certificados en la TV, con mucha complejidad y poco beneficio. **Cuando exista el relay en la nube, ese tramo va obligatoriamente por `wss://` (TLS).**
- **Sin cuentas ni datos personales.** Solo un apodo y la apariencia de la mascota (índices de color y estilo) guardados localmente en el celular (`user://settings.cfg`).

## Privacidad y tiendas

- Si el juego apunta a familias/chicos, Google Play aplica la política **Designed for Families** y Apple la categoría **Kids**: restringen SDKs de anuncios y analítica. Decidir el público objetivo **antes** de integrar monetización.
- Las tiendas exigen una política de privacidad publicada aunque no se recolecten datos.

## Secretos

- Keystores de Android, certificados y perfiles de Apple **nunca** van al repo (ver `.gitignore`). En CI se cargan desde *GitHub Secrets*.

## Reportar un problema

Abrir un issue privado (Security → Report a vulnerability) en el repositorio.
