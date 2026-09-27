# Catálogo de juegos: actuales y propuestos

Qué juegos hay, cuáles conviene sumar y cómo encajan en lo que ya existe. Complementa la Fase C de [PLAN.md](PLAN.md). Para hacer uno: [ADDING_A_MINIGAME.md](ADDING_A_MINIGAME.md) y la skill `nuevo-minijuego`.

**Regla de oro:** cada juego nuevo tiene que sumar algo distinto, ya sea un control, una dinámica o una emoción. Un juego que se parece mucho a otro ocupa lugar en el lobby sin aportar.

## Los 7 de hoy

| Juego | Dinámica | Control | Jugadores |
|---|---|---|---|
| Arena de estrellas | Juntar estrellas | Joystick | 1–4 |
| Ping Pong | Devolver la pelota | Deslizar | 2 |
| Carrera de toques | Tocar lo más rápido posible | Un botón | 1–4 |
| Reloj exacto | Frenar el reloj justo a tiempo | Un botón | 1–4 |
| Esquivar | Evitar bloques que caen | Joystick | 1–4 |
| Pintar el piso | Pintar más territorio que los demás | Joystick | 1–4 |
| Empujones | Tirar a los otros de la isla | Joystick | 2–4 |

## Propuestos

### Carreras

**Concepto: *carrera con vista desde arriba* (top-down).** La cámara mira la pista desde arriba y cada mascota va en su autito. Así se ven los cuatro jugadores a la vez en una sola pantalla, sin dividirla.

*Ejemplo:* Pablo dobla con el joystick, agarra un turbo en la curva y le gana a Sofi en la última vuelta.

| Juego | Cómo se juega | Control | Qué suma | Dificultad |
|---|---|---|---|---|
| **Karts de mascotas** | Circuito de 3 vueltas con curvas, turbos y charcos resbalosos. El kart acelera solo: el jugador solo dobla. | Joystick (usa el eje X; el Y frena) | La primera carrera de verdad: adelantar, cerrar al rival, la tensión de la última vuelta | Media: pista con curvas (`Curve2D`), vueltas y puestos |
| **Carrera de obstáculos** | Vista de costado, 4 carriles. Se salta con el botón para esquivar vallas y pozos, y tropezar frena un segundo. | Un botón | Timing puro; se aprende en 5 segundos | Baja |
| **Derrape** | Mini circuito ovalado. Mantener apretado derrapa: más derrape da más turbo, pero con riesgo de salirse. | Un botón | Riesgo contra recompensa con un solo botón | Media |

**Cuidados en las carreras:**
- **Nadie debe quedar "fuera de carrera".** Técnica de *rubber banding* (goma elástica): el que viene último recibe un turbo un poco más fuerte. *Ejemplo:* si Tomi va 2 vueltas atrás, sus turbos duran 20 % más. Tiene que ser sutil, que no se note como trampa.
- **Cámara:** la pista entra entera en la pantalla. No hay pantalla dividida, porque en una TV a 3 metros cuatro pantallas chicas no se leen.
- **Latencia:** doblar con 60 ms de demora se siente bien si el auto tiene algo de inercia. Con giros bruscos se sentiría "pesado".

### Estilo pool

**Concepto: *física de choques entre círculos*.** Cada bola es un círculo con velocidad. Cuando dos bolas se tocan, rebotan e intercambian velocidad según el ángulo del golpe. Conviene programarla a mano con pasos fijos (*física determinista*), en lugar de usar el motor de física de Godot. Así la misma jugada da siempre el mismo resultado y se puede testear.

*Ejemplo:* la bola de Juli pega de costado en una bola dorada, la dorada sale en diagonal y cae en la tronera: Juli suma 3 puntos.

| Juego | Cómo se juega | Control | Qué suma | Dificultad |
|---|---|---|---|---|
| **Pool loco** *(recomendado)* | Todos tiran **al mismo tiempo**, sin turnos. Cada jugador tiene su bola y la mesa tiene bolas doradas: meterlas suma puntos, y meter la bola de otro también. Hay rondas de 10 segundos para apuntar y tirar. | Joystick para apuntar; al soltarlo se tira, y cuanto más lejos del centro, más fuerza | Puntería y caos. Sin turnos no hay espera, lo que es clave con 4 jugadores | Media: física de círculos, troneras, rondas |
| **Mini golf** | Hoyos cortos con rampas y molinos. Todos juegan a la vez con bolas que se atraviesan entre sí; gana el de menos golpes. | Joystick para apuntar y soltar para tirar (igual que Pool loco) | Planificar el tiro; comparte el código de física con Pool loco | Media |
| **Bochas / curling** | Dejar la bola lo más cerca posible del blanco, y también se puede sacar a las de los rivales. | Joystick + soltar | Estrategia tranquila, buen contraste con los juegos de reflejos | Baja-media |

**Por qué tirar a la vez y no por turnos:** en un pool clásico con 4 jugadores, cada uno espera 3 turnos sin hacer nada. En un party game, esperar es aburrirse. Si un modo por turnos resulta divertido, puede sumarse más adelante como variante para 2 jugadores.

**Control "apuntar y soltar":** se puede hacer con el joystick que ya existe, sin cambiar el protocolo.
- La TV recibe la dirección y el largo del joystick en cada `axis`.
- Cuando el valor vuelve a cero después de haber estado estirado, lo interpreta como "soltó".

Toda la lógica vive en la TV, que sigue siendo autoritativa: el celular solo manda el eje. Si más adelante se quiere una flecha de fuerza dibujada en el celular, eso sí sería un layout nuevo (ver la skill `nuevo-layout`).

### Otros que suman algo distinto

| Juego | Dinámica | Control | Qué suma |
|---|---|---|---|
| Papa caliente | Pasar la bomba antes de que explote | Un botón | Tensión y risas |
| Luz roja, luz verde | Avanzar solo con luz verde | Joystick | Autocontrol |
| Motos de luz | Estela que no se puede tocar, como el clásico "Tron" | Joystick | Encerrar al rival |
| Hockey de mesa | 1 contra 1 o 2 contra 2 | Deslizar | Primer juego por equipos con el control que ya existe |
| Memoria de colores | Repetir la secuencia | Cuatro botones (layout nuevo) | Juego de cabeza |
| Equilibrio | Mantener la bandeja nivelada | Inclinación (layout nuevo) | Usa el celular como objeto físico |

## Orden recomendado

1. **Pool loco:** no necesita un layout nuevo y su física se reutiliza en Mini golf y Bochas.
2. **Karts de mascotas:** es la carrera que la gente espera en un party game y usa el joystick que ya existe.
3. **Carrera de obstáculos:** barata y muy clara para jugadores nuevos.
4. **Hockey de mesa:** primer juego por equipos.
5. Después, los que necesitan layouts nuevos (Memoria de colores, Equilibrio), sumados juntos en una sola versión del protocolo.

Cada juego nuevo tiene que cumplir la definición de "terminado" de [PLAN.md](PLAN.md): tests, capturas revisadas, rendimiento dentro del presupuesto y su miniatura para el lobby.
