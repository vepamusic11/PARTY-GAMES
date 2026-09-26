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
- [ ] Identidad visual propia (arte, tipografía, sonidos)
- [ ] 8–10 minijuegos; nuevos layouts: dos botones, tilt (acelerómetro)
- [ ] Modo torneo: varias rondas y tabla de puntos
- [ ] Localización (es / en / pt)
- [ ] Política de privacidad, clasificación de edad, prueba cerrada en Play Store y TestFlight

## Fase 3 · Crecimiento
- [ ] Relay en la nube (`wss://`) para redes que aíslan dispositivos
- [ ] Solución para Apple TV (ver ADR 0001)
- [ ] Monetización (decidir según público objetivo; ver SECURITY.md)
- [ ] Analítica anónima de qué juegos se juegan más
