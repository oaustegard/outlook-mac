// Shared setup for the live harness. Runs WebKit, the engine WKWebView uses on macOS.
// Playwright's persistent WebKit context fails on this build ("Browser started with no default
// context"), so the session lives in a storage-state file in the profile folder instead. Cookies
// and localStorage survive between runs. Profile and screenshots stay local, outside git.
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
export const target = 'https://webmail.meso-scale.com/';
export const viewport = { width: 1440, height: 900 };

// Same order the app uses: base.css, then owa.css, then theme.css. Re-read on every call.
export function readStyles() {
  return [
    ['omac-base', readFileSync(join(repo, 'Resources', 'base.css'), 'utf8')],
    ['omac-owa', readFileSync(join(repo, 'Resources', 'owa.css'), 'utf8')],
    ['omac-theme', readFileSync(join(repo, 'Bridge', 'theme.css'), 'utf8')],
  ];
}

// Injected at document start. Attaches each stylesheet as a <style> element and keeps them
// attached, the way InjectedScript.swift does, so OWA's own document replacement cannot drop them.
export function styleInitScript(styles) {
  const payload = JSON.stringify(styles);
  return `(() => {
    const styles = ${payload};
    const attach = () => {
      for (const [id, css] of styles) {
        let el = document.getElementById(id);
        if (!el) { el = document.createElement('style'); el.id = id; }
        if (el.textContent !== css) el.textContent = css;
        const parent = document.head || document.documentElement;
        if (el.parentNode !== parent) parent.appendChild(el);
      }
    };
    attach();
    new MutationObserver(attach).observe(document, { childList: true, subtree: true });
  })();`;
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

export async function saveState(context) {
  await context.storageState({ path: stateFile });
}
