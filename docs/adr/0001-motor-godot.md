# ADR 0001 · Motor: Godot 4

- **Estado:** Aceptada
- **Fecha:** 2026-09-26

## Contexto
Necesitamos un motor que exporte a Android (celular y Google TV), iOS y, idealmente, Apple TV, con un solo código para host y control.

## Decisión
Godot 4.4 con GDScript.

## Motivos
- Gratis y open source: sin regalías ni cambios de licencia.
- Proyecto en texto plano: se versiona y revisa bien en Git (y lo puede editar una IA sin el editor abierto).
- Tests y CI headless sin licencias.
- Un solo proyecto exporta a Android e iOS.

## Consecuencias
- ✅ Android, Android TV/Google TV e iOS cubiertos.
- ⚠️ **Godot no exporta a tvOS (Apple TV) oficialmente.** Alternativas para evaluar en Fase 3:
  1. Port comunitario de Godot a tvOS (evaluar madurez en ese momento).
  2. Host en iPhone/iPad y la imagen a la TV por AirPlay (el que transmite también juega, con más latencia).
  3. Una app host liviana nativa en Swift para tvOS que reutilice el mismo protocolo (el protocolo JSON documentado lo hace posible).
- Si Apple TV pasara a ser prioritario desde el inicio, reconsiderar Unity (tvOS oficial) antes de escribir muchos minijuegos.
