// Saves a static snapshot of the page after adding every cell of a notebook:
//   node tests/snapshot.js [base-url] [out.html] [notebook-index] [compiler] [strategy]
// Used by CI to show what the page looks like on the Nim it was built with.
const { chromium } = require("playwright");
const fs = require("fs");
const [base = "http://localhost:8000", out = "snapshot.html", nb = "1", compiler = "c", strategy = "hcr"] = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto(base);
  await page.waitForSelector("[data-add]");
  await page.click(`#notebooks button:nth-child(${nb})`);
  await page.click(`#compiler button[data-v=${compiler}]`);
  await page.click(`#strategy button[data-v=${strategy}]`);
  while (await page.$("[data-add]")) {
    const before = await page.$$eval(".cell.done", (e) => e.length);
    await page.click("[data-add]");
    await page.waitForFunction(() => !document.querySelector(".busy"), null, { timeout: 300000 });
    if ((await page.$$eval(".cell.done", (e) => e.length)) === before) break; // the cell failed: keep the log
  }
  await page.click("#log summary");
  const html = await page.evaluate(() => {
    document.querySelectorAll("script").forEach((s) => s.remove());
    return "<!doctype html>" + document.documentElement.outerHTML;
  });
  fs.writeFileSync(out, html);
  await browser.close();
})();
