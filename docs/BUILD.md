# Compilar y probar en dispositivos reales

## Requisitos

- Godot **4.4.x** estándar.
- Plantillas de exportación: en Godot, **Editor → Administrar plantillas de exportación → Descargar**.

## Jugar en una Google TV (sin PC)

Plan A para la prueba: la **TV es una Google TV / Android TV** (por ejemplo el **Xiaomi TV Stick 4K** con su control remoto) y los **controles son celulares Android**. Todo se hace con un celular; no hace falta computadora. Es **el mismo APK** para la TV y para los celulares: en la TV abre directo como pantalla y en el celular como control.

Necesitás: la TV con su control remoto, un celular Android con la sesión de GitHub iniciada en el navegador, y los dos en la **misma Wi-Fi** (no la de invitados).

### 1. Bajar el APK al celular

1. En el navegador del celular entrá a **github.com/vepamusic11/PARTY-GAMES** con tu sesión iniciada (GitHub solo deja bajar artefactos a usuarios con sesión).
2. **Actions** → workflow **CI** → la corrida más reciente con ✅ (de `main`, de tu PR, o una que lances con **Run workflow** eligiendo la rama).
3. Abajo de todo, en **Artifacts**, tocá **`party-game-debug-apk`**. Si no ves la sección, en el menú del navegador activá **Ver versión para computadoras**. Se baja un `.zip`.
4. Abrí la app **Archivos** (Files de Google) → **Descargas** → tocá el `.zip` → **Extraer**. Queda `party-game-debug.apk`.

### 2. Preparar la TV (una sola vez)

1. **Opciones de desarrollador:** en la TV, **Configuración → Sistema → Información** → bajá hasta **Compilación del SO de Android TV** y apretá **OK 7 veces** seguidas, hasta que diga "Ahora eres desarrollador".
2. Instalá **Send Files to TV** desde **Google Play** en la TV (buscala con el micrófono del control) **y** en el celular.
3. Permitir que instale apps: **Configuración → Apps → Seguridad y restricciones → Fuentes desconocidas** (o *Apps desconocidas*) → activá **Send Files to TV**. Si después usás otro administrador de archivos para instalar, activalo también.

### 3. Pasar el APK a la TV

1. En la TV abrí **Send Files to TV** → **Receive** (Recibir). Queda esperando.
2. En el celular abrí **Send Files to TV** → **Send** (Enviar) → buscá `party-game-debug.apk` (en Descargas) → elegí tu TV en la lista.
3. En la TV aparece el archivo recibido: elegilo con el control y **OK**.

Alternativa con pendrive: solo si la TV tiene un USB libre. El Xiaomi TV Stick usa su único micro-USB para la corriente, así que con el stick es más simple Send Files to TV.

### 4. Instalar y abrir

1. **Instalar**. Si aparece *Play Protect* ("app no verificada"): **Más detalles → Instalar de todas formas**. Es normal en un APK de prueba.
2. **Abrir.** La app arranca directo como **TV** (lobby con el código de 4 letras). Si en algún aparato mostrara la pregunta "¿Qué es este dispositivo?", elegí **Pantalla (TV)** con ◀ y **OK**: queda recordado y desde ahí abre directo.
3. Para abrirla otra vez: **Apps** (o *Tus apps*) en la pantalla de inicio. Si no está en la fila de apps: **Configuración → Apps → Ver todas las apps → PARTY-GAME → Abrir** (ver *Pendiente: APK con Gradle*, abajo).
4. Con el control remoto: **◀ ▶ ▲ ▼** para moverse, **OK** para elegir, **Atrás** abre la pausa (nunca corta la partida sin preguntar). La pantalla no se apaga mientras la app está abierta y el sonido sale por la tele.

### 5. Los celulares

Instalá el mismo `party-game-debug.apk` en cada celular (del paso 1: tocalo en **Archivos** y seguí *2. Instalarlo* de la sección del celular, más abajo), abrí **PARTY-GAME → Control (celular)**, elegí la TV que aparece en la lista y escribí el código de 4 letras del lobby.

### Actualizar a una versión nueva

Repetí los pasos 1, 3 y 4 con el APK nuevo. Lo normal hoy: si al instalar dice **"App no instalada"** o **"el paquete entra en conflicto"**, primero **desinstalá** la anterior (**Configuración → Apps → PARTY-GAME → Desinstalar**) y volvé a instalar. Pasa porque cada build de la CI se firma con una clave de prueba distinta. Para que se instale encima sin desinstalar, configurá una vez la *Firma estable* (más abajo, en la sección del celular): son 3 pasos en GitHub y no hay que tocar nada más.

### Alternativa a futuro: un enlace fijo para la app Downloader

La app **Downloader** (de AFTVnews, en Google Play de la TV) baja e instala un APK escribiendo una URL con el control remoto, sin celular. Para eso el APK tiene que estar publicado en una URL fija y pública (por ejemplo un *release* de GitHub). **Hoy no está configurado**: publicar el APK de forma pública es una decisión del dueño del repo.

### Si algo falla en la TV

- **No aparece en la fila de apps:** abrila desde **Configuración → Apps → Ver todas las apps → PARTY-GAME → Abrir**.
- **Los celulares no ven la TV:** misma Wi-Fi (no invitados); abajo en el lobby de la TV está la dirección para escribirla a mano en el celular.
- **Va lenta:** anotá con qué juego. La TV dibuja a 1080p como máximo y usa OpenGL ES 3 (ver [adr/0021-google-tv.md](adr/0021-google-tv.md)).

### Pendiente: APK con Gradle (aparecer en la fila de apps de la TV, con banner)

Para que la app aparezca sola en el launcher de Google TV con su banner, Godot 4.4 exige exportar con **Use Gradle Build**. En el código ya está todo menos el último paso:

- Banner 320×180: `assets/brand/android/banner_320x180.png`, generado con `tools/make_android_icons.gd`.
- Plugin de editor `addons/android_tv/` (activado en `project.godot`): al exportar con Gradle copia el banner al proyecto Gradle, agrega `android:banner` al manifiesto y declara `touchscreen`, `leanback` y `wifi` como **no requeridos**. Sin Gradle no hace nada.
- Probado en un contenedor Linux con Godot 4.4.1: `--install-android-build-template` instala la plantilla en `android/` (fuera del repo por `.gitignore`) y el plugin deja bien el manifiesto y el banner; el build de Gradle no se pudo completar ahí porque la red no deja bajar el plugin de Android de Google Maven. En la CI de GitHub sí hay acceso.

Lo que falta (toca la CI; decisión del dueño):

1. En `export_presets.cfg`: `gradle_build/use_gradle_build=true` y `package/show_in_android_tv=true`.
2. En el job `apk` de la CI: guardar también `templates/android_source.zip` de las plantillas (y cambiar la clave de la caché), instalar en el SDK `platforms;android-34`, `build-tools;34.0.0` y `ndk;23.2.8568313` (lo que pide `android/build/config.gradle` de Godot 4.4.1), exportar con `godot --headless --path . --install-android-build-template --export-debug "Android" …` y verificar con `aapt2 dump badging` que estén `leanback-launchable-activity`, `banner=` y `uses-feature-not-required` de touchscreen y leanback.

Los dos cambios van juntos: con el preset en Gradle y el job viejo, el job `apk` falla.

## Jugar con la PC conectada a la TV (HDMI)

Alternativa si hay una PC con Windows: la PC es la TV y los celulares, los controles.

1. Conectá la PC a la tele con un cable HDMI.
2. **Windows + P → Solo segunda pantalla** (así la imagen va solo a la tele). Para volver: Windows + P → Solo pantalla de PC.
3. Sonido por la tele: clic en el ícono de volumen de la barra de tareas → elegí la salida con el nombre de la TV (o *HDMI*).
4. Doble clic en **`jugar_en_tv.bat`** (en la carpeta del proyecto): abre la TV en pantalla completa. Si Godot no está en `D:\Claude\Godot\`, abrí el `.bat` con el Bloc de notas y cambiá la línea `set "GODOT=..."`. Equivale a:
   ```powershell
   & "D:\Claude\Godot\Godot_v4.4.1-stable_win64_console.exe" --path . -- --host --fullscreen
   ```
5. Firewall y red: igual que en *3. Abrir la TV en la PC* de la sección siguiente.

## Probar con tu celular Android (APK de prueba)

No hace falta Android Studio: GitHub arma el APK solo. La **TV es tu PC con Windows** y el **control es tu celular**, los dos en la **misma Wi-Fi**.

### 1. Bajar el APK

1. En GitHub, pestaña **Actions** → workflow **CI** → la corrida más reciente con ✅ de tu rama o PR. (Corre sola en cada push a `main` y en cada PR; para otra rama: **CI → Run workflow** y elegís la rama.)
2. Abajo de todo, en **Artifacts**, bajá **`party-game-debug-apk`**. Es un `.zip` con `party-game-debug.apk` adentro (~60 MB). Los artefactos se borran a los 14 días.
3. Pasalo al celular: descomprimilo en la PC y mandalo por cable USB, Google Drive o Telegram "Mensajes guardados". O abrí GitHub directamente desde el navegador del celular (con la sesión iniciada) y bajalo ahí.

### 2. Instalarlo

1. En el celular, tocá `party-game-debug.apk` (desde **Archivos → Descargas** o desde la app donde lo recibiste).
2. Android avisa que la app no puede instalar apps desconocidas: **Configuración → Permitir de esta fuente** (el nombre cambia según la marca: "Instalar apps desconocidas" / "Orígenes desconocidos") y volvé con ◀.
3. **Instalar**. Si aparece *Play Protect* ("app no verificada"): **Más detalles → Instalar de todas formas**. Es normal: es un APK de prueba sin publicar.
4. Si dice **"App no instalada"** o **"el paquete entra en conflicto"**: desinstalá la versión anterior de PARTY-GAME y repetí. Pasa porque cada build de la CI se firma con una clave de prueba nueva (ver *Firma estable* más abajo para evitarlo).

### 3. Abrir la TV en la PC

```powershell
& "D:\Godot\Godot_v4.4.1-stable_win64_console.exe" --path . -- --host
```

La **primera vez**, Windows muestra *"Firewall de Windows Defender bloqueó algunas características de esta aplicación"*: marcá **Redes privadas** y **Permitir acceso**. Además, la Wi-Fi de la PC tiene que estar como red **privada**: **Configuración → Red e Internet → Wi-Fi → (tu red) → Tipo de perfil de red → Privada**. En una red "pública" Windows bloquea a los celulares aunque hayas permitido Godot.

Qué usa el juego (por si configurás el firewall a mano):

| Qué | Protocolo y puerto | Sentido en la PC |
|---|---|---|
| Conexión del celular a la TV | TCP **47777** (si está ocupado, 47778–47781; el lobby muestra el real) | Entrante: hay que permitirlo |
| Anuncio "acá hay una TV" | UDP **47778**, broadcast | Saliente: Windows lo deja salir por defecto |

### 4. Conectar el celular

1. Abrí **PARTY-GAME** en el celular → tocá **Control (celular)** (ya viene resaltada). La app se usa con el celular **acostado** (apaisado).
2. En **1 · Elegí tu TV** aparece la tarjeta de tu PC en 1–2 segundos. Tocala.
3. **2 · Tu apodo** y **3 · Código de la TV**: las 4 letras grandes del lobby (ej. `KX7P`) → **Unirme**.
4. El botón o el gesto **Atrás** del celular no cierra la app (así un roce del borde no te saca del juego): para irte, mantené apretado **Salir**. En una Google TV, el Atrás del control remoto abre la pausa, igual que Escape en la PC.

### Si la TV no aparece en el celular

1. En el lobby de la TV, abajo de "**¿No aparece la TV? Escribí esta dirección:**", está la IP de la PC, por ejemplo `192.168.1.34, 172.27.16.1 · puerto 47777`.
2. En el celular, en "**¿No aparece? Escribí la dirección que muestra la TV:**", escribí la que empieza igual que la IP del celular (en el celular: **Configuración → Wi-Fi → tu red → Dirección IP**). Casi siempre es la `192.168.x.x`; las `172.x` suelen ser de WSL, Hyper-V o VirtualBox y no sirven. La IP escrita a mano usa siempre el puerto 47777: si el lobby muestra otro, cerrá la otra ventana de Godot o el programa que lo ocupa y abrí la TV de nuevo.
3. Si con la IP escrita tampoco conecta, es el firewall: **Panel de control → Firewall de Windows Defender → Permitir una aplicación a través del firewall → Cambiar configuración** → buscá todas las líneas **Godot** y marcá **Privada**. (Si alguna vez tocaste *Cancelar* en el aviso, Windows guardó una regla de **bloqueo** para Godot, y el bloqueo gana sobre cualquier regla que permita el puerto.) Alternativa en PowerShell como administrador:
   ```powershell
   New-NetFirewallRule -DisplayName "PARTY-GAME TV" -Direction Inbound -Protocol TCP -LocalPort 47777-47781 -Action Allow -Profile Private
   ```
4. Si la IP escrita conecta pero la lista sigue vacía: la red filtra el broadcast (Wi-Fi de invitados, "aislamiento de clientes/AP isolation" del router, algunas redes de oficina). Jugá con la IP escrita (hay que volver a escribirla cada vez que abrís la app).
5. PC por cable y celular por Wi-Fi funciona si los dos salen del **mismo router**. Una VPN activa en la PC o en el celular suele cortar la red local: desactivala para jugar.

### Firma estable (opcional, para actualizar sin desinstalar)

Sin configurar nada, cada APK se firma con una clave de prueba **nueva** (se crea y se descarta en la CI), así que para instalar una build nueva hay que desinstalar la anterior (se pierde el apodo guardado). Para que todas usen la misma firma, creá una vez un keystore **de prueba** (no es el de publicación) y guardalo como secreto del repo:

```bash
keytool -genkeypair -keystore debug.keystore -storepass android -keypass android \
  -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 3650
base64 -w0 debug.keystore   # en Windows: [Convert]::ToBase64String([IO.File]::ReadAllBytes("debug.keystore"))
```

Pegá el texto en **Settings → Secrets and variables → Actions → New repository secret** con el nombre `ANDROID_DEBUG_KEYSTORE_BASE64` y borrá el archivo local. **Nunca** lo agregues al repo (`.gitignore` ya ignora `*.keystore`). Desde ahí, cada APK nuevo se instala encima del anterior (la CI usa el número de corrida como `versionCode`, siempre creciente).

### Cómo lo arma la CI (para quien mantenga el proyecto)

Job `apk` de [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), en paralelo a los tests:

1. Baja Godot y las plantillas de exportación de `godotengine/godot-builds` y verifica sus **SHA-512** fijados en el workflow (al subir de versión de Godot hay que actualizarlos desde `SHA512-SUMS.txt` del release). De las plantillas (~1,2 GB) guarda solo `android_debug.apk` en caché.
2. Usa el Android SDK que trae el runner (`$ANDROID_HOME`: `adb` y `apksigner`) y JDK 17 (`actions/setup-java`).
3. Crea el keystore debug en `$RUNNER_TEMP` (o lo toma del secreto) y se lo pasa a Godot con `GODOT_ANDROID_KEYSTORE_DEBUG_PATH/USER/PASSWORD`; las rutas del SDK y Java van a `editor_settings-4.4.tres`.
4. `godot --headless --export-debug "Android"`, verifica la firma con `apksigner verify` y sube el artefacto.

Preset `Android` ([`export_presets.cfg`](../export_presets.cfg)): paquete `com.iogames.partygame`, `arm64-v8a` + `armeabi-v7a` (celulares baratos de 32 bits también sirven de control), permisos `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE` (con él Godot toma el *multicast lock*: sin eso muchos celulares descartan el anuncio broadcast de la TV) y `VIBRATE`; orientación apaisada con sensor (de `project.godot`); íconos de `assets/brand/android/` (clásico, adaptable y temático de Android 13), generados desde el logo con `tools/make_android_icons.gd`. Tamaño: ~60 MB, de los que ~26 MB son la versión de 32 bits (`armeabi-v7a`); si molesta, se saca esa arquitectura y queda en ~35 MB. **No saques `armeabi-v7a`**: muchas Google TV (sticks baratos) corren apps de 32 bits aunque la CPU sea de 64. Sin *Gradle build*: por eso todavía no aparece en el launcher de Google TV (ver [Pendiente: APK con Gradle](#pendiente-apk-con-gradle-aparecer-en-la-fila-de-apps-de-la-tv-con-banner)).

Para exportar en tu PC: instalá las plantillas 4.4.1, configurá SDK y JDK en el editor (pasos de la sección siguiente) y usá **Proyecto → Exportar → Android**. El keystore debug lo crea el editor solo.

## Android (celular y Google TV / Android TV)

La misma APK/AAB sirve para ambos: en un dispositivo **sin pantalla táctil** (TV) arranca como host automáticamente; en un celular muestra el selector.

1. Instalar Android Studio (o solo el SDK + JDK 17) y configurar las rutas en **Editor → Configuración del editor → Exportar → Android**.
2. **Proyecto → Exportar → Android**: el preset ya está en el repo (`export_presets.cfg`, ver [arriba](#cómo-lo-arma-la-ci-para-quien-mantenga-el-proyecto)).
3. Opciones del preset (ya configuradas; revisarlas si se agrega otro):
   - **Permisos:** `Internet`, `Access Network State`, `Access Wifi State`, `Change Wifi Multicast State` (este último ayuda a recibir el anuncio UDP en algunos celulares) y `Vibrate` (vibración del control; sin él, `Haptics.buzz` no hace nada).
   - **Package → Show In Android TV**: en Godot 4.4 **exige *Use Gradle Build*** (proyecto Android en `android/`, que no se versiona: se instala con **Proyecto → Instalar plantilla de compilación de Android** o `--install-android-build-template`). El banner y el manifiesto de TV los agrega el plugin `addons/android_tv/`. Hoy el preset todavía **no** lo activa: ver [Pendiente: APK con Gradle](#pendiente-apk-con-gradle-aparecer-en-la-fila-de-apps-de-la-tv-con-banner).
   - **Include filter:** `web/*`, para que los archivos del control web (`res://web/`) viajen tal cual dentro del APK. Ojo: Godot *importa* imágenes (`.png`, `.svg`…) y fuentes (`.ttf`, `.woff2`…) y en el APK queda solo la versión importada, no el archivo original. Para servirlos por HTTP, marcá cada uno como **Keep File (exported as is)** en el panel Importar (en su `.import`: `importer="keep"`). `.html`, `.js` y `.css` no se importan y viajan tal cual.
   - **Renderer:** en Android se usa Compatibility (OpenGL ES 3) por `rendering/renderer/rendering_method.mobile` de `project.godot` ([ADR 0021](adr/0021-google-tv.md)).
   - **Screen → Support Small/Normal/Large/Xlarge:** activados.
4. Para instalar rápido en un dispositivo conectado por USB/Wi-Fi: botón de **Despliegue remoto** (ícono de Android arriba a la derecha).
5. Para Google TV por Wi-Fi: activar opciones de desarrollador en la TV → Depuración por red → `adb connect IP_DE_LA_TV`.

**Requisitos de Google TV a cumplir antes de publicar:** banner de 320×180, UI navegable 100 % con D-pad (ya lo está), y declarar que no requiere pantalla táctil (`android.hardware.touchscreen required=false`). Los dos los agrega el plugin `addons/android_tv/` al exportar con **Use Gradle Build**.

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
