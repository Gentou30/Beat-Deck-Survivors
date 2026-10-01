// Web audio regression test: loads the page in headless Chrome, starts the game, and measures
// the actual audio output level (RMS) of the Web Audio graph. A working build shows non-zero
// values on the AudioWorkletNode analyser (second number); silence = [0,0].
// Usage: npm i puppeteer-core@19 (Node 16+), then: node tools/web_audio_test.js <url>
// (Serve build/web first, e.g. python -m http.server 8060 --directory build/web.)
const puppeteer = require('puppeteer-core');
(async () => {
  const url = process.argv[2] || 'http://localhost:8070/index.html';
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME || 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    headless: 'new',
    args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=swiftshader', '--window-size=1280,720'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });
  const logs = [];
  page.on('console', m => logs.push(m.text()));
  page.on('pageerror', e => logs.push('PAGEERR ' + e.message));

  await page.evaluateOnNewDocument(() => {
    window.__log = []; window.__ans = [];
    const oc = AudioNode.prototype.connect;
    AudioNode.prototype.connect = function (dest) {
      try { if (dest && dest.constructor && dest.constructor.name === 'AudioDestinationNode' && !this.__t) { this.__t = true; const an = this.context.createAnalyser(); an.fftSize = 1024; oc.call(this, an); window.__ans.push(an); window.__log.push('tap ' + this.constructor.name); } } catch (e) {}
      return oc.apply(this, arguments);
    };
    window.__rmsAll = () => window.__ans.map(a => { const b = new Float32Array(1024); a.getFloatTimeDomainData(b); let s = 0; for (let i = 0; i < 1024; i++) s += b[i] * b[i]; return +Math.sqrt(s / 1024).toFixed(4); });
  });
  await page.goto(url);
  await new Promise(r => setTimeout(r, 6000));
  const raf = await page.evaluate(async () => { let n = 0; const t0 = performance.now(); await new Promise(r => { function f() { n++; if (performance.now() - t0 > 1000) r(); else requestAnimationFrame(f); } requestAnimationFrame(f); setTimeout(r, 2500); }); return { n, hidden: document.hidden }; });
  console.log('raf', JSON.stringify(raf));
  await page.mouse.click(640, 360);
  await new Promise(r => setTimeout(r, 1500));
  const res = [];
  for (let i = 0; i < 12; i++) {
    res.push(JSON.stringify(await page.evaluate(() => window.__rmsAll ? window.__rmsAll() : 'no-hook')));
    await new Promise(r => setTimeout(r, 300));
  }
  console.log('rms', res.join(' '));
  console.log('ctx', JSON.stringify(await page.evaluate(() => ({ ctx: (window.__ctxs || []).map(c => c.state + '/' + c.sampleRate), log: window.__log }))));
  await page.screenshot({ path: (process.env.TEMP || '.') + '/web_audio_shot.png' });
  console.log(logs.filter(l => /audio|Audio|sample|error|Error|ERROR/.test(l)).slice(0, 15).join('\n'));
  await browser.close();
})().catch(e => { console.error('FAIL', e); process.exit(1); });
