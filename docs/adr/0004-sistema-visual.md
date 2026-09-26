# ADR 0004 · Sistema visual dibujado por código

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
El prototipo usaba el tema por defecto de Godot sobre fondo oscuro. La referencia de producto son los party games de consola (marcadores hexagonales "1P | 345", personajes simpáticos, colores vivos, cielo celeste, bloques de colores). Todavía no hay arte encargado a un ilustrador.

## Decisión
- **Tokens de diseño** en `core/ui/ui_theme.gd`: paleta, medidas, tema de Godot y funciones de dibujo. Ninguna pantalla ni juego define colores sueltos.
- **Todo dibujado por código** (`_draw`): fondo, mascotas, chips, tarjetas, íconos. Sin texturas.
- **Tipografía Fredoka** (SIL Open Font License 1.1, en `assets/fonts/` con su licencia).
- **Mascotas por lugar**, con un accesorio distinto además del color: 1P antena · 2P orejas redondas · 3P orejas puntiagudas · 4P brote. Personajes propios (no copiados de otros juegos).
- Los minijuegos comparten fondo, marco, marcador superior (`MiniGame.draw_hud`) y mascotas.

## Motivos
- Nítido en 720p, 1080p y 4K sin exportar imágenes en varios tamaños; el APK queda liviano (~100 KB de fuentes, nada de sprites).
- Un único lugar para cambiar la identidad cuando llegue el arte definitivo.
- Accesibilidad: jugadores distinguibles aunque no se perciban los colores (daltonismo), y textos grandes con contorno legibles a 3 metros.

## Alternativas descartadas
- **Sprites/PNG ahora:** requieren arte que todavía no existe y un pipeline de importación por resolución.
- **Escenas `.tscn` para la UI:** el proyecto construye la UI por código (ver `CLAUDE.md`); mezclar estilos complica el mantenimiento.

## Consecuencias
- Cuando haya arte definitivo, `PlayerAvatar.draw_mascot` y `PartyBackground` se reemplazan por sprites sin tocar pantallas ni juegos.
- `tools/capture_screens.gd` + el job `capturas` de CI permiten revisar cada cambio visual en el PR.
