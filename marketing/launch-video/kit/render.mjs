// Frame renderer for kit/motion.js films.
//   node kit/render.mjs launch/launch.html                 full render -> <dir>/out/<name>-picture.mp4 + <name>-cues.json
//   node kit/render.mjs launch/launch.html --grid 40       QA sheet: 40 evenly spaced frames -> <dir>/out/<name>-grid.jpg
//   node kit/render.mjs launch/launch.html --at 3.2,7.5    stills at those seconds -> <dir>/out/still-<t>.jpg
//   options: --workers 3  --from S --to S (partial)  --out DIR
import puppeteer from 'puppeteer-core';
import {execFileSync} from 'node:child_process';
import {mkdirSync, rmSync, writeFileSync, readdirSync} from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const args = process.argv.slice(2), opt = {};
let file;
for (let i = 0; i < args.length; i++) if (args[i].startsWith('--')) opt[args[i].slice(2)] = args[++i]; else file = args[i];
if (!file) throw new Error('usage: node kit/render.mjs film.html [--grid N | --at t1,t2] [--workers 3] [--from s --to s]');
const name = path.basename(file, '.html'), out = path.resolve(opt.out || path.join(path.dirname(file), 'out'));
mkdirSync(out, {recursive: true});
const url = pathToFileURL(path.resolve(file)); url.searchParams.set('bare', '1');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const browser = await puppeteer.launch({executablePath: CHROME, headless: true,
  args: ['--allow-file-access-from-files', '--hide-scrollbars', '--force-color-profile=srgb', '--font-render-hinting=none', '--disable-gpu-vsync']});

async function open() {
  const page = await browser.newPage(), errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('requestfailed', r => { if (!/fonts\.g/.test(r.url())) errors.push('request failed ' + r.url()); });
  await page.setViewport({width: 1920, height: 1080, deviceScaleFactor: 1});
  await page.goto(url.href, {waitUntil: 'load', timeout: 120000});
  await page.waitForFunction('window.__ready === true || window.__error', {timeout: 180000});
  const err = await page.evaluate(() => window.__error);
  if (err || errors.length) throw new Error(err || errors.join('\n'));
  return {page, errors};
}
const shoot = async ({page, errors}, t, type = 'jpeg') => {
  await page.evaluate(t => window.__seek(t), t);
  if (errors.length) throw new Error(`t=${t}: ${errors.join('\n')}`);
  return page.screenshot({type, quality: type === 'jpeg' ? 93 : undefined, clip: {x: 0, y: 0, width: 1920, height: 1080}, optimizeForSpeed: true});
};
const ff = a => execFileSync('ffmpeg', ['-v', 'error', '-y', ...a], {stdio: 'inherit'});

try {
  const first = await open();
  const {duration, fps, cues} = await first.page.evaluate(() => window.__film);
  const N = Math.round(duration * fps);
  console.log(`${name}: ${duration.toFixed(2)} s, ${N} frames @ ${fps} fps, ${cues.length} sound cues`);
  if (opt.grid) {
    const n = +opt.grid, cols = 6, tmp = path.join(out, `.grid-${name}`); rmSync(tmp, {recursive: true, force: true}); mkdirSync(tmp);
    for (let i = 0; i < n; i++) { const t = (i + .5) * duration / n; writeFileSync(path.join(tmp, `${String(i).padStart(3, '0')}.jpg`), await shoot(first, t)); }
    ff(['-framerate', '1', '-i', path.join(tmp, '%03d.jpg'), '-vf', `scale=480:-2,pad=iw+4:ih+4:2:2:white,tile=${cols}x${Math.ceil(n / cols)}`, '-frames:v', '1', path.join(out, `${name}-grid.jpg`)]);
    rmSync(tmp, {recursive: true, force: true});
    console.log('grid:', path.join(out, `${name}-grid.jpg`), `(${(duration / n).toFixed(2)} s per tile, first at ${(duration / n / 2).toFixed(2)} s)`);
  } else if (opt.at) {
    for (const t of opt.at.split(',').map(Number)) { const f = path.join(out, `still-${name}-${t.toFixed(2)}.jpg`); writeFileSync(f, await shoot(first, t)); console.log(f); }
  } else {
    const from = Math.round((+opt.from || 0) * fps), to = Math.min(N, opt.to ? Math.round(+opt.to * fps) : N);
    const frames = path.join(out, `.${name}-frames`); rmSync(frames, {recursive: true, force: true}); mkdirSync(frames, {recursive: true});
    const nw = Math.max(1, +(opt.workers || 3)), workers = [first];
    for (let i = 1; i < nw; i++) workers.push(await open());
    const per = Math.ceil((to - from) / nw); let done = 0; const t0 = Date.now();
    await Promise.all(workers.map(async (w, k) => {
      for (let f = from + k * per; f < Math.min(to, from + (k + 1) * per); f++) {
        writeFileSync(path.join(frames, `${String(f - from).padStart(5, '0')}.jpg`), await shoot(w, f / fps));
        if (++done % 150 === 0) { const r = done / ((Date.now() - t0) / 1000); console.log(`  ${done}/${to - from}  ${r.toFixed(1)} fps  eta ${((to - from - done) / r / 60).toFixed(1)} min`); }
      }
    }));
    const suffix = opt.from || opt.to ? `-part` : '';
    const mp4 = path.join(out, `${name}-picture${suffix}.mp4`);
    ff(['-framerate', String(fps), '-i', path.join(frames, '%05d.jpg'), '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4]);
    writeFileSync(path.join(out, `${name}-cues.json`), JSON.stringify({duration, fps, cues}, null, 1));
    rmSync(frames, {recursive: true, force: true});
    console.log('picture:', mp4, `(${readdirSync(out).length} files in out/)`);
  }
} finally { await browser.close(); }
