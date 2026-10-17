// Opens a headed WebKit window. Oskar signs in with Duo here. The session is saved every few
// seconds, so closing the window at any point keeps the sign-in.
import { openContext, saveState, profileDir, target } from './common.mjs';

const { browser, context } = await openContext({ headless: false });
const page = await context.newPage();
await page.goto(target, { waitUntil: 'domcontentloaded' });
console.log(`profile: ${profileDir}`);
console.log('window open; sign in, then close the window');
const timer = setInterval(() => saveState(context).catch(() => {}), 5000);
await new Promise((resolveDone) => browser.on('disconnected', resolveDone));
clearInterval(timer);
console.log('closed');
