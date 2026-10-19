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
    /// watcher puts every stylesheet back.
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
            // Puts back any sheet missing from the current document. Re-observes when the
            // document object itself has been replaced.
            S.ensure = function () {
              Object.keys(S.sheets).forEach(function (sid) {
                var cur = document.getElementById(sid);
                if (cur && cur.isConnected) {
                  if (cur.textContent !== S.sheets[sid].css) { cur.textContent = S.sheets[sid].css; }
                  return;
                }
                var el = cur || document.createElement('style');
                el.id = sid;
                el.textContent = S.sheets[sid].css;
                if (S.attach(el, S.sheets[sid].first)) { S.report('re-attached', sid); }
              });
              if (S.doc !== document) {
                if (S.observer) { S.observer.disconnect(); }
                S.doc = document;
                S.observer = new MutationObserver(function () { S.ensure(); });
                S.observer.observe(document, { childList: true, subtree: true });
              }
            };
            // A replaced document fires no mutations on the old observer, so also poll briefly.
            var ticks = 0;
            var poll = setInterval(function () { S.ensure(); if (++ticks > 60) { clearInterval(poll); } }, 1000);
            document.addEventListener('DOMContentLoaded', function () { S.ensure(); });
            window.addEventListener('load', function () { S.ensure(); });
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
        })();
        """
    }
}
