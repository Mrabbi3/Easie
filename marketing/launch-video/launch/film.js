// Timed to a 120 BPM grid (one beat = 0.5 s): the music drops on the logo (4.0 s), breaks for
// the privacy beat (24.0 s) and hits on the end card (28.0 s). kit/music.py is run with those times.
const T = 33, DROP = 4, BRK = 24, HIT = 28;
// launch-vo/launch-vo.html sets VOICE: captions that the read can't fit at music pace follow the voice instead.
const VOICE = typeof VOP !== 'undefined';
const vw = (tag, i, fallback) => (VOICE ? VOP[tag].words[i] : fallback);
const A = '../shots/app/';
const TARGETS = ['pdf', 'doc', 'odt', 'rtf', 'html', 'txt', 'md', 'pages', 'json', 'png', 'jpg'];   // order the app shows them (targets.txt)
const ALL = ['pdf', 'docx', 'doc', 'odt', 'rtf', 'html', 'txt', 'md', 'pages', 'pptx', 'key', 'xlsx', 'numbers', 'csv', 'tsv', 'json', 'png', 'jpg', 'heic', 'tiff', 'gif', 'bmp', 'webp'];

film(T, () => {
  const K = (parent, words, opt) => kinetic(parent, words, opt);
  const place = (k, x, y, o = {}) => css(k.el, {left: x + 'px', top: y + 'px', ...o});
  function inout(el, t, a, b, {din = .45, dout = .35, sIn = .92, sOut = 1.12, blur = 22} = {}) {
    const pi = Ease.outQuint(P(t, a, a + din)), po = Ease.inQ(P(t, b - dout, b));
    el.style.opacity = Math.min(pi, 1 - po);
    el.style.filter = (1 - pi) + po > .002 ? `blur(${(1 - pi) * blur + po * blur}px)` : 'none';
    el.style.transform = `scale(${lerp(sIn, 1, pi) * lerp(1, sOut, po)})`;
  }
  const img = (src, cls = '', style = {}) => h('img', {src: A + src, class: cls, style});

  // ===== A. 0–4 s: the problem. Dark field of real Easie format glyphs ===========================
  const SA = h('div', {class: 'layer'}, h('div', {class: 'black'}));
  const field = h('div', {class: 'layer p3', style: {perspective: '1400px'}}); SA.append(field);
  const pts = Array.from({length: 34}, (_, i) => ({f: ALL[i % ALL.length], x: (hash(i, 1) - .5) * 2600, y: (hash(i, 2) - .5) * 1500, z: -2600 * hash(i, 3), r: (hash(i, 4) - .5) * 40}));
  const gl = pts.map(p => { const g = img(`glyph-${p.f}.png`, 'glyph'); field.append(g); return g; });
  const lineA1 = K(SA, [{text: 'You have a', t: .35}, {text: 'DOCX.', t: .8, cls: 'docx'}], {style: 'rise', out: 1.85});
  const lineA2 = K(SA, [{text: 'They want a', t: 2.0}, {text: 'PDF.', t: 2.45, cls: 'pdf'}], {style: 'rise', out: 3.55});
  for (const k of [lineA1, lineA2]) { place(k, 0, 470, {width: '1920px', textAlign: 'center'}); k.el.classList.add('head'); css(k.el, {fontSize: '128px', color: '#fff'}); }
  lineA1.spans[1].style.color = '#3b7bff'; lineA2.spans[1].style.color = '#ff453a';
  cue(.1, 'air', .6); cue(.8, 'thud', .7); cue(2.45, 'thud', .8); cue(1.85, 'swish', .45); cue(3.4, 'whoosh', .9);
  scene(0, DROP + .02, SA, (_, t) => {
    const rush = Ease.inExpo(P(t, 3.3, 4.0));
    pts.forEach((p, i) => {
      const z = p.z + t * 260 + rush * 2600;
      const zz = ((z + 2600) % 2800) - 2600, near = clamp((zz + 2600) / 2600);
      const op = clamp(near * 1.6) * (1 - clamp((zz - 100) / 200)) * .85;
      css(gl[i], {opacity: op, transform: `translate3d(${960 - 80 + p.x}px, ${540 - 93 + p.y}px, ${zz}px) rotate(${p.r + t * 6 * (hash(i, 5) - .5)}deg)`,
        filter: `blur(${Math.abs(zz + 900) / 140 + rush * 6}px) brightness(${lerp(.35, .85, near)})`});
    });
    lineA1.update(t); lineA2.update(t);
    const fl = P(t, 3.8, 4.0); SA.style.filter = fl > 0 ? `brightness(${1 + fl * 6})` : 'none';
  });

  // ===== B. 4–7 s: meet Easie. The real app icon lands on the drop ===============================
  const SB = h('div', {class: 'layer'}, h('div', {class: 'softbg'}));
  const icoB = img('easie-icon.png', '', {position: 'absolute', left: '810px', top: '330px', width: '300px', height: '300px'}); SB.append(icoB);
  const wordB = h('div', {class: 'word', style: {position: 'absolute', left: '885px', top: '370px', fontSize: '210px', lineHeight: 1, whiteSpace: 'nowrap', color: 'var(--ink)', paddingRight: '20px'}}, 'Easie'); SB.append(wordB);
  const tagB = h('div', {class: 'mono', style: {position: 'absolute', left: '893px', top: '600px', fontSize: '24px', color: 'var(--accent)'}}); SB.append(tagB);
  const TAG = 'THE FREE FILE CONVERTER FOR MAC';
  cue(DROP, 'impact', 1); cue(DROP + .02, 'chime', .7); cue(4.75, 'swish', .6, .3);
  for (let i = 0; i < 14; i++) cue(5.25 + i * .045, 'type', .28);
  scene(DROP - .02, 7.0, SB, (_, t) => {
    const p = P(t, DROP - .02, DROP + .55), s = t < DROP ? .2 : lerp(1.35, 1, Ease.spring(p));
    const slide = Ease.inOutQuint(P(t, 4.7, 5.3));
    css(icoB, {transform: `translateX(${lerp(0, -330, slide)}px) scale(${s}) rotate(${lerp(-12, 0, Ease.outBack(p))}deg)`, filter: `drop-shadow(0 30px 40px rgba(10,60,80,${.25 * clamp(p * 2)}))`});
    css(wordB, {clipPath: `inset(-20px ${lerp(100, 0, Ease.outQuint(P(t, 4.85, 5.4)))}% -20px 0)`, transform: `translateX(${lerp(-60, 0, Ease.outQuint(P(t, 4.85, 5.4)))}px)`});
    tagB.textContent = TAG.slice(0, Math.floor(P(t, 5.25, 5.9) * TAG.length));
    css(SB, {transform: `scale(${lerp(1.04, 1, Ease.outQuint(P(t, DROP, 6.9)))})`});
    inout(SB, t, DROP - .02, 7.0, {din: .05, dout: .4, sOut: 1.2});
  });

  // ===== C+D. 7–20 s: the Mac. Lid opens, Easie from the Dock, then right-click in Finder ==========
  const SC = h('div', {class: 'layer'}, h('div', {class: 'softbg'}));
  const world = h('div', {class: 'layer p3', style: {perspective: '3200px', perspectiveOrigin: '50% 30%'}}); SC.append(world);
  const rig = h('div', {class: 'rig'}); world.append(rig);
  const floor = h('div', {class: 'floor'}), deck = h('div', {class: 'deck'}, h('i', {class: 'kb'}), h('i', {class: 'pad'})), lip = h('div', {class: 'lip'}, h('i'));
  const screenEl = h('div', {class: 'screen'}), lidBack = h('div', {class: 'lid-back'}, h('i', {class: 'apple-free'}));
  const lid = h('div', {class: 'lid'}, h('div', {class: 'lid-front'}, screenEl), lidBack);
  rig.append(floor, deck, lip, lid);
  // the desktop inside the screen
  const desk = h('div', {class: 'desk'}); screenEl.append(desk);
  const wall = h('div', {class: 'wall'}); desk.append(wall);
  desk.append(h('div', {class: 'menubar'}, h('b', {}, 'Finder'), h('span', {}, 'File'), h('span', {}, 'Edit'), h('span', {}, 'View'), h('span', {}, 'Go'), h('span', {}, 'Window'), h('span', {}, 'Help'),
    h('span', {class: 'r', html: '<svg width="26" height="14" viewBox="0 0 26 14"><rect x=".5" y=".5" width="22" height="13" rx="3.5" fill="none" stroke="#fff" opacity=".8"/><rect x="2.5" y="2.5" width="16" height="9" rx="2" fill="#fff"/><rect x="23.5" y="4.5" width="2" height="5" rx="1" fill="#fff" opacity=".6"/></svg><svg width="20" height="15" viewBox="0 0 20 15" fill="#fff"><path d="M10 13.5l2.6-2.9a3.6 3.6 0 0 0-5.2 0z"/><path d="M4.8 8a7.4 7.4 0 0 1 10.4 0l1.4-1.5a9.5 9.5 0 0 0-13.2 0z" opacity=".9"/><path d="M1.6 4.6a12 12 0 0 1 16.8 0L19.8 3A14 14 0 0 0 .2 3z" opacity=".9"/></svg><span>Fri Oct 23&nbsp;&nbsp;9:41 AM</span>'})));
  const dockApps = ['finder', 'safari', 'mail', 'notes', 'photos', 'pages', 'keynote', 'numbers', 'settings'];
  const dock = h('div', {class: 'dock'}); desk.append(dock);
  const dockIt = {};
  for (const n of dockApps) { const it = h('div', {class: 'it'}, img(`dock-${n}.png`), h('i', {class: 'run'})); dock.append(it); dockIt[n] = it; }
  dock.append(h('i', {class: 'sep'}));
  const easieIt = h('div', {class: 'it'}, img('easie-icon.png'), h('i', {class: 'run'})); dock.append(easieIt);
  dock.append(h('div', {class: 'it'}, img('dock-trash.png')));
  dockIt.finder.querySelector('.run').style.opacity = 1;
  // dock geometry: 12 slots of 80 px + gaps 10, separator 9 px, padding 14 -> centred in 1920
  const dockW = 14 * 2 + 11 * 80 + 10 * 11 + 9; const dockX0 = 960 - dockW / 2 + 14;
  const easieX = dockX0 + 9 * 90 + 9 + 10 + 40, easieY = 1080 - 10 - 12 - 40;

  // Finder: Documents, icon view, sorted by name
  const FW = {x: 760, y: 190};
  const finder = h('div', {class: 'win finder', style: {left: FW.x + 'px', top: FW.y + 'px'}}); desk.append(finder);
  const folderSvg = '<svg viewBox="0 0 20 20" fill="none" stroke="#0A84FF" stroke-width="1.6"><path d="M2.5 5.5a1.5 1.5 0 0 1 1.5-1.5h4l1.6 1.8h6.4a1.5 1.5 0 0 1 1.5 1.5v7.7a1.5 1.5 0 0 1-1.5 1.5H4a1.5 1.5 0 0 1-1.5-1.5z"/></svg>';
  const side = h('div', {class: 'side'}, h('h6', {}, 'Favorites'),
    ...['Recents', 'Applications', 'Desktop', 'Documents', 'Downloads'].map(n => h('div', {class: n === 'Documents' ? 'on' : '', html: folderSvg + n})));
  finder.append(h('div', {class: 'lights'}, h('i'), h('i'), h('i')), side,
    h('div', {class: 'tb'}, h('span', {class: 'ch'}, '‹ ›'), h('b', {}, 'Documents'), h('div', {class: 'tools', html: '<span>▦</span><span>☰</span><span>⌕</span>'})));
  const files = [['Budget 2026.xlsx', 'icon-xlsx.png'], ['Invoice 0412.pdf', 'thumb-invoice-pdf.png', 1], ['Launch.key', 'icon-key.png'], ['Pitch Deck.pptx', 'icon-pptx.png'],
    ['Q3 Report.docx', 'icon-demo-docx.png'], ['Q3 Report.pdf', 'thumb-q3-pdf.png', 1], ['Trip Notes.md', 'icon-md.png']];
  const slot = i => [220 + 40 + (i % 4) * 180, 100 + Math.floor(i / 4) * 190];      // top-left of a file cell, in window coords
  const fileEls = files.map(([n, ic, thumb]) => { const f = h('div', {class: 'file'}, h('div', {class: 'ic'}, img(ic, thumb ? 'thumb' : '')), h('div', {class: 'nm'}, n)); finder.append(f); return f; });
  const fresh = h('i', {class: 'fresh'}); fileEls[5].querySelector('.ic').style.position = 'relative'; fileEls[5].querySelector('.ic').append(fresh);
  const iconCenter = i => { const [x, y] = slot(i); return [FW.x + x + 90, FW.y + y + 55]; };
  const [DX, DY] = iconCenter(4);                // Q3 Report.docx: where the right-click happens

  // Setup window (the real SetupView render), opened from the Dock
  const SW = {x: 1230 - 305, y: 200};
  const setup = h('div', {class: 'win setup', style: {left: SW.x + 'px', top: SW.y + 'px', transformOrigin: `${easieX - SW.x}px ${easieY - SW.y}px`}},
    img('setup.png', 'ui'), h('i', {class: 'toggle'}), h('div', {class: 'lights'}, h('i'), h('i'), h('i')));
  desk.append(setup);
  const ring = h('div', {style: {position: 'absolute', left: SW.x + 22 + 'px', top: SW.y + 196 / 1.5 + 'px', width: '567px', height: '120px', borderRadius: '18px', border: '4px solid #0A84FF', opacity: 0}});
  desk.append(ring);

  // Context menu (macOS Finder), ends with Easie's item
  const MI = ['Open', ['Open With', 1], '-', 'Move to Trash', '-', 'Get Info', 'Rename', 'Compress “Q3 Report.docx”', 'Duplicate', 'Quick Look', '-', 'Copy', 'Share…', '-', 'tags', 'Tags…', '-', ['Quick Actions', 1], '-', 'Edit with Easie'];
  const menu = h('div', {class: 'menu'}); desk.append(menu);
  const items = [];
  for (const m of MI) {
    if (m === '-') { menu.append(h('hr')); continue; }
    if (m === 'tags') { menu.append(h('div', {class: 'tags', html: ['#ff453a', '#ff9f0a', '#ffd60a', '#32d74b', '#0a84ff', '#bf5af2', '#8e8e93'].map(c => `<i style="background:${c}"></i>`).join('')})); continue; }
    const [label, sub] = Array.isArray(m) ? m : [m, 0];
    const el = h('div', {class: 'mi'}, label, sub ? h('span', {class: 'ar'}, '›') : null); menu.append(el); items.push(el);
  }
  const RC = {x: DX + 6, y: DY + 4};                        // right-click point
  const MENU = {x: RC.x + 2, y: RC.y - 200};
  css(menu, {left: MENU.x + 'px', top: MENU.y + 'px'});
  // item geometry: padding 7, item 30, hr 11, tags row 27
  const itemY = []; { let y = MENU.y + 7; for (const m of MI) { if (m === '-') { y += 11; continue; } if (m === 'tags') { y += 27; continue; } itemY.push(y); y += 30; } }
  const easieItemY = itemY[itemY.length - 1] + 15;

  // The popup: real glyphs and centre-disc renders, placed with the app's own geometry (RadialMenu.swift)
  const PT = 1.3, R = Math.max(122, TARGETS.length * 74 / (2 * Math.PI)) * PT, SIDE = 503;
  const radial = h('div', {class: 'radial', style: {left: RC.x - SIDE / 2 + 'px', top: RC.y - SIDE / 2 + 'px'}}); desk.append(radial);
  const svgNS = 'http://www.w3.org/2000/svg', svg = document.createElementNS(svgNS, 'svg'); svg.setAttribute('viewBox', `0 0 ${SIDE} ${SIDE}`); radial.append(svg);
  const ang = i => -Math.PI / 2 + 2 * Math.PI * i / TARGETS.length;
  const tint = {pdf: '#e32e29'};
  const spokes = TARGETS.map((f, i) => {
    const a = ang(i), r0 = (59 + 4) * PT, r1 = R - 34 * PT, l = document.createElementNS(svgNS, 'line');
    l.setAttribute('x1', SIDE / 2 + Math.cos(a) * r0); l.setAttribute('y1', SIDE / 2 + Math.sin(a) * r0);
    l.setAttribute('x2', SIDE / 2 + Math.cos(a) * r1); l.setAttribute('y2', SIDE / 2 + Math.sin(a) * r1);
    l.setAttribute('stroke-linecap', 'round'); l.style.filter = 'drop-shadow(0 0 1.3px rgba(0,0,0,.35))'; svg.append(l); return l;
  });
  const bubs = TARGETS.map(f => { const b = img(`glyph-${f}.png`, 'bub'); radial.append(b); return b; });
  const disc = h('div', {class: 'disc'}); radial.append(disc);
  const dImgs = {file: img('center-file.png'), hover: img('center-hover-pdf.png'), conv: img('center-converting.png'), done: img('center-done.png')};
  const spin = img('spinner.png', 'spin');
  for (const k in dImgs) disc.append(dImgs[k]); disc.append(spin);

  const over = h('div', {class: 'over', style: {position: 'absolute', inset: 0}}); desk.append(over);

  // ---- timeline of the Mac scene ----
  const tC0 = 7.0, tOpen1 = 8.3, tDive0 = 8.4, tDive1 = 9.4;
  const tDock = 10.0, tSetup = 10.12, tClose = 11.7;
  const tSel = 12.55, tRight = 12.95, tPick = 13.95, tPop = 14.05, tHover = 15.55, tClick = 16.15, tDone = 16.85, tDismiss = 18.05, tNew = 18.3, tC1 = 20.0;
  const lightsClose = [SW.x + 22 + 8, SW.y + 22 + 8];
  const pdfBub = [RC.x, RC.y - R];
  const path = [
    [9.35, 1500, 760], [tDock - .02, easieX, easieY - 6, 'inOutC'], [tDock + .3, easieX, easieY - 6],
    [10.9, SW.x + 470, SW.y + 182, 'inOutC'], [11.25, SW.x + 470, SW.y + 182], [tClose - .02, ...lightsClose, 'inOutC'], [tClose + .2, ...lightsClose],
    [tSel - .02, DX, DY + 10, 'inOutC'], [tRight, RC.x, RC.y, 'outC'],
    [13.25, RC.x + 40, RC.y + 30, 'inOutC'], [tPick - .03, MENU.x + 120, easieItemY, 'inOutC'], [tPick + .25, MENU.x + 120, easieItemY],
    [tHover - .45, MENU.x + 120, easieItemY], [tHover, pdfBub[0] + 4, pdfBub[1] + 6, 'inOutC'], [tClick + .3, pdfBub[0] + 4, pdfBub[1] + 6],
    [tDismiss + .1, pdfBub[0] + 4, pdfBub[1] + 6], [tNew + .9, DX + 260, DY + 230, 'inOutC'], [tC1 + 1, DX + 260, DY + 230]];
  const cur = pointer({over}, path, [tDock, tClose, tSel, tRight, tPick, tClick], {size: 1.3, silent: true});
  cue(tDock, 'click', 1); cue(tClose, 'click', .8); cue(tSel, 'click', .9); cue(tRight, 'click', 1); cue(tPick, 'click', 1); cue(tClick, 'click', 1.1);
  cue(tC0 + .05, 'whoosh', .7); cue(7.35, 'air', .6); cue(tOpen1 - .05, 'thud', .55); cue(7.9, 'riser', .25); cue(tDive0 + .1, 'whoosh', .8, .2);
  cue(tSetup, 'pop', .8); cue(tClose + .05, 'whoosh-out', .4); cue(tRight + .02, 'tap', .5);
  TARGETS.forEach((_, i) => { if (i % 2 === 0) cue(tPop + .02 + i * .025, 'pop', .35, Math.cos(ang(i)) * .6, 1 + i * .03); });
  cue(tPop, 'swish', .6); cue(tHover, 'tick', .6); cue(tClick + .05, 'counter', .35); cue(tDone, 'ding', 1); cue(tDismiss, 'whoosh-out', .45);
  cue(tNew, 'pop', .9, .3); cue(tNew + .05, 'chime', .55);

  // captions (stage space, over the wallpaper)
  const capL = h('div', {class: 'layer', style: {zIndex: 10}}); SC.append(capL);
  const cOnce = K(capL, [{text: 'Set it up', t: 10.25}, {text: 'once.', t: 10.55}], {style: 'rise', out: tClose - .1}); place(cOnce, 120, 470); cOnce.el.classList.add('cap', 'head');
  const cR = K(capL, [{text: 'Right-click.', t: tRight}], {style: 'rise', out: tC1 - .5}); place(cR, 120, 300); cR.el.classList.add('cap', 'head');
  const cP = K(capL, [{text: 'Pick a', t: tPop + .1}, {text: 'format.', t: tPop + .3}], {style: 'rise', out: tC1 - .5}); place(cP, 120, 430); cP.el.classList.add('cap', 'head');
  const cD = K(capL, [{text: 'Done.', t: tDone}], {style: 'slam', s0: 1.5, out: tC1 - .5}); place(cD, 120, 560); cD.el.classList.add('cap', 'head'); cD.el.style.color = '#7ff5e8';
  const cS = K(capL, [{text: 'Saved right next to the original', t: tNew + .2}], {style: 'fade', blur: 8, out: tC1 - .5}); place(cS, 0, 0); cS.el.classList.add('sub'); css(cS.el, {left: '124px', top: '700px'});
  cue(tRight + .02, 'swish', .35); cue(tDone, 'thud', .6);

  scene(tC0, tC1, SC, (_, t) => {
    // --- laptop: lid opens (7.0–8.3), screen wakes, camera dives into the screen (8.4–9.4)
    const op = Ease.inOutC(P(t, tC0 + .1, tOpen1)), lidA = lerp(-88, 0, op) + 4 * Math.sin(Math.PI * P(t, tOpen1 - .15, tOpen1 + .25)) * (t > tOpen1 - .15 ? 1 : 0) * (1 - P(t, tOpen1, tOpen1 + .3));
    css(lid, {transform: `rotateX(${lidA}deg)`});
    css(deck, {transform: 'rotateX(90deg)'}); css(lip, {transform: 'rotateX(0deg)'});
    const wake = P(t, 7.75, 8.35); screenEl.style.filter = `brightness(${lerp(0, 1, Ease.outQ(wake))})`;
    const dive = Ease.inOutQuint(P(t, tDive0, tDive1));
    const s0 = .36 + .03 * P(t, tC0, tDive0);
    const s = lerp(s0, 1, dive);
    const rx = lerp(20, 0, Ease.inOutQ(P(t, tC0, tDive1)));
    css(rig, {transform: `translate(${960}px, ${lerp(470, 540, dive)}px) rotateX(${rx}deg) scale3d(${s}, ${s}, ${s}) translate(${-960}px, ${-540}px)`});
    floor.style.opacity = deck.style.opacity = lip.style.opacity = 1 - dive;
    // --- camera inside the desktop
    const zoomIn = Ease.inOutC(P(t, 9.4, 10.0)), toFinder = Ease.inOutC(P(t, tClose, tSel)), toPop = Ease.inOutC(P(t, tPop - .1, tPop + .9)), back = Ease.inOutC(P(t, tDismiss, tNew + .8));
    let cx = lerp(960, 1040, zoomIn), cy = lerp(540, 560, zoomIn), cs = lerp(1, 1.25, zoomIn);
    const fx = DX - 440 / 1.3, fy = DY - 20;
    cx = lerp(cx, fx, toFinder); cy = lerp(cy, fy, toFinder); cs = lerp(cs, 1.3, toFinder);
    cx = lerp(cx, RC.x - 440 / 1.5, toPop); cy = lerp(cy, RC.y + 10, toPop); cs = lerp(cs, 1.5, toPop);
    cx = lerp(cx, DX - 440 / 1.3, back); cy = lerp(cy, DY - 10, back); cs = lerp(cs, 1.3, back);
    cs *= 1 + .02 * P(t, tNew, tC1);
    cam(desk, {x: cx, y: cy, s: cs, cx: 960 + 290 * P(t, 9.4, 10) * 0, cy: 540});
    // --- Finder opens once the setup window has closed
    const fo = Ease.outQuint(P(t, tClose + .12, tClose + .5));
    css(finder, {display: t < tClose + .12 ? 'none' : '', opacity: clamp(fo * 2), transform: `scale(${lerp(.94, 1, fo)})`});
    // --- Dock: Easie bounces when clicked
    const bounce = t > tDock ? Math.abs(Math.sin(Math.PI * P(t, tDock, tDock + .5))) * (1 - P(t, tDock, tDock + .5)) : 0;
    easieIt.querySelector('img').style.transform = `translateY(${-38 * bounce}px)`;
    easieIt.querySelector('.run').style.opacity = t > tDock + .1 ? 1 : 0;
    // --- Setup window opens out of the Dock icon, then closes
    const so = Ease.outQuint(P(t, tSetup, tSetup + .45)), sc = Ease.inQ(P(t, tClose + .02, tClose + .3));
    css(setup, {opacity: clamp(so * 3) * (1 - sc), transform: `scale(${lerp(.08, 1, so) * lerp(1, .9, sc)})`, display: t < tSetup || sc >= 1 ? 'none' : ''});
    const rg = Ease.outExpo(P(t, 10.75, 11.1)) * (1 - P(t, 11.45, 11.6));
    css(ring, {opacity: rg, transform: `scale(${lerp(1.06, 1, rg)})`});
    // --- Finder: select, right-click menu with hover highlight, Easie item flashes when picked
    fileEls.forEach((f, i) => {
      if (i === 5 && t < tNew) { f.style.display = 'none'; return; }
      f.style.display = '';
      const shift = i === 6 ? Ease.outQuint(P(t, tNew, tNew + .45)) : 1;
      const [x0, y0] = slot(i === 6 ? 5 : i), [x1, y1] = slot(i);
      const [x, y] = i === 6 ? [lerp(x0, x1, shift), lerp(y0, y1, shift)] : [x1, y1];
      css(f, {left: x + 'px', top: y + 'px'});
    });
    fileEls[4].classList.toggle('sel', t >= tSel && t < tNew);
    fileEls[5].classList.toggle('sel', t >= tNew + .5);
    const np = Ease.outBackBig(P(t, tNew, tNew + .5));
    fileEls[5].querySelector('.ic img').style.transform = `scale(${t < tNew ? 0 : lerp(.3, 1, np)})`;
    fresh.style.opacity = t < tNew ? 0 : 1 - P(t, tNew + .9, tNew + 1.6);
    const mOpen = t >= tRight && t < tPick + .12;
    menu.style.display = mOpen ? '' : 'none';
    if (mOpen) {
      const mo = Ease.outQuint(P(t, tRight, tRight + .12)); css(menu, {opacity: mo, transform: `scale(${lerp(.97, 1, mo)})`});
      const [px, py] = kf(t, path.map(([tt, x, y, e]) => [tt, [x, y], e || 'inOutC']));
      items.forEach((el, k) => { const inside = px > MENU.x && px < MENU.x + 330 && py >= itemY[k] && py < itemY[k] + 30;
        const flash = k === items.length - 1 && t >= tPick && Math.floor((t - tPick) / .04) % 2 === 1;
        el.classList.toggle('on', inside && !flash); });
    }
    // --- the popup
    const popOn = t >= tPop && t < tDismiss + .25;
    radial.style.display = popOn ? '' : 'none';
    if (popOn) {
      const closing = Ease.inQ(P(t, tDismiss, tDismiss + .22));
      radial.style.opacity = 1 - closing;
      const hovered = t >= tHover && t < tClick, chosen = t >= tClick, phaseDone = t >= tDone;
      const cOpen = Ease.spring(P(t, tPop, tPop + .45));
      css(disc, {transform: `scale(${lerp(.5, 1, clamp(cOpen, 0, 1.2)) * lerp(1, .5, closing) * (phaseDone ? 1 + .06 * Math.sin(Math.PI * P(t, tDone, tDone + .3)) : 1)})`, opacity: clamp(P(t, tPop, tPop + .15) * 1.5)});
      bubs.forEach((b, i) => {
        const d = tPop + i * .025, e = Ease.spring(P(t, d, d + .55)), a = ang(i);
        const isPdf = i === 0, faded = chosen && !isPdf;
        const target = !e ? .2 : isPdf && chosen ? 1.2 : isPdf && hovered ? 1.18 : faded ? .85 : 1;
        const hs = isPdf ? lerp(1, target, Ease.outBack(P(t, hovered || chosen ? tHover : 0, (hovered || chosen ? tHover : 0) + .25))) : faded ? lerp(1, .85, P(t, tClick, tClick + .25)) : 1;
        const r = R * e * (1 - closing);
        css(b, {opacity: clamp(e * 3) * (faded ? lerp(1, .25, P(t, tClick, tClick + .25)) : 1),
          transform: `translate(${SIDE / 2 - 40.3 + Math.cos(a) * r}px, ${SIDE / 2 - 46.8 + Math.sin(a) * r}px) scale(${lerp(.2, 1, clamp(e, 0, 1.3)) * hs})`});
        const l = spokes[i], tr = clamp(P(t, tPop + .08 + i * .02, tPop + .38 + i * .02)), hot = isPdf && (hovered || chosen);
        l.setAttribute('stroke', hot ? tint.pdf : 'rgba(60,60,67,.45)'); l.setAttribute('stroke-width', hot ? 2.5 * PT : 1.5 * PT);
        l.setAttribute('stroke-dasharray', hot ? 'none' : `${4 * PT} ${5 * PT}`);
        const len = R - 34 * PT - 63 * PT; l.style.strokeDashoffset = 0;
        l.setAttribute('x2', SIDE / 2 + Math.cos(a) * (63 * PT + len * tr)); l.setAttribute('y2', SIDE / 2 + Math.sin(a) * (63 * PT + len * tr));
        l.style.opacity = (faded ? .4 : 1) * (1 - closing);
      });
      const stateImg = phaseDone ? 'done' : chosen ? 'conv' : hovered ? 'hover' : 'file';
      for (const k in dImgs) dImgs[k].style.opacity = k === stateImg ? 1 : 0;
      spin.style.opacity = stateImg === 'conv' ? 1 : 0;
      spin.style.transform = `rotate(${Math.floor(t / .09) * 45}deg)`;
    }
    cur.update(t);
    cOnce.update(t); cR.update(t); cP.update(t); cD.update(t); cS.update(t);
    inout(SC, t, tC0, tC1, {din: .35, dout: .4, sOut: 1.15});
  });

  // ===== E. 20–24 s: 23 formats in =================================================================
  const SE = h('div', {class: 'layer'}, h('div', {class: 'softbg'}));
  const eH1 = K(SE, [{text: '23', t: 20.25, cls: 'acc'}, {text: 'formats', t: 20.45}, {text: 'in.', t: 20.65}], {style: 'rise'}); place(eH1, 0, 120, {width: '1920px', textAlign: 'center'});
  const eH2 = K(SE, [{text: 'The', t: vw('f2', 0, 21.2)}, {text: 'right', t: vw('f2', 1, 21.35)}, {text: 'one', t: vw('f2', 2, 21.5)}, {text: 'out.', t: vw('f2', 3, 21.65)}], {style: 'rise'}); place(eH2, 0, 250, {width: '1920px', textAlign: 'center'});
  for (const k of [eH1, eH2]) { k.el.classList.add('head'); css(k.el, {fontSize: '104px', color: 'var(--ink)'}); }
  eH1.spans[0].style.color = 'var(--accent)';
  const grid = h('div', {class: 'layer p3'}); SE.append(grid);
  const gEls = ALL.map((f, i) => { const g = img(`glyph-${f}.png`, 'glyph', {width: '122px'}); grid.append(g); return g; });
  const gpos = i => { const row = i < 8 ? 0 : i < 16 ? 1 : 2, col = i < 8 ? i : i < 16 ? i - 8 : i - 16, n = row < 2 ? 8 : 7; return [960 - (n * 150) / 2 + col * 150 + 14, 430 + row * 180]; };
  ALL.forEach((_, i) => { const [x, y] = gpos(i), d = Math.hypot(x - 960, y - 610) / 900; if (i % 2 === 0) cue(20.35 + d * .9, 'pop', .3, (x - 960) / 1000, .9 + hash(i, 9) * .3); });
  cue(20.05, 'whoosh', .7); cue(20.25, 'thud', .6); cue(vw('f2', 0, 21.2), 'swish', .4);
  scene(20.0, BRK, SE, (_, t) => {
    eH1.update(t); eH2.update(t);
    gEls.forEach((g, i) => {
      const [x, y] = gpos(i), d = Math.hypot(x - 960, y - 610) / 900, p = Ease.spring(P(t, 20.35 + d * .9, 20.35 + d * .9 + .6));
      const fl = Math.sin(t * 1.6 + i * .7) * 6;
      css(g, {opacity: clamp(p * 3), transform: `translate3d(${x}px, ${y + lerp(80, 0, clamp(p)) + fl}px, ${lerp(-400, 0, clamp(p))}px) scale(${lerp(.4, 1, clamp(p, 0, 1.15))})`});
    });
    css(grid, {transform: `scale(${lerp(1, 1.06, Ease.inOutQ(P(t, 21.5, BRK)))})`});
    inout(SE, t, 20.0, BRK, {din: .35, dout: .35});
  });

  // ===== F. 24–28 s: works offline, nothing to sign up for, free (dark break) =====================
  const SF = h('div', {class: 'layer'}, h('div', {class: 'black'}));
  const tNo = [vw('noads', 0, 25.2), vw('noads', 2, 25.6), vw('noads', 4, 26.0)], tFree = vw('free', 0, 26.8);
  const fA = K(SF, [{text: 'Works', t: vw('offline', 0, 24.25)}, {text: 'offline.', t: vw('offline', 1, 24.45)}], {style: 'rise', out: tNo[0] - .15}); place(fA, 0, 460, {width: '1920px', textAlign: 'center'});
  const fB = K(SF, [{text: 'No uploads.', t: tNo[0]}, {text: 'No ads.', t: tNo[1]}, {text: 'No account.', t: tNo[2]}], {style: 'slam', s0: 1.3, out: tFree - .15, outDur: VOICE ? .15 : .35}); place(fB, 0, 470, {width: '1920px', textAlign: 'center'});
  const fC = K(SF, [{text: 'Free.', t: tFree}], {style: 'slam', s0: 1.6, out: HIT - .15, outDur: .25}); place(fC, 0, 330, {width: '1920px', textAlign: 'center'});
  const fCs = K(SF, [{text: 'NO TRIAL · NO PAID TIER · FREE FOREVER', t: tFree + .35}], {style: 'fade', blur: 8, out: HIT - .15, outDur: .25}); place(fCs, 0, 700, {width: '1920px', textAlign: 'center'});
  for (const k of [fA, fB]) { k.el.classList.add('head'); css(k.el, {fontSize: '120px', color: '#fff'}); }
  fB.spans.forEach((s, i) => s.style.color = i === 2 ? '#fff' : i === 1 ? '#d8d8dc' : '#b0b0b8');
  fC.el.classList.add('head'); css(fC.el, {fontSize: '330px'});
  css(fC.spans[0], {backgroundImage: 'linear-gradient(120deg, #7ff5e8, #12B5AE 45%, #5aa8ff)', WebkitBackgroundClip: 'text', backgroundClip: 'text', color: 'transparent', padding: '0 .06em 0 .02em', marginRight: 0});
  const glow = h('div', {style: {position: 'absolute', left: '660px', top: '380px', width: '600px', height: '300px', borderRadius: '50%', background: 'rgba(18,181,174,.35)', filter: 'blur(90px)', opacity: 0}}); SF.insertBefore(glow, fC.el);
  fCs.el.classList.add('mono'); css(fCs.el, {fontSize: '22px', color: '#9a9aa5'});
  cue(vw('offline', 0, 24.25), 'thud', .55); tNo.forEach((t, i) => cue(t, 'stamp', .55 + i * .1)); cue(tFree, 'impact', .8); cue(tFree + .02, 'chime', .5);
  scene(BRK, HIT, SF, (_, t) => {
    fA.update(t); fB.update(t); fC.update(t); fCs.update(t);
    glow.style.opacity = Ease.outQuint(P(t, tFree, tFree + .5)) * (1 - P(t, HIT - .15, HIT + .1));
    inout(SF, t, BRK, HIT, {din: .3, dout: .12, sOut: 1.0, blur: 0});
  });

  // ===== G. 28–33 s: end card ====================================================================
  const SG = h('div', {class: 'layer'}, h('div', {class: 'softbg'}));
  const icoG = img('easie-icon.png', '', {position: 'absolute', left: '540px', top: '235px', width: '250px', height: '250px'}); SG.append(icoG);
  const wordG = h('div', {class: 'word', style: {position: 'absolute', left: '830px', top: '238px', fontSize: '200px', lineHeight: 1, color: 'var(--ink)', whiteSpace: 'nowrap', paddingRight: '20px'}}, 'Easie'); SG.append(wordG);
  const tagG = K(SG, [{text: 'Convert any file,', t: 28.7}, {text: 'right from Finder.', t: 28.95}], {style: 'rise', dy: 24, blur: 10}); place(tagG, 836, 440); tagG.el.classList.add('lead'); css(tagG.el, {fontSize: '44px', color: 'var(--muted)'});
  const btnG = h('div', {class: 'btn2', html: '<svg viewBox="0 0 24 24"><path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 19.5h14" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>Download free for Mac'}); css(btnG, {left: '960px', top: '600px'}); SG.append(btnG);
  const urlG = h('div', {class: 'url2'}); css(urlG, {left: '960px', top: '742px'}); SG.append(urlG);
  const metaG = K(SG, [{text: 'macOS 13 or later · Apple Silicon & Intel', t: 30.1}], {style: 'fade', blur: 6}); place(metaG, 0, 822, {width: '1920px', textAlign: 'center'}); metaG.el.classList.add('mono'); css(metaG.el, {fontSize: '19px', color: 'var(--muted)', textTransform: 'uppercase'});
  const devG = K(SG, [{text: 'Designed and developed by MD Rabbi', t: 30.45}], {style: 'fade', blur: 6}); place(devG, 0, 935, {width: '1920px', textAlign: 'center'}); css(devG.el, {font: '500 24px var(--title)', color: 'var(--ink)', letterSpacing: '-.01em'});
  const gOver = h('div', {class: 'over', style: {position: 'absolute', inset: 0}}); SG.append(gOver);
  const URL = 'mrabbi3.github.io/Easie', uT0 = 29.35, uT1 = 30.1, clickG = 31.35;
  const curG = pointer({over: gOver}, [[30.55, 1500, 1080], [clickG - .03, 1080, 645, 'inOutC'], [clickG + 1.5, 1080, 645]], [clickG], {size: 1.3, silent: true});
  cue(HIT, 'impact', .9); cue(HIT + .02, 'chime', .8); cue(28.55, 'swish', .5, .3); typeCues(uT0, uT1, URL.length, 'type'); cue(clickG, 'click', 1); cue(clickG + .05, 'ding', .45);
  // with a voice: keep the end card's typing and swish under the last line
  if (VOICE) for (const c of CUES) if (['type', 'swish'].includes(c.name) && c.t > VOP.end.start - .2 && c.t < VOP.end.end + .1) c.gain *= .3;
  scene(HIT, T, SG, (_, t) => {
    const p = Ease.spring(P(t, HIT, HIT + .55));
    css(icoG, {transform: `scale(${lerp(.3, 1, clamp(p, 0, 1.2))}) rotate(${lerp(-14, 0, Ease.outBack(P(t, HIT, HIT + .5)))}deg)`, filter: `drop-shadow(0 26px 34px rgba(10,60,80,${.22 * clamp(p * 2)}))`, opacity: clamp(P(t, HIT, HIT + .1) * 2)});
    const wo = Ease.outQuint(P(t, HIT + .15, HIT + .7));
    css(wordG, {clipPath: `inset(-20px ${lerp(100, 0, wo)}% -20px 0)`, transform: `translateX(${lerp(-50, 0, wo)}px)`});
    tagG.update(t); metaG.update(t); devG.update(t);
    const bp = Ease.outBack(P(t, 29.05, 29.5)), press = Math.max(0, 1 - Math.abs(t - clickG) / .12);
    css(btnG, {opacity: clamp(bp * 2), transform: `translate(-50%, ${lerp(30, 0, bp)}px) scale(${1 - .05 * press})`, background: t > clickG ? 'var(--accent)' : 'var(--ink)'});
    const k = Math.floor(P(t, uT0, uT1) * URL.length + 1e-6);
    urlG.textContent = URL.slice(0, k) + (t > uT0 - .3 && t < uT1 + .9 && Math.floor(t / .4) % 2 === 0 ? '▍' : '');
    const up = Ease.outQuint(P(t, uT0 - .3, uT0 + .1)); css(urlG, {opacity: up, transform: `translate(-50%, ${lerp(16, 0, up)}px)`});
    curG.update(t);
    css(SG, {transform: `scale(${lerp(1.03, 1, Ease.outQuint(P(t, HIT, T)))})`});
    SG.style.opacity = 1 - P(t, T - .5, T);
  });
});
