#!/usr/bin/env python3
"""Draws the README's animated hero (hero-light.svg, hero-dark.svg) in this folder.

The ring copies the app's popup (Sources/Easie/RadialMenu.swift): the targets a Word file gets, in the
app's order, with each format's tint from FormatStyle.swift. One 7-second loop: right-click, the ring
opens, PDF is picked, "Saved". Pure SVG + CSS animation, so GitHub shows it without scripts.

    python3 docs/media/make-hero.py
"""
import base64, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
ICON = base64.b64encode(open(os.path.join(HERE, '..', '..', 'site', 'icon.png'), 'rb').read()).decode()
W, H, LOOP = 1280, 420, 7.0
CX, CY, R = 930, 210, 158                     # ring centre and radius
TARGETS = ['pdf', 'doc', 'odt', 'rtf', 'html', 'txt', 'md', 'pages', 'json', 'png', 'jpg']
TINT = {'pdf': (.89, .18, .16), 'doc': (.10, .35, .74), 'odt': (.12, .53, .90), 'rtf': (.55, .32, .80), 'html': (.89, .30, .15),
        'txt': (.45, .47, .50), 'md': (.20, .22, .25), 'pages': (1.0, .58, 0), 'json': (.56, .27, .68), 'png': (0, .62, .62),
        'jpg': (.93, .60, 0), 'docx': (.10, .35, .74)}
hexc = lambda c: '#%02x%02x%02x' % tuple(round(v * 255) for v in c)
pct = lambda t: f'{100 * t / LOOP:.2f}%'
FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Helvetica, Arial, sans-serif"


def glyph(fmt, w=52):
    """A page with a folded corner, a few text lines and the format's label band (FormatGlyph)."""
    h, f, tint = w * 56 / 46, w * .3, hexc(TINT[fmt])
    page = f'M{w*.1} 0H{w-f}L{w} {f}V{h-w*.1}Q{w} {h} {w-w*.1} {h}H{w*.1}Q0 {h} 0 {h-w*.1}V{w*.1}Q0 0 {w*.1} 0Z'
    lines = ''.join(f'<rect x="{w*.22}" y="{h*(.2+k*.11)}" width="{w*(.5 if k else .34)}" height="{h*.045}" rx="1" fill="{tint}" opacity=".75"/>' for k in range(3))
    return (f'<path d="{page}" fill="#fff" stroke="rgba(0,0,0,.14)" stroke-width=".8"/>'
            f'<path d="M{w-f} 0V{f*.8}Q{w-f} {f} {w-f*.8} {f}H{w}Z" fill="#d9d9de"/>{lines}'
            f'<rect x="{-w*.08}" y="{h*.63}" width="{w*.92}" height="{h*.27}" rx="3.5" fill="{tint}"/>'
            f'<text x="{w*.38}" y="{h*.82}" text-anchor="middle" font-family="{FONT}" font-weight="800" font-size="{w*.24 if len(fmt) < 5 else w*.2}" fill="#fff">{fmt.upper()}</text>')


def hero(dark):
    ink, muted = ('#F5F5F7', '#A1A1AA') if dark else ('#15171C', '#5A5F6B')
    disc, disc_line, spoke = ('#2C2C2E', 'rgba(255,255,255,.1)', 'rgba(235,235,245,.35)') if dark else ('#ECECEC', 'rgba(0,0,0,.08)', 'rgba(60,60,67,.42)')
    accent = '#2FD0C6' if dark else '#0A8C87'
    css, body = [], []
    css.append(f'''text {{ font-family: {FONT}; }}
.loop {{ animation-duration: {LOOP}s; animation-iteration-count: infinite; animation-timing-function: cubic-bezier(.22,1,.36,1); }}
.cap {{ animation-name: cap; opacity: 0; }}''')
    # left: icon, name, the three steps (they appear as the ring does each one)
    body.append(f'<image href="data:image/png;base64,{ICON}" x="64" y="70" width="96" height="96"/>')
    body.append(f'<text x="180" y="138" font-size="64" font-weight="800" letter-spacing="-2" fill="{ink}">Easie</text>')
    body.append(f'<text x="182" y="170" font-size="21" fill="{muted}">Convert any file, right from Finder. Free and offline.</text>')
    steps = [('Right-click.', .35, ink), ('Pick a format.', 1.55, ink), ('Done.', 3.6, accent)]
    for k, (txt, t0, col) in enumerate(steps):
        css.append(f'@keyframes s{k} {{ 0%, {pct(t0)} {{ opacity: 0; transform: translateY(14px); }} {pct(t0 + .45)}, {pct(LOOP - .6)} {{ opacity: 1; transform: none; }} 100% {{ opacity: 0; }} }}'
                   f'\n.s{k} {{ animation-name: s{k}; }}')
        body.append(f'<text class="loop s{k}" x="66" y="{258 + k * 56}" font-size="46" font-weight="700" letter-spacing="-1.2" fill="{col}">{txt}</text>')
    # ring
    tOpen, tHover, tPick, tDone, tClose = .5, 2.2, 2.9, 3.6, 5.9
    for i, f in enumerate(TARGETS):
        a = -math.pi / 2 + 2 * math.pi * i / len(TARGETS)
        x, y = CX + math.cos(a) * R, CY + math.sin(a) * R
        d0 = tOpen + i * .03
        if f == 'pdf':
            keys = (f'0%, {pct(d0)} {{ transform: translate({CX}px,{CY}px) scale(.2); opacity: 0; }}'
                    f' {pct(d0 + .35)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1.06); opacity: 1; }}'
                    f' {pct(d0 + .55)}, {pct(tHover)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1); opacity: 1; }}'
                    f' {pct(tHover + .2)}, {pct(tPick)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1.18); opacity: 1; }}'
                    f' {pct(tPick + .2)}, {pct(tClose)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1.22); opacity: 1; }}'
                    f' {pct(tClose + .3)}, 100% {{ transform: translate({CX}px,{CY}px) scale(.4); opacity: 0; }}')
        else:
            keys = (f'0%, {pct(d0)} {{ transform: translate({CX}px,{CY}px) scale(.2); opacity: 0; }}'
                    f' {pct(d0 + .35)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1.06); opacity: 1; }}'
                    f' {pct(d0 + .55)}, {pct(tPick)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(1); opacity: 1; }}'
                    f' {pct(tPick + .25)}, {pct(tClose)} {{ transform: translate({x:.1f}px,{y:.1f}px) scale(.85); opacity: .25; }}'
                    f' {pct(tClose + .3)}, 100% {{ transform: translate({CX}px,{CY}px) scale(.4); opacity: 0; }}')
        css.append(f'@keyframes b{i} {{ {keys} }}\n.b{i} {{ animation-name: b{i}; }}')
        r0, r1 = 66, R - 40
        hot = f == 'pdf'
        css.append(f'@keyframes l{i} {{ 0%, {pct(d0 + .1)} {{ opacity: 0; }} {pct(d0 + .45)}, {pct(tClose)} {{ opacity: {1 if hot else .9}; }} {pct(tClose + .2)}, 100% {{ opacity: 0; }} }}\n.l{i} {{ animation-name: l{i}; }}')
        body.append(f'<line class="loop l{i}" x1="{CX + math.cos(a) * r0:.1f}" y1="{CY + math.sin(a) * r0:.1f}" x2="{CX + math.cos(a) * r1:.1f}" y2="{CY + math.sin(a) * r1:.1f}" stroke="{spoke}" stroke-width="1.6" stroke-dasharray="4 5" stroke-linecap="round"/>')
        if hot:
            css.append(f'@keyframes hot {{ 0%, {pct(tHover)} {{ opacity: 0; }} {pct(tHover + .15)}, {pct(tClose)} {{ opacity: 1; }} {pct(tClose + .2)}, 100% {{ opacity: 0; }} }}\n.hot {{ animation-name: hot; }}')
            body.append(f'<line class="loop hot" x1="{CX + math.cos(a) * r0:.1f}" y1="{CY + math.sin(a) * r0:.1f}" x2="{CX + math.cos(a) * r1:.1f}" y2="{CY + math.sin(a) * r1:.1f}" stroke="{hexc(TINT["pdf"])}" stroke-width="3" stroke-linecap="round"/>')
    for i, f in enumerate(TARGETS):
        body.append(f'<g class="loop b{i}"><g transform="translate(-26 -32)">{glyph(f)}</g></g>')
    # centre disc and its states
    css.append(f'@keyframes disc {{ 0%, {pct(tOpen - .1)} {{ transform: translate({CX}px,{CY}px) scale(.5); opacity: 0; }} {pct(tOpen + .3)} {{ transform: translate({CX}px,{CY}px) scale(1.05); opacity: 1; }}'
               f' {pct(tOpen + .5)}, {pct(tDone)} {{ transform: translate({CX}px,{CY}px) scale(1); opacity: 1; }} {pct(tDone + .15)} {{ transform: translate({CX}px,{CY}px) scale(1.07); }}'
               f' {pct(tDone + .35)}, {pct(tClose)} {{ transform: translate({CX}px,{CY}px) scale(1); opacity: 1; }} {pct(tClose + .3)}, 100% {{ transform: translate({CX}px,{CY}px) scale(.5); opacity: 0; }} }}\n.disc {{ animation-name: disc; }}')
    def state(name, a, b):
        css.append(f'@keyframes {name} {{ 0%, {pct(a)} {{ opacity: 0; }} {pct(a + .12)}, {pct(b)} {{ opacity: 1; }} {pct(b + .12)}, 100% {{ opacity: 0; }} }}\n.{name} {{ animation-name: {name}; }}')
    state('st-file', 0, tHover); state('st-hover', tHover, tPick); state('st-conv', tPick, tDone); state('st-done', tDone, LOOP)
    spinner = ''.join(f'<rect x="-1.6" y="-13" width="3.2" height="7" rx="1.6" fill="{muted}" opacity="{.25 + .75 * k / 8:.2f}" transform="rotate({k * 45})"/>' for k in range(8))
    body.append(f'''<g class="loop disc"><circle r="62" fill="{disc}" stroke="{disc_line}"/>
  <g class="loop st-file"><g transform="translate(-19 -40) scale(.73)">{glyph("docx")}</g><text y="32" text-anchor="middle" font-size="12.5" font-weight="600" fill="{ink}">Q3 Report.docx</text></g>
  <g class="loop st-hover"><g transform="translate(-16 -42) scale(.62)">{glyph("pdf")}</g><text y="16" text-anchor="middle" font-size="13" font-weight="700" fill="{ink}">Convert to PDF</text><text y="33" text-anchor="middle" font-size="11.5" fill="{muted}">Document</text></g>
  <g class="loop st-conv"><g transform="translate(0 -12)">{spinner}<animateTransform attributeName="transform" type="rotate" values="0;45;90;135;180;225;270;315" calcMode="discrete" dur=".72s" repeatCount="indefinite" additive="sum"/></g><text y="26" text-anchor="middle" font-size="13" font-weight="600" fill="{ink}">Making PDF…</text></g>
  <g class="loop st-done"><circle cy="-14" r="17" fill="#34C759"/><path d="M-8 -14l5.5 5.5L8 -20" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round" stroke-linejoin="round"/><text y="20" text-anchor="middle" font-size="14" font-weight="700" fill="{ink}">Saved</text><text y="38" text-anchor="middle" font-size="12" fill="#0A84FF">Show in Finder</text></g>
</g>''')
    # the pointer: comes in, right-clicks the file, goes to PDF, clicks
    px, py = CX, CY - R
    css.append(f'@keyframes cur {{ 0% {{ transform: translate({CX + 230}px,{CY + 150}px); opacity: 0; }} 3% {{ opacity: 1; }} {pct(.4)} {{ transform: translate({CX + 4}px,{CY + 6}px); }}'
               f' {pct(.47)} {{ transform: translate({CX + 4}px,{CY + 6}px) scale(.86); }} {pct(.55)}, {pct(tHover - .5)} {{ transform: translate({CX + 4}px,{CY + 6}px); }}'
               f' {pct(tHover)} {{ transform: translate({px + 6}px,{py + 8}px); }} {pct(tPick - .06)} {{ transform: translate({px + 6}px,{py + 8}px); }} {pct(tPick)} {{ transform: translate({px + 6}px,{py + 8}px) scale(.86); }}'
               f' {pct(tPick + .1)}, {pct(tClose)} {{ transform: translate({px + 6}px,{py + 8}px); opacity: 1; }} {pct(tClose + .4)}, 100% {{ transform: translate({CX + 230}px,{CY + 150}px); opacity: 0; }} }}\n.cur {{ animation-name: cur; animation-timing-function: cubic-bezier(.65,0,.35,1); }}')
    body.append('<g class="loop cur"><path d="M0 0v25l6.1-5.8 3.9 9.1 4.3-1.8-3.9-9 8.5-.3z" fill="#111" stroke="#fff" stroke-width="1.9" stroke-linejoin="round"/></g>')
    # transform-box so CSS transforms use the SVG's own coordinates
    css.append('.loop { transform-box: view-box; transform-origin: 0 0; }')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" role="img" aria-label="Easie: right-click a file, pick a format, done.">\n'
            f'<title>Easie: right-click a file, pick a format, done.</title>\n<style>\n' + '\n'.join(css) + '\n</style>\n' + '\n'.join(body) + '\n</svg>\n')


for name, dark in (('hero-light.svg', False), ('hero-dark.svg', True)):
    open(os.path.join(HERE, name), 'w').write(hero(dark))
    print('wrote', name)
