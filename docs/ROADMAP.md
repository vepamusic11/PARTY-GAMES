# Roadmap

## ✅ Fase 0 · Prototipo técnico (v0.1)
- [x] Red local TV ↔ celulares con código de sala, reconexión y latencia visible
- [x] Descubrimiento automático + IP manual
- [x] 3 minijuegos con 3 tipos de control
- [x] Tests automáticos + CI

## Fase 1 · Validación en dispositivos reales
- [ ] Probar en Google TV + 2 Android + 1 iPhone; medir latencia en 3 redes distintas
- [ ] Presets de exportación Android/iOS, banner de TV, íconos
- [ ] Código QR en la TV (librería GDScript o generación propia) que abra la app con IP y código precargados
- [ ] Vibración y sonido de feedback en el control

## Fase 2 · Producto mínimo publicable
- [ ] Identidad visual propia (arte, tipografía, sonidos) — *base lista: sistema visual, tipografía y mascotas por código ([ADR 0004](adr/0004-sistema-visual.md)); faltan arte final y sonidos*
- [ ] 8–10 minijuegos; nuevos layouts: dos botones, tilt (acelerómetro)
- [x] Modo competencia: elegir jugadores y juegos, resumen por ronda, podio ([ADR 0003](adr/0003-modo-competencia.md))
- [ ] Mostrar en el celular el puesto y los puntos propios durante el resumen
- [ ] Localización (es / en / pt)
- [ ] Política de privacidad, clasificación de edad, prueba cerrada en Play Store y TestFlight

## Fase 3 · Crecimiento
- [ ] Relay en la nube (`wss://`) para redes que aíslan dispositivos
- [ ] Solución para Apple TV (ver ADR 0001)
- [ ] Monetización (decidir según público objetivo; ver SECURITY.md)
- [ ] Analítica anónima de qué juegos se juegan más
