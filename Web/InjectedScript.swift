import Foundation

/// Builds JavaScript for injection. Values go in as JSON string literals, so quotes and
/// newlines in them cannot break the script.
enum InjectedScript {
    static func literal(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// Creates or updates a <style> element with the given id. Safe to run more than once, and
    /// safe at document start: before <head> exists the element goes on <html>. With `first`, a
    /// new element goes before the page's other style elements, so later rules win. If the page
    /// removes the element (OWA re-renders its shell) or replaces the whole document
    /// (document.open/write keeps the window but drops the old DOM and its observers), a shared
    /// watcher puts every stylesheet back. A diagnostic runs 3s after load and after each
    /// re-attach, posting "css: diag {json}" to the bridge log.
    static func style(id: String, css: String, first: Bool = false) -> String {
        // The bridge's message handler is "omac" (CommandDispatcher.messageHandlerName).
        """
        (function () {
          var id = \(literal(id));
          var css = \(literal(css));
          var first = \(first);
          var S = window.__omacCss = window.__omacCss || { sheets: {}, doc: null, observer: null };
          S.sheets[id] = { css: css, first: first };
          function post(msg) {
            try {
              var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.omac;
              if (h) { h.postMessage(msg); }
            } catch (e) {}
          }
          if (!S.report) {
            S.report = function (what, sid) {
              post('css: ' + what + ' #' + sid + ' (' + S.sheets[sid].css.length + ' chars) host=' + location.host + ' top=' + (window === window.top));
            };
            S.attach = function (style, atFirst) {
              var parent = document.head || document.documentElement;
              if (!parent) { return false; }
              if (atFirst && parent.firstChild) {
                parent.insertBefore(style, parent.firstChild);
              } else {
                parent.appendChild(style);
              }
              return true;
            };
            S.diag = function (reason) {
              try {
                var out = { reason: reason, readyState: document.readyState, host: location.host,
                  top: window === window.top, styles: {}, body: null, counts: {} };
                Object.keys(S.sheets).forEach(function (sid) {
                  var el = document.getElementById(sid);
                  var rules = null;
                  try { rules = el && el.sheet ? el.sheet.cssRules.length : null; } catch (e) { rules = 'err:' + e.name; }
                  out.styles[sid] = el ? { connected: el.isConnected, parent: el.parentNode ? el.parentNode.nodeName : null,
                    textLen: (el.textContent || '').length, rules: rules, disabled: el.sheet ? el.sheet.disabled : null } : 'missing';
                });
                if (document.body) {
                  var cs = getComputedStyle(document.body);
                  out.body = { fontFamily: cs.fontFamily, fontSize: cs.fontSize };
                }
                ['[role=main]', '[role=main] > [role=region]', '[role=tree]', '[role=listbox]',
                 '[role=document]', '[role=option]', '[role=treeitem]', '[role=toolbar]'].forEach(function (sel) {
                  try { out.counts[sel] = document.querySelectorAll(sel).length; } catch (e) { out.counts[sel] = 'err'; }
                });
                try { out.hasSupport = CSS.supports('selector(:has(a))'); } catch (e) { out.hasSupport = 'err'; }
                out.styleSheets = document.styleSheets.length;
                out.iframes = document.querySelectorAll('iframe').length;
                post('css: diag ' + JSON.stringify(out));
              } catch (e) { post('css: diag failed ' + e); }
            };
            // Puts back any sheet missing from the current document. Re-observes when the
            // document object itself has been replaced.
            S.ensure = function () {
              var fixed = false;
              Object.keys(S.sheets).forEach(function (sid) {
                var cur = document.getElementById(sid);
                if (cur && cur.isConnected) {
                  if (cur.textContent !== S.sheets[sid].css) { cur.textContent = S.sheets[sid].css; }
                  return;
                }
                var el = cur || document.createElement('style');
                el.id = sid;
                el.textContent = S.sheets[sid].css;
                if (S.attach(el, S.sheets[sid].first)) { S.report('re-attached', sid); fixed = true; }
              });
              if (S.doc !== document) {
                if (S.observer) { S.observer.disconnect(); }
                S.doc = document;
                S.observer = new MutationObserver(function () { S.ensure(); });
                S.observer.observe(document, { childList: true, subtree: true });
              }
              if (fixed) { clearTimeout(S.diagTimer); S.diagTimer = setTimeout(function () { S.diag('re-attach'); }, 500); }
            };
            // A replaced document fires no mutations on the old observer, so also poll briefly.
            var ticks = 0;
            var poll = setInterval(function () { S.ensure(); if (++ticks > 60) { clearInterval(poll); } }, 1000);
            document.addEventListener('DOMContentLoaded', function () { S.ensure(); });
            window.addEventListener('load', function () {
              S.ensure();
              setTimeout(function () { S.diag('load+3s'); }, 3000);
            });
          }
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            style.textContent = css;
            if (S.attach(style, first)) { S.report('injected', id); }
          } else {
            style.textContent = css;
            S.report('updated', id);
          }
          S.ensure();
          if (document.readyState === 'complete') {
            clearTimeout(S.diagTimer);
            S.diagTimer = setTimeout(function () { S.diag('reinject'); }, 3000);
          }
        })();
        """
    }
}
