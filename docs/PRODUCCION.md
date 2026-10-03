# Dónde vive el proyecto en producción

Party Games es un juego **local**: la partida corre en la TV y los celulares se conectan por la Wi-Fi de la casa. Por eso, en producción **no hace falta un servidor para jugar**. Lo que "vive en la nube" es la distribución, los reportes de errores, la analítica anónima y, más adelante, un relay opcional.

```
                      ┌────────────────────── Casa del jugador ──────────────────────┐
  Google Play ──────► │  Google TV / Android TV  ◄── Wi-Fi local (ws://) ──►  Celulares │
  App Store  ───────► │  (host autoritativo)                                (controles) │
                      └───────────────┬───────────────────────────────────────┬───────┘
                                      │ errores y eventos anónimos (https)     │
                                      ▼                                        ▼
                          Sentry (crashes) · Aptabase (qué juegos se juegan)
                                      ▲
                                      │ solo si la red aísla dispositivos (Fase E)
                          Relay wss:// (Cloudflare Durable Objects: una sala = un objeto)
```

*Ejemplo:* una familia descarga la app en la TV desde Google Play y en los celulares desde Play o la App Store. Juegan una hora sin que ningún servidor nuestro intervenga. Si la TV se cuelga, Sentry nos avisa con el error exacto; Aptabase nos dice, sin saber quiénes son, que "Empujones" fue el juego más elegido esa semana.

## Piezas

| Pieza | Dónde vive | Costo aproximado | Estado |
|---|---|---|---|
| Código fuente y CI | GitHub (repo público, Actions gratis) | 0 | ✅ Funcionando |
| App de TV y de celular | Google Play: **una sola AAB** para celular y Android TV | USD 25 una vez (cuenta de desarrollador) | Fase B–D |
| App de iPhone (control) | App Store | USD 99 por año | Fase D |
| Firma y subida automática | GitHub Actions + [godot-export](https://github.com/firebelley/godot-export) (Android) y fastlane `match`/`pilot` en un runner macOS (iOS) | 0 (minutos de Actions en repo público) | Fase D |
| Reportes de errores | [Sentry](https://github.com/getsentry/sentry-godot) (o [GlitchTip](https://glitchtip.com/) autoalojado) | Plan gratis *(indirecto)* | Fase D |
| Analítica anónima | [Aptabase](https://github.com/aptabase/aptabase-godot) | Plan gratis *(indirecto)* | Fase D |
| Relay para redes que aíslan dispositivos | Cloudflare Workers + Durable Objects: una sala por objeto, WebSocket con hibernación | < USD 0,01 por hora de sala en el plan de USD 5/mes (estimación con su [tabla de precios](https://raw.githubusercontent.com/cloudflare/cloudflare-docs/production/src/content/partials/durable-objects/durable-objects-pricing.mdx)) | Fase E |
| Página del juego y política de privacidad | GitHub Pages | 0 | Fase D |

El relay **no decide nada**: solo reenvía bytes entre la TV y los celulares de la misma sala. La TV sigue siendo autoritativa (ver [ADR 0002](adr/0002-red-local-websocket.md)).

## Requisitos de tienda que afectan al código (a revisar al publicar)

Relevado el 26/09/2026; algunas fuentes fueron indirectas: confirmar en la consola de cada tienda.

1. **Actualizar Godot a 4.5 o superior (hoy 4.7.x).**
   - El soporte de páginas de memoria de 16 KB llegó en 4.5 ([PR](https://github.com/godotengine/godot/pull/106358)).
   - Google Play lo exige para código nativo, y la [guía de calidad de TV](https://developer.android.com/docs/quality-guidelines/tv-app-quality) lo pide desde el 1/8/2026.
   - También lo necesita Sentry 2.x.
   - **Es una decisión de arquitectura:** nuevo ADR, CI con la nueva versión y probar todo.
2. **TV:**
   - banner de 320×180 e ícono;
   - todo navegable con D-pad (ya cumple);
   - "Atrás" coherente;
   - `touchscreen required=false`;
   - AAB y 64 bits;
   - capturas propias de TV para la ficha.
3. **Cuentas de Play personales nuevas:** prueba cerrada con 12 testers durante 14 días *(indirecto)*. Una cuenta de organización lo evita.
4. **iPhone:**
   - permiso de red local (`NSLocalNetworkUsageDescription`);
   - para recibir el anuncio UDP de la TV, además, un permiso especial de multicast que Apple aprueba a mano ([formulario](https://developer.apple.com/contact/request/networking-multicast)). **El QR con la IP y el código evita depender de ese permiso.**
5. **Renderizador:** hoy usamos `mobile` (Vulkan). Para 2D en TVs económicas, la documentación de Godot recomienda **Compatibility** (OpenGL): medir las dos opciones en una TV real (Fase B).

## Calidad visual y rendimiento en producción

- **Presupuestos** de [PLAN.md](PLAN.md): 60 fps, ≤ 8 ms de CPU por cuadro en la TV, ≤ 60 ms de latencia del celular a la TV.
- **Medición continua (pendiente):** sumar el benchmark (`tools/benchmark.gd`) a la CI y revisar todo PR que empeore el p95 más de un 20 %. Comando y cómo comparar con `--json` en [PERFORMANCE.md](PERFORMANCE.md).
- **Arte final sin romper nada:** el sistema visual está centralizado (`UiTheme`, `PlayerAvatar`, `PartyBackground`). Cuando llegue el arte de un ilustrador, o se elija un estilo de [ESTILOS.md](ESTILOS.md), se reemplazan esas piezas sin tocar juegos ni pantallas.

## ¿Una red neuronal que mejore el juego?

**Concepto:** una red neuronal es un modelo que *aprende* a partir de ejemplos o de prueba y error, en lugar de seguir reglas escritas a mano.

*Ejemplo:* con **aprendizaje por refuerzo**, un bot juega "Esquivar" miles de veces. Cada vez que lo toca un bloque, se le resta un punto; después de muchas partidas, aprende a moverse bien sin que nadie le programe cómo.

**Dónde sí serviría:**
- **Bots** para completar lugares vacíos (jugar de a 2 contra 2 bots).
- **Balanceo:** simular miles de partidas para ver si un juego es demasiado fácil o si un lugar de salida da ventaja.

**Por qué no la recomendamos ahora:**
- La librería de referencia, [Godot RL Agents](https://github.com/edbeeching/godot_rl_agents) (MIT), sigue activa pero no publica versiones desde febrero de 2025.
- Para ejecutar el modelo dentro del juego necesita la versión .NET de Godot, que en celulares sigue siendo experimental.
- Para juegos arcade cortos, un bot con reglas simples ("perseguir la estrella más cercana, esquivar sombras, reaccionar con 250 ms de demora") se programa en horas, es predecible y se ajusta con un número.

**Recomendación en tres pasos:**
1. **Ahora, Fase C:** bots con reglas en GDScript, uno por juego, con dificultad ajustable.
2. **Con los bots:** simular miles de partidas bot contra bot en CI (la TV ya corre sin pantalla en los tests) para balancear puntajes y duración de forma automática.
3. **Más adelante:** red neuronal solo en uno o dos juegos donde los bots con reglas queden flojos, con Godot RL Agents o [godot-native-rl](https://github.com/minigraphx/godot-native-rl) si madura en celulares ARM.

Así el juego "evoluciona" con datos reales: la analítica dice qué juegos gustan, las simulaciones dicen si son justos y los ajustes se validan en CI.
