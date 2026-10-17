// Drives the app's bridge against the live OWA page. Usage:
//   node probe.mjs run <cmd>        run window.__omac.run(cmd); prints the bridge report and the URL hash
//   node probe.mjs search <query>   run window.__omac.searchFor(query); prints the report and the URL hash
// Prints reports, hashes and element labels only. Never prints message text. Screenshots stay in shots/.
import { openContext, openMailbox, shotsDir } from './common.mjs';
import { join } from 'node:path';

const [mode, arg] = process.argv.slice(2);
const { browser, context } = await openContext({ headless: true });
const page = await openMailbox(context);
const before = await page.evaluate(() => location.hash);
if (mode === 'run') {
  await page.evaluate((c) => { window.__omacReports = []; window.__omac.run(c); }, arg);
} else if (mode === 'search') {
  await page.evaluate((q) => { window.__omacReports = []; window.__omac.searchFor(q); }, arg);
} else {
  throw new Error('usage: probe.mjs run|search <arg>');
}
await page.waitForTimeout(4000);
console.log(`report: ${JSON.stringify(await page.evaluate(() => window.__omacReports.at(-1)))}`);
console.log(`hash: ${before} -> ${await page.evaluate(() => location.hash)}`);
await page.screenshot({ path: join(shotsDir, `probe-${mode}.png`) });
await browser.close();
