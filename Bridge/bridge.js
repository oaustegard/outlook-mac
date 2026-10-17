// Injected at documentEnd into the main frame only. The app sets window.__omacKeymap just before
// this script. window.__omac.run(cmd) runs one native menu command and reports the result to
// Swift through the "omac" script message handler. searchFor and survey are called from Swift.
(function () {
  if (window.__omac) return;

  const keymap = window.__omacKeymap || {};
  // The configured server's origin, set by the app before this script runs. Commands act only on
  // this origin, so they do nothing on sign-in pages on other hosts, such as Duo.
  const serverOrigin = window.__OWA_ORIGIN__ || null;

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

  function viewName() {
    return Object.keys(routes).find(v => inView(v)) || 'other';
  }

  function routeFor(view) {
    const onOwa = location.pathname.indexOf('/owa') !== -1;
    return serverOrigin + routes[view][onOwa ? 0 : 1];
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

  // The first visible element matching the selector whose aria-label or text is `label`, or null.
  function visibleLabelled(selector, label) {
    const want = label.toLowerCase();
    return Array.from(document.querySelectorAll(selector)).find(el => {
      const text = (el.getAttribute('aria-label') || el.textContent || '').trim().toLowerCase();
      return text === want && el.getClientRects().length > 0;
    }) || null;
  }

  // Opens the context menu of the selected message, then clicks the item labelled `label`.
  // Outlook offers Pin and Mark as junk only there, not as keyboard shortcuts.
  async function clickMessageMenuItem(label) {
    const row = visibleMatch('[role="listbox"] [role="option"][aria-selected="true"]');
    if (!row) return false;
    const r = row.getBoundingClientRect();
    row.dispatchEvent(new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      button: 2,
      clientX: r.x + r.width / 2,
      clientY: r.y + r.height / 2
    }));
    const started = Date.now();
    while (Date.now() - started < 3000) {
      const item = visibleLabelled('[role="menuitem"], [role="menuitemcheckbox"]', label);
      if (item) {
        item.click();
        return true;
      }
      await delay(100);
    }
    pressKeys([{ key: 'Escape', code: 'Escape' }]);
    return false;
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
    // Other origins, such as the Duo page, have no mailbox to act on, so commands do nothing there.
    if (!serverOrigin || location.origin !== serverOrigin) return false;
    if (special[cmd]) return special[cmd]();

    const entry = keymap[cmd];
    if (!entry) return false;
    if (!(await ensureView(entry))) return false;

    if (entry.menuLabel) return clickMessageMenuItem(entry.menuLabel);
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

  // Structure of one element. Text content is never read.
  // aria-label is kept only on buttons, whose labels are interface text; elsewhere only its presence
  // is recorded. data-* attribute names are recorded, not their values. Elements wider than 150px
  // also get their computed layout styles, and any width set inline is recorded as written.
  function describe(el) {
    const rect = el.getBoundingClientRect();
    const isButton = el.tagName === 'BUTTON' || el.getAttribute('role') === 'button';
    const node = {
      tag: el.tagName.toLowerCase(),
      id: el.id || null,
      role: el.getAttribute('role'),
      label: isButton ? el.getAttribute('aria-label') : (el.hasAttribute('aria-label') ? '(present)' : null),
      data: Array.from(el.attributes).filter(a => a.name.startsWith('data-')).map(a => a.name),
      classes: Array.from(el.classList).slice(0, 3),
      rect: [Math.round(rect.x), Math.round(rect.y), Math.round(rect.width), Math.round(rect.height)],
      children: []
    };
    if (rect.width > 150) {
      const s = getComputedStyle(el);
      node.style = { width: s.width, minWidth: s.minWidth, maxWidth: s.maxWidth, flex: s.flex, position: s.position };
    }
    const inline = { width: el.style.width, minWidth: el.style.minWidth, maxWidth: el.style.maxWidth };
    const written = Object.entries(inline).filter(([, v]) => v);
    if (written.length > 0) node.inline = Object.fromEntries(written);
    return node;
  }

  // An element is kept only if it has a role, an aria-label or a data-* attribute.
  function isMeaningful(el) {
    return el.hasAttribute('role') || el.hasAttribute('aria-label') ||
      Array.from(el.attributes).some(a => a.name.startsWith('data-'));
  }

  // Walks body to depth 15 and stops after 6000 elements. An element that is not kept passes its
  // kept descendants up to its parent, so the tree keeps the meaningful structure.
  function surveyTree() {
    const budget = { left: 6000 };
    function walk(el, depth) {
      budget.left -= 1;
      const kept = [];
      if (depth < 15) {
        for (const child of el.children) {
          if (budget.left <= 0) break;
          kept.push(...walk(child, depth + 1));
        }
      }
      if (depth > 0 && !isMeaningful(el)) return kept;
      const node = describe(el);
      node.children = kept;
      return [node];
    }
    return walk(document.body, 0)[0];
  }

  window.__omac = {
    // Returns a plain boolean at once: evaluateJavaScript cannot convert a Promise, so the real
    // result goes back through the message handler when the command finishes.
    run: function (cmd) {
      runCommand(cmd)
        .catch(() => false)
        .then(ok => report(cmd, ok));
      return true;
    },

    // Puts the query in the page's search box and submits it with Enter.
    searchFor: function (query) {
      const input = document.querySelector('#topSearchInput input, input[aria-label*="Search" i]');
      if (!input) return false;
      input.focus();
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, query);
      input.dispatchEvent(new Event('input', { bubbles: true }));
      return pressKeys([{ key: 'Enter', code: 'Enter' }]);
    },

    // The page's structure as a JSON string, for the layout survey.
    survey: function () {
      const style = getComputedStyle(document.body);
      return JSON.stringify({
        view: viewName(),
        viewport: [window.innerWidth, window.innerHeight],
        font: { family: style.fontFamily, size: style.fontSize },
        tree: surveyTree()
      });
    }
  };
})();
