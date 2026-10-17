// One pass: load OWA headless on the persistent profile, inject the current CSS, print layout
// metrics for the folder tree, message list and header, and save a screenshot. Prints numbers and
// element geometry only. It never reads message text.
import { openContext, readStyles, styleInitScript, shotsDir, target } from './common.mjs';
import { mkdirSync } from 'node:fs';
import { join } from 'node:path';

const name = process.argv[2] ?? 'pass';
const headed = process.argv.includes('--headed');
mkdirSync(shotsDir, { recursive: true });

const { browser, context } = await openContext({ headless: !headed });
const page = context.pages()[0] ?? (await context.newPage());
await context.addInitScript(styleInitScript(readStyles()));
await page.goto(target, { waitUntil: 'domcontentloaded' });

try {
  await page.waitForSelector('#O365_NavHeader', { timeout: 60_000 });
} catch {
  console.log('NOT SIGNED IN: #O365_NavHeader never appeared. Run `npm run login` and sign in.');
  await browser.close();
  process.exit(2);
}
await page.waitForTimeout(4000); // OWA positions panes with script after the shell appears

const metrics = await page.evaluate(() => {
  const r = (el) => { const b = el.getBoundingClientRect(); return { x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height) }; };
  const cs = (el, props) => Object.fromEntries(props.map((p) => [p, getComputedStyle(el)[p]]));
  const take = (sel, n, props) => [...document.querySelectorAll(sel)].slice(0, n).map((el) => ({ ...r(el), ...cs(el, props) }));
  const rowProps = ['fontSize', 'lineHeight', 'paddingTop', 'paddingBottom', 'backgroundColor', 'color'];
  const nav = document.getElementById('O365_NavHeader');
  const main = document.querySelector('[role="main"]');
  const primary = document.getElementById('primaryContainer');
  const selectedTree = document.querySelector('[role="tree"] [role="treeitem"][aria-selected="true"]');
  const selectedOpt = document.querySelector('[role="listbox"] [role="option"][aria-selected="true"]');
  return {
    viewport: { w: innerWidth, h: innerHeight, dpr: devicePixelRatio },
    navHeader: nav ? { ...r(nav), ...cs(nav, ['height', 'lineHeight', 'boxShadow', 'borderBottomWidth', 'position']) } : null,
    primaryContainer: primary ? r(primary) : null,
    main: main ? r(main) : null,
    regions: [...document.querySelectorAll('[role="region"]')].slice(0, 6).map(r),
    folderCount: document.querySelectorAll('[role="tree"] [role="treeitem"]').length,
    folderRows: take('[role="tree"] [role="treeitem"]', 6, rowProps),
    messageCount: document.querySelectorAll('[role="listbox"] [role="option"]').length,
    messageRows: take('[role="listbox"] [role="option"]', 6, rowProps),
    selectedFolder: selectedTree ? cs(selectedTree, ['backgroundColor', 'color', 'fontWeight']) : null,
    selectedMessage: selectedOpt ? cs(selectedOpt, ['backgroundColor', 'color']) : null,
  };
});

console.log(JSON.stringify(metrics, null, 1));
const file = join(shotsDir, `${name}.png`);
await page.screenshot({ path: file, fullPage: false });
console.log(`screenshot: ${file}`);
await browser.close();
