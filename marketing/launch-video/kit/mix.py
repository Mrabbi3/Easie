"""picture + voice + music + SFX cues -> the finished film.

  python kit/mix.py launch      (reads launch/out/launch-picture.mp4, launch/out/launch-cues.json,
                                 launch/vo/vo.wav, audio/music/launch.wav, audio/sfx/*.wav)

 * SFX: every cue(t, name, gain, pan, rate) from the film, placed sample-accurately
 * music ducks under the voice (sidechain) and fades out at the end
 * whole mix normalised to -14 LUFS / -1 dBTP (social feeds)
"""
import json, os, subprocess, sys
import numpy as np, soundfile as sf
from scipy.signal import resample_poly

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
name = sys.argv[1]; music_gain = float(sys.argv[2]) if len(sys.argv) > 2 else (.5 if name == 'launch' else .3)
D = os.path.join(ROOT, name); OUT = os.path.join(D, 'out'); SR = 48000
cues = json.load(open(os.path.join(OUT, f'{name}-cues.json')))
dur = cues['duration']; N = int(dur * SR)
sfx = np.zeros((N + SR * 4, 2)); cache = {}
for c in cues['cues']:
    key = (c['name'], round(c.get('rate', 1), 3))
    if key not in cache:
        x, sr = sf.read(os.path.join(ROOT, 'audio', 'sfx', c['name'] + '.wav'), dtype='float32'); assert sr == SR
        r = c.get('rate', 1)
        if abs(r - 1) > 1e-3: x = resample_poly(x, 1000, int(round(1000 * r)))
        cache[key] = x
    x = cache[key] * c.get('gain', 1); p = c.get('pan', 0)
    i = int(c['t'] * SR); n = min(len(x), len(sfx) - i)
    if n <= 0: continue
    sfx[i:i + n, 0] += x[:n] * np.sqrt((1 - p) / 2) * 1.414; sfx[i:i + n, 1] += x[:n] * np.sqrt((1 + p) / 2) * 1.414
sfx = sfx[:N]; peak = np.abs(sfx).max()
if peak > .98: sfx *= .98 / peak                   # only guard against clipping; levels come from the cues
sf.write(os.path.join(OUT, f'{name}-sfx.wav'), sfx.astype(np.float32), SR, subtype='PCM_24')
print(f'{len(cues["cues"])} cues -> {name}-sfx.wav  (peak {peak:.2f})')

vo = os.path.join(D, 'vo', 'vo.wav'); music = os.path.join(ROOT, 'audio', 'music', f'{name}.wav')
mix = os.path.join(OUT, f'{name}-mix.wav'); final = os.path.join(OUT, f'easie-{name}.mp4')
fade = dur - 2.0
fc = (f"[0:a]aresample={SR},pan=stereo|c0=c0|c1=c0,highpass=f=70,acompressor=threshold=0.1:ratio=2.5:attack=6:release=140,asplit=2[vo][key];"
      f"[1:a]aresample={SR},atrim=0:{dur},afade=t=out:st={fade}:d=2,volume={music_gain}[bed];"
      f"[bed][key]sidechaincompress=threshold=0.035:ratio=6:attack=20:release=500[ducked];"
      f"[2:a]aresample={SR},volume=0.85[fx];"
      f"[ducked][vo][fx]amix=inputs=3:weights=1 1.25 1:normalize=0,alimiter=limit=0.95,loudnorm=I=-14:TP=-1:LRA=11[mix]")
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', vo, '-i', music, '-i', os.path.join(OUT, f'{name}-sfx.wav'), '-filter_complex', fc,
                '-map', '[mix]', '-ar', str(SR), '-t', str(dur), mix], check=True)
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', os.path.join(OUT, f'{name}-picture.mp4'), '-i', mix, '-map', '0:v:0', '-map', '1:a:0',
                '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-shortest', '-movflags', '+faststart', final], check=True)
r = subprocess.run(['ffmpeg', '-hide_banner', '-i', final, '-af', 'ebur128=peak=true', '-f', 'null', '-'], capture_output=True, text=True).stderr
print('\n'.join(l for l in r.splitlines()[-12:] if 'I:' in l or 'Peak:' in l))
print('done:', final)
