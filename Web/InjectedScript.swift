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
            // Posts items as several lines, each under ~800 chars, so os_log never truncates.
            S.chunk = function (prefix, items) {
              var buf = [], len = 0, part = 1;
              var flush = function () { if (buf.length) { post(prefix + ' [' + (part++) + '] ' + buf.join(', ')); buf = []; len = 0; } };
              items.forEach(function (it) {
                if (it.length > 700) { it = it.slice(0, 700) + '...'; }
                if (len + it.length > 700) { flush(); }
                buf.push(it); len += it.length + 2;
              });
              flush();
              if (part === 1) { post(prefix + ' (none)'); }
            };
            // Structure of the first folder row and message row: tags, roles, classes, inline
            // styles and computed box metrics only. No text content or other attributes.
            S.struct = function () {
              try {
                var cls = function (el) { return (el.getAttribute('class') || '').trim().split(/ +/).filter(Boolean).join('.'); };
                var box = function (el) {
                  var c = getComputedStyle(el);
                  return 'h=' + c.height + ' minH=' + c.minHeight + ' lh=' + c.lineHeight + ' pad=' + c.paddingTop + '/' + c.paddingBottom +
                    ' mar=' + c.marginTop + '/' + c.marginBottom + ' pos=' + c.position + ' disp=' + c.display + ' fs=' + c.fontSize;
                };
                var desc = function (el) {
                  return el.tagName.toLowerCase() + (el.getAttribute('role') ? '[role=' + el.getAttribute('role') + ']' : '') +
                    ' class="' + cls(el) + '" style="' + (el.getAttribute('style') || '') + '"';
                };
                var dump = function (label, row) {
                  if (!row) { post('css: struct ' + label + ' not found'); return; }
                  var anc = [], p = row.parentElement;
                  for (var i = 0; i < 2 && p; i++, p = p.parentElement) {
                    var c = getComputedStyle(p);
                    anc.push((i ? 'grandparent ' : 'parent ') + desc(p) + ' pos=' + c.position + ' h=' + c.height + ' top=' + c.top);
                  }
                  S.chunk('css: struct ' + label + ' ancestors', anc);
                  var lines = [], count = 0;
                  var visit = function (el, depth) {
                    if (count >= 40 || depth > 8) { return; }
                    count++;
                    lines.push('d' + depth + ' ' + desc(el) + ' ' + box(el));
                    for (var j = 0; j < el.children.length; j++) { visit(el.children[j], depth + 1); }
                  };
                  visit(row, 0);
                  lines.forEach(function (l, n) { S.chunk('css: struct ' + label + ' #' + n, [l]); });
                };
                dump('treeitem', document.querySelector('[role=tree] [role=treeitem]'));
                dump('option', document.querySelector('[role=listbox] [role=option]'));
              } catch (e) { post('css: struct failed ' + e); }
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
                // Count every distinct selector used by the injected sheets (incl. @media/@supports).
                var seen = {};
                var walk = function (rules) {
                  for (var i = 0; i < rules.length; i++) {
                    var r = rules[i];
                    if (r.selectorText) {
                      r.selectorText.split(',').forEach(function (sel) {
                        sel = sel.trim();
                        if (!sel || seen.hasOwnProperty(sel)) return;
                        try { seen[sel] = document.querySelectorAll(sel).length; } catch (e) { seen[sel] = 'err'; }
                      });
                    } else if (r.cssRules) { try { walk(r.cssRules); } catch (e) {} }
                  }
                };
                Object.keys(S.sheets).forEach(function (sid) {
                  var el = document.getElementById(sid);
                  try { if (el && el.sheet) walk(el.sheet.cssRules); } catch (e) { out.counts['sheet:' + sid] = 'err:' + e.name; }
                });
                out.counts = Object.assign(out.counts, seen);
                out.zero = Object.keys(seen).filter(function (k) { return seen[k] === 0; });
                try { out.hasSupport = CSS.supports('selector(:has(a))'); } catch (e) { out.hasSupport = 'err'; }
                out.styleSheets = document.styleSheets.length;
                out.iframes = document.querySelectorAll('iframe').length;
                var counts = out.counts, zero = out.zero;
                delete out.counts; delete out.zero;
                post('css: diag ' + JSON.stringify(out));
                S.chunk('css: diag counts', Object.keys(counts).map(function (k) { return JSON.stringify(k) + ':' + JSON.stringify(counts[k]); }));
                S.chunk('css: diag zero', zero.map(function (k) { return JSON.stringify(k); }));
                if (reason === 'load+3s') { S.struct(); }
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
