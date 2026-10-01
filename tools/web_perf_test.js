// Web performance probe: opens the exported build with ?screen=stress&perf=1 in headless Chrome and prints
// the in-game PERF lines (script ms per frame) from the console.
// Usage: node tools/web_perf_test.js http://localhost:8060/index.html   (needs puppeteer-core@19)
const puppeteer = require('puppeteer-core');
(async () => {
  const url = (process.argv[2] || 'http://localhost:8060/index.html') + '?screen=stress&perf=1';
  const browser = await puppeteer.launch({
    executablePath: process.env.CHROME || 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    headless: 'new',
    args: ['--autoplay-policy=no-user-gesture-required', '--no-sandbox', '--enable-unsafe-swiftshader', '--use-gl=swiftshader', '--window-size=1280,720'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 720 });
  const lines = [];
  page.on('console', m => { const t = m.text(); if (t.includes('PERF')) lines.push(t); });
  await page.goto(url);
  await new Promise(r => setTimeout(r, 45000));
  console.log(lines.join('\n'));
  await browser.close();
})();
