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
    /// removes the element (OWA re-renders its shell), an observer puts it back.
    static func style(id: String, css: String, first: Bool = false) -> String {
        // The bridge's message handler is "omac" (CommandDispatcher.messageHandlerName).
        """
        (function () {
          var id = \(literal(id));
          var css = \(literal(css));
          function report(what) {
            try {
              var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.omac;
              if (h) { h.postMessage('css: ' + what + ' #' + id + ' (' + css.length + ' chars)'); }
            } catch (e) {}
          }
          function attach(style) {
            var parent = document.head || document.documentElement;
            if (!parent) { return false; }
            if (\(first) && parent.firstChild) {
              parent.insertBefore(style, parent.firstChild);
            } else {
              parent.appendChild(style);
            }
            return true;
          }
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            if (attach(style)) { report('injected'); }
          }
          style.textContent = css;
          // The latest text per id, so a re-attached element gets the current stylesheet.
          var watched = window.__omacStyles = window.__omacStyles || {};
          var isWatched = id in watched;
          watched[id] = css;
          if (isWatched) { return; }
          var observer = new MutationObserver(function () {
            var current = document.getElementById(id);
            if (current && current.isConnected) { return; }
            var replacement = current || document.createElement('style');
            replacement.id = id;
            replacement.textContent = watched[id];
            if (attach(replacement)) { report('re-attached'); }
          });
          observer.observe(document, { childList: true, subtree: true });
        })();
        """
    }
}
