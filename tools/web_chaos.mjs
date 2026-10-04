// Control web en condiciones feas (ADR 0022, docs/PRUEBA_REAL.md §6):
// Chromium real contra la TV de prueba, con cada celular detrás de su propio
// proxy de "Wi-Fi fea" (tools/web_e2e_lib.mjs). Prueba, en medio de una
// competencia de verdad:
//
//   - página cargada con 3G lento; Wi-Fi con demora, variación y retransmisiones;
//   - Wi-Fi que se corta 5, 12 y 20 s (con y sin aviso de "sin conexión");
//   - celular bloqueado 30 s con la conexión abierta (aviso de la TV sin cuenta),
//     bloqueado 20 s con la conexión muerta (iOS) y 40 s (se le vence el lugar);
//   - girar el celular con el dedo apoyado; recargar; dos pestañas del mismo
//     celular; "Atrás" del navegador;
//   - unirse con la partida en curso y con la sala llena (entra solo después);
//   - pantallas chicas (iPhone SE), grandes y con zoom de página 150 %;
//   - la TV que cierra el juego y la que se reinicia (código nuevo).
//
//   node tools/web_chaos.mjs --out=/tmp/chaos            (unos 6 minutos)
//   node tools/web_chaos.mjs --out=/tmp/chaos --long     (+ 5 min en segundo plano)
//
// Saca capturas de cada mensaje nuevo en --out. Sale con 1 si algo falla.
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { loadPlaywright, CHROMIUM, checker, TvProcess, FlakyProxy, throughProxy, touch, lockPhone, unlockPhone, sleep } from "./web_e2e_lib.mjs";

const { chromium, devices } = await loadPlaywright();
const args = Object.fromEntries(process.argv.slice(2).map((a) => a.replace(/^--/, "").split("=")));
const OUT = resolve(args.out || "/tmp/party-games-chaos");
const LONG = "long" in args;
mkdirSync(OUT, { recursive: true });
const counter = checker();
const ok = counter.ok;
const fails = () => counter.failures;

const tv = new TvProcess({ out: OUT, ws: 47890, http: 47880 });
let shotIndex = 0;
const shot = async (page, name) => page.screenshot({ path: resolve(OUT, `${String(++shotIndex).padStart(2, "0")}_${name}.png`), scale: "css" });
const tvShot = (name) => tv.cmd(`shot ${String(++shotIndex).padStart(2, "0")}_tv_${name}`);
const pg = (page, expr) => page.evaluate(expr);
const waitFor = (page, fn, arg, timeout) => page.waitForFunction(fn, arg, { timeout }).then(() => true, () => false);
const UA_IPHONE = devices["iPhone 13"].userAgent;
const SE = { viewport: { width: 375, height: 667 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, userAgent: UA_IPHONE };
const SE_LAND = { ...SE, viewport: { width: 667, height: 375 } };

let browser;
const pages = [];
const jsErrors = [];
const proxies = [];

try {
  tv.start();
  let info = await tv.ready();
  ok(true, `TV lista (sala ${info.code}, web ${info.http}, juego ${info.ws})`);
  const base = () => `http://127.0.0.1:${info.http}`;
  browser = await chromium.launch({ executablePath: CHROMIUM, args: ["--no-sandbox", "--autoplay-policy=no-user-gesture-required"] });

  // Un celular: su contexto (su localStorage) detrás de su propio proxy de Wi-Fi.
  async function phone(name, dev, { proxy = true } = {}) {
    const ctx = await browser.newContext({ ...dev, locale: "es-AR" });
    let px = null;
    if (proxy) { px = new FlakyProxy(info.ws); await px.listen(); proxies.push(px); await throughProxy(ctx, info.ws, px.port); }
    const page = await ctx.newPage();
    page.on("pageerror", (e) => jsErrors.push(name + ": " + e.message));
    pages.push(page);
    const cdp = await ctx.newCDPSession(page);
    return { name, ctx, page, cdp, px };
  }
  async function join(p, nick, code = info.code) {
    await p.page.goto(`${base()}/${code}`);
    await p.page.fill("#name", nick);
    await p.page.click("#join-btn");
  }
  const joined = (p, timeout = 15000) => waitFor(p.page, () => window.__pg.state === "joined", null, timeout);
  const idOf = (p) => pg(p.page, () => window.__pg.info && window.__pg.info.id);
  async function stateLine() { const n = tv.lines.length; await tv.cmd("state"); return tv.lines.slice(n).find((l) => l.startsWith("E2E state ")) || ""; }
  // Que la TV esté con un juego andando (los juegos terminan solos en ~30–50 s).
  async function ensureGame() {
    for (let i = 0; i < 8; i++) {
      const s = await stateLine();
      if (/game=true/.test(s) && !/intro=true/.test(s) && !/summary=true/.test(s)) return true;
      if (/intro=true/.test(s)) await tv.cmd("skip");
      else if (/summary=true/.test(s)) await tv.cmd("continue");
      else if (/phase=lobby/.test(s)) await tv.cmd("start arena,paint,pool");
      else if (/tournament=false/.test(s) || /phase=results/.test(s)) { await tv.cmd("lobby"); }
      await sleep(400);
    }
    return false;
  }
  // Mira el aviso grande del celular durante `ms` y devuelve los textos que mostró.
  async function watchBanner(p, ms) {
    const seen = new Set();
    const end = Date.now() + ms;
    while (Date.now() < end) { const b = await pg(p.page, () => window.__pg.banner).catch(() => ""); if (b) seen.add(b); await sleep(150); }
    return [...seen];
  }

  // --- 1. Página con 3G lento ---------------------------------------------------------------
  console.log("\n· Carga con 3G lento");
  // En un contexto aparte: la limitación de Chrome se queda pegada al WebSocket
  // que se abrió con ella (la Wi-Fi cargada del juego se prueba con el proxy).
  const slow = await phone("3G", devices["iPhone 13"], { proxy: false });
  await slow.cdp.send("Network.enable");
  await slow.cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 400, downloadThroughput: 50 * 1024, uploadThroughput: 25 * 1024 });
  const t0 = Date.now();
  await slow.page.goto(`${base()}/${info.code}`, { waitUntil: "load" });
  await slow.page.evaluate(() => document.fonts.ready);
  const loadMs = Date.now() - t0;
  ok(loadMs < 10000, `la página (con fuentes y logo) carga en ${(loadMs / 1000).toFixed(1)} s con 3G lento (400 ms, 400 kbit/s)`);
  await slow.ctx.close();
  const A = await phone("A", devices["iPhone 13 landscape"]);
  await join(A, "Juli");
  ok(await joined(A), "Juli (iPhone apaisado) se une");

  const B = await phone("B", SE);
  await join(B, "Tomi");
  ok(await joined(B), "Tomi (iPhone SE vertical) se une");
  const C = await phone("C", devices["Pixel 5 landscape"]);
  await join(C, "Pablo");
  ok(await joined(C), "Pablo (Pixel) se une");
  ok(await ensureGame(), "la TV arranca una competencia");
  await A.page.waitForFunction(() => window.__pg.phase === "playing", null, { timeout: 10000 }).catch(() => null);

  // --- 2. Wi-Fi con demora y retransmisiones ----------------------------------------------------
  console.log("\n· Wi-Fi cargada (120–300 ms y 5 % de retransmisiones de 0,3–1,2 s)");
  for (const p of [A, B, C]) p.px.setConditions({ latency: 120, jitter: 180, stallChance: 0.05 });
  await tv.cmd('layout joystick {"hint":"Wi-Fi cargada"}');
  await A.page.waitForFunction(() => document.getElementById("hint").textContent === "Wi-Fi cargada", null, { timeout: 8000 }).catch(() => null);
  const fromLossy = tv.lines.length;
  let box = await A.page.locator("#pad").boundingBox();
  let o = { x: box.x + box.width * 0.3, y: box.y + box.height * 0.5 };
  await touch(A.cdp, "touchStart", [o]);
  const bannerDuringLag = new Set();
  for (let i = 0; i < 60; i++) {
    const a = i / 5;
    await touch(A.cdp, "touchMove", [{ x: o.x + Math.cos(a) * 110, y: o.y + Math.sin(a) * 110 }]);
    if (i % 6 === 0) { const b = await pg(A.page, () => window.__pg.banner); if (b) bannerDuringLag.add(b); }
    await sleep(200);
  }
  const beforeRelease = tv.lines.length;
  await touch(A.cdp, "touchEnd", []);
  const inputs = tv.lines.slice(fromLossy).filter((l) => l.startsWith("E2E input 1 ")).length;
  ok(inputs > 20, `con la Wi-Fi cargada la entrada sigue llegando (${inputs} cambios en 12 s)`);
  ok(!!(await tv.waitLine(/^E2E input 1 0\.00 0\.00 0$/, 4000, beforeRelease).catch(() => null)), "y soltar el dedo llega (el joystick no queda trabado tras un tirón)");
  ok(bannerDuringLag.size === 0 && (await pg(A.page, () => window.__pg.state)) === "joined", "sin falsos «Se cortó la conexión» por demoras de hasta 1,5 s");
  ok(!tv.lines.slice(fromLossy).some((l) => l.startsWith("E2E players reconnected")), "nadie se reconecta por la demora");
  await shot(A.page, "wifi_cargada_senal");
  for (const p of [A, B, C]) p.px.setConditions({});

  // --- 3. Wi-Fi que se corta --------------------------------------------------------------------
  for (const secs of [5, 12, 20]) {
    console.log(`\n· Wi-Fi de Juli cortada ${secs} s`);
    await ensureGame();
    const idBefore = await idOf(A);
    const offline = secs === 20;  // En el corte largo además el celular avisa "sin conexión" (Wi-Fi apagada).
    A.px.cut();
    if (offline) await A.cdp.send("Network.emulateNetworkConditions", { offline: true, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
    const banners = await watchBanner(A, Math.min(secs, 9) * 1000);
    if (secs >= 12) {
      await shot(A.page, offline ? "corte_wifi_sin_conexion" : "corte_wifi_reconectando");
      const toasts = await tv.toasts();
      ok(toasts.some((t) => /Juli/.test(t) || /s$|sin señal/.test(t)), "la TV avisa que Juli no está: " + JSON.stringify(toasts));
      if (secs === 12) await tvShot("aviso_juli_corte");
    }
    await sleep(Math.max(0, secs * 1000 - Math.min(secs, 9) * 1000));
    if (offline) {
      ok(banners.some((b) => b.startsWith("Tu celular se quedó sin Wi-Fi")), "sin Wi-Fi: «Tu celular se quedó sin Wi-Fi» (" + banners.join(" | ") + ")");
      await A.cdp.send("Network.emulateNetworkConditions", { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
    } else if (secs >= 12) {
      ok(banners.some((b) => b.startsWith("Se cortó la conexión")), "aviso «Se cortó la conexión · Reconectando…» (" + banners.join(" | ") + ")");
    }
    const tBack = Date.now();
    A.px.restore();
    const back = await A.page.waitForFunction(() => window.__pg.state === "joined" && !window.__pg.banner, null, { timeout: 15000 }).then(() => true, () => false);
    ok(back && (await idOf(A)) === idBefore, `vuelve sola a su lugar (${idBefore}P) ${((Date.now() - tBack) / 1000).toFixed(1)} s después de volver la Wi-Fi`);
    const ps = await tv.players();
    ok(ps.find((p) => p.id === idBefore)?.connected === true && ps.length === 3, "la TV la tiene conectada, en su lugar, sin duplicados");
  }

  // --- 4. Celular bloqueado -----------------------------------------------------------------------
  console.log("\n· Tomi bloquea el celular 30 s (la conexión queda abierta)");
  await ensureGame();
  const idB = await idOf(B);
  await lockPhone(B.page, B.cdp);
  await sleep(6000);
  let toasts = await tv.toasts();
  ok(toasts.includes("Tomi no responde — su lugar lo espera"), "la TV: «Tomi no responde — su lugar lo espera», sin cuenta (" + JSON.stringify(toasts) + ")");
  await tvShot("aviso_tomi_bloqueado");
  await sleep(26000);
  toasts = await tv.toasts();
  ok(toasts.includes("sin señal") && !toasts.some((t) => /^\d+ s$/.test(t)), "a los 32 s sigue sin cuenta regresiva (" + JSON.stringify(toasts) + ")");
  ok((await tv.players()).some((p) => p.id === idB), "conserva su lugar");
  await unlockPhone(B.page, B.cdp);
  ok(await waitFor(B.page, () => window.__pg.state === "joined" && !window.__pg.banner, null, 6000) && (await idOf(B)) === idB, "al desbloquear vuelve solo a su lugar");
  await sleep(500);
  ok((await tv.players()).find((p) => p.id === idB)?.connected === true, "la TV lo ve conectado otra vez");

  console.log("\n· Pablo bloquea 20 s y el celular corta la conexión (iOS)");
  await ensureGame();
  const idC = await idOf(C);
  await lockPhone(C.page, C.cdp);
  C.px.killSilently();
  await sleep(4000);
  toasts = await tv.toasts();
  ok(toasts.some((t) => /Pablo se desconectó — esperando que vuelva \(\d+ s\)|^\d+ s$/.test(t)), "con la conexión cerrada la TV cuenta la reserva (" + JSON.stringify(toasts) + ")");
  await sleep(16000);
  await unlockPhone(C.page, C.cdp);
  ok(await waitFor(C.page, () => window.__pg.state === "joined" && !window.__pg.banner, null, 8000) && (await idOf(C)) === idC, "al desbloquear (socket muerto) reconecta solo a su lugar");

  // --- 5. Girar el celular con el dedo apoyado ---------------------------------------------------
  console.log("\n· Girar el celular en medio del juego");
  await ensureGame();
  await tv.cmd('layout joystick_ab {"a":"Patear","b":"Saltar"}');
  await A.page.waitForFunction(() => window.__pg.layout === "joystick_ab", null, { timeout: 5000 }).catch(() => null);
  box = await A.page.locator("#pad").boundingBox();
  o = { x: box.x + box.width * 0.25, y: box.y + box.height * 0.5 };
  let mark = tv.lines.length;
  await touch(A.cdp, "touchStart", [o]);
  await touch(A.cdp, "touchMove", [{ x: o.x + 150, y: o.y }]);
  ok(!!(await tv.waitLine(/^E2E input 1 1\.00 0\.00 0$/, 4000, mark).catch(() => null)), "joystick a fondo antes de girar");
  mark = tv.lines.length;
  await A.page.setViewportSize({ width: 390, height: 844 });
  await A.cdp.send("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 3, mobile: true, screenOrientation: { type: "portraitPrimary", angle: 0 } });
  await A.page.evaluate(() => window.dispatchEvent(new Event("orientationchange")));
  ok(!!(await tv.waitLine(/^E2E input 1 0\.00 0\.00 0$/, 3000, mark).catch(() => null)), "al girar se suelta el joystick (la TV recibe 0, 0)");
  await sleep(500);
  const padSize = await A.page.evaluate(() => { const c = document.getElementById("pad"); return { w: c.clientWidth, h: c.clientHeight, bw: c.width, bh: c.height }; });
  ok(padSize.h > padSize.w && padSize.bw === Math.round(padSize.w * 2), `el control se rearma vertical (${padSize.w}×${padSize.h})`);
  await touch(A.cdp, "touchEnd", []);
  box = await A.page.locator("#pad").boundingBox();
  mark = tv.lines.length;
  await touch(A.cdp, "touchStart", [{ x: box.x + box.width * 0.25, y: box.y + box.height * 0.72, id: 1 }, { x: box.x + box.width * 0.82, y: box.y + box.height * 0.8, id: 2 }]);
  ok(!!(await tv.waitLine(/^E2E input 1 0\.00 0\.00 1$/, 4000, mark).catch(() => null)), "después de girar, A responde donde se dibuja");
  await shot(A.page, "girado_vertical");
  await touch(A.cdp, "touchEnd", []);
  await A.cdp.send("Emulation.clearDeviceMetricsOverride");
  await A.page.setViewportSize(devices["iPhone 13 landscape"].viewport);

  // --- 6. Recargar en medio del juego --------------------------------------------------------------
  console.log("\n· Recargar la página en medio del juego");
  await ensureGame();
  await B.page.reload();
  ok(await joined(B, 10000) && (await idOf(B)) === idB, "recargar devuelve a Tomi a su lugar");
  ok(await waitFor(B.page, () => window.__pg.phase === "playing", null, 5000), "y sigue en la partida");

  // --- 7. Dos pestañas del mismo celular ----------------------------------------------------------
  console.log("\n· Dos pestañas del mismo celular");
  const A2page = await A.ctx.newPage();
  A2page.on("pageerror", (e) => jsErrors.push("A2: " + e.message));
  pages.push(A2page);
  await A2page.goto(`${base()}/${info.code}`);
  const A2 = { page: A2page };
  ok(await joined(A2, 10000), "la segunda pestaña entra con el lugar guardado");
  ok(await waitFor(A.page, () => window.__pg.state === "idle", null, 5000), "la primera queda afuera…");
  ok(/otra pestaña/.test(await pg(A.page, () => window.__pg.status)), "…y dice «Abriste el control en otra pestaña…»");
  await shot(A.page, "otra_pestana");
  await sleep(6000);
  ok((await pg(A.page, () => window.__pg.state)) === "idle" && (await pg(A2page, () => window.__pg.state)) === "joined", "no se pelean el lugar (6 s después siguen igual)");
  ok((await tv.players()).length === 3, "la TV no duplica al jugador");
  await A.page.click("#join-btn");
  ok(await joined(A, 8000) && await waitFor(A2page, () => window.__pg.state === "idle", null, 5000), "«¡Unirme!» en la primera recupera el control y la segunda queda afuera");
  await A2page.close();

  // --- 8. Botón Atrás del navegador ----------------------------------------------------------------
  console.log("\n· «Atrás» del navegador");
  await C.page.mouse.click(5, 5).catch(() => null);  // Un toque (Chrome solo respeta el historial creado en un gesto).
  await C.page.locator(".bar").click({ position: { x: 5, y: 5 } }).catch(() => null);
  await C.page.goBack({ timeout: 3000 }).catch(() => null);
  await sleep(400);
  ok((await pg(C.page, () => window.__pg && window.__pg.state)) === "joined", "el primer «Atrás» no saca del juego");
  ok(await C.page.locator("#toast").evaluate((e) => !e.hidden && e.textContent.includes("Salir")).catch(() => false), "y avisa «Para irte, mantené apretado «Salir»»");
  await shot(C.page, "atras_aviso");
  await C.page.goBack({ timeout: 5000 }).catch(() => null);
  await sleep(1500);
  const left = C.page.url().startsWith(base());
  ok(!left, "el segundo «Atrás» sí sale de la página (" + C.page.url() + ")");
  await C.page.goForward({ timeout: 8000 }).catch(() => null);
  ok(await joined(C, 10000) && (await idOf(C)) === idC, "«Adelante» lo devuelve a su lugar");

  // --- 9. Celular bloqueado 40 s: se le vence el lugar ------------------------------------------------
  console.log("\n· Pablo bloquea 40 s con la conexión muerta (se le vence el lugar)");
  await ensureGame();
  await lockPhone(C.page, C.cdp);
  C.px.killSilently();
  await sleep(40000);
  await ensureGame();
  await unlockPhone(C.page, C.cdp);
  ok(await waitFor(C.page, () => window.__pg.state === "idle" && /se liberó tu lugar/.test(window.__pg.status), null, 15000),
    "al volver: «Estuviste afuera un rato y se liberó tu lugar… volvés a entrar apenas termine»");
  await shot(C.page, "lugar_vencido");

  // --- 10. Unirse con la partida en curso; sala llena ---------------------------------------------------
  console.log("\n· Unirse con la partida en curso");
  const D = await phone("D", SE_LAND);
  await join(D, "Sofi");
  ok(await waitFor(D.page, () => /medio de una partida/.test(window.__pg.status), null, 8000), "«Están en medio de una partida. Dejá esta pantalla abierta: entrás apenas termine.»");
  await shot(D.page, "partida_en_curso_se_chico");
  ok((await pg(D.page, () => window.__pg.retrying)) === "game_in_progress", "y reintenta solo");
  await tv.cmd("lobby");
  ok(await joined(D, 15000), "al volver la TV al lobby, Sofi entra sola");
  ok(await joined(C, 15000), "y Pablo también (su lugar se había vencido)");
  ok((await tv.players()).length === 4, "la sala tiene 4");

  console.log("\n· Sala llena");
  const E = await phone("E", devices["Pixel 5"]);
  await join(E, "Caro");
  ok(await waitFor(E.page, () => /sala está llena/.test(window.__pg.status), null, 8000), "«¡La sala está llena! … entrás apenas haya lugar»");
  await shot(E.page, "sala_llena");
  // Sofi se va con "Salir": Caro entra sola.
  const lb = await D.page.locator("#leave").boundingBox();
  await touch(D.cdp, "touchStart", [{ x: lb.x + lb.width / 2, y: lb.y + lb.height / 2 }]);
  await sleep(1300);
  await touch(D.cdp, "touchEnd", []);
  ok(await joined(E, 15000), "cuando se libera un lugar, Caro entra sola");

  // --- 11. Pantallas chicas, grandes y con zoom ----------------------------------------------------------
  console.log("\n· Tamaños de pantalla");
  await tv.cmd('layout joystick_ab {"a":"Patear","b":"Saltar","hint":"Movete y usá A y B"}');
  const sizes = [
    // El zoom de página (Safari "aA", zoom de texto de Chrome) achica el viewport en px CSS.
    ["se_vertical", 375, 667], ["se_apaisado", 667, 375], ["se_zoom150_vertical", 250, 445], ["se_zoom150_apaisado", 445, 250],
    ["promax_vertical", 430, 932], ["tablet_apaisado", 1180, 820],
  ];
  for (const [name, w, h] of sizes) {
    await B.page.setViewportSize({ width: w, height: h });
    await sleep(600);
    const fit = await B.page.evaluate(() => {
      const vw = innerWidth, vh = innerHeight;
      const r = (id) => document.getElementById(id).getBoundingClientRect();
      const inside = (x) => x.left >= -1 && x.right <= vw + 1 && x.top >= -1 && x.bottom <= vh + 1;
      const me = document.querySelector(".me").getBoundingClientRect(), sig = r("signal"), leave = r("leave");
      return { scroll: document.documentElement.scrollWidth <= vw + 1, bar: inside(leave) && inside(sig) && me.right <= sig.left + 1, pad: r("pad").height > 80 };
    });
    ok(fit.scroll && fit.bar && fit.pad, `${name} (${w}×${h}): todo entra, sin desbordes (${JSON.stringify(fit)})`);
    await shot(B.page, "tam_" + name);
  }
  await B.page.setViewportSize(SE.viewport);
  // La pantalla de unirse con el zoom alto: el formulario entra (con desplazamiento) y el botón se alcanza.
  for (const [name, vp] of [["unirse_zoom150_vertical", { width: 250, height: 445 }], ["unirse_zoom150_apaisado", { width: 445, height: 250 }]]) {
    const z = await phone("Z", { ...SE, viewport: vp }, { proxy: false });
    await z.page.goto(`${base()}/`);
    await z.page.click("#join-btn");  // Sin apodo: muestra el aviso de error.
    await sleep(400);
    const fit = await z.page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1 && document.getElementById("join-btn").getBoundingClientRect().width > 100);
    ok(fit, `${name}: el formulario entra a lo ancho`);
    await shot(z.page, name);
    await z.ctx.close();
  }

  // --- 12. La TV cierra el juego y se reinicia ------------------------------------------------------------
  console.log("\n· La TV cierra el juego (avisando) y vuelve con otro código");
  await tv.cmd("layout wait");
  await tv.close();
  const bannersClosed = await watchBanner(A, 6000);
  ok(bannersClosed.some((b) => b.startsWith("No encontramos el juego en la TV")), "«No encontramos el juego en la TV · ¿Se cerró en la TV?…» (" + bannersClosed.join(" | ") + ")");
  await shot(A.page, "tv_cerrada");
  const oldCode = info.code;
  tv.start();
  info = await tv.ready(tv.lines.length);
  ok(info.code !== oldCode && info.ws === 47890, `la TV vuelve (sala nueva ${info.code})`);
  ok(await waitFor(A.page, () => /la TV se reinició/.test(window.__pg.status), null, 20000), "el celular: «Ese código ya no sirve: la TV se reinició. Escaneá otra vez el QR…»");
  ok((await A.page.locator("#code").inputValue()) === "", "y borra el código viejo");
  await shot(A.page, "tv_reiniciada");
  // Vuelve a escanear el QR: apodo guardado, código nuevo, un toque.
  await A.page.goto(`${base()}/${info.code}`);
  ok((await A.page.locator("#name").inputValue()) === "Juli", "al escanear el QR nuevo el apodo ya está");
  await A.page.click("#join-btn");
  ok(await joined(A), "y con un toque vuelve a jugar");

  console.log("\n· La TV se corta de golpe");
  await tv.kill();
  const bannersKilled = await watchBanner(A, 7000);
  ok(bannersKilled.length > 0 && bannersKilled.some((b) => b.startsWith("No encontramos el juego en la TV") || b.startsWith("Se cortó la conexión")),
    "aviso al cortarse la TV (" + bannersKilled.join(" | ") + ")");

  if (LONG) {
    console.log("\n· (largo) Pestaña en segundo plano 5 min con la conexión abierta");
    tv.start();
    info = await tv.ready(tv.lines.length);
    const F = await phone("F", devices["iPhone 13"]);
    await join(F, "Lu");
    await joined(F);
    const idF = await idOf(F);
    await lockPhone(F.page, F.cdp);
    await sleep(5 * 60000);
    ok((await tv.players()).some((p) => p.id === idF), "tras 5 min con la conexión abierta conserva el lugar");
    await unlockPhone(F.page, F.cdp);
    ok(await joined(F, 10000) && (await idOf(F)) === idF && await waitFor(F.page, () => !window.__pg.banner, null, 8000), "al volver, sigue en su lugar");
  }

  ok(jsErrors.length === 0, "sin errores de JS en las páginas" + (jsErrors.length ? ": " + jsErrors.join(" / ") : ""));
} catch (e) {
  console.error("FALLA:", e);
  counter.failures++;
  for (const p of pages) {
    if (p.isClosed()) continue;
    try {
      console.error("  estado de un celular:", JSON.stringify(await p.evaluate(() => ({ state: window.__pg.state, banner: window.__pg.banner, status: window.__pg.status }))));
      await p.screenshot({ path: resolve(OUT, `falla_${pages.indexOf(p)}.png`), scale: "css" });
    } catch (e2) { /* nada */ }
  }
} finally {
  try { await browser?.close(); } catch (e) { /* nada */ }
  for (const px of proxies) await px.close().catch(() => null);
  await tv.stop();
  console.log(`\n${fails() === 0 ? "Todo OK" : fails() + " fallas"} · capturas en ${OUT}`);
  process.exit(fails() ? 1 : 0);
}
