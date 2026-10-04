// Piezas compartidas de las pruebas del control web con navegadores reales
// (tools/web_e2e.mjs y tools/web_chaos.mjs, ADR 0022):
//
// - TvProcess: levanta la TV de prueba (tools/web_e2e_host.gd, con pantalla
//   virtual), le da órdenes por un archivo y lee lo que informa. Se puede
//   cerrar y volver a abrir (la TV que se reinicia).
// - FlakyProxy: un proxy TCP entre los celulares y el WebSocket de la TV que
//   imita una Wi-Fi fea: demora con variación, retransmisiones (pérdida de
//   paquetes), cortes de N segundos (lo que se manda queda en el aire y llega
//   al volver, como en TCP) y conexiones que mueren sin aviso.
// - throughProxy: hace que una página use el proxy (cambia el puerto que la TV
//   inyecta en la página y la CSP).
// - touch, hide/show y freeze/thaw (pantalla bloqueada / app en segundo plano).
import { spawn } from "node:child_process";
import { writeFileSync, appendFileSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import net from "node:net";

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function loadPlaywright() {
  // Playwright puede estar instalado global (en el contenedor: /opt/node22/lib/node_modules).
  return import("playwright").catch(() => import(process.env.PLAYWRIGHT_MODULE || "/opt/node22/lib/node_modules/playwright/index.mjs"));
}
export const CHROMIUM = process.env.PW_CHROMIUM || "/opt/pw-browsers/chromium-1194/chrome-linux/chrome";

// Contador de comprobaciones: ok(cond, "qué") imprime y cuenta las fallas.
export function checker() {
  const c = { failures: 0 };
  c.ok = (cond, what) => { console.log((cond ? "  ok    " : "  FALLA ") + what); if (!cond) c.failures++; return !!cond; };
  return c;
}

// --- TV ---------------------------------------------------------------------------
export class TvProcess {
  constructor({ out, ws, http }) {
    this.out = out; this.wsPort = ws; this.httpPort = http;
    this.cmdFile = resolve(out, "cmd.txt"); this.events = resolve(out, "events.log");
    this.lines = []; this.waiters = []; this.seen = 0; this.proc = null; this.pump = null;
  }
  start() {
    writeFileSync(this.cmdFile, "");
    try { rmSync(this.events); } catch (e) { /* no estaba */ }
    this.seen = 0;
    this.proc = spawn("xvfb-run", ["-a", "-s", "-screen 0 1920x1080x24", "godot", "--path", ".", "--rendering-driver", "opengl3", "--audio-driver", "Dummy",
      "-s", "res://tools/web_e2e_host.gd", "--", `--cmd=${this.cmdFile}`, `--out=${this.out}`, `--ws=${this.wsPort}`, `--http=${this.httpPort}`],
    { stdio: ["ignore", "pipe", "pipe"], detached: true });
    this.proc.stdout.on("data", () => {});
    this.proc.stderr.on("data", (d) => { const t = d.toString(); appendFileSync(resolve(this.out, "host_stderr.log"), t); if (/SCRIPT ERROR/.test(t)) process.stderr.write(t); });
    // La TV informa en events.log (la salida estándar de un hijo puede quedar en el buffer).
    clearInterval(this.pump);
    this.pump = setInterval(() => this.read(), 100);
  }
  read() {
    let text = "";
    try { text = readFileSync(this.events, "utf8"); } catch (e) { return; }
    const all = text.split("\n");
    for (; this.seen < all.length - 1; this.seen++) {
      const line = all[this.seen].trim();
      if (!line.startsWith("E2E ")) continue;
      this.lines.push(line);
      for (const w of [...this.waiters]) if (w.re.test(line)) { this.waiters.splice(this.waiters.indexOf(w), 1); w.resolve(line); }
    }
  }
  // Espera una línea que cumpla `re`, mirando solo desde la posición `from`.
  waitLine(re, timeout = 15000, from = 0) {
    const found = this.lines.slice(from).find((l) => re.test(l));
    if (found) return Promise.resolve(found);
    return new Promise((res, rej) => {
      const w = { re, resolve: res };
      this.waiters.push(w);
      setTimeout(() => { if (this.waiters.includes(w)) { this.waiters.splice(this.waiters.indexOf(w), 1); rej(new Error("timeout esperando " + re)); } }, timeout);
    });
  }
  // Arranque: devuelve {code, http, ws} cuando la TV está lista.
  async ready(from = 0) {
    const first = await this.waitLine(/^E2E code=/, 90000, from);
    return { code: /code=(\w{4})/.exec(first)[1], http: +/http=(\d+)/.exec(first)[1], ws: +/ws=(\d+)/.exec(first)[1] };
  }
  async cmd(c, timeout = 40000) {
    const from = this.lines.length;
    appendFileSync(this.cmdFile, c + "\n");
    await this.waitLine(new RegExp("^E2E done " + c.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$"), timeout, from);
  }
  async players() {
    const n = this.lines.length;
    await this.cmd("players");
    const l = this.lines.slice(n).find((x) => x.startsWith("E2E players asked "));
    return JSON.parse(l.slice("E2E players asked ".length));
  }
  async toasts() {
    const n = this.lines.length;
    await this.cmd("toasts");
    const l = this.lines.slice(n).find((x) => x.startsWith("E2E toasts "));
    return JSON.parse(l.slice("E2E toasts ".length));
  }
  // Cierre: "close" avisa a los celulares (1001); kill() es la TV que se corta de golpe.
  async close() { appendFileSync(this.cmdFile, "close\n"); await this.exited(8000); }
  kill() { try { process.kill(-this.proc.pid, "SIGKILL"); } catch (e) { try { this.proc.kill("SIGKILL"); } catch (e2) { /* nada */ } } return this.exited(5000); }
  exited(ms) {
    return new Promise((res) => {
      if (!this.proc || this.proc.exitCode !== null) { res(); return; }
      const t = setTimeout(() => { try { process.kill(-this.proc.pid, "SIGKILL"); } catch (e) { /* nada */ } res(); }, ms);
      this.proc.once("exit", () => { clearTimeout(t); res(); });
    });
  }
  async stop() {
    try { appendFileSync(this.cmdFile, "quit\n"); } catch (e) { /* nada */ }
    await sleep(1500);
    clearInterval(this.pump);
    try { process.kill(-this.proc.pid, "SIGTERM"); } catch (e) { try { this.proc.kill("SIGTERM"); } catch (e2) { /* nada */ } }
  }
}

// --- Toques y ciclo de vida de la página ---------------------------------------------
// Toques reales por CDP (multitáctil): points = [{x, y, id}].
export async function touch(cdp, type, points) {
  await cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map((p) => ({ x: p.x, y: p.y, id: p.id ?? 0, radiusX: 8, radiusY: 8, force: 1 })) });
}
// Pestaña escondida / visible (Chromium sin pantalla no lo hace solo).
export async function setHidden(page, hidden) {
  await page.evaluate((h) => {
    Object.defineProperty(document, "visibilityState", { configurable: true, get: () => (h ? "hidden" : "visible") });
    Object.defineProperty(document, "hidden", { configurable: true, get: () => h });
    document.dispatchEvent(new Event("visibilitychange"));
  }, hidden);
}
// Pantalla bloqueada: la página se esconde y su JS deja de correr (como iOS
// al bloquear o Android con la app en segundo plano): se detiene en el
// depurador (Page.setWebLifecycleState "frozen" no congela una página que el
// navegador sin pantalla considera visible). El socket sigue abierto salvo
// que el proxy lo mate; lo que llega queda esperando.
export async function lockPhone(page, cdp) { await setHidden(page, true); await cdp.send("Debugger.enable"); await cdp.send("Debugger.pause"); }
export async function unlockPhone(page, cdp) { await cdp.send("Debugger.resume"); await cdp.send("Debugger.disable"); await setHidden(page, false); }

// --- Wi-Fi fea ---------------------------------------------------------------------------
export class FlakyProxy {
  constructor(targetPort, targetHost = "127.0.0.1") {
    this.targetPort = targetPort; this.targetHost = targetHost;
    this.latency = 0; this.jitter = 0; this.stallChance = 0; this.stallMs = [300, 1200];
    this.down = false; this.conns = new Set(); this.server = null; this.port = 0;
  }
  listen(port = 0) {
    this.server = net.createServer((client) => this.accept(client));
    return new Promise((res) => this.server.listen(port, "127.0.0.1", () => { this.port = this.server.address().port; res(this.port); }));
  }
  // Demora por tramo (ms), variación y "retransmisiones": con probabilidad
  // stallChance un pedazo se demora 0,3–1,2 s más (y los que vienen atrás, también: TCP entrega en orden).
  setConditions({ latency = 0, jitter = 0, stallChance = 0 } = {}) { this.latency = latency; this.jitter = jitter; this.stallChance = stallChance; }
  accept(client) {
    const c = { client, upstream: null, queues: { up: [], down: [] }, nextAt: { up: 0, down: 0 }, held: [], dead: false };
    this.conns.add(c);
    client.setNoDelay(true);
    const connectUp = () => {
      if (c.dead) return;
      c.upstream = net.connect(this.targetPort, this.targetHost);
      c.upstream.setNoDelay(true);
      c.upstream.on("data", (d) => this.pass(c, "down", d));
      c.upstream.on("close", () => this.end(c));
      c.upstream.on("error", () => this.end(c));
      for (const d of c.held) this.pass(c, "up", d);
      c.held = [];
    };
    c.connectUp = connectUp;
    client.on("data", (d) => { if (!c.upstream) c.held.push(d); else this.pass(c, "up", d); });
    client.on("close", () => this.end(c));
    client.on("error", () => this.end(c));
    // Con la Wi-Fi caída la conexión nueva queda colgada (como un SYN sin respuesta).
    if (!this.down) connectUp();
  }
  pass(c, dir, data) {
    if (c.dead) return;
    const now = Date.now();
    let delay = this.latency + Math.random() * this.jitter;
    if (this.stallChance && Math.random() < this.stallChance) delay += this.stallMs[0] + Math.random() * (this.stallMs[1] - this.stallMs[0]);
    const at = Math.max(now + delay, c.nextAt[dir]);
    c.nextAt[dir] = at;
    c.queues[dir].push({ at, data });
    this.flush(c, dir);
  }
  flush(c, dir) {
    if (c.dead || this.down || c.timer?.[dir]) return;
    const q = c.queues[dir];
    if (!q.length) return;
    const wait = q[0].at - Date.now();
    c.timer = c.timer || {};
    c.timer[dir] = setTimeout(() => {
      c.timer[dir] = 0;
      if (c.dead || this.down) return;
      while (q.length && q[0].at <= Date.now()) {
        const { data } = q.shift();
        const to = dir === "up" ? c.upstream : c.client;
        if (to && !to.destroyed) to.write(data);
      }
      this.flush(c, dir);
    }, Math.max(0, wait));
  }
  end(c) {
    if (c.dead) return;
    c.dead = true;
    this.conns.delete(c);
    if (c.timer) { clearTimeout(c.timer.up); clearTimeout(c.timer.down); }
    try { c.client.destroy(); } catch (e) { /* nada */ }
    try { c.upstream?.destroy(); } catch (e) { /* nada */ }
  }
  // Wi-Fi caída: nada pasa en ningún sentido (queda en la cola) y las
  // conexiones nuevas cuelgan. Al volver, lo encolado llega (TCP retransmite).
  cut() { this.down = true; for (const c of this.conns) if (c.timer) { clearTimeout(c.timer.up); clearTimeout(c.timer.down); c.timer = null; } }
  restore() {
    this.down = false;
    for (const c of [...this.conns]) {
      if (c.dead) continue;
      if (!c.upstream) c.connectUp();
      // Lo que quedó en la cola sale ya, en orden (como las retransmisiones de TCP).
      for (const dir of ["up", "down"]) { const now = Date.now(); for (const item of c.queues[dir]) item.at = Math.min(item.at, now); c.nextAt[dir] = now; this.flush(c, dir); }
    }
  }
  // La TV pierde la conexión (la ve cerrarse) pero el celular no se entera:
  // su socket queda "abierto" y mudo (iOS al bloquear, router que la descarta).
  killSilently() {
    for (const c of [...this.conns]) {
      c.dead = true; this.conns.delete(c);
      if (c.timer) { clearTimeout(c.timer.up); clearTimeout(c.timer.down); }
      try { c.upstream?.destroy(); } catch (e) { /* nada */ }
      c.client.removeAllListeners("data"); c.client.on("data", () => {});  // Se traga lo que mande.
      c.client.on("error", () => {});
    }
  }
  count() { return this.conns.size; }
  close() { for (const c of [...this.conns]) this.end(c); return new Promise((r) => this.server.close(() => r())); }
}

// Hace que las páginas de `context` usen el proxy: la TV inyecta su puerto de
// WebSocket en la página (<meta name="pg-ws-port">) y en la CSP; acá se cambia
// por el del proxy.
export async function throughProxy(context, wsPort, proxyPort) {
  await context.route("**/*", async (route) => {
    const req = route.request();
    if (req.resourceType() !== "document") { await route.continue(); return; }
    const res = await route.fetch();
    const headers = { ...res.headers() };
    for (const k of Object.keys(headers)) if (k.toLowerCase() === "content-security-policy") headers[k] = headers[k].replace(":" + wsPort, ":" + proxyPort);
    const body = (await res.text()).replace(`name="pg-ws-port" content="${wsPort}"`, `name="pg-ws-port" content="${proxyPort}"`);
    await route.fulfill({ status: res.status(), headers, body });
  });
}
