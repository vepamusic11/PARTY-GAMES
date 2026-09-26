# Recursos open source y assets: qué reutilizar

Investigación del 26/09/2026 para no hacer trabajo de más. Licencias y estado verificados con las fuentes enlazadas; los marcados *(indirecto)* se confirmaron por buscadores o READMEs, porque el sitio original no se pudo abrir. **Antes de usar cada recurso, revisar su licencia de nuevo** y anotarlo en `CREDITS.md`.

## Qué licencias se pueden usar en un juego que se vende

| Licencia | ¿Se puede? | Condición |
|---|---|---|
| CC0 / dominio público | ✅ | Ninguna (dar crédito es opcional) |
| MIT, Apache 2.0, BSD | ✅ | Incluir el aviso de copyright |
| OFL (fuentes) | ✅ | Incluir la licencia junto a la fuente (ya lo hacemos con Fredoka) |
| CC-BY, OGA-BY | ✅ | Atribución obligatoria en los créditos |
| CC-BY-SA | ⚠️ | Los derivados deben compartirse con la misma licencia: evitar |
| CC-BY-NC | ❌ | Prohíbe el uso comercial |
| GPL, AGPL | ❌ | Obliga a liberar el código del producto; solo sirven como referencia de lectura |

## Addons de Godot recomendados

| Addon | Licencia | Para qué | Decisión |
|---|---|---|---|
| [Kenyoni QR Code](https://github.com/kenyoni-software/godot-addons) | MIT | QR en la TV para unirse con la IP y el código precargados | **Usar** (Fase B) |
| [Sentry for Godot](https://github.com/getsentry/sentry-godot) | MIT | Reportes de errores y crashes con stack de GDScript. La versión 2.x requiere Godot 4.5 o superior | **Usar** tras actualizar Godot |
| [Aptabase Godot](https://github.com/aptabase/aptabase-godot) | MIT (SDK) | Analítica anónima sin identificadores del dispositivo | **Usar** en Fase D |
| [TweenFX](https://github.com/EvilBunnyMan/TweenFX) | MIT | "Juice" en una línea (sacudida, pop, flotar) | Evaluar o tomar ideas |
| [godotshaders.com](https://godotshaders.com/license/) *(indirecto)* | Cada shader tiene su licencia: CC0, MIT o GPL-3 | Brillos, outline, transiciones | **Solo CC0 o MIT**, nunca GPL |
| [Beehave](https://github.com/bitbrain/beehave) / [LimboAI](https://github.com/limbonaut/limboai) | MIT | Árboles de comportamiento para bots | Evaluar al hacer bots |
| Localización nativa (gettext `.po`) | MIT (motor) | Traducciones es / en / pt | **Usar** (Fase D) |

## Assets libres para el arte y sonido final

| Fuente | Licencia | Para qué |
|---|---|---|
| [Kenney](https://kenney.nl) *(indirecto)*: UI Audio, Interface Sounds, Particle Pack, Input Prompts | CC0 | Sonidos de interfaz, partículas, íconos de control remoto |
| [Sonniss GDC Bundle 2026](https://gdc.sonniss.com/) | Royalty-free comercial, sin atribución (no redistribuir los archivos sueltos) | Efectos de sonido profesionales |
| [Juhani Junkala en OpenGameArt](https://opengameart.org/content/5-chiptunes-action) | CC0 | Música chiptune en loop para la primera versión |
| [OpenGameArt](https://opengameart.org/content/faq) | Mixtas | Solo tomar CC0 o CC-BY y registrar cada archivo |
| [Freesound](https://freesound.org/help/faq/) | Mixtas | Filtrar CC0 o CC-BY; **nunca NC** |

## Proyectos parecidos (para leer, no para copiar)

| Proyecto | Licencia | Qué aprender |
|---|---|---|
| [godot-phone-mass-controllers](https://github.com/splatterfacegames/godot-phone-mass-controllers) | MIT | La TV sirve una página web como control (sin instalar app), QR y reingreso con token |
| [Open Party Lab](https://github.com/Hartwich/Open-Party-Lab) | Apache 2.0 | 19 juegos web y un SDK de juegos separado del protocolo: ideas de minijuegos |
| [openpartygames](https://github.com/asaf-shitrit/openpartygames) | AGPL-3.0 | Arquitectura de relay con Cloudflare Durable Objects (solo leer) |
| [Super Tux Party](https://gitlab.com/SuperTuxParty/SuperTuxParty) | GPL-3.0 | Party game en Godot: catálogo de minijuegos (solo ideas) |
| [HappyFunTimes](https://github.com/greggman/HappyFunTimes) | BSD-3 (deprecado) | Por qué el control en navegador tuvo problemas: HTTPS y cambios del navegador |

## Decisión abierta: ¿control en navegador en vez de app?

godot-phone-mass-controllers muestra que la TV puede **servir una página web como control**.

- **A favor:** nadie instala nada, se entra escaneando el QR y el iPhone no necesita la App Store ni el permiso de red local.
- **En contra:** menos vibración (Safari en iOS no la expone), los sensores (inclinación) exigen HTTPS y hay que convivir con cambios de los navegadores.

**Propuesta:** mantener la app como experiencia principal y evaluar un control web liviano como "invitado rápido" en la Fase B. Se decide en un ADR.
