// Shared setup for the live harness. Runs WebKit, the engine WKWebView uses on macOS.
// The saved OWA session lives in a storage-state file in the profile folder, so Duo is needed only
// once. Profile and screenshots stay local, outside git.
import { webkit } from 'playwright';
import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
export const repo = resolve(here, '..', '..');
export const shotsDir = join(here, 'shots');
export const profileDir = join(homedir(), 'Library', 'Application Support', 'omac-live');
export const stateFile = join(profileDir, 'storage-state.json');
// Set OWA_URL to your server's mailbox URL, e.g. OWA_URL=https://mail.example.com/owa/
export const target = process.env.OWA_URL ?? 'https://mail.example.com/owa/';
export const origin = new URL(target).origin;
export const viewport = { width: 1440, height: 900 };

// The app's bridge, built the way WebViewStore.loadBridgeScript builds it: the keymap as a JS
// object literal, then bridge.js. Injected at document end in the main frame.
export function bridgeSource() {
  const keymap = readFileSync(join(repo, 'Bridge', 'keymap.json'), 'utf8');
  const bridge = readFileSync(join(repo, 'Bridge', 'bridge.js'), 'utf8');
  return `window.__omacKeymap = ${keymap};\n${bridge}`;
}

export async function openContext({ headless }) {
  mkdirSync(profileDir, { recursive: true });
  const browser = await webkit.launch({ headless });
  const context = await browser.newContext({
    viewport,
    deviceScaleFactor: 2,
    colorScheme: 'light',
    storageState: existsSync(stateFile) ? stateFile : undefined,
  });
  return { browser, context };
}

// Opens the mailbox the way the app does: origin set before any script, bridge after the document.
// Reports from the bridge are collected on window.__omacReports instead of the app's message handler.
export async function openMailbox(context) {
  await context.addInitScript((o) => { window.__OWA_ORIGIN__ = o; }, origin);
  const page = await context.newPage();
  await page.goto(target, { waitUntil: 'domcontentloaded' });
  await page.addInitScript(() => {
    window.__omacReports = [];
    window.webkit = { messageHandlers: { omac: { postMessage: (m) => window.__omacReports.push(m) } } };
  }).catch(() => {});
  await page.evaluate(() => {
    window.webkit = { messageHandlers: { omac: { postMessage: (m) => window.__omacReports.push(m) } } };
    window.__omacReports = [];
  });
  await page.addScriptTag({ content: bridgeSource() });
  await page.waitForSelector('#O365_NavHeader', { timeout: 60_000 });
  await page.waitForTimeout(4000);
  return page;
}

export async function saveState(context) {
  await context.storageState({ path: stateFile });
}
