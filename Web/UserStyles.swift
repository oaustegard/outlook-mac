import AppKit
import WebKit

/// The user's stylesheet, at ~/Library/Application Support/OutlookMac/user.css. It is applied at
/// document start, and the open page is updated whenever the file changes.
@MainActor
final class UserStyles {
    /// The app's own folder. Test builds under another bundle ID get a folder of their own, so they
    /// never read or write the session of the installed app.
    static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(folderName, isDirectory: true)

    private static var folderName: String {
        let identifier = Bundle.main.bundleIdentifier ?? ""
        return identifier == "com.oaustegard.outlook-mac" || identifier.isEmpty
            ? "OutlookMac"
            : "OutlookMac-\(identifier)"
    }
    static let fileURL = directory.appendingPathComponent("user.css")

    var onChange: (@MainActor () -> Void)?
    private var watcher: DispatchSourceFileSystemObject?

    /// Creates the folder and an empty user.css if they are missing.
    func ensureFile() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
            FileManager.default.createFile(atPath: Self.fileURL.path, contents: nil)
        }
    }

    var css: String {
        (try? String(contentsOf: Self.fileURL, encoding: .utf8)) ?? ""
    }

    /// Watches the folder rather than the file, so editors that replace the file on save are seen.
    func startWatching() {
        ensureFile()
        let fd = open(Self.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.onChange?() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }

    func openInEditor() {
        ensureFile()
        NSWorkspace.shared.open(Self.fileURL)
    }

    /// Re-applied on every navigation, so the stylesheet survives reloads.
    func documentStartScript() -> WKUserScript {
        WKUserScript(
            source: applyScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Applies the current stylesheet to the page that is open now.
    func applyScript() -> String {
        InjectedScript.style(id: "omac-user", css: css)
    }
}
