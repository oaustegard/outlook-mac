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

    /// Creates or updates a <style> element with the given id. Safe to run more than once. With
    /// `first`, a new element goes before the page's other style elements, so later rules win.
    static func style(id: String, css: String, first: Bool = false) -> String {
        """
        (function () {
          var style = document.getElementById(\(literal(id)));
          if (!style) {
            style = document.createElement('style');
            style.id = \(literal(id));
            var parent = document.head || document.documentElement;
            if (\(first) && parent.firstChild) {
              parent.insertBefore(style, parent.firstChild);
            } else {
              parent.appendChild(style);
            }
          }
          style.textContent = \(literal(css));
        })();
        """
    }
}
