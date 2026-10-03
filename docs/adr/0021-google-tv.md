# ADR 0021 · Google TV como pantalla: un solo APK, Compatibility y 1080p

**Estado:** aceptada (octubre 2026). El punto 2 está listo en el código (plugin
y banner) pero **sin activar**: el preset sigue sin Gradle hasta que el job `apk`
de la CI instale la plantilla Gradle (ver docs/BUILD.md → *Pendiente: APK con
Gradle*). **Contexto:** la primera prueba real es en un
Xiaomi TV Stick 4K (2.ª gen., Google TV): CPU ARM de 4 núcleos chica, GPU Mali de
gama baja, ~2 GB de RAM, sin PC a mano.

## Decisiones

1. **Un solo APK para celular y TV.** La misma actividad declara `LAUNCHER`
   (celular) y `LEANBACK_LAUNCHER` (TV). `app/boot.gd` decide el modo: en la TV
   abre directo como pantalla. Menos artefactos, menos confusión para el dueño.
2. **Gradle build obligatorio para la TV.** Godot 4.4 solo agrega
   `LEANBACK_LAUNCHER` (`package/show_in_android_tv`) con *Use Gradle Build*.
   La carpeta `android/` **no** se versiona: se instala en cada export con
   `--install-android-build-template`. Lo que Godot no expone (banner 320×180,
   `touchscreen`/`leanback`/`wifi` no requeridos) lo agrega el plugin de editor
   `addons/android_tv/` al exportar; así funciona igual en la CI y en el editor,
   sin commitear la plantilla (~200 MB) ni un manifiesto que quede viejo al
   cambiar de versión de Godot.
3. **Detección de TV por el sistema, no por la pantalla táctil.** En Android,
   `DisplayServer.is_touchscreen_available()` devuelve siempre `true` (código de
   Godot 4.4.1), así que la regla anterior nunca detectaba la TV. Se consulta
   `UiModeManager` y `android.software.leanback` con el plugin `AndroidRuntime`
   (Godot 4.4+). Red de seguridad: si eso fallara en algún aparato, elegir
   "Pantalla (TV)" con el control remoto queda recordado (`user://device.cfg`);
   con un toque no se recuerda, para no dejar un celular fijo como TV.
4. **Renderer Compatibility (OpenGL ES 3) en Android**
   (`rendering/renderer/rendering_method.mobile="gl_compatibility"`), Mobile
   (Vulkan) en la PC sin cambios. Motivos: los drivers Vulkan de Mali de gama
   baja suelen ser lentos o con errores; Compatibility arranca más rápido y usa
   menos memoria; y es el mismo renderer con el que la CI saca las capturas y el
   benchmark (`--rendering-driver opengl3`), así que lo que se ve en
   `docs/img` es lo que se ve en la TV. Además el manifiesto deja de exigir
   `android.hardware.vulkan.version`. `fallback_to_opengl3=true` queda explícito
   para la PC.
5. **1080p como máximo en la TV.** Con `stretch/mode="canvas_items"` todo se
   dibuja a la resolución de la ventana. Si la TV le diera a la app una
   superficie 4K, serían 4× los píxeles. En TV, si la ventana supera
   1920×1080, `boot.gd` pasa a `CONTENT_SCALE_MODE_VIEWPORT`: se dibuja a 1080p
   y la GPU escala. Celulares y PC no cambian. (La mayoría de las Google TV ya
   le dan 1920×1080 a las apps aunque la salida sea 4K.)
6. **`armeabi-v7a` se queda.** Muchos sticks con Google TV corren el espacio de
   usuario de 32 bits aunque la CPU sea de 64. El APK trae `arm64-v8a` y
   `armeabi-v7a` (~+26 MB).

## Consecuencias

- La CI necesita, además de lo de antes, `android_source.zip` de las
  plantillas, la plataforma/build-tools 34 y el NDK 23.2 que pide la plantilla
  Gradle, y Gradle baja dependencias de Google Maven (más tiempo de build).
- Compatibility no tiene algunos efectos de Mobile (p. ej. glow avanzado);
  hoy el juego no los usa en nada que se note (las capturas ya salen así).
- Pendiente medir en el stick real: fps por juego (`tools/benchmark.gd` no
  corre en Android) y memoria (ver `docs/PERFORMANCE.md` → *Google TV*).
