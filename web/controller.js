/* Control web de PARTY-GAME (ADR 0022).
 *
 * Habla el mismo protocolo v2 que la app del celular (docs/PROTOCOL.md) por
 * WebSocket contra la TV que sirvió esta página: manda `join`, `input`,
 * `look`, `ping` y `leave`; recibe `welcome`, `reject`, `layout`, `phase`,
 * `pong`, `feedback`, `appearance` y `standing`. La TV es la autoritativa:
 * acá solo se dice "el dedo está acá" (axis) y "este botón está apretado" (btn).
 *
 * Seguridad: todo texto que llega por la red se pinta con textContent
 * (jamás como HTML) y cada mensaje se valida y recorta como hace
 * Protocol.parse_* en la TV; lo inválido se descarta sin romper nada.
 *
 * Sin frameworks ni nada externo: la Wi-Fi puede no tener internet.
 */
(function () {
  "use strict";

  // --- Protocolo (copiado de core/protocol/protocol.gd; un test lo compara) ----
  const PROTO = {
    VERSION: 2,
    WS_PORT: 47777,
    MAX_MESSAGE_BYTES: 512,
    NAME_MAX: 16,
    ROOM_ALPHABET: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
    LAYOUTS: ["wait", "joystick", "slider_h", "one_button", "joystick_ab"],
    PHASES: ["lobby", "playing", "results"],
    FEEDBACK: ["point", "hit", "win", "lose", "go", "count", "tap"],
    BTN_A: 1, BTN_B: 2,
    MAX_PLAYERS: 4, MAX_ROUNDS: 99, MAX_POINTS: 100000,
    COLORS: ["#E24B4A", "#378ADD", "#F5B82C", "#45C35A", "#8B5CF6", "#FF6FB5", "#2EC4D6", "#F5F7FB", "#2B2D3A", "#16171D"],
    COLOR_NAMES: ["Rojo", "Azul", "Amarillo", "Verde", "Violeta", "Rosa", "Celeste", "Blanco", "Grafito", "Negro"],
    STYLE_NAMES: ["Antena", "Oso", "Gato", "Brote", "Robot", "Diablito", "Conejo"],
  };
  const SEND_HZ = 30, KEEPALIVE_MS = 250, PING_MS = 1000, DEAD_ZONE = 0.12;
  const MAX_RECONNECT = 8, CONNECT_TIMEOUT_MS = 4000, HOLD_MS = 1000;
  const HINT_MAX = 48, LABEL_MAX = 12;
  const LAYOUT_HINTS = {
    joystick: "Mové tu mascota con el joystick",
    slider_h: "Deslizá el dedo para mover tu paleta",
    one_button: "Tocá el botón cuando la TV te diga",
    joystick_ab: "Movete con el joystick y usá A y B",
  };
  const LEAVE_HINT = "Mantené apretado «Salir» para irte";
  const INK = "#1D2140", PAPER = "#FFFFFF", ACCENT = "#FFC83D", DISH = "#2A3163", DISH_RIM = "#454E8C";
  const KEY_NEUTRAL = "#D5DBEA", SHADOW = "rgba(18,26,77,0.22)", GLASS = "rgba(255,255,255,0.55)";
  const LEAF = "#8BE36B", EAR_INNER = "#EE5A32", BUNNY_INNER = "#FFB3C7", METAL = "#C3CADB", SHOE = "#262B4D";

  const $ = (id) => document.getElementById(id);
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

  // --- Colores ----------------------------------------------------------------
  function hexToRgb(hex) {
    const h = hex.replace("#", "");
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }
  function rgbToHex(c) { return "#" + c.map((v) => clamp(Math.round(v), 0, 255).toString(16).padStart(2, "0")).join(""); }
  function mix(a, b, t) { const x = hexToRgb(a), y = hexToRgb(b); return rgbToHex(x.map((v, i) => v + (y[i] - v) * t)); }
  function darken(hex, k) { return rgbToHex(hexToRgb(hex).map((v) => v * (1 - k))); }
  function lighten(hex, k) { return rgbToHex(hexToRgb(hex).map((v) => v + (255 - v) * k)); }
  function luminance(hex) { const [r, g, b] = hexToRgb(hex); return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255; }
  function textOn(hex) { return luminance(hex) > 0.55 ? INK : PAPER; }

  // --- Validación de lo que llega por la red (como Protocol.parse_*) ----------
  const isNum = (v) => typeof v === "number" && Number.isFinite(v);
  function sanitizeName(raw) {
    if (typeof raw !== "string") return "";
    let out = "";
    for (const ch of raw.trim()) {
      const c = ch.codePointAt(0);
      if (c < 32 || (c >= 127 && c < 160)) continue;
      out += ch;
      if ([...out].length >= PROTO.NAME_MAX) break;
    }
    return out.trim();
  }
  function normalizeRoom(raw) { return String(raw || "").toUpperCase().replace(/\s+/g, ""); }
  function isValidRoom(code) { return typeof code === "string" && code.length === 4 && [...code].every((c) => PROTO.ROOM_ALPHABET.includes(c)); }
  function parseIndex(v, count) { return isNum(v) && Math.floor(v) === v && v >= 0 && v < count ? v : -1; }
  function parseColorIndex(v) { return parseIndex(v, PROTO.COLORS.length); }
  function parseStyleIndex(v) { return parseIndex(v, PROTO.STYLE_NAMES.length); }
  function parseStanding(m) {
    const limits = { round: [0, PROTO.MAX_ROUNDS], total_rounds: [0, PROTO.MAX_ROUNDS], place: [0, PROTO.MAX_PLAYERS], points: [0, PROTO.MAX_POINTS],
      total: [0, PROTO.MAX_POINTS], rank: [1, PROTO.MAX_PLAYERS], players: [1, PROTO.MAX_PLAYERS] };
    const out = {};
    for (const k in limits) {
      if (!isNum(m[k])) return null;
      out[k] = Math.floor(clamp(m[k], limits[k][0], limits[k][1]));
    }
    if (typeof m.final !== "boolean") return null;
    out.final = m.final;
    out.total_rounds = Math.max(out.total_rounds, out.round);
    out.players = Math.max(out.players, out.rank, out.place);
    return out;
  }
  function parseAppearance(m) {
    const color = parseColorIndex(m.color), style = parseStyleIndex(m.style);
    if (color < 0 || style < 0) return null;
    const taken = [];
    if (Array.isArray(m.taken)) for (const v of m.taken.slice(0, PROTO.COLORS.length)) {
      const i = parseColorIndex(v);
      if (i >= 0 && i !== color && !taken.includes(i)) taken.push(i);
    }
    return { color, style, taken };
  }
  function cleanText(v, max) { return typeof v === "string" ? v.replace(/[\n\t\r]/g, " ").trim().slice(0, max) : ""; }

  // --- Preferencias locales (apodo, mascota, token de la sala) ---------------
  const store = {
    get(k, d) { try { const v = localStorage.getItem("pg." + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("pg." + k, JSON.stringify(v)); } catch (e) { /* modo privado: sin memoria */ } },
    del(k) { try { localStorage.removeItem("pg." + k); } catch (e) { /* nada */ } },
  };

  // --- Enlace: puerto del WebSocket (lo inyecta la TV) y código en la ruta ----
  const wsPortMeta = parseInt((document.querySelector('meta[name="pg-ws-port"]') || {}).content, 10);
  const WS_PORT = Number.isInteger(wsPortMeta) && wsPortMeta > 0 && wsPortMeta < 65536 ? wsPortMeta : PROTO.WS_PORT;
  const urlRoom = normalizeRoom(location.pathname.split("/").filter(Boolean)[0] || "");
  const ROOM_FROM_URL = isValidRoom(urlRoom) ? urlRoom : "";

  // --- Red --------------------------------------------------------------------
  const net = {
    ws: null, state: "idle", room: "", name: "", token: "", look: {},
    seq: 0, attempt: 0, timer: 0, connectTimer: 0, pingTimer: 0, lastPing: 0, rtt: -1,
    info: null, // {id, name, color, colorIndex, style, taken}
    url() { return "ws://" + location.hostname + ":" + WS_PORT; },
    join(room, name, look) {
      this.room = room; this.name = name; this.look = look || {};
      this.token = store.get("room", "") === room ? store.get("token", "") : "";
      this.attempt = 0; this.rtt = -1;
      this.open("connecting");
    },
    open(newState) {
      this.closeSocket();
      this.state = newState;
      let ws;
      try { ws = new WebSocket(this.url()); } catch (e) { this.onClosed(1006, ""); return; }
      this.ws = ws;
      clearTimeout(this.connectTimer);
      this.connectTimer = setTimeout(() => { if (this.ws === ws && ws.readyState !== WebSocket.OPEN) { ws.close(); } }, CONNECT_TIMEOUT_MS);
      ws.onopen = () => { if (this.ws !== ws) return; this.sendJoin(); };
      ws.onmessage = (ev) => { if (this.ws === ws) this.handle(ev.data); };
      ws.onclose = (ev) => { if (this.ws !== ws) return; this.ws = null; this.onClosed(ev.code, ev.reason); };
      ws.onerror = () => { /* onclose llega igual */ };
    },
    closeSocket() {
      clearTimeout(this.connectTimer); clearInterval(this.pingTimer);
      if (this.ws) { const old = this.ws; this.ws = null; old.onclose = null; old.onmessage = null; try { old.close(); } catch (e) { /* nada */ } }
    },
    send(type, payload) {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return false;
      const msg = Object.assign({}, payload || {}, { v: PROTO.VERSION, type });
      try { this.ws.send(JSON.stringify(msg)); return true; } catch (e) { return false; }
    },
    sendJoin() {
      const payload = { room: this.room, name: this.name };
      if (this.token) payload.token = this.token;
      if (this.look.color !== undefined) payload.color = this.look.color;
      if (this.look.style !== undefined) payload.style = this.look.style;
      this.send("join", payload);
    },
    sendInput(axis, btn) {
      if (this.state !== "joined") return;
      this.seq += 1;
      this.send("input", { seq: this.seq, axis: [Math.round(axis[0] * 1000) / 1000, Math.round(axis[1] * 1000) / 1000], btn });
    },
    sendLook(color, style) {
      const look = {};
      if (parseColorIndex(color) >= 0) look.color = color;
      if (parseStyleIndex(style) >= 0) look.style = style;
      this.look = look;
      if (this.state === "joined" && Object.keys(look).length) this.send("look", look);
    },
    leave() {
      this.send("leave");
      this.state = "idle";
      this.token = ""; store.del("token"); store.del("room");
      if (this.ws) { try { this.ws.close(1000, "bye"); } catch (e) { /* nada */ } }
      this.closeSocket(); clearTimeout(this.timer);
      this.info = null;
    },
    handle(raw) {
      if (typeof raw !== "string" || raw.length === 0 || raw.length > 4096) return;
      let m;
      try { m = JSON.parse(raw); } catch (e) { return; }
      if (!m || typeof m !== "object" || Array.isArray(m) || typeof m.type !== "string" || !isNum(m.v)) return;
      switch (m.type) {
        case "welcome": {
          const id = isNum(m.playerId) ? Math.floor(m.playerId) : 0;
          if (id < 1 || id > PROTO.MAX_PLAYERS) return;
          const wasReconnecting = this.state === "reconnecting";
          this.token = typeof m.token === "string" && /^[0-9a-f]{32}$/i.test(m.token) ? m.token : "";
          const colorIndex = parseColorIndex(m.colorIndex);
          const hex = typeof m.color === "string" && /^[0-9a-f]{6}$/i.test(m.color) ? "#" + m.color.toUpperCase() : (colorIndex >= 0 ? PROTO.COLORS[colorIndex] : PROTO.COLORS[id - 1]);
          this.info = { id, name: sanitizeName(m.name) || this.name, color: hex, colorIndex, style: parseStyleIndex(m.style), taken: [] };
          this.state = "joined"; this.attempt = 0;
          store.set("token", this.token); store.set("room", this.room);
          clearInterval(this.pingTimer);
          this.pingTimer = setInterval(() => this.ping(), PING_MS);
          this.ping();
          ui.onJoined(wasReconnecting);
          ui.onPhase(PROTO.PHASES.includes(m.phase) ? m.phase : "lobby");
          break;
        }
        case "reject":
          this.state = "idle"; this.token = ""; store.del("token");
          this.closeSocket();
          ui.onRejected(typeof m.reason === "string" ? m.reason.slice(0, 32) : "unknown");
          break;
        case "layout": {
          const layout = PROTO.LAYOUTS.includes(m.layout) ? m.layout : "wait";
          const data = m.data && typeof m.data === "object" && !Array.isArray(m.data) ? m.data : {};
          ui.onLayout(layout, data);
          break;
        }
        case "phase":
          if (PROTO.PHASES.includes(m.phase)) ui.onPhase(m.phase);
          break;
        case "pong":
          if (isNum(m.t)) { const sample = performance.now() - m.t; this.rtt = this.rtt < 0 ? sample : this.rtt + (sample - this.rtt) * 0.2; ui.onLatency(this.rtt); }
          break;
        case "feedback":
          if (PROTO.FEEDBACK.includes(m.kind)) feedback(m.kind);
          break;
        case "appearance": {
          const look = parseAppearance(m);
          if (look && this.info) { this.info.colorIndex = look.color; this.info.color = PROTO.COLORS[look.color]; this.info.style = look.style; this.info.taken = look.taken; ui.onAppearance(); }
          break;
        }
        case "standing": {
          const s = parseStanding(m);
          if (s) ui.onStanding(s);
          break;
        }
        default: break; // Tipos desconocidos se ignoran (extensible).
      }
    },
    ping() { this.lastPing = performance.now(); this.send("ping", { t: Math.round(this.lastPing) }); },
    onClosed(code, reason) {
      clearInterval(this.pingTimer);
      if (this.state === "idle") return;
      if (code === 4000) { this.state = "idle"; this.token = ""; store.del("token"); ui.onRejected(reason || "unknown"); return; }
      if (this.state === "connecting") { this.state = "idle"; ui.onRejected("unreachable"); return; }
      if (!this.token) { this.state = "idle"; ui.onGaveUp(); return; }
      if (this.state === "joined") ui.onConnectionLost();
      this.attempt += 1;
      if (this.attempt > MAX_RECONNECT) { this.state = "idle"; ui.onGaveUp(); return; }
      this.state = "reconnecting";
      const delay = Math.min(500 * Math.pow(2, this.attempt - 1), 5000);
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.open("reconnecting"), delay);
    },
    // Al volver a la pestaña (pantalla bloqueada, otra app): reintentar ya.
    wake() {
      if (this.state === "reconnecting") { clearTimeout(this.timer); this.open("reconnecting"); }
      else if (this.state === "joined" && (!this.ws || this.ws.readyState !== WebSocket.OPEN)) { this.onClosed(1006, ""); }
    },
  };

  // --- Vibración, sonido y pantalla encendida -------------------------------------
  const VIBES = { point: [30], hit: [70, 40, 70], win: [60, 40, 60, 40, 140], lose: [160], go: [45], count: [15], tap: [12] };
  const TONES = { point: [[880, 0.06], [1320, 0.08]], hit: [[220, 0.12], [160, 0.14]], win: [[660, 0.08], [880, 0.08], [1100, 0.08], [1320, 0.18]], lose: [[300, 0.12], [220, 0.2]],
    go: [[990, 0.1]], count: [[660, 0.06]], tap: [[1200, 0.03]], select: [[1000, 0.04]], join: [[700, 0.06], [1050, 0.1]], pop: [[800, 0.05]] };
  let audioCtx = null, soundOn = store.get("sound", true);
  function unlockAudio() {
    if (!soundOn) return;
    try {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return;
      if (!audioCtx) audioCtx = new AC();
      if (audioCtx.state === "suspended") audioCtx.resume();
    } catch (e) { audioCtx = null; }
  }
  function tone(kind) {
    if (!soundOn || !audioCtx || audioCtx.state !== "running" || !TONES[kind]) return;
    let t = audioCtx.currentTime;
    for (const [freq, dur] of TONES[kind]) {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.type = "triangle"; o.frequency.value = freq;
      g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(0.18, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g).connect(audioCtx.destination); o.start(t); o.stop(t + dur + 0.02);
      t += dur * 0.9;
    }
  }
  function buzz(kind) { try { if (navigator.vibrate && VIBES[kind]) navigator.vibrate(VIBES[kind]); } catch (e) { /* iPhone: no vibra */ } }
  function feedback(kind) { buzz(kind); tone(kind); if (kind === "hit" || kind === "lose") ui.setMood("sad", 1800); if (kind === "win" || kind === "point") ui.setMood("happy", 1800); }
  let wakeLock = null;
  async function keepAwake() {
    try { if ("wakeLock" in navigator && !wakeLock) { wakeLock = await navigator.wakeLock.request("screen"); wakeLock.addEventListener("release", () => { wakeLock = null; }); } } catch (e) { wakeLock = null; }
  }

  // --- Mascota (cabeza y cuerpo, dibujados en canvas) --------------------------------
  // Versión chica de PlayerAvatar: cara blanca, ojos, cachetes y el accesorio
  // de cada estilo (antena, orejas de oso, gato, brote, robot, cuernos, conejo).
  function drawMascot(canvas, color, style, mood) {
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    const cssW = canvas.clientWidth || canvas.width, cssH = canvas.clientHeight || canvas.height;
    const W = Math.round(cssW * dpr), H = Math.round(cssH * dpr);
    if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; }
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);
    const s = Math.min(cssW, cssH), cx = cssW / 2, R = s * 0.3, cy = cssH * 0.5 - s * 0.02;
    const dark = luminance(color) < 0.2, body = dark ? lighten(color, 0.22) : color;
    const line = Math.max(1.5, s * 0.022);
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    const circle = (x, y, r, fill, stroke) => { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); if (stroke) { ctx.lineWidth = line; ctx.strokeStyle = INK; ctx.stroke(); } };
    const ellipse = (x, y, rx, ry, fill, stroke, rot) => { ctx.beginPath(); ctx.ellipse(x, y, rx, ry, rot || 0, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); if (stroke) { ctx.lineWidth = line; ctx.strokeStyle = INK; ctx.stroke(); } };
    // Sombra en el piso y cuerpo (debajo de la cabeza).
    ellipse(cx, cy + R * 1.95, R * 0.75, R * 0.16, SHADOW, false);
    const by = cy + R * 1.2;
    ellipse(cx, by, R * 0.62, R * 0.72, body, true);
    // Brazos: arriba si está contenta, abajo si no.
    const armY = mood === "happy" ? by - R * 0.55 : by + R * 0.15, armDx = R * 0.78;
    ellipse(cx - armDx, armY, R * 0.2, R * 0.2, body, true);
    ellipse(cx + armDx, armY, R * 0.2, R * 0.2, body, true);
    // Zapatos.
    ellipse(cx - R * 0.3, by + R * 0.62, R * 0.26, R * 0.14, SHOE, true);
    ellipse(cx + R * 0.3, by + R * 0.62, R * 0.26, R * 0.14, SHOE, true);
    // Accesorio (detrás de la cabeza).
    const top = cy - R;
    ctx.lineWidth = line; ctx.strokeStyle = INK;
    switch (style) {
      case 1: // Oso
        circle(cx - R * 0.72, top + R * 0.2, R * 0.3, body, true); circle(cx + R * 0.72, top + R * 0.2, R * 0.3, body, true);
        circle(cx - R * 0.72, top + R * 0.2, R * 0.15, lighten(body, 0.45), false); circle(cx + R * 0.72, top + R * 0.2, R * 0.15, lighten(body, 0.45), false);
        break;
      case 2: // Gato
        for (const sgn of [-1, 1]) {
          ctx.beginPath(); ctx.moveTo(cx + sgn * R * 0.35, top + R * 0.25); ctx.lineTo(cx + sgn * R * 0.95, top - R * 0.35); ctx.lineTo(cx + sgn * R * 0.95, top + R * 0.5); ctx.closePath();
          ctx.fillStyle = body; ctx.fill(); ctx.stroke();
          ctx.beginPath(); ctx.moveTo(cx + sgn * R * 0.5, top + R * 0.28); ctx.lineTo(cx + sgn * R * 0.85, top - R * 0.1); ctx.lineTo(cx + sgn * R * 0.85, top + R * 0.42); ctx.closePath(); ctx.fillStyle = EAR_INNER; ctx.fill();
        }
        break;
      case 3: // Brote
        ctx.beginPath(); ctx.moveTo(cx, top + R * 0.1); ctx.quadraticCurveTo(cx + R * 0.05, top - R * 0.3, cx, top - R * 0.5); ctx.lineWidth = line * 1.6; ctx.strokeStyle = "#4E9F57"; ctx.stroke();
        ellipse(cx - R * 0.3, top - R * 0.45, R * 0.32, R * 0.16, LEAF, true, -0.5); ellipse(cx + R * 0.3, top - R * 0.55, R * 0.32, R * 0.16, LEAF, true, 0.5);
        break;
      case 4: // Robot
        ctx.fillStyle = METAL; ctx.fillRect(cx - R * 0.08, top - R * 0.45, R * 0.16, R * 0.5); ctx.lineWidth = line; ctx.strokeStyle = INK; ctx.strokeRect(cx - R * 0.08, top - R * 0.45, R * 0.16, R * 0.5);
        circle(cx, top - R * 0.5, R * 0.16, "#E5484D", true);
        for (const sgn of [-1, 1]) { ctx.fillStyle = METAL; ctx.fillRect(cx + sgn * R - (sgn > 0 ? 0 : R * 0.22), cy - R * 0.18, R * 0.22, R * 0.36); ctx.strokeRect(cx + sgn * R - (sgn > 0 ? 0 : R * 0.22), cy - R * 0.18, R * 0.22, R * 0.36); }
        break;
      case 5: // Diablito
        for (const sgn of [-1, 1]) {
          ctx.beginPath(); ctx.moveTo(cx + sgn * R * 0.3, top + R * 0.22); ctx.quadraticCurveTo(cx + sgn * R * 0.75, top - R * 0.05, cx + sgn * R * 0.72, top - R * 0.5);
          ctx.quadraticCurveTo(cx + sgn * R * 0.95, top + R * 0.1, cx + sgn * R * 0.72, top + R * 0.5); ctx.closePath(); ctx.fillStyle = dark ? "#8C96C8" : darken(body, 0.25); ctx.fill(); ctx.stroke();
        }
        break;
      case 6: // Conejo
        for (const sgn of [-1, 1]) {
          ellipse(cx + sgn * R * 0.45, top - R * 0.45, R * 0.22, R * 0.62, body, true, sgn * 0.18);
          ellipse(cx + sgn * R * 0.45, top - R * 0.42, R * 0.1, R * 0.42, BUNNY_INNER, false, sgn * 0.18);
        }
        break;
      default: // Antena
        ctx.beginPath(); ctx.moveTo(cx, top + R * 0.05); ctx.lineTo(cx, top - R * 0.4); ctx.lineWidth = line * 1.5; ctx.strokeStyle = INK; ctx.stroke();
        circle(cx, top - R * 0.52, R * 0.16, "#E5484D", true);
        break;
    }
    // Cabeza y cara.
    circle(cx, cy, R, body, true);
    ctx.beginPath(); ctx.ellipse(cx - R * 0.35, cy - R * 0.45, R * 0.28, R * 0.14, -0.5, 0, Math.PI * 2); ctx.fillStyle = "rgba(255,255,255,0.45)"; ctx.fill();
    ellipse(cx, cy + R * 0.12, R * 0.68, R * 0.6, PAPER, false);
    const eyeY = cy + R * 0.02, eyeDx = R * 0.3;
    if (mood === "happy") {
      ctx.lineWidth = line * 1.8; ctx.strokeStyle = "#11132A";
      for (const sgn of [-1, 1]) { ctx.beginPath(); ctx.arc(cx + sgn * eyeDx, eyeY + R * 0.08, R * 0.14, Math.PI * 1.1, Math.PI * 1.9); ctx.stroke(); }
    } else {
      for (const sgn of [-1, 1]) { ellipse(cx + sgn * eyeDx, eyeY, R * 0.12, R * 0.17, "#11132A", false); circle(cx + sgn * eyeDx - R * 0.04, eyeY - R * 0.06, R * 0.04, PAPER, false); }
    }
    for (const sgn of [-1, 1]) circle(cx + sgn * R * 0.48, cy + R * 0.27, R * 0.1, "rgba(255,111,181,0.55)", false);
    ctx.beginPath();
    if (mood === "sad") { ctx.arc(cx, cy + R * 0.5, R * 0.14, Math.PI * 1.15, Math.PI * 1.85); ctx.lineWidth = line * 1.5; ctx.strokeStyle = "#11132A"; ctx.stroke(); circle(cx + R * 0.52, cy + R * 0.12, R * 0.06, "#3E7BFA", false); }
    else if (mood === "happy") { ctx.arc(cx, cy + R * 0.3, R * 0.2, 0.1, Math.PI - 0.1); ctx.fillStyle = "#11132A"; ctx.fill(); }
    else { ctx.arc(cx, cy + R * 0.28, R * 0.16, 0.25, Math.PI - 0.25); ctx.lineWidth = line * 1.5; ctx.strokeStyle = "#11132A"; ctx.stroke(); }
  }

  // --- Interfaz -------------------------------------------------------------------
  const el = {
    bg: $("bg"), bgTag: $("bg-tag"), join: $("join"), play: $("play"), form: $("join-form"), name: $("name"), code: $("code"),
    tiles: [...document.querySelectorAll("#code-tiles .tile")], status: $("join-status"), statusText: $("join-status-text"), joinBtn: $("join-btn"),
    tvAddress: $("tv-address"), meFace: $("me-face"), meTag: $("me-tag"), meName: $("me-name"), hint: $("hint"), signal: $("signal"), ms: $("ms"),
    sound: $("sound"), leave: $("leave"), ringFill: document.querySelector("#leave .ring-fill"), stage: $("stage"), wait: $("wait"), pad: $("pad"),
    cardTag: $("card-tag"), cardFace: $("card-face"), cardName: $("card-name"), cardStatus: $("card-status"), waitSub: $("wait-sub"),
    picker: $("picker"), styleName: $("style-name"), stylePrev: $("style-prev"), styleNext: $("style-next"), swatches: $("swatches"), colorName: $("color-name"),
    standing: $("standing"), standingBand: $("standing-band"), standingRound: $("standing-round"), standingCheer: $("standing-cheer"), standingMedal: $("standing-medal"),
    standingMedalText: $("standing-medal-text"), standingMain: $("standing-main"), standingTotal: $("standing-total"), toast: $("toast"),
  };

  const ui = {
    phase: "lobby", layout: "wait", mood: "normal", moodTimer: 0, toastTimer: 0, standingShown: false, lefty: store.get("lefty", false),
    init() {
      el.name.value = store.get("name", "");
      if (ROOM_FROM_URL) this.setCode(ROOM_FROM_URL);
      el.tvAddress.textContent = location.host;
      el.tvAddress.hidden = false;
      el.code.addEventListener("input", () => { const v = normalizeRoom(el.code.value).slice(0, 4); if (el.code.value !== v) el.code.value = v; this.paintTiles(); });
      el.code.addEventListener("focus", () => this.paintTiles(true));
      el.code.addEventListener("blur", () => this.paintTiles(false));
      el.name.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); (isValidRoom(el.code.value) ? el.joinBtn : el.code).focus(); if (isValidRoom(el.code.value)) this.submit(); } });
      el.form.addEventListener("submit", (e) => { e.preventDefault(); this.submit(); });
      el.sound.setAttribute("aria-pressed", String(soundOn));
      el.sound.addEventListener("click", () => { soundOn = !soundOn; store.set("sound", soundOn); el.sound.setAttribute("aria-pressed", String(soundOn)); if (soundOn) { unlockAudio(); setTimeout(() => tone("select"), 50); } buzz("tap"); });
      this.initHold();
      this.initPicker();
      pad.init();
      document.addEventListener("pointerdown", unlockAudio, { capture: true, passive: true });
      document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") { net.wake(); keepAwake(); } else { pad.releaseAll(); } });
      window.addEventListener("pageshow", () => net.wake());
      window.addEventListener("resize", () => { pad.resize(); this.paintFaces(); });
      document.addEventListener("contextmenu", (e) => e.preventDefault());
      // Volver a la sala sin pasar por el formulario si hay un lugar guardado
      // (pantalla recargada, pestaña cerrada y abierta): la TV reconecta por token.
      const savedRoom = store.get("room", ""), savedToken = store.get("token", ""), savedName = store.get("name", "");
      if (savedToken && isValidRoom(savedRoom) && (!ROOM_FROM_URL || ROOM_FROM_URL === savedRoom) && savedName) {
        this.setCode(savedRoom);
        this.setStatus("Volviendo a tu lugar en la sala " + savedRoom + "…", false);
        net.join(savedRoom, savedName, this.savedLook());
      }
    },
    savedLook() { const look = {}; const c = parseColorIndex(store.get("color", -1)), s = parseStyleIndex(store.get("style", -1)); if (c >= 0) look.color = c; if (s >= 0) look.style = s; return look; },
    setCode(code) { el.code.value = code; this.paintTiles(); },
    paintTiles(focused) {
      const v = el.code.value;
      const hasFocus = focused === undefined ? document.activeElement === el.code : focused;
      el.tiles.forEach((t, i) => { t.textContent = v[i] || ""; t.classList.toggle("lit", hasFocus && i === Math.min(v.length, 3)); });
    },
    submit() {
      const name = sanitizeName(el.name.value), code = normalizeRoom(el.code.value);
      if (!name) { this.setStatus("Contanos cómo te llamás: escribí tu apodo.", true); el.name.focus(); return; }
      if (!isValidRoom(code)) { this.setStatus("El código son 4 letras o números: copialo de las fichas de la TV.", true); el.code.focus(); return; }
      store.set("name", name);
      el.name.blur(); el.code.blur();
      this.setStatus("Conectando con la TV…", false);
      unlockAudio();
      net.join(code, name, this.savedLook());
    },
    setStatus(msg, isError) {
      el.statusText.textContent = msg;
      el.status.hidden = !msg;
      el.status.classList.toggle("info", !isError);
      el.status.classList.remove("shake");
      if (isError && msg) { void el.status.offsetWidth; el.status.classList.add("shake"); }
    },
    showJoin(msg) {
      pad.setLayout("wait", {});
      this.clearStanding();
      el.play.hidden = true; el.join.hidden = false;
      el.bg.classList.remove("joined", "dark");
      document.documentElement.style.setProperty("--bg-top", "#2B9CF5"); document.documentElement.style.setProperty("--bg-bottom", "#BFE4FF");
      this.setStatus(msg, !!msg);
      this.setSignal("lost", -1);
    },
    onJoined(wasReconnecting) {
      const info = net.info;
      el.join.hidden = true; el.play.hidden = false;
      this.applyInfo();
      if (!wasReconnecting) { tone("join"); buzz("go"); }
      else this.toast("¡Volviste a tu lugar!");
      el.cardStatus.textContent = "¡Listo para jugar!"; el.cardStatus.classList.remove("warn");
      keepAwake();
      this.setSignal(net.rtt < 0 ? "good" : this.levelFor(net.rtt), net.rtt);
      this.updatePicker();
      void info;
    },
    onRejected(reason) {
      const messages = {
        bad_room: "Ese código no es el de la TV. Fijate las 4 fichas de colores en la pantalla.",
        room_full: "¡La sala está llena! Pedile a quien tiene el control de la TV que sume un lugar.",
        game_in_progress: "Están en medio de una partida. Esperá a que termine y volvé a probar.",
        bad_name: "Ese apodo no se puede usar. Probá con otro.",
        bad_version: "Esta página y la TV son de versiones distintas. Recargá la página.",
        unreachable: "No encontramos la TV. ¿Están los dos en la misma Wi-Fi?",
        timeout: "La TV no respondió a tiempo. Probá de nuevo.",
      };
      const auto = el.join.hidden === false && el.status.classList.contains("info") && el.statusText.textContent.startsWith("Volviendo");
      this.showJoin(auto && reason === "bad_room" ? "" : (messages[reason] || ("No se pudo unir (" + reason + "). Probá de nuevo.")));
    },
    onConnectionLost() {
      el.cardStatus.textContent = "Reconectando…"; el.cardStatus.classList.add("warn");
      this.setSignal("lost", -1);
      this.toast("Se cortó la conexión con la TV. Reconectando…");
      pad.releaseAll();
    },
    onGaveUp() { this.showJoin("Se cortó la conexión con la TV. Volvé a unirte cuando quieras."); },
    onLayout(layout, data) {
      const prev = this.layout;
      this.layout = layout;
      pad.setLayout(layout, data);
      const hint = cleanText(data.hint, HINT_MAX) || (layout === "wait" ? "" : LAYOUT_HINTS[layout] || "");
      el.hint.textContent = hint; el.hint.hidden = !hint;
      el.hint.classList.toggle("portrait-row", !!hint);
      el.wait.hidden = layout !== "wait"; el.pad.hidden = layout === "wait";
      if (layout !== "wait") { this.clearStanding(); this.setMood("normal"); if (prev !== layout) { tone("select"); buzz("point"); } }
      this.updatePicker();
    },
    onPhase(phase) {
      this.phase = phase;
      if (phase !== "results") this.clearStanding();
      if (phase === "lobby") this.setMood("happy");
      this.updatePicker();
    },
    onAppearance() { this.applyInfo(); this.updatePicker(); },
    onLatency(ms) { this.setSignal(this.levelFor(ms), ms); },
    levelFor(ms) { return ms < 120 ? "good" : ms < 250 ? "slow" : "bad"; },
    setSignal(level, ms) {
      el.signal.className = "pill signal " + level;
      el.ms.textContent = ms >= 0 ? Math.round(ms) + " ms" : "— ms";
    },
    applyInfo() {
      const info = net.info; if (!info) return;
      const slot = info.id - 1, tag = (slot + 1) + "P", color = info.color;
      const dark = luminance(color) < 0.2, light = luminance(color) > 0.8;
      const root = document.documentElement.style;
      root.setProperty("--player", color);
      root.setProperty("--player-dark", darken(color, 0.3));
      root.setProperty("--player-ink", textOn(mix(color, PAPER, 0.4)));
      root.setProperty("--player-top", mix(color, PAPER, dark ? 0.3 : 0.82));
      root.setProperty("--player-bottom", mix(color, PAPER, dark ? 0.1 : 0.6));
      root.setProperty("--bg-top", dark ? lighten(color, 0.2) : mix(color, PAPER, 0.58));
      root.setProperty("--bg-bottom", dark ? color : light ? darken(color, 0.14) : mix(color, PAPER, 0.22));
      el.bg.classList.add("joined"); el.bg.classList.toggle("dark", dark);
      el.bgTag.textContent = tag;
      el.meTag.textContent = tag; el.cardTag.textContent = tag;
      el.meName.textContent = info.name; el.cardName.textContent = info.name;
      this.paintFaces();
      pad.setColor(color);
    },
    paintFaces() {
      const info = net.info; if (!info) return;
      const style = info.style >= 0 ? info.style : info.id - 1;
      drawMascot(el.meFace, info.color, style, "normal");
      drawMascot(el.cardFace, info.color, style, this.mood);
    },
    setMood(mood, ms) {
      clearTimeout(this.moodTimer);
      this.mood = mood; this.paintFaces();
      if (ms) this.moodTimer = setTimeout(() => { this.mood = this.phase === "lobby" ? "happy" : "normal"; this.paintFaces(); }, ms);
    },
    // Selector de mascota: solo en el lobby, sin control ni resultado en pantalla.
    initPicker() {
      PROTO.COLORS.forEach((hex, i) => {
        const b = document.createElement("button");
        b.type = "button"; b.className = "swatch"; b.setAttribute("aria-label", PROTO.COLOR_NAMES[i]);
        b.style.setProperty("--c", hex); b.style.setProperty("--c-l", lighten(hex, 0.28)); b.style.setProperty("--c-d", darken(hex, 0.35));
        b.addEventListener("click", () => this.pickColor(i));
        el.swatches.appendChild(b);
      });
      el.stylePrev.addEventListener("click", () => this.stepStyle(-1));
      el.styleNext.addEventListener("click", () => this.stepStyle(1));
    },
    updatePicker() {
      const info = net.info;
      const supported = !!info && info.colorIndex >= 0 && info.style >= 0;
      const shown = supported && this.phase === "lobby" && this.layout === "wait" && !this.standingShown;
      el.picker.hidden = !shown;
      el.waitSub.textContent = shown ? "Elegí tu mascota mientras la TV arranca" : "El juego empieza cuando la TV lo elija";
      if (!supported) return;
      el.styleName.textContent = PROTO.STYLE_NAMES[info.style];
      el.colorName.textContent = PROTO.COLOR_NAMES[info.colorIndex];
      [...el.swatches.children].forEach((b, i) => { b.classList.toggle("selected", i === info.colorIndex); b.classList.toggle("taken", info.taken.includes(i) && i !== info.colorIndex); b.disabled = info.taken.includes(i) && i !== info.colorIndex; });
    },
    pickColor(i) { const info = net.info; if (!info || i === info.colorIndex || info.taken.includes(i)) return; this.applyLook(i, info.style); },
    stepStyle(d) { const info = net.info; if (!info) return; this.applyLook(info.colorIndex, (info.style + d + PROTO.STYLE_NAMES.length) % PROTO.STYLE_NAMES.length); },
    applyLook(color, style) {
      // Se ve al instante (la TV confirma o corrige con "appearance") y queda guardado.
      tone("select"); buzz("tap");
      net.info.colorIndex = color; net.info.color = PROTO.COLORS[color]; net.info.style = style;
      store.set("color", color); store.set("style", style);
      this.applyInfo(); this.updatePicker();
      net.sendLook(color, style);
    },
    onStanding(d) {
      const isFinal = d.final, medalPlace = isFinal ? d.rank : d.place;
      const celebrate = d.place === 1 || (isFinal && d.rank === 1);
      tone(celebrate ? "win" : "pop"); buzz(celebrate ? "win" : "point");
      const medalColor = medalPlace === 1 ? "#FFC53D" : medalPlace === 2 ? "#C9D1E0" : medalPlace === 3 ? "#E0955A" : "#EAEEFB";
      el.standing.style.setProperty("--medal", medalColor); el.standing.style.setProperty("--medal-light", mix(medalColor, PAPER, 0.45));
      el.standingRound.textContent = isFinal ? "Resultado final" : "Ronda " + d.round + "/" + d.total_rounds;
      el.standingCheer.textContent = this.cheerText(isFinal, medalPlace);
      el.standingMedal.hidden = medalPlace <= 0;
      el.standingMedalText.textContent = medalPlace + "°";
      el.standingMedal.classList.remove("rays"); void el.standingMedal.offsetWidth; el.standingMedal.classList.add("rays");
      el.standingMain.classList.toggle("gold", medalPlace === 1); el.standingMain.classList.toggle("small", isFinal);
      if (isFinal) { el.standingMain.textContent = "¡Terminaste " + d.rank + "°!"; el.standingTotal.textContent = d.total + " pts"; }
      else if (d.place > 0) { el.standingMain.textContent = "+" + d.points; el.standingTotal.textContent = "Total " + d.total + " · vas " + d.rank + "°"; }
      else { el.standingMain.textContent = "Total " + d.total; el.standingTotal.textContent = "Vas " + d.rank + "°"; }
      el.waitSub.hidden = true; el.standing.hidden = false; this.standingShown = true;
      this.setMood(d.rank === 1 || d.place === 1 || (isFinal && d.rank <= 3) ? "happy" : (d.players > 1 && d.rank >= d.players ? "sad" : "normal"));
      this.updatePicker();
    },
    cheerText(isFinal, place) {
      if (isFinal) return place === 1 ? "¡Ganaste la competencia!" : place === 2 || place === 3 ? "¡Llegaste al podio!" : "¡Gracias por jugar!";
      return ["¡La próxima es tuya!", "Esta ronda no jugaste", "¡Ganaste la ronda!", "¡Casi, casi!", "¡Bien ahí!"][place >= 0 && place <= 3 ? place + 1 : 0];
    },
    clearStanding() { el.standing.hidden = true; el.waitSub.hidden = false; this.standingShown = false; this.updatePicker(); },
    toast(text) {
      el.toast.textContent = text; el.toast.hidden = false; el.toast.classList.remove("fade");
      clearTimeout(this.toastTimer);
      this.toastTimer = setTimeout(() => { el.toast.classList.add("fade"); setTimeout(() => { el.toast.hidden = true; }, 320); }, 1800);
    },
    // "Salir" hay que mantenerlo apretado 1 s: un roce no te saca de la partida.
    initHold() {
      let start = 0, raf = 0, pointer = -1;
      const circ = 97.4;
      const tick = () => {
        const k = clamp((performance.now() - start) / HOLD_MS, 0, 1);
        el.ringFill.style.strokeDashoffset = String(circ * (1 - k));
        if (k >= 1) { stop(false); buzz("hit"); net.leave(); this.showJoin(""); return; }
        raf = requestAnimationFrame(tick);
      };
      const stop = (early) => {
        cancelAnimationFrame(raf); el.leave.classList.remove("holding", "down"); el.ringFill.style.strokeDashoffset = String(circ); pointer = -1;
        if (early) this.toast(LEAVE_HINT);
      };
      el.leave.addEventListener("pointerdown", (e) => {
        if (pointer !== -1) return;
        pointer = e.pointerId; start = performance.now(); el.leave.classList.add("holding", "down");
        try { el.leave.setPointerCapture(e.pointerId); } catch (err) { /* puntero sintético */ }
        raf = requestAnimationFrame(tick);
      });
      el.leave.addEventListener("pointerup", (e) => { if (e.pointerId === pointer) stop(true); });
      el.leave.addEventListener("pointercancel", (e) => { if (e.pointerId === pointer) stop(false); });
      el.leave.addEventListener("click", (e) => e.preventDefault());
    },
  };

  // --- Control en canvas: joystick, slider, botón y joystick + A/B ------------------
  // Misma semántica que los layouts de la app (controller/layouts/): joystick
  // flotante (la base aparece donde apoyás el dedo), zona muerta 0,12, slider
  // absoluto que no vuelve al centro, botón que cuenta en toda su zona y
  // multitáctil real en joystick + A/B (cada dedo sigue yendo a la pieza donde
  // apoyó). Se envía a 30 Hz solo si cambió, y cada 250 ms como keepalive.
  const pad = {
    layout: "wait", data: {}, color: "#E24B4A", W: 0, H: 0, dpr: 1, ctx: null, raf: 0, dirty: true,
    stick: { id: -1, ox: 0, oy: 0, kx: 0, ky: 0, value: [0, 0], press: 0 },
    slider: { id: -1, value: 0, press: 0 },
    btnA: { ids: new Set(), press: 0, ripple: 1 }, btnB: { ids: new Set(), press: 0, ripple: 1 },
    routes: new Map(), lastAxis: [NaN, NaN], lastBtn: -1, lastSent: 0, sendTimer: 0,
    init() {
      this.ctx = el.pad.getContext("2d");
      const opts = { passive: false };
      el.pad.addEventListener("pointerdown", (e) => { e.preventDefault(); try { el.pad.setPointerCapture(e.pointerId); } catch (err) { /* nada */ } this.down(e.pointerId, ...this.pos(e)); }, opts);
      el.pad.addEventListener("pointermove", (e) => { e.preventDefault(); this.move(e.pointerId, ...this.pos(e)); }, opts);
      const up = (e) => { e.preventDefault(); this.up(e.pointerId); };
      el.pad.addEventListener("pointerup", up, opts); el.pad.addEventListener("pointercancel", up, opts); el.pad.addEventListener("lostpointercapture", up);
      el.pad.addEventListener("touchstart", (e) => e.preventDefault(), opts); // iOS: sin zoom ni selección.
      this.sendTimer = setInterval(() => this.tick(), 1000 / SEND_HZ);
    },
    pos(e) { const r = el.pad.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; },
    setColor(c) { this.color = c; this.dirty = true; this.draw(); },
    setLayout(layout, data) {
      this.releaseAll();
      this.layout = layout; this.data = data || {};
      this.labelA = cleanText(this.data.a, LABEL_MAX); this.labelB = cleanText(this.data.b, LABEL_MAX);
      this.label = cleanText(this.data.label, LABEL_MAX) || "A";
      this.slider.value = 0; this.lastBtn = -1; this.lastAxis = [NaN, NaN];
      el.pad.hidden = layout === "wait";
      if (layout !== "wait") { this.resize(); this.animate(); }
    },
    resize() {
      if (el.pad.hidden) return;
      const r = el.stage.getBoundingClientRect();
      this.dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.W = Math.max(1, Math.round(r.width)); this.H = Math.max(1, Math.round(r.height));
      el.pad.width = Math.round(this.W * this.dpr); el.pad.height = Math.round(this.H * this.dpr);
      this.dirty = true; this.draw();
    },
    portrait() { return this.H > this.W; },
    // --- Geometría (apaisado como la app; en vertical, las piezas bajan a la mitad de abajo).
    stickRect() {
      if (this.layout !== "joystick_ab") return { x: 0, y: 0, w: this.W, h: this.H };
      if (this.portrait()) { const w = this.W * 0.5, h = this.H * 0.62; return { x: ui.lefty ? this.W - w : 0, y: this.H - h, w, h }; }
      const w = this.W * 0.54; return { x: ui.lefty ? this.W - w : 0, y: 0, w, h: this.H };
    },
    stickRadius() { const z = this.stickRect(); return clamp(Math.min(z.w, z.h) * (this.portrait() ? 0.2 : 0.16), 40, 140); },
    stickRest() {
      const z = this.stickRect();
      if (this.layout === "joystick_ab") return [z.x + z.w * 0.5, z.y + z.h * (this.portrait() ? 0.55 : 0.5)];
      if (this.portrait()) return [this.W * 0.5, this.H * 0.6];
      return [this.W * (ui.lefty ? 0.7 : 0.3), this.H * 0.5];
    },
    buttonRadius(which) {
      const share = which === "A" ? 0.19 : 0.16;
      const fit = this.portrait() ? this.W * 0.5 * 0.3 : this.W * 0.46 * 0.2;
      return clamp(Math.min(this.H * share, fit), 36, 230);
    },
    buttonCenter(which) {
      const ra = this.buttonRadius("A"), rb = this.buttonRadius("B"), housing = 1.24;
      const margin = this.W * 0.04;
      let a = this.portrait() ? [this.W - margin - ra * housing, this.H * 0.8] : [this.W - margin - ra * housing, this.H * 0.62];
      let p = a;
      if (which === "B") {
        const gap = (ra + rb) * housing + 20;
        if (this.portrait()) p = [a[0] - rb * 0.35, a[1] - gap];  // Vertical: B arriba de A (no hay ancho para la diagonal).
        else { const dy = this.H * 0.26; p = [a[0] - Math.sqrt(Math.max(gap * gap - dy * dy, 0)) - rb * 0.1, a[1] - dy]; }
      }
      if (ui.lefty) p = [this.W - p[0], p[1]];
      return p;
    },
    oneButton() {
      const fit = Math.min(this.W * 0.5, this.H), r = Math.min(fit * 0.33, fit * 0.37);
      const c = this.portrait() ? [this.W * 0.5, this.H * 0.56] : [this.W * (ui.lefty ? 0.3 : 0.7), this.H * 0.5];
      return { c, r };
    },
    partAt(x, y) {
      if (this.layout === "joystick") return "stick";
      if (this.layout === "one_button") return "A";
      if (this.layout === "slider_h") return "slider";
      const z = this.stickRect();
      if (x >= z.x && x < z.x + z.w && y >= z.y && y < z.y + z.h) return "stick";
      const ca = this.buttonCenter("A"), cb = this.buttonCenter("B");
      const da = Math.hypot(x - ca[0], y - ca[1]) / this.buttonRadius("A"), db = Math.hypot(x - cb[0], y - cb[1]) / this.buttonRadius("B");
      return da <= db ? "A" : "B";
    },
    // --- Dedos.
    down(id, x, y) {
      if (this.layout === "wait" || this.routes.has(id)) return;
      const part = this.partAt(x, y);
      if (part === "stick") {
        if (this.stick.id !== -1) { this.routes.set(id, "none"); return; }
        this.stick.id = id; this.stick.ox = x; this.stick.oy = y; this.stick.kx = x; this.stick.ky = y; this.stick.value = [0, 0];
      } else if (part === "slider") {
        if (this.slider.id !== -1) { this.routes.set(id, "none"); return; }
        this.slider.id = id; this.setSlider(x);
      } else {
        const b = part === "A" ? this.btnA : this.btnB;
        const was = b.ids.size > 0; b.ids.add(id);
        if (!was) { b.ripple = 0; buzz("tap"); tone("tap"); }
      }
      this.routes.set(id, part);
      this.sendNow();
      this.animate();
    },
    move(id, x, y) {
      const part = this.routes.get(id);
      if (part === "stick" && this.stick.id === id) {
        const reach = this.stickRadius(), dx = x - this.stick.ox, dy = y - this.stick.oy, len = Math.hypot(dx, dy);
        const k = len > reach ? reach / len : 1;
        this.stick.kx = this.stick.ox + dx * k; this.stick.ky = this.stick.oy + dy * k;
        const vx = (this.stick.kx - this.stick.ox) / reach, vy = (this.stick.ky - this.stick.oy) / reach;
        this.stick.value = Math.hypot(vx, vy) > DEAD_ZONE ? [vx, vy] : [0, 0];
        this.dirty = true;
      } else if (part === "slider" && this.slider.id === id) {
        this.setSlider(x);
      }
    },
    up(id) {
      const part = this.routes.get(id);
      if (part === undefined) return;
      this.routes.delete(id);
      if (part === "stick" && this.stick.id === id) { this.stick.id = -1; this.stick.value = [0, 0]; }
      else if (part === "slider" && this.slider.id === id) { this.slider.id = -1; }
      else if (part === "A" || part === "B") { (part === "A" ? this.btnA : this.btnB).ids.delete(id); }
      this.dirty = true;
      this.sendNow();
      this.animate();
    },
    releaseAll() {
      this.routes.clear(); this.stick.id = -1; this.stick.value = [0, 0]; this.slider.id = -1; this.btnA.ids.clear(); this.btnB.ids.clear();
      this.dirty = true;
      if (this.layout !== "wait") { this.sendNow(); this.animate(); }
    },
    setSlider(x) {
      const margin = this.W * 0.08, t = clamp((x - margin) / Math.max(this.W - margin * 2, 1), 0, 1);
      this.slider.value = t * 2 - 1; this.dirty = true;
    },
    // --- Envío.
    current() {
      let axis = [0, 0], btn = 0;
      if (this.layout === "joystick" || this.layout === "joystick_ab") axis = this.stick.value;
      if (this.layout === "slider_h") axis = [this.slider.value, 0];
      if (this.layout === "one_button" || this.layout === "joystick_ab") btn = (this.btnA.ids.size ? PROTO.BTN_A : 0) | (this.layout === "joystick_ab" && this.btnB.ids.size ? PROTO.BTN_B : 0);
      return [axis, btn];
    },
    tick() {
      if (this.layout === "wait" || net.state !== "joined") return;
      const [axis, btn] = this.current();
      const now = performance.now();
      if (axis[0] !== this.lastAxis[0] || axis[1] !== this.lastAxis[1] || btn !== this.lastBtn || now - this.lastSent >= KEEPALIVE_MS) {
        net.sendInput(axis, btn); this.lastAxis = [axis[0], axis[1]]; this.lastBtn = btn; this.lastSent = now;
      }
    },
    sendNow() { this.lastSent = 0; this.tick(); },
    // --- Dibujo (solo mientras algo se mueve; quieto no se redibuja).
    animate() { if (!this.raf) this.raf = requestAnimationFrame(() => this.frame()); },
    frame() {
      this.raf = 0;
      if (this.layout === "wait") return;
      let busy = false;
      const ease = (obj, key, target, up, down) => { const v = obj[key]; const n = v + (target - v) * (target > v ? up : down); obj[key] = Math.abs(n - target) < 0.01 ? target : n; if (obj[key] !== v) busy = true; };
      ease(this.stick, "press", this.stick.id !== -1 ? 1 : 0, 0.5, 0.25);
      ease(this.slider, "press", this.slider.id !== -1 ? 1 : 0, 0.5, 0.25);
      for (const b of [this.btnA, this.btnB]) { ease(b, "press", b.ids.size ? 1 : 0, 0.55, 0.3); if (b.ripple < 1) { b.ripple = Math.min(1, b.ripple + 0.06); busy = true; } }
      if (this.stick.id !== -1 || this.slider.id !== -1) busy = true;
      this.dirty = true; this.draw();
      if (busy) this.animate();
    },
    draw() {
      if (!this.dirty || el.pad.hidden || !this.W) return;
      this.dirty = false;
      const ctx = this.ctx;
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      ctx.clearRect(0, 0, this.W, this.H);
      ctx.lineJoin = "round"; ctx.lineCap = "round";
      if (this.layout === "joystick" || this.layout === "joystick_ab") this.drawStick(ctx);
      if (this.layout === "slider_h") this.drawSlider(ctx);
      if (this.layout === "one_button") { const o = this.oneButton(); this.drawButton(ctx, o.c, o.r, this.color, this.label, this.btnA, ""); }
      if (this.layout === "joystick_ab") {
        this.drawButton(ctx, this.buttonCenter("B"), this.buttonRadius("B"), KEY_NEUTRAL, "B", this.btnB, this.labelB);
        this.drawButton(ctx, this.buttonCenter("A"), this.buttonRadius("A"), this.color, "A", this.btnA, this.labelA);
      }
    },
    ellipse(ctx, x, y, rx, ry, fill, rot) { ctx.beginPath(); ctx.ellipse(x, y, rx, ry, rot || 0, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); },
    circle(ctx, x, y, r, fill) { ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill(); },
    toyDisc(ctx, x, y, r, color, press) {
      const depth = r * 0.16, outline = Math.max(3, r * 0.05), lift = depth * (1 - 0.8 * press);
      const sx = r * (1 + 0.08 * press), sy = r * (1 - 0.08 * press);
      const by = y + depth, fy = by - lift;
      this.ellipse(ctx, x, by + r * 0.1, sx + outline * 2, sy * 0.9 + outline, SHADOW);
      this.ellipse(ctx, x, by, sx + outline, sy + outline, INK);
      this.ellipse(ctx, x, by, sx, sy, darken(color, 0.3));
      this.ellipse(ctx, x, fy, sx + outline, sy + outline, INK);
      this.ellipse(ctx, x, fy, sx, sy, color);
      this.ellipse(ctx, x, fy + sy * 0.18, sx * 0.86, sy * 0.78, darken(color, 0.06));
      this.ellipse(ctx, x, fy - sy * 0.06, sx * 0.8, sy * 0.72, color);
      this.ellipse(ctx, x, fy - sy * 0.4, sx * 0.6, sy * 0.3, "rgba(255,255,255,0.22)");
      this.ellipse(ctx, x - sx * 0.38, fy - sy * 0.46, sx * 0.15, sy * 0.09, "rgba(255,255,255,0.5)", -0.6);
      return fy;
    },
    text(ctx, s, x, y, size, fill, stroke) {
      ctx.font = "700 " + size + "px Fredoka, Nunito, system-ui, sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle";
      if (stroke) { ctx.lineWidth = Math.max(3, size * 0.14); ctx.strokeStyle = INK; ctx.strokeText(s, x, y); }
      ctx.fillStyle = fill; ctx.fillText(s, x, y);
    },
    pill(ctx, s, cx, y) {
      ctx.font = "700 15px Fredoka, Nunito, system-ui, sans-serif";
      const w = ctx.measureText(s).width + 32, h = 32, x = cx - w / 2;
      ctx.beginPath(); ctx.roundRect(x, y, w, h, 16); ctx.fillStyle = GLASS; ctx.fill();
      this.text(ctx, s, cx, y + h / 2 + 1, 15, INK, false);
    },
    drawStick(ctx) {
      const s = this.stick, active = s.id !== -1, rad = this.stickRadius(), [rx, ry] = this.stickRest();
      const cx = active ? s.ox : rx, cy = active ? s.oy : ry, kx = active ? s.kx : cx, ky = active ? s.ky : cy;
      const knobR = rad * 0.56, dish = rad + knobR * 0.45, line = Math.max(3, rad * 0.045);
      this.circle(ctx, cx, cy + 7, dish + line + 3, SHADOW);
      this.circle(ctx, cx, cy, dish + line, INK);
      this.circle(ctx, cx, cy, dish, DISH);
      this.circle(ctx, cx, cy, dish - line * 1.6, DISH_RIM);
      this.circle(ctx, cx, cy + line * 0.8, dish - line * 2.4, DISH);
      const v = s.value, len = Math.hypot(v[0], v[1]);
      for (const [dx, dy] of [[0, -1], [1, 0], [0, 1], [-1, 0]]) {
        const lit = active && len > 0 && (v[0] * dx + v[1] * dy) / len > 0.7;
        const tx = cx + dx * (dish + line + rad * 0.22), ty = cy + dy * (dish + line + rad * 0.22);
        this.arrow(ctx, tx, ty, rad * 0.3, dx, dy, INK); this.arrow(ctx, tx, ty, rad * 0.22, dx, dy, lit ? ACCENT : PAPER);
      }
      const leanX = (kx - cx) / Math.max(rad, 1);
      this.ellipse(ctx, kx + leanX * 5, ky + knobR * 0.35 + 4, knobR * 1.05, knobR * 0.7, SHADOW);
      if (luminance(this.color) < 0.2) this.circle(ctx, kx, ky - knobR * 0.12, knobR + line * 1.4, "rgba(255,255,255,0.45)");
      this.toyDisc(ctx, kx, ky - knobR * 0.12, knobR, active ? this.color : mix(this.color, PAPER, 0.15), s.press);
      if (!active) { const z = this.stickRect(); this.pill(ctx, this.layout === "joystick_ab" ? "Arrastrá para moverte" : "Arrastrá en cualquier lugar", cx, Math.min(z.y + z.h - 44, cy + dish + rad * 0.9)); }
    },
    arrow(ctx, x, y, s, dx, dy, fill) {
      const nx = -dy, ny = dx;
      ctx.beginPath(); ctx.moveTo(x + dx * s * 0.6, y + dy * s * 0.6);
      ctx.lineTo(x - dx * s * 0.4 + nx * s * 0.55, y - dy * s * 0.4 + ny * s * 0.55); ctx.lineTo(x - dx * s * 0.4 - nx * s * 0.55, y - dy * s * 0.4 - ny * s * 0.55);
      ctx.closePath(); ctx.fillStyle = fill; ctx.fill();
    },
    drawButton(ctx, c, r, color, label, b, caption) {
      const [x0, y0] = c, y = y0 - r * 0.06, line = Math.max(3, r * 0.04);
      this.circle(ctx, x0, y + r * 0.2, r * 1.24, SHADOW);
      this.circle(ctx, x0, y + r * 0.12, r * 1.2 + line, INK);
      this.circle(ctx, x0, y + r * 0.12, r * 1.2, DISH);
      this.circle(ctx, x0, y + r * 0.12, r * 1.12, DISH_RIM);
      this.circle(ctx, x0, y + r * 0.16, r * 1.07, DISH);
      if (luminance(color) < 0.2) this.circle(ctx, x0, y + r * 0.1, r * 1.04, "rgba(255,255,255,0.45)");
      if (b.ripple < 1) {
        ctx.beginPath(); ctx.arc(x0, y + r * 0.12, r * (1.2 + 0.35 * b.ripple), 0, Math.PI * 2);
        ctx.lineWidth = line * 2 * (1 - b.ripple) + 1; ctx.strokeStyle = "rgba(255,255,255," + (0.8 * (1 - b.ripple)).toFixed(2) + ")"; ctx.stroke();
      }
      const fy = this.toyDisc(ctx, x0, y, r, color, b.press);
      const fs = Math.round(r * (label.length <= 2 ? 0.4 : 0.26));
      this.text(ctx, label, x0, fy + 1, fs, PAPER, true);
      // En vertical B queda arriba de A: su texto va encima para que A no lo tape.
      if (caption) this.text(ctx, caption, x0, label === "B" && this.portrait() ? y0 - r * 1.3 - 14 : y0 + r * 1.44 + 16, 17, PAPER, true);
    },
    drawSlider(ctx) {
      const margin = this.W * 0.08, y = this.H * (this.portrait() ? 0.5 : 0.46), v = this.slider.value;
      const x = margin + (this.W - margin * 2) * (v + 1) / 2;
      const tx = margin - 20, tw = this.W - margin * 2 + 40, th = 34;
      ctx.beginPath(); ctx.roundRect(tx - 4, y - th / 2 - 4, tw + 8, th + 8, 21); ctx.fillStyle = INK; ctx.fill();
      ctx.beginPath(); ctx.roundRect(tx, y - th / 2, tw, th, 17); ctx.fillStyle = DISH; ctx.fill();
      ctx.beginPath(); ctx.roundRect(tx + 5, y - th / 2 + 4, tw - 10, 5, 3); ctx.fillStyle = DISH_RIM; ctx.fill();
      const fillW = Math.max(x - tx - 7, 0);
      if (fillW > 0) { ctx.beginPath(); ctx.roundRect(tx + 7, y - th / 2 + 11, fillW, th - 18, 8); ctx.fillStyle = this.color + "8C"; ctx.fill(); }
      ctx.lineWidth = 4; ctx.strokeStyle = "rgba(29,33,64,0.45)";
      for (let i = 0; i < 5; i++) { const mx = margin + (this.W - margin * 2) * i / 4, h = i === 2 ? 32 : 20; ctx.beginPath(); ctx.moveTo(mx, y + 30); ctx.lineTo(mx, y + 30 + h); ctx.stroke(); }
      for (const d of [-1, 1]) { const ax = this.W / 2 + d * (this.W / 2 - margin + 40); this.arrow(ctx, ax, y + 2, 32, d, 0, INK); this.arrow(ctx, ax, y, 28, d, 0, PAPER); }
      const p = this.slider.press, kw = 115 * (1 + 0.08 * p), kh = 85 * (1 - 0.08 * p), depth = 7, lift = depth * (1 - 0.8 * p);
      const kx = x - kw / 2, ky = y + 40 - kh;
      ctx.beginPath(); ctx.roundRect(kx - 2, ky + depth - 2, kw + 4, kh - depth + 4, 19); ctx.fillStyle = INK; ctx.fill();
      ctx.beginPath(); ctx.roundRect(kx, ky + depth, kw, kh - depth, 17); ctx.fillStyle = darken(this.color, 0.3); ctx.fill();
      ctx.beginPath(); ctx.roundRect(kx - 2, ky + depth - lift - 2, kw + 4, kh - depth + 4, 19); ctx.fillStyle = INK; ctx.fill();
      ctx.beginPath(); ctx.roundRect(kx, ky + depth - lift, kw, kh - depth, 17); ctx.fillStyle = this.color; ctx.fill();
      ctx.beginPath(); ctx.roundRect(kx + 8, ky + depth - lift + 4, kw - 16, (kh - depth) * 0.4, 12); ctx.fillStyle = "rgba(255,255,255,0.22)"; ctx.fill();
      ctx.lineWidth = 4; ctx.strokeStyle = "rgba(29,33,64,0.35)";
      for (const k of [-1, 0, 1]) { const gx = x + k * 15; ctx.beginPath(); ctx.moveTo(gx, ky + depth - lift + (kh - depth) * 0.3); ctx.lineTo(gx, ky + depth - lift + (kh - depth) * 0.76); ctx.stroke(); }
      this.pill(ctx, "Deslizá el dedo de lado a lado", this.W / 2, Math.min(this.H - 44, y + 110));
    },
  };

  // CanvasRenderingContext2D.roundRect llegó a Safari 16: respaldo para 15.
  if (window.CanvasRenderingContext2D && !CanvasRenderingContext2D.prototype.roundRect) {
    CanvasRenderingContext2D.prototype.roundRect = function (x, y, w, h, r) {
      r = Math.min(r, w / 2, h / 2);
      this.moveTo(x + r, y); this.arcTo(x + w, y, x + w, y + h, r); this.arcTo(x + w, y + h, x, y + h, r); this.arcTo(x, y + h, x, y, r); this.arcTo(x, y, x + w, y, r); this.closePath();
    };
  }

  // Para las pruebas de punta a punta (tools/web_e2e.mjs): estado observable, sin tocar nada.
  window.__pg = { get state() { return net.state; }, get info() { return net.info; }, get layout() { return ui.layout; }, get phase() { return ui.phase; }, get rtt() { return net.rtt; },
    drop() { if (net.ws) net.ws.close(); } };

  ui.init();
})();
