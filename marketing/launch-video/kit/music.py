"""Synthesised music beds, composed against the voice timing (no samples, no licences).

  launch       120 BPM. Tense filtered intro (A minor) under the problem, riser, the DROP lands
               exactly on --drop (the logo punch), bright C-G-Am-F groove, a breakdown for the price
               (--brk), a last hit on the end card (--hit), then a tail.
  walkthrough  92 BPM. Warm, unobtrusive: soft kick/rim/shaker, electric-piano chords, round bass,
               a quiet pluck arpeggio. Evolves every 8 bars so three minutes don't loop audibly.

The beat grid is anchored so that bar lines fall on the anchor time (drop / first step), which is
how cuts in the films can land on the beat.

    python kit/music.py launch --dur 38 --drop 9.6 --brk 27.0 --hit 33.2 --out audio/music/launch.wav
    python kit/music.py walkthrough --dur 166 --anchor 9.4 --out audio/music/walkthrough.wav
"""
import argparse, os
import numpy as np, soundfile as sf
from scipy.signal import butter, sosfilt, fftconvolve

SR = 48000
rng = np.random.default_rng(11)
ap = argparse.ArgumentParser()
ap.add_argument('kind', choices=['launch', 'walkthrough'])
ap.add_argument('--dur', type=float, required=True)
ap.add_argument('--drop', type=float, default=8.0)
ap.add_argument('--brk', type=float, default=None)
ap.add_argument('--hit', type=float, default=None)
ap.add_argument('--anchor', type=float, default=0.0)
ap.add_argument('--out', required=True)
a = ap.parse_args()

N = int(a.dur * SR)
def z(): return np.zeros(N)
def lp(x, f, o=2): return sosfilt(butter(o, min(f, SR / 2 - 100), 'lowpass', fs=SR, output='sos'), x)
def hp(x, f, o=2): return sosfilt(butter(o, f, 'highpass', fs=SR, output='sos'), x)
def bp(x, lo, hi, o=2): return sosfilt(butter(o, [lo, hi], 'bandpass', fs=SR, output='sos'), x)
def midi(n): return 440 * 2 ** ((n - 69) / 12)
def put(buf, t, x, g=1.0):
    i = int(round(t * SR))
    if i >= len(buf) or i + len(x) <= 0: return
    s = max(0, -i); x = x[s:]; i = max(0, i); n = min(len(x), len(buf) - i); buf[i:i + n] += g * x[:n]
def adsr(d, a=.01, dcy=.1, s=.7, r=.2):
    n = int(d * SR); t = np.arange(n) / SR; e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / max(dcy, 1e-3)))
    rel = np.exp(-np.arange(int(r * SR)) / (r * SR / 5)) * e[-1] if n else np.zeros(0)
    return np.concatenate([e, rel])
def saw(f, n, ph=0.0):
    p = (np.arange(n) * f / SR + ph) % 1.0; return 2 * p - 1
def supersaw(f, d, voices=5, det=.012):
    n = int(d * SR); y = np.zeros(n)
    for v in range(voices):
        k = (v - (voices - 1) / 2) / ((voices - 1) / 2 or 1); y += saw(f * (1 + det * k), n, rng.random())
    return y / voices
def sine(f, d, ph=0): return np.sin(2 * np.pi * f * np.arange(int(d * SR)) / SR + ph)
def reverb(x, d=2.2, damp=4000, mix=.3):
    t = np.arange(int(d * SR)) / SR; irL = lp(rng.standard_normal(len(t)) * np.exp(-t * 6.9 / d), damp); irL /= np.sqrt((irL ** 2).sum()) * 3
    return x * (1 - mix) + fftconvolve(x, irL)[:len(x)] * mix * 2.2
def delay(x, dt, fb=.35, mix=.25, n=5):
    y = x.copy(); s = int(dt * SR)
    for k in range(1, n + 1): y[s * k:] += x[:len(x) - s * k] * (fb ** k) * mix / fb if s * k < len(x) else 0
    return y

# drums
def kick(g=1.0):
    d = .45; t = np.arange(int(d * SR)) / SR; f = 45 + 110 * np.exp(-t * 28)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7.5); y[:240] += hp(rng.standard_normal(240), 2000) * .4 * np.linspace(1, 0, 240)
    return np.tanh(y * 1.6) * g
def hat(open_=False):
    d = .25 if open_ else .05; t = np.arange(int(d * SR)) / SR
    return hp(rng.standard_normal(len(t)), 7500) * np.exp(-t * (14 if open_ else 70))
def clap():
    d = .35; t = np.arange(int(d * SR)) / SR; y = bp(rng.standard_normal(len(t)), 900, 5000) * np.exp(-t * 16)
    for o in (0, .011, .022): y[int(o * SR):] += bp(rng.standard_normal(len(t) - int(o * SR)), 1000, 4000) * np.exp(-t[:len(t) - int(o * SR)] * 60) * .6
    return reverb(np.pad(y, (0, SR // 2)), 1.0, 5000, .25)
def rim():
    d = .08; t = np.arange(int(d * SR)) / SR; return (bp(rng.standard_normal(len(t)), 1500, 6000) * .5 + np.sin(2 * np.pi * 1700 * t) * .5) * np.exp(-t * 55)
def shaker():
    d = .07; t = np.arange(int(d * SR)) / SR; return hp(rng.standard_normal(len(t)), 6000) * np.sin(np.pi * t / d) ** 2
def epiano(f, d):
    t = np.arange(int((d + .8) * SR)) / SR; mod = np.sin(2 * np.pi * f * 1.0 * t) * 1.2 * np.exp(-t * 3)
    y = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 1.6) + .25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 4)
    return y * np.minimum(1, t / .004)
def pluck(f, d=.5):
    t = np.arange(int(d * SR)) / SR; y = (saw(f, len(t)) * .5 + np.sin(2 * np.pi * f * t)) * np.exp(-t * 9); return lp(y, 3500)

def pump(beat, grid0, depth=.6, shape=5):   # sidechain envelope keyed to every beat from grid0
    t = np.arange(N) / SR; ph = ((t - grid0) / beat) % 1.0; return 1 - depth * np.exp(-ph * shape) * (t >= grid0)

if a.kind == 'launch':
    bpm = 120
    if a.hit:                                          # fit the tempo so drop -> hit is a whole number of bars
        nbar = max(1, round((a.hit - a.drop) / 2.0)); bpm = 240 * nbar / (a.hit - a.drop)
    beat = 60 / bpm; bar = 4 * beat
    g0 = a.drop - np.ceil(a.drop / bar) * bar        # grid origin so a bar line lands on the drop
    brk = a.brk if a.brk else a.dur; hit = a.hit if a.hit else a.dur
    brk = a.drop + np.floor((brk - a.drop) / bar + .25) * bar   # quantised to bars (at or just before)
    hit = a.drop + round((hit - a.drop) / bar) * bar
    drums, bass, pad, fx = z(), z(), z(), z()
    prog_dark = [57, 53, 57, 55]                     # A F A G (roots, intro)
    prog = [60, 55, 57, 53]                          # C G Am F
    chord = {60: [60, 64, 67, 71], 55: [55, 59, 62, 67], 57: [57, 60, 64, 67], 53: [53, 57, 60, 64]}
    chord_dark = {57: [57, 60, 64], 53: [53, 57, 60], 55: [55, 59, 62]}
    nb = int((a.dur - g0) / bar) + 2
    for b in range(nb):
        tb = g0 + b * bar
        if tb + bar < 0 or tb > a.dur: continue
        intro, main = tb < a.drop - 1e-6, a.drop - 1e-6 <= tb < brk - 1e-6
        brkp = brk - 1e-6 <= tb < hit - 1e-6
        tail = tb >= hit - 1e-6
        if intro:
            r = prog_dark[b % 4]
            for n in chord_dark[r]: put(pad, tb, supersaw(midi(n), bar + .1, 3, .007) * adsr(bar + .1, .4, 1, .8, .3)[:int((bar + .1) * SR)], .22)
            for k in range(8): put(drums, tb + k * beat / 2, hat(), .12 if k % 2 else .06)
            if a.drop - tb <= 2 * bar:                              # build: kicks + claps accelerate
                for k in range(4): put(drums, tb + k * beat, kick(.6), 1)
                for k in range(8 if a.drop - tb <= bar else 4): put(drums, tb + k * beat * (0.5 if a.drop - tb <= bar else 1), clap(), .18)
        elif main or tail:
            r = prog[b % 4]
            for n in chord[r]: put(pad, tb, supersaw(midi(n), bar + .05, 5, .012) * adsr(bar + .05, .02, .6, .75, .25)[:int((bar + .05) * SR)], .2)
            for k in range(4): put(drums, tb + k * beat, kick(), 1)
            for k in (1, 3): put(drums, tb + k * beat, clap(), .5)
            for k in range(8): put(drums, tb + k * beat / 2, hat(k % 2 == 1), .18 if k % 2 else .1)
            for k in range(8):                                           # offbeat bass eighths
                f = midi(r - 24); d = beat / 2 * .92
                y = (np.sin(2 * np.pi * f * np.arange(int(d * SR)) / SR) + .35 * saw(f, int(d * SR))) * adsr(d, .005, .12, .6, .03)[:int(d * SR)]
                put(bass, tb + k * beat / 2, lp(y, 900), .55 if k % 2 else .3)
            if tail:                                                      # hold the tonic to the end
                hold = a.dur - (tb + bar) + .5
                if hold > 0:
                    for n in chord[60]: put(pad, tb + bar, supersaw(midi(n), hold, 5, .01) * adsr(hold, .05, 2.5, .6, .1)[:int(hold * SR)], .2)
                    put(bass, tb + bar, lp(np.sin(2 * np.pi * midi(36) * np.arange(int(hold * SR)) / SR) * np.exp(-np.arange(int(hold * SR)) / SR * 1.2), 400), .5)
                break
        elif brkp:                                                     # breakdown: pad + ticking only
            r = prog[b % 4]
            for n in chord[r]: put(pad, tb, supersaw(midi(n + 12), bar + .05, 5, .01) * adsr(bar + .05, .3, 1, .8, .3)[:int((bar + .05) * SR)], .12)
            for k in range(16): put(drums, tb + k * beat / 4, hat(), .05 if k % 4 else .1)
    # riser into the drop, the drop hit, and the end hit
    rd = 2 * bar; t = np.arange(int(rd * SR)) / SR; u = t / rd
    put(fx, a.drop - rd, bp(rng.standard_normal(len(t)), 700, 9000) * u ** 2.5 * .5)
    crash = hp(rng.standard_normal(int(2.5 * SR)), 5000) * np.exp(-np.arange(int(2.5 * SR)) / SR * 2.2)
    for tt in [a.drop] + ([hit] if a.brk else []):
        put(fx, tt, crash, .35); put(drums, tt, kick(1.2), 1)
        sub = np.sin(2 * np.pi * np.cumsum(38 + 60 * np.exp(-np.arange(int(1.4 * SR)) / SR * 6)) / SR) * np.exp(-np.arange(int(1.4 * SR)) / SR * 2.4); put(fx, tt, sub, .8)
    # the intro pad is filtered dark, opening up into the drop
    tt = np.arange(N) / SR; cut = np.where(tt < a.drop, 500 + 2500 * np.clip((tt - (a.drop - 2 * bar)) / (2 * bar), 0, 1) ** 2, 4200)
    padf = np.zeros(N); blk = 2048
    for i in range(0, N, blk): padf[i:i + blk] = lp(pad[max(0, i - 4096):i + blk], cut[i])[-len(pad[i:i + blk]):]
    sc = pump(beat, a.drop, .55) ; sc[tt < a.drop] = 1
    mixd = reverb(padf * sc, 2.4, 5000, .28) + bass * sc + drums + reverb(fx, 1.8, 6000, .2)
    fade_from = a.dur - 2.5
else:
    bpm = 92; beat = 60 / bpm; bar = 4 * beat
    g0 = a.anchor - np.ceil(a.anchor / bar) * bar
    drums, keys, bass, arp = z(), z(), z(), z()
    prog = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]   # Fmaj7 Em7 Dm7 Cmaj7
    roots = [41, 40, 38, 36]
    nb = int((a.dur - g0) / bar) + 2
    for b in range(nb):
        tb = g0 + b * bar; sec = (b // 8) % 4; c = prog[b % 4]
        if tb + bar < 0 or tb > a.dur: continue
        for k, n in enumerate(c): put(keys, tb + k * .012, epiano(midi(n), bar), .16)
        if tb >= 0:
            put(keys, tb + 2.5 * beat, epiano(midi(c[1] + 12), beat), .06)
            for k in (0, 2): put(drums, tb + k * beat, kick(.7), .8)
            if sec != 0 or b > 3: put(drums, tb + 2.75 * beat, kick(.5), .4)
            for k in (1, 3): put(drums, tb + k * beat, rim(), .22)
            for k in range(16): put(drums, tb + k * beat / 4, shaker(), (.06 if k % 2 else .1) * (1 if sec else .6))
            for k, (o, dd) in enumerate([(0, 1.5), (1.5, .5), (2, 1.5), (3.5, .5)]):
                f = midi(roots[b % 4] - (0 if k % 2 == 0 else -12 + 12)); d = dd * beat * .95
                y = np.sin(2 * np.pi * f * np.arange(int(d * SR)) / SR) * adsr(d, .01, .3, .7, .05)[:int(d * SR)]
                put(bass, tb + o * beat, lp(y, 600), .5)
            if sec in (1, 3):
                for k in range(8): put(arp, tb + k * beat / 2, pluck(midi(c[(k * 3) % 4] + 12), .4), .08)
    sc = pump(beat, g0, .25, 6)
    mixd = reverb(keys * sc, 2.0, 3500, .3) + bass * sc + drums * .9 + reverb(delay(arp, beat * .75, .4, .5), 2.0, 5000, .35)
    fade_from = a.dur - 4

t = np.arange(N) / SR
mixd *= np.clip(t / .8, 0, 1) * np.clip((a.dur - t) / (a.dur - fade_from), 0, 1)
stereo = np.stack([mixd, np.concatenate([mixd[int(.012 * SR):], np.zeros(int(.012 * SR))])], 1)   # a touch of width
stereo = np.tanh(stereo / (np.abs(stereo).max() + 1e-9) * 1.3) * .85
os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
sf.write(a.out, stereo.astype(np.float32), SR, subtype='PCM_16')
print(f'{a.kind}: {a.dur:.1f}s  {bpm:.2f} bpm  grid origin {g0:.3f}s  -> {a.out}')
