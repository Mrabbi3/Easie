"""Synthesised sound effects (no samples, no licences): writes audio/sfx/<name>.wav at 48 kHz.

Motion-design SFX are short and tuned: every UI event gets a transient (click / tap / key),
every move gets air (whoosh / swish), every reveal gets weight (impact / punch / boom) and every
success gets a pitched note (ding / chime). Films ask for them by name with cue(t, name).

    python kit/sfx.py        (numpy + scipy + soundfile; the chatterbox venv has them)
"""
import os
import numpy as np, soundfile as sf
from scipy.signal import butter, sosfilt

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'audio', 'sfx')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)

def t_(d): return np.arange(int(d * SR)) / SR
def env(d, a=.002, r=None, curve=4.0):
    t = t_(d); r = d - a if r is None else r
    e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-curve * np.maximum(0, t - a) / max(r, 1e-4))
    return e
def bp(x, lo, hi, o=2): return sosfilt(butter(o, [lo, hi], 'bandpass', fs=SR, output='sos'), x)
def lp(x, f, o=2): return sosfilt(butter(o, f, 'lowpass', fs=SR, output='sos'), x)
def hp(x, f, o=2): return sosfilt(butter(o, f, 'highpass', fs=SR, output='sos'), x)
def noise(d): return rng.standard_normal(len(t_(d)))
def sine(f, d, ph=0):
    f = np.broadcast_to(np.asarray(f, float), (len(t_(d)),)) if np.ndim(f) else np.full(len(t_(d)), float(f))
    return np.sin(2 * np.pi * np.cumsum(f) / SR + ph)
def sweep(f0, f1, d, k=1.0): u = t_(d) / d; return f0 * (f1 / f0) ** (u ** k)
def verb(x, d=1.2, mix=.25, damp=3500):
    ir = noise(d) * np.exp(-t_(d) * 5.5 / d); ir = lp(ir, damp); ir /= np.abs(ir).sum() ** .5 * 6
    wet = np.convolve(x, ir)[:len(x) + int(d * SR * .6)]
    y = np.zeros(len(wet)); y[:len(x)] = x
    return y * (1 - mix) + wet * mix
def norm(x, peak=.9): return x / (np.abs(x).max() + 1e-9) * peak
def pad(x, d): y = np.zeros(max(len(x), int(d * SR))); y[:len(x)] = x; return y
def S(*xs):  # sum signals of different lengths (all start at 0)
    y = np.zeros(max(len(x) for x in xs))
    for x in xs: y[:len(x)] += x
    return y
def save(name, x, peak=.9):
    x = norm(np.asarray(x, float), peak); fade = min(len(x), 480); x[-fade:] *= np.linspace(1, 0, fade)
    sf.write(os.path.join(OUT, name + '.wav'), x.astype(np.float32), SR, subtype='PCM_16'); print(f'{name:10s} {len(x) / SR:.2f}s')

# --- UI ---------------------------------------------------------------------------------------
# mouse click: two tiny transients (press + release), bright and dry
c = pad(hp(noise(.012), 2500) * env(.012, .0005, curve=9), .09)
c[int(.045 * SR):int(.045 * SR) + int(.01 * SR)] += .55 * hp(noise(.01), 3500) * env(.01, .0005, curve=9)
c += .35 * sine(2600, .09) * env(.09, .001, curve=30)
save('click', c, .7)
# touch tap on glass: softer, lower, a little body
save('tap', pad(S(lp(noise(.03), 2200) * env(.03, .001, curve=10), .6 * sine(sweep(420, 180, .06), .06) * env(.06, .001, curve=14)), .12), .75)
# keypad key: tap + tiny pitched blip
save('key', pad(S(.7 * lp(noise(.02), 3000) * env(.02, .001, curve=10), .5 * sine(1250, .07) * env(.07, .001, curve=22)), .1), .7)
# keyboard typing: clack
save('type', pad(S(bp(noise(.035), 900, 5000) * env(.035, .0008, curve=12), .25 * sine(180, .03) * env(.03, .001, curve=18)), .06), .55)
# pop: pitch-drop bubble (chips, cards, checkmarks appearing)
save('pop', pad(sine(sweep(1100, 380, .09, .6), .09) * env(.09, .002, curve=6), .14), .75)
# tick: clock / counter
save('tick', pad(S(hp(noise(.006), 4000) * env(.006, .0003, curve=8), .4 * sine(3400, .03) * env(.03, .0005, curve=40)), .05), .5)
# toggle / checkbox
save('check', pad(S(sine(sweep(700, 1400, .05), .05) * env(.05, .001, curve=8), .3 * hp(noise(.01), 3000) * env(.01, .0005, curve=9)), .1), .6)

# --- movement ---------------------------------------------------------------------------------
def whoosh(d, lo, hi, up=True, grain=1.0):
    n = noise(d); u = t_(d) / d
    f = (lo * (hi / lo) ** u) if up else (hi * (lo / hi) ** u)
    y = np.zeros_like(n); blk = 480
    for i in range(0, len(n), blk):
        fc = f[min(i, len(f) - 1)]; y[i:i + blk] = bp(n[max(0, i - 2000):i + blk], max(60, fc * .6), min(20000, fc * 1.6))[-len(n[i:i + blk]):]
    shape = np.sin(np.pi * np.clip(u, 0, 1)) ** (1.4 if up else 1.1)
    return verb(y * shape, .5, .18)
save('whoosh', whoosh(.55, 300, 5000, True))                  # something flies in
save('swish', whoosh(.28, 900, 7000, True), .6)                # quick text / card move
save('whoosh-out', whoosh(.5, 5000, 400, False))               # something leaves
save('air', lp(noise(1.6), 900) * np.sin(np.pi * t_(1.6) / 1.6) ** 2, .35)   # soft camera drift
# riser into a reveal
d = 1.6; u = t_(d) / d
r = bp(noise(d), 800, 9000) * u ** 2.2 + .35 * np.sin(2 * np.pi * np.cumsum(sweep(180, 900, d, 1.6)) / SR) * u ** 2
save('riser', verb(r, .8, .2), .75)

# --- weight -----------------------------------------------------------------------------------
# impact: sub drop + transient + short room
d = 1.3
imp = 1.0 * sine(sweep(120, 38, d, .35), d) * env(d, .002, curve=3.2)
imp[:int(.08 * SR)] += .6 * lp(noise(.08), 1800) * env(.08, .001, curve=9)
save('impact', verb(imp, 1.0, .22, 2200), .95)
# punch: the logo's fist — a boxing-glove thump with a leather slap on top
d = .7
pu = .9 * sine(sweep(160, 45, d, .3), d) * env(d, .001, curve=6)
pu[:int(.05 * SR)] += .9 * bp(noise(.05), 400, 3200) * env(.05, .0005, curve=12)
pu[:int(.012 * SR)] += .6 * hp(noise(.012), 3000) * env(.012, .0003, curve=10)
save('punch', verb(pu, .7, .18, 3000), .95)
# thud: a card / device set down
th = pad(.8 * sine(sweep(140, 60, .25, .4), .25) * env(.25, .002, curve=9), .3); th[:int(.03 * SR)] += .3 * lp(noise(.03), 1200) * env(.03, .001, curve=10)
save('thud', verb(th, .4, .12), .7)
# stamp: rubber stamp / strike on the paper
st = pad(S(.8 * lp(noise(.06), 2500) * env(.06, .001, curve=10), .6 * sine(sweep(220, 90, .12), .12) * env(.12, .001, curve=10)), .3)
save('stamp', verb(st, .35, .15), .8)
# marker scribble (red pen across the timesheet)
d = .45; sc = bp(noise(d), 1500, 7000) * (0.5 + .5 * np.abs(np.sin(2 * np.pi * 7 * t_(d)))) * np.sin(np.pi * t_(d) / d) ** .5
save('marker', sc, .5)
# paper: a sheet sliding in
d = .5; save('paper', bp(noise(d), 600, 6000) * np.sin(np.pi * t_(d) / d) ** 1.5 * (0.6 + .4 * np.abs(noise(d)) ** .1), .45)

# --- success ----------------------------------------------------------------------------------
def bell(f, d, bright=1.0):
    t = t_(d); y = np.zeros_like(t)
    for k, (m, a) in enumerate([(1, 1), (2.0, .45 * bright), (3.01, .22 * bright), (4.2, .1 * bright)]):
        y += a * np.sin(2 * np.pi * f * m * t) * np.exp(-t * (3.2 + k * 2.4))
    return y * np.minimum(1, t / .003)
# ding: clocked in (two notes up, E6 -> B6)
dg = pad(bell(1318.5, 1.2), 1.5); dg[int(.09 * SR):] += .9 * bell(1975.5, 1.5 - .09)[:len(dg) - int(.09 * SR)]
save('ding', verb(dg, 1.2, .2), .7)
# dong: clocked out (two notes down)
dn = pad(bell(1975.5, 1.2), 1.5); dn[int(.09 * SR):] += .9 * bell(1318.5, 1.5 - .09)[:len(dn) - int(.09 * SR)]
save('dong', verb(dn, 1.2, .2), .7)
# chime: brand sting (E major arpeggio)
ch = np.zeros(int(2.6 * SR))
for i, f in enumerate([659.3, 830.6, 987.8, 1318.5]):
    o = int(i * .085 * SR); b = bell(f, 2.6 - i * .085, .8); ch[o:o + len(b)] += b[:len(ch) - o] * (1 - i * .12)
save('chime', verb(ch, 1.6, .3), .75)
# send: mail leaves (swish up + small bell)
se = whoosh(.45, 600, 8000, True); se = pad(se, .9); se[int(.3 * SR):int(.3 * SR) + int(.6 * SR)] += .35 * bell(2349, .6)
save('send', se, .7)
# counter: fast ticking for a number rolling up (1.2 s)
d = 1.2; co = np.zeros(int(d * SR))
for i in range(22):
    o = int(d * (1 - (1 - i / 22) ** 1.6) * SR); k = pad(S(hp(noise(.005), 3500) * env(.005, .0003, curve=8), .3 * sine(2800 + i * 40, .02) * env(.02, .0005, curve=40)), .02)
    co[o:o + len(k)] += k[:len(co) - o]
save('counter', co, .5)
