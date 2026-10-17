// Injected at documentEnd into the main frame only. The app sets window.__omacKeymap just before
// this script. window.__omac.run(cmd) runs one native menu command and reports the result to
// Swift through the "omac" script message handler.
(function () {
  if (window.__omac) return;

  const keymap = window.__omacKeymap || {};

  // On-premises OWA lives under /owa/ and routes by hash; outlook.com uses plain paths.
  const routes = {
    mail: ['/owa/#path=/mail', '/mail/inbox'],
    calendar: ['/owa/#path=/calendar', '/calendar'],
    people: ['/owa/#path=/people', '/people'],
    tasks: ['/owa/#path=/tasks', '/tasks']
  };

  function report(cmd, ok) {
    try {
      window.webkit.messageHandlers.omac.postMessage({ type: 'ran', cmd: cmd, ok: ok });
    } catch (e) {
      // Not running inside the app, so there is nowhere to report to.
    }
  }

  function delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function inView(view) {
    const marker = '/' + view;
    return location.hash.indexOf(marker) !== -1 || location.pathname.indexOf(marker) !== -1;
  }

  function routeFor(view) {
    const onOwa = location.pathname.indexOf('/owa') !== -1;
    return location.origin + routes[view][onOwa ? 0 : 1];
  }

  // Resolves true once the URL differs from `before`. Gives up after 5s.
  function waitForUrlChange(before) {
    return new Promise(resolve => {
      const started = Date.now();
      const timer = setInterval(() => {
        if (location.href !== before) {
          clearInterval(timer);
          resolve(true);
        } else if (Date.now() - started > 5000) {
          clearInterval(timer);
          resolve(false);
        }
      }, 50);
    });
  }

  // Resolves true once one of the selectors matches a visible element, or false after 8s.
  function waitForReady(selectors) {
    return new Promise(resolve => {
      const started = Date.now();
      const timer = setInterval(() => {
        const found = selectors.some(s => visibleMatch(s));
        if (found || Date.now() - started > 8000) {
          clearInterval(timer);
          resolve(found);
        }
      }, 100);
    });
  }

  // After a view switch, waits until the view is ready. The keymap entry's "ready" and "selector"
  // name what to wait for. A fixed 600ms wait is used only when the entry names neither.
  async function ensureView(entry) {
    const view = entry.view;
    if (!view || !routes[view] || inView(view)) return true;
    const before = location.href;
    location.assign(routeFor(view));
    if (!(await waitForUrlChange(before))) return false;
    const selectors = [entry.ready, entry.selector].filter(Boolean);
    if (selectors.length > 0) {
      await waitForReady(selectors);
    } else {
      await delay(600);
    }
    return true;
  }

  // The first visible element matching the selector, or null.
  function visibleMatch(selector) {
    return Array.from(document.querySelectorAll(selector)).find(el => el.getClientRects().length > 0) || null;
  }

  function pressKeys(keys) {
    const target = document.activeElement || document.body;
    for (const k of keys) {
      const init = {
        key: k.key,
        code: k.code,
        ctrlKey: !!k.ctrlKey,
        shiftKey: !!k.shiftKey,
        altKey: !!k.altKey,
        metaKey: !!k.metaKey,
        bubbles: true,
        cancelable: true
      };
      target.dispatchEvent(new KeyboardEvent('keydown', init));
      target.dispatchEvent(new KeyboardEvent('keyup', init));
    }
    return true;
  }

  function focusSearch() {
    const input = document.querySelector('#topSearchInput input, input[aria-label*="Search" i]');
    if (!input) return false;
    input.focus();
    input.select();
    return true;
  }

  // Commands that are not in the keymap.
  const special = {
    search: function () {
      return focusSearch() || pressKeys([{ key: '/', code: 'Slash' }]);
    },
    refresh: function () {
      location.reload();
      return true;
    }
  };

  async function runCommand(cmd) {
    if (special[cmd]) return special[cmd]();

    const entry = keymap[cmd];
    if (!entry) return false;
    if (!(await ensureView(entry))) return false;

    if (entry.selector) {
      const el = visibleMatch(entry.selector);
      if (el) {
        el.click();
        return true;
      }
    }
    if (entry.keys && entry.keys.length > 0) return pressKeys(entry.keys);
    // A view-only command succeeds once the view is open. A selector-only command needs its element.
    return !entry.selector;
  }

  window.__omac = {
    run: function (cmd) {
      return runCommand(cmd)
        .catch(() => false)
        .then(ok => {
          report(cmd, ok);
          return ok;
        });
    }
  };
})();
