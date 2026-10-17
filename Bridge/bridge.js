// Injected at documentEnd into the main frame only. Exposes window.__omac.run(cmd)
// for the native menu commands and reports each run to Swift through the "omac"
// script message handler.
(function () {
  if (window.__omac) return;

  function report(cmd, ok) {
    try {
      window.webkit.messageHandlers.omac.postMessage({ type: 'ran', cmd: cmd, ok: ok });
    } catch (e) {
      // Not running inside the app, so there is nowhere to report to.
    }
  }

  function keyPress(key, code) {
    const init = { key: key, code: code, bubbles: true, cancelable: true };
    document.body.dispatchEvent(new KeyboardEvent('keydown', init));
    document.body.dispatchEvent(new KeyboardEvent('keyup', init));
    return true;
  }

  function focusSearch() {
    const input = document.querySelector('#topSearchInput input, input[aria-label*="Search" i]');
    if (!input) return false;
    input.focus();
    input.select();
    return true;
  }

  // On-premises OWA lives under /owa/ and routes by hash; outlook.com uses plain paths.
  function go(owaTarget, plainTarget) {
    const onOwa = location.pathname.indexOf('/owa') !== -1;
    location.assign(location.origin + (onOwa ? owaTarget : plainTarget));
    return true;
  }

  const commands = {
    newMail: function () {
      return keyPress('n', 'KeyN');
    },
    search: function () {
      return focusSearch() || keyPress('/', 'Slash');
    },
    gotoInbox: function () {
      return go('/owa/#path=/mail', '/mail/inbox');
    },
    gotoCalendar: function () {
      return go('/owa/#path=/calendar', '/calendar');
    },
    gotoPeople: function () {
      return go('/owa/#path=/people', '/people');
    },
    refresh: function () {
      location.reload();
      return true;
    }
  };

  window.__omac = {
    run: function (cmd) {
      let ok = false;
      try {
        const fn = commands[cmd];
        ok = fn ? fn() === true : false;
      } catch (e) {
        ok = false;
      }
      report(cmd, ok);
      return ok;
    }
  };
})();
