# Skills de Claude Code para este proyecto

## Qué es una skill

Una **skill** es un instructivo empaquetado (`SKILL.md`) que Claude Code carga **solo cuando la tarea lo necesita**. Tiene un nombre, una descripción de cuándo usarla y los pasos a seguir.

*Ejemplo:* si pedís "agregá un minijuego de esquivar bloques", Claude ve que la tarea coincide con la descripción de `nuevo-minijuego`, la carga y sigue el checklist (registrar en el registry, usar `draw_hud`, definir `score_label`, correr tests…). Sin la skill tendría que redescubrir esas convenciones leyendo el código cada vez.

Diferencia con `CLAUDE.md`: `CLAUDE.md` se lee **siempre** (reglas generales, cortas); una skill se lee **a demanda** (procedimientos largos de una tarea concreta). Así el contexto no se llena de instrucciones que no aplican.

## Skills propias del proyecto (`.claude/skills/`)

| Skill | Cuándo se usa | Por qué hace falta |
|---|---|---|
| `nuevo-minijuego` | Crear o cambiar un minijuego | Es la tarea que más se va a repetir (roadmap: 8–10 juegos). Garantiza que todos sigan el mismo contrato y estilo visual |
| `diseno-tv` | Tocar pantallas, componentes, colores o navegación | Resume el sistema visual y las reglas de TV (D-pad, overscan, legibilidad, accesibilidad) |
| `verificar-visual` | Después de cambios de UI o para actualizar `docs/img` | Los tests no "ven" la pantalla: genera capturas reales con pantalla virtual |
| `nuevo-layout` | Sumar un tipo de control (dos botones, inclinación…) | Toca protocolo, celular, lobby, capturas y docs a la vez; fácil olvidar algo |

*Ejemplo de uso:* "Cambiá el color del botón principal y mostrame cómo queda" → `diseno-tv` (cambiar el token `ACCENT` en `UiTheme`) + `verificar-visual` (capturas antes/después).

## Hook de inicio (`.claude/hooks/session-start.sh`)

No es una skill, pero resuelve el problema más práctico: en Claude Code en la web el contenedor arranca sin Godot. El hook instala **Godot 4.4.1** (la misma versión que la CI) e importa el proyecto, así los tests corren desde el primer mensaje. Es idempotente: si Godot ya está, no descarga nada. Solo corre en sesiones en la nube (`CLAUDE_CODE_REMOTE=true`).

## Skills incluidas en Claude Code: cuáles sirven acá

| Skill | ¿Sirve? | Para qué, en este proyecto |
|---|---|---|
| `code-review` | ✅ Sí | Revisar cada PR buscando bugs (ej. un juego que llama a `finish` dos veces) |
| `security-review` | ✅ Sí | Obligatoria al tocar `HostServer`, `Protocol` o cualquier entrada de red |
| `simplify` | ✅ Sí | Limpieza tras agregar varios juegos (código repetido entre juegos) |
| `run` | ✅ Sí | Levantar TV + control para probar; se apoya en `verificar-visual` |
| `session-start-hook` | ✅ Ya usada | Generó el hook de inicio |
| `init` | ➖ Ya hecho | `CLAUDE.md` ya existe |
| `claude-api` | ❌ No | El juego no usa modelos de IA |
| `docx`, `xlsx`, `pptx`, `pdf` | ❌ No | No hay documentos de oficina; la documentación es Markdown en `docs/` |
| `dataviz` | ❌ Por ahora no | Útil recién con la analítica anónima de la Fase 3 del roadmap |
| `artifact-design`, `artifact-capabilities` | ✅ Sí | La página de avances del proyecto (tablero, capturas y bitácora) |
| `web-artifacts-builder` | ❌ No | Para apps web complejas; el tablero no lo necesita |

## Plugins del catálogo (se instalan desde claude.ai)

| Plugin | Recomendación | Para qué |
|---|---|---|
| **Design** (Anthropic) | ✅ Instalar ahora | Revisión de accesibilidad, crítica de diseño y textos de interfaz |
| **Marketing** (Anthropic) | ⏳ En la Fase D del [plan](PLAN.md) | Fichas de tienda, lanzamiento y comunicación |
| Axe, Snagly y otros de QA web | ❌ No | Auditan sitios web con navegador; no aplican a una app de Godot |

No hay skills ni plugins específicos de Godot en el catálogo: el conocimiento del motor queda en las skills propias de arriba.

## Cuándo crear una skill nueva

Cuando una tarea se repite y tiene pasos que es fácil olvidar. Candidatas a futuro:

- `release`: exportar Android/iOS y subir a las tiendas, cuando exista el pipeline (Fase B del [plan](PLAN.md)).
- `benchmark`: correr y leer `tools/benchmark.gd` contra los presupuestos, cuando esté integrado.
