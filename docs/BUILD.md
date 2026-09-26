# Compilar y probar en dispositivos reales

## Requisitos

- Godot **4.4.x** estándar.
- Plantillas de exportación: en Godot, **Editor → Administrar plantillas de exportación → Descargar**.

## Android (celular y Google TV / Android TV)

La misma APK/AAB sirve para ambos: en un dispositivo **sin pantalla táctil** (TV) arranca como host automáticamente; en un celular muestra el selector.

1. Instalar Android Studio (o solo el SDK + JDK 17) y configurar las rutas en **Editor → Configuración del editor → Exportar → Android**.
2. **Proyecto → Exportar → Agregar → Android**.
3. Opciones a revisar en el preset:
   - **Permisos:** `Internet`, `Access Network State`, `Access Wifi State`, `Change Wifi Multicast State` (este último ayuda a recibir el anuncio UDP en algunos celulares) y `Vibrate` (vibración del control; sin él, `Haptics.buzz` no hace nada).
   - **Package → Show In Android TV** (si tu versión de Godot la tiene): activado, para aparecer en el launcher de Google TV. Si no está, se resuelve con el manifiesto personalizado del punto siguiente.
   - **Screen → Support Small/Normal/Large/Xlarge:** activados.
4. Para instalar rápido en un dispositivo conectado por USB/Wi-Fi: botón de **Despliegue remoto** (ícono de Android arriba a la derecha).
5. Para Google TV por Wi-Fi: activar opciones de desarrollador en la TV → Depuración por red → `adb connect IP_DE_LA_TV`.

**Requisitos de Google TV a cumplir antes de publicar:** banner de 320×180, UI navegable 100 % con D-pad (ya lo está), y declarar que no requiere pantalla táctil (`android.hardware.touchscreen required=false`); si el preset no lo expone, se hace con **Use Gradle Build** y un manifiesto personalizado.

## iOS (celular como control)

Requiere una Mac con Xcode y cuenta de Apple Developer.

1. **Proyecto → Exportar → Agregar → iOS**, completar Team ID y Bundle ID.
2. Exporta un proyecto de Xcode; compilar y firmar desde Xcode.
3. iOS 14+ pide permiso de **Red local**: completar `NSLocalNetworkUsageDescription` (ej. "Para encontrar la TV y usar tu celular como control") en *Info.plist* adicional del preset.

## Apple TV (tvOS)

**Godot 4 no exporta a tvOS oficialmente.** Ver [adr/0001-motor-godot.md](adr/0001-motor-godot.md) para las alternativas evaluadas. Mientras tanto, en hogares con Apple TV el host puede correr en una Google TV, una PC conectada a la TV o una tablet Android.

## Prueba de red mínima (checklist)

1. TV y celulares en la **misma Wi-Fi** (no la de invitados: suele aislar dispositivos).
2. La TV aparece sola en la lista del celular. Si no aparece, escribir la IP que muestra la TV.
3. Mirar la latencia arriba a la derecha del control: **< 60 ms excelente, 60–100 ms aceptable, > 100 ms revisar la red**.
4. Bloquear el celular 5 segundos y volver: debe reconectarse solo como el mismo jugador.
