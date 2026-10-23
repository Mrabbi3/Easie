'use strict';
// Motion kit — a tiny deterministic timeline for 1920x1080 product films.
// Every frame is a pure function of t: kit/render.mjs calls __seek(t) and screenshots the page.
// Nothing here uses CSS animations, timers or requestAnimationFrame.
//
//   Scenes      scene(t0, t1, el, update)  — el is shown only inside [t0, t1)
//   Voice       VO.line('tag') / VO.words('tag') from the generated timing.js
//   Type        kinetic(parent, words, opts)  — word-by-word blur-rise / slam
//   Screens     browser(...) / tablet(...) hold real captures (shots/index.js), with camera,
//               spotlight, cursor/tap and pixel-accurate typing
//   Sound       cue(t, 'click')  — exported as window.__film.cues for kit/mix.py

const W = 1920, H = 1080, FPS = 30;
const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const P = (t, a, b) => (b === a ? (t >= b ? 1 : 0) : clamp((t - a) / (b - a)));
const Ease = {
  lin: t => t,
  inQ: t => t * t, outQ: t => 1 - (1 - t) ** 2, inOutQ: t => (t < .5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2),
  inC: t => t ** 3, outC: t => 1 - (1 - t) ** 3, inOutC: t => (t < .5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2),
  outQuint: t => 1 - (1 - t) ** 5, inOutQuint: t => (t < .5 ? 16 * t ** 5 : 1 - (-2 * t + 2) ** 5 / 2),
  inExpo: t => (t <= 0 ? 0 : 2 ** (10 * t - 10)), outExpo: t => (t >= 1 ? 1 : 1 - 2 ** (-10 * t)),
  inOutExpo: t => (t <= 0 ? 0 : t >= 1 ? 1 : t < .5 ? 2 ** (20 * t - 10) / 2 : (2 - 2 ** (-20 * t + 10)) / 2),
  outBack: t => { const c = 1.70158; return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2; },
  outBackBig: t => { const c = 3; return 1 + (c + 1) * (t - 1) ** 3 + c * (t - 1) ** 2; },
  // damped spring that settles at 1 (overshoots once or twice)
  spring: t => (t >= 1 ? 1 : 1 - Math.exp(-7 * t) * Math.cos(10.5 * t)),
};
const E = (name, t) => (typeof name === 'function' ? name : Ease[name || 'inOutC'])(clamp(t));
// Keyframes: kf(t, [[time, value, ease], ...]). Values: number | number[] | {k: number}.
// The ease on a key shapes the segment that *arrives* at that key.
function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, ez] = keys[i], [t0, v0] = keys[i - 1];
    if (t <= t1) return mix(v0, v1, E(ez, P(t, t0, t1)));
  }
  return keys[keys.length - 1][1];
}
function mix(a, b, p) {
  if (typeof a === 'number') return lerp(a, b, p);
  if (Array.isArray(a)) return a.map((v, i) => lerp(v, b[i], p));
  const o = {}; for (const k in a) o[k] = k in b ? lerp(a[k], b[k], p) : a[k]; for (const k in b) if (!(k in a)) o[k] = b[k]; return o;
}
const hash = (n, s = 0) => { const x = Math.sin(n * 127.1 + s * 311.7) * 43758.5453; return x - Math.floor(x); };
const noise = (t, s = 0) => { const i = Math.floor(t), f = t - i, u = f * f * (3 - 2 * f); return lerp(hash(i, s), hash(i + 1, s), u) * 2 - 1; };

// ---- DOM helpers -------------------------------------------------------------------------------
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k === 'class') el.className = v;
    else if (k === 'html') el.innerHTML = v;
    else el.setAttribute(k, v);
  }
  for (const c of kids.flat()) if (c != null) el.append(c.nodeType ? c : document.createTextNode(c));
  return el;
}
const css = (el, o) => { for (const k in o) el.style[k] = o[k]; return el; };
const tf = ({x = 0, y = 0, s = 1, sx, sy, r = 0, rx = 0, ry = 0, z = 0} = {}) =>
  `translate3d(${x}px,${y}px,${z}px) rotateX(${rx}deg) rotateY(${ry}deg) rotate(${r}deg) scale(${sx ?? s},${sy ?? s})`;
const stage = () => document.getElementById('stage');

// ---- Voice timing (timing.js from kit/voice.py) -----------------------------------------------
const VO = {
  total: typeof VO_TOTAL !== 'undefined' ? VO_TOTAL : 0,
  lines: typeof VO_LINES !== 'undefined' ? VO_LINES : [],
  allWords: typeof VO_WORDS !== 'undefined' ? VO_WORDS : [],
  line(tag) { const l = this.lines.find(l => l.tag === tag); if (!l) throw new Error('no VO line ' + tag); return l; },
  words(tag) { const i = this.lines.findIndex(l => l.tag === tag); return this.allWords.filter(w => w.line === i); },
  // time of the first word in line `tag` that matches `re` (after `from` matches)
  at(tag, re, n = 0) {
    const ws = this.words(tag).filter(w => (re instanceof RegExp ? re : new RegExp('^' + re, 'i')).test(w.w.replace(/[^\w$.:'-]/g, '')));
    if (!ws.length) throw new Error(`no word ${re} in ${tag}`); return ws[Math.min(n, ws.length - 1)].t;
  },
  end(tag) { return this.line(tag).end; }, start(tag) { return this.line(tag).start; },
};

// ---- Scenes & cues -----------------------------------------------------------------------------
const SCENES = [], CUES = [], HOOKS = [];
function scene(t0, t1, el, update = () => {}) { el.classList.add('scene'); stage().append(el); SCENES.push({t0, t1, el, update}); return el; }
function every(update) { HOOKS.push(update); }
// gain in dB-ish linear (1 = default), pan -1..1
function cue(t, name, gain = 1, pan = 0, rate = 1) { if (Number.isFinite(t) && t >= 0) CUES.push({t: +t.toFixed(3), name, gain, pan, rate}); }
function seek(t) {
  for (const s of SCENES) {
    const on = t >= s.t0 && t < s.t1;
    if (on !== s._on) { s.el.style.display = on ? '' : 'none'; s._on = on; }
    if (on) s.update(t - s.t0, t);
  }
  for (const f of HOOKS) f(t);
}

// ---- Kinetic type ------------------------------------------------------------------------------
// words: [{text, t, cls?}] or a string + times. Styles: 'rise' (blur + rise), 'slam' (scale down + blur),
// 'fade', 'type' (per character). out: time the whole line leaves (blur up + fade).
function kinetic(parent, words, {style = 'rise', dur = .55, blur = 16, dy = 38, s0 = 1.4, out = Infinity, outDur = .35, cls = ''} = {}) {
  const el = h('div', {class: 'kin ' + cls});
  const spans = words.map(w => {
    const sp = h('span', {class: 'w ' + (w.cls || '')});
    if (style === 'type') { sp.append(...[...w.text].map(c => h('span', {class: 'c'}, c))); } else sp.textContent = w.text;
    el.append(sp, w.br ? h('br') : ' ');
    return sp;
  });
  parent.append(el);
  const update = t => {
    const po = Ease.inC(P(t, out, out + outDur));
    words.forEach((w, i) => {
      const sp = spans[i], d = w.dur ?? dur;
      if (style === 'type') {
        const cs = sp.children, n = cs.length, pp = P(t, w.t, w.t + d);
        for (let k = 0; k < n; k++) cs[k].style.opacity = pp * n > k ? 1 : 0;
      } else {
        const p = P(t, w.t, w.t + d), e = style === 'slam' ? Ease.outExpo(p) : Ease.outQuint(p);
        const sc = style === 'slam' ? lerp(w.s0 ?? s0, 1, e) : 1;
        sp.style.opacity = style === 'fade' ? e : clamp(p * 3);
        sp.style.filter = `blur(${(1 - e) * blur + po * blur}px)`;
        sp.style.transform = `translateY(${(1 - e) * (style === 'rise' ? dy : 0) - po * dy}px) scale(${sc})`;
      }
      if (po > 0) sp.style.opacity = Math.min(+sp.style.opacity || 1, 1 - po);
    });
  };
  return {el, spans, update};
}
// Words for a whole VO line, keeping the spoken timing. map(w, i) may restyle each word.
function voWords(tag, map = w => w) { return VO.words(tag).map((w, i) => map({text: w.w, t: w.t}, i)); }

// ---- Screens holding real captures --------------------------------------------------------------
// A "page" is the captured document: several state images stacked at the same size; show(name)
// picks the visible one. Everything placed in page coordinates (rects from the capture) moves with it.
function page(names, {vw, vh} = {}) {
  const meta = SHOTS[names[0]]; vw = vw || meta.vw; vh = vh || meta.vh;
  const el = h('div', {class: 'page', style: {width: vw + 'px', height: vh + 'px'}});
  const imgs = {};
  for (const n of names) { if (!SHOTS[n]) throw new Error('no shot ' + n); imgs[n] = h('img', {src: `../shots/${n}.png`, class: 'state', style: {width: SHOTS[n].vw + 'px'}}); el.append(imgs[n]); }
  const over = h('div', {class: 'over'}); el.append(over);
  const pg = {el, over, imgs, vw, vh, cur: null,
    rect: (key, n = pg.cur || names[0]) => { const r = SHOTS[n].rects[key]; if (!r) throw new Error(`no rect ${key} in ${n}`); return r; },
    center: (key, n) => { const r = pg.rect(key, n); return [r.x + r.w / 2, r.y + r.h / 2]; },
    show(n, fade = 1) { for (const k in imgs) imgs[k].style.opacity = k === n ? fade : k === pg.cur && fade < 1 ? 1 : 0; if (fade >= 1) pg.cur = n; },
    // timeline of states: [[t, name], ...] with optional crossfade seconds
    states(t, list, xf = 0) {
      let cur = list[0][1], prev = null, tp = -1e9;
      for (const [ts, n] of list) if (t >= ts) { prev = cur; cur = n; tp = ts; }
      for (const k in imgs) imgs[k].style.opacity = 0;
      if (xf > 0 && prev && prev !== cur && t < tp + xf) { imgs[prev].style.opacity = 1; imgs[cur].style.opacity = Ease.inOutQ(P(t, tp, tp + xf)); }
      else imgs[cur].style.opacity = 1;
      pg.cur = cur; return cur;
    }};
  pg.show(names[0]);
  return pg;
}
// macOS-like browser window around a page; the viewport shows `viewH` px of it (scrollable).
function browser(pg, {url = 'example.com', width = pg.vw, viewH = 1000, title = ''} = {}) {
  const bar = h('div', {class: 'bw-bar'},
    h('i', {class: 'dot r'}), h('i', {class: 'dot y'}), h('i', {class: 'dot g'}),
    h('div', {class: 'bw-url'}, h('span', {class: 'lock', html: '<svg viewBox="0 0 10 12" width="9" height="11"><rect x="1" y="5" width="8" height="6.5" rx="1.3" fill="currentColor"/><path d="M3 5V3.4a2 2 0 0 1 4 0V5" stroke="currentColor" stroke-width="1.3" fill="none"/></svg>'}), h('span', {class: 'u'}, url)));
  const view = h('div', {class: 'bw-view', style: {width: width + 'px', height: viewH + 'px'}}, pg.el);
  const el = h('div', {class: 'bw', style: {width: width + 'px'}}, bar, view);
  const urlEl = bar.querySelector('.u');
  return {el, pg, view, viewH, width, barH: 52, setUrl: u => { if (urlEl.textContent !== u) urlEl.textContent = u; }, scroll: y => { pg.el.style.transform = `translateY(${-y}px)`; }};
}
function tablet(pg, {bezel = 34} = {}) {
  const view = h('div', {class: 'tb-view', style: {width: pg.vw + 'px', height: pg.vh + 'px'}}, pg.el);
  const el = h('div', {class: 'tb', style: {padding: bezel + 'px'}}, view, h('i', {class: 'tb-cam'}));
  return {el, pg, view, bezel, scroll: () => {}};
}

// Camera: places `el` (size w x h) so that the local point (x, y) sits at stage (cx, cy), scaled by s.
function cam(el, {x, y, s = 1, rx = 0, ry = 0, r = 0, cx = W / 2, cy = H / 2, z = 0}) {
  el.style.transformOrigin = '0 0';
  el.style.transform = `translate3d(${cx}px,${cy}px,${z}px) rotateX(${rx}deg) rotateY(${ry}deg) rotate(${r}deg) scale(${s}) translate(${-x}px,${-y}px)`;
}

// Spotlight around a page rect: blue ring + dim outside. p 0..1 (in), q 0..1 (out).
function spot(pg, {pad = 10, radius = 10, dim = .26, label = null, side = 'right'} = {}) {
  const ring = h('div', {class: 'spot'}), tag = label ? h('div', {class: 'spot-tag ' + side}, label) : null;
  pg.over.append(ring); if (tag) pg.over.append(tag);
  return {ring, tag, set(rect, p, q = 0) {
    const v = Ease.outExpo(p) * (1 - Ease.inQ(q)); if (v <= .001) { ring.style.opacity = 0; if (tag) tag.style.opacity = 0; return; }
    const g = lerp(18, 0, Ease.outExpo(p));
    css(ring, {opacity: v, left: rect.x - pad - g + 'px', top: rect.y - pad - g + 'px', width: rect.w + 2 * pad + 2 * g + 'px', height: rect.h + 2 * pad + 2 * g + 'px', borderRadius: radius + 'px', boxShadow: `0 0 0 4000px rgba(12,12,30,${dim * v}), 0 0 0 1px rgba(52,52,224,.25), 0 10px 40px rgba(52,52,224,.35)`});
    if (tag) {
      const e = Ease.outBack(P(p, .25, 1));
      const x = side === 'right' ? rect.x + rect.w + pad + 18 : side === 'left' ? rect.x - pad - 18 : rect.x + rect.w / 2;
      const y = side === 'below' ? rect.y + rect.h + pad + 16 : side === 'above' ? rect.y - pad - 16 : rect.y + rect.h / 2;
      css(tag, {opacity: v * clamp(e * 2), left: x + 'px', top: y + 'px', transform: `${side === 'left' ? 'translate(-100%,-50%)' : side === 'right' ? 'translate(0,-50%)' : side === 'above' ? 'translate(-50%,-100%)' : 'translate(-50%,0)'} scale(${lerp(.7, 1, e)})`});
    }
  }};
}

// Mouse cursor (macOS arrow) or touch dot, moving through [[t, x, y], ...] in page coords.
// clicks: [t, ...] — press dip + ripple. Emits click cues unless silent.
function pointer(pg, path, clicks = [], {touch = false, silent = false, sound = touch ? 'tap' : 'click', size = 1} = {}) {
  const el = h('div', {class: touch ? 'touch' : 'cursor', html: touch ? '' : '<svg viewBox="0 0 28 40" width="28" height="40"><path d="M3 2v31l7.6-7.2 4.9 11.4 5.3-2.3-4.9-11.2 10.6-.4z" fill="#111" stroke="#fff" stroke-width="2.4" stroke-linejoin="round"/></svg>'});
  const ripples = clicks.map(() => { const r = h('div', {class: 'ripple'}); pg.over.append(r); return r; });
  pg.over.append(el);
  if (!silent) clicks.forEach(t => cue(t + (pg._t0 || 0), sound, touch ? .9 : 1));
  const keys = path.map(([t, x, y, e]) => [t, [x, y], e || 'inOutC']);
  return {el, update(t) {
    const [x, y] = kf(t, keys);
    const vis = t >= path[0][0] - .25 && t <= path[path.length - 1][0] + (touch ? .5 : 1.2);
    let press = 0; clicks.forEach(c => { press = Math.max(press, 1 - Math.abs(t - c) / .12); });
    const fin = touch ? clamp(P(t, path[0][0] - .2, path[0][0])) * (1 - P(t, path[path.length - 1][0] + .2, path[path.length - 1][0] + .5)) : clamp(P(t, path[0][0] - .25, path[0][0]));
    css(el, {opacity: vis ? fin : 0, left: x + 'px', top: y + 'px', transform: `translate(${touch ? '-50%,-50%' : '-3px,-2px'}) scale(${size * (1 - clamp(press) * (touch ? .25 : .14))})`});
    clicks.forEach((c, i) => {
      const p = P(t, c, c + .55), r = ripples[i];
      if (p <= 0 || p >= 1) { r.style.opacity = 0; return; }
      const d = lerp(10, touch ? 110 : 70, Ease.outC(p));
      css(r, {opacity: (1 - p) * .9, left: x + 'px', top: y + 'px', width: d + 'px', height: d + 'px'});
    });
  }};
}
// Cursor path helper: glide to each [t, rectCenter] with a small curve; returns path + clicks.
function glide(pts, {lead = .55} = {}) {
  const path = [], clicks = [];
  pts.forEach(([t, [x, y], click = true], i) => {
    if (i) path.push([t - .02, x, y, 'inOutC']); else path.push([t - lead, x + 180, y + 140], [t - .02, x, y, 'inOutC']);
    path.push([t + .25, x, y]);
    if (click) clicks.push(t);
  });
  return {path, clicks};
}

// Typing: reveal the app's own text for `key` from the filled shot, one char-step at a time.
function typer(pg, filled, key, text, {cover = true, caret = true, secret = false} = {}) {
  const m = SHOTS[filled], r = m.rects[key], ink = m.ink[key], bgc = m.bg[key] || '#fff';
  if (!ink) throw new Error(`no ink for ${key} in ${filled}`);
  const box = h('div', {class: 'typer', style: {left: r.x + 4 + 'px', top: r.y + 3 + 'px', width: r.w - 8 + 'px', height: r.h - 7 + 'px', background: cover ? bgc : 'transparent'}});
  const txt = h('div', {class: 'typer-t', style: {left: ink.x - r.x - 4 + 'px', top: ink.y - r.y - 3 - 2 + 'px', height: ink.h + 4 + 'px', backgroundImage: `url(../shots/${filled}.png)`, backgroundSize: `${m.vw}px auto`, backgroundPosition: `${-ink.x}px ${-(ink.y - 2)}px`}});
  const car = h('i', {class: 'caret', style: {top: ink.y - r.y - 3 - 4 + 'px', height: ink.h + 8 + 'px'}});
  box.append(txt, car); pg.over.append(box);
  const n = Math.max(1, text.length);
  return {n, update(t, t0, t1, tHide = Infinity) {
    const on = t >= t0 - .05 && t < tHide;
    box.style.display = on ? '' : 'none'; if (!on) return;
    const k = Math.floor(P(t, t0, t1) * n + 1e-6), w = ink.w * (k / n) + (k >= n ? 2 : 0);
    txt.style.width = w + 'px';
    const blink = t > t1 ? (Math.floor((t - t1) / .5) % 2 === 0) : true;
    car.style.left = ink.x - r.x - 4 + w + 1 + 'px';
    car.style.opacity = caret && blink && t < t1 + 1.2 ? 1 : 0;
  }};
}
// sound cues for typing across [t0, t1] with n keys
function typeCues(t0, t1, n, name = 'type') { for (let i = 0; i < n; i++) cue(t0 + (t1 - t0) * (i + .5) / n, name, .55 + hash(i, 3) * .3, 0, .9 + hash(i, 5) * .25); }

// ---- Boot ----------------------------------------------------------------------------------------
// film(duration, build): build() creates scenes/cues. Renderer contract: __ready, __film, __seek.
function film(duration, build, {fps = FPS} = {}) {
  window.__film = {duration, fps, cues: CUES, w: W, h: H};
  const q = new URLSearchParams(location.search);
  (async () => {
    try {
      await document.fonts.ready;
      build();
      CUES.sort((a, b) => a.t - b.t);
      const imgs = [...document.images];
      await Promise.all(imgs.map(i => (i.complete && i.naturalWidth ? Promise.resolve() : new Promise((ok, no) => { i.onload = ok; i.onerror = () => no(new Error('image failed: ' + i.src)); })).then(() => i.decode().catch(() => {}))));
      window.__seek = t => seek(t);
      seek(q.has('t') ? +q.get('t') : 0);
      window.__ready = true;
      if (!q.has('bare')) preview(duration);
    } catch (e) { window.__error = String(e && e.stack || e); console.error(e); }
  })();
}
// In a normal browser: scrub bar + play, so films can be checked without rendering.
function preview(duration) {
  const bar = h('input', {type: 'range', min: 0, max: duration, step: 1 / FPS, value: 0, class: 'scrub'});
  const lab = h('div', {class: 'scrub-t'}); document.body.append(bar, lab);
  let playing = false, t0 = 0, s0 = 0;
  const show = t => { seek(t); bar.value = t; lab.textContent = t.toFixed(2) + 's'; };
  bar.oninput = () => { playing = false; show(+bar.value); };
  document.addEventListener('keydown', e => { if (e.code === 'Space') { playing = !playing; t0 = performance.now(); s0 = +bar.value; tick(); } });
  const tick = () => { if (!playing) return; const t = s0 + (performance.now() - t0) / 1000; show(Math.min(duration, t)); if (t < duration) requestAnimationFrame(tick); };
  const fit = () => { const k = Math.min(innerWidth / W, (innerHeight - 40) / H); stage().style.transform = `scale(${k})`; };
  fit(); addEventListener('resize', fit); show(0);
}
