// For each destructive command, runs the bridge with every write blocked and lists the write action it produced.
// Nothing reaches the server, so no mail is deleted, archived or moved.
import { openContext, openMailbox, origin } from './common.mjs';

const cmds = process.argv.slice(2);
for (const cmd of cmds) {
  const { browser, context } = await openContext({ headless: true });
  const page = await openMailbox(context);
  const writes = new Set();
  let armed = false;
  await context.route('**/*', (route) => {
    const req = route.request();
    if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method()) && req.url().startsWith(origin)) {
      if (armed) writes.add(req.headers()['x-owa-actionname'] || req.headers()['action'] || '?');
      return route.abort();
    }
    return route.continue();
  });
  await page.evaluate(() => document.querySelector('[role="listbox"] [role="option"]').click());
  await page.waitForTimeout(1200);
  armed = true;
  await page.evaluate((c) => { window.__omacReports = []; window.__omac.run(c); }, cmd);
  await page.waitForTimeout(4000);
  const report = await page.evaluate(() => window.__omacReports.at(-1));
  console.log(`${cmd}: report ok=${report?.ok} writes=${[...writes].filter((w) => !/^(Get|Subscribe|Browse)/.test(w)).join(', ') || 'none'}`);
  await browser.close();
}
