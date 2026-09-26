# ADR 0003 · Modo competencia con puntos por posición

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
Antes se jugaba un minijuego suelto y se volvía al lobby. Queremos una sesión con varias rondas donde:
- quien maneja la TV elige **cuántos juegan** y **qué minijuegos entran**;
- al terminar cada minijuego se ve un **resumen por jugador** con lo que sumó;
- al final hay un podio.

Cada minijuego mide cosas distintas en escalas distintas (12 estrellas, 40 toques, 5 goles).

## Decisión
1. **Puntos por posición**: cada ronda se traduce a puestos y el puesto da puntos fijos: 1° 100 · 2° 70 · 3° 50 · 4° 30. Los empates comparten puesto ("1-2-2-4"). Si el juego declara `winners`, esos van primero aunque otro tenga más puntaje (ej. Carrera: gana quien cruza la meta).
2. **Lógica pura en `Tournament`** (`host/tournament/tournament.gd`), sin nodos ni UI. `HostMain` solo orquesta y las pantallas solo muestran.
3. **La cantidad de jugadores es la capacidad de la sala** (`HostServer.max_players`). No se puede bajar por debajo de los conectados; subir abre lugares. Arrancar exige que estén todos.
4. **Juegos incompatibles se saltean** sin puntos (ej. alguien se va y Ping Pong necesita 2). Las rondas salteadas no cuentan en "Ronda 2/3".
5. **Sin cambios de protocolo**: el resumen y el podio usan la fase existente `results` y el layout `wait`. El celular no recibe ni decide puntajes *(después se sumó el mensaje informativo `standing`; ver Consecuencias)*.

## Motivos
- Puntos por posición es justo entre juegos y fácil de entender en el sillón ("salí segundo, +70"). Es el esquema de los party games de consola.
- La lógica aislada se testea sin red ni pantalla (`test_tournament_*`).
- No tocar el protocolo evita actualizar la app del celular.

## Alternativas descartadas
- **Sumar puntajes crudos**: favorece a los juegos con números grandes (40 toques > 5 goles).
- **Normalizar por el máximo de cada juego**: justo en teoría, pero difícil de explicar en pantalla y sensible a valores extremos.
- **Elegir la cantidad de jugadores solo como filtro visual** (sin limitar la sala): un celular de más podía entrar sin que nadie lo notara.

## Consecuencias
- Un minijuego solo tiene que reportar su puntaje propio (`result.scores`) y opcionalmente `winners`.
- Metadatos opcionales nuevos en `get_info()`: `score_label` ("estrellas") y `accent` (color de su tarjeta).
- Si en el futuro el celular muestra "vas 2°", se agrega un mensaje nuevo *host → control* (compatible: los tipos desconocidos se ignoran), nunca uno que el control pueda usar para decidir resultados.
  - **Hecho:** mensaje `standing` (ver [PROTOCOL](../PROTOCOL.md)). La TV manda a cada celular solo su puesto, puntos y total al mostrar el resumen y el podio; `VERSION` no cambia y el control no manda nada nuevo.
