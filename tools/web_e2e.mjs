// Prueba de punta a punta del control web (ADR 0022) con navegadores reales.
//
// Levanta la TV de prueba (tools/web_e2e_host.gd, con pantalla virtual),
// abre tres controles web con Playwright emulando celulares (iPhone apaisado,
// iPhone vertical y un Pixel), se une, elige mascota, prueba cada layout con
// toques reales (multitáctil incluido), fuerza una reconexión (se cierra la
// página y se abre otra con el mismo localStorage) y juega dos rondas de una
// competencia. Saca capturas de los celulares y de la TV en --out.
//
//   node tools/web_e2e.mjs --out=/tmp/e2e            (Chromium de Playwright en /opt/pw-browsers)
//   PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers node tools/web_e2e.mjs --out=/tmp/e2e --keep
//
// Sale con código 1 si alguna comprobación falla. Necesita xvfb-run y godot en el PATH.
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync, appendFileSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";

// Playwright puede estar instalado global (en el contenedor: /opt/node22/lib/node_modules).
const pw = await import("playwright").catch(() => import(process.env.PLAYWRIGHT_MODULE || "/opt/node22/lib/node_modules/playwright/index.mjs"));
const { chromium, devices } = pw;

const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const OUT = resolve(args.out || "/tmp/party-games-e2e");
const WS_PORT = 47990, HTTP_PORT = 47980;
mkdirSync(OUT, { recursive: true });
const CMD = resolve(OUT, "cmd.txt");
writeFileSync(CMD, "");
try { rmSync(resolve(OUT, "events.log")); } catch (e) { /* no estaba */ }

let failures = 0;
const pages = [];  // Para volcar el estado de cada celular si algo falla.
const ok = (cond, what) => { console.log((cond ? "  ok    " : "  FALLA ") + what); if (!cond) failures++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- TV ---------------------------------------------------------------------------
const lines = [];
const waiters = [];
const host = spawn("xvfb-run", ["-a", "-s", "-screen 0 1920x1080x24", "godot", "--path", ".", "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
  "-s", "res://tools/web_e2e_host.gd", "--", `--cmd=${CMD}`, `--out=${OUT}`, `--ws=${WS_PORT}`, `--http=${HTTP_PORT}`], { stdio: ["ignore", "pipe", "pipe"], detached: true });
// La TV informa en events.log (la salida estándar de un hijo puede quedar en el buffer).
const EVENTS = resolve(OUT, "events.log");
let seen = 0;
function pump() {
  let text = "";
  try { text = readFileSync(EVENTS, "utf8"); } catch (e) { return; }
  const all = text.split("\n");
  for (; seen < all.length - 1; seen++) {
    const line = all[seen].trim();
    if (!line.startsWith("E2E ")) continue;
    lines.push(line);
    for (const w of [...waiters]) if (w.re.test(line)) { waiters.splice(waiters.indexOf(w), 1); w.resolve(line); }
  }
}
const pumpTimer = setInterval(pump, 100);
host.stdout.on("data", () => {});
host.stderr.on("data", (d) => { const t = d.toString(); appendFileSync(resolve(OUT, "host_stderr.log"), t); if (/ERROR|SCRIPT ERROR/.test(t)) process.stderr.write(t); });
// Espera una línea que cumpla `re`, mirando solo desde la posición `from`
// (así "E2E done players" de una orden anterior no da por cumplida la nueva).
function waitLine(re, timeout = 15000, from = 0) {
  const found = lines.slice(from).find((l) => re.test(l));
  if (found) return Promise.resolve(found);
  return new Promise((resolve, reject) => {
    const w = { re, resolve };
    waiters.push(w);
    setTimeout(() => { if (waiters.includes(w)) { waiters.splice(waiters.indexOf(w), 1); reject(new Error("timeout esperando " + re)); } }, timeout);
  });
}
async function tv(cmd) { const from = lines.length; appendFileSync(CMD, cmd + "\n"); await waitLine(new RegExp("^E2E done " + cmd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$"), 40000, from); }
async function players() { const n = lines.length; await tv("players"); const l = lines.slice(n).find((x) => x.startsWith("E2E players asked ")); return JSON.parse(l.slice("E2E players asked ".length)); }
let mark = 0;  // Desde dónde buscar las entradas de un gesto (se marca antes de tocar).
const setMark = () => { mark = lines.length; };
let shotIndex = 0;
async function shot(page, name) { await page.screenshot({ path: resolve(OUT, `${String(++shotIndex).padStart(2, "0")}_${name}.png`), scale: "css" }); }
async function tvShot(name) { await tv(`shot ${String(++shotIndex).padStart(2, "0")}_tv_${name}`); }

// Toques reales por CDP (multitáctil): points = [{x, y, id}].
async function touch(cdp, type, points) {
  await cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map((p) => ({ x: p.x, y: p.y, id: p.id ?? 0, radiusX: 8, radiusY: 8, force: 1 })) });
}
async function padBox(page) { return page.locator("#pad").boundingBox(); }
async function waitInput(re, timeout = 4000) { return waitLine(re, timeout, mark); }

try {
  const first = await waitLine(/^E2E code=/, 90000);
  const code = /code=(\w{4})/.exec(first)[1];
  const httpPort = +/http=(\d+)/.exec(first)[1];
  ok(httpPort >= HTTP_PORT && httpPort < HTTP_PORT + 5, `la TV sirve el control web en ${httpPort} (sala ${code})`);
  const base = `http://127.0.0.1:${httpPort}`;

  // --- Navegadores -------------------------------------------------------------------
  const exe = process.env.PW_CHROMIUM || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";
  const browser = await chromium.launch({ executablePath: exe, args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"] });
  const mk = (dev, extra = {}) => browser.newContext({ ...dev, deviceScaleFactor: 2, locale: "es-AR", permissions: [], ...extra });
  const iphoneL = devices["iPhone 13 landscape"], iphoneP = devices["iPhone 13"], pixel = devices["Pixel 5 landscape"];
  const ctxA = await mk(iphoneL), ctxB = await mk(iphoneP), ctxC = await mk(pixel);
  const pageA = await ctxA.newPage(), pageB = await ctxB.newPage(), pageC = await ctxC.newPage();
  pages.push(pageA, pageB, pageC);
  for (const p of [pageA, pageB, pageC]) p.on("pageerror", (e) => { console.log("  JS error:", e.message); failures++; });

  // A entra por el QR (código en la ruta); B escribe la dirección y el código; C también por QR.
  await pageA.goto(`${base}/${code}`); await pageA.waitForLoadState("networkidle");
  await shot(pageA, "join_iphone_land");
  ok(await pageA.locator("#code").inputValue() === code, "el código llega prellenado desde el enlace del QR");
  const csp = await (await fetch(`${base}/${code}`)).headers.get("content-security-policy");
  ok(/connect-src ws:\/\/127\.0\.0\.1:\d+/.test(csp || ""), "CSP con el WebSocket a la misma IP: " + csp);
  await pageB.goto(`${base}/`); await pageB.waitForLoadState("networkidle");
  await shot(pageB, "join_iphone_port");
  await pageC.goto(`${base}/${code}`); await pageC.waitForLoadState("networkidle");

  await pageA.fill("#name", "Juli"); await pageA.click("#join-btn");
  await pageA.waitForFunction(() => window.__pg.state === "joined", null, { timeout: 20000 });
  ok((await pageA.evaluate(() => window.__pg.info.id)) === 1, "Juli se une como 1P");
  // El input del código es transparente (las fichas van encima): se escribe con el teclado.
  await pageB.fill("#name", "Tomi"); await pageB.locator("#code").focus(); await pageB.keyboard.type(code.toLowerCase());
  ok(await pageB.locator("#code-tiles .tile >> nth=3").evaluate((e) => e.textContent) === code[3], "las fichas muestran el código tipeado (en mayúsculas)");
  await pageB.click("#join-btn");
  await pageB.waitForFunction(() => window.__pg.state === "joined", null, { timeout: 20000 });
  await pageC.fill("#name", "Pablo"); await pageC.click("#join-btn");
  await pageC.waitForFunction(() => window.__pg.state === "joined", null, { timeout: 20000 });
  let ps = await players();
  ok(ps.length === 3 && ps.map((p) => p.name).join() === "Juli,Tomi,Pablo", "la TV tiene a los 3 (" + ps.map((p) => p.name).join(", ") + ")");
  await sleep(1200);
  await shot(pageA, "wait_lobby_iphone_land");
  await shot(pageB, "wait_lobby_iphone_port");
  await tvShot("lobby_3");

  // Mascota: Tomi elige conejo rosa; Juli no puede elegir el rosa (ocupado).
  const stepsToBunny = await pageB.evaluate(() => (6 - window.__pg.info.style + 7) % 7);
  for (let i = 0; i < stepsToBunny; i++) { await pageB.click("#style-next"); await sleep(150); }
  await pageB.click(".swatch >> nth=5");
  await pageB.waitForFunction(() => window.__pg.info.colorIndex === 5 && window.__pg.info.style === 6, null, { timeout: 4000 });
  await sleep(600);
  ok(await pageA.locator(".swatch >> nth=5").evaluate((e) => e.classList.contains("taken")), "el rosa aparece ocupado en el celular de Juli");
  await pageA.click(".swatch >> nth=5", { force: true });
  await sleep(500);
  ok((await pageA.evaluate(() => window.__pg.info.colorIndex)) === 0, "Juli sigue roja: el color ocupado no se puede elegir");
  await pageC.click(".swatch >> nth=8"); await pageC.click("#style-prev");
  await sleep(800);
  await shot(pageB, "look_iphone_port");
  await shot(pageA, "look_iphone_land");
  await tvShot("lobby_looks");
  ps = await players();
  ok(ps[1].color === 5 && ps[1].style === 6 && ps[2].color === 8, "la TV refleja las mascotas elegidas");

  // --- Cada layout, con toques reales ----------------------------------------------
  const cdpA = await ctxA.newCDPSession(pageA), cdpB = await ctxB.newCDPSession(pageB);
  await tv('layout joystick {"hint":"Mové para juntar estrellas"}');
  await pageA.waitForFunction(() => window.__pg.layout === "joystick");
  await sleep(400);
  let box = await padBox(pageA);
  let o = { x: box.x + box.width * 0.3, y: box.y + box.height * 0.5 };
  setMark();
  await touch(cdpA, "touchStart", [{ x: o.x, y: o.y }]);
  await touch(cdpA, "touchMove", [{ x: o.x + 200, y: o.y }]);
  let l = await waitInput(/^E2E input 1 1\.00 0\.00 0$/).catch(() => null);
  ok(!!l, "joystick: arrastrar a la derecha llega como axis (1, 0)");
  await sleep(300);
  await shot(pageA, "joystick_iphone_land");
  await touch(cdpA, "touchEnd", []);
  l = await waitInput(/^E2E input 1 0\.00 0\.00 0$/).catch(() => null);
  ok(!!l, "joystick: soltar vuelve a (0, 0)");
  await sleep(300);
  await shot(pageB, "joystick_iphone_port");

  await tv('layout one_button {"label":"¡TOCÁ!","hint":"Tocá cuando la TV lo diga"}');
  await pageA.waitForFunction(() => window.__pg.layout === "one_button");
  await sleep(400);
  box = await padBox(pageA);
  setMark();
  await touch(cdpA, "touchStart", [{ x: box.x + box.width * 0.7, y: box.y + box.height * 0.5 }]);
  l = await waitInput(/^E2E input 1 0\.00 0\.00 1$/).catch(() => null);
  ok(!!l, "botón: tocar manda btn = 1");
  await sleep(250);
  await shot(pageA, "button_iphone_land");
  await touch(cdpA, "touchEnd", []);
  await waitInput(/^E2E input 1 0\.00 0\.00 0$/).catch(() => null);
  await shot(pageB, "button_iphone_port");

  await tv('layout slider_h {"hint":"Deslizá para mover tu paleta"}');
  await pageA.waitForFunction(() => window.__pg.layout === "slider_h");
  await sleep(400);
  box = await padBox(pageA);
  setMark();
  await touch(cdpA, "touchStart", [{ x: box.x + box.width * 0.5, y: box.y + box.height * 0.5 }]);
  await touch(cdpA, "touchMove", [{ x: box.x + box.width * 0.92, y: box.y + box.height * 0.5 }]);
  l = await waitInput(/^E2E input 1 1\.00 0\.00 0$/).catch(() => null);
  ok(!!l, "slider: el dedo en la punta derecha es axis.x = 1");
  await touch(cdpA, "touchEnd", []);
  await sleep(300);
  await shot(pageA, "slider_iphone_land");
  const afterRelease = await waitInput(/^E2E input 1 0\.00 0\.00 0$/, 800).catch(() => null);
  ok(!afterRelease, "slider: al soltar, la paleta se queda donde estaba");

  await tv('layout joystick_ab {"a":"Patear","b":"Saltar","hint":"Movete y usá A y B"}');
  await pageA.waitForFunction(() => window.__pg.layout === "joystick_ab");
  await sleep(400);
  box = await padBox(pageA);
  // Dos dedos a la vez: uno en el joystick (hacia arriba) y otro en A; después un tercero en B.
  o = { x: box.x + box.width * 0.27, y: box.y + box.height * 0.5 };
  setMark();
  await touch(cdpA, "touchStart", [{ x: o.x, y: o.y, id: 1 }]);
  await touch(cdpA, "touchMove", [{ x: o.x, y: o.y - 200, id: 1 }]);
  setMark();
  await touch(cdpA, "touchStart", [{ x: o.x, y: o.y - 200, id: 1 }, { x: box.x + box.width * 0.88, y: box.y + box.height * 0.66, id: 2 }]);
  l = await waitInput(/^E2E input 1 0\.00 -1\.00 1$/).catch(() => null);
  ok(!!l, "joystick + A: arriba y A a la vez (axis (0, -1), btn 1)");
  setMark();
  await touch(cdpA, "touchStart", [{ x: o.x, y: o.y - 200, id: 1 }, { x: box.x + box.width * 0.88, y: box.y + box.height * 0.66, id: 2 }, { x: box.x + box.width * 0.7, y: box.y + box.height * 0.36, id: 3 }]);
  l = await waitInput(/^E2E input 1 0\.00 -1\.00 3$/).catch(() => null);
  ok(!!l, "joystick + A + B: los tres dedos (btn 3)");
  await sleep(250);
  await shot(pageA, "joystick_ab_iphone_land");
  await touch(cdpA, "touchEnd", []);
  await waitInput(/^E2E input 1 0\.00 0\.00 0$/).catch(() => null);
  await shot(pageB, "joystick_ab_iphone_port");
  // Vertical: joystick abajo a la izquierda y A abajo a la derecha, también con toques.
  box = await padBox(pageB);
  setMark();
  await touch(cdpB, "touchStart", [{ x: box.x + box.width * 0.25, y: box.y + box.height * 0.72, id: 1 }, { x: box.x + box.width * 0.85, y: box.y + box.height * 0.8, id: 2 }]);
  await touch(cdpB, "touchMove", [{ x: box.x + box.width * 0.25 + 150, y: box.y + box.height * 0.72, id: 1 }, { x: box.x + box.width * 0.85, y: box.y + box.height * 0.8, id: 2 }]);
  l = await waitInput(/^E2E input 2 1\.00 0\.00 1$/).catch(() => null);
  ok(!!l, "vertical: joystick a la derecha + A (jugador 2)");
  await sleep(200);
  await shot(pageB, "joystick_ab_iphone_port_touch");
  await touch(cdpB, "touchEnd", []);
  await tv("layout wait");

  // --- Reconexión: se cierra la página de Juli y se abre otra con el mismo localStorage --
  await pageA.close();
  await waitLine(/^E2E players disconnected /, 8000).catch(() => null);
  ps = await players();
  ok(ps.length === 3 && ps[0].connected === false, "la TV reserva el lugar de Juli al cerrarse la página");
  await tvShot("lobby_juli_desconectada");
  const pageA2 = await ctxA.newPage();
  pageA2.on("pageerror", (e) => { console.log("  JS error:", e.message); failures++; });
  await pageA2.goto(`${base}/`);
  await pageA2.waitForFunction(() => window.__pg.state === "joined", null, { timeout: 10000 });
  ps = await players();
  ok(ps[0].connected === true && ps[0].id === 1 && ps[0].name === "Juli", "Juli vuelve sola a su lugar (1P) al abrir la página de nuevo");
  ok((await pageA2.evaluate(() => window.__pg.info.id)) === 1, "la página sabe que sigue siendo 1P");
  await tvShot("lobby_juli_volvio");
  // Corte del WebSocket en caliente (pantalla bloqueada): reintenta con backoff.
  await pageC.evaluate(() => window.__pg.drop());
  await pageC.waitForFunction(() => window.__pg.state === "reconnecting", null, { timeout: 3000 }).catch(() => null);
  await pageC.waitForFunction(() => window.__pg.state === "joined", null, { timeout: 20000 });
  ps = await players();
  ok(ps[2].connected === true && ps[2].id === 3, "Pablo se reconecta solo tras cortarse el WebSocket");

  // --- Competencia: Arena (joystick) y Carrera de toques (botón) --------------------------
  await tv("start arena,tap_race");
  await pageA2.waitForFunction(() => window.__pg.layout === "joystick" && window.__pg.phase === "playing", null, { timeout: 8000 });
  await tv("skip");
  const cdpA2 = await ctxA.newCDPSession(pageA2);
  box = await padBox(pageA2);
  o = { x: box.x + box.width * 0.3, y: box.y + box.height * 0.5 };
  setMark();
  await touch(cdpA2, "touchStart", [{ x: o.x, y: o.y }]);
  for (let i = 0; i < 40; i++) { const a = i / 6; await touch(cdpA2, "touchMove", [{ x: o.x + Math.cos(a) * 120, y: o.y + Math.sin(a) * 120 }]); await sleep(50); }
  await tvShot("arena_jugando");
  await shot(pageA2, "arena_joystick");
  await touch(cdpA2, "touchEnd", []);
  await tv("finish");
  await pageA2.waitForFunction(() => window.__pg.phase === "results", null, { timeout: 8000 });
  await pageA2.waitForSelector("#standing:not([hidden])", { timeout: 5000 });
  await sleep(800);
  await shot(pageA2, "standing_round_iphone_land");
  await shot(pageB, "standing_round_iphone_port");
  await tvShot("resumen");
  await tv("continue");
  await pageA2.waitForFunction(() => window.__pg.layout === "one_button", null, { timeout: 8000 });
  await tv("skip");
  box = await padBox(pageA2);
  for (let i = 0; i < 12; i++) { await touch(cdpA2, "touchStart", [{ x: box.x + box.width * 0.7, y: box.y + box.height * 0.5 }]); await sleep(60); await touch(cdpA2, "touchEnd", []); await sleep(60); }
  await tvShot("tap_race_jugando");
  await tv("finish");
  await pageA2.waitForFunction(() => window.__pg.phase === "results", null, { timeout: 8000 });
  await sleep(1000);
  await tv("continue");
  await sleep(2500);
  await pageA2.waitForSelector("#standing:not([hidden])", { timeout: 8000 });
  ok(await pageA2.locator("#standing-round").evaluate((e) => e.textContent) === "Resultado final", "el celular muestra el resultado final del podio");
  await shot(pageA2, "standing_final_iphone_land");
  await shot(pageC, "standing_final_pixel");
  await tvShot("podio");
  await tv("lobby");
  await pageA2.waitForFunction(() => window.__pg.phase === "lobby", null, { timeout: 8000 });

  // --- Salir: hay que mantener apretado --------------------------------------------------
  const cdpC = await ctxC.newCDPSession(pageC);
  const leaveBox = await pageC.locator("#leave").boundingBox();
  const leaveAt = { x: leaveBox.x + leaveBox.width / 2, y: leaveBox.y + leaveBox.height / 2 };
  await touch(cdpC, "touchStart", [leaveAt]);
  await sleep(200);
  await touch(cdpC, "touchEnd", []);
  await sleep(300);
  ok(await pageC.locator("#toast").evaluate((e) => !e.hidden && e.textContent.includes("Mantené")), "soltar «Salir» antes de tiempo solo avisa");
  await shot(pageC, "toast_salir_pixel");
  await touch(cdpC, "touchStart", [leaveAt]);
  await sleep(1300);
  await touch(cdpC, "touchEnd", []);
  await pageC.waitForFunction(() => window.__pg.state === "idle", null, { timeout: 3000 });
  await waitLine(/^E2E players left /, 5000).catch(() => null);
  ps = await players();
  ok(ps.length === 2, "mantener «Salir» libera el lugar en la TV");

  await browser.close();
} catch (e) {
  console.error("FALLA:", e);
  failures++;
  for (const p of pages) {
    if (p.isClosed()) continue;
    try {
      const st = await p.evaluate(() => ({ state: window.__pg.state, layout: window.__pg.layout, status: (document.getElementById("join-status-text") || {}).textContent, joinHidden: document.getElementById("join").hidden }));
      console.error("  estado de un celular:", JSON.stringify(st));
      await p.screenshot({ path: resolve(OUT, `falla_${pages.indexOf(p)}.png`), scale: "css" });
    } catch (e2) { /* nada */ }
  }
} finally {
  appendFileSync(CMD, "quit\n");
  await sleep(1500);
  clearInterval(pumpTimer);
  try { process.kill(-host.pid, "SIGTERM"); } catch (e) { host.kill("SIGTERM"); }  // xvfb-run y godot (grupo de procesos).
  console.log(`\n${failures === 0 ? "Todo OK" : failures + " fallas"} · capturas en ${OUT}`);
  process.exit(failures ? 1 : 0);
}
