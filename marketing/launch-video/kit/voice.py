"""Voice first, with a human read: <dir>/script.txt -> <dir>/vo.wav + <dir>/timing.js
("@tag" at the start of a row names it, so a film can say line('meet') instead of a row number)

1. Chatterbox (Resemble AI, MIT) speaks each row several times with different seeds.
2. Every take is transcribed with whisper.cpp; the take that matches the script best (and
   doesn't run long or trail off) wins. Expressive TTS sometimes slurs or adds a breathy tail,
   so picking from takes is what makes it sound like a person rather than a machine.
3. Rows are joined with a breath (or a longer beat on "+"), and whisper word stamps on the final
   read give the film its per-word timing.

Run:  ~/.local/share/chatterbox/.venv/bin/python vo/voice.py [--takes 4] [--exaggeration .6] [--cfg .4]
"""
import argparse, difflib, json, os, re, subprocess, tempfile
import numpy as np, soundfile as sf

MODELS = os.path.expanduser('~/.local/share/whisper-models')
WHISPER = next((os.path.join(MODELS, m) for m in ('ggml-large-v3-turbo-q5_0.bin', 'ggml-base.en.bin')
                if os.path.exists(os.path.join(MODELS, m))))

ap = argparse.ArgumentParser()
ap.add_argument('dir', help='folder holding script.txt; vo.wav, takes/ and timing.js are written there')
ap.add_argument('--engine', choices=['chatterbox', 'kokoro'], default='chatterbox', help='kokoro: fast, clean, one voice per take seed')
ap.add_argument('--kvoice', default='af_heart', help='kokoro voice')
ap.add_argument('--speed', type=float, default=1.0, help='kokoro speed')
ap.add_argument('--takes', type=int, default=4)
ap.add_argument('--exaggeration', type=float, default=.6, help='0.5 neutral, higher = more animated')
ap.add_argument('--cfg', type=float, default=.3, help='lower = slower, more natural pacing')
ap.add_argument('--wps', type=float, default=2.85, help='target words per second (2.85 = ~170 wpm)')
ap.add_argument('--temperature', type=float, default=.8)
ap.add_argument('--voice', default=None, help='optional reference .wav to clone (only with consent)')
ap.add_argument('--lead', type=float, default=.6)
ap.add_argument('--breath', type=float, default=.35)
ap.add_argument('--beat', type=float, default=.8)
ap.add_argument('--tail', type=float, default=3.6)
ap.add_argument('--resume', action='store_true', help='reuse takes already in vo/takes')
a = ap.parse_args()
HERE = os.path.abspath(a.dir)

rows = []
for raw in open(os.path.join(HERE, 'script.txt')):
    raw = raw.rstrip('\n')
    if not raw.strip() or raw.startswith('#'): continue
    body = raw.lstrip('+').strip(); tag = None
    if body.startswith('@'): tag, _, body = body[1:].partition(' ')
    shown, _, spoken = body.partition(' | ')          # "on screen | how to say it"
    shown, spoken = shown.strip(), (spoken or shown).strip()
    assert len(shown.split()) == len(spoken.split()), f'word counts differ: {raw}'
    rows.append({'beat': raw.startswith('+'), 'text': shown, 'say': spoken, 'tag': tag or f'l{len(rows)}'})

if a.engine == 'chatterbox':
    import torch
    from chatterbox.tts import ChatterboxTTS
    tts = ChatterboxTTS.from_pretrained(device='mps' if torch.backends.mps.is_available() else 'cpu'); SR = tts.sr
    def speak(text, seed):
        torch.manual_seed(seed)
        kw = dict(exaggeration=a.exaggeration, cfg_weight=a.cfg, temperature=a.temperature)
        if a.voice: kw['audio_prompt_path'] = a.voice
        return tts.generate(text, **kw).squeeze(0).cpu().numpy().astype(np.float32)
else:
    from kokoro_onnx import Kokoro
    K = os.path.expanduser('~/.local/share/kokoro')
    tts = Kokoro(os.path.join(K, 'kokoro-v1.0.onnx'), os.path.join(K, 'voices-v1.0.bin')); SR = 24000
    def speak(text, seed):   # Kokoro is deterministic; takes vary the speed a touch instead
        audio, sr = tts.create(text, voice=a.kvoice, speed=a.speed * (1 + .03 * ((seed % 10) - 1)), lang='en-us'); assert sr == SR
        return np.asarray(audio, np.float32)
norm = lambda w: re.sub(r'[^a-z0-9]', '', w.lower())

WHISPER_WORDS = os.path.join(MODELS, 'ggml-base.en.bin')      # turbo transcribes better, base.en stamps words more accurately

def whisper_json(wav, words=True):
    with tempfile.TemporaryDirectory() as td:
        w16 = os.path.join(td, 'a.wav'); ffout = os.path.join(td, 'o')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', wav, '-ac', '1', '-ar', '16000', w16], check=True)
        cmd = ['whisper-cli', '-m', WHISPER_WORDS if words else WHISPER, '-f', w16, '-oj', '-of', ffout, '-np'] + (['-ml', '1', '-sow'] if words else [])
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return json.load(open(ffout + '.json'))['transcription']

def trim(x, thr=.01, pad=.05):
    idx = np.where(np.abs(x) > thr)[0]
    return x if not len(idx) else x[max(0, idx[0] - int(pad * SR)): min(len(x), idx[-1] + int(pad * 1.6 * SR))]

takes_dir = os.path.join(HERE, 'takes'); os.makedirs(takes_dir, exist_ok=True)
chosen = []
for k, R in enumerate(rows):
    best = None
    for n in range(a.takes):
        p = os.path.join(takes_dir, f'{k:02d}-{n}.wav')
        if a.resume and os.path.exists(p): wav = sf.read(p, dtype='float32')[0]          # reuse a finished take
        else: wav = trim(speak(R['say'], 1000 * k + n)); sf.write(p, wav, SR)
        heard = ' '.join(s['text'] for s in whisper_json(p, words=False))
        sim = difflib.SequenceMatcher(a=[norm(w) for w in R['say'].split()], b=[norm(w) for w in heard.split() if norm(w)]).ratio()
        dur = len(wav) / SR; wps = len(R['say'].split()) / dur
        score = sim - abs(wps - a.wps) * .12                                    # prefer a conversational pace
        print(f'  row {k} take {n}: sim {sim:.2f}  {dur:.2f}s  {wps:.2f} w/s  -> {score:.2f}   "{heard.strip()[:70]}"')
        if best is None or score > best[0]: best = (score, wav, n, p)
    print(f'row {k}: take {best[2]} ({best[0]:.2f})  {R["text"]}')
    chosen.append(best[1]); R['take'] = best[3]

out, t = [np.zeros(int(a.lead * SR), np.float32)], a.lead
for k, (R, wav) in enumerate(zip(rows, chosen)):
    if k: gap = a.beat if R['beat'] else a.breath; out.append(np.zeros(int(gap * SR), np.float32)); t += gap
    R['start'], R['end'] = round(t, 3), round(t + len(wav) / SR, 3); out.append(wav); t += len(wav) / SR
out.append(np.zeros(int(a.tail * SR), np.float32))
vo = np.concatenate(out); vo = vo / max(1e-6, np.abs(vo).max()) * .89
vo_path = os.path.join(HERE, 'vo.wav'); sf.write(vo_path, vo, SR, subtype='PCM_16'); total = len(vo) / SR

# word timing on the final read
# each row is stamped on its own take (short clips stamp precisely), then shifted to its place
heard = []
for L in rows:
    for s_ in whisper_json(L['take']):
        if re.search(r'[A-Za-z0-9]', s_['text']): heard.append((s_['text'].strip(), L['start'] + s_['offsets']['from'] / 1000, L['start'] + s_['offsets']['to'] / 1000))
words = []
for li, L in enumerate(rows):
    toks = L['say'].split(); shown = L['text'].split()
    near = [h for h in heard if L['start'] - .15 <= (h[1] + h[2]) / 2 <= L['end'] + .15]
    sm = difflib.SequenceMatcher(a=[norm(x) for x in toks], b=[norm(h[0]) for h in near], autojunk=False)
    times = [None] * len(toks)
    for blk in sm.get_matching_blocks():
        for j in range(blk.size): times[blk.a + j] = [near[blk.b + j][1], near[blk.b + j][2]]
    anchors = [(-1, L['start'])] + [(i, times[i][0]) for i in range(len(toks)) if times[i]] + [(len(toks), L['end'])]
    for (i0, t0), (i1, t1) in zip(anchors, anchors[1:]):
        gap = list(range(i0 + 1, i1))
        if not gap: continue
        s = times[i0][1] if i0 >= 0 else t0; wts = [len(toks[g]) + 2 for g in gap]; acc = s
        for g, wt in zip(gap, wts): d = (t1 - s) * wt / sum(wts); times[g] = [acc, acc + d]; acc += d
    for i, tok in enumerate(toks):
        s = min(max(times[i][0], L['start']), L['end'])
        words.append({'line': li, 'i': i, 'w': shown[i], 't': round(s, 3), 'e': round(max(s + .05, min(times[i][1], L['end'])), 3)})
with open(os.path.join(HERE, 'timing.js'), 'w') as f:
    f.write('// generated by vo/voice.py — do not edit by hand\n')
    f.write(f'const VO_TOTAL = {total:.3f};\n')
    f.write('const VO_LINES = ' + json.dumps([{k: L[k] for k in ('tag', 'text', 'start', 'end', 'beat')} for L in rows]) + ';\n')
    f.write('const VO_WORDS = ' + json.dumps(words) + ';\n')
for L in rows: print(f"{L['start']:6.2f}-{L['end']:6.2f}  {L['text']}")
print(f'vo.wav {total:.2f}s  {len(rows)} rows  {len(words)} words  whisper={os.path.basename(WHISPER)}')
