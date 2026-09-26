# ADR 0005 · Sonido sintetizado por código y vibración por eventos

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
El juego no tenía sonido ni vibración, y en un party game el feedback físico es la mitad de la diversión: saber que sumaste o que te eliminaron sin mirar la pantalla. No hay presupuesto ni proveedor de audio todavía.

## Decisión
- **Efectos sintetizados** en `core/audio/sfx.gd`: cada efecto es una receta de notas (frecuencia, duración, tipo de onda, volumen) que se convierte en PCM de 16 bits al iniciar. Nada de archivos de audio.
- **Un único punto de uso:** `Sfx.play("nombre")`, estático. Sin nodo `Sfx` en el árbol (tests, herramientas) no hace nada.
- **Vibración por tipo de evento** en `core/audio/haptics.gd`, con duraciones distintas (`tap` 15 ms … `hit` 220 ms).
- **Mensaje `feedback` TV → celular** (compatible, sin subir `VERSION`): el juego pide `notify_player(pid, "point")` y la TV lo reenvía solo a ese celular, con lista cerrada de tipos y máximo 1 cada 80 ms.
- Preferencias "Sonido" y "Vibrar" en el celular y "Sonido" en la pausa de la TV, guardadas localmente.

## Motivos
- Cero licencias y cero peso: la app no crece y no hay que importar ni versionar `.wav`.
- Estilo "chiptune" coherente con la estética de juguete del sistema visual.
- Los tests verifican cada efecto (duración, formato, sin saturar) sin reproducir audio.

## Alternativas descartadas
- **Bancos de sonidos gratuitos:** licencias variadas (CC-BY exige atribución por archivo) y estilos que no combinan entre sí.
- **Que el celular decida cuándo vibrar según su input:** no sabe si sumó un punto; solo la TV (autoritativa) lo sabe.

## Consecuencias
- Cuando haya música o sonidos de un diseñador, se reemplazan las recetas por `AudioStream` importados sin tocar las llamadas `Sfx.play`.
- Android necesita el permiso `Vibrate` en el preset (ver `docs/BUILD.md`).
