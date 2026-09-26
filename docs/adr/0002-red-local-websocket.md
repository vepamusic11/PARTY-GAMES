# ADR 0002 · Red local con WebSocket y host autoritativo

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
Los celulares deben controlar la TV con baja latencia, ser fáciles de conectar y resistentes a trampas y cortes.

## Decisión
- La TV corre un servidor **WebSocket** con mensajes JSON y es **autoritativa** (toda la lógica del juego vive ahí).
- Descubrimiento por **UDP broadcast**, sin el código de sala.
- Protocolo propio versionado (`docs/PROTOCOL.md`) en lugar de la multiplayer de alto nivel de Godot (RPC).

## Motivos
- WebSocket funciona igual en Godot, en navegadores y en cualquier lenguaje: deja abierta la puerta a un control web (sin instalar app) o a un host nativo de Apple TV.
- JSON es legible al depurar y suficiente para ~30 mensajes/seg por jugador.
- Las RPC de Godot atan ambos extremos a la misma versión del motor y del árbol de escenas.

## Alternativas descartadas
- **ENet/UDP:** menor latencia ante pérdida de paquetes, pero no funciona desde navegadores. Se reconsidera si las pruebas reales muestran problemas; la red está aislada en `HostServer`/`ControllerClient` para cambiarla sin tocar juegos.
- **Servidor en la nube desde el día 1:** más latencia, costo y dependencia de internet.

## Consecuencias
- Necesitamos misma Wi-Fi; redes con aislamiento de clientes requieren el relay futuro.
- Tráfico sin cifrar en LAN (ver SECURITY.md).
