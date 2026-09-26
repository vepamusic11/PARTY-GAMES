# Plan hacia calidad de producto

Cómo seguimos desde v0.2 hasta un juego publicable en tiendas, con criterios medibles para saber cuándo algo está "terminado de verdad". El estado día a día se ve en el tablero de avances; los ítems cerrados se tildan en [ROADMAP.md](ROADMAP.md).

## Dónde estamos

| Área | Estado |
|---|---|
| Red TV ↔ celular | Sólida: código de sala, reconexión, validación, límites (ver [SECURITY.md](SECURITY.md)) |
| Modo competencia | Elegir jugadores y juegos, resumen por ronda, podio, resultado en el celular |
| Juegos | 5 (Arena, Ping Pong, Carrera, Reloj exacto, Esquivar) y 2 en desarrollo (Empujones, Pintar el piso) |
| Sistema visual | Propio, dibujado por código ([ADR 0004](adr/0004-sistema-visual.md)) |
| Sonido y vibración | Sintetizados por código ([ADR 0005](adr/0005-sonido-sintetizado.md)) |
| Calidad | ~450 verificaciones automáticas, CI con compilación y capturas en cada PR |
| Sin probar todavía | TV y celulares reales, exportación a tiendas |

## Definición de "terminado"

Un cambio está terminado cuando cumple **todo** esto (lo revisa quien integra):

1. **Tests:** la suite pasa y hay al menos un test nuevo por cada comportamiento nuevo o bug corregido.
2. **CI en verde:** tests, compilación de todos los scripts y capturas.
3. **Revisión visual:** se miraron las capturas (skill `verificar-visual`); nada cortado y foco visible.
4. **TV:** todo se maneja con el D-pad; "Atrás" nunca corta sin confirmar.
5. **Accesibilidad:** textos de al menos 24 px en la TV; jugadores distinguibles sin color (1P–4P y accesorio); contraste legible.
6. **Seguridad:** toda entrada de red se valida en quien la recibe; el celular nunca decide resultados.
7. **Rendimiento:** dentro de los presupuestos de abajo (benchmark en `tools/benchmark.gd`).
8. **Documentación:** protocolo, guía o ADR actualizados si cambió algo de eso.

## Presupuestos medibles

| Métrica | Objetivo | Cómo se mide |
|---|---|---|
| Cuadros por segundo en la TV | 60 estables | Benchmark con render real |
| CPU por cuadro en la TV | ≤ 8 ms (p95) | `tools/benchmark.gd` |
| Latencia dedo → TV | ≤ 60 ms (p95) en Wi-Fi doméstico | Medidor de latencia del control, en dispositivos reales |
| Reconexión tras corte | ≤ 3 s | Test de integración y prueba manual |
| Arranque de la TV | ≤ 3 s hasta el lobby | Cronómetro en dispositivo real |
| Tamaño del APK | ≤ 40 MB | Exportación de release |
| Batería del celular | ≤ 8 % por hora de juego | Prueba en dispositivo real |

*Ejemplo:* si un juego nuevo lleva la TV a 12 ms por cuadro en el benchmark, no está terminado aunque se vea bien: hay que optimizarlo antes de integrarlo.

## Fases

### Fase A · Pulido del núcleo *(en curso)*
- [x] Sonido y vibración
- [ ] Rendimiento: benchmark, capas estáticas cacheadas y ahorro de batería en el celular
- [ ] Pantalla "¿Cómo se juega?" antes de cada juego y transiciones entre pantallas
- [ ] Juegos 6 y 7: Empujones (contacto físico) y Pintar el piso (territorio)
- **Listo cuando:** 7 juegos, CI en verde, benchmark dentro del presupuesto.

### Fase B · Validación en dispositivos reales
Requiere tu TV y tus celulares en la misma Wi-Fi: se hace con **Claude Code en la terminal de tu PC**, no desde la nube.
- **Actualizar Godot 4.4 → 4.7.x** (ADR): lo exige Google Play (páginas de 16 KB) y habilita Sentry 2.x. Ver [PRODUCCION.md](PRODUCCION.md).
- Comparar los renderizadores `mobile` y `Compatibility` en una TV real.
- Presets de exportación Android y Google TV (banner, íconos, permisos `Vibrate` y de red).
- Medir latencia y batería en 3 redes distintas y ajustar la frecuencia de envío.
- QR en la TV que abra la app con la IP y el código precargados, con [Kenyoni QR Code](https://github.com/kenyoni-software/godot-addons) (MIT). En iPhone evita depender del permiso de multicast de Apple.
- **Listo cuando:** una partida de 4 jugadores de 20 minutos sin cortes y con los presupuestos cumplidos.

### Fase C · Contenido: 10–12 juegos con variedad
Principio: cada juego nuevo tiene que sumar **algo distinto** (control, dinámica o emoción), no repetir.

| Juego propuesto | Dinámica | Control | Por qué suma |
|---|---|---|---|
| Papa caliente | Pasar la bomba antes de que explote | Un botón | Tensión y risas; reglas en 5 segundos |
| Luz roja, luz verde | Avanzar solo con luz verde | Joystick | Autocontrol; castiga al ansioso |
| Remo en pareja | Alternar dos botones rápido | **Dos botones** (layout nuevo) | Primer uso del layout de dos botones |
| Fútbol 2 vs 2 | Equipos | Joystick | Primer juego **por equipos** |
| Memoria de colores | Repetir la secuencia | **Cuatro botones** (layout nuevo) | Juego de cabeza, no de reflejos |
| Equilibrio | Mantener la bandeja nivelada | **Inclinación** (layout nuevo, acelerómetro) | Usa el celular como objeto físico |

Bots con reglas en GDScript para completar lugares y simulación de miles de partidas en CI para balancear (ver "¿Una red neuronal…?" en [PRODUCCION.md](PRODUCCION.md)).

Cada layout nuevo cambia el protocolo y obliga a actualizar la app del celular: conviene sumarlos juntos en una sola versión.
- **Listo cuando:** 10 juegos o más, al menos 4 tipos de control y 1 por equipos, con puntajes balanceados (ningún juego decide la competencia solo).

### Fase D · Producto publicable
- Identidad final: estilo elegido en [ESTILOS.md](ESTILOS.md), ilustrador para mascotas y logo, música y sonidos de diseñador (o CC0 de calidad, ver [RECURSOS.md](RECURSOS.md)), que reemplazan lo generado por código sin tocar pantallas ni juegos.
- Reportes de errores (Sentry) y analítica anónima (Aptabase); pipeline de tiendas con godot-export y fastlane.
- Tutorial de primera vez y ajustes: volumen, vibración y modo de alto contraste.
- Localización es / en / pt.
- Política de privacidad, clasificación de edad, fichas de tienda, prueba cerrada en Play Store y TestFlight.
- **Listo cuando:** la prueba cerrada con 10 grupos reales no reporta bloqueos y la mayoría quiere volver a jugar.

### Fase E · Crecimiento
Relay en la nube para redes que aíslan dispositivos, solución para Apple TV ([ADR 0001](adr/0001-motor-godot.md)), analítica anónima y monetización según el público elegido.

## Cómo trabajamos con agentes

- Por sprint, 3 a 5 agentes en paralelo, cada uno en su propia copia del repo (*worktree*), partiendo de un commit fijo.
- Cada agente entrega: commit sin push, tests en verde, captura revisada y riesgos de integración.
- La integración la hace una sola sesión, que resuelve los conflictos, corre tests y capturas, sube el PR y actualiza el tablero.
- Godot se ejecuta con un candado compartido (`flock /tmp/party-games-godot.lock`), porque los tests usan puertos fijos.

## Decisiones pendientes (son tuyas)

1. **Público objetivo:** familias con chicos o adultos. Cambia las políticas de las tiendas, los anuncios permitidos y el tono.
2. **¿2D o 3D?** Ver abajo. Recomendación: seguir en 2D hasta terminar la Fase C.
3. **Apple TV:** esperar, o invertir en un host nativo (ver ADR 0001).

### ¿Conviene usar *heightfields*?

Un **heightfield** (mapa de alturas) es una grilla donde cada punto guarda una altura. Con eso se genera un terreno 3D con colinas y valles; Godot lo trae como `HeightMapShape3D` para la física.

*Ejemplo:* un juego de "carrera en la montaña", con pistas que suben y bajan, usaría un heightfield para el suelo.

**Recomendación: no, por ahora.**
- Los juegos actuales y los propuestos pasan en arenas chicas y planas, vistas desde arriba o de costado. Un terreno no agrega diversión ahí.
- Pasar a 3D cambia todo el pipeline: modelos, luces, cámaras. Además, el renderer *mobile* en una Google TV de gama baja tiene poco margen, y sin 3D ya estamos por debajo de los 8 ms por cuadro.
- Si más adelante se quiere el look 3D de los party games de consola, el camino con mejor relación costo/resultado es **2.5D**: personajes 3D low-poly sobre escenarios planos, sin terreno. Un heightfield se justifica solo para un juego puntual de terreno, y encaja como un minijuego más sin cambiar la arquitectura (cada juego es independiente).
